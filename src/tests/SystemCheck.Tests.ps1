# SystemCheck.Tests.ps1 — 系统检测模块单元测试

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\modules\SystemCheck.psm1"
    $corePath = Join-Path $PSScriptRoot "..\core\Config.psm1"
    Import-Module $corePath -Force
    Import-Module $modulePath -Force

    # Mock 日志函数
    if (-not (Get-Command 'Write-SetupLog' -ErrorAction SilentlyContinue)) {
        function Write-SetupLog { }
    }
}

Describe 'Test-SystemEnvironment' {
    It '返回 PSCustomObject' {
        $result = Test-SystemEnvironment
        $result | Should -BeOfType [PSCustomObject]
    }

    It '包含所有预期属性' {
        $result = Test-SystemEnvironment
        $result.PSObject.Properties.Name | Should -Contain 'OSVersion'
        $result.PSObject.Properties.Name | Should -Contain 'Arch'
        $result.PSObject.Properties.Name | Should -Contain 'IsAdmin'
        $result.PSObject.Properties.Name | Should -Contain 'PSVersion'
        $result.PSObject.Properties.Name | Should -Contain 'IsOnline'
        $result.PSObject.Properties.Name | Should -Contain 'DiskFreeMB'
        $result.PSObject.Properties.Name | Should -Contain 'AllChecksPass'
        $result.PSObject.Properties.Name | Should -Contain 'HasDDrive'
    }

    It 'Arch 应为 x64 或 x86' {
        $result = Test-SystemEnvironment
        $result.Arch | Should -BeIn @('x64', 'x86')
    }

    It 'PSVersion 应不小于 5.1' {
        $result = Test-SystemEnvironment
        $result.PSVersion | Should -Not -BeLessThan [Version]"5.1"
    }
}
