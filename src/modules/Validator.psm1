# Validator.psm1 — 验证与报告模块

function New-InstallationReport {
    <#
    .SYNOPSIS
        安装完成后全面验证并输出格式化报告
    .PARAMETER NodeInfo
        Node.js 安装信息对象
    .PARAMETER NpmConfigured
        npm 配置是否成功
    .PARAMETER ClaudeCodeInstalled
        Claude Code CLI 是否安装成功
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$NodeInfo,
        [bool]$NpmConfigured = $false,
        [bool]$ClaudeCodeInstalled = $false
    )

    Write-SetupLog "STEP" "正在生成安装验证报告..."

    # 运行各项验证
    $checks = @()
    $checks += Invoke-Check "Node.js" {
        $v = & "node" --version 2>$null
        if (-not $v) { return [PSCustomObject]@{ Pass = $false; Value = "未检测到"; Detail = "" } }
        $ok = $v -match 'v(\d+)' -and [int]$Matches[1] -ge 18
        $detail = if ($NodeInfo) { "安装路径: $($NodeInfo.Path)" } else { "" }
        return [PSCustomObject]@{ Pass = $ok; Value = $v; Detail = $detail }
    }

    $checks += Invoke-Check "npm" {
        $v = & "npm" --version 2>$null
        if (-not $v) { return [PSCustomObject]@{ Pass = $false; Value = "未检测到"; Detail = "" } }
        $ok = [Version]$v -ge [Version]"9.0.0"
        return [PSCustomObject]@{ Pass = $ok; Value = "v$v"; Detail = "" }
    }

    $checks += Invoke-Check "npm prefix" {
        $prefix = npm config get prefix 2>$null
        $expected = Get-Config "NpmPrefix"
        $ok = $prefix -eq $expected
        return [PSCustomObject]@{ Pass = $ok; Value = $prefix; Detail = "预期: $expected" }
    }

    $checks += Invoke-Check "claude-code CLI" {
        $claude = Get-Command "claude" -ErrorAction SilentlyContinue
        if (-not $claude) { $claude = Get-Command "claude-code" -ErrorAction SilentlyContinue }
        if ($claude) {
            $v = & $claude.Source --version 2>$null
            return [PSCustomObject]@{ Pass = $true; Value = $v.Trim(); Detail = "已安装: $($claude.Source)" }
        }
        return [PSCustomObject]@{ Pass = $false; Value = "未安装"; Detail = "试试 claude --version" }
    }

    $checks += Invoke-Check "cc-switch" {
        $cc = Get-Command "cc-switch" -ErrorAction SilentlyContinue
        if (-not $cc) { $cc = Get-Command "CC-Switch" -ErrorAction SilentlyContinue }
        if (-not $cc) { $cc = Get-Command "CC Switch" -ErrorAction SilentlyContinue }
        if ($cc) {
            $v = & $cc.Source --version 2>$null
            return [PSCustomObject]@{ Pass = $true; Value = $v.Trim(); Detail = "已安装: $($cc.Source)" }
        }
        $paths = @(
            "${env:ProgramFiles}\CC-Switch\CC-Switch.exe"
            "${env:ProgramFiles(x86)}\CC-Switch\CC-Switch.exe"
            "${env:LOCALAPPDATA}\Programs\CC-Switch\CC-Switch.exe"
            "${env:LOCALAPPDATA}\Programs\CC Switch\CC-Switch.exe"
            "${env:LOCALAPPDATA}\Programs\CC Switch\CC Switch.exe"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) { return [PSCustomObject]@{ Pass = $true; Value = "桌面应用"; Detail = $p } }
        }
        return [PSCustomObject]@{ Pass = $false; Value = "未安装"; Detail = "可从 GitHub Releases 下载" }
    }

    $checks += Invoke-Check "PATH - Node.js" {
        $expectedPath = if ($NodeInfo -and $NodeInfo.Path) {
            # $NodeInfo.Path 可能是 "C:\nodejs\node.exe" 或 "C:\nodejs"
            if ($NodeInfo.Path -like "*.exe") { Split-Path $NodeInfo.Path -Parent } else { $NodeInfo.Path }
        } else { "C:\nodejs" }
        $pathEntries = $env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }
        $ok = $expectedPath.TrimEnd('\') -in $pathEntries
        $detail = if ($ok) { "已在 PATH 中" } else { "不在 PATH 中" }
        return [PSCustomObject]@{ Pass = $ok; Value = $expectedPath; Detail = $detail }
    }

    $checks += Invoke-Check "PATH - npm-global" {
        $npmPrefix = Get-Config "NpmPrefix"
        $npmBinDir = Join-Path $npmPrefix "bin"
        $pathEntries = $env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }
        $prefixOk = $npmPrefix.TrimEnd('\') -in $pathEntries
        $binOk = $npmBinDir.TrimEnd('\') -in $pathEntries
        $ok = $prefixOk -or $binOk
        $detail = if ($ok) { "已在 PATH 中 (prefix=$npmPrefix)" } else { "不在 PATH 中" }
        return [PSCustomObject]@{ Pass = $ok; Value = "$npmPrefix"; Detail = $detail }
    }

    # 输出报告
    Write-ReportToConsole $checks
    Write-ReportToLog $checks

    # 总体结论
    $allPass = ($checks | Where-Object { -not $_.Pass }).Count -eq 0
    if ($allPass) {
        Write-SetupLog "OK" "所有检查通过！ClaudeCode 环境已就绪"
    }
    else {
        $failCount = ($checks | Where-Object { -not $_.Pass }).Count
        Write-SetupLog "WARN" "$failCount 项检查未通过，请参考上述提示手动处理"
    }

    return [PSCustomObject]@{ AllPass = $allPass; Checks = $checks }
}

function Invoke-Check {
    <#
    .SYNOPSIS
        执行单项检查，统一处理异常
    #>
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )
    try {
        $result = & $ScriptBlock
        return [PSCustomObject]@{
            Name   = $Name
            Pass   = $result.Pass
            Value  = $result.Value
            Detail = $result.Detail
        }
    }
    catch {
        return [PSCustomObject]@{
            Name   = $Name
            Pass   = $false
            Value  = "检查失败"
            Detail = $_.Exception.Message
        }
    }
}

function Write-ReportToConsole {
    <#
    .SYNOPSIS
        在终端输出格式化的安装报告
    #>
    param($Checks)

    $installPath = if ($env:NODE_PATH) { $env:NODE_PATH -replace '\\node_modules', '' } else { "系统默认" }

    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║         ClaudeCode 环境配置报告                        ║" -ForegroundColor Green
    Write-Host "╠════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║ 执行时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                          ║" -ForegroundColor Green
    Write-Host "║ 操作系统：$((Get-CimInstance Win32_OperatingSystem).Caption)   ║" -ForegroundColor Green
    Write-Host "║ 管理员权限：是                                          ║" -ForegroundColor Green
    Write-Host "║ Node.js 安装路径：$installPath" -ForegroundColor Green
    Write-Host "╠════════════════════════════════════════════════════════╣" -ForegroundColor Green

    foreach ($c in $Checks) {
        $icon = if ($c.Pass) { '[✅]' } else { '[❌]' }
        $color = if ($c.Pass) { 'Green' } else { 'Red' }
        $line = "$icon $($c.Name)".PadRight(30)
        Write-Host "║ " -NoNewline -ForegroundColor Green
        Write-Host "$line $($c.Value)".PadRight(45) -NoNewline -ForegroundColor $color
        Write-Host "║" -ForegroundColor Green
    }

    Write-Host "╠════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║ 日志文件：$($Script:LogFilePath)" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green

    # 下一步提示
    Write-Host ""
    Write-Host "📋 下一步：" -ForegroundColor Cyan
    Write-Host "  1. Windows + R 输入 cmd，回车" -ForegroundColor White
    Write-Host "  2. 设置 API Key：claude set-key YOUR_KEY" -ForegroundColor White
    Write-Host "  3. 运行：claude" -ForegroundColor White
    Write-Host ""
}

function Write-ReportToLog {
    <#
    .SYNOPSIS
        将验证结果写入日志文件
    #>
    param($Checks)
    Write-SetupLog "STEP" "===== 安装验证报告 ====="
    foreach ($c in $Checks) {
        $status = if ($c.Pass) { "✅" } else { "❌" }
        Write-SetupLog "INFO" "  $status $($c.Name): $($c.Value) $($c.Detail)"
    }
}

Export-ModuleMember -Function New-InstallationReport
