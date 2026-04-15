<#
.SYNOPSIS
    Simple installation checker and starter for Blocklist Function App onboarding.
#>

[CmdletBinding()]
param(
    # Max seconds to allow a winget command before we kill/retry it
    [int]$WingetTimeoutSec = 180,
    # Warm-up timeout (source update/list); lets you shorten or extend priming time separately
    [int]$WingetWarmupTimeoutSec = 10,
    # Reduce noise from winget retries/timeouts
    [switch]$QuietWinget = $true,
    # Max retries when Windows Installer is busy (exit code 1618)
    [int]$WingetBusyRetryCount = 3,
    # Seconds to wait between retries when installer is busy
    [int]$WingetBusyRetryDelaySec = 15
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
$script:WingetTimeoutSec = $WingetTimeoutSec
$script:WingetWarmupTimeoutSec = $WingetWarmupTimeoutSec
$script:QuietWinget = $QuietWinget
$script:WingetBusyRetryCount = $WingetBusyRetryCount
$script:WingetBusyRetryDelaySec = $WingetBusyRetryDelaySec
$script:WingetInitialized = $false

$loggingHelper = Join-Path $root 'Logging.ps1'
if (Test-Path $loggingHelper) {
    . $loggingHelper
    $script:LogFilePath = Start-BlocklistLogging -ForceNew -Prefix 'BlocklistFunctionApp-Start'
    Write-Host "Logging (Start) to: $script:LogFilePath" -ForegroundColor Cyan
} else {
    Write-Warning "Logging helper not found at $loggingHelper. Proceeding without transcript logging."
}

function Stop-LoggingAndExit {
    param([int]$Code)
    if (Get-Command -Name Stop-BlocklistLogging -ErrorAction SilentlyContinue) {
        try { Stop-BlocklistLogging } catch { }
    }
    exit $Code
}

Write-Host ""
Write-Host "=== Helse- og KommuneCERT Blocklist Function App Setup ===" -ForegroundColor Cyan
Write-Host "Checking prerequisites..." -ForegroundColor Cyan
Write-Host ""

# --- Helpers ------------------------------------------------------------------

function Test-Cmd {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Write-WingetRetryNotice {
    param(
        [Parameter(Mandatory)][string]$Args,
        [Parameter(Mandatory)][int]$RetryTimeoutSec
    )
    $msg = "winget timed out: winget $Args. Retrying (attempt 2) after source update with timeout ${RetryTimeoutSec}s..."
    if ($script:QuietWinget) {
        Write-Host "Pending Winget... retrying (attempt 2)." -ForegroundColor Yellow
        Write-Verbose $msg
    } else {
        Write-Warning $msg
    }
}

function Write-WingetWarmupNotice {
    param([Parameter(Mandatory)][string]$Message)
    if ($script:QuietWinget) {
        Write-Host "Pending Winget... continuing." -ForegroundColor Yellow
        Write-Verbose $Message
    } else {
        Write-Warning $Message
    }
}

function Test-WingetAlreadyInstalled {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Output
    )
    if ($ExitCode -eq -1978335189) { return $true }
    if ($Output -match 'Found an existing package already installed') { return $true }
    if ($Output -match 'No available upgrade found') { return $true }
    if ($Output -match 'No newer package versions are available') { return $true }
    return $false
}

function Test-WingetInstallerBusy {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Output
    )
    # Exit code 1618 = ERROR_INSTALL_ALREADY_RUNNING (Windows Installer is busy)
    if ($ExitCode -eq 1618) { return $true }
    if ($Output -match 'Another installation is already in progress') { return $true }
    return $false
}

function Invoke-WingetCommand {
    param(
        [Parameter(Mandatory)][string]$Args,   # include subcommand, e.g. "install --id Microsoft.PowerShell --exact --silent"
        [int]$TimeoutSec = $script:WingetTimeoutSec,
        [switch]$AddAcceptSource,
        [switch]$AddAcceptPackage,
        [switch]$DisableInteractivity = $true,
        [switch]$AllowHangRetry,
        [int]$RetryCount = 0,
        [int]$BusyRetryCount = $script:WingetBusyRetryCount
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = "winget.exe"
    $flags = @()
    if ($DisableInteractivity) { $flags += "--disable-interactivity" }
    if ($AddAcceptSource)      { $flags += "--accept-source-agreements" }
    if ($AddAcceptPackage)     { $flags += "--accept-package-agreements" }
    $flagString = if($flags.Count -gt 0){ ' ' + ($flags -join ' ') } else { '' }
    $psi.Arguments = "$Args$flagString"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        if ($AllowHangRetry -and $RetryCount -lt 1) {
            $retryTimeout = [Math]::Min([Math]::Max($TimeoutSec + 30, 60), 240)
            $updateTimeout = [Math]::Min([Math]::Max([Math]::Floor($TimeoutSec / 2), 10), 30)
            Write-WingetRetryNotice -Args $psi.Arguments -RetryTimeoutSec $retryTimeout
            try { Invoke-WingetCommand -Args "source update --name winget" -TimeoutSec $updateTimeout -DisableInteractivity | Out-Null }
            catch { try { Invoke-WingetCommand -Args "source update" -TimeoutSec $updateTimeout -DisableInteractivity | Out-Null } catch {} }
            return Invoke-WingetCommand -Args $Args -TimeoutSec $retryTimeout -AddAcceptSource:$AddAcceptSource -AddAcceptPackage:$AddAcceptPackage -DisableInteractivity:$DisableInteractivity -AllowHangRetry -RetryCount ($RetryCount + 1) -BusyRetryCount $BusyRetryCount
        }
        throw "winget timed out: winget $($psi.Arguments)"
    }

    $outStd = $p.StandardOutput.ReadToEnd()
    $outErr = $p.StandardError.ReadToEnd()
    $out = $outStd + "`n" + $outErr

    $global:LASTEXITCODE = $p.ExitCode
    if ($LASTEXITCODE -ne 0) {
        if (Test-WingetAlreadyInstalled -ExitCode $LASTEXITCODE -Output $out) {
            if ($script:QuietWinget) {
                Write-Host "Winget package already present; continuing." -ForegroundColor Yellow
                Write-Verbose $out
            } else {
                Write-Warning "Winget reports package already installed; continuing."
            }
            $global:LASTEXITCODE = 0
            return
        }
        # Retry if Windows Installer is busy (exit code 1618)
        if ((Test-WingetInstallerBusy -ExitCode $LASTEXITCODE -Output $out) -and $BusyRetryCount -gt 0) {
            $delay = $script:WingetBusyRetryDelaySec
            $remaining = $BusyRetryCount
            Write-Host "Windows Installer is busy (exit code 1618). Waiting ${delay}s before retry ($remaining retries left)..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delay
            return Invoke-WingetCommand -Args $Args -TimeoutSec $TimeoutSec -AddAcceptSource:$AddAcceptSource -AddAcceptPackage:$AddAcceptPackage -DisableInteractivity:$DisableInteractivity -AllowHangRetry:$AllowHangRetry -RetryCount $RetryCount -BusyRetryCount ($BusyRetryCount - 1)
        }
        throw "winget failed ($LASTEXITCODE): $out"
    }
}

function Install-WithWinget {
    param(
        [Parameter(Mandatory)][string]$Args,   # include subcommand, e.g. "install --id Microsoft.PowerShell --exact --silent"
        [int]$TimeoutSec = $script:WingetTimeoutSec
    )
    Initialize-Winget
    Invoke-WingetCommand -Args "$Args --source winget" -TimeoutSec $TimeoutSec -AddAcceptSource -AddAcceptPackage -AllowHangRetry | Out-Null
}

# Warm-up winget so first run does not block waiting for source initialization/prompts
function Initialize-Winget {
    param([int]$TimeoutSec = $script:WingetWarmupTimeoutSec)
    if ($script:WingetInitialized) { return }
    $script:WingetInitialized = $true
    if ($TimeoutSec -le 0) { return }
    Write-Host "Initializing winget sources (timeout ${TimeoutSec}s)..." -ForegroundColor Yellow
    try {
        Invoke-WingetCommand -Args "source update --name winget" -TimeoutSec $TimeoutSec -DisableInteractivity | Out-Null
    } catch {
        try { Invoke-WingetCommand -Args "source update" -TimeoutSec $TimeoutSec -DisableInteractivity | Out-Null } catch {}
        Write-WingetWarmupNotice -Message "winget warm-up failed: $($_.Exception.Message)"
    }
}

# Optional helper: if not elevated, we’ll try --scope user on failure
function Install-WithFallback {
    param([Parameter(Mandatory)][string]$Id)
    try {
        Install-WithWinget "install --id $Id --exact --silent"
    } catch {
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
            Write-Warning "Machine-scope install failed without elevation; retrying as user scope..."
            Install-WithWinget "install --id $Id --exact --silent --scope user"
        } else {
            throw
        }
    }
}

# --- 0. Winget presence & warm sources  ----------------------------------------

Write-Host "Winget version:" -ForegroundColor Yellow
try {
    winget --version
}
catch {
    Write-Error "winget is not available. Please install App Installer from Microsoft Store."
    exit 1
}

# --- 1. PowerShell Core -------------------------------------------------------

Write-Host "[1/3] Checking PowerShell Core..." -ForegroundColor Yellow

# Check for pwsh in PATH or common installation locations
$pwshFound = $false
if (Test-Cmd 'pwsh') {
    $pwshFound = $true
} else {
    # Check common installation paths
    $commonPaths = @(
        "${env:ProgramFiles}\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
        "${env:LOCALAPPDATA}\Microsoft\PowerShell\7\pwsh.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $pwshFound = $true
            Write-Host "  Found PowerShell Core at: $path" -ForegroundColor Gray
            break
        }
    }
}

if (-not $pwshFound) {
    Write-Host "  Not found. Installing PowerShell Core..." -ForegroundColor Yellow
    Install-WithFallback -Id "Microsoft.PowerShell"
    Write-Host "  $([char]0x2713) PowerShell Core installed successfully" -ForegroundColor Green
} else {
    $pwshVersion = if (Test-Cmd 'pwsh') { 
        (pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null)
    } else { 
        "installed" 
    }
    Write-Host "  $([char]0x2713) PowerShell Core already installed ($pwshVersion)" -ForegroundColor Green
}

# --- 2. Azure CLI -------------------------------------------------------------

Write-Host "[2/3] Checking Azure CLI..." -ForegroundColor Yellow

# Check for az in PATH or common installation locations
$azFound = $false
if (Test-Cmd 'az') {
    $azFound = $true
} else {
    # Check common installation paths
    $commonPaths = @(
        "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        "${env:ProgramFiles}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        "${env:LOCALAPPDATA}\Programs\Azure CLI\wbin\az.cmd"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $azFound = $true
            Write-Host "  Found Azure CLI at: $path" -ForegroundColor Gray
            # Refresh PATH to include Azure CLI
            $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
            $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $env:Path    = $machinePath + ';' + $userPath
            break
        }
    }
}

if (-not $azFound) {
    Write-Host "  Not found. Installing Azure CLI..." -ForegroundColor Yellow
    Install-WithFallback -Id "Microsoft.AzureCLI"
    Write-Host "  $([char]0x2713) Azure CLI installed successfully" -ForegroundColor Green
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = $machinePath + ';' + $userPath
} else {
    Write-Host "  $([char]0x2713) Azure CLI already installed" -ForegroundColor Green
}

# --- 3. Bicep CLI -------------------------------------------------------------

Write-Host "[3/3] Checking Bicep CLI..." -ForegroundColor Yellow

# Check for bicep in PATH or common installation locations
$bicepFound = $false
if (Test-Cmd 'bicep') {
    $bicepFound = $true
} else {
    # Check common installation paths
    $commonPaths = @(
        "${env:ProgramFiles}\Bicep CLI\bicep.exe",
        "${env:ProgramFiles(x86)}\Bicep CLI\bicep.exe",
        "${env:LOCALAPPDATA}\Programs\Bicep CLI\bicep.exe",
        "${env:USERPROFILE}\.Azure\bin\bicep.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $bicepFound = $true
            Write-Host "  Found Bicep CLI at: $path" -ForegroundColor Gray
            # Refresh PATH to include Bicep CLI
            $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
            $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $env:Path    = $machinePath + ';' + $userPath
            break
        }
    }
}

if (-not $bicepFound) {
    Write-Host "  Not found. Installing Bicep CLI..." -ForegroundColor Yellow
    Install-WithFallback -Id "Microsoft.Bicep"
    Write-Host "  $([char]0x2713) Bicep CLI installed successfully" -ForegroundColor Green
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = $machinePath + ';' + $userPath
} else {
    Write-Host "  $([char]0x2713) Bicep CLI already installed" -ForegroundColor Green
}

Write-Host ""
Write-Host "$([char]0x2713) All prerequisites satisfied" -ForegroundColor Green
Write-Host ""

# --- Preflight ----------------------------------------------------------------

Write-Host "Running preflight checks..." -ForegroundColor Cyan
$preflight = Join-Path $root 'Preflight-BlocklistFunctionApp.ps1'
if (-not (Test-Path $preflight)) {
    Write-Error "Preflight script not found: $preflight"
    Stop-LoggingAndExit -Code 1
}

 & pwsh -NoLogo -NoProfile -File $preflight -AutoInstall
if ($LASTEXITCODE -ne 0) {
    Write-Host "Preflight checks failed. Aborting." -ForegroundColor Red
    Stop-LoggingAndExit -Code 1
}

Write-Host ""
Write-Host "$([char]0x2713) Preflight checks passed" -ForegroundColor Green
Write-Host ""

# --- Onboarding ---------------------------------------------------------------

Write-Host "Launching onboarding script..." -ForegroundColor Cyan
$onboard = Join-Path $root 'Onboard-FunctionApp.ps1'
if (-not (Test-Path $onboard)) {
    Write-Error "Onboarding script not found: $onboard"
    Stop-LoggingAndExit -Code 1
}

& pwsh -NoLogo -NoProfile -File $onboard
Stop-LoggingAndExit -Code $LASTEXITCODE
