# Blocklist Function App-onboarding

Dette repoet automatiserer utrulling av en Flex Consumption Azure Function App som synkroniserer HelseCert-blocklisten til Entra ID Conditional Access-navngitte lokasjoner hvert femte minutt. Skriptene installerer nødvendige verktøy, klargjør infrastrukturen og aktiverer funksjonen, slik at du kan onboarde et nytt miljø med én kommando. Merk: Scriptet skal bare kjøres én gang, forutsatt at onboarding fullføres. 

## Design
![Blocklist-arkitekturoversikt](design1.0.svg)

## Hurtigstart
Sørg for at tilgangskrav er lest og gjennomført før man starter scriptet. 
Kjør følgende fra rotmappen (som administrator):

```powershell
Start-Process powershell -ArgumentList '-NoExit -ExecutionPolicy Bypass -File "Start.ps1"'
```

Merk! Scriptet åpner automatisk en nettleser for innlogging i Azure og Microsoft Graph. Etter at du har logget inn i nettleseren, klikk tilbake i PowerShell-vinduet for å fortsette og følge progresjonen. Du må også velge riktig subscription i PowerShell når du blir bedt om det.

Bootstrap-skriptet:
1. Installerer forutsetninger (PowerShell 7+, Azure CLI, Bicep CLI, nødvendige PowerShell-moduler).
2. Utfører preflight-kontroller mot abonnementet og adressene.
3. Distribuerer Bicep-maler på abonnements- og ressursgruppenivå.
4. Konfigurerer applikasjonsinnstillinger og aktiverer timer-trigget når Private endpoint er klar.

## Forutsetninger og tilganger

### Verktøy (installeres automatisk av `Start.ps1`)
Hvis du hopper over bootstrap-skriptet, installer:
- PowerShell 7.2+
- Azure CLI (nyeste)
- Bicep CLI
- PowerShell-moduler: Az.Accounts, Az.Resources, Az.Network, Az.Websites, Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Az.Storage, Az.Functions, Az.PrivateDNS

### Tilgangskrav
- **Azure RBAC:** Owner på målressursgruppen eller abonnementet. User Access Administrator er også støttet for å tildele RBAC-roller; Contributor alene er ikke tilstrekkelig.
- **Entra ID admin consent:** Gi én gang for `Policy.Read.All` og `Policy.ReadWrite.ConditionalAccess` som brukes av den administrerte identiteten. Dette blir prompted automatisk ved kjøring av onboarding første gang.
- **Private endpoint-godkjenning:** HelseCert-tjenesteeier må godkjenne Private endpoint-tilkoblingen som distribusjonen oppretter. Dette skal gå ganske raskt.

## Løsningsoversikt

Den timer-utløste PowerShell-funksjonen:
- Laster ned siste HelseCert-blocklist over Private endpoint.
- Normaliserer og dedupliserer CIDR-oppføringer og deler i sett på 2 000 per Conditional Access navngitt lokasjon.
- Synkroniserer den autoritative listen til Entra ID via Microsoft Graph med administrert identitet.
- Logger diagnostikk til Application Insights og Log Analytics.
- Onboarding med én kommando og CAF-tilpassede navn og tagger.
- Flex Consumption-plan med reservert VNet-integrasjon og Private DNS.
- Automatisert modulinstallasjon i Function App-runtime via `profile.ps1`.

## Identitet og Graph-tilganger
- Function App bruker en system-tildelt Managed Identity som får `Policy.Read.All` og `Policy.ReadWrite.ConditionalAccess` i Microsoft Graph. `Start.ps1` kobler til Graph med `Connect-MgGraph -Scopes Application.ReadWrite.All,AppRoleAssignment.ReadWrite.All` for å tildele rollene automatisk.
- Hvis samtykke eller roller må fornyes (for eksempel etter at de er tilbakekalt), kjør `Start.ps1` eller `Onboard-FunctionApp.ps1` på nytt. 
- Hver gang du roterer passord eller legger til flere Conditional Access-miljøer, kjør onboarding-skriptet igjen slik at Application Insights/Log Analytics og Function App-konfigurasjonen holdes i synk.

## Distribusjonsartefakter

### Bicep-maler
- `BlockListFunctionApp.sub.bicep` – oppretter CAF-ressursgruppen og kaller arbeidsbelastningsmodulen.
- `BlockListFunctionApp.bicep` – klargjør lagring, overvåking, Flex-plan, Function App, VNet, NSG-er og Private DNS.

### PowerShell-skript
| Skript | Formål |
|--------|--------|
| `Start.ps1` | Anbefalt inngangspunkt; installerer verktøy, kjører validering, distribuerer infrastrukturen. |
| `Preflight-BlocklistFunctionApp.ps1` | Utfører forutsetningskontroller uten å distribuere ressurser. |
| `Onboard-FunctionApp.ps1` | Distribuerer arbeidslasten når verktøy allerede er installert. |

### Function App-artefakter
- `function/profile.ps1` – installerer nødvendige Graph-moduler og autentiserer med administrert identitet.
- `function/TimerTriggerFunction/run.ps1` – timerlogikk for blocklist-nedlasting og Conditional Access-synkronisering.
- `function/TimerTriggerFunction/function.json` – binder timer-triggeren, definerer `runOnStartup`, frekvens og loggnivåer.
- `function/host.json` – konfigurasjon på host-nivå for Function-runtime.

### Nettverksbilde
- VNet `vnet-<workload>-<env>-<region>-<instance>` med to subnett: `snet-funcintegration` (delegert til Microsoft.Web) og `snet-privateendpoints` (kun Private endpoints).
- NSG-er begrenser trafikk til nødvendige Azure service tags og stien for Private endpoint.
- Private DNS-sone `norwayeast.azure.privatelinkservice` kobles tilbake til VNet for navneoppløsning.
- Etter at Private endpoint-tilkoblingen er godkjent, oppdaterer onboarding applikasjonsinnstillingene `HelseCertPrivateEndpointFqdn` og `HelseCertPrivateEndpointIP`.

📖 Se `NETWORK-IMPLEMENTATION.md` for fullstendig nettverksveiledning.

## Ressursnavn som distribueres (standard)

Navn følger CAF-mønsteret `abbreviation-workload-environment-region-instance`. Med standardverdiene i `Onboard-FunctionApp.ps1` får du:
- Ressursgruppe: `rg-helsecert-blocklist-prod-nwe-001`
- Function App: `func-helsecert-blocklist-prod-nwe-001`
- Flex-plan: `asp-helsecert-blocklist-prod-nwe-001`
- Storage account: `sthelsecertblocklistprod001`
- Virtual network: `vnet-helsecert-blocklist-prod-nwe-001`
- NSG-er: `nsg-helsecert-blocklist-funcintegration-prod-nwe-001`, `nsg-helsecert-blocklist-privateendpoints-prod-nwe-001`
- Overvåking: `log-helsecert-blocklist-prod-nwe-001`, `appi-helsecert-blocklist-prod-nwe-001`

## Feilsøking

| Symptom | Foreslått løsning |
|---------|-------------------|
| Timer kjører ikke | Kontroller at `BlocklistActivation` er satt til `ready` og at `AzureWebJobs.TimerTriggerFunction.Disabled` fortsatt er `false`. |
| Graph-tilgangsfeil | Bekreft tenant-admin consent for Graph-tillatelsene, og kjør onboarding på nytt for å oppdatere tokenene. |
| Private endpoint-IP mangler | Vent på godkjenning av Private endpoint-forespørselen, og kjør deretter `Onboard-FunctionApp.ps1` på nytt. |
| Storage account-navn avvist | Kort ned eller forenkle `$WorkloadName` / `$Instance`; storage-navn må være små bokstaver, alfanumerisk og ≤24 tegn. |

- Logging av onboardingsscript finner du her: "C:\ProgramData\BlocklistFunctionApp\Logs\"

## Tilleggsdokumentasjon
- `CAF-NAMING.md` – hvordan justere CAF-tilpassede navn og regionkoder.
- `NETWORK-IMPLEMENTATION.md` – subnettoppsett, NSG-er, Private DNS og valideringsveiledning.
