# SystemCheck.psm1 — 系统环境检测模块
# 前置条件检查，确保满足安装所需的环境要求

function Test-SystemEnvironment {
    <#
    .SYNOPSIS
        全面检测系统环境，返回检测结果对象
    .DESCRIPTION
        检测项包括：操作系统版本、架构、管理员权限、PowerShell 版本、网络连通性、磁盘空间
    #>
    [CmdletBinding()]
    param()

    Write-SetupLog "STEP" "正在检测系统环境..."

    $result = [PSCustomObject]@{
        OSVersion    = $null
        Arch         = $null
        IsAdmin      = $false
        PSVersion    = $null
        IsOnline     = $false
        DiskFreeMB   = 0
        HasDDrive    = $false
        AllChecksPass = $true
    }

    # 1. 操作系统版本
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $result.OSVersion = "$($os.Caption) ($($os.OSArchitecture))"
        Write-SetupLog "OK" "操作系统: $($result.OSVersion)"

        $isWin10OrLater = $os.Version -ge 10
        if (-not $isWin10OrLater) {
            Write-SetupLog "WARN" "Windows 10 以下版本可能不受完全支持"
        }
    }
    catch {
        Write-SetupLog "WARN" "无法获取操作系统版本: $($_.Exception.Message)"
    }

    # 2. 系统架构
    $result.Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    Write-SetupLog "OK" "系统架构: $($result.Arch)"

    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-SetupLog "ERROR" "不支持 x86 架构（Node.js 官方已停止提供 32 位版本）"
        $result.AllChecksPass = $false
    }

    # 3. 管理员权限
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $result.IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $result.IsAdmin) {
        Write-SetupLog "ERROR" "需要管理员权限！请右键 → 以管理员身份运行"
        $result.AllChecksPass = $false
    }
    else {
        Write-SetupLog "OK" "管理员权限: 是"
    }

    # 4. PowerShell 版本
    $result.PSVersion = $PSVersionTable.PSVersion
    Write-SetupLog "OK" "PowerShell 版本: $($result.PSVersion)"

    if ($result.PSVersion -lt [Version]"5.1") {
        Write-SetupLog "ERROR" "PowerShell 版本低于 5.1，请升级 PowerShell"
        $result.AllChecksPass = $false
    }

    # 5. 网络连通性（多发几次避免丢包误判）
    try {
        $pingOk = Test-Connection -ComputerName "nodejs.org" -Count 3 -Quiet -ErrorAction SilentlyContinue
        $dnsOk = $false
        if (-not $pingOk) {
            try { $dnsOk = ([System.Net.Dns]::GetHostEntry("nodejs.org").AddressList.Count -gt 0) } catch { }
        }
        $result.IsOnline = $pingOk -or $dnsOk
        if ($result.IsOnline) {
            Write-SetupLog "OK" "网络连通: 正常"
        }
        else {
            Write-SetupLog "WARN" "网络连通: 无法访问 nodejs.org，将使用离线模式"
        }
    }
    catch {
        Write-SetupLog "WARN" "网络连通: 检测失败，将使用离线模式"
    }

    # 6. 磁盘空间
    try {
        $drive = Get-PSDrive -Name C -ErrorAction Stop
        $result.DiskFreeMB = [math]::Round($drive.Free / 1MB)
        Write-SetupLog "OK" "C 盘可用空间: $($result.DiskFreeMB) MB"

        if ($result.DiskFreeMB -lt (Get-Config "MinDiskSpaceMB")) {
            Write-SetupLog "WARN" "C 盘可用空间不足 $(Get-Config "MinDiskSpaceMB")MB，建议清理磁盘"
        }
    }
    catch {
        Write-SetupLog "WARN" "无法检测磁盘空间: $($_.Exception.Message)"
    }

    # 7. D 盘检测
    try {
        $dDrive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
        $result.HasDDrive = ($dDrive -ne $null)
        if ($result.HasDDrive) {
            Write-SetupLog "OK" "D 盘已检测到，可用空间: $([math]::Round($dDrive.Free / 1GB, 1)) GB"
        }
    }
    catch {
        $result.HasDDrive = $false
    }

    if ($result.AllChecksPass) {
        Write-SetupLog "OK" "系统环境检测通过 ✓"
    }
    else {
        Write-SetupLog "ERROR" "系统环境检测未通过，请修复上述问题后重试"
    }

    return $result
}

Export-ModuleMember -Function Test-SystemEnvironment
