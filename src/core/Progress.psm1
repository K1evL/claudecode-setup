# Progress.psm1 — 进度展示工具

function Show-StepProgress {
    <#
    .SYNOPSIS
        显示安装步骤进度条和状态
    .PARAMETER StepName
        步骤名称
    .PARAMETER TotalSteps
        总步骤数
    .PARAMETER CurrentStep
        当前步骤序号
    .PARAMETER Status
        状态：Running / Success / Failed / Skipped
    .PARAMETER Detail
        可选的详细信息
    #>
    param(
        [Parameter(Mandatory)]
        [string]$StepName,

        [int]$TotalSteps = 1,

        [int]$CurrentStep = 1,

        [ValidateSet('Running', 'Success', 'Failed', 'Skipped', 'Warn')]
        [string]$Status = 'Running',

        [string]$Detail = ''
    )

    $percent = [math]::Round(($CurrentStep / $TotalSteps) * 100)

    switch ($Status) {
        'Running' {
            Write-Progress -Activity "正在安装 ClaudeCode 环境" -Status $StepName -CurrentOperation $Detail -PercentComplete $percent
        }
        'Success' {
            Write-Progress -Activity "正在安装 ClaudeCode 环境" -Status $StepName -Completed
        }
        'Failed' {
            Write-Progress -Activity "正在安装 ClaudeCode 环境" -Status "$StepName ❌ 失败" -Completed
        }
        'Skipped' {
            Write-Progress -Activity "正在安装 ClaudeCode 环境" -Status "$StepName ⏭️ 跳过" -Completed
        }
        'Warn' {
            Write-Progress -Activity "正在安装 ClaudeCode 环境" -Status "$StepName ⚠️ 警告" -Completed
        }
    }
}

function Get-StatusIcon {
    <#
    .SYNOPSIS
        根据状态返回对应的图标/标记
    #>
    param(
        [ValidateSet('Pass', 'Fail', 'Warn', 'Info', 'Skip')]
        [string]$Status
    )
    switch ($Status) {
        'Pass'  { return '[✅]' }
        'Fail'  { return '[❌]' }
        'Warn'  { return '[⚠️]' }
        'Info'  { return '[ℹ️]' }
        'Skip'  { return '[⏭️]' }
    }
}

Export-ModuleMember -Function Show-StepProgress, Get-StatusIcon
