# NodeInstaller.psm1 — Node.js 安装与检测模块
# 六级递进策略：系统检测 → 路径扫描 → 版本协商+卸载旧版 → 离线引导 → 自动下载安装

function Install-NodeJS {
    <#
    .SYNOPSIS
        六级递进策略确保 Node.js >= 18.x 可用
    .DESCRIPTION
        Level 1: 系统检测 → Level 2: 路径扫描 → Level 3: 版本协商+卸载旧版
        → Level 4: 离线引导 → Level 5: 自动下载安装 → Level 6: 卸载旧版后安装新版
    #>
    [CmdletBinding()]
    param()

    Write-SetupLog "STEP" "正在检测 Node.js 环境..."

    # ------ Level 1: 系统检测 ------
    Write-SetupLog "INFO" "[Level 1/6] 检查系统 PATH 中的 Node.js..."
    $nodeInfo = Find-NodeInPath

    if ($nodeInfo.Found -and $nodeInfo.Version -ge (Get-Config "NodeMinVersion")) {
        Write-SetupLog "OK" "系统已安装 Node.js $($nodeInfo.Version)，路径: $($nodeInfo.Path)"
        return [PSCustomObject]@{ Installed = $true; Version = $nodeInfo.Version; Path = $nodeInfo.Path; Method = 'existing' }
    }

    # ------ Level 2: 路径扫描 ------
    Write-SetupLog "INFO" "[Level 2/6] 扫描已知安装路径..."
    $nodeInfo = Find-NodeByPathScan

    if ($nodeInfo.Found) {
        if ($nodeInfo.Version -ge (Get-Config "NodeMinVersion")) {
            Write-SetupLog "OK" "在 $($nodeInfo.Path) 发现 Node.js $($nodeInfo.Version)，正在加入 PATH..."
            Add-NodeToPath $nodeInfo.Path
            return [PSCustomObject]@{ Installed = $true; Version = $nodeInfo.Version; Path = $nodeInfo.Path; Method = 'path-scanned' }
        }
        else {
            # Level 3: 版本协商 + 卸载旧版
            return Invoke-VersionNegotiation -OldNode $nodeInfo
        }
    }

    # ------ Level 4: 离线引导 ------
    if (-not (Test-NetworkAvailable)) {
        return Invoke-OfflineGuide
    }

    # ------ Level 5: 自动下载安装 ------
    return Invoke-NodeDownloadAndInstall
}

function Find-NodeInPath {
    <#
    .SYNOPSIS
        Level 1: 在系统 PATH 中查找 Node.js
    #>
    $nodePath = Get-Command "node" -ErrorAction SilentlyContinue
    if (-not $nodePath) { return [PSCustomObject]@{ Found = $false } }

    $versionStr = & "node" --version 2>$null
    if (-not $versionStr) { return [PSCustomObject]@{ Found = $false } }

    $version = Parse-NodeVersion $versionStr
    return [PSCustomObject]@{ Found = $true; Version = $version; Path = $nodePath.Source }
}

function Find-NodeByPathScan {
    <#
    .SYNOPSIS
        Level 2: 扫描已知安装路径
    #>
    $searchPaths = @(
        "C:\Program Files\nodejs\node.exe",
        "C:\nodejs\node.exe",
        "$env:LOCALAPPDATA\nodejs\node.exe",
        "$env:APPDATA\nvm\*\node.exe",
        "$env:USERPROFILE\scoop\apps\nodejs\*\node.exe"
    )

    # 展开通配符路径
    $expandedPaths = @()
    foreach ($p in $searchPaths) {
        $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
        if ($resolved) { $expandedPaths += $resolved.Path }
    }

    foreach ($p in $expandedPaths) {
        if (Test-Path $p) {
            $versionStr = & $p --version 2>$null
            if ($versionStr) {
                $version = Parse-NodeVersion $versionStr
                Write-SetupLog "INFO" "在 $p 发现 Node.js v$version"
                return [PSCustomObject]@{ Found = $true; Version = $version; Path = $p }
            }
        }
    }

    return [PSCustomObject]@{ Found = $false }
}

function Invoke-VersionNegotiation {
    <#
    .SYNOPSIS
        Level 3: 版本协商 — 发现旧版时询问是否升级
    #>
    param($OldNode)

    Write-SetupLog "WARN" "当前 Node.js 版本 v$($OldNode.Version) 低于要求 (>= $(Get-Config "NodeMinVersion"))"

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  检测到旧版 Node.js v$($OldNode.Version)                  ║" -ForegroundColor Yellow
    Write-Host "║  推荐升级到 Node.js $(Get-Config "NodeLTSVersion") LTS                ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""

    $choice = if (Get-Config "Unattended") { 'Y' } else { Read-Host "是否升级? [Y] 升级到最新 LTS  [N] 跳过（使用现有版本）" }
    if ($choice -eq 'Y' -or $choice -eq 'y') {
        # 卸载旧版
        Write-SetupLog "STEP" "正在卸载旧版 Node.js v$($OldNode.Version)..."
        Invoke-NodeUninstall -NodeInfo $OldNode

        # 询问安装路径
        $installPath = Select-NodeInstallPath

        # 下载并安装新版
        return Invoke-NodeDownloadAndInstall -InstallPath $installPath
    }
    else {
        Write-SetupLog "WARN" "用户选择跳过，保留当前 Node.js v$($OldNode.Version)"
        return [PSCustomObject]@{ Installed = $true; Version = $OldNode.Version; Path = $OldNode.Path; Method = 'existing-old' }
    }
}

function Invoke-OfflineGuide {
    <#
    .SYNOPSIS
        Level 4: 离线引导 — 网络不可用时提示手动下载
    #>
    # 静默模式（exe）下无法处理离线场景，直接报错
    if (Get-Config "Unattended") {
        throw "网络不可用，静默安装无法继续，请检查网络连接后重试"
    }

    Write-SetupLog "WARN" "网络不可用，进入离线引导模式"
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  网络连接不可用，请手动操作：                            ║" -ForegroundColor Yellow
    Write-Host "║  1. 访问 https://nodejs.org 下载 LTS 版本               ║" -ForegroundColor Yellow
    Write-Host "║  2. 解压到 C:\nodejs 或 D:\nodejs                       ║" -ForegroundColor Yellow
    Write-Host "║  3. 将路径添加到系统 PATH                                ║" -ForegroundColor Yellow
    Write-Host "║  4. 完成后输入 Y 继续安装                               ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""

    do {
        $input = Read-Host "完成后输入 Y 继续，或输入 Q 退出安装"
        if ($input -eq 'Q' -or $input -eq 'q') {
            throw "用户选择退出安装"
        }
    } while ($input -ne 'Y' -and $input -ne 'y')

    # 重新检测
    $nodeInfo = Find-NodeInPath
    if (-not $nodeInfo.Found) { $nodeInfo = Find-NodeByPathScan }

    if ($nodeInfo.Found -and $nodeInfo.Version -ge (Get-Config "NodeMinVersion")) {
        Write-SetupLog "OK" "Node.js $($nodeInfo.Version) 已就绪"
        return [PSCustomObject]@{ Installed = $true; Version = $nodeInfo.Version; Path = $nodeInfo.Path; Method = 'manual' }
    }

    throw "未检测到有效的 Node.js 安装"
}

function Invoke-NodeDownloadAndInstall {
    <#
    .SYNOPSIS
        Level 5: 自动下载并安装 Node.js
    .PARAMETER InstallPath
        安装路径，默认 C:\nodejs
    #>
    param([string]$InstallPath = "")

    if (-not $InstallPath) {
        $InstallPath = Select-NodeInstallPath
    }

    $version = Get-Config "NodeLTSVersion"
    $downloadUrl = (Get-Config "NodePrimaryUrl") -replace "{version}", $version
    $mirrors = (Get-Config "NodeMirrors") | ForEach-Object { $_ -replace "{version}", $version }

    $tempDir = Join-Path (Get-Config "TempDir") "downloads"
    $zipPath = Join-Path $tempDir "node-v$version-win-x64.zip"

    Write-SetupLog "INFO" "正在下载 Node.js v$version → $zipPath"

    # 创建安装目录
    if (-not (Test-Path $InstallPath)) { New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null }

    try {
        # 尝试获取 SHA256
        $expectedHash = Get-NodeHash -Version $version

        # 下载
        Invoke-RobustDownload -Url $downloadUrl -FallbackUrls $mirrors -OutputPath $zipPath -ExpectedHash $expectedHash

        # 解压
        Write-SetupLog "INFO" "正在解压到 $InstallPath..."
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
        $extractedDir = Join-Path $tempDir "node-v$version-win-x64"
        if (Test-Path $extractedDir) {
            Copy-Item -Path "$extractedDir\*" -Destination $InstallPath -Recurse -Force
        }

        # 添加到系统 PATH
        Add-NodeToPath $InstallPath

        # 记录安装路径到注册表
        Save-NodeInstallPath $InstallPath

        # 验证
        $nodeExe = Join-Path $InstallPath "node.exe"
        if (Test-Path $nodeExe) {
            $verStr = & $nodeExe --version
            Write-SetupLog "OK" "Node.js $verStr 安装成功 (路径: $InstallPath)"
            return [PSCustomObject]@{ Installed = $true; Version = $verStr; Path = $InstallPath; Method = 'downloaded' }
        }
        else {
            throw "安装后未找到 node.exe"
        }
    }
    catch {
        Write-SetupLog "ERROR" "Node.js 安装失败: $($_.Exception.Message)"

        # 哈希校验失败的兜底
        if ($_.Exception.Message -match "SHA256" -or $_.Exception.Message -match "校验") {
            Write-SetupLog "WARN" "无法校验文件完整性（nodejs.org 可能不可用）"
            $continue = Read-Host "是否忽略校验继续安装? [Y/N]"
            if ($continue -eq 'Y' -or $continue -eq 'y') {
                Write-SetupLog "INFO" "用户选择忽略校验，继续安装"
                # 直接解压已下载的文件
                if (Test-Path $zipPath) {
                    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
                    Copy-Item -Path "$tempDir\node-v$version-win-x64\*" -Destination $InstallPath -Recurse -Force
                    Add-NodeToPath $InstallPath
                    Save-NodeInstallPath $InstallPath
                    return [PSCustomObject]@{ Installed = $true; Version = "v$version"; Path = $InstallPath; Method = 'downloaded-unverified' }
                }
            }
            else {
                throw "用户取消安装"
            }
        }
        else {
            throw $_
        }
    }
}

function Select-NodeInstallPath {
    <#
    .SYNOPSIS
        选择 Node.js 安装路径（交互或静默）
    #>
    $defaultPath = Get-Config "NodeDefaultInstall"

    # 静默模式直接用默认路径
    if (Get-Config "Unattended") {
        Write-SetupLog "INFO" "静默安装，使用默认路径: $defaultPath"
        return $defaultPath
    }

    $hasDDrive = (Get-PSDrive -Name D -ErrorAction SilentlyContinue) -ne $null

    if ($hasDDrive) {
        Write-Host "检测到 D 盘，推荐安装到 D:\nodejs（便于重装系统后保留）" -ForegroundColor Cyan
        do {
            $choice = Read-Host "安装路径? [C] C:\nodejs  [D] D:\nodejs  (默认 C)"
            $valid = $choice -eq '' -or $choice -eq 'C' -or $choice -eq 'c' -or $choice -eq 'D' -or $choice -eq 'd'
            if (-not $valid) { Write-Host "请输入 C 或 D，或直接回车使用默认值" -ForegroundColor Yellow }
        } while (-not $valid)

        if ($choice -eq 'D' -or $choice -eq 'd') {
            $path = "D:\nodejs"
        }
        else {
            $path = $defaultPath
        }
    }
    else {
        $path = Read-Host "请输入 Node.js 安装路径 (默认: $defaultPath)"
        if ([string]::IsNullOrWhiteSpace($path)) { $path = $defaultPath }
    }

    Write-SetupLog "INFO" "Node.js 安装路径: $path"
    return $path
}

function Add-NodeToPath {
    <#
    .SYNOPSIS
        将 Node.js 路径添加到系统 PATH 并更新当前会话
    #>
    param([string]$NodePath)

    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($machinePath -notlike "*$NodePath*") {
        $newPath = "$machinePath;$NodePath"
        if ($newPath.Length -gt 2048) {
            Write-SetupLog "WARN" "PATH 长度超过 2048 字符，建议手动添加"
        }
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
        Write-SetupLog "OK" "已将 $NodePath 添加到系统 PATH"
    }
    # 同时更新当前会话 PATH，后续步骤能立即找到 node/npm
    if ($env:PATH -notlike "*$NodePath*") {
        $env:PATH = "$env:PATH;$NodePath"
    }
}

function Save-NodeInstallPath {
    <#
    .SYNOPSIS
        将安装路径记录到注册表
    #>
    param([string]$InstallPath)
    try {
        $regPath = Get-Config "RegistryPath"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name (Get-Config "RegistryNodePath") -Value $InstallPath
        Write-SetupLog "OK" "安装路径已记录到注册表: $regPath"
    }
    catch {
        Write-SetupLog "WARN" "注册表写入失败: $($_.Exception.Message)"
    }
}

function Get-NodeHash {
    <#
    .SYNOPSIS
        获取 Node.js 安装包的 SHA256 哈希值（优先走国内镜像）
    #>
    param([string]$Version)

    try {
        # 启用 TLS 1.2
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor `
            [System.Net.SecurityProtocolType]::Tls12

        # 优先从国内镜像获取哈希文件（更快）
        $hashUrls = @(
            "https://npmmirror.com/mirrors/node/v$version/SHASUMS256.txt"
            "https://mirrors.huaweicloud.com/nodejs/v$version/SHASUMS256.txt"
            "https://mirrors.tencent.com/nodejs-release/v$version/SHASUMS256.txt"
            "https://nodejs.org/dist/v$version/SHASUMS256.txt"
        )
        $content = $null
        foreach ($url in $hashUrls) {
            try {
                $wc = New-Object System.Net.WebClient
                try { $content = $wc.DownloadString($url); break }
                finally { $wc.Dispose() }
            }
            catch { continue }
        }
        if (-not $content) { return $null }
        $lines = $content -split "`n"
        $zipFile = "node-v$version-win-x64.zip"
        foreach ($line in $lines) {
            if ($line -match $zipFile) {
                return ($line -split '\s+')[0]
            }
        }
    }
    catch {
        Write-SetupLog "WARN" "无法获取哈希值（nodejs.org 不可用），将跳过校验"
    }
    return $null
}

function Parse-NodeVersion {
    <#
    .SYNOPSIS
        解析 node --version 输出，返回 Version 对象
    #>
    param([string]$VersionStr)
    $clean = $VersionStr.Trim().TrimStart('v')
    try { return [Version]$clean } catch { return [Version]"0.0.0" }
}

function Invoke-NodeUninstall {
    <#
    .SYNOPSIS
        Level 6: 卸载旧版 Node.js
    #>
    param($NodeInfo)

    $path = $NodeInfo.Path.ToLower()

    # MSI 安装 — 从注册表获取产品码
    if ($path -match "program files") {
        $guid = Find-NodeMsiGuid
        if ($guid) {
            Write-SetupLog "INFO" "检测到 MSI 安装，产品码: $guid"
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait
            Write-SetupLog "OK" "MSI 卸载完成"
        }
    }
    # NVM 管理
    elseif ($path -match "nvm") {
        $version = $NodeInfo.Version.ToString()
        $nvmPath = Get-Command "nvm" -ErrorAction SilentlyContinue
        if ($nvmPath) {
            Start-Process -FilePath "nvm.exe" -ArgumentList "uninstall $version" -Wait
            Write-SetupLog "OK" "NVM 卸载 Node.js $version 完成（NVM 本身已保留）"
        }
    }
    # Scoop 管理
    elseif ($path -match "scoop") {
        $scoopPath = Get-Command "scoop" -ErrorAction SilentlyContinue
        if ($scoopPath) {
            Start-Process -FilePath "powershell.exe" -ArgumentList "scoop uninstall nodejs" -Wait
            Write-SetupLog "OK" "Scoop 卸载 Node.js 完成"
        }
    }
    # 免安装 zip 包
    else {
        $nodeDir = Split-Path $path -Parent
        if (Test-Path $nodeDir) {
            Remove-Item -Path $nodeDir -Recurse -Force
            Write-SetupLog "OK" "已删除目录: $nodeDir"
        }
    }

    # 清理 PATH 中的旧条目
    Remove-NodeFromPath -NodePath (Split-Path $NodeInfo.Path -Parent)
    Write-SetupLog "OK" "PATH 中的旧 Node.js 条目已清理"
}

function Find-NodeMsiGuid {
    <#
    .SYNOPSIS
        在注册表中查找 Node.js MSI 安装的产品码
    #>
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($base in $regPaths) {
        $items = Get-ItemProperty $base -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if ($item.DisplayName -match "Node.js") {
                return $item.PSChildName
            }
        }
    }
    return $null
}

function Remove-NodeFromPath {
    <#
    .SYNOPSIS
        从系统 PATH 中移除 Node.js 相关条目
    #>
    param([string]$NodePath)

    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $entries = $machinePath -split ';'
    $filtered = $entries | Where-Object { $_ -notlike "*nodejs*" -and $_ -notlike "*npm*" -and $_ -notlike "*$NodePath*" }
    $newPath = $filtered -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
}

Export-ModuleMember -Function Install-NodeJS, Invoke-NodeUninstall, Find-NodeInPath, Find-NodeByPathScan, Remove-NodeFromPath, Find-NodeMsiGuid, Parse-NodeVersion, Get-NodeHash
