# NodeInstaller.Tests.ps1 — Node.js 安装模块单元测试

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\modules\NodeInstaller.psm1"
    $corePath = Join-Path $PSScriptRoot "..\core\Config.psm1"
    Import-Module $corePath -Force
    Import-Module $modulePath -Force

    # Mock 日志和下载函数
    function Write-SetupLog { }
    function Invoke-RobustDownload { param($Url, $FallbackUrls, $OutputPath) }
    function Test-NetworkAvailable { return $true }
}

Describe '解析 Node.js 版本' {
    It '解析正常版本号' {
        $result = Parse-NodeVersion "v20.11.0"
        $result | Should -BeOfType [Version]
        $result.Major | Should -Be 20
    }

    It '解析无 v 前缀版本' {
        $result = Parse-NodeVersion "18.17.1"
        $result.Major | Should -Be 18
    }

    It '无效版本返回 0.0.0' {
        $result = Parse-NodeVersion "invalid"
        $result | Should -Be ([Version]"0.0.0")
    }
}

Describe 'Node.js 路径检测' {
    It 'PATH 中无 Node 时返回 Found=false' {
        # Mock Get-Command 返回 null
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'node' }
        $result = Find-NodeInPath
        $result.Found | Should -Be $false
    }
}

Describe '安装路径选择' {
    It '默认路径为 C:\nodejs' {
        (Get-Config "NodeDefaultInstall") | Should -Be "C:\nodejs"
    }
}
