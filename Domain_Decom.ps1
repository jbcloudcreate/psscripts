# =============================================================================
#
# Script: Domain_Decom.ps1
# Description: Script with disclaimer to decommision AWS Instance 
# Author: James Buller.
# Creation Date: Date: 5th July 2025
# 
# =============================================================================

# Corrected version check and auto-update logic from GitHub

$CurrentVersion = "1.0.0"
$RepoRawUrl = "https://raw.githubusercontent.com/jbcloudcreate/psscripts/main/Domain_Decom.ps1"

try {
    Log "Checking for updated script version at $RepoRawUrl"
    $RemoteScriptContent = Invoke-WebRequest -Uri $RepoRawUrl -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content
    if ($RemoteScriptContent -match '\\$CurrentVersion\\s*=\\s*"([\\d\\.]+)"') {
        $RemoteVersion = $Matches[1]
        Log "Remote script version detected: $RemoteVersion"
        if ($RemoteVersion -ne $CurrentVersion) {
            Log "New version available. Downloading updated script..."
            $LocalScriptPath = $PSCommandPath
            $BackupPath = "$LocalScriptPath.bak"
            Copy-Item -Path $LocalScriptPath -Destination $BackupPath -Force
            $RemoteScriptContent | Out-File -FilePath $LocalScriptPath -Encoding UTF8
            Log "Script updated to version $RemoteVersion. Relaunching new version."
            Write-LogColor "🔄 Script updated to version $RemoteVersion. Relaunching..." Cyan
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$LocalScriptPath`"" -Verb RunAs
            exit 0
        } else {
            Log "Current script is up-to-date (version $CurrentVersion)."
        }
    } else {
        Log-Error "Could not determine remote script version. Skipping update."
    }
} catch {
    Log-Error "Version check or update failed: $_"
}

# Check for administrator privileges and auto-elevate if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $promptTitle = "Administrator Privileges Required"
    $promptMessage = "This script must run with elevated permissions to perform all actions.\n\nDo you want to restart it as administrator now?"
    $confirmTime = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $confirm = [System.Windows.Forms.MessageBox]::Show($promptMessage, $promptTitle,'YesNo','Question')
    Log "$confirmTime - Elevation prompt displayed. User response: $confirm"
    if ($confirm -ne 'Yes') {
        Log "$confirmTime - User declined elevation. Exiting script."
        Write-Error "User declined elevation. Exiting."
        exit 1
    }

    Log "$confirmTime - Elevation prompt accepted. Relaunching script as administrator."

    $procInfo = New-Object System.Diagnostics.ProcessStartInfo
    $procInfo.FileName = "powershell.exe"
    $procInfo.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $procInfo.Verb = "runas"
    try {
        [System.Diagnostics.Process]::Start($procInfo) | Out-Null
    } catch {
        Write-Error "ERROR: User cancelled elevation or elevation failed. Exiting."
        Log "$confirmTime - Elevation attempt failed or cancelled by user."
    }
    exit 0
}

# Get user and computer info
$CurrentUser = $env:USERNAME
$CurrentComputer = $env:COMPUTERNAME

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
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    "$timestamp [$CurrentUser@$CurrentComputer] - $Message" | Tee-Object -FilePath $LogFile -Append
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
Add-Type -AssemblyName PresentationCore,PresentationFramework

$Username = "ssc-localadmin"
$PlainPassword = [System.Web.Security.Membership]::GeneratePassword(20,3)
$Password = $PlainPassword | ConvertTo-SecureString -AsPlainText -Force
try {
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $Username -Password $Password -FullName "Local Administrator" -Description "Decommission local admin account"
        Add-LocalGroupMember -Group "Administrators" -Member $Username
        Log "Created local admin account: $Username"

        # Display password in a popup with option to copy to clipboard
        Set-Clipboard -Value $PlainPassword
        [System.Windows.MessageBox]::Show("Local admin '$Username' password:\n$PlainPassword\n\nPassword has been copied to clipboard.", "Local Admin Password", 'OK', 'Info')
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

Log "Starting Sophos uninstall script..."
$ScriptStartTime = Get-Date

# Check tamper protection status via Sophos registry key
$TamperKey = "HKLM:\\SOFTWARE\\Sophos\\Management\\Policy\\TamperProtection"
$TamperEnabled = $null
if (Test-Path $TamperKey) {
    try {
        $TamperValue = Get-ItemProperty -Path $TamperKey -Name Enabled -ErrorAction Stop
        $TamperEnabled = $TamperValue.Enabled
        if ($TamperEnabled -eq 0) {
            Log "Tamper protection is DISABLED. Proceeding with uninstall."
        } else {
            Log "Tamper protection is ENABLED. Aborting uninstall."
            exit 1
        }
    } catch {
        Log "Error reading tamper protection status: $_"
        exit 1
    }
} else {
    Log "Tamper protection registry key not found. Assuming protection is disabled."
}

# Array of Sophos product display names in recommended uninstall order
$SophosProducts = @(
    "Sophos AutoUpdate",
    "Sophos Network Threat Protection",
    "Sophos Endpoint Defense",
    "Sophos Endpoint Agent",
    "Sophos Anti-Virus"
)

$ActivityName = "Sophos Uninstall"
$ProgressPercent = 0

foreach ($Product in $SophosProducts) {
    Log "Searching for $Product..."
    Write-Progress -Activity $ActivityName -Status "Looking for $Product..." -PercentComplete $ProgressPercent
    $App = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "$Product*" }
    if ($App) {
        Log "Uninstalling $($App.Name)..."
        try {
            $ProgressPercent = 50
            Write-Progress -Activity $ActivityName -Status "Uninstalling $($App.Name)... (Estimated: ~15 seconds remaining)" -PercentComplete $ProgressPercent
            $App.Uninstall() | Out-Null
            $ProgressPercent = 100
            Write-Progress -Activity $ActivityName -Status "Uninstall of $($App.Name) complete." -PercentComplete $ProgressPercent -Completed
            Log "Successfully uninstalled $($App.Name)."
        } catch {
            Write-Progress -Activity $ActivityName -Status "Failed to uninstall $($App.Name)." -PercentComplete $ProgressPercent -Completed
            Log "Failed to uninstall $($App.Name): $_"
        }
    } else {
        Log "$Product not found, skipping."
    }
}

$ScriptEndTime = Get-Date
$TotalDuration = ($ScriptEndTime - $ScriptStartTime).TotalSeconds
Log "Sophos uninstall script completed in $([math]::Round($TotalDuration,1)) seconds."

# ManageEngine Patch Agent Uninstall Script with dynamic progress and summary timing

Log "Starting ManageEngine Patch Agent uninstall script..."
$ScriptStartTime = Get-Date

# Array of common ManageEngine agent product display names
$MEProducts = @(
    "ManageEngine Patch Manager Plus Agent",
    "ManageEngine Endpoint Central Agent",
    "DesktopCentral Agent"
)

$ActivityName = "ManageEngine Uninstall"
$ProgressPercent = 0

foreach ($Product in $MEProducts) {
    Log "Searching for $Product..."
    Write-Progress -Activity $ActivityName -Status "Looking for $Product..." -PercentComplete $ProgressPercent
    $App = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "$Product*" }
    if ($App) {
        Log "Uninstalling $($App.Name)..."
        try {
            $ProgressPercent = 50
            Write-Progress -Activity $ActivityName -Status "Uninstalling $($App.Name)... (Estimated: ~15 seconds remaining)" -PercentComplete $ProgressPercent
            $App.Uninstall() | Out-Null
            $ProgressPercent = 100
            Write-Progress -Activity $ActivityName -Status "Uninstall of $($App.Name) complete." -PercentComplete $ProgressPercent -Completed
            Log "Successfully uninstalled $($App.Name)."
        } catch {
            Write-Progress -Activity $ActivityName -Status "Failed to uninstall $($App.Name)." -PercentComplete $ProgressPercent -Completed
            Log "Failed to uninstall $($App.Name): $_"
        }
    } else {
        Log "$Product not found, skipping."
    }
}

$ScriptEndTime = Get-Date
$TotalDuration = ($ScriptEndTime - $ScriptStartTime).TotalSeconds
Log "ManageEngine Patch Agent uninstall script completed in $([math]::Round($TotalDuration,1)) seconds."

# Elastic Agent Silent Uninstall Script

Log "Starting Elastic Agent uninstall script..."

$ElasticAgentPath = "C:\\Program Files\\Elastic\\Agent\\elastic-agent.exe"

$ProgressActivity = "Elastic Agent Uninstall"
$ProgressPercent = 0
$startTime = Get-Date

if (Test-Path $ElasticAgentPath) {
    Log "Found Elastic Agent. Uninstalling silently..."
    Write-Progress -Activity $ProgressActivity -Status "Starting uninstall... (Estimated: ~30 seconds)" -PercentComplete $ProgressPercent
    try {
        $ProgressPercent = 50
        Write-Progress -Activity $ProgressActivity -Status "Running uninstall command... (Estimated: ~15 seconds remaining)" -PercentComplete $ProgressPercent
        & $ElasticAgentPath uninstall --force
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        $ProgressPercent = 100
        Write-Progress -Activity $ProgressActivity -Status "Uninstall complete. Took $([math]::Round($duration,1)) seconds." -PercentComplete $ProgressPercent -Completed
        Log "Elastic Agent uninstalled successfully in $([math]::Round($duration,1)) seconds."
    } catch {
        Write-Progress -Activity $ProgressActivity -Status "Uninstall failed." -PercentComplete $ProgressPercent -Completed
        Log "Failed to uninstall Elastic Agent: $_"
    }
} else {
    Log "Elastic Agent not found at $ElasticAgentPath, skipping."
}

Log "Elastic Agent uninstall script completed."

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

$reboot = Read-Host "Some changes may require a reboot. Reboot now? (Y/N)"
if ($reboot -eq 'Y') { Restart-Computer -Force }
