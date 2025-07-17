# ===========================================================================================
#
# Script: Service_Process_Checker_ME.ps1
# Description: Script to test if services and processes are running and if not to start them 
# Author: James Buller / Aamir Miah
# Creation Date: Date: 17th July 2025
# 
# ===========================================================================================

# Utility function to retry a command
function Retry-Command {
    param (
        [ScriptBlock]$Command,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2,
        [string]$FailureMessage
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            & $Command
            return $true
        } catch {
            if ($i -eq $MaxRetries) {
                Log-Message "$FailureMessage after $MaxRetries attempts." -EventType "Warning" -EventId 1101
                Write-Warning "$FailureMessage after $MaxRetries attempts."
                return $false
            }
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# Logging setup
$logDir = "C:\temp\me_logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
$logFile = Join-Path $logDir "monitor_log.txt"

# Ensure Event Source exists
if (-not [System.Diagnostics.EventLog]::SourceExists("ServiceMonitor")) {
    New-EventLog -LogName Application -Source "ServiceMonitor"
}

function Log-Message {
    param (
        [string]$Message,
        [string]$EventType = "Information",
        [int]$EventId = 1000
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-EventLog -LogName Application -Source "ServiceMonitor" -EntryType $EventType -EventId $EventId -Message $logEntry
}

$servicesToCheck = @("ManageEngine UEMS - Agent", "W32Time")

$processesToCheck = @(
    @{ Name = "dcondemand"; Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\dcondemand.exe" },
    @{ Name = "DCProcessMonitor";    Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\DCProcessMonitor.exe" }
	
)

Write-Host "Checking services..." -ForegroundColor Cyan
Log-Message "--- Checking services ---" -EventId 1001

foreach ($svc in $servicesToCheck) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        $msg = "Service '$svc' not found."
        Write-Warning $msg
        Log-Message $msg -EventType "Error" -EventId 1201
        continue
    }

    if ($service.Status -ne "Running") {
        $msg = "Starting service '$svc'..."
        Write-Host $msg -ForegroundColor Yellow
        Log-Message $msg -EventType "Warning" -EventId 1202
        Retry-Command -Command { Start-Service -Name $svc } -FailureMessage "Failed to start service '$svc'"
    } else {
        $msg = "Service '$svc' is running."
        Write-Host $msg -ForegroundColor Green
        Log-Message $msg -EventId 1002
    }
}

Write-Host "`nChecking processes..." -ForegroundColor Cyan
Log-Message "--- Checking processes ---" -EventId 1003

foreach ($proc in $processesToCheck) {
    $runningProcs = Get-Process -Name $proc.Name -ErrorAction SilentlyContinue

    if ($runningProcs) {
        $isResponsive = $true
        foreach ($p in $runningProcs) {
            $dotNetProc = [System.Diagnostics.Process]::GetProcessById($p.Id)
            if (-not $dotNetProc.Responding) {
                $isResponsive = $false
                break
            }
        }

        if (-not $isResponsive) {
            $msg = "Process '$($proc.Name)' is unresponsive. Restarting..."
            Write-Warning $msg
            Log-Message $msg -EventType "Warning" -EventId 1301
            $runningProcs | Stop-Process -Force
            Retry-Command -Command { Start-Process -FilePath $proc.Path } -FailureMessage "Failed to start process '$($proc.Name)'"
        } else {
            $msg = "Process '$($proc.Name)' is responsive and running."
            Write-Host $msg -ForegroundColor Green
            Log-Message $msg -EventId 1004
        }
    } else {
        $msg = "Process '$($proc.Name)' not running. Starting..."
        Write-Host $msg -ForegroundColor Yellow
        Log-Message $msg -EventType "Warning" -EventId 1302
        Retry-Command -Command { Start-Process -FilePath $proc.Path } -FailureMessage "Failed to start process '$($proc.Name)'"
    }
}
