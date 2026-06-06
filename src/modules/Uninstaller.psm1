# Uninstaller.psm1 — 卸载清理模块
# 支持一键完整卸载，兼容 MSI/zip/NVM/Scoop 四种安装方式

function Uninstall-Environment {
    <#
    .SYNOPSIS
        完整卸载所有已安装组件
    .PARAMETER All
        一键全部卸载，无需逐项确认
    #>
    [CmdletBinding()]
    param(
        [switch]$All
    )

    Write-SetupLog "STEP" "===== 开始卸载 ClaudeCode 环境 ====="
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║     ClaudeCode 环境卸载工具                      ║" -ForegroundColor Yellow
    Write-Host "║     将卸载：Node.js / npm 配置 / cc-switch      ║" -ForegroundColor Yellow
    Write-Host "║     以及清理相关 PATH 条目                       ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""

    # 检测已安装组件
    $components = Get-InstalledComponents

    $results = @()

    # 1. 卸载 cc-switch
    if ($components.HasCcSwitch -or $All) {
        $confirm = $All -or (Read-Host "卸载 cc-switch? [Y/N] (默认 Y)") -ne 'N'
        if ($confirm) {
            $results += Uninstall-CcSwitchComponent
        }
        else {
            $results += [PSCustomObject]@{ Component = 'cc-switch'; Status = 'Skipped' }
        }
    }

    # 2. 卸载 Node.js
    if ($components.HasNodeJS -or $All) {
        $confirm = $All -or (Read-Host "卸载 Node.js? [Y/N] (默认 Y)") -ne 'N'
        if ($confirm) {
            $results += Uninstall-NodeJSComponent
        }
        else {
            $results += [PSCustomObject]@{ Component = 'Node.js'; Status = 'Skipped' }
        }
    }

    # 3. 清理 npm 配置
    $confirm = $All -or (Read-Host "重置 npm 全局配置? [Y/N] (默认 Y)") -ne 'N'
    if ($confirm) {
        $results += Reset-NpmConfig
    }
    else {
        $results += [PSCustomObject]@{ Component = 'npm 配置'; Status = 'Skipped' }
    }

    # 4. 清理 PATH
    $confirm = $All -or (Read-Host "清理环境变量 PATH 中的相关条目? [Y/N] (默认 Y)") -ne 'N'
    if ($confirm) {
        $results += Clear-EnvironmentPath
    }
    else {
        $results += [PSCustomObject]@{ Component = 'PATH 清理'; Status = 'Skipped' }
    }

    # 5. 广播环境变更
    try {
        Update-SessionEnvironment
    }
    catch {
        Write-SetupLog "WARN" "环境刷新失败: $($_.Exception.Message)"
    }

    # 输出卸载报告
    Write-UninstallReport $results

    Write-SetupLog "STEP" "卸载完成"
    return $results
}

function Get-InstalledComponents {
    <#
    .SYNOPSIS
        检测当前已安装的组件清单
    #>
    $node = Get-Command "node" -ErrorAction SilentlyContinue
    $cc = Get-Command "cc-switch" -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        HasNodeJS   = ($node -ne $null)
        HasCcSwitch = ($cc -ne $null)
        NodePath    = if ($node) { $node.Source } else { $null }
        NodeVersion = if ($node) { & "node" --version 2>$null } else { $null }
    }
}

function Uninstall-CcSwitchComponent {
    <#
    .SYNOPSIS
        卸载 cc-switch 全局工具
    #>
    try {
        Write-SetupLog "INFO" "正在卸载 cc-switch..."
        npm uninstall -g (Get-Config "CcSwitchPackage") 2>&1 | Out-Null
        Write-SetupLog "OK" "cc-switch 已卸载"
        return [PSCustomObject]@{ Component = 'cc-switch'; Status = 'Uninstalled' }
    }
    catch {
        Write-SetupLog "WARN" "cc-switch 卸载失败（可能已被移除）"
        return [PSCustomObject]@{ Component = 'cc-switch'; Status = 'Failed'; Detail = $_.Exception.Message }
    }
}

function Uninstall-NodeJSComponent {
    <#
    .SYNOPSIS
        卸载 Node.js，支持四种安装方式
    #>
    $nodeInfo = Find-NodeInPath
    if (-not $nodeInfo.Found) { $nodeInfo = Find-NodeByPathScan }

    if (-not $nodeInfo.Found) {
        Write-SetupLog "WARN" "未检测到 Node.js 安装，跳过卸载"

        # 尝试从注册表读取安装路径
        $regPath = Get-NodePathFromRegistry
        if ($regPath -and (Test-Path $regPath)) {
            $confirm = Read-Host "注册表中记录有安装路径 $regPath，是否删除该目录? [Y/N]"
            if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-SetupLog "OK" "已删除目录: $regPath"
                return [PSCustomObject]@{ Component = 'Node.js'; Status = 'Uninstalled-from-registry'; Path = $regPath }
            }
        }

        return [PSCustomObject]@{ Component = 'Node.js'; Status = 'Not-found' }
    }

    Write-SetupLog "INFO" "正在卸载 Node.js $($nodeInfo.Version) (路径: $($nodeInfo.Path))..."

    try {
        $path = $nodeInfo.Path.ToLower()
        $nodeDir = Split-Path $nodeInfo.Path -Parent

        # 根据安装方式决定卸载策略
        if ($path -match "program files") {
            # MSI 安装
            $guid = Find-NodeMsiGuid
            if ($guid) {
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow
                Write-SetupLog "OK" "MSI 静默卸载完成"
            }
        }
        elseif ($path -match "nvm") {
            $version = $nodeInfo.Version.ToString()
            $nvmExe = Get-Command "nvm" -ErrorAction SilentlyContinue
            if ($nvmExe) {
                Start-Process -FilePath "nvm.exe" -ArgumentList "uninstall $version" -Wait -NoNewWindow
                Write-SetupLog "OK" "NVM 已卸载 Node.js $version（NVM 本身保留）"
            }
        }
        elseif ($path -match "scoop") {
            $scoopExe = Get-Command "scoop" -ErrorAction SilentlyContinue
            if ($scoopExe) {
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile scoop uninstall nodejs" -Wait -NoNewWindow
                Write-SetupLog "OK" "Scoop 已卸载 Node.js"
            }
        }
        else {
            # 免安装 zip
            if (Test-Path $nodeDir) {
                Remove-Item -Path $nodeDir -Recurse -Force -ErrorAction Stop
                Write-SetupLog "OK" "已删除目录: $nodeDir"
            }
        }

        # 清理 PATH
        Remove-NodeFromPath $nodeDir

        return [PSCustomObject]@{ Component = 'Node.js'; Status = 'Uninstalled'; Path = $nodeDir }
    }
    catch {
        Write-SetupLog "ERROR" "Node.js 卸载失败: $($_.Exception.Message)"
        return [PSCustomObject]@{ Component = 'Node.js'; Status = 'Failed'; Detail = $_.Exception.Message }
    }
}

function Reset-NpmConfig {
    <#
    .SYNOPSIS
        重置 npm 全局配置
    #>
    try {
        $npmPath = Get-Command "npm" -ErrorAction SilentlyContinue
        if (-not $npmPath) {
            return [PSCustomObject]@{ Component = 'npm 配置'; Status = 'Skipped'; Detail = 'npm 不可用' }
        }

        npm config delete prefix 2>$null
        $npmPrefixDir = Get-Config "NpmPrefix"
        if (Test-Path $npmPrefixDir) {
            $confirm = Read-Host "是否删除 npm 全局目录 $npmPrefixDir? [Y/N] (默认 N)"
            if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                Remove-Item -Path $npmPrefixDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-SetupLog "OK" "已删除 npm 全局目录"
            }
        }

        Write-SetupLog "OK" "npm 全局配置已重置"
        return [PSCustomObject]@{ Component = 'npm 配置'; Status = 'Reset' }
    }
    catch {
        return [PSCustomObject]@{ Component = 'npm 配置'; Status = 'Failed'; Detail = $_.Exception.Message }
    }
}

function Clear-EnvironmentPath {
    <#
    .SYNOPSIS
        清理 PATH 中的 Node.js 和 npm 相关条目
    #>
    $removed = @()

    # 系统 PATH
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($machinePath) {
        $entries = $machinePath -split ';'
        $filtered = $entries | Where-Object {
            $keep = $true
            if ($_ -match "nodejs" -or $_ -match "npm-global") {
                $keep = $false
                $removed += "Machine: $_"
            }
            $keep
        }
        [Environment]::SetEnvironmentVariable("PATH", ($filtered -join ';'), "Machine")
    }

    # 用户 PATH
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath) {
        $entries = $userPath -split ';'
        $filtered = $entries | Where-Object {
            $keep = $true
            if ($_ -match "npm-global" -or $_ -match "nodejs") {
                $keep = $false
                $removed += "User: $_"
            }
            $keep
        }
        [Environment]::SetEnvironmentVariable("PATH", ($filtered -join ';'), "User")
    }

    if ($removed.Count -gt 0) {
        Write-SetupLog "OK" "PATH 清理完成，共移除 $($removed.Count) 条记录"
        foreach ($r in $removed) { Write-SetupLog "INFO" "  已移除: $r" }
    }
    else {
        Write-SetupLog "INFO" "PATH 中未发现需要清理的条目"
    }

    return [PSCustomObject]@{ Component = 'PATH 清理'; Status = 'Cleaned'; RemovedCount = $removed.Count }
}

function Write-UninstallReport {
    <#
    .SYNOPSIS
        输出卸载报告
    #>
    param($Results)

    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         ClaudeCode 环境卸载报告                        ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ 执行时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                          ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

    foreach ($r in $Results) {
        $icon = switch ($r.Status) {
            'Uninstalled' { '[✅]' }
            'Uninstalled-from-registry' { '[✅]' }
            'Cleaned' { '[✅]' }
            'Reset' { '[✅]' }
            'Failed' { '[❌]' }
            'Skipped' { '[⏭️]' }
            'Not-found' { '[ℹ️]' }
            default { '[  ]' }
        }
        $statusText = "$icon $($r.Component)".PadRight(40)
        Write-Host "║ $statusText $($r.Status)" -ForegroundColor Cyan
    }

    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # 检查是否有残留
    $nodeCheck = Get-Command "node" -ErrorAction SilentlyContinue
    $npmCheck = Get-Command "npm" -ErrorAction SilentlyContinue
    $ccCheck = Get-Command "cc-switch" -ErrorAction SilentlyContinue

    if (-not $nodeCheck -and -not $npmCheck -and -not $ccCheck) {
        Write-SetupLog "OK" "所有组件已完全卸载"
        Write-Host "💡 建议重新启动计算机以确保所有环境变更生效" -ForegroundColor Cyan
    }
    else {
        Write-SetupLog "WARN" "部分组件可能仍有残留"
        if ($nodeCheck) { Write-SetupLog "INFO" "  残留: node ($($nodeCheck.Source))" }
        if ($npmCheck) { Write-SetupLog "INFO" "  残留: npm" }
        if ($ccCheck) { Write-SetupLog "INFO" "  残留: cc-switch" }
    }
}

Export-ModuleMember -Function Uninstall-Environment
