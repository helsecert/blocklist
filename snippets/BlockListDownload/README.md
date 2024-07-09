# BlockListDownload
Dette skriptet laster ned HelseCERT blocklist og lagrer de i CSV format.  
Til standard laster dette skriptet ned følgende listetyper:
- list_context - Full liste med kontekstinformasjon (inneholder IP og URL-er)
- list_cdir - Liste med IP-addresser i CDIR format (inneholder bare IP-er)
- list_regex - Full liste i regex format (inneholder IP og URL-er)

## Komme i gang
Kopier ``.env.sample`` til ``.env`` og ``.env.credential.sample`` til ``.env.credential``.  
Deretter redigere instillingene som nødvendig.  
Legg inn addressen til HelseCERT listen i ``.env`` (Obs! Bruk full URL her ikke bare serveraddressen, per i dag så slutter den fulle addressen på ``/v2``) og endre stien som filer skal lastes ned til om nødvendig.  
Legg til riktig brukernavn og passord i ``.env.credential``.
Når dette er på plass så kan man kjøre skriptet.

### Feilhåndering
Skriptet vil prøve å bruke feilhånderings skriptet definert i funksjonen "GetEnvData" hvis det eksisterer.  
Hvis skriptet ikke er definert eller ikke finnes så hoppes det over å sende noe til feilhåndering.  
Forventingen er at att ett eventuelt feilhånderings skript hånderer følgende:
- Parameter: ErrorMessage, Type: string
- Parameter: ErrorObject, Type: System.Management.Automation.ErrorRecord
