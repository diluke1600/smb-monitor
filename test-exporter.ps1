# 测试 SMB Client Exporter 脚本
# 用于验证脚本是否能正常工作

param(
    [string]$OutputPath = "$PSScriptRoot\test_output.prom"
)

Write-Host "测试 SMB Client Exporter..."
Write-Host "输出路径: $OutputPath"
Write-Host ""

# 运行导出脚本
& "$PSScriptRoot\smb-client-exporter.ps1" -OutputPath $OutputPath

Write-Host ""
Write-Host "检查输出文件..."

if (Test-Path $OutputPath) {
    Write-Host "✓ 输出文件已创建: $OutputPath"
    Write-Host ""
    Write-Host "文件内容预览:"
    Write-Host "----------------------------------------"
    Get-Content $OutputPath -Head 20
    Write-Host "----------------------------------------"
    Write-Host ""
    
    $lineCount = (Get-Content $OutputPath).Count
    Write-Host "文件总行数: $lineCount"
    
    # 验证 Prometheus 格式
    $content = Get-Content $OutputPath -Raw
    if ($content -match "# HELP" -and $content -match "# TYPE") {
        Write-Host "✓ 文件包含 Prometheus HELP 和 TYPE 声明"
    } else {
        Write-Warning "文件可能不符合 Prometheus 格式"
    }
    
    if ($content -match "smb_client_") {
        Write-Host "✓ 文件包含 SMB Client 指标"
    } else {
        Write-Warning "文件未包含 SMB Client 指标"
    }
} else {
    Write-Error "输出文件未创建"
    exit 1
}

Write-Host ""
Write-Host "测试完成！"

