# File: CheckAndRestart.ps1

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
                Log-Message "$FailureMessage after $MaxRetries attempts."
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

function Log-Message {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

$servicesToCheck = @("ManageEngine UEMS - Agent", "W32Time")

$processesToCheck = @(
    @{ Name = "dcondemand"; Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\dcondemand.exe" },
    @{ Name = "DCProcessMonitor";    Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\DCProcessMonitor.exe" },
	@{ Name = "dcagenttrayicon"; Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\dcagenttrayicon.exe" }
	
)

Write-Host "Checking services..." -ForegroundColor Cyan
Log-Message "--- Checking services ---"

foreach ($svc in $servicesToCheck) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        $msg = "Service '$svc' not found."
        Write-Warning $msg
        Log-Message $msg
        continue
    }

    if ($service.Status -ne "Running") {
        $msg = "Starting service '$svc'..."
        Write-Host $msg -ForegroundColor Yellow
        Log-Message $msg
        Retry-Command -Command { Start-Service -Name $svc } -FailureMessage "Failed to start service '$svc'"
    } else {
        $msg = "Service '$svc' is running."
        Write-Host $msg -ForegroundColor Green
        Log-Message $msg
    }
}

Write-Host "`nChecking processes..." -ForegroundColor Cyan
Log-Message "--- Checking processes ---"

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
            Log-Message $msg
            $runningProcs | Stop-Process -Force
            Retry-Command -Command { Start-Process -FilePath $proc.Path } -FailureMessage "Failed to start process '$($proc.Name)'"
        } else {
            $msg = "Process '$($proc.Name)' is responsive and running."
            Write-Host $msg -ForegroundColor Green
            Log-Message $msg
        }
    } else {
        $msg = "Process '$($proc.Name)' not running. Starting..."
        Write-Host $msg -ForegroundColor Yellow
        Log-Message $msg
        Retry-Command -Command { Start-Process -FilePath $proc.Path } -FailureMessage "Failed to start process '$($proc.Name)'"
    }
}
