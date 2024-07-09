# UpdateConditonalAccessIndirect
Dette skriptet oppdatere en IP Named Location i Microsoft Entra Conditonal access.  
Skriptet oppdatere basert på CDIR listen som kommer fra HelseCERT blocklist og som er lasted ned via "HelseCertBlocklist" skriptet.

## Komme i gang
Kopier ``.env.sample`` til ``.env`` og ``.env.credential.sample`` til ``.env.credential``.  
Deretter redigere instillingene som nødvendig.  
Legg til referanser til riktig tenant ID og hvilen AppRegistration som skal brukes til å oppdatere listen Conditonal access.
Legg til thumprint for sertifikatet som brukes for app autentisering mot Entra ID i ``.env.credential``.
Man må også legge til ID-en til Location listen som skal oppdaters, skriptet vill ikke opprette denne selv.  
ID-en kan hentes på forksjellige måter, men enkleste er enten å liste ut via ``Get-MgIdentityConditionalAccessNamedLocation`` eller via Graph Explorer og ``GET https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations``
Når dette er på plass så kan man kjøre skriptet.

### Feilhåndering
Skriptet vil prøve å bruke feilhånderings skriptet definert i funksjonen "GetEnvData" hvis det eksisterer.  
Hvis skriptet ikke er definert eller ikke finnes så hoppes det over å sende noe til feilhåndering.  
Forventingen er at att ett eventuelt feilhånderings skript hånderer følgende:
- Parameter: ErrorMessage, Type: ``string``
- Parameter: ErrorObject, Type: ``System.Management.Automation.ErrorRecord``

## AppRegistration
> **OBS OBS!!!**  
> Disse applikasjonsrettighetene gir mulighet til å endre alle Conditonal Access Policyer man har.
> Dette er en priviligert tilgang og man burde være veldig forsiktig med hvem som har denne tilgangen, da man kan sabotere hele sikkerheten i Conditonal Access med denne tilgangen.
> Husk når man sette opp en automatisk oppgave med denne rettigheten på en server, så gir man i praksis alle som har administrator-rettighet til serveren dette privileget.  
> En hvilken som helst bruker med administrator-rettighet kan bruke sertifikatet på maskinen og autentisere seg mot Entra og gjøre endringer i kontekst av applikasjonen.  
> Så være nøye med hvem som har tilgang til serveren som brukes for å automatisere dette.
> Andre alternativer kan være å se på Azure Automation istedenfor, eller at man har spesifikk og uavhengig VM Azure der man kjører slike skript fra (og som man kan låse ned).

For at løsningen skal virke så må man ha opprettet en AppRegistration med GraphAPI ``Application`` rettigheter på scopene ``Policy.Read.All`` og ``Policy.ReadWrite.ConditionalAccess``.  
Man må deretter registere ett sertifiat mot denne applikasjonen som skal brukes for å logge inn.
Informasjon på hvordan dette gjøres finner man i Microsoft sin dokumentasjon:  
Lage Applikasjon: https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app?tabs=certificate  
Tildele rettigheter: https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-configure-app-access-web-apis  
Det finnes forskjellige andre PowerShell Cmdlets som kan gjøre denne oppgaven enklere f.eks. PnP PowerShell:  
https://pnp.github.io/powershell/
