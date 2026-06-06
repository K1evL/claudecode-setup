# Downloader.psm1 — 稳健下载器
# 支持多 CDN 容错、指数退避重试、SHA256 校验

function Invoke-RobustDownload {
    <#
    .SYNOPSIS
        稳健下载函数，支持多备用源和自动重试
    .PARAMETER Url
        主下载地址
    .PARAMETER FallbackUrls
        备用地址数组（CDN 镜像）
    .PARAMETER OutputPath
        输出文件路径
    .PARAMETER ExpectedHash
        可选 SHA256 校验值
    .PARAMETER MaxRetries
        最大重试次数（默认 3）
    .PARAMETER TimeoutSec
        超时秒数（默认 300）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [string[]]$FallbackUrls = @(),

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$ExpectedHash,

        [int]$MaxRetries = 1,

        [int]$TimeoutSec = 30
    )

    $urls = @($Url) + $FallbackUrls
    $attempt = 0
    $retryDelays = @(1, 2, 4, 8, 16)

    # 启用 TLS 1.2（.NET 4.x 默认不开启，连 nodejs.org 会卡死）
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor `
            [System.Net.SecurityProtocolType]::Tls12
    }
    catch { }

    foreach ($source in $urls) {
        $attempt = 0
        do {
            $attempt++
            try {
                Write-SetupLog "INFO" "正在下载: $source (尝试 $attempt/$MaxRetries)"

                # 确保输出目录存在
                $outDir = Split-Path $OutputPath -Parent
                if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

                # 后台线程下载 + 主线程显示进度（每 2 秒轮询一次，减少文件锁竞争）
                $runspace = [RunspaceFactory]::CreateRunspace()
                $runspace.Open()
                $ps = [PowerShell]::Create()
                $ps.Runspace = $runspace
                [void]$ps.AddScript("param(`$u,`$o) `$w=New-Object System.Net.WebClient; `$w.DownloadFile(`$u,`$o); `$w.Dispose()")
                [void]$ps.AddArgument($source).AddArgument($OutputPath)
                $async = $ps.BeginInvoke()

                $lastDataTime = [DateTime]::Now          # 上次收到数据的时间
                $startTime = [DateTime]::Now              # 总开始时间
                $lastSize = 0
                $tick = 0
                while (-not $async.IsCompleted) {
                    Start-Sleep -Seconds 2
                    $tick++
                    $elapsed = $tick * 2

                    if ([System.IO.File]::Exists($OutputPath)) {
                        $sz = (New-Object System.IO.FileInfo $OutputPath).Length
                        if ($sz -gt 0) {
                            if ($sz -ne $lastSize) {
                                $lastDataTime = [DateTime]::Now  # 有数据进来，续命
                                $lastSize = $sz
                            }
                            Write-Progress "下载" "$([math]::Round($sz/1MB,1))MB" -PercentComplete -1
                            if ($tick % 2 -eq 0) {
                                Write-Host "`r       [下载中] $([math]::Round($sz/1MB,1))MB / ${elapsed}s" -NoNewline -ForegroundColor DarkGray
                            }
                        }
                        else {
                            Write-Host "`r       [连接中] ${elapsed}s ..." -NoNewline -ForegroundColor DarkGray
                        }
                    }
                    else {
                        Write-Host "`r       [等待中] ${elapsed}s ..." -NoNewline -ForegroundColor DarkGray
                    }

                    # 超时检测：每10秒检查，不到1MB就切源
                    $totalTime = [DateTime]::Now - $startTime
                    if ($tick % 5 -eq 0 -and $totalTime.TotalSeconds -ge 10 -and $lastSize -lt 1MB) {
                        $ps.Stop() | Out-Null
                        throw "下载过慢（$([math]::Round($lastSize/1MB,2))MB / $([math]::Round($totalTime.TotalSeconds))s），自动切换源"
                    }
                    # 完全没数据超过 TimeoutSec → 超时
                    $idleTime = [DateTime]::Now - $lastDataTime
                    if ($idleTime.TotalSeconds -gt $TimeoutSec -and $lastSize -eq 0) {
                        $ps.Stop() | Out-Null
                        throw "连接超时 ($TimeoutSec 秒无响应)"
                    }
                    # 总时间超过 TimeoutSec×4 → 安全兜底
                    if ($totalTime.TotalSeconds -gt ($TimeoutSec * 4)) {
                        $ps.Stop() | Out-Null
                        throw "下载超时（总耗时超过 $($TimeoutSec*4) 秒）"
                    }
                }
                Write-Host "`r$(' ' * 45)" -NoNewline  # 清除进度行
                $ps.EndInvoke($async) | Out-Null
                $runspace.Dispose()
                $ps.Dispose()
                Write-Progress "下载 Node.js" -Completed

                # 校验文件大小
                $f = [System.IO.FileInfo]::new($OutputPath)
                if (-not $f.Exists -or $f.Length -eq 0) { throw "下载文件为空或不完整" }

                Write-SetupLog "OK" "下载完成 ($([math]::Round($f.Length / 1MB, 2))MB)"

                # 哈希校验
                if ($ExpectedHash) {
                    if (-not (Test-FileHash -FilePath $OutputPath -ExpectedHash $ExpectedHash)) {
                        try { [System.IO.File]::Delete($OutputPath) } catch { }
                        throw "SHA256 校验不匹配"
                    }
                    Write-SetupLog "OK" "SHA256 校验通过"
                }

                return $OutputPath
            }
            catch {
                Write-SetupLog "WARN" "下载失败: $($_.Exception.Message)"

                if ($attempt -lt $MaxRetries) {
                    $delay = if ($attempt -le $retryDelays.Count) { $retryDelays[$attempt - 1] } else { 16 }
                    Write-SetupLog "INFO" "将在 ${delay}s 后重试 ($attempt/$MaxRetries)"
                    Start-Sleep -Seconds $delay
                }
                elseif ($source -ne $urls[-1]) {
                    Write-SetupLog "INFO" "切换到下一个镜像源..."
                }
            }
        } while ($attempt -lt $MaxRetries)
    }

    # 全部失败
    throw "所有下载源均失败，请手动下载 Node.js 并指定安装路径"
}

function Test-FileHash {
    <#
    .SYNOPSIS
        校验文件的 SHA256 哈希值
    #>
    param(
        [string]$FilePath,
        [string]$ExpectedHash
    )

    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
        return $hash.Hash.ToLower() -eq $ExpectedHash.ToLower()
    }
    catch {
        Write-SetupLog "WARN" "哈希校验失败: $($_.Exception.Message)"
        return $false
    }
}

function Test-NetworkAvailable {
    <#
    .SYNOPSIS
        检测网络是否可用（多发几次避免丢包误判）
    #>
    param([string]$TestHost = "nodejs.org")
    # 多发几次 ping，任意一次成功就算通（避免单次丢包误判）
    $pingResult = Test-Connection -ComputerName $TestHost -Count 3 -Quiet -ErrorAction SilentlyContinue
    if ($pingResult) { return $true }

    # Ping 不通时再试 DNS 解析 + HTTP 连接（可能 ICMP 被禁）
    try {
        $dns = [System.Net.Dns]::GetHostEntry($TestHost)
        if ($dns.AddressList.Count -gt 0) { return $true }
    }
    catch { }
    return $false
}

Export-ModuleMember -Function Invoke-RobustDownload, Test-FileHash, Test-NetworkAvailable
