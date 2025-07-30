<#
.SYNOPSIS
    Checks current Forest and Domain Functional Levels and all DC OS versions.
.DESCRIPTION
    This script reports:
    - Current forest and domain functional levels
    - Operating systems of all domain controllers
    - Compatibility with Windows Server 2025 promotion
.NOTES
    Run as a domain admin on any domain-joined machine.
#>

Write-Host "🔍 Checking Active Directory Functional Levels and DC Compatibility..." -ForegroundColor Cyan

$forest = Get-ADForest
$domain = Get-ADDomain
$dcs = Get-ADDomainController -Filter * | Select-Object Name,OperatingSystem,IPv4Address

Write-Host "`nForest Functional Level:`t$($forest.ForestMode)"
Write-Host "Domain Functional Level:`t$($domain.DomainMode)"
Write-Host "`Domain Controllers in the Forest:" -ForegroundColor Yellow
$dcs | Format-Table -AutoSize

# Interpret forest level
$supportedLevels = @("Windows2016Forest", "Windows2019Forest", "Windows2022Forest", "Windows2025Forest")
if ($supportedLevels -contains $forest.ForestMode.ToString()) {
    Write-Host "Forest level is sufficient for Windows Server 2025 domain controllers." -ForegroundColor Green
} else {
    Write-Host "Forest level is too low for Windows Server 2025 domain controllers." -ForegroundColor Red
    Write-Host "   Required: Windows Server 2016 or higher." -ForegroundColor Red
}

# Interpret domain level
if ($supportedLevels -contains $domain.DomainMode.ToString()) {
    Write-Host "Domain level is sufficient for Windows Server 2025 domain controllers." -ForegroundColor Green
} else {
    Write-Host "Domain level may also need raising (Windows Server 2016 or higher recommended)." -ForegroundColor Red
}

Write-Host "This script performs no changes. To raise the levels, use Set-ADForestMode and Set-ADDomainMode." -ForegroundColor Cyan
