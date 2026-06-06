# Logger.psm1 — 双通道日志系统
# 同时输出到终端（彩色）和文件

$Script:LogFilePath = $null
$Script:LogColors = @{
    'INFO'   = 'Cyan'
    'OK'     = 'Green'
    'WARN'   = 'Yellow'
    'ERROR'  = 'Red'
    'STEP'   = 'Magenta'
    'WAIT'   = 'Gray'
}

function Start-SetupLog {
    <#
    .SYNOPSIS
        初始化日志系统，创建日志文件
    #>
    param([string]$LogDir = "$env:TEMP\claudecode-setup")
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Script:LogFilePath = Join-Path $LogDir "claudecode-setup-$timestamp.log"
    Write-SetupLog "INFO" "日志系统初始化完成"
}

function Write-SetupLog {
    <#
    .SYNOPSIS
        写入日志（终端彩色输出 + 文件记录）
    .PARAMETER Level
        日志级别：INFO / OK / WARN / ERROR / STEP
    .PARAMETER Message
        日志内容
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO','OK','WARN','ERROR','STEP','WAIT')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $time = Get-Date -Format "HH:mm:ss"
    $color = $Script:LogColors[$Level]
    if (-not $color) { $color = 'White' }

    # 终端输出
    $tag = "[$Level]".PadRight(7)
    Write-Host "[$time] " -NoNewline -ForegroundColor DarkGray
    Write-Host "$tag " -NoNewline -ForegroundColor $color
    Write-Host $Message -ForegroundColor $color

    # 文件日志
    if ($Script:LogFilePath) {
        $logLine = "[$time] [$Level] $Message"
        Add-Content -Path $Script:LogFilePath -Value $logLine -Encoding UTF8
    }
}

function Write-SetupProgress {
    <#
    .SYNOPSIS
        在终端显示等待动画
    #>
    param([string]$Message)
    $frames = @('.  ', '.. ', '...', ' ..', '  .', '   ')
    foreach ($f in $frames) {
        Write-Host "`r[$((Get-Date).ToString('HH:mm:ss'))] [....] $Message $f" -NoNewline -ForegroundColor Gray
        Start-Sleep -Milliseconds 200
    }
    Write-Host "`r$(' ' * 80)" -NoNewline
    Write-Host "`r[$((Get-Date).ToString('HH:mm:ss'))] [....] $Message" -ForegroundColor Gray
}

function Stop-SetupLog {
    <#
    .SYNOPSIS
        关闭日志系统，返回日志文件路径
    #>
    Write-SetupLog "INFO" "日志系统关闭"
    return $Script:LogFilePath
}

Export-ModuleMember -Function Start-SetupLog, Write-SetupLog, Write-SetupProgress, Stop-SetupLog
