# NpmConfig.psm1 — npm 全局环境配置模块

function Initialize-NpmEnvironment {
    <#
    .SYNOPSIS
        配置 npm 全局环境，设置 prefix 和 registry
    #>
    [CmdletBinding()]
    param()

    Write-SetupLog "STEP" "正在配置 npm 全局环境..."

    $npmPrefix = Get-Config "NpmPrefix"

    # 1. 创建 npm 全局目录
    $npmBinDir = Join-Path $npmPrefix "bin"
    foreach ($dir in @($npmPrefix, $npmBinDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-SetupLog "INFO" "创建目录: $dir"
        }
    }

    # 2. 检查 npm 是否可用
    $npmPath = Get-Command "npm" -ErrorAction SilentlyContinue
    if (-not $npmPath) {
        Write-SetupLog "ERROR" "npm 不可用，请确保 Node.js 安装正确"
        return $false
    }

    # 3. 设置 npm prefix
    try {
        $currentPrefix = npm config get prefix
        if ($currentPrefix -ne $npmPrefix) {
            npm config set prefix "`"$npmPrefix`""
            Write-SetupLog "OK" "npm prefix 已设置为 $npmPrefix"
        }
        else {
            Write-SetupLog "OK" "npm prefix 已正确配置: $npmPrefix"
        }
    }
    catch {
        Write-SetupLog "WARN" "npm prefix 设置失败: $($_.Exception.Message)"
    }

    # 4. 设置 mirror registry 加速
    try {
        $registry = Get-Config "NpmRegistry"
        npm config set registry $registry
        Write-SetupLog "OK" "npm registry 已设置为 $registry"
    }
    catch {
        Write-SetupLog "WARN" "npm registry 设置失败，使用默认 registry"
    }

    # 5. 将 npm-global\bin 加入用户 PATH
    Add-NpmBinToPath $npmBinDir

    # 6. 验证
    $verifyPrefix = npm config get prefix
    if ($verifyPrefix -eq $npmPrefix) {
        Write-SetupLog "OK" "npm 环境配置验证通过"
        return $true
    }
    else {
        Write-SetupLog "WARN" "npm prefix 验证不一致: 预期 $npmPrefix, 实际 $verifyPrefix"
        return $false
    }
}

function Add-NpmBinToPath {
    <#
    .SYNOPSIS
        将 npm-global\bin 添加到用户 PATH
    #>
    param([string]$NpmBinDir)

    $npmPrefix = Get-Config "NpmPrefix"
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")

    # npm 在 Windows 上把 .cmd/.ps1 放 prefix 根目录，不是 bin/ 子目录
    $pathEntries = @($NpmBinDir, $npmPrefix) | Where-Object { $_ }
    $userPathEntries = $userPath -split ';' | ForEach-Object { $_.TrimEnd('\') }

    foreach ($entry in $pathEntries) {
        $entryKey = $entry.TrimEnd('\')
        if ($entryKey -notin $userPathEntries) {
            $userPath = if ($userPath) { "$userPath;$entry" } else { $entry }
            Write-SetupLog "INFO" "已将 $entry 添加到用户 PATH"
        }
    }

    if ($userPath -ne [Environment]::GetEnvironmentVariable("PATH", "User")) {
        [Environment]::SetEnvironmentVariable("PATH", $userPath, "User")

        # 广播环境变更
        try {
            [Environment]::SetEnvironmentVariable("NPM_CONFIG_PREFIX", $npmPrefix, "User")
        }
        catch {
            Write-SetupLog "WARN" "NPM_CONFIG_PREFIX 设置失败"
        }

        # 更新当前会话（同时加 bin/ 和 prefix 根目录）
        $env:PATH = "$env:PATH;$NpmBinDir;$npmPrefix"
        Write-SetupLog "OK" "当前会话 PATH 已更新"
    }
    else {
        Write-SetupLog "OK" "$($pathEntries -join ', ') 已在用户 PATH 中"
    }
}

Export-ModuleMember -Function Initialize-NpmEnvironment
