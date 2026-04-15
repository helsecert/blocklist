<#
.SYNOPSIS
    Azure Functions-timer som synkroniserer HelseCERT-blokkliste-IP-rekker til Entra ID named locations.

.DESCRIPTION
    Funksjonen kjører etter en tidsplan (standard: hvert 5. minutt) for å:
    1. Laste ned siste IP-blokkliste fra HelseCERT via privat endepunkt
    2. Normalisere og fjerne duplikater i CIDR-oppføringer (IPv4 og IPv6)
    3. Synkronisere oppføringer til navngitte steder for betinget tilgang i Entra ID
    4. Automatisk dele store blokklister på flere navngitte steder (maks 2000 IP-er per sted)
    5. Holde på basissett av navngitte steder (01-10) for å støtte opptil 20 000 CIDR-er uten endring i CA-policyer

    De navngitte stedene kan deretter refereres i CA-policyer for å blokkere pålogginger
    fra kjente ondsinnede IP-adresser.

.NOTES
    Påkrevde miljøvariabler:
    - BlocklistActivation: Må settes til 'ready' for å aktivere funksjonen
    - HelseCertApiKey: API-nøkkel for HelseCERT-blokkliste
    - HelseCertPrivateEndpointFqdn eller HelseCertPrivateEndpointIP: Endepunkt for nedlasting av blokkliste

    Nødvendige tillatelser:
    - Microsoft Graph: Policy.Read.All, Policy.ReadWrite.ConditionalAccess

.LINK
    https://learn.microsoft.com/en-us/graph/api/resources/ipnamedlocation
#>

param($Timer)


#################################################################
#region HELPER FUNCTIONS
#################################################################

function Invoke-DownloadWithRetry {
    <#
    .SYNOPSIS
        Laster ned innhold fra en URL med automatisk retry og eksponentiell backoff.
    .PARAMETER Url
        URL-en som skal lastes ned fra.
    .PARAMETER MaxAttempts
        Maksimalt antall forsøk (standard: 3).
    .PARAMETER InitialDelaySeconds
        Startforsinkelse mellom forsøk i sekunder, dobles for hvert forsøk (standard: 5).
    .OUTPUTS
        Tekstinnholdet av den nedlastede ressursen.
    #>
    param(
        [string]$Url,
        [int]$MaxAttempts = 3,
        [int]$InitialDelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Host "Download attempt $attempt of $MaxAttempts..."
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            Write-Host "Download successful on attempt $attempt"
            return $response.Content
        }
        catch {
            $errMsg = $_.Exception.Message

            if ($attempt -eq $MaxAttempts) {
                throw
            }

            $delaySec = $InitialDelaySeconds * [Math]::Pow(2, $attempt - 1)
            Write-Warning "Attempt $attempt failed: $errMsg"
            Write-Host "Retrying in $delaySec seconds..."
            Start-Sleep -Seconds $delaySec
        }
    }
}


function Convert-Cidr {
    <#
    .SYNOPSIS
        Normaliserer en CIDR-oppføring for konsistent sammenligning og lagring.
    .DESCRIPTION
        - Fjerner mellomrom
        - Legger til /32-suffiks på rene IPv4-adresser
        - Legger til /128-suffiks på rene IPv6-adresser
        - Gjør IPv6-adresser små bokstaver (Graph API normaliserer til lowercase)
    .PARAMETER Entry
        Rå IP-adresse eller CIDR-streng.
    .OUTPUTS
        Normalisert CIDR-streng, eller $null hvis input er tom.
    #>
    param([string]$Entry)

    if (-not $Entry) { return $null }

    $e = $Entry.Trim()
    if (-not $e) { return $null }

    # If no / present, append host mask (/32 IPv4, /128 IPv6)
    if ($e -notmatch '/') {
        if ($e -match ':') {
            $e = "$e/128"
        }
        else {
            $e = "$e/32"
        }
    }

    # Lowercase IPv6 portion (Graph may normalize this)
    if ($e -match ':') {
        $e = $e.ToLowerInvariant()
    }

    return $e
}


function New-IpRangeObject {
    <#
    .SYNOPSIS
        Oppretter et Graph API ipRange-objekt fra en CIDR-streng.
    .PARAMETER Entry
        IP-adresse eller CIDR-streng.
    .OUTPUTS
        Hashtable med @odata.type og cidrAddress for Graph API, eller $null hvis ugyldig.
    #>
    param([string]$Entry)

    $e = Convert-Cidr -Entry $Entry
    if (-not $e) { return $null }

    if ($e -match ':') {
        return @{
            "@odata.type" = "#microsoft.graph.iPv6CidrRange"
            cidrAddress   = $e
        }
    }
    else {
        return @{
            "@odata.type" = "#microsoft.graph.iPv4CidrRange"
            cidrAddress   = $e
        }
    }
}


function Get-LocationIpRangeCount {
    <#
    .SYNOPSIS
        Returnerer antall IP-områder i et navngitt steds-objekt.
    .DESCRIPTION
        Håndterer både AdditionalProperties og direkte IpRanges-format
        som kan returneres av ulike versjoner av Microsoft Graph SDK.
    .PARAMETER Location
        Navngitt steds-objekt fra Graph API.
    .OUTPUTS
        Antall IP-områder, eller 0 hvis ingen finnes.
    #>
    param($Location)

    if (-not $Location) { return 0 }

    $ranges = @()

    if ($Location.PSObject.Properties['AdditionalProperties'] -and
        $Location.AdditionalProperties -and
        $Location.AdditionalProperties.ContainsKey('ipRanges')) {
        $ranges = $Location.AdditionalProperties['ipRanges']
    }
    elseif ($Location.PSObject.Properties['IpRanges'] -and $Location.IpRanges) {
        $ranges = $Location.IpRanges
    }

    if (-not $ranges) { return 0 }

    return @($ranges).Count
}


function New-CidrChunks {
    <#
    .SYNOPSIS
        Deler en liste med CIDR-er i bolker av gitt størrelse.
    .DESCRIPTION
        Graph API begrenser navngitte steder til 2000 IP-områder hver.
        Denne funksjonen deler større lister i flere bolker.
    .PARAMETER AllCidrs
        Array med normaliserte CIDR-strenger.
    .PARAMETER Size
        Maks antall oppføringer per bolk (standard: 2000).
    .OUTPUTS
        Array av arrays, hver med inntil Size CIDR-strenger.
    #>
    param(
        [string[]]$AllCidrs,
        [int]$Size
    )

    $result = [System.Collections.ArrayList]::new()

    for ($i = 0; $i -lt $AllCidrs.Count; $i += $Size) {
        $end = [Math]::Min($i + $Size - 1, $AllCidrs.Count - 1)
        $chunk = $AllCidrs[$i..$end]
        $null = $result.Add($chunk)
    }

    return , $result.ToArray()
}


function Get-PrefixNamedLocations {
    <#
    .SYNOPSIS
        Henter alle IP-navngitte steder som matcher et navneprefiks.
    .DESCRIPTION
        Spør Graph API etter alle navngitte steder for betinget tilgang,
        filtrerer til IP-typer med riktig prefiks, og henter detaljerte
        ipRanges-data for hver.
    .PARAMETER Prefix
        Visningsnavn-prefiks for filtrering (f.eks. "HelseCERT-Blocklist-").
    .OUTPUTS
        PSCustomObject med:
        - Locations: Array av navngitte steds-objekter med ipRanges utfylt
        - ByName: Hashtable som mapper displayName til array av matchende steder
    #>
    param([string]$Prefix)

    $result = [pscustomobject]@{
        Locations = @()
        ByName    = @{}
    }

    try {
        $baseSet = Get-MgIdentityConditionalAccessNamedLocation -All -ErrorAction Stop

        foreach ($loc in $baseSet) {
            if (-not $loc) { continue }

            $displayName = $loc.DisplayName
            if (-not $displayName) { continue }
            if ($displayName -notlike "$Prefix*") { continue }

            # Check if this is an IP named location
            $odataType = $null
            if ($loc.PSObject.Properties['AdditionalProperties'] -and
                $loc.AdditionalProperties -and
                $loc.AdditionalProperties.ContainsKey('@odata.type')) {
                $odataType = $loc.AdditionalProperties['@odata.type']
            }
            if ($odataType -ne '#microsoft.graph.ipNamedLocation') { continue }

            # Add to ByName mapping
            if (-not $result.ByName.ContainsKey($displayName)) {
                $result.ByName[$displayName] = @()
            }
            $result.ByName[$displayName] += $loc

            # Try to fetch detailed ipRanges data
            $detail = $null
            try {
                $detailCmd = Get-Command -Name Get-MgIdentityConditionalAccessNamedLocation -ErrorAction SilentlyContinue
                if ($detailCmd) {
                    $getParams = $detailCmd.Parameters.Keys
                    $candidateParams = @('ConditionalAccessNamedLocationId', 'NamedLocationId', 'Identity', 'Id') +
                                       ($getParams | Where-Object { $_ -match 'Id$' })

                    foreach ($p in $candidateParams | Select-Object -Unique) {
                        if ($getParams -contains $p) {
                            try {
                                $invokeParams = @{ }
                                $invokeParams[$p] = $loc.Id
                                $invokeParams['Property'] = 'id,displayName,ipRanges'
                                $detail = Get-MgIdentityConditionalAccessNamedLocation @invokeParams -ErrorAction SilentlyContinue
                                if ($detail) { break }
                            }
                            catch { continue }
                        }
                    }
                }
            }
            catch {
                Write-Verbose "[Diag] Exception during detail fetch loop for $($_.Exception.Message)"
            }

            if ($detail) {
                $result.Locations += $detail
            }
            else {
                $result.Locations += $loc
            }
        }
    }
    catch {
        Write-Warning "Failed to enumerate named locations via SDK: $($_.Exception.Message)"
    }

    return $result
}


function Remove-PlaceholderDuplicates {
    <#
    .SYNOPSIS
        Fjerner duplikate navngitte steder som kun har ett plassholder-IP-område.
    .DESCRIPTION
        Når duplikater finnes med samme displayName, beholdes den med flest IP-områder
        og oppføringer med kun én range (plassholder) slettes. Håndterer race-tilfeller
        der basisopprettelse og bolkoppdateringer lager midlertidige duplikater.
    .PARAMETER NameMap
        Hashtable som mapper displayName til array av steds-objekter.
    .OUTPUTS
        Antall steder som ble slettet.
    #>
    param([hashtable]$NameMap)

    $removed = 0

    foreach ($name in $NameMap.Keys) {
        $entries = @($NameMap[$name])
        if ($entries.Count -le 1) { continue }

        $keepers = $entries | Where-Object { (Get-LocationIpRangeCount -Location $_) -gt 1 }
        $deleteCandidates = $entries | Where-Object { (Get-LocationIpRangeCount -Location $_) -eq 1 }

        if (-not $keepers -or $keepers.Count -eq 0) {
            Write-Warning "Duplicate named locations found for $name but no non-placeholder entry; skipping auto-cleanup."
            continue
        }

        foreach ($del in $deleteCandidates) {
            if (-not $del.Id) {
                Write-Warning "Duplicate named location for $name missing Id; skipping delete."
                continue
            }

            try {
                $removeCmd = Get-Command -Name Remove-MgIdentityConditionalAccessNamedLocation -ErrorAction SilentlyContinue
                if (-not $removeCmd) {
                    Write-Warning "Remove-MgIdentityConditionalAccessNamedLocation cmdlet missing; cannot delete duplicate $name."
                    break
                }

                $candidateParams = @('ConditionalAccessNamedLocationId', 'NamedLocationId', 'Identity', 'Id') +
                                   ($removeCmd.Parameters.Keys | Where-Object { $_ -match 'Id$' })
                $paramName = ($candidateParams | Where-Object { $removeCmd.Parameters.ContainsKey($_) } | Select-Object -First 1)

                if (-not $paramName) {
                    Write-Warning "Unable to determine id parameter for delete cmdlet; cannot delete duplicate $name."
                    break
                }

                $splat = @{ }
                $splat[$paramName] = $del.Id.ToString()
                Remove-MgIdentityConditionalAccessNamedLocation @splat -ErrorAction Stop
                $removed++
                Write-Output "Deleted duplicate named location $name (placeholder range only)."
            }
            catch {
                Write-Warning "Failed to delete duplicate named location ${name}: $($_.Exception.Message)"
            }
        }
    }

    return $removed
}


function Test-CidrSetEqual {
    <#
    .SYNOPSIS
        Sammenligner to CIDR-arrays for sett-likhet.
    .DESCRIPTION
        Returnerer $true hvis begge arrays inneholder de samme elementene,
        uavhengig av rekkefølge eller duplikater i hvert array.
    .PARAMETER Left
        Første array med CIDR-strenger.
    .PARAMETER Right
        Andre array med CIDR-strenger.
    .OUTPUTS
        Boolsk verdi som indikerer sett-likhet.
    #>
    param(
        [string[]]$Left,
        [string[]]$Right
    )

    if ($null -eq $Left -and $null -eq $Right) { return $true }
    if (-not $Left) { $Left = @() }
    if (-not $Right) { $Right = @() }
    if ($Left.Count -ne $Right.Count) { return $false }

    $set = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($l in $Left) {
        if ($l) { $null = $set.Add($l) }
    }

    foreach ($r in $Right) {
        if ($r -and -not $set.Contains($r)) { return $false }
    }

    return $true
}


function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Kjører et scriptblock med automatisk retry ved feil.
    .DESCRIPTION
        Gjør nye forsøk ved HTTP 429 (throttling) og andre midlertidige feil.
        Bruker fast forsinkelse mellom forsøk.
    .PARAMETER Action
        Scriptblock som skal kjøres.
    .PARAMETER MaxAttempts
        Maksimalt antall forsøk (standard: 3).
    .PARAMETER DelaySeconds
        Forsinkelse mellom forsøk i sekunder (standard: 5).
    .OUTPUTS
        Resultatet av scriptblock-kjøringen.
    #>
    param(
        [ScriptBlock]$Action,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5
    )

    for ($a = 1; $a -le $MaxAttempts; $a++) {
        try {
            return & $Action
        }
        catch {
            $err = $_

            if ($err.Exception -and
                $err.Exception.Response -and
                $err.Exception.Response.StatusCode -eq 429 -and
                $a -lt $MaxAttempts) {
                Write-Warning "Throttled (429). Attempt $a/$MaxAttempts. Retrying after $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
            elseif ($a -lt $MaxAttempts) {
                Write-Warning "Attempt $a failed: $($err.Exception.Message). Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                throw
            }
        }
    }
}


function Write-NamedLocationChunk {
    <#
    .SYNOPSIS
        Oppretter eller oppdaterer ett navngitt sted med de angitte IP-områdene.
    .DESCRIPTION
        Hvis et navngitt sted med riktig indeks finnes i $indexedExisting,
        oppdateres det. Ellers opprettes et nytt. Bruker retry-innpakning for robusthet.
    .PARAMETER ChunkCidrs
        Array av CIDR-strenger som skal lagres i dette navngitte stedet.
    .PARAMETER DisplayIndex
        Numerisk indeks for visningsnavnet (f.eks. 1 for "HelseCERT-Blocklist-01").
    #>
    param(
        [string[]]$ChunkCidrs,
        [int]$DisplayIndex
    )

    # Build display name (e.g., "HelseCERT-Blocklist-01")
    $displayNumber = "{0:00}" -f $DisplayIndex
    $displayName = "$prefix$displayNumber"

    # Convert CIDRs to IP range objects
    $ranges = @()
    foreach ($c in $ChunkCidrs) {
        $rangeObj = New-IpRangeObject -Entry $c
        if ($rangeObj) {
            $ranges += $rangeObj
        }
    }

    # Prepare shared body for create/update
    $body = @{
        "@odata.type" = "#microsoft.graph.ipNamedLocation"
        displayName   = $displayName
        isTrusted     = $false
        ipRanges      = $ranges
    }

    # Check if location already exists
    if ($indexedExisting.ContainsKey($DisplayIndex)) {
        # UPDATE existing location
        $loc = $indexedExisting[$DisplayIndex]

        $patchBody = $body

        # Find the update cmdlet and determine the ID parameter name
        $updateCmd = Get-Command -Name Update-MgIdentityConditionalAccessNamedLocation -ErrorAction SilentlyContinue
        if (-not $updateCmd) {
            throw "Update-MgIdentityConditionalAccessNamedLocation cmdlet missing."
        }

        $existingId = $loc.Id
        if (-not $existingId) {
            throw "Existing location missing Id."
        }

        # Try different parameter names for the ID
        $candidateParams = @('ConditionalAccessNamedLocationId', 'NamedLocationId', 'Identity', 'Id') +
                           ($updateCmd.Parameters.Keys | Where-Object { $_ -match 'Id$' })
        $paramName = ($candidateParams | Where-Object { $updateCmd.Parameters.ContainsKey($_) } | Select-Object -First 1)

        if (-not $paramName) {
            throw "Unable to determine id parameter for update cmdlet (candidates tried: $($candidateParams -join ', '))."
        }

        # Execute update with retry, but fall back to create if the object disappeared
        $splat = @{
            BodyParameter = $patchBody
        }
        $splat[$paramName] = $existingId.ToString()

        $updateSucceeded = $false

        try {
            Invoke-WithRetry -Action {
                Update-MgIdentityConditionalAccessNamedLocation @splat -ErrorAction Stop
            } | Out-Null

            $script:updated++
            $updateSucceeded = $true
            Write-Output "Overwrote existing $displayName (CIDRs: $($ChunkCidrs.Count))"
        }
        catch {
            $err = $_
            $errText = $err | Out-String
            $statusCode = $null

            if ($err.Exception -and $err.Exception.Response -and $err.Exception.Response.StatusCode) {
                $statusCode = $err.Exception.Response.StatusCode
            }
            elseif ($err.Exception -and $err.Exception.PSObject.Properties['StatusCode']) {
                $statusCode = $err.Exception.StatusCode
            }
            elseif ($errText -match 'Status:\s*(\d{3})') {
                $statusCode = [int]$Matches[1]
            }

            $isNotFound = ($statusCode -eq 404 -or $errText -match 'ResourceNotFound' -or $errText -match 'does not exist in the directory')

            if (-not $isNotFound) {
                throw
            }

            Write-Warning "Named location $displayName (Id=$existingId) not found in Graph. Recreating..."

            # Try a fresh lookup by displayName in case the ID changed
            $refreshed = $null
            try {
                $filterName = $displayName -replace "'", "''"
                $refreshed = Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$filterName'" -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "Refresh lookup for $displayName failed: $($_.Exception.Message)"
            }

            $refreshedId = $null
            if ($refreshed) {
                $refreshed = @($refreshed)
                $refreshedOne = $refreshed | Sort-Object { Get-LocationIpRangeCount -Location $_ } -Descending | Select-Object -First 1
                $refreshedId = $refreshedOne.Id
                if ($refreshedId) {
                    $indexedExisting[$DisplayIndex] = $refreshedOne
                }
            }

            if ($refreshedId) {
                $splat[$paramName] = $refreshedId.ToString()

                Invoke-WithRetry -Action {
                    Update-MgIdentityConditionalAccessNamedLocation @splat -ErrorAction Stop
                } | Out-Null

                $script:updated++
                $updateSucceeded = $true
                Write-Output "Overwrote existing $displayName after refresh (CIDRs: $($ChunkCidrs.Count))"
            }
            else {
                $newLoc = Invoke-WithRetry -Action {
                    New-MgIdentityConditionalAccessNamedLocation -BodyParameter $body -ErrorAction Stop
                }

                if ($newLoc) {
                    $indexedExisting[$DisplayIndex] = $newLoc
                }

                $script:created++
                $updateSucceeded = $true
                Write-Output "Created ${displayName} (CIDRs: $($ChunkCidrs.Count)) after missing existing location"
            }
        }

        if (-not $updateSucceeded) {
            throw "Failed to update or recreate named location $displayName."
        }
    }
    else {
        # CREATE new location
        $newLoc = Invoke-WithRetry -Action {
            New-MgIdentityConditionalAccessNamedLocation -BodyParameter $body -ErrorAction Stop
        }

        if ($newLoc) {
            $indexedExisting[$DisplayIndex] = $newLoc
        }

        $script:created++
        Write-Output "Created ${displayName} (CIDRs: $($ChunkCidrs.Count))"
    }

    # Track the highest index used
    if ($DisplayIndex -gt $script:maxDisplayIndexUsed) {
        $script:maxDisplayIndexUsed = $DisplayIndex
    }
}


function Process-ChunkWithBackoff {
    <#
    .SYNOPSIS
        Skriver en bolk med CIDR-er med automatisk splitting hvis størrelsesgrensen nås.
    .DESCRIPTION
        Forsøker å skrive bolken. Hvis Graph API returnerer feil 1050 (PolicyDetail
        størrelse), deles bolken i to og kjøres på nytt rekursivt. Prøver også på nytt
        ved midlertidige serverfeil (500, 503, 504).
    .PARAMETER ChunkCidrs
        Array av CIDR-strenger for denne bolken.
    .PARAMETER DisplayIndex
        Startindeks for navngivning av sted.
    .OUTPUTS
        Neste tilgjengelige indeks etter prosessering.
    #>
    param(
        [string[]]$ChunkCidrs,
        [int]$DisplayIndex
    )

    if (-not $ChunkCidrs -or $ChunkCidrs.Count -eq 0) {
        return $DisplayIndex
    }

    $maxAttempts = 4
    $delay = 5

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Write-NamedLocationChunk -ChunkCidrs $ChunkCidrs -DisplayIndex $DisplayIndex
            return ($DisplayIndex + 1)
        }
        catch {
            $errText = $_ | Out-String
            $statusCode = $null

            if ($_.Exception -and $_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = $_.Exception.Response.StatusCode
            }
            elseif ($_.Exception -and $_.Exception.PSObject.Properties['StatusCode']) {
                $statusCode = $_.Exception.StatusCode
            }
            elseif ($errText -match 'Status:\s*(\d{3})') {
                $statusCode = [int]$Matches[1]
            }

            # Error 1050: PolicyDetail size limit - split chunk in half
            if ($errText -match '1050' -and $ChunkCidrs.Count -gt 1) {
                $mid = [Math]::Max(1, [Math]::Floor($ChunkCidrs.Count / 2))
                $first = $ChunkCidrs[0..($mid - 1)]
                $second = $ChunkCidrs[$mid..($ChunkCidrs.Count - 1)]

                Write-Warning "PolicyDetail size limit (1050) hit for chunk size $($ChunkCidrs.Count). Splitting into $($first.Count) and $($second.Count)."

                $nextIndex = Process-ChunkWithBackoff -ChunkCidrs $first -DisplayIndex $DisplayIndex | Select-Object -Last 1
                return (Process-ChunkWithBackoff -ChunkCidrs $second -DisplayIndex $nextIndex | Select-Object -Last 1)
            }

            # Retry on transient server errors
            if ($statusCode -in 500, 503, 504 -and $attempt -lt $maxAttempts) {
                Write-Warning "Transient server error ($statusCode). Attempt $attempt/$maxAttempts. Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
                $delay = [Math]::Min(30, $delay * 2)
                continue
            }

            # Fail on persistent errors
            Write-Error $_
            $script:failed++
            throw
        }
    }
}

#endregion HELPER FUNCTIONS


#################################################################
#region MAIN EXECUTION
#################################################################

# Sikring: Ikke kjør funksjonslogikk før aktiveringsflagget er satt av onboardingskriptet
if ($env:BlocklistActivation -ne 'ready') {
    Write-Output "TimerTriggerFunction not activated yet (BlocklistActivation=$($env:BlocklistActivation)). Exiting."
    return
}

Write-Output "Timer trigger function executed at: $(Get-Date)"

#----------------------------------------------------------------
# Konfigurasjonsinnlasting
#----------------------------------------------------------------

# Hent API-nøkkelen fra miljøvariabel
$apiKey = $env:HelseCertApiKey

if (-not $apiKey) {
    Write-Error "HelseCertApiKey environment variable not found"
    throw "Missing required configuration"
}
else {
    Write-Output "HelseCertApiKey found (length: $($apiKey.Length))"
}

# Hent privat endepunkt FQDN (foretrukket) eller IP fra miljøvariabel
$privateEndpointFqdn = $env:HelseCertPrivateEndpointFqdn
$privateEndpointIP = $env:HelseCertPrivateEndpointIP

if ($privateEndpointFqdn) {
    $targetHost = $privateEndpointFqdn
    Write-Output "Using Private Endpoint FQDN: $privateEndpointFqdn"
}
elseif ($privateEndpointIP) {
    $targetHost = $privateEndpointIP
    Write-Output "Using Private Endpoint IP (fallback): $privateEndpointIP"
}
else {
    Write-Error "Neither HelseCertPrivateEndpointFqdn nor HelseCertPrivateEndpointIP environment variable found"
    throw "Missing required configuration"
}

#----------------------------------------------------------------
# Graph API-tilkobling
#----------------------------------------------------------------

try {
    $context = Get-MgContext
    if (-not $context) {
        Write-Output "No active Graph context, connecting..."
        Connect-MgGraph -Identity -NoWelcome
    }
    else {
        Write-Output "Using existing Graph connection"
    }
}
catch {
    Write-Error "Failed to get Graph context: $_"
    throw
}

#----------------------------------------------------------------
# Last ned blokkliste-data
#----------------------------------------------------------------

$blocklistDataUrl = "https://${targetHost}/v3?apikey=$apiKey&format=list_cidr&type=ipv4&type=ipv4_cidr&type=ipv6&type=ipv6_cidr&list_name=auth&list_name=default&azureautomationtest=true"
$tempPath = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
$namedLocations = Join-Path $tempPath "NamedLocations.csv"

Write-Output "Downloading blocklist from HelseCert on $targetHost..."

try {
    $content = Invoke-DownloadWithRetry -Url $blocklistDataUrl
    $content | Out-File $namedLocations -Encoding ASCII

    Write-Output "Blokklist downloaded"
    $totalLines = (Get-Content $namedLocations).Count
    Write-Output "Blocklist CIDR ranges: $totalLines"
}
catch {
    Write-Error "Failed to download blocklist after retries: $($_.Exception.Message)"
    throw
}

#----------------------------------------------------------------
# Parse og normaliser CIDR-oppføringer
#----------------------------------------------------------------

$prefix = "HelseCERT-Blocklist-"
$chunkSize = 2000
$rawLines = Get-Content $namedLocations -ErrorAction Stop

# Filtrer ut tomme linjer
$cidrLines = @()
foreach ($l in $rawLines) {
    if ($null -ne $l -and $l -ne '') {
        $cidrLines += $l
    }
}

if ($cidrLines.Count -eq 0) {
    Write-Warning "No CIDR entries found (after removing empty lines). Exiting sync."
    return
}

Write-Output "Preparing to sync $($cidrLines.Count) entries into named locations…"

# Debug-flag (sett BlocklistDebug=1 for detaljert diagnostikk)
$debugEnabled = $false
if ($env:BlocklistDebug -eq '1') {
    $debugEnabled = $true
    Write-Output "[Debug] Blocklist debug mode enabled."
}

# Dedup normaliserte linjer FØR bolking slik at fingeravtrykk matcher Graph-kanonisk form
$normalizedUniqueCidrs = @()
$seen = [System.Collections.Generic.HashSet[string]]::new()

foreach ($raw in $cidrLines) {
    $n = Convert-Cidr -Entry $raw
    if ($n -and $seen.Add($n)) {
        $normalizedUniqueCidrs += $n
    }
}

if ($debugEnabled) {
    Write-Output "[Debug] Raw lines count: $($cidrLines.Count); Normalized unique count: $($normalizedUniqueCidrs.Count)"
    $sample = $normalizedUniqueCidrs | Select-Object -First 5
    Write-Output "[Debug] Sample normalized CIDRs: $($sample -join ', ')"
}

# Erstatt cidrLines med normalizedUniqueCidrs for videre behandling
$cidrLines = $normalizedUniqueCidrs

#----------------------------------------------------------------
# Initier synk-tellere og tilstand
#----------------------------------------------------------------

$created = 0
$updated = 0
$deleted = 0
$cleared = 0
$failed = 0

$desiredAllCidrsSorted = ($cidrLines | Sort-Object -Unique)

# Plassholder-range for å holde overskuddssteder gyldige (Graph krever minst ett ipRange)
$placeholderEntry = if ($desiredAllCidrsSorted.Count -gt 0) { $desiredAllCidrsSorted[0] } else { '203.0.113.0/32' }
$placeholderRange = New-IpRangeObject -Entry $placeholderEntry
$maxDisplayIndexUsed = 0

#----------------------------------------------------------------
# Enumerer eksisterende navngitte steder
#----------------------------------------------------------------

$enumResult = Get-PrefixNamedLocations -Prefix $prefix
$existingLocations = $enumResult.Locations
$prefixLocationsByName = $enumResult.ByName

# Auto-opprydding av duplikater med én range når en rikere oppføring finnes
$duplicateCleanupCount = Remove-PlaceholderDuplicates -NameMap $prefixLocationsByName
if ($duplicateCleanupCount -gt 0) {
    Write-Output "Duplicate cleanup deleted $duplicateCleanupCount placeholder named locations. Re-enumerating..."
    $enumResult = Get-PrefixNamedLocations -Prefix $prefix
    $existingLocations = $enumResult.Locations
    $prefixLocationsByName = $enumResult.ByName
}

# Kartlegg eksisterende steder etter numerisk indeks
$indexedExisting = @{}
foreach ($loc in $existingLocations) {
    if ($loc.DisplayName -and ($loc.DisplayName -match "^$([regex]::Escape($prefix))(\d+)$")) {
        $idx = [int]$Matches[1]

        if ($indexedExisting.ContainsKey($idx)) {
            # Behold den med flest IP-områder
            $current = $indexedExisting[$idx]
            if ((Get-LocationIpRangeCount -Location $loc) -gt (Get-LocationIpRangeCount -Location $current)) {
                $indexedExisting[$idx] = $loc
            }
        }
        else {
            $indexedExisting[$idx] = $loc
        }
    }
}

#----------------------------------------------------------------
# Sørg for at basis-navngitte steder finnes (01-10)
#----------------------------------------------------------------

$baselineCount = 10
$baselineCreated = $false
$baselineStart = "{0:00}" -f 1
$baselineEnd = "{0:00}" -f $baselineCount

Write-Output "Ensuring baseline named locations ($prefix$baselineStart through $prefix$baselineEnd) exist..."

for ($baseIdx = 1; $baseIdx -le $baselineCount; $baseIdx++) {
    if (-not $indexedExisting.ContainsKey($baseIdx)) {
        $displayNumber = "{0:00}" -f $baseIdx
        $displayName = "$prefix$displayNumber"

        # Dobbeltsjekk på displayName for å unngå duplisert basisopprettelse
        $existingByName = @()
        if ($prefixLocationsByName.ContainsKey($displayName)) {
            $existingByName = @($prefixLocationsByName[$displayName])
        }

        if (-not $existingByName) {
            try {
                $filterName = $displayName -replace "'", "''"
                $existingByName = Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$filterName'" -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "Baseline lookup by displayName failed for ${displayName}: $($_.Exception.Message)"
            }
        }

        if ($existingByName) {
            $existingByName = @($existingByName)
            $existingOne = $existingByName | Sort-Object { Get-LocationIpRangeCount -Location $_ } -Descending | Select-Object -First 1

            if ($existingByName.Count -gt 1) {
                Write-Warning "Multiple named locations found with displayName $displayName. Using the one with the most IP ranges."
            }

            $indexedExisting[$baseIdx] = $existingOne
            Write-Output "Baseline named location already exists: $displayName"
            continue
        }

        # Opprett med plassholder-range (overskrives med ekte data om nødvendig)
        $body = @{
            "@odata.type" = "#microsoft.graph.ipNamedLocation"
            displayName   = $displayName
            isTrusted     = $false
            ipRanges      = @($placeholderRange)
        }

        try {
            $newLoc = Invoke-WithRetry -Action {
                New-MgIdentityConditionalAccessNamedLocation -BodyParameter $body -ErrorAction Stop
            }
            Write-Output "Created baseline named location: $displayName"

            if ($newLoc) {
                $indexedExisting[$baseIdx] = $newLoc
            }
            $created++
            $baselineCreated = $true
        }
        catch {
            Write-Error "Failed to create baseline named location $displayName`: $($_.Exception.Message)"
            $failed++
        }
    }
}

# Re-registrer etter basisopprettelse for å få friske ID-er fra Graph
# MEN behold oppføringene vi nettopp opprettet dersom Graph ikke har replikert ennå
if ($baselineCreated) {
    Write-Output "Re-enumerating named locations after baseline creation..."
    Start-Sleep -Seconds 3  # Brief delay for Graph API consistency

    $enumResult = Get-PrefixNamedLocations -Prefix $prefix
    $existingLocations = $enumResult.Locations
    $prefixLocationsByName = $enumResult.ByName

    # Behold eksisterende oppføringer - oppdater kun hvis ny enum gir data for indeksen
    $enumeratedIndexes = @{}
    foreach ($loc in $existingLocations) {
        if ($loc.DisplayName -and ($loc.DisplayName -match "^$([regex]::Escape($prefix))(\d+)$")) {
            $idx = [int]$Matches[1]
            $enumeratedIndexes[$idx] = $loc
        }
    }

    # Flett: enum-data har prioritet, men behold lokale oppføringer hvis Graph ikke returnerte dem ennå
    foreach ($idx in $enumeratedIndexes.Keys) {
        $indexedExisting[$idx] = $enumeratedIndexes[$idx]
    }
}

# Opprydding av duplikater etter basisopprettelse
$duplicateCleanupCountPost = Remove-PlaceholderDuplicates -NameMap $prefixLocationsByName
if ($duplicateCleanupCountPost -gt 0) {
    Write-Output "Duplicate cleanup (post-baseline) deleted $duplicateCleanupCountPost placeholder named locations. Re-enumerating..."

    $enumResult = Get-PrefixNamedLocations -Prefix $prefix
    $existingLocations = $enumResult.Locations
    $prefixLocationsByName = $enumResult.ByName

    # Flett enum-data men behold lokale oppføringer som Graph ikke returnerte
    $enumeratedIndexes = @{}
    foreach ($loc in $existingLocations) {
        if ($loc.DisplayName -and ($loc.DisplayName -match "^$([regex]::Escape($prefix))(\d+)$")) {
            $idx = [int]$Matches[1]
            $enumeratedIndexes[$idx] = $loc
        }
    }

    foreach ($idx in $enumeratedIndexes.Keys) {
        $indexedExisting[$idx] = $enumeratedIndexes[$idx]
    }
}

#----------------------------------------------------------------
# Samle eksisterende CIDR-er for sammenligning
#----------------------------------------------------------------

$aggregatedExistingCidrsSet = [System.Collections.Generic.HashSet[string]]::new()
$existingLocationCidrsMap = @{}

foreach ($loc in $existingLocations) {
    if (-not $loc) { continue }

    $cidrs = @()
    if ($loc.PSObject.Properties['AdditionalProperties'] -and
        $loc.AdditionalProperties -and
        $loc.AdditionalProperties.ContainsKey('ipRanges')) {
        $cidrs = $loc.AdditionalProperties['ipRanges'] | ForEach-Object { Convert-Cidr -Entry $_.cidrAddress }
    }
    elseif ($loc.PSObject.Properties['IpRanges'] -and $loc.IpRanges) {
        $cidrs = $loc.IpRanges | ForEach-Object { Convert-Cidr -Entry $_.cidrAddress }
    }

    $normalized = ($cidrs | Where-Object { $_ } | Sort-Object -Unique)
    $existingLocationCidrsMap[$loc.DisplayName] = $normalized

    foreach ($c in $normalized) {
        $null = $aggregatedExistingCidrsSet.Add($c)
    }
}

#----------------------------------------------------------------
# Bestem synk-handling
#----------------------------------------------------------------

$missingCount = ($desiredAllCidrsSorted | Where-Object { -not $aggregatedExistingCidrsSet.Contains($_) }).Count
$extraCount = ($aggregatedExistingCidrsSet | Where-Object { $desiredAllCidrsSorted -notcontains $_ }).Count

# Bestem synk-handling basert på CIDR-sammenligning
if ($missingCount -eq 0 -and $extraCount -eq 0 -and $existingLocations.Count -gt 0) {
    # Alle CIDR-er allerede til stede og ingen utdaterte oppføringer - ingenting å gjøre
    Write-Output "All desired CIDRs already represented across existing named locations. No overwrite needed."
    Write-Output "Sync summary: Total CIDRs=$($desiredAllCidrsSorted.Count); Missing=0; Extra=0; Created=$created; Updated=$updated; Unchanged=$($existingLocations.Count); Deleted=$deleted; Failed=$failed"
    return
}
elseif ($missingCount -gt 0) {
    Write-Output "Detected $missingCount missing CIDRs. Performing full overwrite of all $prefix* named locations."
}
elseif ($extraCount -gt 0) {
    Write-Output "Detected $extraCount extra CIDRs in existing locations (blocklist was cleaned up). Performing full overwrite of all $prefix* named locations."
}
else {
    # missingCount = 0, extraCount = 0, existingLocations.Count = 0 (initial creation)
    Write-Output "No existing data found. Performing initial creation of $prefix* named locations."
}

#----------------------------------------------------------------
# Prosesser CIDR-bolker
#----------------------------------------------------------------

Write-Output "Computing overwrite chunks..."
$chunks = New-CidrChunks -AllCidrs $desiredAllCidrsSorted -Size $chunkSize
Write-Output "Total chunks required: $($chunks.Count) for $($desiredAllCidrsSorted.Count) CIDRs (chunk size $chunkSize)."

# Prosesser bolker med adaptiv backoff
$currentIndex = 1
for ($i = 0; $i -lt $chunks.Count; $i++) {
    $chunkCidrs = $chunks[$i]
    $currentIndex = Process-ChunkWithBackoff -ChunkCidrs $chunkCidrs -DisplayIndex $currentIndex | Select-Object -Last 1
}

#----------------------------------------------------------------
# Sluttopprydding
#----------------------------------------------------------------

# Siste duplikatopprydding etter bolkskriving (sikrer fjerning av plassholder-duplikater i samme kjøring)
try {
    $postEnum = Get-PrefixNamedLocations -Prefix $prefix
    $postMap = $postEnum.ByName
    $postCleanup = Remove-PlaceholderDuplicates -NameMap $postMap

    if ($postCleanup -gt 0) {
        Write-Output "Final duplicate cleanup deleted $postCleanup placeholder named locations."
    }
}
catch {
    Write-Warning "Final duplicate cleanup failed: $($_.Exception.Message)"
}

# Brief settle time and re-enumeration to get fresh IDs before clearing surplus slots
Start-Sleep -Seconds 2
$refreshEnum = Get-PrefixNamedLocations -Prefix $prefix
$existingLocations = $refreshEnum.Locations
$indexedExisting = @{}
foreach ($loc in $existingLocations) {
    if ($loc.DisplayName -and ($loc.DisplayName -match "^$([regex]::Escape($prefix))(\d+)$")) {
        $idx = [int]$Matches[1]
        $indexedExisting[$idx] = $loc
    }
}

# Clear surplus existing locations with higher indices (cannot delete if referenced in policies)
$maxNeeded = if ($maxDisplayIndexUsed -gt 0) { $maxDisplayIndexUsed } else { $chunks.Count }
$clearDelaySeconds = 2

foreach ($kv in $indexedExisting.GetEnumerator()) {
    # Clear locations beyond what we actually used this run (even baseline slots) to avoid stale ranges
    if ($kv.Key -gt $maxNeeded) {
        $surplusLoc = $kv.Value

        try {
            $updateCmd = Get-Command -Name Update-MgIdentityConditionalAccessNamedLocation -ErrorAction SilentlyContinue

            if ($updateCmd) {
                $candidateParams = @('ConditionalAccessNamedLocationId', 'NamedLocationId', 'Identity', 'Id') +
                                   ($updateCmd.Parameters.Keys | Where-Object { $_ -match 'Id$' })
                $paramName = ($candidateParams | Where-Object { $updateCmd.Parameters.ContainsKey($_) } | Select-Object -First 1)

                $rangesToSet = @()
                if ($placeholderRange) {
                    $rangesToSet += $placeholderRange
                }

                $patchBody = @{
                    "@odata.type" = "#microsoft.graph.ipNamedLocation"
                    displayName   = $surplusLoc.DisplayName
                    isTrusted     = $false
                    ipRanges      = $rangesToSet
                }

                $splat = @{ BodyParameter = $patchBody }
                $splat[$paramName] = $surplusLoc.Id

                if ($clearDelaySeconds -gt 0) {
                    Start-Sleep -Seconds $clearDelaySeconds
                }

                Invoke-WithRetry -Action {
                    Update-MgIdentityConditionalAccessNamedLocation @splat
                } | Out-Null

                $cleared++
                Write-Output "Cleared surplus named location $($surplusLoc.DisplayName) (set placeholder range $placeholderEntry)"
            }
        }
        catch {
            $errText = $_ | Out-String
            $statusCode = $null
            if ($_.Exception -and $_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = $_.Exception.Response.StatusCode
            }
            elseif ($errText -match 'Status:\s*(\d{3})') {
                $statusCode = [int]$Matches[1]
            }

            # If the named location disappeared (e.g., manual delete), ignore and continue
            if ($statusCode -eq 404 -or $errText -match 'ResourceNotFound') {
                Write-Warning "Surplus location $($surplusLoc.DisplayName) missing during clear; skipping."
                continue
            }

            # Treat transient server errors as warnings and continue
            if ($statusCode -in 500, 503) {
                Write-Warning "Transient error clearing surplus location $($surplusLoc.DisplayName): $errText"
                continue
            }

            Write-Error "Failed to clear surplus location $($surplusLoc.DisplayName): $($_.Exception.Message)"
            $failed++
        }
    }
}

#----------------------------------------------------------------
# Summary
#----------------------------------------------------------------

Write-Output "Sync summary: Total CIDRs=$($desiredAllCidrsSorted.Count); Missing=$missingCount; Created=$created; Updated=$updated; Deleted=$deleted; Cleared=$cleared; Failed=$failed"

#endregion MAIN EXECUTION
