# ===========================================================================================
#
# Script: Service_Process_Checker_ME.ps1
# Description: Script to test if services and processes are running and if not to start them 
# Author: James Buller / Aamir Miah
# Creation Date: Date: 17th July 2025
# 
# ===========================================================================================

# Variables
$currentUser = $env:USERNAME
$computerName = $env:COMPUTERNAME

$servicesToCheck = @("ManageEngine UEMS - Agent", "W32Time")

$processesToCheck = @(
    @{ Name = "dcondemand"; Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\dcondemand.exe" },
    @{ Name = "DCProcessMonitor";    Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\DCProcessMonitor.exe" },
	@{ Name = "dcagenttrayicon"; Path = "C:\Program Files (x86)\ManageEngine\UEMS_Agent\bin\dcagenttrayicon.exe" }
	
)

Write-Host "Checking services..." -ForegroundColor Cyan

foreach ($svc in $servicesToCheck) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        Write-Warning "Service '$svc' not found."
        continue
    }

    if ($service.Status -ne "Running") {
        Write-Host "Starting service '$svc'..." -ForegroundColor Yellow
        Start-Service -Name $svc
    } else {
        Write-Host "Service '$svc' is running." -ForegroundColor Green
    }
}

Write-Host "`nChecking processes..." -ForegroundColor Cyan

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
            Write-Warning "Process '$($proc.Name)' is unresponsive. Restarting..."
            $runningProcs | Stop-Process -Force
            Start-Process -FilePath $proc.Path
        } else {
            Write-Host "Process '$($proc.Name)' is responsive and running." -ForegroundColor Green
        }
    } else {
        Write-Host "Process '$($proc.Name)' not running. Starting..." -ForegroundColor Yellow
        Start-Process -FilePath $proc.Path
    }
}
