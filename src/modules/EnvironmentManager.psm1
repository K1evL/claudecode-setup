# EnvironmentManager.psm1 — 环境变量管理模块

function Update-SessionEnvironment {
    <#
    .SYNOPSIS
        刷新当前会话的环境变量，使注册表变更立即生效
    .DESCRIPTION
        从注册表重新读取 PATH，并更新 $env:PATH 和其他相关环境变量
    #>
    [CmdletBinding()]
    param()

    Write-SetupLog "STEP" "正在刷新环境变量..."

    $beforePath = $env:PATH

    # 1. 广播 WM_SETTINGCHANGE
    try {
        $broadcast = @'
using System;
using System.Runtime.InteropServices;
public class EnvBroadcaster {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    public static void Broadcast() {
        const uint HWND_BROADCAST = 0xffff;
        const uint WM_SETTINGCHANGE = 0x001a;
        const uint SMTO_ABORTIFHUNG = 0x0002;
        IntPtr result;
        SendMessageTimeout((IntPtr)HWND_BROADCAST, WM_SETTINGCHANGE,
            IntPtr.Zero, "Environment", SMTO_ABORTIFHUNG, 5000, out result);
    }
}
'@
        Add-Type -TypeDefinition $broadcast -ErrorAction Stop
        [EnvBroadcaster]::Broadcast()
        Write-SetupLog "INFO" "已广播环境变更通知 (WM_SETTINGCHANGE)"
    }
    catch {
        Write-SetupLog "WARN" "WM_SETTINGCHANGE 广播失败: $($_.Exception.Message)"
    }

    # 2. 从注册表重新读取 PATH
    try {
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")

        # 合并：系统 PATH + 用户 PATH（用户优先）
        $mergedPath = "$machinePath;$userPath"

        # 去重，保持顺序
        $entries = $mergedPath -split ';' | Where-Object { $_ -ne '' }
        $unique = @()
        $seen = @{}
        foreach ($e in $entries) {
            $key = $e.ToLower().TrimEnd('\')
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $unique += $e
            }
        }

        $env:PATH = $unique -join ';'

        # 3. 设置其他相关环境变量
        $npmPrefix = Get-Config "NpmPrefix"
        $env:NPM_CONFIG_PREFIX = $npmPrefix

        $nodePath = Get-NodePathFromRegistry
        if ($nodePath) {
            $env:NODE_PATH = Join-Path $nodePath "node_modules"
        }

        Write-SetupLog "OK" "环境变量已刷新"
    }
    catch {
        Write-SetupLog "WARN" "PATH 刷新失败: $($_.Exception.Message)"
    }

    # 4. 记录变更
    $afterPath = $env:PATH
    if ($beforePath -ne $afterPath) {
        Write-SetupLog "INFO" "PATH 已更新（长度: $($beforePath.Length) → $($afterPath.Length)）"
    }
}

function Get-NodePathFromRegistry {
    <#
    .SYNOPSIS
        从注册表读取 Node.js 安装路径
    #>
    $regPath = Get-Config "RegistryPath"
    $keyName = Get-Config "RegistryNodePath"
    try {
        if (Test-Path $regPath) {
            return (Get-ItemProperty -Path $regPath -Name $keyName -ErrorAction SilentlyContinue).$keyName
        }
    }
    catch {
        # 忽略
    }
    return $null
}

Export-ModuleMember -Function Update-SessionEnvironment, Get-NodePathFromRegistry
