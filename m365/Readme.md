M365 integrasjon
--

Den langsiktige løsningen på phishing vil være phishingresistent autentisering, men implementasjon av blokkeringslistene mot M365 vil forhindre flere av de større kampanjene vi har sett i nyere tid.

En rekke adresser vi har i blokkeringslistene vil forsøkes brukt til innlogging på M365 som et ledd i enten kompromittering av konto, eller bruk (utnyttelse) av kompromittert konto.  

I tillegg kan innlogging fra brukere begrenses basert på geografi, eksempelvis kun tillate innlogginger fra Norge med mindre personell er på reise.

NB! Husk å opprette break-the-glass konto når dere innfører Conditional Access! Dette er også nevnt readme-filene. Ikke lås dere selv ute.

I denne mappen ligger 2 scripts:
 - [Update-NamedLocationsFromHelseCert.ps1](https://github.com/helsecert/blocklist/blob/main/m365/Update-NamedLocationsFromHelseCert.ps1) [README/GUIDE](https://github.com/helsecert/blocklist/blob/main/m365/Kort%20readme%20Update-NamedLocationsFromHelseCert.txt): Sørger for å oppdatere Conditional Access slik innloggingsforsøk fra IP-adressene vi kjenner til blir blokkert
 - [Get-SigninsFromHelseCertBlocklistIPs.ps1](https://github.com/helsecert/blocklist/blob/main/m365/Get-SigninsFromHelseCertBlocklistIPs.ps1) [README/GUIDE](https://github.com/helsecert/blocklist/blob/main/m365/Kort%20readme%20Get-SigninsFromHelseCertBlocklistIPs.txt): Sørger for å søke gjennom Sign-In logs og matche disse mot blokkeringslistene våre, og varsle ved treff.
