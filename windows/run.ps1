<#
.SYNOPSIS
    Starts the lunet server for Windows.

.DESCRIPTION
    This script starts the lunet server, manages logging, and waits for the
    server to be ready on port 8080. It handles cleanup of existing processes.

.PARAMETER LuaFile
    The Lua file to run. Defaults to "app/main.lua".

.PARAMETER BuildConfig
    The build configuration (Debug or Release). Defaults to "Debug".

.PARAMETER Port
    The port to listen on. Defaults to 8080.

.EXAMPLE
    .\run.ps1
    .\run.ps1 -LuaFile "app/main.lua" -BuildConfig "Release"
#>

param (
    [string]$LuaFile = "app/main.lua",
    [string]$BuildConfig = "Debug",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Ensure .tmp directory exists
# =============================================================================
if (-not (Test-Path ".tmp")) {
    New-Item -ItemType Directory -Path ".tmp" | Out-Null
}

# =============================================================================
# Kill existing process on the specified port
# =============================================================================
Write-Host "Checking for existing process on port $Port..."
$netstat = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if ($netstat) {
    $pidToKill = $netstat.OwningProcess
    Write-Host "Killing process $pidToKill listening on port $Port..."
    Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

# =============================================================================
# Setup logging
# =============================================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$logDir = ".tmp/logs/$timestamp"
New-Item -ItemType Directory -Path $logDir | Out-Null
$logFile = "$logDir/server.log"
$pidFile = "$logDir/server.pid"

Write-Host "Logs will be written to $logDir"

# =============================================================================
# Locate and start the server
# =============================================================================
$exePath = "build\$BuildConfig\lunet.exe"
if (-not (Test-Path $exePath)) {
    # Try alternative path
    $exePath = "build\lunet.exe"
    if (-not (Test-Path $exePath)) {
        Write-Error "Executable not found. Tried build\$BuildConfig\lunet.exe and build\lunet.exe"
        exit 1
    }
}

Write-Host "Starting $exePath $LuaFile..."

# Use System.Diagnostics.Process for robust background execution with logging
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Resolve-Path $exePath
$psi.Arguments = $LuaFile
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = Get-Location

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi

# Global variable for event handler access
$Global:ServerLogFile = $logFile

# Event handlers for async logging
$outputHandler = { 
    param($sender, $e) 
    if ($e.Data) { 
        Add-Content -Path $Global:ServerLogFile -Value $e.Data 
    } 
}

Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $outputHandler | Out-Null
Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $outputHandler | Out-Null

$process.Start() | Out-Null
$process.BeginOutputReadLine()
$process.BeginErrorReadLine()

$process.Id | Out-File -FilePath $pidFile -Encoding ascii
Write-Host "Server started with PID $($process.Id)"

# =============================================================================
# Wait for server to be ready
# =============================================================================
Write-Host "Waiting for port $Port to open..."
$retries = 0
$maxRetries = 30
$started = $false

while ($retries -lt $maxRetries) {
    Start-Sleep -Milliseconds 500
    
    if ($process.HasExited) {
        Write-Host "Server process exited prematurely with exit code $($process.ExitCode)"
        if (Test-Path $logFile) {
            Write-Host "=== Server Log ==="
            Get-Content $logFile | Write-Host
        }
        exit 1
    }

    $conns = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($conns -and ($conns.State -contains 'Listen')) {
        Write-Host "Server is LISTENING on port $Port."
        $started = $true
        break
    }
    $retries++
}

if (-not $started) {
    Write-Host "Timed out waiting for port $Port after $($maxRetries * 0.5) seconds."
    if (Test-Path $logFile) {
        Write-Host "=== Server Log ==="
        Get-Content $logFile | Write-Host
    }
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Server is ready!"
