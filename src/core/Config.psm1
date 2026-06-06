# Config.psm1 — 全局配置常量
# 集中管理所有可配置项，便于维护和修改

$Script:Config = @{
    # Node.js
    NodeMinVersion     = [Version]"18.0.0"
    NodeLTSVersion     = "20.18.0"
    NodeDefaultInstall = "C:\nodejs"
    NodeArch           = "x64"

    # CDN 镜像（国内用户优先走镜像，nodejs.org 放最后兜底）
    NodePrimaryUrl     = "https://npmmirror.com/mirrors/node/v{version}/node-v{version}-win-x64.zip"
    NodeMirrors = @(
        "https://mirrors.huaweicloud.com/nodejs/v{version}/node-v{version}-win-x64.zip"
        "https://mirrors.tencent.com/nodejs-release/v{version}/node-v{version}-win-x64.zip"
        "https://nodejs.org/dist/v{version}/node-v{version}-win-x64.zip"
    )

    # npm
    NpmPrefix          = "$env:USERPROFILE\npm-global"
    NpmRegistry        = "https://registry.npmmirror.com"
    NpmOfficialRegistry = "https://registry.npmjs.org"

    # cc-switch
    CcSwitchPackage    = "@claude-code/cc-switch"
    CcSwitchVersion    = "v3.16.1"                                  # 已知最新版，API 不可用时作为回退
    CcSwitchRepo       = "farion1231/cc-switch"                     # GitHub 仓库
    CcSwitchApiUrl     = "https://api.github.com/repos/farion1231/cc-switch/releases/latest"
    CcSwitchApiMirrors = @(                                          # GitHub API 国内镜像（hscsec.cn 实测可用）
        "https://api.github.hscsec.cn/repos/farion1231/cc-switch/releases/latest"
    )
    CcSwitchDownloadMirrors = @(                                     # 文件下载国内加速（越多越容易成功）
        "https://gh-proxy.com/{url}"
        "https://github.hscsec.cn/{url}"
        "https://gh.api.c99ser.dev/{url}"
        "https://hub.gitmirror.com/{url}"
    )

    # 路径
    TempDir            = "$env:TEMP\claudecode-setup"
    RegistryPath       = "HKCU:\Software\ClaudeCodeSetup"
    RegistryNodePath   = "NodeInstallPath"

    # 下载
    DownloadMaxRetries = 1                                              # 每源重试1次，不行就跳下一个
    DownloadTimeoutSec = 30                                             # 10秒没传完直接超时
    DownloadRetryDelay = @(2)                                           # 重试前等2秒

    # 磁盘
    MinDiskSpaceMB     = 500
}

function Get-Config {
    <#
    .SYNOPSIS
        获取全局配置项
    .PARAMETER Key
        配置键名，省略则返回全部
    #>
    param([string]$Key)
    if ($Key) { return $Script:Config[$Key] }
    return $Script:Config
}

function Set-Config {
    <#
    .SYNOPSIS
        更新全局配置项（运行时覆盖）
    #>
    param(
        [string]$Key,
        [object]$Value
    )
    $Script:Config[$Key] = $Value
}

Export-ModuleMember -Function Get-Config, Set-Config
