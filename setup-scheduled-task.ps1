# Configure a scheduled task to run the SMB Client exporter
# Requires administrative privileges

param(
    [string]$ScriptPath = "$PSScriptRoot\smb-client-exporter.ps1",
    [string]$TaskName = "SMB Client Prometheus Exporter",
    [int]$IntervalMinutes = 1
)

# Verify administrative privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Administrative privileges are required"
    exit 1
}

# Make sure the exporter exists
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Exporter script not found: $ScriptPath"
    exit 1
}

# Remove an existing task with the same name
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Removing existing task: $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create the new task definition
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 365)

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Export SMB Client counters to Prometheus textfile format"

# Register the task
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force

Write-Host "Scheduled task created: $TaskName"
Write-Host "Frequency: every $IntervalMinutes minute(s)"
Write-Host "Use the commands below to inspect the task:"
Write-Host "  Get-ScheduledTask -TaskName `"$TaskName`""
Write-Host "  Get-ScheduledTaskInfo -TaskName `"$TaskName`""

