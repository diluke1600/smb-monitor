# SMB Client Performance Counters to Prometheus Textfile Exporter
# 将 SMB Client 性能计数器转换为 Prometheus textfile 格式

param(
    [string]$OutputPath = "C:\prometheus\textfile\smb_client.prom",
    [int]$IntervalSeconds = 60
)

# 确保输出目录存在
$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# 临时文件路径（原子写入）
$tempFile = "$OutputPath.tmp"

# 获取当前时间戳（Unix 时间戳，秒）
$timestamp = [int64](([datetime]::UtcNow)-(get-date "1/1/1970")).TotalSeconds

# Prometheus metrics 格式函数
function Write-PrometheusMetric {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Type,
        [double]$Value,
        [hashtable]$Labels = @{},
        [int64]$Timestamp = 0
    )
    
    $labelString = ""
    if ($Labels.Count -gt 0) {
        $labelPairs = $Labels.GetEnumerator() | ForEach-Object {
            "$($_.Key)=`"$($_.Value)`""
        }
        $labelString = "{" + ($labelPairs -join ",") + "}"
    }
    
    $output = ""
    
    # 处理 NaN 和 Infinity 值
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
        $Value = 0
    }
    
    if ($Timestamp -gt 0) {
        $output += "$Name$labelString $Value $Timestamp`n"
    } else {
        $output += "$Name$labelString $Value`n"
    }
    
    return $output
}

# 收集 SMB Client 性能计数器
function Get-SMBClientCounters {
    $metrics = @()
    $script:helpTypesPrinted = @{}
    
    try {
        # SMB Client Shares 计数器类别
        $smbClientCategory = "SMB Client Shares"
        
        # 获取所有 SMB Client Shares 实例
        $counterSet = Get-Counter -ListSet $smbClientCategory -ErrorAction SilentlyContinue
        if (-not $counterSet) {
            Write-Warning "无法访问 SMB Client Shares 性能计数器类别"
            return $metrics
        }
        
        $instances = @()
        foreach ($path in $counterSet.PathsWithInstances) {
            if ($path -match "\\SMB Client Shares\\(.+?)\\") {
                $instanceName = $matches[1]
                if ($instanceName -and $instanceName -ne "_Total") {
                    $instances += $instanceName
                }
            }
        }
        $instances = $instances | Select-Object -Unique
        
        if ($instances) {
            foreach ($instance in $instances) {
                # 读取各种计数器
                $counterPaths = @(
                    "\\SMB Client Shares($instance)\\Bytes Read/sec",
                    "\\SMB Client Shares($instance)\\Bytes Written/sec",
                    "\\SMB Client Shares($instance)\\Read Bytes/sec",
                    "\\SMB Client Shares($instance)\\Write Bytes/sec",
                    "\\SMB Client Shares($instance)\\Read Requests/sec",
                    "\\SMB Client Shares($instance)\\Write Requests/sec",
                    "\\SMB Client Shares($instance)\\Current Data Queue Length",
                    "\\SMB Client Shares($instance)\\Data Bytes/sec",
                    "\\SMB Client Shares($instance)\\Data Requests/sec"
                )
                
                foreach ($counterPath in $counterPaths) {
                    try {
                        $counter = Get-Counter -Counter $counterPath -ErrorAction SilentlyContinue
                        if ($counter) {
                            $counterName = ($counterPath -split "\\")[-1] -replace " ", "_" -replace "/", "_per_" -replace "-", "_"
                            $counterName = $counterName.ToLower()
                            $value = $counter.CounterSamples[0].CookedValue
                            
                            $labels = @{
                                share = $instance
                            }
                            
                            $metricName = "smb_client_$counterName"
                            
                            # 添加 HELP 和 TYPE（仅第一次）
                            if (-not $script:helpTypesPrinted.ContainsKey($metricName)) {
                                $script:helpTypesPrinted[$metricName] = $true
                                $metrics += "# HELP $metricName SMB Client $counterName for share`n"
                                $metrics += "# TYPE $metricName gauge`n"
                            }
                            
                            $metrics += Write-PrometheusMetric -Name $metricName `
                                -Description $null `
                                -Type $null `
                                -Value $value `
                                -Labels $labels `
                                -Timestamp $timestamp
                        }
                    } catch {
                        Write-Warning "无法读取计数器 $counterPath : $_"
                    }
                }
            }
        }
        
        # SMB Client 全局计数器（无实例）
        $globalCounters = @(
            @{Path = "\SMB Client Shares\Bytes Read/sec"; Name = "bytes_read_per_sec_total"; Desc = "Total bytes read per second"},
            @{Path = "\SMB Client Shares\Bytes Written/sec"; Name = "bytes_written_per_sec_total"; Desc = "Total bytes written per second"},
            @{Path = "\SMB Client Shares\Read Bytes/sec"; Name = "read_bytes_per_sec_total"; Desc = "Total read bytes per second"},
            @{Path = "\SMB Client Shares\Write Bytes/sec"; Name = "write_bytes_per_sec_total"; Desc = "Total write bytes per second"},
            @{Path = "\SMB Client Shares\Read Requests/sec"; Name = "read_requests_per_sec_total"; Desc = "Total read requests per second"},
            @{Path = "\SMB Client Shares\Write Requests/sec"; Name = "write_requests_per_sec_total"; Desc = "Total write requests per second"}
        )
        
        foreach ($counterInfo in $globalCounters) {
            try {
                $counter = Get-Counter -Counter $counterInfo.Path -ErrorAction SilentlyContinue
                if ($counter) {
                    $value = $counter.CounterSamples[0].CookedValue
                    $metricName = "smb_client_$($counterInfo.Name)"
                    
                    # 添加 HELP 和 TYPE（仅第一次）
                    if (-not $script:helpTypesPrinted.ContainsKey($metricName)) {
                        $script:helpTypesPrinted[$metricName] = $true
                        $metrics += "# HELP $metricName $($counterInfo.Desc)`n"
                        $metrics += "# TYPE $metricName gauge`n"
                    }
                    
                    $metrics += Write-PrometheusMetric -Name $metricName `
                        -Description $null `
                        -Type $null `
                        -Value $value `
                        -Timestamp $timestamp
                }
            } catch {
                Write-Warning "无法读取全局计数器 $($counterInfo.Path) : $_"
            }
        }
        
    } catch {
        Write-Error "获取 SMB Client 计数器时出错: $_"
    }
    
    return $metrics
}

# 主函数：收集指标并写入文件
function Export-SMBClientMetrics {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 开始收集 SMB Client 指标..."
    
    # 收集指标
    $metrics = Get-SMBClientCounters
    
    # 如果没有收集到指标，写入空文件或添加注释
    if ($metrics.Count -eq 0) {
        $metrics += "# No SMB Client metrics available`n"
        Write-Warning "未收集到任何 SMB Client 指标"
    }
    
    # 写入临时文件
    try {
        $metrics -join "" | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline -ErrorAction Stop
        
        # 原子性移动文件（Windows 支持）
        Move-Item -Path $tempFile -Destination $OutputPath -Force -ErrorAction Stop
        
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 指标已导出到: $OutputPath"
        Write-Host "共收集 $($metrics.Count) 个指标行"
    } catch {
        Write-Error "写入文件时出错: $_"
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
        exit 1
    }
}

# 执行导出
Export-SMBClientMetrics

