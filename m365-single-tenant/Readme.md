# M365 integrasjon for en tenant

## Introduksjon
Implementasjon av blokkeringslistene mot M365 vil forhindre flere av de større phishing-kampanjene, og lar dere automatisk søke etter vellykkede angrep. Den langsiktige løsningen på phishing vil imidlertid fortsatt være phishingresistent autentisering. 

En rekke adresser vi har i blokkeringslistene vil forsøkes brukt til innlogging på M365 som et ledd i enten kompromittering av konto, eller bruk (utnyttelse) av kompromittert konto.  

## Innhold

I denne mappen ligger 2 scripts:
 - [Update-NamedLocationsFromHelseCert.ps1](https://github.com/helsecert/blocklist/blob/master/m365/Update-NamedLocationsFromHelseCert.ps1) [README/GUIDE](https://github.com/helsecert/blocklist/blob/master/m365/Kort%20readme%20Update-NamedLocationsFromHelseCert.txt): Sørger for å oppdatere Conditional Access slik innloggingsforsøk fra IP-adressene vi kjenner til blir blokkert
 - [Get-SigninsFromHelseCertBlocklistIPs.ps1](https://github.com/helsecert/blocklist/blob/master/m365/Get-SigninsFromHelseCertBlocklistIPs.ps1) [README/GUIDE](https://github.com/helsecert/blocklist/blob/master/m365/Kort%20readme%20Get-SigninsFromHelseCertBlocklistIPs.txt): Sørger for å søke gjennom Sign-In logs og matche disse mot blokkeringslistene våre, og varsle ved treff.


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
    - [Tredjepartsguide](https://newhelptech.wordpress.com/2022/03/01/step-by-step-how-to-configuring-conditional-access-policy-to-restrict-access-from-specific-location-in-office-365/) for å begrense tilgang åp denne måten

### For søkeskript (Get-SigningsFromhelseCERTBlocklistPs.ps1)
- Microsoft.Graph modular med tilhørende lisens for å kunne bruke [Microsoft Graph API](ttps://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0)