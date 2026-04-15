<#
  Shared logging helper for Blocklist Function App scripts.
  Creates a timestamped log file under ProgramData (or a temp fallback) and starts a transcript.
#>

function Get-BlocklistLogDirectory {
  $programData = $env:ProgramData
  if ([string]::IsNullOrWhiteSpace($programData)) {
    $systemDrive = if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { 'C:' } else { $env:SystemDrive }
    $programData = Join-Path $systemDrive 'ProgramData'
  }

  $target = Join-Path $programData 'BlocklistFunctionApp\Logs'
  try {
    if (-not (Test-Path $target)) {
      New-Item -ItemType Directory -Path $target -Force | Out-Null
    }
    return $target
  } catch {
    $fallback = Join-Path ([System.IO.Path]::GetTempPath()) 'BlocklistFunctionApp\Logs'
    if (-not (Test-Path $fallback)) {
      New-Item -ItemType Directory -Path $fallback -Force | Out-Null
    }
    Write-Warning "Failed to create log directory at '$target'. Using fallback '$fallback'. Error: $($_.Exception.Message)"
    return $fallback
  }
}

function New-BlocklistLogFilePath {
  param(
    [string]$ExistingPath,
    [string]$Prefix = 'BlocklistFunctionApp'
  )

  if (-not [string]::IsNullOrWhiteSpace($ExistingPath)) {
    $logDir = Split-Path -Parent $ExistingPath
    if (-not (Test-Path $logDir)) {
      try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch { }
    }
    return $ExistingPath
  }

  $logDir = Get-BlocklistLogDirectory
  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $counter = 0
  do {
    $suffix = if ($counter -eq 0) { '' } else { "-$counter" }
    $candidate = Join-Path $logDir "$Prefix-$timestamp$suffix.log"
    $counter++
  } while (Test-Path $candidate)

  return $candidate
}

function Start-BlocklistLogging {
  param(
    [string]$LogPath,
    [string]$Prefix = 'BlocklistFunctionApp',
    [switch]$ForceNew
  )

  $path = $LogPath
  if ($ForceNew -or [string]::IsNullOrWhiteSpace($path)) {
    $path = New-BlocklistLogFilePath -ExistingPath $null -Prefix $Prefix
  } else {
    $path = New-BlocklistLogFilePath -ExistingPath $path -Prefix $Prefix
  }
  $env:BLOCKLIST_LOG_PATH = $path

  if ($ForceNew -and $global:BlocklistTranscriptActive) {
    try { Stop-Transcript | Out-Null } catch { }
    $global:BlocklistTranscriptActive = $false
  }

  if (-not $ForceNew -and $global:BlocklistTranscriptActive) { return $path }

  $transcriptStarted = $false
  $removedDefaults = @()
  try {
    if ($PSDefaultParameterValues) {
      foreach ($key in @('*:EventName', 'Start-Transcript:EventName', 'Microsoft.PowerShell.Utility\\Start-Transcript:EventName')) {
        if ($PSDefaultParameterValues.ContainsKey($key)) {
          $removedDefaults += [pscustomobject]@{ Key = $key; Value = $PSDefaultParameterValues[$key] }
          $null = $PSDefaultParameterValues.Remove($key)
        }
      }
    }

    Start-Transcript -Path $path -Append | Out-Null
    $transcriptStarted = $true
    $global:BlocklistTranscriptActive = $true
    $global:BlocklistTranscriptPath = $path
  } catch {
    Write-Warning "Unable to start transcript logging at '$path': $($_.Exception.Message)"
  } finally {
    if ($removedDefaults) {
      foreach ($entry in $removedDefaults) {
        $PSDefaultParameterValues[$entry.Key] = $entry.Value
      }
    }
  }

  if ($transcriptStarted -and -not $global:BlocklistTranscriptCleanupRegistered) {
    try {
      Register-EngineEvent -SourceIdentifier 'PowerShell.Exiting' -Action {
        try { Stop-Transcript | Out-Null } catch { }
      } | Out-Null
      $global:BlocklistTranscriptCleanupRegistered = $true
    } catch {
      Write-Warning "Transcript started but failed to register exit cleanup: $($_.Exception.Message)"
    }
  }

  return $path
}

function Stop-BlocklistLogging {
  if (-not $global:BlocklistTranscriptActive) { return }
  try { Stop-Transcript | Out-Null } catch { Write-Warning "Failed to stop transcript: $($_.Exception.Message)" }
  $global:BlocklistTranscriptActive = $false
}
