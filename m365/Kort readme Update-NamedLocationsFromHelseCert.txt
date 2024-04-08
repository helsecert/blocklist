Update-NamedLocationsFromHelseCert.ps1

Scriptet gjer følgande:
Laster ned blockliste  fra HelseCert
Kobler til Microsoft Graph
Oppdaterer (overskriver) Named Location i Conditional Access
Sender epost hvis egne public ip-adresser er inkludert i blocklista

Scriptet er laga for å kjøres som oppgave i Windows Task Scheduler
Scriptet krever ein app registrert i Azure AD med følgende API tilganger:
 - Policy.Read.All
 - Policy.ReadWrite.ConditionalAccess
Scriptet krever ein SMTP server for å sende epost

Scriptet anbefales kjørt en gang i timen.

NB! NB!

Om ein er ukjent med Conditional Access (CA), så lag først ein break-glas konto så ein ikkje stenger seg sjølv ute frå tenanten ved ein feil!
https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access


Ein må forandre verdiane i variablane i fila config.txt for at scriptet skal fungere som tenkt. Fila er referert i linje 49 i scriptet.
For å bruke scriptet må ein også ha høvelige Microsoft lisensar (P1)

Scriptet krever at det blir oppretta ein applikasjon i Entra med riktige rettigheter, samt eit sertifikat som blir brukt til autentisering.
https://www.alitajran.com/connect-to-microsoft-graph-powershell/#h-method-2-how-to-connect-to-microsoft-graph-with-certificate-based-authentication-cba

Det anbefales å først kjøre scriptet manuelt for å sjekke at det fungerer slik det skal,
når det er gjort setter man opp ein Scheduled task på ein server:
https://lazyadmin.nl/powershell/how-to-create-a-powershell-scheduled-task/
Obs! Brukaren som kjører scriptet må ha sertifikatet oppretta i førre steg i sin personlige sert-store.

Det må lages ein "tom" Named Location og opprettes ein eigen Condtional Access policy som hindrer all pålogging frå IPane i den Named Location.
ID'en til Named Location finner man ved å kjøre: Get-MgIdentityConditionalAccessNamedLocation -All
https://newhelptech.wordpress.com/2022/03/01/step-by-step-how-to-configuring-conditional-access-policy-to-restrict-access-from-specific-location-in-office-365/ (berre ikkje velg land!)
