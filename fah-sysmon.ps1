# Syntaxe : .\fah-sysmon.ps1 [INTERVALLE_SECONDES] [LOG_FILE]
# Exemple 1 : .\fah-sysmon.ps1 (1 passe, pas de log)
# Exemple 2 : .\fah-sysmon.ps1 -LogFile "C:\logs\fah-sysmon.log" (1 passe + log)
# Exemple 3 : .\fah-sysmon.ps1 10 "C:\logs\fah-sysmon.log" (boucle 10s + log)

param(
    [Parameter(Position=0)]
    [int]$Interval = 0,

    [Parameter(Position=1)]
    [string]$LogFile = ""
)

function Get-FahMonitoring {
    $output = @()
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $output += "`n`n================================================================================"
    $output += "  SYSTEM & GPU MONITORING - $timestamp"
    $output += "================================================================================"

    # === CPU INFO ===
    $output += "`n=== CPU INFO ==="
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuCores = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    
    $modelName = if ($cpu) { $cpu.Name.Trim() } else { "N/A" }
    $cpuId = if ($cpu) { "Family $($cpu.Caption) Stepping $($cpu.Stepping)" } else { "N/A" }
    $cpuFreq = if ($cpu) { "$($cpu.CurrentClockSpeed) MHz" } else { "N/A" }

    $output += "CPU Model          : $modelName"
    $output += "CPU ID             : $cpuId"
    $output += "CPUs               : $cpuCores"
    $output += "CPU Freq           : $cpuFreq (avg on $cpuCores cores)"

    # === MEMORY USAGE ===
    $output += "`n=== MEMORY USAGE ==="
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRamGB = $os.TotalVisibleMemorySize / 1MB
    $freeRamGB = $os.FreePhysicalMemory / 1MB
    $usedRamGB = $totalRamGB - $freeRamGB
    $pctRam = ($usedRamGB / $totalRamGB) * 100

    $output += "Container RAM      : N/A (Windows system)"
    $output += ("Host RAM           : {0:N2} GiB used | {1:N2} GiB free | {2:N2} GiB total ({3:N1}%)" -f $usedRamGB, $freeRamGB, $totalRamGB, $pctRam)

    # === OS INFO ===
    $output += "`n=== OS INFO ==="
    # Lecture dans le registre Windows (Version texte 25H2 + Révision de build UBR)
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $displayVersion = (Get-ItemProperty -Path $regPath -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
    $ubr = (Get-ItemProperty -Path $regPath -Name UBR -ErrorAction SilentlyContinue).UBR

    # Reconstruction du build exact (ex: 10.0.26200.9168) et du nom complet
    $fullBuild = if ($ubr) { "$($os.Version).$ubr" } else { $os.Version }
    $distroStr = if ($displayVersion) { "$($os.Caption) ($displayVersion)" } else { $os.Caption }

    $output += "OS Distribution    : $distroStr"
    $output += "Kernel Version     : $fullBuild"

    # === DRIVER & CUDA INFO ===
    $output += "`n=== DRIVER & CUDA INFO ==="
    $driverVer = "N/A"
    $cudaMax = "N/A"
    
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $driverVer = (nvidia-smi --query-gpu=driver_version --format=csv,noheader | Select-Object -First 1).Trim()
        
        # Out-String force la sortie complète en une seule chaîne multi-lignes
        $rawText = Out-String -InputObject (nvidia-smi 2>&1)
        if ($rawText -match 'CUDA Version:\s*([0-9.]+)') {
            $cudaMax = $Matches[1]
        }
    }
    $output += "Host Driver        : $driverVer"
    $output += "Max CUDA Support   : $cudaMax"
    $output += "CUDA Runtime       : N/A (Windows system)"

    # === GPU INFO ===
    $output += "`n=== GPU INFO   ==="
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $gpuLines = nvidia-smi --query-gpu=name,memory.total,temperature.gpu,utilization.gpu,utilization.memory,power.draw,power.limit,power.default_limit,power.max_limit,compute_cap --format=csv,noheader
        foreach ($line in $gpuLines) {
            $cols = $line -split ',\s*'
            $pDraw = [float]($cols[5] -replace ' W','')
            $pLimit = [float]($cols[6] -replace ' W','')
            $pDef = [float]($cols[7] -replace ' W','')
            $pMax = $cols[8]
            
            $capped = if ($pLimit -lt $pDef) { " (power capped)" } else { "" }

            $output += "GPU Model          : $($cols[0])"
            $output += "Compute Capability : $($cols[9])"
            $output += "Total VRAM         : $($cols[1])"
            $output += "VRAM Utilization   : $($cols[4])"
			$output += "GPU Temp           : $($cols[2]) $([char]176)C"
			$output += "GPU Utilization    : $($cols[3])"
            $output += "Power Draw         : $($cols[5])"
            $output += "Power Limit        : $($cols[6])$capped"
            $output += "Max VBIOS Limit    : $pMax"
        }
    } else {
        $output += "nvidia-smi non détecté"
    }

    # === FAH PROCESSES ===
    $output += "`n=== FAH PROCESSES ==="
    $fahProcs = Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'FAHClient|FahCore_' }
    
    if ($fahProcs) {
        $output += ("{0,-8} {1,-10} {2,-6} {3,-12} {4}" -f "PID", "USER", "%MEM", "RSS", "COMMAND")
        foreach ($p in $fahProcs) {
            $pidVal = $p.ProcessId
            
            # Récupération du Propriétaire
            $owner = "N/A"
            try {
                $ownerRes = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
                if ($ownerRes.User) { $owner = $ownerRes.User }
            } catch {}

            $workingSetMB = $p.WorkingSetSize / 1MB
            $memStr = if ($workingSetMB -ge 1024) { "{0:N2} GiB" -f ($workingSetMB / 1024) } else { "{0:N1} MiB" -f $workingSetMB }
            
            $pctMemVal = ($p.WorkingSetSize / ($os.TotalVisibleMemorySize * 1KB)) * 100
            $pctMemStr = "{0:N1}%" -f $pctMemVal
            
            $cmd = if ($p.CommandLine) { $p.CommandLine } else { $p.Name }

            $output += ("{0,-8} {1,-10} {2,-6} {3,-12} {4}" -f $pidVal, $owner, $pctMemStr, $memStr, $cmd)
        }
    } else {
        $output += "No FAH process running"
    }

    # === FAHCLIENT DATA DIRECTORY ===
    $fahDir = "$env:APPDATA\FAHClient"
    if (-not (Test-Path $fahDir)) {
        $fahDir = "C:\ProgramData\FAHClient"
    }

    if (Test-Path $fahDir) {
        $output += "`n=== SUBDIRECTORIES IN $fahDir ==="
        $dirs = Get-ChildItem -Path $fahDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name
        if ($dirs) {
            foreach ($d in $dirs) {
                $size = (Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $sizeMB = $size / 1MB
                $sizeStr = if ($sizeMB -ge 1024) { "{0:N1}G" -f ($sizeMB / 1024) } else { "{0:N1}M" -f $sizeMB }
                $output += "{0,-8} {1}" -f $sizeStr, $d.Name
            }
        } else {
            $output += "No subdirectories"
        }

        $output += "`n=== FILES IN $fahDir ROOT ==="
        $files = Get-ChildItem -Path $fahDir -File -ErrorAction SilentlyContinue
        if ($files) {
            $totalFilesSize = ($files | Measure-Object -Property Length -Sum).Sum
            $sizeMB = $totalFilesSize / 1MB
            $sizeStr = if ($sizeMB -ge 1024) { "{0:N1}G" -f ($sizeMB / 1024) } else { "{0:N1}M" -f $sizeMB }
            $output += "{0,-8} total" -f $sizeStr
        } else {
            $output += "No individual files"
        }
    } else {
        $output += "`n=== FAHCLIENT DATA DIRECTORY ==="
        $output += "Directory not found (%APPDATA%\FAHClient or C:\ProgramData\FAHClient)"
    }

    return $output
}

function Execute-Monitoring {
    $res = Get-FahMonitoring
    $res | Out-Host

    if ($LogFile) {
        $res | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
}

# Boucle principale
if ($Interval -gt 0) {
    while ($true) {
        Clear-Host
        Execute-Monitoring
        if ($LogFile) { Write-Host "--> Output appended to $LogFile" }
        Write-Host "`n[Refreshing every ${Interval}s - Press Ctrl+C to stop]"
        Start-Sleep -Seconds $Interval
    }
} else {
    Execute-Monitoring
    if ($LogFile) { Write-Host "`n--> Output appended to $LogFile" }
}
