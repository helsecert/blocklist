targetScope = 'subscription'

@description('Resource group name to create (CAF: rg-{workload}-{environment}-{region}-{instance})')
param resourceGroupName string

@description('Location for resource group and resources')
param location string = deployment().location

@description('Workload or application name')
param workloadName string = 'blocklist'

@description('Environment (e.g., prod, dev, test)')
param environment string = 'prod'

@description('Azure region shortcode (e.g., nwe for NorwayEast, weu for WestEurope)')
param regionCode string = 'nwe'

@description('Instance number for uniqueness')
param instance string = '001'

// CAF-compliant resource names
@description('App Service plan name (CAF: asp-{workload}-{environment}-{region}-{instance})')
param planName string = 'asp-${workloadName}-${environment}-${regionCode}-${instance}'

@description('Function App name (CAF: func-{workload}-{environment}-{region}-{instance})')
param functionAppName string = 'func-${workloadName}-${environment}-${regionCode}-${instance}'

@description('Log Analytics workspace name (CAF: log-{workload}-{environment}-{region}-{instance})')
param logAnalyticsName string = 'log-${workloadName}-${environment}-${regionCode}-${instance}'

@description('Application Insights name (CAF: appi-{workload}-{environment}-{region}-{instance})')
param appInsightsName string = 'appi-${workloadName}-${environment}-${regionCode}-${instance}'

@description('Storage account name (CAF: st{sanitizedWorkload}{environment}{instance} - no hyphens, lowercase). Hyphens removed automatically.')
param storageAccountName string = 'st${replace(workloadName, '-', '')}${environment}${instance}'

@description('Virtual Network name (CAF: vnet-{workload}-{environment}-{region}-{instance})')
param vnetName string = 'vnet-${workloadName}-${environment}-${regionCode}-${instance}'

@description('Private DNS zone name for Private Link Service')
param privateDnsZoneName string = 'blocklist-az.helsecert.no'

@description('Private DNS A record name')
param privateDnsRecordName string = 'pls-${workloadName}-${environment}-${regionCode}-${instance}'

@description('Address space for the virtual network (recommended: /26 for small deployments, e.g., 10.203.47.0/26)')
param vnetAddressSpace string

@description('Subnet name for Function App regional VNet integration (delegated to Microsoft.Web)')
param integrationSubnetName string = 'snet-funcintegration'

@description('CIDR prefix for integration subnet (recommended: /28 for Flex Consumption, e.g., 10.203.47.0/28)')
param integrationSubnetPrefix string

@description('Subnet name reserved for future Private Endpoints (network policies disabled)')
param privateEndpointSubnetName string = 'snet-privateendpoints'

@description('CIDR prefix for private endpoint subnet (recommended: /28, e.g., 10.203.47.16/28)')
param privateEndpointSubnetPrefix string

@description('Tags to apply to the resource group and its resources')
param tags object = {}

var mergedResourceGroupTags = union({
  provisionedBy: 'bicep'
}, tags)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: mergedResourceGroupTags
}

module funcModule 'BlockListFunctionApp.bicep' = {
  name: 'functionAppDeployment'
  scope: rg
  params: {
    workloadName: workloadName
    environment: environment
    regionCode: regionCode
    instance: instance
    location: location
    planName: planName
    functionAppName: functionAppName
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    storageAccountName: storageAccountName
    vnetName: vnetName
    vnetAddressSpace: vnetAddressSpace
    integrationSubnetName: integrationSubnetName
    integrationSubnetPrefix: integrationSubnetPrefix
    privateEndpointSubnetName: privateEndpointSubnetName
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    privateDnsZoneName: privateDnsZoneName
    privateDnsRecordName: privateDnsRecordName
    tags: tags
  }
}

output functionAppId string = funcModule.outputs.functionAppId
output functionAppPrincipalId string = funcModule.outputs.functionAppPrincipalId
output functionAppTenantId string = funcModule.outputs.functionAppTenantId
output logAnalyticsWorkspaceId string = funcModule.outputs.logAnalyticsWorkspaceId
output vnetId string = funcModule.outputs.vnetId
output integrationSubnetId string = funcModule.outputs.integrationSubnetId
output privateEndpointSubnetId string = funcModule.outputs.privateEndpointSubnetId
output privateDnsZoneId string = funcModule.outputs.privateDnsZoneId
output privateDnsFqdn string = funcModule.outputs.privateDnsFqdn
output nsgIntegrationId string = funcModule.outputs.nsgIntegrationId
output nsgPrivateEndpointId string = funcModule.outputs.nsgPrivateEndpointId
