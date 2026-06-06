#!/usr/bin/env pwsh
# sign.ps1 — 代码签名脚本
# 使用 EV Code Signing Certificate 对 exe 签名

param(
    [Parameter(Mandatory)]
    [string]$ExePath,

    [string]$CertificateThumbprint,

    [string]$TimestampServer = "http://timestamp.digicert.com",

    [string]$Description = "ClaudeCode 一键环境配置器",

    [string]$Url = "https://github.com/your-repo/claudecode-setup"
)

if (-not (Test-Path $ExePath)) {
    Write-Error "文件不存在: $ExePath"
    exit 1
}

Write-Host "正在签名: $ExePath" -ForegroundColor Cyan

# 查找 signtool
$SignToolPaths = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\8.1\bin\x64\signtool.exe",
    "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe"
)

$signtool = $null
foreach ($pattern in $SignToolPaths) {
    $resolved = Resolve-Path $pattern -ErrorAction SilentlyContinue
    if ($resolved) {
        $signtool = $resolved[-1].Path
        break
    }
}

if (-not $signtool) {
    Write-Error "未找到 signtool，请安装 Windows SDK"
    exit 1
}

Write-Host "使用: $signtool" -ForegroundColor DarkGray

$args = @(
    "sign"
    "/fd", "SHA256"
    "/a"
    "/d", "`"$Description`""
    "/du", "`"$Url`""
    "/tr", $TimestampServer
    "/td", "SHA256"
)

if ($CertificateThumbprint) {
    $args += "/sha1"
    $args += $CertificateThumbprint
}

$args += "`"$ExePath`""

$process = Start-Process -FilePath $signtool -ArgumentList $args -Wait -PassThru -NoNewWindow

if ($process.ExitCode -eq 0) {
    Write-Host "✅ 签名成功" -ForegroundColor Green

    # 验证签名
    Start-Process -FilePath $signtool -ArgumentList "verify /pa /v `"$ExePath`"" -Wait -NoNewWindow
}
else {
    Write-Error "签名失败 (退出码: $($process.ExitCode))"
    exit 1
}
