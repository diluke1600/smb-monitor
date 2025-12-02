# SMB Client Performance Counters to Prometheus Textfile Exporter
# Converts SMB Client performance counters into Prometheus textfile format

param(
    [string]$OutputPath = "C:\Program Files\windows_exporter\textfile_inputs\smb_client.prom",
    [int]$IntervalSeconds = 60
)

# Ensure the output directory exists
$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Temporary file path for atomic writes
$tempFile = "$OutputPath.tmp"

# Current Unix timestamp (seconds)
$timestamp = [int64](([datetime]::UtcNow)-(get-date "1/1/1970")).TotalSeconds

# Helper to build Prometheus metrics
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
            # Prometheus exposition format requires backslash and quote escaping
            $escapedValue = $_.Value
            $escapedValue = $escapedValue -replace '\\', '\\\\'
            $escapedValue = $escapedValue -replace '"', '\"'
            "$($_.Key)=`"$escapedValue`""
        }
        $labelString = "{" + ($labelPairs -join ",") + "}"
    }
    
    $output = ""
    
    # Guard against NaN and Infinity
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
        $Value = 0
    }
    
    # Textfile collectors (like windows_exporter) do not support client-side
    # timestamps, so we always omit the timestamp column.
    $output += "$Name$labelString $Value`n"
    
    return $output
}

# Sanitize share instance names for use as Prometheus label values
function Convert-ShareNameToLabelValue {
    param(
        [string]$InstanceName
    )

    if (-not $InstanceName) {
        return ""
    }

    $sanitized = $InstanceName
    # Remove leading backslashes (e.g. "\server\share" -> "server\share")
    $sanitized = $sanitized -replace '^[\\]+', ''
    # Replace remaining backslashes with underscores
    $sanitized = $sanitized -replace '\\', '_'
    # Replace whitespace with underscores
    $sanitized = $sanitized -replace '\s+', '_'

    return $sanitized
}

# Collect SMB client counters
function Get-SMBClientCounters {
    $metrics = @()
    $script:helpTypesPrinted = @{}
    
    try {
        # SMB Client Shares counter category
        $smbClientCategory = "SMB Client Shares"
        
        # Discover counter instances
        $counterSet = Get-Counter -ListSet $smbClientCategory -ErrorAction SilentlyContinue
        if (-not $counterSet) {
            Write-Warning "Unable to access SMB Client Shares counter category"
            return $metrics
        }
        
        $instances = @()
        foreach ($path in $counterSet.PathsWithInstances) {
            if ($path -match "\\SMB Client Shares\((.+?)\)\\") {
                $instanceName = $matches[1]
                if ($instanceName -and $instanceName -ne "_Total") {
                    $instances += $instanceName
                }
            }
        }
        $instances = $instances | Select-Object -Unique
        
        if ($instances) {
            foreach ($instance in $instances) {
                # Read the counters for the instance
                $counterPaths = @(
                    "\SMB Client Shares($instance)\Bytes Read/sec",
                    "\SMB Client Shares($instance)\Bytes Written/sec",
                    "\SMB Client Shares($instance)\Read Bytes/sec",
                    "\SMB Client Shares($instance)\Write Bytes/sec",
                    "\SMB Client Shares($instance)\Read Requests/sec",
                    "\SMB Client Shares($instance)\Write Requests/sec",
                    "\SMB Client Shares($instance)\Current Data Queue Length",
                    "\SMB Client Shares($instance)\Data Bytes/sec",
                    "\SMB Client Shares($instance)\Data Requests/sec",
                    "\SMB Client Shares($instance)\Credit Stalls/sec"
                )
                
                foreach ($counterPath in $counterPaths) {
                    try {
                        $counter = Get-Counter -Counter $counterPath -ErrorAction SilentlyContinue
                        if ($counter) {
                            $counterName = ($counterPath -split "\\")[-1] -replace " ", "_" -replace "/", "_per_" -replace "-", "_"
                            $counterName = $counterName.ToLower()
                            $value = $counter.CounterSamples[0].CookedValue
                            
                            $labels = @{
                                share = (Convert-ShareNameToLabelValue -InstanceName $instance)
                            }
                            
                            $metricName = "smb_client_$counterName"
                            
                            # Add HELP and TYPE once per metric
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
                        Write-Warning "Failed to read counter $counterPath : $_"
                    }
                }
            }
        }
        
        # Global SMB Client counters (no instance)
        $globalCounters = @(
            @{Path = "\SMB Client Shares\Bytes Read/sec"; Name = "bytes_read_per_sec_total"; Desc = "Total bytes read per second"},
            @{Path = "\SMB Client Shares\Bytes Written/sec"; Name = "bytes_written_per_sec_total"; Desc = "Total bytes written per second"},
            @{Path = "\SMB Client Shares\Read Bytes/sec"; Name = "read_bytes_per_sec_total"; Desc = "Total read bytes per second"},
            @{Path = "\SMB Client Shares\Write Bytes/sec"; Name = "write_bytes_per_sec_total"; Desc = "Total write bytes per second"},
            @{Path = "\SMB Client Shares\Read Requests/sec"; Name = "read_requests_per_sec_total"; Desc = "Total read requests per second"},
            @{Path = "\SMB Client Shares\Write Requests/sec"; Name = "write_requests_per_sec_total"; Desc = "Total write requests per second"},
            @{Path = "\SMB Client Shares\Credit Stalls/sec"; Name = "credit_stalls_per_sec_total"; Desc = "Total credit stalls per second"}
        )
        
        foreach ($counterInfo in $globalCounters) {
            try {
                $counter = Get-Counter -Counter $counterInfo.Path -ErrorAction SilentlyContinue
                if ($counter) {
                    $value = $counter.CounterSamples[0].CookedValue
                    $metricName = "smb_client_$($counterInfo.Name)"
                    
                    # Add HELP and TYPE once per metric
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
                Write-Warning "Failed to read global counter $($counterInfo.Path) : $_"
            }
        }
        
    } catch {
        Write-Error "Failed to query SMB Client counters: $_"
    }
    
    return $metrics
}

# Collect metrics and write them to disk
function Export-SMBClientMetrics {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Collecting SMB Client metrics..."
    
    # Gather metrics
    $metrics = Get-SMBClientCounters
    
    # If nothing was collected, emit a placeholder comment
    if ($metrics.Count -eq 0) {
        $metrics += "# No SMB Client metrics available`n"
        Write-Warning "No SMB Client metrics were collected"
    }
    
    # Write to temp file first
    try {
        $metrics -join "" | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline -ErrorAction Stop
        
        # Atomic move into place
        Move-Item -Path $tempFile -Destination $OutputPath -Force -ErrorAction Stop
        
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Metrics exported to: $OutputPath"
        Write-Host "Total metric lines: $($metrics.Count)"
    } catch {
        Write-Error "Failed to write metrics file: $_"
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
        exit 1
    }
}

# Entrypoint
Export-SMBClientMetrics

