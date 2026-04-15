# Cloud Adoption Framework (CAF) navneguide

Alle ressurser i denne løsningen følger CAF-mønsteret:

```
{abbreviation}-{workload}-{environment}-{region}-{instance}
```

## Komponentreferanse

| Komponent | Formål | Eksempler |
|-----------|--------|-----------|
| `abbreviation` | CAF-forkortelse for ressurs | `func`, `asp`, `log`, `appi`, `rg`, `vnet`, `nsg` |
| `workload` | Identifikator for arbeidslast | `helsecert-blocklist` |
| `environment` | Distribusjonsstadium | `prod`, `dev`, `test`, `qa` |
| `region` | Regionskode | `nwe` (Norway East), `weu` (West Europe), `eus` (East US) |
| `instance` | Numerisk skille | `001`, `002` |

Viktige forkortelser i denne distribusjonen:

| Ressurstype | CAF-forkortelse | Eksempelnavn |
|-------------|-----------------|--------------|
| Ressursgruppe | `rg` | `rg-helsecert-blocklist-prod-nwe-001` |
| Function App | `func` | `func-helsecert-blocklist-prod-nwe-001` |
| Flex-plan | `asp` | `asp-helsecert-blocklist-prod-nwe-001(uniqueID)` |
| Storage account* | `st` | `sthelsecertblocklistprod001(uniqueID)` |
| Log Analytics | `log` | `log-helsecert-blocklist-prod-nwe-001` |
| Application Insights | `appi` | `appi-helsecert-blocklist-prod-nwe-001` |
| Virtual network | `vnet` | `vnet-helsecert-blocklist-prod-nwe-001` |
| Subnet | `snet` | `snet-funcintegration` |
| Network security group | `nsg` | `nsg-helsecert-blocklist-funcintegration-prod-nwe-001` |
| Private endpoint | `pe` | `pe-helsecert-blocklist-prod-nwe-001` |

`*` Storage accounts må være små bokstaver, alfanumeriske, 3–24 tegn og globalt unike. Skriptene renser og forkorter navn automatisk.

## Standardkonfigurasjon

`Onboard-FunctionApp.ps1` leveres med:

```powershell
$WorkloadName = 'helsecert-blocklist'
$Environment  = 'prod'
$RegionCode   = 'nwe'
$Instance     = '001'
```

Resultatnavn inkluderer:
- `rg-helsecert-blocklist-prod-nwe-001`
- `func-helsecert-blocklist-prod-nwe-001`
- `asp-helsecert-blocklist-prod-nwe-001`
- `sthelsecertblocklistprod001`
- `vnet-helsecert-blocklist-prod-nwe-001`
- `nsg-helsecert-blocklist-funcintegration-prod-nwe-001`

## Tilpasse mønsteret

### PowerShell-distribusjon
Oppdater variablene øverst i `Onboard-FunctionApp.ps1` før du kjører `Start.ps1` eller `Onboard-FunctionApp.ps1` direkte.

### Direkte Bicep-distribusjon
Overstyr parametere når du kjører abonnementsmalen:

```pwsh
az deployment sub create \
  --location norwayeast \
  --template-file BlockListFunctionApp.sub.bicep \
  --parameters \
    workloadName='myapp' \
    environment='dev' \
    regionCode='weu' \
    instance='002' \
    resourceGroupName='rg-myapp-dev-weu-002'
```

## Nyttige regionskoder

| Region | Kode |
|--------|------|
| Norway East | `nwe` |
| Norway West | `nww` |
| West Europe | `weu` |
| North Europe | `neu` |
| East US | `eus` |
| Central US | `cus` |

## Tips
- Reserver beskrivende suffiks for delte ressurser (for eksempel `snet-funcintegration`).
- Bruk instansnummeret for å skille flere miljøer per region (`001`, `002`, ...).
- Kjør onboarding på nytt etter endringer slik at Storage account- og Function App-navn regenereres konsekvent.

## Referanser
- [CAF naming guidance](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [CAF resource abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
- [Azure naming rules](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)
