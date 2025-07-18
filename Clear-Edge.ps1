# File: Clear-Edge.ps1

# Ensure Edge is closed
Write-Host "Closing Microsoft Edge..."
Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue

# Set Edge profile path
$edgeProfile = "$env:LocalAppData\Microsoft\Edge\User Data\Default"

# Check if path exists
if (-Not (Test-Path $edgeProfile)) {
    Write-Host "Edge profile not found at: $edgeProfile"
    exit 1
}

# List of files to delete
$filesToDelete = @(
    "Cookies",
    "History",
    "History-journal",
    "Network Persistent State",
    "Visited Links",
    "Session Storage",
    "Web Data",
    "Web Data-journal"
)

# List of directories to clean
$dirsToDelete = @(
    "Cache",
    "Code Cache",
    "GPUCache",
    "Session Storage",
    "Storage",
    "IndexedDB",
    "Local Storage",
    "Service Worker",
    "File System",
    "databases"
)

# Delete files
foreach ($file in $filesToDelete) {
    $fullPath = Join-Path $edgeProfile $file
    if (Test-Path $fullPath) {
        Remove-Item $fullPath -Force -ErrorAction SilentlyContinue
        Write-Host "Deleted file: $file"
    }
}

# Delete folders
foreach ($dir in $dirsToDelete) {
    $fullPath = Join-Path $edgeProfile $dir
    if (Test-Path $fullPath) {
        Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Deleted folder: $dir"
    }
}

Write-Host "`nEdge history and cookies cleaned."
