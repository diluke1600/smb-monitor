# Quick test harness for the SMB Client exporter

param(
    [string]$OutputPath = "$PSScriptRoot\test_output.prom"
)

Write-Host "Testing SMB Client exporter..."
Write-Host "Output path: $OutputPath"
Write-Host ""

# Execute the exporter
& "$PSScriptRoot\smb-client-exporter.ps1" -OutputPath $OutputPath

Write-Host ""
Write-Host "Checking output file..."

if (Test-Path $OutputPath) {
    Write-Host "[OK] Output file created: $OutputPath"
    Write-Host ""
    Write-Host "Preview:"
    Write-Host "----------------------------------------"
    Get-Content $OutputPath -Head 20
    Write-Host "----------------------------------------"
    Write-Host ""
    
    $lineCount = (Get-Content $OutputPath).Count
    Write-Host "Total lines: $lineCount"
    
    # Basic validation for Prometheus format
    $content = Get-Content $OutputPath -Raw
    if ($content -match "# HELP" -and $content -match "# TYPE") {
        Write-Host "[OK] HELP and TYPE sections found"
    } else {
        Write-Warning "File might not follow Prometheus format"
    }
    
    if ($content -match "smb_client_") {
        Write-Host "[OK] SMB Client metrics detected"
    } else {
        Write-Warning "No SMB Client metrics detected"
    }
} else {
    Write-Error "Output file was not created"
    exit 1
}

Write-Host ""
Write-Host "Test complete!"

