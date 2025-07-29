# =============================================================================
#
# Script: Instance_Post_Build.ps1
# Description: Interactive script with disclaimer and separate options 
# Author: James Buller.
# Creation Date: Date: 3rd July 2025
# 
# Version: 4.0 - Modernized UI & Structure
#
# =============================================================================

# --- Logging Setup ---
$logDir = "C:\\Temp\\Install"
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
$logFile = Join-Path $logDir "script_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Start-Transcript -Path $logFile -Append | Out-Null

$currentUser = $env:USERNAME
$computerName = $env:COMPUTERNAME

# --- Disclaimer UI ---

# --- Disclaimer UI ---
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = "Disclaimer Agreement"
$form.Size = New-Object System.Drawing.Size(500, 300)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Size = New-Object System.Drawing.Size(460, 180)
$label.Location = New-Object System.Drawing.Point(10,10)
$label.Text = "WARNING: This script will make changes to the system.\n\nClick AGREE to continue or DECLINE to exit."

$agree = New-Object System.Windows.Forms.Button
$agree.Text = "AGREE"
$agree.Location = New-Object System.Drawing.Point(120, 200)
$agree.Add_Click({ $form.Tag = 'AGREE'; $form.Close() })

$decline = New-Object System.Windows.Forms.Button
$decline.Text = "DECLINE"
$decline.Location = New-Object System.Drawing.Point(240, 200)
$decline.Add_Click({ $form.Tag = 'DECLINE'; $form.Close() })

$form.Controls.AddRange(@($label, $agree, $decline))
$form.ShowDialog() | Out-Null

if ($form.Tag -ne 'AGREE') {
    Write-Host "[INFO] Disclaimer not accepted. Exiting..."
    Stop-Transcript | Out-Null
    exit
}

Write-Host "[INFO] Disclaimer accepted by $currentUser on $computerName at $(Get-Date)"

# --- Main Menu Loop ---

do {
    Clear-Host
    Write-Host @"
====================================
ICT Infrastructure Post-Build Menu
====================================
 1. Join Domain
 2. Run Gpupdate
 3. Install Applications
 4. Set Locale, Time & Region
 5. Reboot System
 Q. Quit Script
"@

    $choice = Read-Host "Select an option (1-5 or Q)"
    switch ($choice) {
        '1' {
            Write-Host "Please remember to set the DNS servers and suffix addresses in the adaptor settings before continuing"
            Write-Host "[INFO] Option 1: Domain Join"
            $newComputerName = Read-Host "Enter the new computer name"
            $domainName = Read-Host "Enter the domain name (e.g., ssc.dftssc.gsi.gov.uk)"
            $domainUser = Read-Host "Enter the domain user (e.g., ssc\\admin account)"

            Add-Type -AssemblyName System.Windows.Forms
            $passwordBox = New-Object System.Windows.Forms.Form
            $passwordBox.Text = "Enter Domain Password"
            $passwordBox.Width = 300
            $passwordBox.Height = 150
            $passwordLabel = New-Object System.Windows.Forms.Label
            $passwordLabel.Left = 10; $passwordLabel.Top = 20; $passwordLabel.Text = "Password:"
            $passwordInput = New-Object System.Windows.Forms.TextBox
            $passwordInput.Left = 80; $passwordInput.Top = 18; $passwordInput.Width = 180
            $passwordInput.UseSystemPasswordChar = $true
            $okButton = New-Object System.Windows.Forms.Button
            $okButton.Text = "OK"; $okButton.Left = 110; $okButton.Top = 60; $okButton.Add_Click({$passwordBox.Close()})
            $passwordBox.Controls.AddRange(@($passwordLabel, $passwordInput, $okButton))
            $passwordBox.ShowDialog() | Out-Null
            $securePassword = ConvertTo-SecureString $passwordInput.Text -AsPlainText -Force

            $credential = New-Object System.Management.Automation.PSCredential($domainUser, $securePassword)

            try {
                [System.Net.Dns]::GetHostEntry($domainName) | Out-Null
                Add-Computer -DomainName $domainName -NewName $newComputerName -Credential $credential -Force
                Write-Host "[INFO] Joined domain successfully without reboot."
            } catch {
                Write-Error "[ERROR] Failed to join domain: $_"
            }
        }
        '2' {
            Write-Host "[INFO] Option 2: Gpupdate 3x with 20s sleep"
            for ($i=1; $i -le 3; $i++) {
                gpupdate /force | Out-Null
                Write-Host "[INFO] Completed gpupdate attempt $i. Sleeping 20s..."
                Start-Sleep -Seconds 20
            }
			gpresult /SCOPE:COMPUTER /r
            Write-Host "[INFO] Gpupdate sequence complete."
        }
        '3' {
            Write-Host "[INFO] Option 3: Custom installer block"
            try {
                # Automatically detect domain FQDN
                $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                $fqdn = $domain.Name
                $netlogonPath = "\\$fqdn\netlogon\"
                Write-Host "[INFO] Using Netlogon path: $netlogonPath"

                # Manage Engine Installer (Silent):
				Write-Host "[INFO] Installing: Manage Engine Agent"
                $installer1 = Join-Path $netlogonPath "\ManageEngine\Install\LocalOffice_Agent.exe"
                Start-Process -FilePath $installer1 -ArgumentList "/silent" -Wait -PassThru | Out-Null
                Write-Host "[INFO] Completed: Manage Engine Agent"
				# Correct location in all domains

                # Sophos Installer (Silent):
				Write-Host "[INFO] Installing: Sophos"
                $installer2 = Join-Path $netlogonPath "\Sophos\SophosSetup.exe"
                Start-Process -FilePath $installer2 -ArgumentList "--messagerelays=10.8.3.4:8190,10.8.3.36:8190" -Wait -PassThru | Out-Null
                Write-Host "[INFO] Completed: Sophos"
				
				# Elastic Installer (Prompts) :
				Write-Host "[INFO] Installing: Elastic Agent"
                $installer3 = Join-Path $netlogonPath "\Elastic\elastic-agent.exe"
                & $installer3 install --url=https://89486c01198942bd8c8db4c4a196b18b.fleet.eu-west-2.aws.cloud.es.io:443 `
				--enrollment-token=QVIwR1JZa0JiNG1ZYmRpZm9EdGY6WWd3MHJLQVdRS3FpdmM5N3FKNVhkQQ== `
				--proxy-url=http://squid.arvtest.co.uk:3128

				Write-Host "[INFO] Completed: Elastic Agent"
				
				# Install of Sysmon:
				Write-Host "[INFO] Installing: Sysmon"
				$installer4 = Join-Path $netlogonPath "\Sysmon\sysmon.exe"
				& $installer4 -accepteula -i "\\$fqdn\netlogon\Sysmon\sysmonconfig-export.xml"
				& $installer4 -accepteula -m
				Write-Host "[INFO] Completed: Sysmon"
				
				# Remove Windows Defender
				"[INFO] Un-installing: Windows Defender"
				try {
					$defender = Get-WindowsFeature -Name Windows-Defender
					if ($defender.Installed) {
						Write-Host "[INFO] Windows Defender is installed. Uninstalling..."
						Uninstall-WindowsFeature -Name Windows-Defender -Remove -Verbose
					} else {
						Write-Host "[INFO] Windows Defender is NOT installed. Skipping removal."
					}
				} catch {
					Write-Error "[ERROR] Failed to check or uninstall Defender: $_"
				}
				
				# Add more installers as needed:
                # $installer2 = Join-Path $netlogonPath "anotherapp\\setup.exe"
                # Start-Process -FilePath $installer2 -ArgumentList "/qn" -Wait -PassThru | Out-Null
            } catch {
                Write-Warning "[WARN] Custom installer command failed: $_"
            }
        }
        '4' {
            Write-Host "[INFO] Option 4: Set Time, Region, and Language Settings"
            try {
                Write-Output "Setting system locale to en-GB..."
                Set-WinSystemLocale -SystemLocale en-GB
                Write-Output "System locale set to: $(Get-WinSystemLocale)"

                Write-Output "Setting culture to en-GB..."
                Set-Culture -CultureInfo en-GB
                Write-Output "Culture set to: $(Get-Culture)"

                Write-Output "Setting home location to United Kingdom (GeoID 242)..."
                Set-WinHomeLocation -GeoId 242
                Write-Output "Home location set to GeoID: $(Get-WinHomeLocation)"

                Write-Output "Setting time zone to GMT Standard Time..."
                Set-TimeZone -Id "GMT Standard Time"
                Write-Output "Time zone set to: $(Get-TimeZone).Id"

                Write-Output "All settings have been applied successfully."
            } catch {
                Write-Error "[ERROR] Failed to apply regional settings: $_"
            }
        }
        '5' {
            Write-Host "[INFO] Option 5: Reboot computer"
            shutdown.exe /r /f /t 60 /d p:2:4 /c "Restart for updates by $currentUser"
        }
        'Q' {
            Write-Host "[INFO] Exiting..."
            Stop-Transcript | Out-Null
            break
        }
        Default {
            Write-Warning "IInvalid choice. Please select 1-5 or Q."
        }
    }
    if ($choice -ne 'Q') {
        Write-Host "\nPress Enter to return to menu..."
        [void][System.Console]::ReadKey($true)
    }
} while ($true)
