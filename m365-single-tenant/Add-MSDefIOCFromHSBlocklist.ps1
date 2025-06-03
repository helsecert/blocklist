<#    
.SYNOPSIS
    Script for å laste ned blockliste fra HelseCERT og legge inn indicators i Microsoft Defender for Endpoint via API.

.DESCRIPTION
    Scriptet laster ned ei liste med url'ar og legg dei inn som blocked i MS Defender for Endpoint via API.
    Om det er endringar i lista, vil den oppdaterte lista bli lagt inn i MS Defender for Endpoint.
    Scriptet sjekker om lista er oppdatert ved å sammenligne MD5-sjekksum av lista med den som er lagret i ei fil.
    Om lista er oppdatert, vil den bli lagt inn i MS Defender for Endpoint.
    Scriptet sender også varsling via e-post om det oppstår feil under kjøringen.¨
    Scriptet logger også all aktivitet i ei loggfil som blir lagret i ei mappe kalt "Logs" i samme mappe som scriptet.

    Scriptet er laget for å bli kjørt som en oppgave i Windows Task Scheduler, og kan også kjøres manuelt.
    Scriptet kan kjøres så ofte som ønsket, feks kvart 5 minutt.

    Før du kjører scriptet, må du endre variablene i config.txt-fila som ligger i samme mappe som scriptet.
    Du må også ha lagt inn app permissions i Azure AD for å kunne bruke API'et.
    App permissions required: Ti.ReadWrite.All - https://www.hanley.cloud/2024-08-27-Push-IoCs-with-PowerShell-via-API/

.NOTES
    Version:        0.2
    Author:         SysIKT KO
    Updated date:  2025-05-08

    ### Config.txt - eksempel   NB! Må lagrast som eiga fil, i samme mappe som scriptet!

    $blocklistname = 'HelseCert'
    $blocklistkey = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    $blocklisturl = "blocklistdomain.local"
    $tenantId = '12345678-abcd-1234-abcd-0123456789abcd'
    $appId = '12345678-1234-abcd-1234-0123456789abcd'
    $appSecret = '-AA123456ABC12345ABC41B4F20E4B2D1'
    $expirationTime = 15
    $action = 'Block'
    $smtpserver = 'X.X.X.X'
    $smtpto = helpdesk@virksomhet.lokal, admin@virksomhet.lokal
    $smtpfrom = noreply@virksomhet.lokal
    $logDays = 14

#>

# Om heile scriptet ikkje blir kjørt, fallback til working dir!
if (-not $PSScriptRoot) {
    $PSScriptRoot = Get-Location
}

# Lokasjon for konfigurasjon for scriptet
# Om config.txt ligg ein anna stad enn i samme mappe som scriptet må denne linja endrast!
$configfil = Join-Path $PSScriptRoot config.txt

# Henter inn configdata fra filen config.txt
Get-Content $configfil | ForEach-Object { 
  $key, $val = $_ -split '='
  if($val -ne $null) {
    $key = $key.Trim()
    $val = $val.Trim()
    if ($key -eq '$TenantId') { $TenantId=$val } 
    elseif ($key -eq '$AppId') { $AppId=$val } 
    elseif ($key -eq '$appSecret') { $appSecret=$val } 
    elseif ($key -eq '$blocklistkey') { $blocklistkey=$val }
    elseif ($key -eq '$blocklistname') { $blocklistname=$val }
    elseif ($key -eq '$blocklistdomain') { $blocklistdomain=$val } 
    elseif ($key -eq '$smtpserver') { $smtpserver=$val }
    elseif ($key -eq '$smtpto') { $smtpto=$val }
    elseif ($key -eq '$smtpfrom') { $smtpfrom=$val }
    elseif ($key -eq '$action') { $action=$val }
    elseif ($key -eq '$expirationDate') { $expirationDate=$val }
    elseif ($key -eq '$logDays') { $logDays=$val }
    
  }
}

# Sjekker om variabler er endret før kjøring
if($blocklistkey -eq 'DittNbpBlocklistPassord') {write-error 'Variabel $blocklistkey ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($smtpserver -eq "X.X.X.X") {write-error 'Variabel $smtpserver ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
foreach($smtptoemail in $smtpto){if($smtptoemail.contains("virksomhet.local")) {write-error 'Variabel $NBPsmtptouser ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}}
if($smtpfrom -eq "noreply@virksomhet.local") {write-error 'Variabel $smtpfrom ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($TenantId -eq "12345678-abcd-1234-abcd-0123456789abcd") {write-error 'Variabel $TenantId ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($AppId -eq "12345678-1234-abcd-1234-0123456789abcd") {write-error 'Variabel $AppId ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($appSecret -eq "-AA123456ABC12345ABC41B4F20E4B2D1") {write-error 'Variabel $CertificateThumbprint ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($blocklistdomain -eq "blocklistdomain.local") {write-error 'Variabel $blocklistdomain ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}

# Sett variabel for md5sjekksum fil
$md5checksumurl = "https://$blocklistdomain/v3?apikey="+ $blocklistkey +"&format=list&type=domain&type=ipv6&type=ipv4&list_name=default&hash=md5"
$md5checksumfile = Join-Path $PSScriptRoot md5.txt

# Sett variabel for nedlasting av blocklist fra Helse og KommuneCERT
$blocklisturl = "https://$blocklistdomain/v3?apikey="+ $blocklistkey +"&format=list&type=domain&type=ipv6&type=ipv4&list_name=default"

$expirationTime = (Get-Date).AddDays($expirationDate).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Sett loggfil namn
$logDir = Join-Path $PSScriptRoot Logs
$logFile = Join-Path $logDir "\$($blocklistdomain)_$(Get-Date -Format 'yyyy-MM-dd').log"
# Sjekk om $logDir finnes, opprett hvis ikkje
try {
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
        Write-Host "Fann ikkje Logs.." -ForegroundColor Yellow
        Write-Host "Oppretter $($logDir)" -ForegroundColor Green
    }
}
catch {
    Write-Host "Error oppretting av $($logDir): $_" -ForegroundColor Red
    Exit 0
}

# Function to write to daily log
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# Funksjon for å slette gamle loggfiler
function Remove-OldLogFiles {
    param (
        [string]$logDirectory = $logDir,
        [int]$daysToKeep = $logDays
    )
    try {
        $cutoffDate = (Get-Date).AddDays(-$daysToKeep)
        $oldLogs = Get-ChildItem -Path $logDirectory -File -Filter "$($blocklistdomain)_*.log" |
            Where-Object { $_.LastWriteTime -lt $cutoffDate }
       
        foreach ($log in $oldLogs) {
            Write-Log "Deleting old log file: $($log.FullName)"
            Remove-Item -Path $log.FullName -Force
        }
    }
    catch {
        Write-Log "Error deleting old log files: $($_.Exception.Message)"
    }
}

#Funksjon for varsling - Denne kan byttes ut om ein vil ha varsel på andre måtar enn epost, feks Teams eller likandne.
function Send-Varsel {
    Send-MailMessage -SmtpServer $smtpserver -To $smtpto -From $smtpfrom -Subject "Error under kjøring av Add-MSDfEOCFromHelseCert.ps1” -Body "Scriptet Add-MSDfEOCFromHelseCert.ps1 fekk error ved kjørng. Sjekk $($logFile)!" -Encoding UTF8
}

#Funksjon for å sammenligne MD5-sjekksum
function Compare-MD5Checksum {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ChecksumFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ChecksumUrl
    )

    try {
        # Laster ned MD5-sjekksum
        $md5checksum = Invoke-WebRequest -Uri $md5checksumurl -UseBasicParsing -ErrorAction Stop
        $md5checksumContent = $md5checksum.Content
        Write-Host "MD5-sjekksum lastet ned!" -ForegroundColor Green
        Write-Log "[Information] MD5-sjekksum lastet ned."
    } 
    catch {
        Write-host "Ein feil oppstod under nedlasting av MD5-sjekksum: " -ForegroundColor Red
        Write-Host "$_"
        Write-Log "[Error] Ein feil oppstod under nedlasting av MD5-sjekksum: $_"
        Send-Varsel
        exit 1
    }

    try {
        # Sjekk om filen eksisterer, opprett den om den ikke gjør det
        if (-not (Test-Path -Path $ChecksumFilePath)) {
            New-Item -Path $ChecksumFilePath -ItemType File -Force | Out-Null
            Write-host "MD5-sjekksumfil opprettet." -ForegroundColor Green
            Write-Log "[Information] MD5-sjekksumfil opprettet."
        }
    } 
    catch {
        Write-Host "Ein feil oppstod under oppretting av MD5-sjekksum fila:" -ForegroundColor Red
        Write-Host "$_"
        Write-Log "[Error] Ein feil oppstod under oppretting av MD5-sjekksum fila: $_"
        Send-Varsel
        exit 1
    }

    try {
        # Henter MD5-sjekksummen frå fila
        $storedChecksum = Get-Content -Path $ChecksumFilePath -ErrorAction SilentlyContinue

        # Sammenligner MD5-sjekksummen frå fila er den som blei lasta ned. Exit om den er den samme.
        if ($storedChecksum -eq $md5checksumContent) {
            throw "MD5-sjekksummen frå fila er den samme som blei lasta ned. Avslutter scriptet."
        } 
        else {
            # Om den var ny, lagre den til fila.
            Set-Content -Path $ChecksumFilePath -Value $md5checksumContent -Force
            Write-Host "MD5-sjekksummen er ny, lagrer ny sjekksum til fila, og fortsetter.." -ForegroundColor Green
            Write-Log "[Information] MD5-sjekksummen er ny, lagrer ny sjekksum til fila, og fortsetter.."
        }
    }
    # Exit om MD5-sjekksummen var den samme.
    catch {
        Write-Host "Sjekksummen er den samme." -ForegroundColor Green
        Write-Log "[Information] MD5-sjekksummen frå fila er den som blei lasta ned. Avslutter scriptet."
        exit 0
    }
}
Write-Log "[Information] Starter script..."

# Funksjon for å sjekke om blocklista er oppdatert sidan sist kjøring. Exit scriptet om den ikkje er oppdatert.
Compare-MD5Checksum $md5checksumfile $md5checksumurl


# Url til Microsoft Defender API
$resourceAppIdUri = 'https://api.securitycenter.windows.com'
# URL til token endpoint
$oAuthUri = "https://login.windows.net/$tenantId/oauth2/token"
# URL til Microsoft Defender API in EU region
$api = "https://api.securitycenter.windows.com/api/indicators/import"

# Last ned nyeste blocklist fra Helse- og KommuneCERT
try {
    Write-Host "Laster ned blocklist frå Helse- og KommuneCERT" -ForegroundColor Green
    Write-Log "[Information] Laster ned blocklist frå Helse- og KommuneCERT"
    $blocklist = Invoke-WebRequest -Uri $blocklisturl -UseBasicParsing -ErrorAction Stop
    $blocklistContent = $blocklist.Content -split "`n"
    }
catch {
    Write-Host "Nedlasting av blocklista feilet!" -ForegroundColor Red
    Write-Log "[Error] Nedlasting av blocklista feilet med feilkode: $_ "
    Send-Varsel
    exit 0
}

# Authbody for token retrieval
# https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
$authBody = [Ordered] @{
    resource = "$resourceAppIdUri"
    client_id = "$appId"
    client_secret = "$appSecret"
    grant_type = 'client_credentials'
}

# Error handling for token retrieval
try {
    $authResponse = Invoke-RestMethod -Method Post -Uri $oAuthUri -Body $authBody -ErrorAction Stop
    $token = $authResponse.access_token
    Write-Host "Token obtained successfully." -ForegroundColor Green
    Write-Log  "[Information] Token obtained successfully."
} catch {
    Write-Host "Failed to obtain token: $_" -ForegroundColor Red
    Write-Log "[Error] Failed to obtain token: $_"
    Send-Varsel
    exit 1
}

# Sett opp headers for API-kallet
$headers = @{
    'Content-Type' = 'application/json'
    Accept         = 'application/json'
    Authorization  = "Bearer $token"
}

# Lag batch med max 500 url'ar
# https://learn.microsoft.com/en-us/defender-endpoint/api/import-ti-indicators
$batchSize = 500 # Number of indicators to process in a single batch
$batchCount = [math]::Ceiling($blocklistContent.Count / $batchSize) # Calculate the number of batches
$batchNumber = 0 # Initialize batch number

for ($i = 0; $i -lt $blocklistContent.Count; $i += $batchSize) {
    $batch = $blocklistContent[$i..($i + $batchSize - 1)]
    Write-Host "Done $($i) of $($blocklistContent.Count)" -ForegroundColor Cyan
    Write-Log "[Information] Done $($i) of $($blocklistContent.Count)"

    $indicators = $null # Reset the indicators array for each batch
    $indicators = @() # Initialize the array

    $batchNumber++ # Increment the batch number
    Write-Host "Processing batch $batchNumber of $batchCount..." -ForegroundColor Cyan
    Write-Log "[Information] Processing batch $batchNumber of $batchCount..."

    # Loop through the new array and create the indicator objects
    foreach ($url in $batch) {
        $indicator = @{
            indicatorValue     = $url
            indicatorType      = 'DomainName'
            action             = $action
            title              = "$blocklistname : $url"
            description        = "Blocking domain: $url"
            expirationTime     = $expirationTime
        }
        # Add the indicator to the array
        $indicators += $indicator #| ConvertTo-Json
    }

    # Build body of indicators
    $jsonObject = $indicators
    $body = @{
        Indicators = $jsonObject
    }| ConvertTo-Json -Depth 10

    # Uncomment the following line to see the JSON body being sent
    #Write-Output $body
    
    # Update the API with the new batch of indicators
    try {
        $response = Invoke-WebRequest -Method Post -Uri $api -Body ($body) -Headers $headers -ErrorAction Stop
        if($response.StatusCode -eq 200) {
       # $response = 200 # Simulate a successful response for testing purposes
       # if($response -eq 200) { # For testing purposes
            Write-Host "Successfully submitted indicators to Microsoft Defender for Endpoint API" -ForegroundColor Green
            Write-Log "[Information] Successfully submitted indicators to Microsoft Defender for Endpoint API."
        } else {
            throw "Failed to submit indicator. Status code: $($response.StatusCode)"
            Write-Log "[Error] Failed to submit indicator. Status code: $($response.StatusCode)"
        }
    } 
    catch {
        Write-Error "Failed to submit indicator: $_"
        Write-Log "[Error] Failed to submit indicator: $_"
        Send-Varsel
        exit 0
    }
    
    Write-Host "Sleeping for 10 seconds to avoid hitting the API rate limit." -ForegroundColor Green
    Write-Log "[Information] Sleeping for 10 seconds to avoid hitting the API rate limit."

    Start-Sleep -Seconds 10 # Sleep for 10 seconds to avoid hitting the API rate limit

}

try { 
    Write-Host "Kobler fra Microsoft Graph" -ForegroundColor Green
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-null
    }catch {}
    
Write-Host "Ser etter, og sletter, gamle loggfiler." -ForegroundColor Green
Remove-OldLogFiles 
Write-Log "[Information] Avslutter script..."
