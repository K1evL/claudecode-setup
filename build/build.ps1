#!/usr/bin/env pwsh
# build.ps1 — ClaudeCode-Setup 构建脚本
# 编译 C# Bootloader 并注入 PowerShell 脚本资源

param(
    [switch]$Clean,
    [switch]$Release
)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BootloaderDir = Join-Path $ProjectRoot "src\ClaudeCode.Setup.Bootloader"
$OutputDir = Join-Path $ProjectRoot "build\out"
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ClaudeCode-Setup 构建脚本" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# 清理
if ($Clean -and (Test-Path $OutputDir)) {
    Write-Host "正在清理输出目录..." -ForegroundColor Yellow
    Remove-Item "$OutputDir\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# 确保输出目录存在
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 检查资源文件
Write-Host "检查资源文件..." -ForegroundColor Yellow
$installScript = Join-Path $ProjectRoot "src\scripts\install.ps1"
$bannerFile = Join-Path $ProjectRoot "src\assets\banner.txt"

if (-not (Test-Path $installScript)) {
    Write-Error "未找到安装脚本: $installScript"
    exit 1
}
if (-not (Test-Path $bannerFile)) {
    Write-Warning "未找到 Banner 文件: $bannerFile"
}

# 编译
Write-Host ""
Write-Host "正在编译 Bootloader..." -ForegroundColor Yellow

$config = if ($Release) { "Release" } else { "Debug" }
$compiled = $false

# --- 尝试 1: MSBuild (Visual Studio Build Tools) ---
if (-not $compiled) {
    $msbuildCandidates = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:SystemRoot}\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
    )
    foreach ($msbuild in $msbuildCandidates) {
        if (Test-Path $msbuild) {
            Write-Host "  尝试 MSBuild: $msbuild" -ForegroundColor DarkGray
            $projectFile = Join-Path $BootloaderDir "ClaudeCode.Setup.Bootloader.csproj"
            & $msbuild $projectFile /p:Configuration=$config /p:OutputPath=$OutputDir /p:Platform=x64
            if ($LASTEXITCODE -eq 0) { $compiled = $true; break }
        }
    }
}

# --- 尝试 2: dotnet build ---
if (-not $compiled) {
    Write-Host "  尝试 dotnet build..." -ForegroundColor DarkGray
    $projectFile = Join-Path $BootloaderDir "ClaudeCode.Setup.Bootloader.csproj"
    dotnet build $projectFile -c $config -o $OutputDir
    if ($LASTEXITCODE -eq 0) { $compiled = $true }
}

# --- 尝试 3: csc.exe 直接编译（零依赖）---
if (-not $compiled) {
    Write-Host "  尝试 csc.exe 直接编译..." -ForegroundColor DarkGray
    $csc = "${env:SystemRoot}\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (Test-Path $csc) {
        $cscArgs = @(
            "/target:exe",
            "/platform:x64",
            "/out:$OutputDir\ClaudeCode-Setup.exe",
            "/optimize+",
            "/nowin32manifest",
            "/resource:$installScript,install.ps1",
            "/resource:$bannerFile,banner.txt"
        )

        # 内嵌所有核心模块 (core/)
        Get-ChildItem "$ProjectRoot\src\core\*.psm1" | ForEach-Object {
            $cscArgs += "/resource:$($_.FullName),core.$($_.Name)"
        }
        # 内嵌所有功能模块 (modules/)
        Get-ChildItem "$ProjectRoot\src\modules\*.psm1" | ForEach-Object {
            $cscArgs += "/resource:$($_.FullName),modules.$($_.Name)"
        }
        # 可选内嵌 cc-switch zip（放在 src/assets/cc-switch-portable.zip）
        $ccSwitchZip = "$ProjectRoot\src\assets\cc-switch-portable.zip"
        if (Test-Path $ccSwitchZip) {
            $zipSize = (Get-Item $ccSwitchZip).Length
            $cscArgs += "/resource:$ccSwitchZip,cc-switch-portable.zip"
            Write-Host "  内嵌 cc-switch zip ($([math]::Round($zipSize/1MB,1)) MB)" -ForegroundColor Green
        }
        else {
            Write-Host "  未找到 cc-switch zip，启用运行时下载" -ForegroundColor DarkGray
        }

        $cscArgs += @(
            "$BootloaderDir\Program.cs",
            "$BootloaderDir\EmbeddedResources.cs"
        )

        & $csc $cscArgs
        if ($LASTEXITCODE -eq 0) { $compiled = $true }
    }
}

if (-not $compiled) {
    Write-Error "所有编译方式均失败，请安装 Visual Studio Build Tools 或 .NET SDK"
    Write-Error "  dotnet SDK: https://dotnet.microsoft.com/download"
    exit 1
}

# 复制 .config 文件（解决 SxS 并行配置错误）
$configSrc = Join-Path $BootloaderDir "app.config"
$configDst = Join-Path $OutputDir "ClaudeCode-Setup.exe.config"
if (Test-Path $configSrc) {
    Copy-Item $configSrc $configDst -Force
    Write-Host "  配置文件: $configDst" -ForegroundColor DarkGray
}

# 检查输出
$exePath = Join-Path $OutputDir "ClaudeCode-Setup.exe"
if (Test-Path $exePath) {
    $fileInfo = Get-Item $exePath
    Write-Host ""
    Write-Host "✅ 构建成功!" -ForegroundColor Green
    Write-Host "   输出: $exePath" -ForegroundColor Green
    Write-Host "   大小: $([math]::Round($fileInfo.Length / 1KB)) KB" -ForegroundColor Green
}
else {
    Write-Error "构建完成但未找到输出文件: $exePath"
    exit 1
}
