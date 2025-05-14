# Scripts og guides for Helse- og KommuneCERTs blokkeringslister

Her ligger kode som kan brukes for å integrere med Helse- og KommuneCERTs blokkeringslister for ulike produkter.

Blokkeringslistene er en av tjenestene vi tilbyr til medlemmer i Nasjonalt beskyttelsesprogram. Se [helsecert.no](helsecert.no) for alle tjenester.

Skriptene er i hovedsak laget av våre medlemmer og brukt i produksjonssystemer i dag. 

## Bruke blokkeringslister

Når man ber om tilgang til blokkeringslistene får man en intro-e-post med infor for å komme i gang. Blokkeringslistene har også et api hvor man kan spesifisere hva man vil hente ned.

Blokkeringslistene har to hovedbruksområder: 
- Blokkering av IP / domener i brannmur/proxy/endepunkt
- Blokkinger og søk etter phishing-IPer i M365

## Brannmur
- [Fortigate](https://github.com/helsecert/blocklist/blob/master/FortigateBrannmur.md)

## Endepunkt
### Defender for Endpoint
- [Defender for Endpoint](https://github.com/helsecert/blocklist/blob/master/m365-single-tenant/Add-MSDefIOCFromHSBlocklist.ps1)
  - NB! Fordi dette scriptet gjenbruker config fra m365-single-tenant scriptet nevnt under, ligger dette under [m365-single-tenant](https://github.com/helsecert/blocklist/tree/master/m365-single-tenant)

## M365-phishing / Entra ID

- For dere som vil sette det opp for en M365-tenant har vi fått inn flere måter i gjøre dette på.
  - Mappen [m365-single-tenant](https://github.com/helsecert/blocklist/tree/master/m365-single-tenant) inneholder skript for å
    - oppdatere blokkeringsliste
    - søke 30 dager tilbake i tid for å se om angriper har logget inn fra en kjent angreps-IP
    - Kim André Vaksdal har laget en god [guide](https://prottecio.com/2025/05/13/2025-automating-updated-named-locations-like-a-boss/) for dette
  - Mappen [snippets](https://github.com/helsecert/blocklist/tree/master/snippets) inneholder dedikerte skripts for å:
    - laste ned og lagre blockliste-data
    - oppdatere blokkeringslister i M365 basert på nedlasted data
    - Laste og oppdatere i ett (om dette gjøres fra samme maskin)
    - dedikerte skript for å håndtere feilsituasjoner
  -  Mappen [m365-sentinel-watchlist](https://github.com/helsecert/blocklist/tree/master/m365-sentinel-watchlist) inneholder script for å oppdatere watchlist i Sentinel


## Hvor har dere guide for \<mitt produkt\>

Vi legger ut skript / guider vi får fra medlemmer fortløpende. Finner du ikke ditt produkt her er vi takknemlige om DU kan lage en guide for det. Guider tas imot med takk på "post@helsecert.no"

## Feil / mangler
Har du/dere:
* Forbedringer til skript/beskrivelser

Vi vil gjerne ha med ditt bidrag! Kontakt oss på *post@helsecert.no*.


## Forutsetninger


For tilgang til blokkeringslistene må:
* Din virksomhet være medlem hos oss. 
  * Se https://helsecert.no -> bli medlem
* Dere har aktivert tjenesten "blokkeringslister". 
  * For å aktivere:  Send e-post til post@helsecert.no med:
    * IP-adresse(r) evt IP-nett som skal teste og bruke blokkeringslister - (kan hentes ned via internett).
    * Kontaktperson hos dere. E-post og telefonnummer
 
IP-adresse dere kommer fra kan finnes ved å kjøre `curl https://api.ipify.org` i kommandolinje eller fra browser.
