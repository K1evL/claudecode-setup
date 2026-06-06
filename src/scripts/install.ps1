#!/usr/bin/env pwsh
# install.ps1 — ClaudeCode 环境配置器核心安装脚本
# 被 Bootloader 调用，在管理员权限下执行

param(
    [switch]$Uninstall,
    [switch]$All,
    [switch]$Unattended     # 来自 exe 启动：静默模式，跳过 Read-Host 交互
)

# ---------- 加载基础设施 ----------
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 支持两种路径模式：
#   源码模式: install.ps1 在 src/scripts/，模块在 src/core/ 和 src/modules/
#   exe 模式: install.ps1 在 tempdir/，模块在 tempdir/core/ 和 tempdir/modules/
$coreCandidates = @(
    (Join-Path $ScriptRoot "..\core")      # 源码模式
    (Join-Path $ScriptRoot "core")         # exe 解压模式
)
$modulesCandidates = @(
    (Join-Path $ScriptRoot "..\modules")   # 源码模式
    (Join-Path $ScriptRoot "modules")      # exe 解压模式
)

$CorePath = $null
$ModulesPath = $null
foreach ($p in $coreCandidates) { if (Test-Path (Join-Path $p "Config.psm1")) { $CorePath = $p; break } }
foreach ($p in $modulesCandidates) { if (Test-Path (Join-Path $p "CcSwitchInstaller.psm1")) { $ModulesPath = $p; break } }

if (-not $CorePath -or -not $ModulesPath) {
    Write-Host "错误: 找不到模块文件 (core=$CorePath, modules=$ModulesPath)" -ForegroundColor Red
    exit 1
}

# 导入核心模块
Import-Module (Join-Path $CorePath "Config.psm1") -Force
Import-Module (Join-Path $CorePath "Logger.psm1") -Force
Import-Module (Join-Path $CorePath "Downloader.psm1") -Force
Import-Module (Join-Path $CorePath "Progress.psm1") -Force

# 导入功能模块
Import-Module (Join-Path $ModulesPath "SystemCheck.psm1") -Force
Import-Module (Join-Path $ModulesPath "NodeInstaller.psm1") -Force
Import-Module (Join-Path $ModulesPath "NpmConfig.psm1") -Force
Import-Module (Join-Path $ModulesPath "CcSwitchInstaller.psm1") -Force
Import-Module (Join-Path $ModulesPath "EnvironmentManager.psm1") -Force
Import-Module (Join-Path $ModulesPath "Uninstaller.psm1") -Force
Import-Module (Join-Path $ModulesPath "Validator.psm1") -Force

# ---------- 显示 Banner ----------
$BannerPath = Join-Path $ScriptRoot "..\assets\banner.txt"
if (Test-Path $BannerPath) {
    Get-Content $BannerPath | Write-Host -ForegroundColor Cyan
}
else {
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   ClaudeCode 一键环境配置器 v1.0.0" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
}

Write-Host ""

# ---------- 初始化日志 ----------
Start-SetupLog
Write-SetupLog "INFO" "===== ClaudeCode 环境配置器启动 ====="
Write-SetupLog "INFO" "PowerShell 版本: $($PSVersionTable.PSVersion)"
Write-SetupLog "INFO" "操作系统: $([Environment]::OSVersion)"

# ---------- 卸载模式 ----------
if ($Uninstall) {
    Write-SetupLog "STEP" "卸载模式已激活"
    Uninstall-Environment -All:$All
    $logPath = Stop-SetupLog
    Write-Host "日志文件: $logPath" -ForegroundColor DarkGray
    exit 0
}

# ---------- 安装模式 ----------
try {
    # 如果是 exe 静默模式，标记到配置供模块读取
    if ($Unattended) {
        Set-Config "Unattended" $true
        Write-Host "静默安装模式 (exe 启动，自动选择默认选项)" -ForegroundColor DarkGray
    }

    # Step 0: 设置 PowerShell 执行策略（让 claude 命令直接可用）
    $effectivePolicy = Get-ExecutionPolicy
    $needChange = $effectivePolicy -eq 'Restricted' -or $effectivePolicy -eq 'AllSigned' -or $effectivePolicy -eq 'Undefined'

    if ($needChange) {
        # 尝试设置 LocalMachine 范围（管理员权限下生效）
        $setArgs = @{ Scope = 'CurrentUser'; ExecutionPolicy = 'RemoteSigned'; Force = $true }
        $null = Set-ExecutionPolicy @setArgs -ErrorAction SilentlyContinue

        # 如果以管理员运行，同步设置 LocalMachine 范围
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
            .IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            $null = Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue
        }

        Write-SetupLog "OK" "PowerShell 执行策略已设为 RemoteSigned (原: $effectivePolicy)"
    }
    else {
        Write-SetupLog "INFO" "PowerShell 执行策略: $effectivePolicy"
    }

    # Step 1: 系统环境检测
    Show-StepProgress -StepName "系统环境检测" -TotalSteps 6 -CurrentStep 1
    $sysEnv = Test-SystemEnvironment
    if (-not $sysEnv.AllChecksPass) {
        throw "系统环境检测未通过，请修复后重试"
    }
    Show-StepProgress -StepName "系统环境检测" -Status Success

    # Step 2: Node.js 安装/检测
    Show-StepProgress -StepName "Node.js 安装" -TotalSteps 6 -CurrentStep 2 -Status Running
    $nodeInfo = Install-NodeJS
    Show-StepProgress -StepName "Node.js 安装" -Status Success

    # Step 3: npm 环境配置
    Show-StepProgress -StepName "npm 环境配置" -TotalSteps 6 -CurrentStep 3 -Status Running
    $npmOk = Initialize-NpmEnvironment
    Show-StepProgress -StepName "npm 环境配置" -Status $(if ($npmOk) { 'Success' } else { 'Warn' })

    # Step 4: 安装 cc-switch
    Show-StepProgress -StepName "cc-switch 安装" -TotalSteps 6 -CurrentStep 4 -Status Running
    $ccOk = Install-CcSwitch
    Show-StepProgress -StepName "cc-switch 安装" -Status $(if ($ccOk) { 'Success' } else { 'Warn' })

    # Step 5: 刷新环境变量
    Show-StepProgress -StepName "刷新环境变量" -TotalSteps 6 -CurrentStep 5 -Status Running
    Update-SessionEnvironment
    Show-StepProgress -StepName "刷新环境变量" -Status Success

    # Step 6: 生成验证报告
    Show-StepProgress -StepName "生成验证报告" -TotalSteps 6 -CurrentStep 6 -Status Running
    $report = New-InstallationReport -NodeInfo $nodeInfo -NpmConfigured $npmOk -ClaudeCodeInstalled $ccOk
    Show-StepProgress -StepName "生成验证报告" -Status Success

    # Step 7: 验证 claude 命令可用
    # 先确保 PowerShell 不会优先加载 claude.ps1（被执行策略限制）
    $npmPrefix = Get-Config "NpmPrefix"
    $claudePs1 = Join-Path $npmPrefix "claude.ps1"
    $claudeCmd = Join-Path $npmPrefix "claude.cmd"
    if ((Test-Path $claudePs1) -and (Test-Path $claudeCmd)) {
        try {
            $disabledPs1 = Join-Path $npmPrefix "claude.ps1.disabled"
            Move-Item -Path $claudePs1 -Destination $disabledPs1 -Force
            Write-SetupLog "OK" "已禁用 claude.ps1（改用 claude.cmd 避免执行策略限制）"
        }
        catch {
            Write-SetupLog "WARN" "禁用 claude.ps1 失败: $($_.Exception.Message)"
        }
    }

    $claude = Get-Command "claude" -ErrorAction SilentlyContinue
    if (-not $claude) {
        # 如果 PATH 刷新没生效，直接手动加到当前会话
        $pathEntries = $env:PATH -split ';'
        $npmRootKey = $npmPrefix.TrimEnd('\')
        if ($npmRootKey -notin $pathEntries) {
            $env:PATH = "$env:PATH;$npmPrefix"
            Write-SetupLog "INFO" "已将 $npmPrefix 添加到当前会话 PATH"
        }
        $claude = Get-Command "claude" -ErrorAction SilentlyContinue
    }

    if ($claude) {
        Write-SetupLog "OK" "环境就绪！运行 claude 即可启动 Claude Code"
    }
    else {
        Write-SetupLog "WARN" "claude 命令不可用"
        # 输出诊断信息
        $claudePaths = @(
            (Join-Path (Get-Config "NpmPrefix") "claude.cmd"),
            (Join-Path (Get-Config "NpmPrefix") "claude.ps1"),
            (Join-Path (Get-Config "NpmPrefix") "bin\claude.cmd")
        )
        foreach ($cp in $claudePaths) {
            if (Test-Path $cp) {
                Write-SetupLog "INFO" "文件存在: $cp"
            }
        }
    }

    # 完成
    Write-SetupLog "OK" "===== ClaudeCode 环境配置完成 ====="
    Write-Host ""
    Write-Host "   Windows + R 输入 cmd，然后运行：" -ForegroundColor Cyan
    Write-Host "   claude" -ForegroundColor White
    Write-Host "   首次使用先设置 API Key：claude set-key YOUR_KEY" -ForegroundColor DarkGray
}
catch {
    Write-SetupLog "ERROR" "安装过程中断: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "❌ 安装失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   详细信息请查看日志文件" -ForegroundColor DarkGray
    exit 1
}
finally {
    $logPath = Stop-SetupLog
    Write-Host ""
    Write-Host "日志文件: $logPath" -ForegroundColor DarkGray
}
