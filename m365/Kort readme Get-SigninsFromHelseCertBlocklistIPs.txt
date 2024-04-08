Get-SigninsFromHelseCertBlocklistIPs

Scriptet gjer følgande:
    Laster ned blockliste fra HelseCert
    Kobler til Microsoft Graph
    Søker gjennom sign-in logs i EntraID
    Sender epost om nye sign-ins vis det er kommet nye innslag siden sist kjøring
    Lagrer tidligare sign-ins som alt er varsla til lokal txt-fil

    Scriptet er laga for å kjøres som oppgave i Windows Task Scheduler
    Scriptet krever ein app registrert i Azure AD med følgende API tilganger:
    - AuditLog.Read.All
    - Directory.Read.All
    Scriptet krever ein SMTP server for å sende epost
    Brukeren som kjører scriptet må ha skrivetilganger til dei to lokale filene

Scriptet anbefales kjørt en gang i døgnet, gjerne på morgenen. Dette med bakgrunn i at det kan ta en stund å kjøres scriptet (ca 50 min). Det er dog ingenting i veien for å kjøre dette 2-3 ganger i løpet av dagen om man ikke møter på trøbbel med throttling i azure.

Ein må forandre verdiane i variablane i fila config.txt for at scriptet skal fungere som tenkt. Fila er referert i linje 49 i scriptet.
Scriptet fungerer kun i Powershell 7 eller nyere.

Scriptet krever at det blir oppretta ein applikasjon i Entra med riktige rettigheter, samt eit sertifikat som blir brukt til autentisering.
https://www.alitajran.com/connect-to-microsoft-graph-powershell/#h-method-2-how-to-connect-to-microsoft-graph-with-certificate-based-authentication-cba

Det anbefales å først kjøre scriptet manuelt for å sjekke at det fungerer slik det skal,
når det er gjort setter man opp ein Scheduled task på ein server:
https://lazyadmin.nl/powershell/how-to-create-a-powershell-scheduled-task/
Obs! brukaren som kjører scriptet må ha sertifikatet oppretta i førre steg i sin personlige sert-store.

Scriptet varsler via epost/SMTP, så kan være greit å sjekke at dette fungerer slik det skal før i gangsetting.
