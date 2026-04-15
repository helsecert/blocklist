<#[
Preflight-BlocklistFunctionApp.ps1
Purpose: Validate (and optionally install) prerequisites for the Blocklist Function App onboarding.
Zero-parameter onboarding design retained; this script remains optional but recommended.
]#>
param(
  [switch]$AutoInstall,
  [switch]$NoInstall,
  [string]$JsonReportPath,
  [switch]$Silent,
  [switch]$SkipBicepValidate,
  [switch]$SkipAzCheck,
  [int]$WingetWarmupTimeoutSec = 10,
  [int]$WingetInstallTimeoutSec = 300,
  [switch]$PreferWinget      # Use winget for installations where possible (Windows only)
)

$ErrorActionPreference = 'Stop'
$script:Failures = 0
$checks = @()

$loggingHelper = Join-Path $PSScriptRoot 'Logging.ps1'
if (Test-Path $loggingHelper) {
  . $loggingHelper
  $script:LogFilePath = Start-BlocklistLogging -ForceNew -Prefix 'BlocklistFunctionApp-Preflight'
  if (-not $Silent) { Write-Host "[Logging] Writing to (Preflight): $script:LogFilePath" -ForegroundColor Cyan }
} elseif (-not $Silent) {
  Write-Warning "Logging helper not found at $loggingHelper. Transcript logging disabled."
}

function Stop-LoggingAndExit {
  param([int]$Code)
  if (Get-Command -Name Stop-BlocklistLogging -ErrorAction SilentlyContinue) {
    try { Stop-BlocklistLogging } catch { }
  }
  exit $Code
}

function Add-CheckResult {
  param(
    [string]$Name,
    [string]$Status,  # OK | Installed | Warning | Missing | Failed | Skipped
    [string]$Detail
  )
  $checks += [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }
  if($Status -in 'Missing','Failed') { $script:Failures++ }
  if(-not $Silent){
    $color = switch($Status){ 'OK' {'Green'} 'Installed' {'Green'} 'Warning' {'Yellow'} 'Skipped' {'DarkGray'} default {'Red'} }
    Write-Host ("[{0}] {1} - {2}" -f $Status,$Name,$Detail) -ForegroundColor $color
  }
}

function Test-CmdPresent { param([string]$Cmd) return [bool](Get-Command $Cmd -ErrorAction SilentlyContinue) }
function Test-WingetAvailable { Test-CmdPresent -Cmd 'winget' }

$script:WingetWarmupAttempted = $false
function Invoke-WingetCommandWithTimeout {
  param(
    [Parameter(Mandatory)][string]$Args,
    [Parameter(Mandatory)][int]$TimeoutSec,
    [switch]$IgnoreExitCode
  )
  if($TimeoutSec -le 0){ return }
  $tmpRoot = if($env:TEMP){ $env:TEMP } elseif($env:TMP){ $env:TMP } else { $PSScriptRoot }
  $outFile = Join-Path $tmpRoot 'blocklist-winget-tmp.out'
  $errFile = Join-Path $tmpRoot 'blocklist-winget-tmp.err'
  $p = Start-Process -FilePath 'winget.exe' -ArgumentList "$Args --disable-interactivity" -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
  if(-not $p.WaitForExit($TimeoutSec * 1000)){
    try { $p.Kill() } catch {}
    throw "winget timed out: winget $Args"
  }
  if((-not $IgnoreExitCode) -and $p.ExitCode -ne 0){
    $out = ''
    try { $out = (Get-Content $outFile -Raw 2>$null) + "`n" + (Get-Content $errFile -Raw 2>$null) } catch {}
    throw "winget failed ($($p.ExitCode)): $out"
  }
}

function Invoke-WingetSourceUpdateBestEffort {
  param([int]$TimeoutSec = $WingetWarmupTimeoutSec)
  if($script:WingetWarmupAttempted -or -not (Test-WingetAvailable)) { return }
  $script:WingetWarmupAttempted = $true
  try { Invoke-WingetCommandWithTimeout -Args 'source update --name winget' -TimeoutSec $TimeoutSec -IgnoreExitCode }
  catch { try { Invoke-WingetCommandWithTimeout -Args 'source update' -TimeoutSec $TimeoutSec -IgnoreExitCode } catch {} }
}

$script:WingetWarmed = $false
$script:WingetHangRetried = $false
function Ensure-WingetWarmed {
  if($script:WingetWarmed -or -not (Test-WingetAvailable)) { return }
  $script:WingetWarmed = $true
  try {
    Write-Host '[Preflight] Warming up winget (non-interactive)...' -ForegroundColor Cyan
    Invoke-WingetSourceUpdateBestEffort -TimeoutSec $WingetWarmupTimeoutSec
  } catch {
    Write-Host "[Preflight] winget warm-up skipped: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

function Invoke-WingetInstall {
  param([Parameter(Mandatory)][string]$Id)
  if(-not (Test-WingetAvailable)){ throw "winget is not available" }
  Ensure-WingetWarmed
  $psi = Start-Process -FilePath "winget.exe" -ArgumentList "install -e --id $Id --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --force --silent" -NoNewWindow -PassThru -RedirectStandardOutput "${env:TEMP}\winget-install-$Id.out" -RedirectStandardError "${env:TEMP}\winget-install-$Id.err"
  if(-not $psi.WaitForExit([Math]::Max($WingetInstallTimeoutSec, 30) * 1000)){
    try { $psi.Kill() } catch {}
    if(-not $script:WingetHangRetried){
      $script:WingetHangRetried = $true
      Write-Host "[Preflight] winget install hung, retrying once after source update..." -ForegroundColor Yellow
      try { Invoke-WingetCommandWithTimeout -Args 'source update --name winget' -TimeoutSec ([Math]::Min([Math]::Max($WingetWarmupTimeoutSec, 10), 30)) -IgnoreExitCode }
      catch { try { Invoke-WingetCommandWithTimeout -Args 'source update' -TimeoutSec ([Math]::Min([Math]::Max($WingetWarmupTimeoutSec, 10), 30)) -IgnoreExitCode } catch {} }
      return Invoke-WingetInstall -Id $Id
    }
    throw "winget install for $Id timed out"
  }
  if($psi.ExitCode -ne 0){
    $out = ""
    try {
      $out = (Get-Content "${env:TEMP}\winget-install-$Id.out" -Raw 2>$null) + "`n" + (Get-Content "${env:TEMP}\winget-install-$Id.err" -Raw 2>$null)
    } catch {}
    throw "winget install for $Id failed with exit code $($psi.ExitCode): $out"
  }
}

# 1. PowerShell version (attempt winget install/upgrade if requested)
$minVersion = [Version]'7.2'
if($PSVersionTable.PSVersion -lt $minVersion){
  if($AutoInstall -and -not $NoInstall -and (Test-WingetAvailable) -and $PreferWinget){
    try {
      Write-Host "[Preflight] Installing/upgrading PowerShell Core via winget..." -ForegroundColor Cyan
      Invoke-WingetInstall -Id 'Microsoft.Powershell'
      $newVer = $PSVersionTable.PSVersion
      if($newVer -lt $minVersion){ Add-CheckResult -Name 'PowerShellVersion' -Status 'Failed' -Detail "Upgrade attempted but still below $minVersion" }
      else { Add-CheckResult -Name 'PowerShellVersion' -Status 'Installed' -Detail $newVer.ToString() }
    } catch { Add-CheckResult -Name 'PowerShellVersion' -Status 'Failed' -Detail "winget install failed: $($_.Exception.Message)" }
  } else {
    Add-CheckResult -Name 'PowerShellVersion' -Status 'Failed' -Detail "Found $($PSVersionTable.PSVersion); require >= $minVersion (run: winget install -e --id Microsoft.Powershell)"
  }
} else { Add-CheckResult -Name 'PowerShellVersion' -Status 'OK' -Detail $PSVersionTable.PSVersion.ToString() }

# 2. Azure CLI
if($SkipAzCheck){
  Add-CheckResult -Name 'AzureCLI' -Status 'Skipped' -Detail 'SkipAzCheck specified'
} else {
  if(Test-CmdPresent az){
    $azVer = (az version --output json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty azure-cli 2>$null)
    if(-not $azVer){ $azVer = (az --version 2>$null | Select-String -Pattern 'azure-cli' | Select-Object -First 1 | ForEach-Object { ($_ -split ' ')[1] }) }
    Add-CheckResult -Name 'AzureCLI' -Status 'OK' -Detail $(if($azVer){$azVer}else{'detected'})
  } else {
    if($AutoInstall -and -not $NoInstall -and $PreferWinget -and (Test-WingetAvailable)){
      try {
        Write-Host '[Preflight] Installing Azure CLI via winget...' -ForegroundColor Cyan
        Invoke-WingetInstall -Id 'Microsoft.AzureCLI'
        if(Test-CmdPresent az){
          $azVer = (az --version 2>$null | Select-String -Pattern 'azure-cli' | Select-Object -First 1 | ForEach-Object { ($_ -split ' ')[1] })
          Add-CheckResult -Name 'AzureCLI' -Status 'Installed' -Detail $(if($azVer){$azVer}else{'installed'})
        } else { Add-CheckResult -Name 'AzureCLI' -Status 'Failed' -Detail 'winget install attempted but az still missing' }
      } catch { Add-CheckResult -Name 'AzureCLI' -Status 'Failed' -Detail "winget Azure CLI install failed: $($_.Exception.Message)" }
    } else {
      Add-CheckResult -Name 'AzureCLI' -Status 'Missing' -Detail 'az command not found; install Azure CLI'
    }
  }
}

# 3. Bicep CLI
$bicepPresent = $false
if(Test-CmdPresent bicep){ $bicepPresent = $true; $bicepVer = (bicep --version) }
elseif(Test-CmdPresent az){
  try { $bicepVer = (az bicep version 2>$null); if($LASTEXITCODE -eq 0 -and $bicepVer){ $bicepPresent = $true } } catch {}
}
if(-not $bicepPresent){
  if($AutoInstall -and -not $NoInstall){
    $installed = $false
    if($PreferWinget -and (Test-WingetAvailable)){
      try {
        Write-Host "[Preflight] Installing Bicep via winget..." -ForegroundColor Cyan
        Invoke-WingetInstall -Id 'Microsoft.Bicep'
        if(Test-CmdPresent bicep){ $bicepVer = (bicep --version); $installed = $true }
      } catch { Write-Host "[Preflight] winget Bicep install failed: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    if(-not $installed -and (Test-CmdPresent az)){
      try {
        Write-Host "[Preflight] Installing Bicep via az bicep install..." -ForegroundColor Cyan
        az bicep install 2>$null | Out-Null
        $bicepVer = (az bicep version 2>$null); if($LASTEXITCODE -eq 0 -and $bicepVer){ $installed = $true }
      } catch { Write-Host "[Preflight] az bicep install failed: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    if($installed){ $bicepPresent = $true; Add-CheckResult -Name 'BicepCLI' -Status 'Installed' -Detail $bicepVer }
    else { Add-CheckResult -Name 'BicepCLI' -Status 'Failed' -Detail 'Install attempts failed (winget/az). Manual install required.' }
  } else {
    Add-CheckResult -Name 'BicepCLI' -Status 'Missing' -Detail 'Not found. Onboarding may fail deploying Bicep.'
  }
} else { Add-CheckResult -Name 'BicepCLI' -Status 'OK' -Detail $bicepVer }

# 4. Required PowerShell modules (targeted subset)
$requiredModules = @(
  @{Name='Az.Accounts';      Install='Az.Accounts'},
  @{Name='Az.Resources';     Install='Az.Resources'},
  @{Name='Az.Network';       Install='Az.Network'},
  @{Name='Az.Websites';      Install='Az.Websites'},
  @{Name='Az.PrivateDNS';    Install='Az.PrivateDNS'},
  @{Name='Az.Storage';       Install='Az.Storage'},
  @{Name='Az.Functions';     Install='Az.Functions'},
  @{Name='Microsoft.Graph.Authentication';  Install='Microsoft.Graph.Authentication'},
  @{Name='Microsoft.Graph.Identity.SignIns'; Install='Microsoft.Graph.Identity.SignIns'}
)

foreach($m in $requiredModules){
  $found = Get-Module -ListAvailable -Name $m.Name | Sort-Object Version -Descending | Select-Object -First 1
  if($found){
    $status = 'OK'; $detail = $found.Version.ToString()
  } else {
    if($AutoInstall -and -not $NoInstall){
      try { Install-Module -Name $m.Install -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop | Out-Null; $status='Installed'; $detail='Installed latest'; }
      catch { $status='Failed'; $detail = "Install failed: $($_.Exception.Message)" }
    } else { $status='Missing'; $detail='Not installed' }
  }
  Add-CheckResult -Name $m.Name -Status $status -Detail $detail
}

# 5. Bicep syntax validation
if(-not $SkipBicepValidate){
  $bicepFile = Join-Path $PSScriptRoot 'BlockListFunctionApp.bicep'
  if((Test-Path $bicepFile) -and ($checks | Where-Object { $_.Name -eq 'BicepCLI' -and $_.Status -in 'OK','Installed' })){
    try { $null = bicep build --stdout $bicepFile 2>$null; Add-CheckResult -Name 'BicepSyntax' -Status 'OK' -Detail 'Validated' }
    catch { Add-CheckResult -Name 'BicepSyntax' -Status 'Failed' -Detail "bicep build failed: $($_.Exception.Message)" }
  } else { Add-CheckResult -Name 'BicepSyntax' -Status 'Skipped' -Detail 'Bicep CLI missing or file absent' }
}

# 6. Azure login status (advisory)
try {
  if(Test-CmdPresent az){
    $acct = az account show -o json 2>$null | ConvertFrom-Json
    if($acct){ Add-CheckResult -Name 'AzureLogin' -Status 'OK' -Detail $acct.id }
    else { Add-CheckResult -Name 'AzureLogin' -Status 'Warning' -Detail 'Not logged in (az). Onboarding will prompt.' }
  } else { Add-CheckResult -Name 'AzureLogin' -Status 'Skipped' -Detail 'Azure CLI not present' }
} catch { Add-CheckResult -Name 'AzureLogin' -Status 'Warning' -Detail 'Unable to determine login state' }

if($JsonReportPath){
  try { $checks | ConvertTo-Json -Depth 4 | Set-Content -Path $JsonReportPath -Encoding UTF8 } catch { Write-Warning "Failed to write JSON report: $($_.Exception.Message)" }
}

if(-not $Silent){
  Write-Host 'Summary:' -ForegroundColor Cyan
  $checks | Format-Table -AutoSize | Out-String | Write-Host
  if($script:Failures -gt 0){ Write-Host "One or more critical prerequisites are missing/failed." -ForegroundColor Red }
  else { Write-Host "All critical prerequisites satisfied." -ForegroundColor Green }
}

if($script:Failures -gt 0){ Stop-LoggingAndExit -Code 1 } else { $env:BLOCKLIST_PREFLIGHT_DONE = '1'; Stop-LoggingAndExit -Code 0 }
