# 设置计划任务以定期运行 SMB Client Exporter
# 需要管理员权限运行

param(
    [string]$ScriptPath = "$PSScriptRoot\smb-client-exporter.ps1",
    [string]$TaskName = "SMB Client Prometheus Exporter",
    [int]$IntervalMinutes = 1
)

# 检查管理员权限
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "此脚本需要管理员权限运行"
    exit 1
}

# 检查脚本文件是否存在
if (-not (Test-Path $ScriptPath)) {
    Write-Error "找不到脚本文件: $ScriptPath"
    exit 1
}

# 删除已存在的任务（如果存在）
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "删除已存在的任务: $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# 创建计划任务
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 365)

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "定期导出 SMB Client 性能计数器到 Prometheus textfile 格式"

# 注册任务
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force

Write-Host "计划任务已创建: $TaskName"
Write-Host "任务将每 $IntervalMinutes 分钟运行一次"
Write-Host "使用以下命令查看任务状态:"
Write-Host "  Get-ScheduledTask -TaskName `"$TaskName`""
Write-Host "  Get-ScheduledTaskInfo -TaskName `"$TaskName`""

