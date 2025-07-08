# =============================================================================
#
# Script: Instance_Post_Build.ps1
# Description: Interactive script with disclaimer and separate options 
# Author: James Buller.
# Creation Date: Date: 3rd July 2025
# 
# =============================================================================

$logDir = "C:\\Temp\\Install"
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
$logFile = Join-Path $logDir "script_log_$(Get-Date -Format 'ddMMyyyy_HHmmss').txt"
Start-Transcript -Path $logFile -Append | Out-Null

$currentUser = $env:USERNAME
$computerName = $env:COMPUTERNAME

Add-Type -AssemblyName System.Windows.Forms
$disclaimerBox = New-Object System.Windows.Forms.Form
$disclaimerBox.Text = "Disclaimer Agreement"
$disclaimerBox.Width = 500
$disclaimerBox.Height = 300
$label = New-Object System.Windows.Forms.Label
$label.Left = 10; $label.Top = 10; $label.Width = 460; $label.Height = 200
$label.Text = "WARNING: This script makes changes to system and domain settings. By clicking AGREE, you acknowledge you understand the risks. If you do not agree, the script will exit."
$agreeButton = New-Object System.Windows.Forms.Button
$agreeButton.Text = "AGREE"; $agreeButton.Left = 150; $agreeButton.Top = 220; $agreeButton.Add_Click({$disclaimerBox.Tag = 'AGREE'; $disclaimerBox.Close()})
$declineButton = New-Object System.Windows.Forms.Button
$declineButton.Text = "DECLINE"; $declineButton.Left = 250; $declineButton.Top = 220; $declineButton.Add_Click({$disclaimerBox.Tag = 'DECLINE'; $disclaimerBox.Close()})
$disclaimerBox.Controls.AddRange(@($label, $agreeButton, $declineButton))
$disclaimerBox.ShowDialog() | Out-Null

if ($disclaimerBox.Tag -ne 'AGREE') {
    Write-Host "You declined the disclaimer. Exiting script."
    Stop-Transcript | Out-Null
    exit
} else {
    $acceptTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[INFO] Disclaimer accepted at $acceptTime by user $currentUser on computer $computerName"
    Add-Content -Path $logFile -Value "[INFO] Disclaimer accepted at $acceptTime by user $currentUser on computer $computerName"
}
Clear-Host
do {
    Write-Host @"
MAIN MENU:
  1. Join Domain (no reboot)
  2. Run gpupdate (3x with 20s sleep)
  3. Install application (custom block)
  4. View log file
  5. Reboot computer
  Q. Quit script
"@

    $choice = Read-Host "Enter 1, 2, 3, 4, 5, or Q"
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
                Start-Process -FilePath $installer3 -ArgumentList "install --url=https://89486c01198942bd8c8db4c4a196b18b.fleet.eu-west-2.aws.cloud.es.io:443 --enrollment-token=QVIwR1JZa0JiNG1ZYmRpZm9EdGY6WWd3MHJLQVdRS3FpdmM5N3FKNVhkQQ== --proxy-url=http://squid.arvtest.co.uk:3128" -Wait -PassThru | Out-Null
                PAUSE
				Write-Host "[INFO] Completed: Elastic Agent"
				
				# Install of Sysmon:
				Write-Host "[INFO] Installing: Sysmon"
				$installer4 = Join-Path $netlogonPath "\Sysmon\sysmon.exe"
                Start-Process -FilePath $installer4 -ArgumentList "-accepteula -i \\$fqdn\netlogon\Sysmon\sysmonconfig-export.xml" -Wait -PassThru | Out-Null
				Start-Process -FilePath $installer4 -ArgumentList "-accepteula -m" -Wait -PassThru | Out-Null
                Write-Host "[INFO] Completed: Sysmon"
								
				# Add more installers as needed:
                # $installer2 = Join-Path $netlogonPath "anotherapp\\setup.exe"
                # Start-Process -FilePath $installer2 -ArgumentList "/qn" -Wait -PassThru | Out-Null
            } catch {
                Write-Warning "[WARN] Custom installer command failed: $_"
            }
        }
        '4' {
            Write-Host "[INFO] Option 4: View logs"
            $latestLog = Get-ChildItem -Path C:\\Temp\\Install -Filter *.txt | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestLog) {
                Get-Content -Path $latestLog.FullName | Out-Host -Paging
            } else {
                Write-Warning "No log files found in C:\\Temp\\Install."
            }
        }
        '5' {
            Write-Host "[INFO] Option 5: Reboot computer"
            shutdown.exe /r /f /t 60 /d p:2:4 /c "Restart for updates by $currentUser"
        }
        'Q' {
            Write-Host "[INFO] Exiting script. Goodbye."
            Stop-Transcript | Out-Null
            exit
        }
        Default {
            Write-Warning "Invalid option. Please enter 1, 2, 3, 4, 5, or Q."
        }
    }
    Write-Host "Press any key to Return to Main Menu..."
    Pause
    Clear-Host
} while ($true)
