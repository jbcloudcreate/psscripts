#**********************************************************************************
# Powershell Script Functions
#**********************************************************************************

# Function to show Proxy
function Get-InternetProxy
 { 
    $proxies = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').proxyServer
    if ($proxies)
    {
        if ($proxies -ilike "*=*")
        {
            $proxies -replace "=","://" -split(';') | Select-Object -First 1
        }
        else
        {
            "http://" + $proxies
        }
    }    
}
Get-InternetProxy

#Server Pending Reboot (False if not needed)
function Test-PendingReboot {
    if (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -EA Ignore) { return $true }
    if (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -EA Ignore) { return $true }
    if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA Ignore) { return $true }
    try { 
        $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
        $status = $util.DetermineIfRebootPending()
        if (($status -ne $null) -and $status.RebootPending) {
            return $true
        }
    }
    catch { }

    return $false
}

Test-PendingReboot

#**********************************************************************************
# Powershell Script Snippits
#**********************************************************************************

#Get Events for restarts for a system (Saved to Temp folder (Created if needed)
$date = Get-Date -Format "dd-MM-yy"
$logpath = "C:\temp\"
If(!(test-path -PathType container $logpath))
{
      New-Item -ItemType Directory -Path $logpath | out-null
}
Get-WinEvent -FilterHashtable @{logname = 'System'; id = 1074, 6005, 6006, 6008} -MaxEvents 20 | Format-Table -wrap > $logpath\$($date)_events_reboots.txt
ii $logpath

#Get Events for update installs for a system (Saved to Temp folder (Created if needed)
$date = Get-Date -Format "dd-MM-yy"
$logpath = "C:\temp\"
If(!(test-path -PathType container $logpath))
{
      New-Item -ItemType Directory -Path $logpath | out-null
}
Get-WinEvent -FilterHashtable @{logname = 'Setup'; id = 1, 2, 4} -MaxEvents 30 | Format-Table -wrap > $logpath\$($date)_events_updates.txt
ii $logpath

##User Logins
Get-EventLog system -after (get-date).AddDays(-10) | where {$_.InstanceId -eq 7001}

##Get Events for uninstalled applications by person
$date = Get-Date -Format "dd-MM-yy"
$logpath = "C:\temp\"
If(!(test-path -PathType container $logpath))
{
      New-Item -ItemType Directory -Path $logpath | out-null
}
Get-WinEvent -FilterHashtable @{logname = 'Application'; ProviderName = "msiInstaller"; id = 1034, 6005, 6006, 6008} -MaxEvents 20 | Format-Table -wrap > $logpath\$($date)_eventsall.txt
ii $logpath

#Group Policy Results
$date = Get-Date -Format "dd-MM-yy"
$logpath = "C:\gpresult\"
If(!(test-path -PathType container $logpath))
{
      New-Item -ItemType Directory -Path $logpath | out-null
}
gpresult /H $logpath\$($date)_gpresultoutput.html
ii $logpath

# Remove old windows backups
wbadmin delete backup -keepVersions:5

#Computer Last Boot Time
Get-WmiObject win32_operatingsystem | select csname, @{LABEL='LastBootUpTime';EXPRESSION={$_.ConverttoDateTime($_.lastbootuptime)}}

#AD (Get List of Windows 10/11 Machines)
Get-ADComputer -filter {operatingsystem -like "Windows 10*" } -Properties OperatingSystemVersion|select name,OperatingSystemVersion > C:\temp\JamesB\windows10machines.csv

#FSMO Roles
# Get FSMO role status
get-addomain | select InfrastructureMaster, PDCEmulator, RIDMaster 
Get-ADForest | select DomainNamingMaster, SchemaMaster
#or
netdom query fsmo

#Change FSMO Roles
Move-ADDirectoryServerOperationMasterRole -Identity "ARVSSAADC03" RIDMaster
Move-ADDirectoryServerOperationMasterRole -Identity "ARVSSAADC03" Infrastructuremaster

Move-ADDirectoryServerOperationMasterRole -Identity "AWSARVM200" RIDMaster
Move-ADDirectoryServerOperationMasterRole -Identity "AWSARVM200" Infrastructuremaster

Move-ADDirectoryServerOperationMasterRole "AWSARVM101" –OperationMasterRole 0,1,2,3,4
Move-ADDirectoryServerOperationMasterRole -Identity "ARVSSAADC04" –OperationMasterRole DomainNamingMaster,PDCEmulator,RIDMaster,SchemaMaster,InfrastructureMaster


# Users that need to be removed due to no login for 6+ Months
Import-Module ActiveDirectory -EA Stop
$DateCutOff=(Get-Date).AddDays(-200)
$DisabledOU="OU=Disabled Users,OU=Users Accounts,OU=SSA - Migration,DC=ssc,DC=dftssc,DC=gsi,DC=gov,DC=uk"
Get-AdUser -Filter * -SearchBase $DisabledOU -Property whenChanged,lastlogondate | Where {$_.whenChanged -gt $DateCutOff} | Sort-Object -descending whenChanged | FT GivenName,Surname,Enabled,lastlogondate -auto #> C:\temp\HS_Mobilise_DA.txt

# Who has H Drives
Get-ADUser -Filter 'enabled -eq $true' -Properties ProfilePath, HomeDirectory, HomeDrive | Select Name, SamAccountName, ProfilePath, HomeDirectory, HomeDrive | Export-Csv -path "c:\temp\hdrive_userlist.csv"

# Remove H Drives from CSV users
# 1. Import the user data from CSV
$UserList = Import-Csv -Path C:\temp\usernames_removehomedirectory_corp_etc.csv;
# 2. For each user ...
foreach ($User in $UserList) {
    # 2a. Get the user's AD account
    $Account = Get-ADUser -LDAPFilter ('(&(displayname={0}))' -f $User.DisplayName);
    # 2b. Set their home directory and home drive letter in Active Directory
    Set-ADUser -Identity $Account.SamAccountName -HomeDirectory $null -HomeDrive $null;
}

#Display names to Usernames (SamAccountName)
Get-Content 'C:\temp\usernames_batch.txt' | 
    ForEach-Object {
        $name = $_
        $adUser = Get-ADUser -Filter "DisplayName -eq '$name'"

        # Create object for every user in users.csv even if Get-ADUser returns nothing
        [PSCustomObject]@{
            DisplayName    = $name                     # this will be populated with name from the csv file
            SamAccountName = $adUser.SamAccountName    # this will be empty if $adUser is empty
        }
    } | Export-Csv 'C:\temp\usernames_batch_output.csv'

#Get Installed Programs
get-wmiobject Win32_Product | Sort-Object -Property Name |Format-Table IdentifyingNumber, Name, LocalPackage -AutoSize > C:\temp\installedprograms.csv

#or

$Installer = New-Object -ComObject WindowsInstaller.Installer; $InstallerProducts = $Installer.ProductsEx("", "", 7); $InstalledProducts = ForEach($Product in $InstallerProducts){[PSCustomObject]@{ProductCode = $Product.ProductCode(); LocalPackage = $Product.InstallProperty("LocalPackage"); VersionString = $Product.InstallProperty("VersionString"); ProductPath = $Product.InstallProperty("ProductName")}} $InstalledProducts

# Output Computername
$env:computername

# Restart Server with Comment (event viewer audit)
shutdown.exe /r /f /t 0 /d p:2:4 /c "Restart for updates by James Buller"
# Shutdown in 12 hours with Comment (event viewer audit)
shutdown /r /f /t 43200 /d p:2:4 /c "Restart for updates by James Buller"
# Shutdown in 5 hours with Comment (event viewer audit)
shutdown /r /f /t 18000 /d p:2:4 /c "Restart for updates by James Buller"

# Check for updates on a machine
$date = Get-Date -Format "dd-MM-yy"
$logpath = "C:\temp\updates\"
If(!(test-path -PathType container $logpath))
{
      New-Item -ItemType Directory -Path $logpath | out-null
}
$KB = "KB5014633"
Clear-Host
Get-HotFix -Id $KB 
Get-HotFix -Id $KB > $logpath\$($date)_$($KB).txt
Write-Host "Log has been outputted"
ii $logpath

# Disable TLS 1.0
New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force | Out-Null
New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client' -name 'Enabled' -value '0' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client' -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force | Out-Null
Write-Host 'TLS 1.0 has been disabled.'

# Disable TLS 1.2
New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -name 'Enabled' -value '1' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -name 'DisabledByDefault' -value 0 -PropertyType 'DWord' -Force | Out-Null
New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -name 'Enabled' -value '1' -PropertyType 'DWord' -Force | Out-Null
New-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -name 'DisabledByDefault' -value 0 -PropertyType 'DWord' -Force | Out-Null
Write-Host 'TLS 1.2 has been enabled.'

# Monthly DA Review
C:\PowerShellScripts\domainappsadminfinder.ps1

# Get all certificates from the store
Get-ChildItem -Path Cert:\LocalMachine\My\ | Select Thumbprint,NotAfter,SerialNumber,Subject

# Install .Net3.5 Fix (Manage Engine)
# Copy the SXS folder from a Windows 2016 / 2019 ISO and add it the problematic machine and run the 
# folling command as an administrator // restart // Install the missing patch // restart and rescan (ME)
DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:\\ssc.dftssc.gsi.gov.uk\NETLOGON\dotnet35fix\WS2016\sxs

#Get Domain Name
$DomainShortName = ((Get-WmiObject Win32_ComputerSystem).Domain).Split(".")[0]

#Extract GPOs
Get-GPO -All | Export-Csv -Path "C:\temp\AllGPOs.csv -NoTypeInformation"

# Retrieve all GPOs (not all GPO Reports!)
$AllGpos = Get-GPO -All
# Create a custom object holding all the information for each GPO component Version and Enabled state
$GpoVersionInfo = foreach ($g in $AllGpos) {
    [xml]$Gpo = Get-GPOReport -ReportType Xml -Guid $g.Id
    [PSCustomObject]@{
        "Name" = $Gpo.GPO.Name
        "Comp-Ad" = $Gpo.GPO.Computer.VersionDirectory
        "Comp-Sys" = $Gpo.GPO.Computer.VersionSysvol
        "Comp Ena" = $Gpo.GPO.Computer.Enabled
        "User-Ad" = $Gpo.GPO.User.VersionDirectory
        "User-Sys" = $Gpo.GPO.User.VersionSysvol
        "User Ena" = $Gpo.GPO.User.Enabled
    }
}
# See the result
$GpoVersionInfo | Sort-Object Name | Format-Table -AutoSize -Wrap

# Output GPO's in HTML Format
# Individial

$allgpos = Get-GPO -All | Select-Object -ExpandProperty DisplayName
foreach ($g in $allgpos) {
    Get-GPOReport -Name $g -ReportType HTML -Path C:\temp\$g.html
}

# All

Get-GPOReport -All -Domain "SSC.DFTSSC.GSI.GOV.UK" -ReportType HTML -Path C:\temp\allgporeports.html

# Spec OU

# Specify the OUs we’re interested in
$OU = “OU=Staging,DC=ssc,DC=dftssc,DC=gsi,DC=gov,DC=uk”

$logpath = "C:\temp\GPO\Staging\"
If(!(test-path -PathType container $logpath))
{
      New-Item -ItemType Directory -Path $logpath | out-null
}

# Get GPOs applied to the OUs
$GPOs = Get-GPInheritance -Target "$OU" | Select-object -ExpandProperty InheritedGpoLinks

# Loop through the applied GPOs
foreach ($GPO in $GPOs) {
$Name = $GPO.DisplayName
Get-GPOReport -Name $Name -ReportType HTML -Path $logpath\$Name.html
}

#Backup and List GPO outputs and UnLinkedGPOs (can removed UnLinkedGPOs if comment removed)
Import-Module GroupPolicy
$Date = Get-Date -Format dd_MM_yyyy
$BackupPath = "c:\temp\GPOBackup\$Date"
if (-Not(Test-Path -Path $BackupPath)) 
{ New-Item -ItemType Directory $BackupPath -Force}
Get-GPO -All | Sort-Object displayname | Where-Object { If ( $_ | Get-GPOReport -ReportType XML | Select-String -NotMatch "<LinksTo>" )
 {
   Backup-GPO -Name $_.DisplayName -Path $BackupPath
   Get-GPOReport -Name $_.DisplayName -ReportType Html -Path "c:\temp\GPOBackup\$Date\$($_.DisplayName).html"
   $_.DisplayName | Out-File "c:\temp\GPOBackup\$Date\UnLinkedGPOs.txt" -Append
   #$_.Displayname | remove-gpo -Confirm
   }
}

#GPUpdate Commands
gpupdate /Target:Computer /force

gpresult /SCOPE:COMPUTER /r


Uninstall-WindowsFeature -Name Windows-Defender -Restart

Get-MpComputerStatus | select AntivirusEnabled

netsh winhttp show proxy

netsh winhttp reset proxy
