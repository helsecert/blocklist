# Network implementation

## Topologi
- VNet `vnet-<workload>-<env>-<region>-<instance>` med standard CIDR `10.203.47.0/24` (kan endres via skriptparametere).
- `snet-funcintegration` delegert til `Microsoft.Web/serverFarms` for regional VNet-integrasjon (standard `10.203.47.0/26`).
- `snet-privateendpoints` reservert for Private endpoints med nettverkspolicy deaktivert (standard `10.203.47.64/26`).
- NSG-er (`nsg-*-funcintegration-*` og `nsg-*-privateendpoints-*`) begrenser trafikk mellom integrasjonssubnettet, Private endpoint-subnettet og nødvendige Azure service tags.

## Tilgangskontroll
- Offentlig nettverkstilgang til Function App er deaktivert; trafikken går via VNet-integrasjon.
- Private DNS-sone `norwayeast.azure.privatelinkservice` kobles til VNet slik at Private endpoint løses internt.
- Private endpoint arver IP-en dynamisk fra `snet-privateendpoints`; onboarding fanger IP/FQDN i appinnstillingene (`HelseCertPrivateEndpointIP`, `HelseCertPrivateEndpointFqdn`).

## Drift
- Overvåk Application Insights og Log Analytics for tilkoblingsdiagnostikk som skrives av `run.ps1`.
- Revider NSG-regler jevnlig for å sikre at de beholder least privilege-omfang.
- Valider Private endpoint-status når du trenger innsikt i godkjenninger:

```pwsh
az network private-endpoint-connection list `
  --name pe-helsecert-blocklist-prod-nwe-001 `
  --resource-group rg-helsecert-blocklist-prod-nwe-001 `
  --type microsoft.web/sites | ConvertFrom-Json |
  Select-Object name,properties.connectionState.status
```

- Bekreft at Private DNS peker internt før du aktiverer timeren:

```pwsh
Resolve-DnsName <HelseCertPrivateEndpointFqdn> -Server 168.63.129.16
```

- Bruk `Test-AzNetworkWatcherConnectivity` ved behov for å feilsøke ruten fra Function App-integrasjonssubnettet:

```pwsh
Test-AzNetworkWatcherConnectivity `
  -NetworkWatcherName 'NetworkWatcher_norwayeast' `
  -ResourceGroupName 'NetworkWatcherRG' `
  -SourceResourceId "/subscriptions/<subId>/resourceGroups/rg-helsecert-blocklist-prod-nwe-001/providers/Microsoft.Network/virtualNetworks/vnet-helsecert-blocklist-prod-nwe-001/subnets/snet-funcintegration" `
  -DestinationAddress "<HelseCertPrivateEndpointFqdn>" `
  -Protocol Tcp -Port 443
```

## Referanser
- [Azure Functions networking options](https://learn.microsoft.com/azure/azure-functions/functions-networking-options)
- [Azure Private Endpoint overview](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
