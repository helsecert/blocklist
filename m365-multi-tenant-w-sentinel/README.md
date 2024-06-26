# M365 integrasjon for de med mer enn en tenant og tilgang på sentinel

## Introduksjon
Dette skriptet brukes i dag i Norsk helsenett for søk på tvers av flere M365-tenants på en gang. Skriptet henter ned blokklistedata fra Helse- og KommuneCERTs blokkeringslister og bruker dette til blokkering og søk i flere tenants.
Dette orkestreres gjennom Microsoft Sentinel

## Innhold

## Komme i gang
For å ta i bruk dette kreves:
* Dere har aktivert tjenesten "blokkeringslister". 
  * For å aktivere:  Send e-post til post@helsecert.no med:
    * IP-adresse(r) evt IP-nett som skal teste og bruke blokkeringslister - (kan hentes ned via både internett og helsenett).
    * Kontaktperson hos dere. E-post og telefonnummer
* [Microsoft Sentinel](https://azure.microsoft.com/en-us/pricing/details/microsoft-sentinel/)


## For søking på tvers av tenants
Søk som kan brukes på tvers av tenants.
```
// Define the Watchlist alias
let watchlistAlias = "HelseCERT_Blocklist_IPv4";
// Get IPv4 addresses from the Watchlist
let WatchlistIPs = (_GetWatchlist(watchlistAlias)
    | project WatchlistIPAddress = ipv4);
//
// Search for IPv4 address in Signin logs Cross tenant
CrossTenantSigninLogsProd
// Join with the Watchlist IP records
| join kind=inner WatchlistIPs on $left.IPAddress == $right.WatchlistIPAddress
| extend TimeGenerated_UTC = format_datetime(TimeGenerated, 'dd/MM/yyyy HH:mm:ss')
| extend Succeeded = parse_json(AuthenticationDetails)[0].succeeded
| extend ResultDetail = parse_json(AuthenticationDetails)[0].authenticationStepResultDetail
| extend Method = parse_json(AuthenticationDetails)[0].authenticationMethod
| extend MethodDetail = parse_json(AuthenticationDetails)[0].authenticationMethodDetail
| extend Tenant = tostring(split(UserPrincipalName, "@")[1])
// Project required fields
| project
    TimeGenerated_UTC,
    Tenant,
    UserPrincipalName,
    IPAddress,
    Location,
    ClientAppUsed,
    AppDisplayName,
    ResourceDisplayName,
    IsInteractive,
    UserAgent,
    Method,
    MethodDetail,
    Succeeded,
    ResultDetail
```