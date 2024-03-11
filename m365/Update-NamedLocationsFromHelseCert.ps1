<#    
.SYNOPSIS
    Script for automatisk nedhenting av blockliste og oppdatering av Named Locations i Conditional Access

.DESCRIPTION
    Laster ned blockliste  fra Helse- og KommuneCERT
    Kobler til Microsoft Graph
    Oppdaterer (overskriver) Named Location i Conditional Access
    
    Scriptet er laga for å kjøres som oppgave i Windows Task Scheduler
    Scriptet krever ein app registrert i Azure AD med følgende API tilganger:
    - Policy.Read.All
    - Policy.ReadWrite.ConditionalAccess
    Scriptet krever ein SMTP server for å sende epost

.NOTES
    Version:        0.4
    Author:         SysIKT KO
    Updated date:  2024-03-11

    Takk til Alexander Filipin for utgangspunktet til scriptet:
    https://github.com/AlexFilipin/ConditionalAccess/blob/master/Deploy-NamedLocations.ps1

    NB! NB! NB!

    Om ein er ukjent med CA, så lag først ein break-glas konto så ein ikkje stenger seg sjølv ute frå tenanten ved ein feil!
    https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access

    Denne versjonen av scriptet er tilpassa for å kunne brukes av medlemmer av Nasjonalt beskyttelsesprogram (NBP), 
    men har blitt utvikla for å passe inn i SysIKT KO sitt driftsmiljø, og ein må rekne med å måtte gjere lokale tilpassingar.
    Helse- og KommuneCERT mottar gjerne oppdaterte versjoner av scriptet frå andre medlemmer som vil bidra til å forbedre det.

    Variablane må settes i fila config.txt før kjøring av scriptet. Denne er referert til i linje 64 i koden.
    Det anbefales å kjøre scriptet manuelt første gang for å sjekke at det fungerer som forventa.

    Potensielle forbedringer:
    - Logging
    - Epost utsending via Microsoft Graph / andre varslingsmetoder som td. Teams eller API
    - Kjøre scriptet som en Azure Automation istadenfor i Task Scheduler
    - Fjerne klartekst brukarnavn og passord
    - Array av public ip-adresser/ipnett mot blocklista og varsling på dette, for virksomheter som har fleire public ip-adresser i bruk.
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
    elseif ($key -eq '$NBPuser') { $NBPuser=$val }
    elseif ($key -eq '$NBPpass') { $NBPpass=$val } 
    elseif ($key -eq '$smtpserver') { $smtpserver=$val }
    elseif ($key -eq '$smtpto') { $smtpto=$val }
    elseif ($key -eq '$smtpfrom') { $smtpfrom=$val }
    elseif ($key -eq '$NamedLocations') { $NamedLocations=$val }
    elseif ($key -eq '$blocklistdomain') { $blocklistdomain=$val }
    elseif ($key -eq '$NamedLocationId') { $NamedLocationId=$val }
  }
}

# Sjekker om variabler er endret før kjøring

if($NBPuser -eq 'Virksomhet') {write-error 'Variabel $NBPuser ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($NBPpass -eq 'DittNbpBlocklistPassord') {write-error 'Variabel $NBPpass ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($smtpserver -eq "X.X.X.X") {write-error 'Variabel $smtpserver ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
foreach($smtptoemail in $smtpto){if($smtptoemail.contains("virksomhet.local")) {write-error 'Variabel $NBPsmtptouser ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}}

if($smtpfrom -eq "noreply@virksomhet.local") {write-error 'Variabel $smtpfrom ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($TenantId -eq "12345678-abcd-1234-abcd-0123456789abcd") {write-error 'Variabel $TenantId ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($AppId -eq "12345678-1234-abcd-1234-0123456789abcd") {write-error 'Variabel $AppId ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($CertificateThumbprint -eq "AA123456ABC12345ABC41B4F20E4B2D1") {write-error 'Variabel $CertificateThumbprint ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($blocklistdomain -eq "blocklistdomain.local") {write-error 'Variabel $blocklistdomain ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}
if($NamedLocationId -eq "1234abcd-1234-abcd-1324-abcdf12345") {write-error 'Variabel $blocklistdomain ikke endret fra defaultverdi. Gjør dette før kjøring'; Exit}

# Sett parameter for nedlasting av blocklist fra Helse og KommuneCERT
$blocklisturl = "https://$blocklistdomain/blocklist/v2?f=list_cidr&t=ipv4&category=phishing"

# Sjekker om fila NamedLocations finnes fra før, vis ikkje opprette den
if(!(Test-Path $NamedLocations)) {New-Item -Path $NamedLocations -ItemType File -Force}

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns

#region connect
Import-Module -Name Microsoft.Graph.Authentication
Import-Module -Name Microsoft.Graph.Identity.SignIns

try { Disconnect-MgGraph -ErrorAction SilentlyContinue }catch {}
Connect-MgGraph -TenantId $TenantId -AppId $AppId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop

#endregion

$NBPsecpasswd = ConvertTo-SecureString $NBPpass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($NBPuser, $NBPsecpasswd)

# Last ned nyeste blocklist fra Helse- og KommuneCERT
Write-Host "Laster ned blocklist frå Helse- og KommuneCERT" -ForegroundColor Green
Invoke-WebRequest -Uri $blocklisturl -Credential $credential | Select-Object -ExpandProperty Content | Out-File $NamedLocations

# Sjekk om filen er lastet ned og ikkje tom. Dette gjøres for å unngå at scriptet overskriver Named Locations med ei tom fil.
if ((Test-Path $NamedLocations) -and (Get-Content $NamedLocations | Measure-Object -Line).Lines -gt 0) {
    
    # Importer csv fil
    $Locations = Import-Csv -Path $NamedLocations -Delimiter "`t" -Header "cidrAddress"

    # Bygge opp body
    $params = @{
	"@odata.type" = "#microsoft.graph.ipNamedLocation"
	DisplayName = "HelseCertBlockList"
    isTrusted = $false
    }
	
    $params.Add("IpRanges",@())
    # Loop gjennom alle ipane i csv filen

    foreach($Location in $Locations){
            write-host "Legger til:" $Location.cidrAddress -ForegroundColor Yellow
            $IpRanges=@{}
            $IpRanges.add("@odata.type" , "#microsoft.graph.iPv4CidrRange")
            $IpRanges.add("CidrAddress" , $Location.cidrAddress)
            $params.IpRanges+=$IpRanges
    }
    $params | ConvertTo-Json -Depth 4 
    
    # Oppdater Named Location
    write-host "Oppdaterer Named Locations" -ForegroundColor Green
    Update-MgIdentityConditionalAccessNamedLocation -NamedLocationId $NamedLocationId -BodyParameter $params
} 

else {
    Write-Host "Nedlasting feilet! Avslutter scriptet." -ForegroundColor Red
    Send-MailMessage -SmtpServer $smtpserver -To $smtpto -From $smtpfrom -Subject "Nedlasting av blokkliste fra Helse- og KommuneCERT feilet!” -Body "Scriptet Update-NamedLocationsFromHelseCert.ps1 feila ved nedlasting av ny blockliste fil!" -Encoding UTF8

}

#region disconnect
try { 
write-host "Kobler fra MgGraph" -ForegroundColor Green
Disconnect-MgGraph -ErrorAction SilentlyContinue 
}catch {}
#endregion
