#Requires -Version 7.0

<#    
.SYNOPSIS
    Script for automatisk søke gjennom sign-in logs etter IPer frå blocklista til Helse- og KommuneCERT

.DESCRIPTION
    Laster ned blockliste fra Helse- og KommuneCERT
    Kobler til Microsoft Graph
    Søker gjennom sign-in logs i EntraID
    Sender epost om nye sign-ins vis det er kommet nye innslag siden sist kjøring
    Lagrer tidligare sign-ins som alt er varsla til lokal csv-fil

    Scriptet er laga for å kjøres som oppgave i Windows Task Scheduler
    Scriptet krever ein app registrert i Azure AD med følgende API tilganger:
    - AuditLog.Read.All
    - Directory.Read.All
    Scriptet krever ein SMTP server for å sende epost
    Brukeren som kjører scriptet må ha skrivetilganger til dei tre lokale filene

.NOTES
    Version:        0.5
    Author:         SysIKT KO
    Updated date:  2024-03-11

    Denne versjonen av scriptet er tilpassa for å kunne brukes av medlemmer av Nasjonalt beskyttelsesprogram (NBP), 
    men har blitt utvikla for å passe inn i SysIKT KO sitt driftsmiljø, og ein må rekne med å måtte gjere lokale tilpassingar.
    Helse- og KommuneCERT mottar gjerne oppdaterte versjoner av scriptet frå andre medlemmer som vil bidra til å forbedre det.

    Variablane i fila config.txt må endrast før kjøring av scriptet! Fila er referert på linje 75.
    Det anbefales å kjøre scriptet manuelt første gang for å sjekke at det fungerer som forventa.
    Scriptet anbefales kjørt en gang i døgnet, gjerne på morgenen. Dette med bakgrunn i at det kan ta en stund å kjøres scriptet (ca 50 min). Det er dog ingenting i veien for å kjøre dette 2-3 ganger i løpet av dagen om man ikke møter på trøbbel med throttling i azure.

    Scriptet krever Powershell versjon 7 eller nyare, samt tilhørande Microsoft.Graph modular.
    I tillegg lyt ein ha høvande lisensar hos Microsoft for å kunne bruke Microsoft Graph API.
    Se: https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0

    Scriptet krever at det blir oppretta ein applikasjon i Entra med riktige rettigheter, samt eit sertifikat som blir brukt til autentisering.
    https://www.alitajran.com/connect-to-microsoft-graph-powershell/#h-method-2-how-to-connect-to-microsoft-graph-with-certificate-based-authentication-cba

    Det anbefales å først kjøre scriptet manuelt for å sjekke at det fungerer slik det skal,
    når det er gjort setter man opp ein Scheduled task på ein server:
    https://lazyadmin.nl/powershell/how-to-create-a-powershell-scheduled-task/
    Obs! brukaren som kjører scriptet må ha sertifikatet oppretta i førre steg i sin personlige sert-store.

    Scriptet varsler via epost/SMTP, så kan være greit å sjekke at dette fungerer slik det skal før i gangsetting.

    Potensielle forbedringer:
    - Uthenting av signins frå Sentinel
    - Logging
    - Epost utsending via Microsoft Graph / andre varslingsmetoder som td. Teams eller API
    - Kjøre scriptet som en Azure Automation istadenfor i Task Scheduler
    - Meir effektiv/elegant funksjon for å sjekke om sign-in er varsla om fra før
    - Støtte bruk av proxy for nedlasting av blokkeringslister
    
    Mtp. bruk av proxy kan kode som dette kan benyttes:

    $ProxyServer = 'http://proxy.virksomhet.local:3128'
    #ved autentisert proxy, og spesifikt brukernavn og passord for proxy, bruk -ProxyCredential parameteret (med credential som argument) til Invoke-WebRequest linja.
    #ved autentisert proxy, og credential til bruker som kjører scriptet også brukes for proxy, bruk -UseDefaultCredentials  som parameter (uten argument) til Invoke-Webrequest linja.
    if ($proxyserver) {
        Invoke-WebRequest -Uri $blocklisturl -Credential $credential -Proxy $ProxyServer | Select-Object -ExpandProperty Content | Out-File $NamedLocations 
    }
    else {
        Invoke-WebRequest -Uri $blocklisturl -Credential $credential | Select-Object -ExpandProperty Content | Out-File $NamedLocations
    }
#>

############################################################################################################
# Variabel som kan endrast
############################################################################################################


# lokasjon for konfigurasjon for scriptet
$configfil = "C:\Scripts\_Task scheduler\config.txt"


############################################################################################################
# Slutt: Variabel som kan endrast
############################################################################################################

# Henter inn configdata fra filen config.txt
Get-Content $configfil | ForEach-Object { 
  $key, $val = $_ -split '='
  if($val -ne $null) {
      $key = $key.Trim()
      $val = $val.Trim()
      if ($key -eq '$TenantId') { $TenantId=$val } 
      elseif ($key -eq '$AppId') { $AppId=$val } 
      elseif ($key -eq '$CertificateThumbprint') { $CertificateThumbprint=$val } 
      elseif ($key -eq '$NBPpass') { $NBPpass=$val } 
      elseif ($key -eq '$smtpserver') { $smtpserver=$val }
      elseif ($key -eq '$smtpto') { $smtpto=$val }
      elseif ($key -eq '$smtpfrom') { $smtpfrom=$val }
      elseif ($key -eq '$NamedLocations') { $NamedLocations=$val }
      elseif ($key -eq '$Signinslog') { $Signinslog=$val }
      elseif ($key -eq '$blocklistdomain') { $blocklistdomain=$val }
  }
}

# Sjekker om variabler er endret før kjøring

if($NBPpass -eq 'DittNbpBlocklistPassord') {write-error 'Variabel $NBPpass ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($smtpserver -eq "X.X.X.X") {write-error 'Variabel $smtpserver ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
foreach($smtptoemail in $smtpto){if($smtptoemail.contains("virksomhet.local")) {write-error 'Variabel $NBPsmtptouser ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}}

if($smtpfrom -eq "noreply@virksomhet.local") {write-error 'Variabel $smtpfrom ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($TenantId -eq "12345678-abcd-1234-abcd-0123456789abcd") {write-error 'Variabel $TenantId ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($AppId -eq "12345678-1234-abcd-1234-0123456789abcd") {write-error 'Variabel $AppId ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($CertificateThumbprint -eq "AA123456ABC12345ABC41B4F20E4B2D1") {write-error 'Variabel $CertificateThumbprint ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($blocklistdomain -eq "blocklistdomain.local") {write-error 'Variabel $blocklistdomain ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}

# Sett parameter for nedlasting av blocklist fra Helse og KommuneCERT
$url = "https://$blocklistdomain/v3?apikey=" + $NBPpass + "&format=list&type=ipv4&type=ipv6&list_name=auth"

# Sjekker om filene NamedLocations og Signinslog finnes fra før, vis ikkje opprette den
if(!(Test-Path $NamedLocations)) {New-Item -Path $NamedLocations -ItemType File -Force}
if(!(Test-Path $Signinslog)) {New-Item -Path $Signinslog -ItemType File -Force}

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns


$secpasswd = ConvertTo-SecureString $NBPpass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($NBPuser, $secpasswd)

# Last nyeste blocklist fra Helse- og KommuneCERT
write-host "Laster ned blocklist frå Helse- og KommuneCERT" -ForegroundColor Green
Invoke-WebRequest -Uri $url -Credential $credential | Select-Object -ExpandProperty Content | Out-File $NamedLocations

# Array for å lagre nye signins fra IPane i blocklista
$NyeSignins = [System.Collections.Concurrent.ConcurrentDictionary[object,string]]::new()
# Start tidtaking
$watch = New-Object System.Diagnostics.Stopwatch
$watch.Start()

# Sjekk om filen er lastet ned og ikkje tom
if ((Test-Path $NamedLocations) -and (Get-Content $NamedLocations | Measure-Object -Line).Lines -gt 0) {
    
    # Importer csv fil
    $Locations = Import-Csv -Path $NamedLocations -Delimiter "`t" -Header "cidrAddress"

    # Sjekk om det er signins fra IPane i blocklista, 5 samtidige tråder, meir kan føre til rate limit hos Microsoft.
    $locations | ForEach-Object -Parallel { 
        write-host "Sjekker signins fra:" $($_.cidrAddress) -ForegroundColor Yellow;
        $ip = $($_.cidrAddress)
        Import-Module Microsoft.Graph.Beta.Reports
        Connect-MgGraph -TenantId $using:TenantId -AppId $using:AppId -CertificateThumbprint $using:CertificateThumbprint -ErrorAction Stop -NoWelcome
        #$Signins  = Get-MgAuditLogSignIn -Filter "startsWith(ipAddress,'$ip')" -All | Select-Object Id, UserPrincipalName, CreatedDateTime, IPAddress
        $Signins  = Get-MgBetaAuditLogSignIn -Filter "startsWith(ipAddress,'$ip')" -All | Select-Object Id, UserPrincipalName, CreatedDateTime, IPAddress
         
        if (!($signins)){
            write-host "Ingen signins fra:" $ip -ForegroundColor Green
        }

        else {
            write-host "Signin funnet! Match på IP:" $ip -ForegroundColor Red

            # Sjekk om det har blitt sendt varsel på singin Id'en fra før -loop gjennom $signins.id'ane
            foreach($Signin in $Signins){
                $SigninId = $Signin.Id
                $SigninUser = $Signin.UserPrincipalName
                $SigninIP = $Signin.IPAddress
                
                $nyeSignIn = $using:NyeSignins
                # Sjekk om signin finnes i Signinslog-fila fra før
                $tidligareSignins = Get-Content $using:Signinslog | Select-String -Pattern $SigninId

                # Vis det finnes i fila frå før skal det ikkje varsles på nytt
                if($null -ne $tidligareSignins){   
                    write-host "IDen er varsel på tidligere! ID: $SigninId" -ForegroundColor Green
                }

                # Vis IDen ikkje finnes i fila fra før skal det legges til i arrayet
                else {
                    write-host "IDen er ny! $SigninUser har logga inn frå $SigninIP. ID: $SigninId" -ForegroundColor Red
                    
                    # Lagre ny kvar signin til $signinslog
                    $nyeSignIn.TryAdd($SigninId, $SigninIP)
                }
            }    
        }
    }
}

write-host "Spørringa tok: "$watch.Elapsed.TotalMinutes" minutter" -ForegroundColor Blue

# Skriver $NyeSignins til $Signinlog fila og sender epost om nye signins er funnet
# Her kan ein legge inn andre varslingsmetoder som td. Teams eller API,
# eller feks deaktivere kontoar som har signins frå blokklista, tvinge passordbytte, etc.
if($NyeSignins.Count -ne 0){
    $NyeSignins.ToArray() |  ConvertTo-Csv -NoHeader | out-file $Signinslog -Append
    $NyeSignins = $NyeSignins | Out-String
    Send-MailMessage -SmtpServer $smtpserver -To $smtpto -From $smtpfrom -Subject "Signin fra blokkliste IP funnet" -Body “Det er funnet signins frå blocklista: $NyeSignins " -Encoding UTF8
 
}
