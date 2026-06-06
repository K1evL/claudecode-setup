# CcSwitchInstaller.psm1 — 安装 cc-switch（Claude Code 模型切换工具）
# 从 GitHub Releases 自动下载最新版并静默安装

function Install-CcSwitch {
    <#
    .SYNOPSIS
        安装 cc-switch 桌面应用 + claude-code CLI
    .DESCRIPTION
        - cc-switch 从 GitHub Releases 自动下载 MSI 安装
        - claude-code CLI 从 npm 安装
    #>
    [CmdletBinding()]
    param()

    Write-SetupLog "STEP" "正在安装 Claude Code + cc-switch..."

    # ------ 安装 Claude Code CLI ------
    $npmPath = Get-Command "npm" -ErrorAction SilentlyContinue
    if ($npmPath) {
        Install-ClaudeCodeCLI
    }
    else {
        Write-SetupLog "WARN" "npm 不可用，跳过 Claude Code CLI 安装"
    }

    # ------ 安装 cc-switch 桌面应用 ------
    Install-CCSwitchApp

    return $true
}

function Install-ClaudeCodeCLI {
    <#
    .SYNOPSIS
        安装 @anthropic-ai/claude-code CLI 工具
    #>
    $existing = Get-Command "claude-code" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-SetupLog "OK" "Claude Code CLI 已安装"
        return
    }

    Write-SetupLog "INFO" "正在安装 @anthropic-ai/claude-code..."

    # 镜像 registry
    $mirror = "https://registry.npmmirror.com"
    $output = npm install -g @anthropic-ai/claude-code --registry=$mirror 2>&1
    $output | ForEach-Object { Write-Host "       npm> $_" -ForegroundColor DarkGray }

    if ($LASTEXITCODE -ne 0) {
        # 官方 registry 重试
        Write-SetupLog "WARN" "镜像安装失败，尝试官方 registry..."
        $output = npm install -g @anthropic-ai/claude-code 2>&1
        $output | ForEach-Object { Write-Host "       npm> $_" -ForegroundColor DarkGray }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-SetupLog "OK" "Claude Code CLI 安装成功"
        # 验证 claude.cmd 是否确实生成
        $npmPrefix = Get-Config "NpmPrefix"
        $claudeCmd = Join-Path $npmPrefix "claude.cmd"
        $claudePs1 = Join-Path $npmPrefix "claude.ps1"
        if (Test-Path $claudeCmd) {
            Write-SetupLog "OK" "claude.cmd 已生成: $claudeCmd"
        }
        if (Test-Path $claudePs1) {
            Write-SetupLog "OK" "claude.ps1 已生成: $claudePs1"
        }

        # PowerShell 优先找 .ps1 而不是 .cmd，但执行策略可能限制脚本运行
        # 解决方案：禁用 .ps1，让 PowerShell 用 .cmd（批处理不受执行策略影响）
        if ((Test-Path $claudePs1) -and (Test-Path $claudeCmd)) {
            try {
                # 重命名 claude.ps1 → claude.ps1.disabled
                $disabledPs1 = Join-Path $npmPrefix "claude.ps1.disabled"
                Move-Item -Path $claudePs1 -Destination $disabledPs1 -Force
                Write-SetupLog "OK" "已禁用 claude.ps1（改用 claude.cmd 避免执行策略限制）"
            }
            catch {
                Write-SetupLog "WARN" "禁用 claude.ps1 失败: $($_.Exception.Message)"
            }
        }

        if (-not (Test-Path $claudeCmd) -and -not (Test-Path $claudePs1)) {
            Write-SetupLog "WARN" "npm 报告成功但未找到 claude 入口文件，尝试寻找其他 shim..."
            # npm 可能在 bin/ 或 node_modules/.bin/ 里放 shim
            $altPaths = @(
                (Join-Path $npmPrefix "bin\claude.cmd"),
                (Join-Path $npmPrefix "node_modules\.bin\claude.cmd"),
                (Join-Path $npmPrefix "node_modules\@anthropic-ai\claude-code\index.js")
            )
            foreach ($alt in $altPaths) {
                if (Test-Path $alt) {
                    Write-SetupLog "INFO" "在 $alt 找到 claude 入口"
                }
            }
        }
    }
    else {
        Write-SetupLog "WARN" "Claude Code CLI 安装失败，可稍后手动安装: npm install -g @anthropic-ai/claude-code"
    }
}

function Install-CCSwitchApp {
    <#
    .SYNOPSIS
        从 GitHub 自动下载最新 cc-switch 并安装
    .DESCRIPTION
        优先走 GitHub API 获取最新版，失败时降级到已知版本号直接构造下载链接。
        下载时国内加速：ghproxy.com / hscsec.cn 镜像
    #>
    Write-SetupLog "INFO" "正在获取 cc-switch 最新版本..."

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor `
            [System.Net.SecurityProtocolType]::Tls12

        # 1. 获取版本号和下载文件信息
        $version = $null
        $fileName = $null
        $directDownloadUrl = $null
        $repo = Get-Config "CcSwitchRepo"

        # 尝试 GitHub API（镜像优先，直连兜底）
        $apiUrls = @()
        $apiUrls += Get-Config "CcSwitchApiMirrors"
        $apiUrls += Get-Config "CcSwitchApiUrl"

        foreach ($apiUrl in $apiUrls) {
            try {
                Write-SetupLog "INFO" "查询版本: $apiUrl"
                $releaseInfo = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop -TimeoutSec 15
                $version = $releaseInfo.tag_name

                # 查找 Windows 安装包
                $windowsAsset = $releaseInfo.assets | Where-Object {
                    $_.name -like "*Windows*" -and $_.name -like "*.zip"
                } | Select-Object -First 1

                if ($windowsAsset) {
                    $fileName = $windowsAsset.name
                    $directDownloadUrl = $windowsAsset.browser_download_url
                    Write-SetupLog "INFO" "最新版本: $version"
                    Write-SetupLog "INFO" "下载文件: $fileName"
                    break
                }
            }
            catch {
                Write-SetupLog "WARN" "API $apiUrl 不可用: $($_.Exception.Message)"
                continue
            }
        }

        # API 全部失败时使用已知版本号构造下载链接
        if (-not $version) {
            $version = Get-Config "CcSwitchVersion"
            $fileName = "CC-Switch-$version-Windows-Portable.zip"
            $directDownloadUrl = "https://github.com/$repo/releases/download/$version/$fileName"
            Write-SetupLog "WARN" "GitHub API 不可用，使用已知版本: $version"
        }


        # 2. 检查本地是否已有 zip（exe 内嵌或先前下载）
        $tempDir = Get-Config "TempDir"
        $localZip = Join-Path $tempDir $fileName
        $localZipAlt = Join-Path $tempDir "cc-switch-portable.zip"   # exe 内嵌时的文件名
        $downloadPath = $localZip
        $needDownload = $true

        foreach ($zp in @($localZip, $localZipAlt)) {
            if (Test-Path $zp) {
                $localSize = (Get-Item $zp).Length
                if ($localSize -gt 1MB) {
                    $downloadPath = $zp
                    Write-SetupLog "OK" "本地已有 cc-switch zip ($([math]::Round($localSize/1MB,1)) MB)，跳过下载"
                    $needDownload = $false
                    break
                }
            }
        }

        if ($needDownload) {
            # 构造下载 URL 列表（直连 + 国内镜像）
            $primaryUrl = $directDownloadUrl
            $mirrorUrls = (Get-Config "CcSwitchDownloadMirrors") | ForEach-Object {
                $_ -replace "{url}", $primaryUrl
            }

            if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

            Write-SetupLog "INFO" "正在下载 cc-switch $version..."
            try {
                $null = Invoke-RobustDownload -Url $primaryUrl -FallbackUrls $mirrorUrls -OutputPath $downloadPath `
                    -TimeoutSec (Get-Config "DownloadTimeoutSec") -MaxRetries (Get-Config "DownloadMaxRetries")
            }
            catch {
                Write-SetupLog "WARN" "cc-switch 下载失败，跳过安装（可稍后手动下载）"
                $needDownload = $false
            }
        }

        # 4. 安装（便携版解压）
        $installDir = "C:\Program Files\CC-Switch"
        if (Test-Path $installDir) {
            Remove-Item "$installDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        Expand-Archive -Path $downloadPath -DestinationPath $installDir -Force
        Write-SetupLog "OK" "cc-switch 已解压到 $installDir"

        # 5. 创建桌面快捷方式
        $exePath = Join-Path $installDir "CC-Switch.exe"
        if (Test-Path $exePath) {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut("$env:USERPROFILE\Desktop\CC-Switch.lnk")
                $shortcut.TargetPath = $exePath
                $shortcut.Save()
                Write-SetupLog "OK" "已创建桌面快捷方式"
            }
            catch {
                Write-SetupLog "WARN" "快捷方式创建失败: $($_.Exception.Message)"
            }
        }
        else {
            Write-SetupLog "WARN" "解压后未找到 CC-Switch.exe"
        }

        # 6. 验证
        $ccExe = Get-Command "cc-switch" -ErrorAction SilentlyContinue
        if (-not $ccExe) { $ccExe = Get-Command "CC-Switch" -ErrorAction SilentlyContinue }
        if ($ccExe) {
            Write-SetupLog "OK" "cc-switch 已就绪: $($ccExe.Source)"
        }
        else {
            Write-SetupLog "INFO" "cc-switch 已下载到 $installDir"
        }
    }
    catch {
        Write-SetupLog "WARN" "cc-switch 自动安装失败: $($_.Exception.Message)"
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║  手动下载 cc-switch：                                    ║" -ForegroundColor Yellow
        Write-Host "║  https://github.com/farion1231/cc-switch/releases       ║" -ForegroundColor Yellow
        Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
    }
}

Export-ModuleMember -Function Install-CcSwitch
