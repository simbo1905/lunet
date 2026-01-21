<#
.SYNOPSIS
    Stops all lunet server processes.

.DESCRIPTION
    This script stops all running lunet processes and optionally
    cleans up any process listening on the specified port.

.PARAMETER Port
    Optional port to clean up. Defaults to 8080.

.EXAMPLE
    .\stop.ps1
    .\stop.ps1 -Port 3000
#>

param (
    [int]$Port = 8080
)

Write-Host "Stopping lunet processes..."

# Stop by process name
$processes = Get-Process -Name "lunet" -ErrorAction SilentlyContinue
if ($processes) {
    $processes | ForEach-Object {
        Write-Host "Stopping process ID $($_.Id)..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

# Also clean up any process on the specified port
$netstat = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if ($netstat) {
    $pidToKill = $netstat.OwningProcess
    if ($pidToKill -and $pidToKill -ne 0) {
        Write-Host "Stopping process $pidToKill on port $Port..."
        Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "All lunet processes stopped."
