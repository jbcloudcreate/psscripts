# =============================================================================
#
# Script: Domain_Decom.ps1
# Description: Script with disclaimer to decommision AWS Instance 
# Author: James Buller.
# Creation Date: Date: 5th July 2025
# 
# =============================================================================

# Determine domain FQDN
try {
    $DomainFQDN = ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name
    Log "Detected domain FQDN: $DomainFQDN"
} catch {
    Write-Error "ERROR: Could not determine domain FQDN. Exiting."
    exit 1
}

# Set log path to netlogon\decommission
$NetlogonPath = "\\$DomainFQDN\netlogon\decommission"
if (-not (Test-Path $NetlogonPath)) {
    try {
        New-Item -Path $NetlogonPath -ItemType Directory -Force | Out-Null
        Write-Output "Created folder: $NetlogonPath"
    } catch {
        Write-Error "ERROR: Could not create folder at $NetlogonPath. Exiting."
        exit 1
    }
}

$LogFile = Join-Path $NetlogonPath "DecommissionLog_$(Get-Date -Format yyyyMMdd_HHmmss).txt"

function Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

# Disclaimer
$Disclaimer = @"
WARNING: You are about to decommission this computer.
This will remove it from the domain, delete temp files, remove applications, stop services, etc.
Do you agree to continue?
"@

$response = [System.Windows.Forms.MessageBox]::Show($Disclaimer, "Decommission Disclaimer", 'YesNo', 'Warning')
if ($response -ne 'Yes') {
    Log "User did not accept the disclaimer. Exiting."
    exit 1
}
Log "User accepted the disclaimer."

# Create local admin account
$Username = "ssc-localadmin"
$Password = [System.Web.Security.Membership]::GeneratePassword(20,3) | ConvertTo-SecureString -AsPlainText -Force
try {
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $Username -Password $Password -FullName "Local Administrator" -Description "Decommission local admin account"
        Add-LocalGroupMember -Group "Administrators" -Member $Username
        Log "Created local admin account: $Username"
    } else {
        Log "Local admin account already exists: $Username"
    }
} catch {
    Log "ERROR creating local admin: $_"
}
# Stop services
$ServicesToStop = @("Elastic Agent","SomeService2") # Replace with actual services
foreach ($svc in $ServicesToStop) {
    try {
        Stop-Service -Name $svc -Force -ErrorAction Stop
        Log "Stopped service: $svc"
    } catch {
        Log "Failed to stop service: $svc - $_"
    }
}

# Uninstall applications
$AppsToUninstall = @("AppName1","AppName2") # Replace with actual display names
foreach ($app in $AppsToUninstall) {
    try {
        $product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $app }
        if ($product) {
            $product.Uninstall()
            Log "Uninstalled application: $app"
        } else {
            Log "Application not found: $app"
        }
    } catch {
        Log "Failed to uninstall application: $app - $_"
    }
}

# Detect current domain
try {
    $Domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name
    Log "Detected domain: $Domain"
} catch {
    Log "Computer is not part of a domain or could not detect domain. Exiting."
    exit 1
}

# Prompt for domain admin credentials
$Credential = Get-Credential -Message "Enter domain admin credentials to unjoin from $Domain"
Log "Domain admin credentials collected."

# Unjoin from domain
try {
    Remove-Computer -UnjoinDomaincredential $Credential -PassThru -Verbose -Force
    Log "Successfully unjoined from domain: $Domain"
} catch {
    Log "ERROR unjoining from domain: $_"
}

# Clean temporary files
try {
    Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Log "Cleared contents of TEMP folder: $env:TEMP"
} catch {
    Log "Error clearing TEMP folder: $_"
}

try {
    if (Test-Path C:\Temp) {
        Remove-Item -Path C:\Temp\* -Recurse -Force -ErrorAction SilentlyContinue
        Log "Cleared contents of C:\Temp"
    } else {
        Log "C:\Temp folder does not exist."
    }
} catch {
    Log "Error clearing C:\Temp: $_"
}

Log "Script completed successfully. Computer will restart if unjoin was successful."
Pause
