
# ====================================================================================================
# BESKRIVELSE
# ----------------------------------------------------------------------------------------------------
# Dette PowerShell-scriptet automatiserer onboarding og oppsett av en Azure Function App (Flex Consumption)
# for helsecert Blocklist-løsningen. Scriptet følger Cloud Adoption Framework (CAF) navnekonvensjoner og sørger for:
#   - Opprettelse av ressursgruppe, App Service Plan, Function App, lagringskonto, Log Analytics, Application Insights,
#     VNet, subnets, Private Endpoint, Private DNS Zone og NSGer via Bicep-maler.
#   - Sikker tilkobling til HelseCert Blocklist API via Private Link og DNS.
#   - Automatisk deteksjon av eksisterende infrastruktur for idempotent kjøring.
#   - Interaktiv innhenting av nødvendige nøkler og parametere.
#   - Tildeling av nødvendige rettigheter til Managed Identity.
#   - Aktivering av timer-trigger etter vellykket oppsett.
#   - Deaktivering av offentlig nettverkstilgang etter ferdigstilling.
#
# Scriptet gir løpende status, validerer alle steg, og gir en oppsummering til slutt. Krever Azure CLI, Az-moduler og nødvendige rettigheter.
# ====================================================================================================

####################################################################################################
# PARAMETER DECLARATIONS
####################################################################################################
param(
  [switch]$PlainMode,
  [bool]$UseEmoji = $true,
  [switch]$VerboseMode,
  [switch]$TimeStampEachLine
)

$loggingHelper = Join-Path $PSScriptRoot 'Logging.ps1'
if (Test-Path $loggingHelper) {
  . $loggingHelper
  $script:LogFilePath = Start-BlocklistLogging -ForceNew -Prefix 'BlocklistFunctionApp-Onboard'
  Write-Host "Logging (Onboard) to: $script:LogFilePath" -ForegroundColor Cyan
} else {
  Write-Warning "Logging helper not found at $loggingHelper. Proceeding without transcript logging."
}

try {

####################################################################################################
# GLOBAL STATE INITIALIZATION (Do not modify logic)
####################################################################################################
$global:__StartTime  = Get-Date
$script:StepCounter  = 0
$script:TotalSteps   = 20

####################################################################################################
# CAF CONFIGURATION & DERIVED NAMES (User-adjustable variables)
# CAF pattern: {abbreviation}-{workload}-{environment}-{region}-{instance}
####################################################################################################
$WorkloadName                = 'helsecert-blocklist'
$Environment                 = 'prod'
$RegionCode                  = 'nwe'
$Instance                    = '001'
$Location                    = 'NorwayEast'
$ResourceAlias               = 'pls-blocklist-prod.e081d7a6-92bb-40a6-8787-199877ae6968.norwayeast.azure.privatelinkservice'
$PrivateDnsZoneName          = 'blocklist-az.helsecert.no'
$PrivateDnsRecordName        = '@'
$VNetAddressSpace            = '10.203.47.0/26'
$IntegrationSubnetPrefix     = '10.203.47.0/28'
$PrivateEndpointSubnetPrefix = '10.203.47.16/28'

# Resource tagging (adjust values to align with your governance strategy)
$ResourceTags = @{
  workload    = $WorkloadName
  environment = $Environment
  managedBy   = 'Onboard-FunctionApp.ps1'
}

# Derived CAF-compliant resource names
$ResourceGroup    = "rg-$WorkloadName-$Environment-$RegionCode-$Instance"
$PlanName         = "asp-$WorkloadName-$Environment-$RegionCode-$Instance"
$FunctionAppName  = "func-$WorkloadName-$Environment-$RegionCode-$Instance"
$LogAnalyticsName = "log-$WorkloadName-$Environment-$RegionCode-$Instance"
$AppInsightsName  = "appi-$WorkloadName-$Environment-$RegionCode-$Instance"
$pename           = "pe-$WorkloadName-$Environment-$RegionCode-$Instance"

####################################################################################################
# STORAGE ACCOUNT NAME DERIVATION & VALIDATION
#   Rules: 3-24 chars, lowercase letters/digits only, globally unique, no hyphens.
####################################################################################################
function Test-StorageAccountNameValid {
  <#
    .SYNOPSIS
      Validates an Azure Storage account name against length and character rules.
    .PARAMETER Name
      Candidate storage account name.
    .OUTPUTS
      [bool] True if valid, otherwise False.
    .NOTES
      Rules enforced: 3-24 chars, only lowercase letters and digits.
  #>
  param([string]$Name)
  return (
    $Name.Length -ge 3 -and
    $Name.Length -le 24 -and
    ($Name -cmatch '^[a-z0-9]+$')
  )
}

$SanitizedWorkloadForStorage = ($WorkloadName.ToLower() -replace '[^a-z0-9]', '')
if([string]::IsNullOrWhiteSpace($SanitizedWorkloadForStorage)) { Write-Error "After sanitization the workload name '$WorkloadName' became empty."; throw }
$StorageAccountPrefix = "st$SanitizedWorkloadForStorage$Environment$Instance".ToLower()

####################################################################################################
# PATH RESOLUTION
####################################################################################################
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BicepRg    = Join-Path $ScriptRoot 'BlockListFunctionApp.bicep'
$BicepSub   = Join-Path $ScriptRoot 'BlockListFunctionApp.sub.bicep'
$FunctionFolder = Join-Path $ScriptRoot 'function'

####################################################################################################
# FUNCTION DEFINITIONS (Utility / Output / Spinner / Timing / Deployment Helpers)
####################################################################################################
#region Functions
function New-ColorProfile {
  <# Returns a color profile object used for themed output. #>
  [pscustomobject]@{
    Header      = 'Cyan'
    SectionLine = 'DarkCyan'
    Info        = 'Gray'
    Step        = 'Magenta'
    Success     = 'Green'
    Warning     = 'Yellow'
    Error       = 'Red'
    FieldLabel  = 'Cyan'
    FieldValue  = 'White'
  }
}

function Test-EmojiSupport {
  <# Determines whether emoji output should be used based on PlainMode. #>
  return -not $PlainMode
}

function Format-Stamp {
  <# Returns timestamp prefix if enabled. #>
  if($TimeStampEachLine){ '[' + (Get-Date -Format 'HH:mm:ss') + ']' } else { '' }
}

function Write-ColoredLine {
  <# Writes a line with optional color and timestamp prefix. #>
  param(
    [string]$Message,
    [string]$Color = 'Gray',
    [switch]$NoNewLine
  )
  $prefix = Format-Stamp
  if($PlainMode){ $Color = 'Gray' }
  if($NoNewLine){
    Write-Host "$prefix $Message" -ForegroundColor $Color -NoNewline
  } else {
    Write-Host "$prefix $Message" -ForegroundColor $Color
  }
}

function Write-Header {
  <# Writes a framed header banner. #>
  param([string]$Text)
  $borderChar = '='
  $line = ($borderChar * ([Math]::Max((" $Text ").Length,40)))
  Write-ColoredLine $line $script:Theme.Header
  Write-ColoredLine (" $Text ") $script:Theme.Header
  Write-ColoredLine $line $script:Theme.Header
}

function Write-Section {
  <# Writes a section delimiter line. #>
  param([string]$Name)
  $emoji = if($UseEmoji -and (Test-EmojiSupport)) { '⚙️ ' } else { '' }
  Write-ColoredLine ("--- ${emoji}$Name ---") $script:Theme.SectionLine
}

function Write-Step {
  <# Increments and writes a step progress line. #>
  param([string]$Text)
  $script:StepCounter++
  $emoji = if($UseEmoji -and (Test-EmojiSupport)) { '⚙️ ' } else { '' }
  $prefix = "[$script:StepCounter/$script:TotalSteps]"
  Write-ColoredLine "$prefix ${emoji}$Text" $script:Theme.Step
}

function Write-Result {
  <# Writes a standardized result line (Success / Warning / Error). #>
  param(
    [ValidateSet('Success','Warning','Error')][string]$Status,
    [string]$Message
  )
  $color = $script:Theme.$Status
  $emoji = switch($Status){
    'Success' { if($UseEmoji){ '✅' } }
    'Warning' { if($UseEmoji){ '⚠️' } }
    'Error'   { if($UseEmoji){ '❌' } }
  }
  Write-ColoredLine "[$Status] $emoji $Message" $color
}

function Write-Field {
  <# Writes a labeled field in 'Label: Value' format with grouping. #>
  param(
    [string]$Label,
    [string]$Value,
    [string]$Group
  )
  $pad = 15
  $labelColor = $script:Theme.FieldLabel
  $valueColor = $script:Theme.FieldValue
  if($PlainMode){ $labelColor = 'Gray'; $valueColor = 'White' }
  $groupPrefix = if($Group){ "[$Group] " } else { '' }
  Write-Host (Format-Stamp + ' ' + $groupPrefix + $Label.PadRight($pad) + ': ') -ForegroundColor $labelColor -NoNewLine
  Write-Host $Value -ForegroundColor $valueColor
}

function Write-ErrorPane {
  <# Writes a bordered multi-line error pane with optional resolution. #>
  param(
    [string]$Message,
    [string]$Resolution
  )
  $border = ('!' * [Math]::Min([Math]::Max($Message.Length,40),100))
  Write-ColoredLine $border $script:Theme.Error
  Write-ColoredLine "ERROR: $Message" $script:Theme.Error
  if($Resolution){ Write-ColoredLine "RESOLUTION: $Resolution" $script:Theme.Warning }
  Write-ColoredLine $border $script:Theme.Error
}

function Start-Spinner {
  <# Initializes spinner state. #>
  param([string]$Text)
  $script:SpinnerActive = $true
  $script:SpinnerText   = $Text
  $script:SpinnerChars  = @('|', '/', '-', '\')
  $script:SpinnerIndex  = 0
  $script:SpinnerLastLength = 0
}

function Update-Spinner {
  <# Updates spinner animation frame - stays on one line. #>
  if(-not $script:SpinnerActive){ return }
  $char = $script:SpinnerChars[$script:SpinnerIndex % $script:SpinnerChars.Count]
  $script:SpinnerIndex++
  
  # Build the spinner line - ensure no newlines in text
  $cleanText = $script:SpinnerText -replace "`r|`n", ""
  $line = "$char $cleanText"
  $maxWidth = $null
  try {
    if(-not [System.Console]::IsOutputRedirected){ $maxWidth = [System.Console]::BufferWidth }
    if(-not $maxWidth -and $Host.UI -and $Host.UI.RawUI){ $maxWidth = $Host.UI.RawUI.BufferSize.Width }
  } catch { $maxWidth = $null }
  if($maxWidth -and $maxWidth -gt 1){
    $usableWidth = $maxWidth - 1
    if($line.Length -gt $usableWidth){
      $trimLength = [Math]::Max($usableWidth - 3, 0)
      if($trimLength -gt 0){
        $line = $line.Substring(0, $trimLength) + '...'
      } else {
        $line = $line.Substring(0, [Math]::Min($usableWidth, $line.Length))
      }
    }
  }
  $requiredWidth = [Math]::Max($script:SpinnerLastLength, $line.Length)
  $paddedLine = $line.PadRight($requiredWidth)
  $script:SpinnerLastLength = $requiredWidth
  $colorName = if($PlainMode){ 'Gray' } else { $script:Theme.Step }
  $consoleColor = $null
  if($colorName){
    try { $consoleColor = [System.Enum]::Parse([System.ConsoleColor], $colorName, $true) } catch { $consoleColor = $null }
  }

  $written = $false
  if(-not [System.Console]::IsOutputRedirected){
    try {
      $previousColor = [System.Console]::ForegroundColor
      if($consoleColor){ [System.Console]::ForegroundColor = $consoleColor }
      [System.Console]::Write("`r$paddedLine")
      if($consoleColor){ [System.Console]::ForegroundColor = $previousColor }
      $written = $true
    } catch {
      # Fall back to carriage-return approach if RawUI positioning fails.
    }
  }
  if(-not $written){
    Write-Host ("`r$paddedLine") -ForegroundColor $colorName -NoNewline
  }
}

function Stop-Spinner {
  <# Stops spinner and writes completion marker. #>
  if(-not $script:SpinnerActive){ return }
  $script:SpinnerActive = $false
  
  # Clear the line and write the completion marker
  $cleanText = $script:SpinnerText -replace "`r|`n", ""
  $line = "✔ $cleanText"
  $maxWidth = $null
  try {
    if(-not [System.Console]::IsOutputRedirected){ $maxWidth = [System.Console]::BufferWidth }
    if(-not $maxWidth -and $Host.UI -and $Host.UI.RawUI){ $maxWidth = $Host.UI.RawUI.BufferSize.Width }
  } catch { $maxWidth = $null }
  if($maxWidth -and $maxWidth -gt 1){
    $usableWidth = $maxWidth - 1
    if($line.Length -gt $usableWidth){
      $trimLength = [Math]::Max($usableWidth - 3, 0)
      if($trimLength -gt 0){
        $line = $line.Substring(0, $trimLength) + '...'
      } else {
        $line = $line.Substring(0, [Math]::Min($usableWidth, $line.Length))
      }
    }
  }
  $requiredWidth = [Math]::Max($script:SpinnerLastLength, $line.Length)
  $paddedLine = $line.PadRight($requiredWidth)
  $colorName = if($PlainMode){ 'Gray' } else { $script:Theme.Success }
  $consoleColor = $null
  if($colorName){
    try { $consoleColor = [System.Enum]::Parse([System.ConsoleColor], $colorName, $true) } catch { $consoleColor = $null }
  }

  $written = $false
  if(-not [System.Console]::IsOutputRedirected){
    try {
      $previousColor = [System.Console]::ForegroundColor
      if($consoleColor){ [System.Console]::ForegroundColor = $consoleColor }
      [System.Console]::Write("`r$paddedLine`n")
      if($consoleColor){ [System.Console]::ForegroundColor = $previousColor }
      $written = $true
    } catch {
      # Fall back to carriage-return approach if RawUI positioning fails.
    }
  }
  if(-not $written){
    Write-Host ("`r$paddedLine") -ForegroundColor $colorName
  }
  $script:SpinnerLastLength = 0
}

function Measure-Stage {
  <# Measures execution time of a scriptblock and reports success/failure. #>
  param(
    [string]$Name,
    [scriptblock]$Action
  )
  Write-Step $Name
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    & $Action
    $sw.Stop()
    Write-Result -Status Success -Message "$Name completed in $([Math]::Round($sw.Elapsed.TotalSeconds,2))s"
  } catch {
    $sw.Stop()
    Write-ErrorPane -Message "$Name failed: $($_.Exception.Message)" -Resolution 'Review error details and retry.'
    throw
  }
}

function Grant-ManagedIdentityAppPermissions {
  <#
    .SYNOPSIS
      Assigns required Microsoft Graph app roles to a managed identity service principal.
    .DESCRIPTION
      Idempotent: Skips roles if already assigned. Returns object with NewlyAssigned & AlreadyPresent.
    .PARAMETER PrincipalId
      Object ID of the managed identity service principal.
    .PARAMETER GraphAppId
      AppId of Microsoft Graph (default: global multi-tenant Graph app id).
    .PARAMETER Quiet
      Suppresses per-role output for cleaner calling contexts.
    .OUTPUTS
      PSCustomObject with arrays: NewlyAssigned, AlreadyPresent.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PrincipalId,
    [Parameter()][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$GraphAppId = '00000003-0000-0000-c000-000000000000',
    [switch]$Quiet
  )

  $requiredRoleValues = @('Policy.Read.All','Policy.ReadWrite.ConditionalAccess')

  # Verify Graph connection exists (must be established before calling this function)
  if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw "Not connected to Microsoft Graph. Please connect using Connect-MgGraph before calling this function."
  }

  # Use direct REST API calls to avoid module loading conflicts
  $headers = @{
    Authorization = "Bearer $($script:GraphAccessToken)"
    'Content-Type' = 'application/json'
  }

  # Get managed identity service principal
  try {
    $spUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=id eq '$PrincipalId'"
    $spResponse = Invoke-RestMethod -Method Get -Uri $spUri -Headers $headers -ErrorAction Stop
    if(-not $spResponse.value -or $spResponse.value.Count -eq 0){
      throw "Managed identity service principal '$PrincipalId' not found."
    }
    $sp = $spResponse.value[0]
  } catch {
    throw "Failed to retrieve managed identity service principal: $($_.Exception.Message)"
  }

  # Get Microsoft Graph service principal
  try {
    $graphSpUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$GraphAppId'"
    $graphSpResponse = Invoke-RestMethod -Method Get -Uri $graphSpUri -Headers $headers -ErrorAction Stop
    if(-not $graphSpResponse.value -or $graphSpResponse.value.Count -eq 0){
      throw "Microsoft Graph service principal with appId '$GraphAppId' not found."
    }
    $graphSp = $graphSpResponse.value[0]
  } catch {
    throw "Failed to retrieve Graph service principal: $($_.Exception.Message)"
  }

  # Get existing app role assignments
  try {
    $assignmentsUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignments"
    $assignmentsResponse = Invoke-RestMethod -Method Get -Uri $assignmentsUri -Headers $headers -ErrorAction Stop
    $existingAssignments = $assignmentsResponse.value
  } catch {
    throw "Failed to retrieve existing role assignments: $($_.Exception.Message)"
  }

  $newlyAssigned  = @()
  $alreadyPresent = @()

  foreach($roleValue in $requiredRoleValues){
    $role = $graphSp.appRoles | Where-Object { $_.value -eq $roleValue -and $_.isEnabled }
    if(-not $role){
      if(-not $Quiet){ Write-ColoredLine "Graph app role '$roleValue' not found (skipping)." $script:Theme.Warning }
      continue
    }
    
    $existing = $existingAssignments | Where-Object { $_.appRoleId -eq $role.id -and $_.resourceId -eq $graphSp.id }
    if($existing){
      $alreadyPresent += $roleValue
      if(-not $Quiet){ Write-ColoredLine "Role already present: $roleValue" $script:Theme.Info }
      continue
    }
    
    # Assign the role
    try {
      $assignUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignments"
      $body = @{
        principalId = $sp.id
        resourceId = $graphSp.id
        appRoleId = $role.id
      } | ConvertTo-Json
      
      Invoke-RestMethod -Method Post -Uri $assignUri -Headers $headers -Body $body -ErrorAction Stop | Out-Null
      $newlyAssigned += $roleValue
      if(-not $Quiet){ Write-ColoredLine "Assigned role: $roleValue" $script:Theme.Success }
    } catch {
      if(-not $Quiet){ Write-ColoredLine "Failed to assign role '$roleValue': $($_.Exception.Message)" $script:Theme.Warning }
    }
  }

  [pscustomobject]@{ NewlyAssigned = $newlyAssigned; AlreadyPresent = $alreadyPresent }
}

function Get-SignedInUserObjectId {
  <#
    .SYNOPSIS
      Attempts to resolve the Azure AD objectId for the signed-in user.
    .PARAMETER UserPrincipalName
      Optional UPN used as a fallback lookup via Get-AzADUser.
  #>
  param([string]$UserPrincipalName)

  $objectId = $null
  try {
    $objectId = az ad signed-in-user show --query id -o tsv 2>$null
  } catch { }

  if([string]::IsNullOrWhiteSpace($objectId) -and $UserPrincipalName){
    try {
      $user = Get-AzADUser -UserPrincipalName $UserPrincipalName -ErrorAction Stop
      $objectId = $user.Id
    } catch { }
  }

  if([string]::IsNullOrWhiteSpace($objectId)){
    throw 'Unable to determine the signed-in user objectId. Verify az ad signed-in-user show works for your account.'
  }

  return $objectId.Trim()
}

function Assert-SubscriptionRoleAssignment {
  <#
    .SYNOPSIS
      Validates the signed-in user has one of the required Azure RBAC roles at subscription scope.
    .PARAMETER UserObjectId
      ObjectId of the calling user.
    .PARAMETER SubscriptionId
      Target subscription Id to inspect.
    .PARAMETER AllowedRoles
      Array of acceptable RBAC role display names.
    .OUTPUTS
      The display name of the role that satisfied the requirement.
  #>
  param(
    [Parameter(Mandatory)][string]$UserObjectId,
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string[]]$AllowedRoles,
    [string]$UserPrincipalName
  )

  $scope = "/subscriptions/$SubscriptionId"
  $assignments = Get-AzRoleAssignment -ObjectId $UserObjectId -Scope $scope -ErrorAction SilentlyContinue

  $matchInfo = $null
  if($assignments){
    $match = $assignments | Where-Object { $AllowedRoles -contains $_.RoleDefinitionName }
    if($match){
      $matchInfo = @{
        Role   = $match[0].RoleDefinitionName
        Source = 'Direct'
      }
    }
  }

  if(-not $matchInfo){
    $groupIds = @()
    try {
      if([string]::IsNullOrWhiteSpace($script:GraphAccessToken)){
        throw 'Graph access token unavailable for membership lookup.'
      }
      $groupIds = Get-CurrentUserGroupIdsViaGraph -GraphAccessToken $script:GraphAccessToken
    } catch {
      throw "Unable to enumerate group memberships for RBAC validation: $($_.Exception.Message)"
    }

    foreach($groupId in $groupIds){
      if([string]::IsNullOrWhiteSpace($groupId)){ continue }
      $groupAssignments = Get-AzRoleAssignment -ObjectId $groupId -Scope $scope -ErrorAction SilentlyContinue
      if(-not $groupAssignments){ continue }
      $groupMatch = $groupAssignments | Where-Object { $AllowedRoles -contains $_.RoleDefinitionName }
      if($groupMatch){
        $groupName = $null
        try {
          $groupObj = Get-AzADGroup -ObjectId $groupId -ErrorAction SilentlyContinue
          if($groupObj){ $groupName = $groupObj.DisplayName }
        } catch { }
        if([string]::IsNullOrWhiteSpace($groupName)){ $groupName = $groupId }
        $matchInfo = @{
          Role   = $groupMatch[0].RoleDefinitionName
          Source = "Group:$groupName"
        }
        break
      }
    }
  }

  if(-not $matchInfo){
    $current = @()
    if($assignments){
      $current = $assignments | Select-Object -ExpandProperty RoleDefinitionName -Unique
    }
    $currentList = if($current -and $current.Count -gt 0){ $current -join ', ' } else { 'none (user or groups)' }
    throw "Signed-in user lacks required subscription permissions at '$scope'. Current roles: $currentList. Required: $($AllowedRoles -join ' or ')."
  }

  if($matchInfo.Source -eq 'Direct'){
    return $matchInfo.Role
  } else {
    $groupDisplay = ($matchInfo.Source -replace '^Group:','')
    return "$($matchInfo.Role) via group '$groupDisplay'"
  }
}

function Get-CurrentUserGroupIdsViaGraph {
  <#
    .SYNOPSIS
      Uses the cached Graph access token to enumerate current user's group memberships.
    .PARAMETER GraphAccessToken
      Bearer token for Microsoft Graph (delegated user).
  #>
  param(
    [Parameter(Mandatory)][string]$GraphAccessToken
  )

  $groupIds = @()
  $uri = 'https://graph.microsoft.com/v1.0/me/getMemberGroups'
  $body = @{ securityEnabledOnly = $false } | ConvertTo-Json
  $headers = @{
    Authorization = "Bearer $GraphAccessToken"
    'Content-Type' = 'application/json'
  }

  $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ErrorAction Stop
  if($response.value){
    $groupIds = @($response.value | Where-Object { $_ })
  }

  return $groupIds
}

function Get-CurrentUserDirectoryRoleNames {
  <#
    .SYNOPSIS
      Retrieves Microsoft Entra directory roles assigned to the current user (directly or via group).
    .OUTPUTS
      Array of directory role display names.
  #>
  if(-not $script:GraphAccessToken){ throw 'Graph access token is missing. Cannot evaluate directory roles.' }
  $headers = @{
    Authorization = "Bearer $script:GraphAccessToken"
    'Content-Type' = 'application/json'
  }

  $memberBody = @{ securityEnabledOnly = $false } | ConvertTo-Json
  try {
    $memberResponse = Invoke-RestMethod -Method Post -Uri 'https://graph.microsoft.com/v1.0/me/getMemberObjects' -Headers $headers -Body $memberBody -ErrorAction Stop
  } catch {
    throw "Failed to enumerate member objects for Graph role detection: $($_.Exception.Message)"
  }

  $ids = @()
  if($memberResponse.value){
    $ids = @($memberResponse.value | Where-Object { $_ })
  }

  if(-not $ids -or $ids.Count -eq 0){ return @() }

  $roleNamesSet = [System.Collections.Generic.HashSet[string]]::new()
  $chunkSize = 20
  for($offset = 0; $offset -lt $ids.Count; $offset += $chunkSize){
    $chunk = $ids[$offset..([Math]::Min($offset + $chunkSize - 1, $ids.Count - 1))]
    $body = @{ ids = $chunk; types = @('directoryRole') } | ConvertTo-Json
    try {
      $detailResponse = Invoke-RestMethod -Method Post -Uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds' -Headers $headers -Body $body -ErrorAction Stop
    } catch {
      throw "Failed to resolve directory role names: $($_.Exception.Message)"
    }
    if($detailResponse.value){
      foreach($obj in $detailResponse.value){
        if($obj.'@odata.type' -eq '#microsoft.graph.directoryRole' -and $obj.displayName){
          $null = $roleNamesSet.Add($obj.displayName)
        }
      }
    }
  }

  $result = @()
  foreach($value in $roleNamesSet){
    if($value){ $result += $value }
  }
  return $result
}

function Assert-GraphDirectoryAdminPermissions {
  <#
    .SYNOPSIS
      Ensures the signed-in Graph user meets the directory role prerequisites.
    .PARAMETER RequiredRoles
      Role names the caller must always have.
    .PARAMETER AnyOfRoles
      At least one of these roles must be present.
  #>
  param(
    [Parameter(Mandatory)][string[]]$RequiredRoles,
    [Parameter(Mandatory)][string[]]$AnyOfRoles,
    [string[]]$OverrideRolesSatisfyingAll = @()
  )

  $roleNames = Get-CurrentUserDirectoryRoleNames

  if($OverrideRolesSatisfyingAll -and ($OverrideRolesSatisfyingAll | Where-Object { $_ -in $roleNames }).Count -gt 0){
    return $roleNames
  }
  $missing = $RequiredRoles | Where-Object { $_ -notin $roleNames }
  if($missing -and $missing.Count -gt 0){
    $detected = if($roleNames -and $roleNames.Count -gt 0){ $roleNames -join ', ' } else { '<none>' }
    throw "Graph account missing required directory role(s): $($missing -join ', '). Detected roles: $detected."
  }

  if($AnyOfRoles -and ($AnyOfRoles | Where-Object { $_ -in $roleNames }).Count -eq 0){
    $detected = if($roleNames -and $roleNames.Count -gt 0){ $roleNames -join ', ' } else { '<none>' }
    throw "Graph account must have at least one of: $($AnyOfRoles -join ', '). Detected roles: $detected."
  }

  return $roleNames
}

function Get-TenantSuffix {
  <#
    .SYNOPSIS
      Produces a short, tenant-specific suffix for globally unique naming.
    .DESCRIPTION
      Prefers a trimmed tenant display name combined with tenantId characters. Always returns lowercase alphanumerics, 4–6 chars.
  #>
  param(
    [string]$TenantId,
    [string]$TenantDisplayName
  )

  $namePart = $null
  if(-not [string]::IsNullOrWhiteSpace($TenantDisplayName)){
    $namePart = ($TenantDisplayName -replace '[^a-zA-Z0-9]', '').ToLower()
    if($namePart.Length -gt 3){ $namePart = $namePart.Substring(0,3) }
  }

  $idPart = $null
  if(-not [string]::IsNullOrWhiteSpace($TenantId)){
    $idPart = ($TenantId -replace '[^a-zA-Z0-9]', '').ToLower()
    if($idPart.Length -gt 3){ $idPart = $idPart.Substring(0,3) }
  }

  $suffix = "$namePart$idPart"
  if([string]::IsNullOrWhiteSpace($suffix) -and $idPart){
    $suffix = $idPart.Substring(0, [Math]::Min(6, $idPart.Length))
  }
  if([string]::IsNullOrWhiteSpace($suffix)){
    $suffix = 'tenant'
  } elseif($suffix.Length -gt 6){
    $suffix = $suffix.Substring(0,6)
  }
  return $suffix
}

function New-StorageAccountName {
  <# Returns a storage account name that preserves a suffix while honoring the 24-char limit. #>
  param(
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$Suffix
  )

  $prefixLower = $Prefix.ToLower()
  $suffixLower = $Suffix.ToLower()
  $maxLen = 24

  $candidate = "$prefixLower$suffixLower"
  if($candidate.Length -le $maxLen){ return $candidate }

  $trim = $candidate.Length - $maxLen
  $newPrefixLen = [Math]::Max($prefixLower.Length - $trim, 0)
  $result = $prefixLower.Substring(0, $newPrefixLen) + $suffixLower
  if($result.Length -gt $maxLen){
    $result = $result.Substring(0, $maxLen)
  }
  return $result
}
#endregion Functions

####################################################################################################
# INITIALIZATION OUTPUT
####################################################################################################
$script:Theme = New-ColorProfile
Write-Header 'Helsecert Blocklist Function App Onboarding'
Write-Section 'Initialization'
$ErrorActionPreference = 'Stop'

####################################################################################################
# MODULE CHECK / IMPORT
####################################################################################################
Write-Step 'Checking Az modules'
if(-not (Get-Module -ListAvailable -Name Az.Accounts)) { Install-Module Az -Scope CurrentUser -Force -Repository PSGallery }
Import-Module Az.Accounts
Import-Module Az.Resources   -ErrorAction SilentlyContinue
Import-Module Az.Functions   -ErrorAction SilentlyContinue
Import-Module Az.Network     -ErrorAction SilentlyContinue
Import-Module Az.Websites    -ErrorAction SilentlyContinue
Import-Module Az.PrivateDNS  -ErrorAction SilentlyContinue
Import-Module Az.Storage     -ErrorAction SilentlyContinue

# Prevent ANSI color codes in az prompts/output (cleaner in transcripts/logs)
$env:AZURE_CORE_NO_COLOR = '1'
$env:NO_COLOR            = '1'

####################################################################################################
# AUTHENTICATION (Fresh Context)
####################################################################################################
Write-Step 'Resetting Az contexts'
try { Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue | Out-Null; az logout 2>$null | Out-Null } catch { }
try { Get-AzContext -ListAvailable -ErrorAction SilentlyContinue | ForEach-Object { Remove-AzContext -Name $_.Name -Force -ErrorAction SilentlyContinue } } catch { }
Write-Step 'Authenticating to Azure'
az config set core.login_experience_v2=on 2>$null | Out-Null
az config set core.enable_broker_on_windows=false 2>$null | Out-Null
az login
$acct           = az account show --output json 2>$null | ConvertFrom-Json
$subscriptionId  = $acct.id
$tenantId        = $acct.tenantId
$accountUser     = $acct.user.name
$mgmt  = (az account get-access-token  --resource https://management.azure.com/  --query accessToken -o tsv 2>$null).Trim()
$graph = (az account get-access-token  --resource https://graph.microsoft.com/  --query accessToken -o tsv 2>$null).Trim()
$script:GraphAccessToken = $graph

# Attempt full token login; fall back to plain login if it fails
try { Connect-AzAccount -AccessToken $mgmt -GraphAccessToken $graph -Tenant $tenantId -AccountId $accountUser -SubscriptionId $subscriptionId | Out-Null } catch { Write-Host 'Connect-AzAccount (full token set) failed, falling back to plain login...' -ForegroundColor Yellow; Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId | Out-Null }
Set-AzContext -Subscription $subscriptionId | Out-Null
try { $currentCtx = Get-AzContext -ErrorAction Stop; if($currentCtx.Subscription.Id -ne $subscriptionId){ Set-AzContext -Subscription $subscriptionId | Out-Null } } catch { Set-AzContext -Subscription $subscriptionId | Out-Null }
$context = Get-AzContext; if(-not $context){ throw 'No Azure context available after login.' }
$subscription = Get-AzSubscription -SubscriptionId $context.Subscription.Id
Write-Field 'Subscription(final)' "$(($subscription.Name)) [$(($subscription.Id))]" 'SUB'

$signedInUserObjectId = Get-SignedInUserObjectId -UserPrincipalName $accountUser
Write-Step 'Validating subscription RBAC permissions'
try {
  $effectiveRole = Assert-SubscriptionRoleAssignment -UserObjectId $signedInUserObjectId -SubscriptionId $subscriptionId -AllowedRoles @('Owner','User Access Administrator') -UserPrincipalName $accountUser
  Write-Result -Status Success -Message "Current user has '$effectiveRole' role on subscription scope."
} catch {
  Write-ErrorPane -Message "Missing required Azure RBAC role: $($_.Exception.Message)" -Resolution 'Ensure you are Owner or User Access Administrator on the subscription so role assignments can be created, then rerun the script.'
  throw
}

# Connect to Microsoft Graph for managed identity role assignments
Write-Step 'Connecting to Microsoft Graph'
$requiredGraphScopes = @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All')
Connect-MgGraph -Scopes $requiredGraphScopes | Out-Null
Write-Result -Status Success -Message 'Connected to Microsoft Graph'

Write-Step 'Validating Microsoft Graph directory roles'
try {
  $graphRoles = Assert-GraphDirectoryAdminPermissions -RequiredRoles @('Application Administrator') -AnyOfRoles @('Privileged Role Administrator','Company Administrator','Global Administrator') -OverrideRolesSatisfyingAll @('Company Administrator','Global Administrator')
  Write-Result -Status Success -Message "Graph prerequisites satisfied (roles detected: $($graphRoles -join ', '))."
} catch {
  Write-ErrorPane -Message "Graph directory roles missing: $($_.Exception.Message)" -Resolution 'Activate the required Entra ID admin roles (Application Administrator AND Privileged Role Administrator or Global Administrator) before rerunning.'
  throw
}

# Tenant-specific suffix for globally unique names (storage/function app)
Write-Step 'Building tenant-specific name suffix'
$tenantDisplayName = $null
try {
  $tenantDisplayName = az rest --method GET --url https://graph.microsoft.com/v1.0/organization --query "value[0].displayName" -o tsv 2>$null
} catch { }
if([string]::IsNullOrWhiteSpace($tenantDisplayName)){ $tenantDisplayName = $tenantId }
$tenantSuffix = Get-TenantSuffix -TenantId $tenantId -TenantDisplayName $tenantDisplayName
$FunctionAppName  = "func-$WorkloadName-$Environment-$RegionCode-$Instance-$tenantSuffix"
$storageCandidate = "$StorageAccountPrefix$tenantSuffix"
$StorageAccount   = New-StorageAccountName -Prefix $StorageAccountPrefix -Suffix $tenantSuffix
if($StorageAccount -ne $storageCandidate){
  Write-ColoredLine "Storage account name trimmed to '$StorageAccount' to fit 24-char limit." $script:Theme.Warning
}
if(-not (Test-StorageAccountNameValid -Name $StorageAccount)) { throw "Generated storage account name '$StorageAccount' is invalid. Adjust workload/environment/instance or tenant suffix." }

####################################################################################################
# NAMING SUMMARY
####################################################################################################
Write-Section 'Naming Summary'
Write-Field 'Resource Group'     $ResourceGroup            'NAME'
Write-Field 'Function App'       $FunctionAppName          'NAME'
Write-Field 'App Service Plan'   $PlanName                 'NAME'
Write-Field 'Storage Account'    $StorageAccount           'NAME'
Write-Field 'Log Analytics'      $LogAnalyticsName         'NAME'
Write-Field 'App Insights'       $AppInsightsName          'NAME'
Write-Field 'Private Endpoint'   $pename                   'NAME'
Write-Field 'VNet Name'          "vnet-$WorkloadName-$Environment-$RegionCode-$Instance"  'NAME'
Write-Field 'Integration Subnet' "snet-$WorkloadName-integration-$Environment-$RegionCode-$Instance" 'NAME'
Write-Field 'PE Subnet'          "snet-$WorkloadName-pe-$Environment-$RegionCode-$Instance" 'NAME'
Write-Field 'Integration NSG'    "nsg-$WorkloadName-integration-$Environment-$RegionCode-$Instance" 'NAME'
Write-Field 'PE NSG'             "nsg-$WorkloadName-pe-$Environment-$RegionCode-$Instance" 'NAME'
Write-Field 'Private DNS Zone'   $PrivateDnsZoneName       'NAME'
Write-Field 'VNet Address Space' $VNetAddressSpace         'NETWORK'
Write-Field 'Integration Subnet' $IntegrationSubnetPrefix  'NETWORK'
Write-Field 'PE Subnet Prefix'   $PrivateEndpointSubnetPrefix 'NETWORK'
Write-ColoredLine '' 'Gray'

####################################################################################################
# INFRASTRUCTURE & AUTO-DETECTION
####################################################################################################
$InfraAlreadyExists = $false
Write-Step 'Detecting existing infrastructure'
if(Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue){
    if(Get-AzWebApp -Name $FunctionAppName -ResourceGroup $ResourceGroup -ErrorAction SilentlyContinue){
        if(Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccount -ErrorAction SilentlyContinue){
            $InfraAlreadyExists = $true
            Write-Result -Status Success -Message 'Detected existing Function App infrastructure. Will skip deployment steps.'
            $mode = 'AutoResume'
            
            # Check and apply managed identity permissions for existing infrastructure
            Write-Step 'Verifying managed identity Graph API permissions'
            try {
              $functionApp = Get-AzWebApp -Name $FunctionAppName -ResourceGroup $ResourceGroup
              $principalId = $functionApp.Identity.PrincipalId
              
              if([string]::IsNullOrWhiteSpace($principalId)){
                Write-Result -Status Warning -Message 'Function App does not have a managed identity enabled.'
              } else {
                Write-ColoredLine "Found managed identity principal ID: $principalId" $script:Theme.Info
                
                # Check and grant permissions using existing function
                $roleResult = Grant-ManagedIdentityAppPermissions -PrincipalId $principalId -Quiet
                
                if($roleResult.NewlyAssigned.Count -gt 0){
                  Write-Result -Status Success -Message ('Managed identity was missing permissions. Newly assigned: ' + ($roleResult.NewlyAssigned -join ', '))
                } elseif($roleResult.AlreadyPresent.Count -gt 0) {
                  Write-Result -Status Success -Message ('Managed identity already has all required permissions: ' + ($roleResult.AlreadyPresent -join ', '))
                } else {
                  Write-Result -Status Warning -Message 'Unable to verify managed identity permissions (no roles found).'
                }
              }
            } catch {
              Write-Result -Status Warning -Message "Failed to check/assign managed identity roles: $($_.Exception.Message)"
              Write-ColoredLine "You may need to manually assign 'Policy.Read.All' and 'Policy.ReadWrite.ConditionalAccess' Graph API permissions." $script:Theme.Warning
            }
        }
    }
}
if(-not $InfraAlreadyExists){
    $confirmMsg = 'Proceed with deployment? (Y/N)'
    $proceed = Read-Host $confirmMsg
    if($proceed -notin 'Y','y'){ Write-Result -Status Warning -Message 'User cancelled before deployment.'; throw 'Cancelled.' }
    Write-Result -Status Success -Message 'User confirmed deployment.'
    $HelseCertApiKey = $null
    while($true) {
        $HelseCertApiKey = Read-Host 'Enter HelseCert API Key (required)'
        if([string]::IsNullOrWhiteSpace($HelseCertApiKey)) { continue }
        if($HelseCertApiKey.Length -ne 32) {
            Write-Host 'The API key is not correct' -ForegroundColor Red
            $HelseCertApiKey = $null
            continue
        }
        break
    }
    $deploymentOutputs = $null
    $mode = 'Subscription'
    try {
        Write-Step 'Subscription-scope deployment - Please wait...'
        $d = New-AzSubscriptionDeployment -Name 'func-blocklist-deployment' -Location $Location -TemplateFile $BicepSub `
            -resourceGroupName $ResourceGroup `
            -workloadName $WorkloadName `
            -environment $Environment `
            -regionCode $RegionCode `
            -instance $Instance `
            -planName $PlanName `
            -functionAppName $FunctionAppName `
            -logAnalyticsName $LogAnalyticsName `
            -appInsightsName $AppInsightsName `
            -storageAccountName $StorageAccount `
            -vnetAddressSpace $VNetAddressSpace `
            -integrationSubnetPrefix $IntegrationSubnetPrefix `
            -privateEndpointSubnetPrefix $PrivateEndpointSubnetPrefix `
            -privateDnsZoneName $PrivateDnsZoneName `
            -privateDnsRecordName $PrivateDnsRecordName `
            -tags $ResourceTags `
            -ErrorAction Stop
        $deploymentOutputs = $d.Outputs
        Write-Result -Status Success -Message 'Subscription deployment succeeded.'
    } catch {
        Write-Result -Status Warning -Message "Subscription deployment failed: $($_.Exception.Message)"
        $mode = 'ResourceGroup'
        if(-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)){
            Write-Step 'Creating resource group'
            New-AzResourceGroup -Name $ResourceGroup -Location $Location -Tag $ResourceTags | Out-Null
        }
        Write-Step 'Resource group-scope deployment'
        $d = New-AzResourceGroupDeployment -Name 'func-blocklist-deployment' -ResourceGroupName $ResourceGroup -TemplateFile $BicepRg `
            -workloadName $WorkloadName `
            -environment $Environment `
            -regionCode $RegionCode `
            -instance $Instance `
            -planName $PlanName `
            -functionAppName $FunctionAppName `
            -logAnalyticsName $LogAnalyticsName `
            -appInsightsName $AppInsightsName `
            -storageAccountName $StorageAccount `
            -location $Location `
            -vnetAddressSpace $VNetAddressSpace `
            -integrationSubnetPrefix $IntegrationSubnetPrefix `
            -privateEndpointSubnetPrefix $PrivateEndpointSubnetPrefix `
            -privateDnsZoneName $PrivateDnsZoneName `
            -privateDnsRecordName $PrivateDnsRecordName `
            -tags $ResourceTags `
            -ErrorAction Stop
        $deploymentOutputs = $d.Outputs
        Write-Result -Status Success -Message 'Resource group deployment succeeded.'
  }
  try{
    Write-Step 'Granting managed identity Graph roles'
    $principalId = $deploymentOutputs.functionAppPrincipalId.value
    Start-Sleep -Seconds 10
    $roleResult = Grant-ManagedIdentityAppPermissions -PrincipalId $principalId -Quiet
    if($roleResult.NewlyAssigned.Count -gt 0){
      Write-Result -Status Success -Message ('Managed identity granted roles: ' + ($roleResult.NewlyAssigned -join ', '))
    } else {
      Write-Result -Status Success -Message 'Managed identity already had required roles.'
    }
  } catch {
    Write-Result -Status Warning -Message "Failed to assign managed identity roles: $($_.Exception.Message)"
  }

  Write-Step 'Setting app setting HelseCertApiKey'
  if($HelseCertApiKey -isnot [string]){
    try {
      if($HelseCertApiKey | Get-Member -Name SecretValueText -ErrorAction SilentlyContinue){
        $HelseCertApiKey = $HelseCertApiKey.SecretValueText
      } elseif($HelseCertApiKey | Get-Member -Name Value -ErrorAction SilentlyContinue) {
        $HelseCertApiKey = [string]$HelseCertApiKey.Value
      } else {
        $HelseCertApiKey = [string]$HelseCertApiKey
      }
    } catch {
      throw "Unable to coerce HelseCertApiKey to string: $($_.Exception.Message)"
    }
  }
  $HelseCertApiKey = ($HelseCertApiKey | ForEach-Object { $_.ToString() }).Trim()
  if([string]::IsNullOrWhiteSpace($HelseCertApiKey)) { throw 'HelseCertApiKey resolved to empty string after normalization.' }
  
  # Get existing app settings and merge with new one to preserve Application Insights settings
  $functionApp = Get-AzWebApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup
  $existingSettings = $functionApp.SiteConfig.AppSettings
  $newSettings = @{}
  
  # Preserve all existing settings (including APPLICATIONINSIGHTS_CONNECTION_STRING, etc.)
  foreach ($setting in $existingSettings) {
    $newSettings[$setting.Name] = $setting.Value
  }
  
  # Add or update HelseCertApiKey
  $newSettings['HelseCertApiKey'] = $HelseCertApiKey

  # Ensure timer function stays disabled until explicit activation phase later
  $newSettings['AzureWebJobs.TimerTriggerFunction.Disabled'] = 'true'
  $newSettings['BlocklistActivation'] = 'pending'
  
  # Apply merged settings
  Set-AzWebApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup -AppSettings $newSettings | Out-Null
  Write-Result -Status Success -Message 'App setting HelseCertApiKey set (existing settings preserved).'

  # Grant storage permissions for deployment (both current user and Function App managed identity)
  Write-Step 'Granting storage permissions for deployment'
  try {
    $currentUser = az ad signed-in-user show --query id -o tsv
    $storageAccountId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$StorageAccount"
    $functionApp = Get-AzWebApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup
    $managedIdentityPrincipalId = $functionApp.Identity.PrincipalId
    
    # Grant to current user
    $existingUserAssignment = az role assignment list `
      --assignee $currentUser `
      --role "Storage Blob Data Contributor" `
      --scope $storageAccountId `
      --query "[0].id" -o tsv 2>$null
    
    if([string]::IsNullOrWhiteSpace($existingUserAssignment)) {
      az role assignment create `
        --assignee $currentUser `
        --role "Storage Blob Data Contributor" `
        --scope $storageAccountId `
        --output none 2>$null
      Write-Result -Status Success -Message 'Storage Blob Data Contributor role assigned to current user.'
    } else {
      Write-Result -Status Success -Message 'Current user already has Storage Blob Data Contributor role.'
    }
    
    # Grant to Function App managed identity (critical for zip deploy)
    $existingMsiAssignment = az role assignment list `
      --assignee $managedIdentityPrincipalId `
      --role "Storage Blob Data Contributor" `
      --scope $storageAccountId `
      --query "[0].id" -o tsv 2>$null
    
    if([string]::IsNullOrWhiteSpace($existingMsiAssignment)) {
      az role assignment create `
        --assignee $managedIdentityPrincipalId `
        --role "Storage Blob Data Contributor" `
        --scope $storageAccountId `
        --output none 2>$null
      Write-Result -Status Success -Message 'Storage Blob Data Contributor role assigned to Function App managed identity.'
    } else {
      Write-Result -Status Success -Message 'Function App managed identity already has Storage Blob Data Contributor role.'
    }
    
    Write-ColoredLine 'Waiting 30 seconds for permission propagation...' $script:Theme.Step
    Start-Sleep -Seconds 30
  } catch {
    Write-Result -Status Warning -Message "Could not assign storage role: $($_.Exception.Message). Continuing anyway..."
  }

  # Deploy PowerShell function code
  Write-Step 'Deploying PowerShell function code'
  if(-not (Test-Path $FunctionFolder)) {
    Write-Result -Status Warning -Message "Function folder not found at '$FunctionFolder'. Skipping function deployment."
  } else {
    # Create a zip package of the function folder
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zipPath = Join-Path $env:TEMP "function-deploy-$timestamp.zip"
    
    try {
      # Compress function folder
      Compress-Archive -Path "$FunctionFolder\*" -DestinationPath $zipPath -Force
      Write-Result -Status Success -Message "Function package created: $zipPath"
      
      # Wait for Function App to be fully ready
      Write-ColoredLine "Waiting for Function App to be fully provisioned..." $script:Theme.Step
      Start-Sleep -Seconds 30
      
      # Deploy using Azure CLI (more reliable for Flex Consumption)
      Write-ColoredLine "Deploying function package via Azure CLI..." $script:Theme.Step
      $deployOutput = az functionapp deployment source config-zip `
        --resource-group $ResourceGroup `
        --name $FunctionAppName `
        --src $zipPath `
        --build-remote false `
        --timeout 600 `
        2>&1
      
      if($LASTEXITCODE -ne 0) {
        Write-Result -Status Warning -Message "Azure CLI deployment returned exit code $LASTEXITCODE"
        Write-ColoredLine "Output: $deployOutput" $script:Theme.Warning
        
        # Fallback: Try direct blob upload for Flex Consumption
        Write-ColoredLine "Attempting fallback: Upload to storage blob container..." $script:Theme.Step
        
        # Upload zip to the deployment container
        az storage blob upload `
          --account-name $StorageAccount `
          --container-name 'deploy' `
          --name 'function-package.zip' `
          --file $zipPath `
          --auth-mode login `
          --overwrite true `
          2>&1 | Out-Null
        
        if($LASTEXITCODE -eq 0) {
          Write-Result -Status Success -Message 'Function package uploaded to storage. Function App will sync automatically.'
        } else {
          throw "Both deployment methods failed. Please deploy manually via Azure Portal or check Function App status."
        }
      } else {
        Write-Result -Status Success -Message 'PowerShell function code deployed successfully.'
      }
      
      # Clean up temp zip file
      Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    } catch {
      Write-Result -Status Error -Message "Function deployment failed: $($_.Exception.Message)"
      Write-ColoredLine "You can manually deploy the function code from: $FunctionFolder" $script:Theme.Warning
      # Don't throw - allow script to continue with other setup steps
    }
  }

  try {
    # Enable VNet integration (idempotent; will skip if already present)
    Write-Step 'Enabling VNet integration'
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue | Select-Object -First 1
    $IntegrationSubnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet | Where-Object { $_.Name -like '*func*' -or $_.Name -like '*integration*' } | Select-Object -First 1
    $subnetId = az network vnet subnet show `
      --resource-group $ResourceGroup `
      --vnet-name $vnet.name `
      --name $integrationSubnet.name `
      --query id -o tsv

    az functionapp vnet-integration add `
      --name $FunctionAppName `
      --resource-group $ResourceGroup `
      --subnet $subnetId `
      --vnet $vnet.Name `
      --output none 2>$null
  } catch {
      Write-Result -Status Warning -Message "Failed to enable VNet integration: $($_.Exception.Message)"
  }


} else {
  Write-Result -Status Success -Message 'Skipping deployment phases due to detected existing infra.'
}

try{
  # Private Endpoint subnet (used in both paths)
  $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue | Select-Object -First 1
  $IntegrationSubnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet | Where-Object { $_.Name -like '*private*' -or $_.Name -like '*endpoint*' } | Select-Object -First 1
  $subnetId = az network vnet subnet show `
    --resource-group $ResourceGroup `
    --vnet-name $vnet.name `
    --name $integrationSubnet.name `
    --query id -o tsv
} catch {
  throw "Failed to determine Private Endpoint subnet: $($_.Exception.Message)"
}

try{
  # Idempotent Private Endpoint creation (only if missing)
  $existingPe = az network private-endpoint show -g $ResourceGroup -n $pename -o json 2>$null
  if(-not $existingPe){
    # Get tenant display name
    if([string]::IsNullOrWhiteSpace($tenantDisplayName)){
      $tenantDisplayName = az rest --method GET --url https://graph.microsoft.com/v1.0/organization --query "value[0].displayName" -o tsv
    }
    if([string]::IsNullOrWhiteSpace($tenantDisplayName)){ $tenantDisplayName = $tenantId }
    $tenantName = $tenantDisplayName
    $apiKeyForMsg = $HelseCertApiKey
    $peRequestMsg = "$tenantName - $apiKeyForMsg"
    az network private-endpoint create `
      -g $ResourceGroup `
      -n $pename `
      --subnet $subnetId `
      --connection-name "${pename}-conn" `
      --private-connection-resource-id $ResourceAlias `
      --manual-request true `
      --request-message "$peRequestMsg" `
      --output none 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){
      throw "Private Endpoint creation failed (exit $LASTEXITCODE). Verify the alias '$ResourceAlias' is correct and rerun."
    }
    Write-Result -Status Success -Message 'Private Endpoint creation requested.'
  } else {
    Write-Result -Status Success -Message 'Private Endpoint already exists; entering approval wait loop.'
  }
} catch {
  throw "Failed to create or detect Private Endpoint: $($_.Exception.Message)"
}

 # Simple inline wait loop for Private Endpoint approval with colored progress
 $maxWaitMinutes   = 60
 $pollSeconds      = 20
 $spinnerIntervalMs= 150
 $deadline         = (Get-Date).AddMinutes($maxWaitMinutes)
 Write-Step "Waiting for Private Endpoint approval (timeout ${maxWaitMinutes}m)"
 Start-Spinner "Private Endpoint '$pename' pending approval - please wait... this is manually approved by Helse- og KommuneCERT. Relaunch start.ps1 if this reaches timeout."
 $iteration = 0
 do {
   $iteration++
   # Poll current state once per outer loop - suppress ALL output
   $raw = az network private-endpoint show -g $ResourceGroup -n $pename -o json --only-show-errors 2>$null | Out-String
   $peObj = $null
   $rawTrim = $raw.Trim()
   if($rawTrim -and ($rawTrim.StartsWith('{') -or $rawTrim.StartsWith('['))){
     try { $peObj = $rawTrim | ConvertFrom-Json } catch { }
   }
   $connection = $null
   if($peObj){
     if($peObj.privateLinkServiceConnections -and $peObj.privateLinkServiceConnections.Count -gt 0){
       $connection = $peObj.privateLinkServiceConnections[0]
     } elseif($peObj.manualPrivateLinkServiceConnections -and $peObj.manualPrivateLinkServiceConnections.Count -gt 0){
       $connection = $peObj.manualPrivateLinkServiceConnections[0]
     }
   }
   $state = $connection.privateLinkServiceConnectionState.status
   $prov  = $connection.provisioningState
   if(-not $state){ $state = 'Provisioning' }
   if(-not $prov){ $prov = $peObj.provisioningState }
   if(-not $prov){ $prov = 'Provisioning' }
   if($state -eq 'Approved' -and $prov -eq 'Succeeded'){
     Stop-Spinner
     Write-Result -Status Success -Message "Private Endpoint approved after $iteration polls"
     break
   } elseif($state -eq 'Rejected') {
     Stop-Spinner
     Write-Result -Status Error -Message "Private Endpoint rejected (State: $state / $prov)"
     throw "Private Endpoint '$pename' was rejected."
   }
   if((Get-Date) -ge $deadline){ throw "Timed out waiting for Private Endpoint '$pename' approval (last state: $state / $prov, polls: $iteration)." }
   # Animate spinner while waiting for next poll
   $pollEnd = (Get-Date).AddSeconds($pollSeconds)
   while((Get-Date) -lt $pollEnd){
     Update-Spinner
     Start-Sleep -Milliseconds $spinnerIntervalMs
   }
 } while ($true)
 $global:PrivateEndpointState = 'Approved'

####################################################################################################
# RETRIEVE PRIVATE ENDPOINT IP & UPDATE FUNCTION APP SETTINGS (Robust Polling + NIC Fallback)
####################################################################################################
Write-Step 'Retrieving Private Endpoint IP address'
try {
  $privateIP    = $null
  $maxAttempts  = 15            # ~2 minutes worst case (15 * 8s)
  $waitSeconds  = 8

  for($attempt = 1; $attempt -le $maxAttempts -and -not $privateIP; $attempt++){
    $pe = Get-AzPrivateEndpoint -Name $pename -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
    if($pe){
      # First preference: CustomDnsConfigs (may appear slightly later than NIC IP)
      if($pe.CustomDnsConfigs){
        foreach($cfg in $pe.CustomDnsConfigs){
          if($cfg.IpAddresses){
            foreach($ipCandidate in $cfg.IpAddresses){
              if($ipCandidate -and $ipCandidate -match '^\d{1,3}(\.\d{1,3}){3}$'){ $privateIP = $ipCandidate; break }
            }
          }
          if($privateIP){ break }
        }
      }

      # Fallback: Private Endpoint NIC IP
      if(-not $privateIP -and $pe.NetworkInterfaces -and $pe.NetworkInterfaces.Count -gt 0){
        $nicId = $pe.NetworkInterfaces[0].Id
        if($nicId){
          $parts   = $nicId -split '/'
          $nicRg   = $parts[4]
          $nicName = $parts[8]
          $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $nicRg -ErrorAction SilentlyContinue
          if($nic -and $nic.IpConfigurations){
            foreach($ipConf in $nic.IpConfigurations){
              if($ipConf.PrivateIpAddress){ $privateIP = $ipConf.PrivateIpAddress; break }
            }
          }
        }
      }
    }

    if($privateIP){
      Write-Field 'Private IP' $privateIP 'NETWORK'
      Write-ColoredLine "Resolved private IP on attempt $attempt." $script:Theme.Info
      break
    } elseif ($attempt -lt $maxAttempts) {
  Write-ColoredLine "Attempt ${attempt}/${maxAttempts}: Private IP not yet available. Waiting ${waitSeconds}s..." $script:Theme.Step
      Start-Sleep -Seconds $waitSeconds
    }
  }

  if($privateIP){
    # Update Function App settings with Private Endpoint IP (merge with existing settings)
    Write-Step 'Updating Function App settings with Private Endpoint IP'
    $functionApp = Get-AzWebApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup
    $existingSettings = $functionApp.SiteConfig.AppSettings
    $newSettings = @{}
    foreach ($setting in $existingSettings) { $newSettings[$setting.Name] = $setting.Value }
    $newSettings['HelseCertPrivateEndpointIP'] = $privateIP
    Set-AzWebApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup -AppSettings $newSettings | Out-Null
    Write-Result -Status Success -Message "Private Endpoint IP '$privateIP' added to Function App settings."
  } else {
    Write-Result -Status Warning -Message "Private Endpoint IP not discovered after $maxAttempts attempts. You can rerun the script section later (PE is approved)."
  }
} catch {
  Write-Result -Status Warning -Message "Failed during Private Endpoint IP retrieval logic: $($_.Exception.Message)"
}

####################################################################################################
# ADD PRIVATE DNS A RECORD (Dynamic - after IP is resolved)
####################################################################################################
if($privateIP){
  Write-Step 'Configuring Private DNS A record'
  try {
    # Use script-level DNS configuration variables (already defined at top of script)
    
    # Check if DNS zone exists (should exist from Bicep deployment)
    $dnsZone = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroup -Name $privateDnsZoneName -ErrorAction SilentlyContinue
    
    if(-not $dnsZone){
      Write-Result -Status Warning -Message "Private DNS zone '$privateDnsZoneName' not found. Creating..."
      $dnsZone = New-AzPrivateDnsZone -ResourceGroupName $ResourceGroup -Name $privateDnsZoneName -Tag $ResourceTags
      
      # Link to VNet
      $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue | Select-Object -First 1
      New-AzPrivateDnsVirtualNetworkLink `
        -ResourceGroupName $ResourceGroup `
        -ZoneName $privateDnsZoneName `
        -Name "${vnet.Name}-link" `
        -VirtualNetworkId $vnet.Id `
        -EnableRegistration:$false | Out-Null
      
      Write-Result -Status Success -Message 'Private DNS zone created and linked to VNet.'
    }
    
    # Check if A record already exists
    $existingRecord = Get-AzPrivateDnsRecordSet `
      -ResourceGroupName $ResourceGroup `
      -ZoneName $privateDnsZoneName `
      -Name $privateDnsRecordName `
      -RecordType A `
      -ErrorAction SilentlyContinue
    
    if($existingRecord){
      # Update existing record if IP changed
      if($existingRecord.Records[0].Ipv4Address -ne $privateIP){
        $existingRecord.Records[0].Ipv4Address = $privateIP
        Set-AzPrivateDnsRecordSet -RecordSet $existingRecord | Out-Null
        Write-Result -Status Success -Message "Updated DNS A record '$privateDnsRecordName' to IP '$privateIP'"
      } else {
        Write-Result -Status Success -Message "DNS A record already exists with correct IP '$privateIP'"
      }
    } else {
      # Create new A record
      New-AzPrivateDnsRecordSet `
        -ResourceGroupName $ResourceGroup `
        -ZoneName $privateDnsZoneName `
        -Name $privateDnsRecordName `
        -RecordType A `
        -Ttl 300 `
        -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -Ipv4Address $privateIP) | Out-Null
      
      Write-Result -Status Success -Message "Created DNS A record '$privateDnsRecordName' → '$privateIP'"
    }
    
    $fqdn = "${privateDnsRecordName}.${privateDnsZoneName}"
    Write-Field 'Private DNS FQDN' $fqdn 'NETWORK'
    
  } catch {
    Write-Result -Status Warning -Message "Failed to configure Private DNS A record: $($_.Exception.Message)"
    Write-ColoredLine "You can manually add the A record via Azure Portal." $script:Theme.Warning
  }
}
 
####################################################################################################
# ACTIVATION PHASE - Enable timer trigger only after all settings & private IP resolved
####################################################################################################
Write-Step 'Activating TimerTriggerFunction'
try {
  $functionApp = Get-AzWebApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup
  $existingSettings = $functionApp.SiteConfig.AppSettings
  $updated = @{}
  foreach($s in $existingSettings){ $updated[$s.Name] = $s.Value }
  $updated['AzureWebJobs.TimerTriggerFunction.Disabled'] = 'false'
  $updated['BlocklistActivation'] = 'ready'
  Set-AzWebApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup -AppSettings $updated | Out-Null
  Write-Result -Status Success -Message 'Timer trigger function activated.'
} catch {
  Write-Result -Status Warning -Message "Failed to activate timer function: $($_.Exception.Message)"
}

####################################################################################################
# DISABLE PUBLIC NETWORK ACCESS (After all configuration is complete)
####################################################################################################
Write-Step 'Disabling public network access on Function App'
try {
  Write-ColoredLine "Waiting 30 seconds for function activation to complete..." $script:Theme.Step
  Start-Sleep -Seconds 30
  
  # Test connectivity before disabling public access
  Write-ColoredLine "Testing private connectivity before disabling public access..." $script:Theme.Step
  $testUrl = "https://$FunctionAppName.azurewebsites.net/api/healthcheck"
  try {
    Invoke-WebRequest -Uri $testUrl -Method Get -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
    Write-ColoredLine "Function App is responding." $script:Theme.Info
  } catch {
    Write-ColoredLine "Note: Health check endpoint not configured (expected)." $script:Theme.Info
  }
  
  # Disable public network access
  az functionapp update `
    --resource-group $ResourceGroup `
    --name $FunctionAppName `
    --set publicNetworkAccess=Disabled `
    --output none 2>$null
  
  if($LASTEXITCODE -eq 0) {
    Write-Result -Status Success -Message 'Public network access disabled. Function App now accessible only via VNet/Private Endpoint.'
    Write-ColoredLine "Note: Future deployments and management must be done from within the VNet or via Private Endpoint." $script:Theme.Warning
  } else {
    Write-Result -Status Warning -Message "Failed to disable public network access via Azure CLI. You can disable it manually via Azure Portal: Function App > Networking > Public access."
  }
} catch {
  Write-Result -Status Warning -Message "Failed to disable public network access: $($_.Exception.Message)"
  Write-ColoredLine "You can manually disable it via Azure Portal after verifying private connectivity." $script:Theme.Warning
}
  

Write-Result -Status Success -Message 'Onboarding completed.'

} finally {
  if (Get-Command -Name Stop-BlocklistLogging -ErrorAction SilentlyContinue) {
    try { Stop-BlocklistLogging } catch { }
  }
}



