# DC Demotion Readiness Script - PDQ-Safe + Extended Checks + Logging
# Date: August 2025

$NewDCs = @("AWSARVM202", "AWSARVM203")  # New DCs to validate
$PortsToCheck = @(389, 88)               # LDAP & Kerberos
$LogFile = "\\nonprod.sharedservicesarvato.gsi.co.uk\NETLOGON\Logs\2025_domain_readiness2.txt"

$Result = [PSCustomObject]@{
    ServerName         = $env:COMPUTERNAME
    Timestamp          = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DNSAddresses       = $null
    SecureChannelOK    = $null
    ReachableDCs       = @()
    AD_Site            = $null
    DiscoveredDC       = $null
    TimeSource         = $null
    GPO_OK             = $null
    Issues             = @()
}

Write-Host "🔍 Checking DC connectivity status for: $($Result.ServerName)" -ForegroundColor Cyan

# 1. DNS Server Configuration
try {
    $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses
    $Result.DNSAddresses = $dnsServers -join ", "
} catch {
    $Result.Issues += "Failed to get DNS settings."
}

# 2. Secure Channel Check
try {
    if (Test-ComputerSecureChannel -Verbose:$false) {
        $Result.SecureChannelOK = $true
    } else {
        $Result.SecureChannelOK = $false
        $Result.Issues += "Secure channel to domain is broken."
    }
} catch {
    $Result.Issues += "Secure channel test failed."
}

# 3. Check TCP Port Connectivity to New DCs
foreach ($dc in $NewDCs) {
    $allPortsReachable = $true
    foreach ($port in $PortsToCheck) {
        $check = Test-NetConnection -ComputerName $dc -Port $port -InformationLevel Quiet
        if (-not $check) {
            $allPortsReachable = $false
            $Result.Issues += "Cannot connect to $dc on TCP port $port"
        }
    }
    if ($allPortsReachable) {
        $Result.ReachableDCs += $dc
    }
}

# 4. AD Site Check
try {
    $siteName = nltest /dsgetsite 2>&1
    $Result.AD_Site = $siteName.Trim()
} catch {
    $Result.Issues += "Failed to determine AD Site."
}

# 5. DC Discovery Check
try {
    $dcInfo = nltest /dsgetdc:$env:USERDNSDOMAIN 2>&1 | Out-String
    if ($dcInfo -match "DC: (.+)") {
        $Result.DiscoveredDC = $matches[1].Trim()
    } else {
        $Result.DiscoveredDC = "Unavailable"
        $Result.Issues += "Could not discover DC using nltest."
    }
} catch {
    $Result.Issues += "Failed to run DC discovery check."
}

# 6. Time Source Check
try {
    $timeSource = w32tm /query /source 2>&1
    $Result.TimeSource = $timeSource.Trim()
} catch {
    $Result.Issues += "Failed to get time source."
}

# 7. GPO Health Check (optional)
try {
    $gpoOutput = gpresult /r /scope:computer 2>&1 | Out-String
    if ($gpoOutput -match "Group Policy was applied") {
        $Result.GPO_OK = $true
    } else {
        $Result.GPO_OK = $false
        $Result.Issues += "Group Policy may not be applying correctly."
    }
} catch {
    $Result.GPO_OK = $false
    $Result.Issues += "Failed to check GPO status."
}

# 8. Console Output
Write-Host "`n📋 Summary for: $($Result.ServerName)" -ForegroundColor Green
Write-Host "DNS Servers:         $($Result.DNSAddresses)"
Write-Host "Secure Channel OK:   $($Result.SecureChannelOK)"
Write-Host "Reachable New DCs:   $($Result.ReachableDCs -join ', ')"
Write-Host "AD Site:             $($Result.AD_Site)"
Write-Host "Discovered DC:       $($Result.DiscoveredDC)"
Write-Host "Time Source:         $($Result.TimeSource)"
Write-Host "GPO Applied OK:      $($Result.GPO_OK)"

if ($Result.Issues.Count -eq 0) {
    Write-Host "`n✅ No issues detected. Server appears ready for DC change." -ForegroundColor Green
} else {
    Write-Host "`n⚠️ Issues Detected:" -ForegroundColor Yellow
    foreach ($issue in $Result.Issues) {
        Write-Host " - $issue" -ForegroundColor Yellow
    }
}

# 9. Append to Netlogon Log
try {
    $logEntry = @()
    $logEntry += "============================================================"
    $logEntry += "Timestamp:         $($Result.Timestamp)"
    $logEntry += "Server Name:       $($Result.ServerName)"
    $logEntry += "DNS Servers:       $($Result.DNSAddresses)"
    $logEntry += "Secure Channel OK: $($Result.SecureChannelOK)"
    $logEntry += "Reachable DCs:     $($Result.ReachableDCs -join ', ')"
    $logEntry += "AD Site:           $($Result.AD_Site)"
    $logEntry += "Discovered DC:     $($Result.DiscoveredDC)"
    $logEntry += "Time Source:       $($Result.TimeSource)"
    $logEntry += "GPO Applied OK:    $($Result.GPO_OK)"
    if ($Result.Issues.Count -eq 0) {
        $logEntry += "Issues:            None"
    } else {
        $logEntry += "Issues:"
        foreach ($issue in $Result.Issues) {
            $logEntry += "  - $issue"
        }
    }
    $logEntry += ""

    Add-Content -Path $LogFile -Value $logEntry
    Write-Host "`n📝 Log entry appended to: $LogFile" -ForegroundColor Cyan
} catch {
    Write-Host "`n❌ Failed to write to log file: $_" -ForegroundColor Red
}

# 10. PDQ Exit Code
if ($Result.Issues.Count -eq 0) {
    exit 0
} else {
    exit 1
}
