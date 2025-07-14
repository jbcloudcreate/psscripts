# Patch_Install_Manual.ps1
# For Windows Server 2025 Datacenter (24H2)
# Installs updates in sequence with logging and service checks
# Author: James Buller

# Add patches to the directory below.
$patchDir = "C:\temp\patches"

$logFile = "C:\temp\patches\install-log.txt"
$currentUser = $env:USERNAME

# Exact name of the patches in order.
$patches = @(
    "Exact_File_Name.msu",
    #"More_Filenames.msu",
    #"More_Filenames.msu",
    #"More_Filenames.msu"
)

function Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $entry = "$timestamp - $message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

function Ensure-ServiceRunning {
    param ([string]$serviceName)

    try {
        $svc = Get-Service -Name $serviceName -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            Log "Starting service: $serviceName"
            Start-Service $serviceName
            Start-Sleep -Seconds 2
        }
        Log "Service '$serviceName' is running"
    }
    catch {
        Log "Could not check or start service: $serviceName"
        exit 1
    }
}

# --- Start ---
Log "=== Starting patch installation ==="

# Start required update services
Ensure-ServiceRunning -serviceName "wuauserv"
Ensure-ServiceRunning -serviceName "BITS"

# Install patches in order
foreach ($patch in $patches) {
    $patchPath = Join-Path -Path $patchDir -ChildPath $patch
    if (Test-Path $patchPath) {
        Log "Installing: $patch"
        $process = Start-Process -FilePath "wusa.exe" -ArgumentList "`"$patchPath`" /quiet /norestart" -Wait -PassThru
        $exitCode = $process.ExitCode
        if ($exitCode -eq 0) {
            Log "Success: $patch"
        } else {
            Log "Failed: $patch with exit code $exitCode"
        }
    } else {
        Log "File not found: $patchPath"
    }
}

Log "=== Patch installation complete ==="

# Optional reboot prompt
$reboot = Read-Host "Do you want to reboot now? (Y/N)"
if ($reboot -eq "Y") {
    Log "System rebooting..."
	shutdown.exe /r /f /t 30 /d p:2:4 /c "Restart for updates by $currentUser"
}
