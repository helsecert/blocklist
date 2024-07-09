# Skript eksempler for HelseCERT blocklist
I denne mappen er det skript for å hente og bruker HelseCERT sin blocklist.  
Skripene er skrevet med tanke på å være små og fokuserte skript på spesifike jobber som man kan plukke og sy sammen tilpasset sitt eget miljø.  
Disse er også rimelig "opinionated". Det er mange måter å gjøre ting på med PowerShell, så det kan være bedre (og dårligere) måter å løse disse tingene på.

Skriptene har ett konfigurasjons design der man putter statisk konfigurasjon i ``.env`` og pålogginginformasjon (brukernavn/passord, sertifikat thumpprint, osv...) i ``.env.credential``.  

Hvert skript har sin egen README, men her er overordnet beskrivelse av skriptene.

## BlockListDownload
Dette skriptet er ment for å bare laste ned HelseCERT sine blocklister i CSV format.  
Skriptet henter full liste med kontekst infomrasjon, og enkle lister i CDIR og regex format.  
Dette kan være nyttig om man henter ned listene på en sentral server og andre løsninger kan da bruke disse listene videre.

## UpdateConditonalAccessDirect
Dette skriptet henter blocklist data og oppdaterer direkte en location liste i Microsoft Entra Conditonal Access.  
Ingen mellomlagring og oppdaterer direkte basert på cdir listen fra HelseCERT.

## UpdateConditonalAccessIndirect
Dette skriptet oppdaterer location listen i Microsoft Entra Conditonal Acccess basert på cdir listen som er hentet ned via ``BlockListDownload``.  
Kan være nyttig hvis man må splitte oppgavene på hvilken server som henter listen og hvem som har rettighet til å endre på Conditonal Access.  

## ErrorHandler
Dette skriptet er en enkel implementering av varsling via SMTP hvis ett av skriptene her feiler.  
Tar i praksis en melding og ett PowerShell Exception objekt og sender infomrasjonen her til en epost man har definert.  
Denne metoden gjør det mulig å skrive sin egen tilpasset varsling hvis man f.eks. ønsker å bruke GraphAPI til å sende mail istedenfor.

### Feilhåndering
Skriptene vil generelt sett prøve prøve å bruke feilhånderings skriptet definert i funksjonen "GetEnvData" hvis det eksisterer.
Hvis skriptet ikke er definert eller ikke finnes så hoppes det over å sende noe til feilhåndering.  
Forventingen er at att ett eventuelt feilhånderings skript hånderer følgende:
- Parameter: ErrorMessage, Type: string
- Parameter: ErrorObject, Type: System.Management.Automation.ErrorRecord
