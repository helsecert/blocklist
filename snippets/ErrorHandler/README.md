# ErrorHandler
Dette er ett enkelt eksempelskript på hvordan ErrorHandler kan implementes for skriptene her.  
Dette skriptet sender en epost basert på parameterne det får inn.
- Parameter: ErrorMessage, Type: string
- Parameter: ErrorObject, Type: System.Management.Automation.ErrorRecord

## Komme i gang
Kopier ``.env.sample`` til ``.env`` og ``.env.credential.sample`` til ``.env.credential``.  
Deretter redigere instillingene som nødvendig.  

I ``.env`` legger man inn SMTP server addresse og epost til/fra.  
I ``.env.credential`` så kan man legge til brukernanv og passord for SMTP (hvis nødvendig).  
Om man ønsker å bruke integrert autentisering eller det ikke er noe autentisering så setter man brukernavn og passord til blankt/tomt.
