# Integration.Tests.ps1 — 集成测试
# 验证模块间协作和完整安装流程

BeforeAll {
    $ScriptRoot = $PSScriptRoot
    $CorePath = Join-Path $ScriptRoot "..\core"
    $ModulesPath = Join-Path $ScriptRoot "..\modules"

    Import-Module (Join-Path $CorePath "Config.psm1") -Force
    Import-Module (Join-Path $CorePath "Logger.psm1") -Force
    Import-Module (Join-Path $CorePath "Downloader.psm1") -Force
    Import-Module (Join-Path $CorePath "Progress.psm1") -Force
    Import-Module (Join-Path $ModulesPath "SystemCheck.psm1") -Force
    Import-Module (Join-Path $ModulesPath "NodeInstaller.psm1") -Force
    Import-Module (Join-Path $ModulesPath "NpmConfig.psm1") -Force
    Import-Module (Join-Path $ModulesPath "EnvironmentManager.psm1") -Force
    Import-Module (Join-Path $ModulesPath "Validator.psm1") -Force
}

Describe '模块导入验证' {
    It 'Config 模块导出 Get-Config' {
        Get-Command Get-Config -Module Config | Should -Not -BeNullOrEmpty
    }

    It 'SystemCheck 模块导出 Test-SystemEnvironment' {
        Get-Command Test-SystemEnvironment -Module SystemCheck | Should -Not -BeNullOrEmpty
    }

    It 'NodeInstaller 模块导出 Install-NodeJS' {
        Get-Command Install-NodeJS -Module NodeInstaller | Should -Not -BeNullOrEmpty
    }

    It 'EnvironmentManager 模块导出 Update-SessionEnvironment' {
        Get-Command Update-SessionEnvironment -Module EnvironmentManager | Should -Not -BeNullOrEmpty
    }

    It 'Validator 模块导出 New-InstallationReport' {
        Get-Command New-InstallationReport -Module Validator | Should -Not -BeNullOrEmpty
    }
}

Describe '配置一致性' {
    It 'NodeMinVersion 应为 18.0.0' {
        (Get-Config "NodeMinVersion") | Should -Be ([Version]"18.0.0")
    }

    It 'CDN 镜像列表至少包含 2 个备用源' {
        $mirrors = Get-Config "NodeMirrors"
        $mirrors.Count | Should -BeGreaterOrEqual 2
    }

    It 'TempDir 路径有效' {
        $tempDir = Get-Config "TempDir"
        $tempDir | Should -Match "claudecode-setup"
    }
}

Describe '报告模板验证' {
    It '使用有效数据生成报告不抛出异常' {
        $mockNodeInfo = [PSCustomObject]@{ Installed = $true; Version = "v20.11.0"; Path = "C:\nodejs\node.exe"; Method = "existing" }
        { New-InstallationReport -NodeInfo $mockNodeInfo -NpmConfigured $true -CcSwitchInstalled $true } | Should -Not -Throw
    }
}

# 以下测试需要在管理员模式下运行
Describe '卸载模块验证' -Skip:(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    It 'Uninstaller 模块可加载' {
        Import-Module (Join-Path $PSScriptRoot "..\modules\Uninstaller.psm1") -Force
        Get-Command Uninstall-Environment -Module Uninstaller | Should -Not -BeNullOrEmpty
    }
}
