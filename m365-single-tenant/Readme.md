# M365 integrasjon for en tenant

## Introduksjon
Implementasjon av blokkeringslistene mot M365 vil forhindre flere av de større phishing-kampanjene, og lar dere automatisk søke etter vellykkede angrep. Den langsiktige løsningen på phishing vil imidlertid fortsatt være phishingresistent autentisering. 

En rekke adresser vi har i blokkeringslistene vil forsøkes brukt til innlogging på M365 som et ledd i enten kompromittering av konto, eller bruk (utnyttelse) av kompromittert konto.  

## Innhold

I denne mappen ligger 3 scripts:
 - [Update-NamedLocationsFromHelseCert.ps1](https://github.com/helsecert/blocklist/blob/master/m365-single-tenant/Update-NamedLocationsFromHelseCert.ps1): Sørger for å oppdatere Conditional Access slik innloggingsforsøk fra IP-adressene vi kjenner til blir blokkert
   - Se https://prottecio.com/2025/05/13/2025-automating-updated-named-locations-like-a-boss/ skrevet av Kim André Vaksdal for en detaljert guide 
 - [Get-SigninsFromHelseCertBlocklistIPs.ps1](https://github.com/helsecert/blocklist/blob/master/m365-single-tenant/Get-SigninsFromHelseCertBlocklistIPs.ps1): Sørger for å søke gjennom Sign-In logs og matche disse mot blokkeringslistene våre, og varsle ved treff
 - [Add-MSDefIOCFromHSBlocklist.ps1](https://github.com/helsecert/blocklist/blob/master/m365-single-tenant/Get-SigninsFromHelseCertBlocklistIPs.ps1): Script for å laste ned blockliste fra HelseCERT og legge inn indicators i Microsoft Defender for Endpoint via API

## Komme i gang
Man trenger:

### For begge
- Windowsmaskin for å kjøre skriptene
    - De er tiltenkt kjørt via [Windows Task Scheduler](https://lazyadmin.nl/powershell/how-to-create-a-powershell-scheduled-task/)
    - Vi anbefaler å kjøre de manuelt første gang
    - Skriptene krever Powershell 7
- Skriptene bruker e-post for å varsle om funn
    - Det krever SMTP-server man kan sende fra.
- Applikasjon i Entra med riktige rettigheter og sertifikat for autentisering mot det
    - Se [tredjepartsguide](https://www.alitajran.com/connect-to-microsoft-graph-powershell/#h-method-2-how-to-connect-to-microsoft-graph-with-certificate-based-authentication-cba)

### For blokkeringsskript (Update-NamedLocationsFromHelseCERT.ps1)    
- En "tom" `Named Location` og en egen `Conditional Access policy`
    - IDen til named location kan finnes med `Get-MgIdentityConditionalAccessNamedLocation -All`
    - [Tredjepartsguide](https://newhelptech.wordpress.com/2022/03/01/step-by-step-how-to-configuring-conditional-access-policy-to-restrict-access-from-specific-location-in-office-365/) for å begrense tilgang på denne måten

### For søkeskript (Get-SigninsFromHelseCertBlocklistIPs.ps1)
- Microsoft.Graph modular med tilhørende lisens for å kunne bruke [Microsoft Graph API](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0)
