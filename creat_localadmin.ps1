# Prompt for secure password input
$securePassword = Read-Host "Enter password for local admin user" -AsSecureString
$Username = "ssc-localadmin"
$Group = "Administrators"

# Define log file path and ensure directory exists
$logDir = "C:\temp"
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
$logFile = "$logDir\local_admin_setup.log"

function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Output $message
}

try {
    # Check if user exists
    $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

    if (-not $existingUser) {
        Write-Log "Creating new local user '$Username'."
        New-LocalUser -Name $Username -Password $securePassword -FullName "Local Admin User" -PasswordNeverExpires -UserMayNotChangePassword
    }
    else {
        Write-Log "User '$Username' already exists. Updating password."
        $existingUser | Set-LocalUser -Password $securePassword
    }

    # Add to Administrators group
    Write-Log "Adding '$Username' to local '$Group' group."
    Add-LocalGroupMember -Group $Group -Member $Username -ErrorAction Stop

} catch {
    Write-Log "Failed to create or configure local user: $_"
    exit 1
}

# Confirm before removing from domain
$confirmation = Read-Host "Do you really want to unjoin this computer from the domain? Type YES to continue"
if ($confirmation -eq "YES") {
    try {
        $domainCred = Get-Credential -Message "Enter domain admin credentials for unjoin"
        Write-Log "Initiating domain unjoin."
        Remove-Computer -UnjoinDomainCredential $domainCred -PassThru -Verbose -Restart -Force
    } catch {
        Write-Log "Failed to unjoin domain: $_"
    }
} else {
    Write-Log "Domain unjoin aborted by user."
}
