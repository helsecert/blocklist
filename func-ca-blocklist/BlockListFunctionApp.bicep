targetScope = 'resourceGroup'

@description('Workload or application name')
param workloadName string = 'blocklist'

@description('Environment (e.g., prod, dev, test)')
param environment string = 'prod'

@description('Azure region shortcode (e.g., nwe for NorwayEast, weu for WestEurope)')
param regionCode string = 'nwe'

@description('Location for resources')
param location string = resourceGroup().location

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

@description('Private DNS zone name for blocklist backend')
param privateDnsZoneName string = 'blocklist-az.helsecert.no'

@description('Private DNS A record name (root for the private endpoint)')
param privateDnsRecordName string = '@'

@description('Address space for the virtual network (recommended: /26 for small deployments, e.g., 10.203.47.0/26)')
param vnetAddressSpace string

@description('Subnet name for Function App regional VNet integration (delegated to Microsoft.Web)')
param integrationSubnetName string = 'snet-funcintegration'

@description('CIDR prefix for integration subnet (recommended: /28 for Flex Consumption, e.g., 10.203.47.0/28)')
param integrationSubnetPrefix string

@description('Subnet name reserved for future Private Endpoints (no delegation, network policies disabled)')
param privateEndpointSubnetName string = 'snet-privateendpoints'

@description('CIDR prefix for private endpoint subnet (recommended: /28, e.g., 10.203.47.16/28)')
param privateEndpointSubnetPrefix string

@description('Flex Consumption SKU (currently only FC1)')
@allowed([
  'FC1'
])
param flexSkuName string = 'FC1'

@description('PowerShell runtime version (Flex Consumption preview)')
param powershellVersion string = '7.4'

@description('Maximum instance count (Flex scale upper bound)')
@minValue(1)
@maxValue(1000)
param maximumInstanceCount int = 100

@description('Per-instance memory in MB for Flex (512, 2048, 4096)')
@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048

@description('Function App extension version')
param functionsExtensionVersion string = '~4'

@description('Whether to enable public network access on function app')
param enablePublicNetworkAccess bool = true

@description('Blob container name for one-deploy package (created if absent)')
param deploymentContainerName string = 'deploy'

@description('Tags to apply to deployed resources')
param tags object = {}

// Construct deployment container URL (Flex one-deploy expects a blob container reference)
var deploymentContainerUrl = 'https://${storage.name}.blob.${az.environment().suffixes.storage}/${deploymentContainerName}'

// Storage key (Functions still needs a storage connection string for triggers/state)
var storageKey = storage.listKeys().keys[0].value

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: tags
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
  }
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storage.name}/default/${deploymentContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: union(tags, {
    'hidden-link:${law.id}': 'Resource'
  })
  properties: {
    Application_Type: 'web'
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: law.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  sku: {
    name: flexSkuName
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  tags: tags
  properties: {
    maximumElasticWorkerCount: 1
    reserved: true
  }
}

resource func 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: enablePublicNetworkAccess ? 'Enabled' : 'Disabled'
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: deploymentContainerUrl
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      runtime: {
        name: 'powershell'
        version: powershellVersion
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
    }
    siteConfig: {
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storageKey};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: functionsExtensionVersion
        }
        {
          name: 'POWERSHELL_TELEMETRY_OPTOUT'
          value: '1'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appi.properties.ConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_RESOURCE_ID'
          value: appi.id
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'recommended'
        }
        {
          name: 'HelseCertPrivateEndpointFqdn'
          value: privateDnsZoneName
        }
        // Initially disable the TimerTriggerFunction until onboarding script activates it
        {
          name: 'AzureWebJobs.TimerTriggerFunction.Disabled'
          value: 'true'
        }
        // Activation guard flag checked inside run.ps1
        {
          name: 'BlocklistActivation'
          value: 'pending'
        }
      ]
    }
  }
  dependsOn: [
    deploymentContainer
  ]
}

// Private DNS Zone for blocklist backend
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
  properties: {}
}

// Private DNS A record at root (@) for private endpoint
// Note: IP is placeholder (0.0.0.0) - PowerShell script will update dynamically after PE creation
resource privateDnsARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: privateDnsRecordName
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '0.0.0.0'
      }
    ]
  }
}

// Network Security Group for Function App Integration Subnet
resource nsgIntegration 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${workloadName}-funcintegration-${environment}-${regionCode}-${instance}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureServicesOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['443']
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureCloud'
          description: 'Allow outbound HTTPS (443) to Azure services (Storage, Monitor, Graph API)'
        }
      }
      {
        name: 'AllowPrivateEndpointOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['443']
          sourceAddressPrefix: integrationSubnetPrefix
          destinationAddressPrefix: privateEndpointSubnetPrefix
          description: 'Allow outbound HTTPS (443) to Private Endpoint subnet for HelseCert API'
        }
      }
      {
        name: 'AllowDnsOutbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          description: 'Allow DNS resolution within VNet'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Deny all inbound traffic (Functions do not need inbound on integration subnet)'
        }
      }
    ]
  }
}

// Network Security Group for Private Endpoint Subnet
resource nsgPrivateEndpoint 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${workloadName}-privateendpoints-${environment}-${regionCode}-${instance}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowFromIntegrationSubnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['443']
          sourceAddressPrefix: integrationSubnetPrefix
          destinationAddressPrefix: privateEndpointSubnetPrefix
          description: 'Allow inbound HTTPS (443) from Function integration subnet'
        }
      }
        {
          name: 'Deny-All-Inbound'
          properties: {
            priority: 4096
            direction: 'Inbound'
            access: 'Deny'
            protocol: '*'
            sourcePortRange: '*'
            destinationPortRange: '*'
            sourceAddressPrefix: '*'
            destinationAddressPrefix: '*'
            description: 'Deny all other inbound traffic'
          }
        }
    ]
  }
}

// Virtual Network with two subnets: one delegated for Function App integration, one reserved for Private Endpoints
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: integrationSubnetName
        properties: {
          addressPrefix: integrationSubnetPrefix
          networkSecurityGroup: {
            id: nsgIntegration.id
          }
          delegations: [
            {
              name: 'delegation-web'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: nsgPrivateEndpoint.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Link Private DNS Zone to Virtual Network
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Grant the function app's system-assigned identity read access to blob content in the storage account (needed to pull package)
resource funcBlobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, 'blobdatareader', func.name)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: func.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

#disable-next-line BCP081
resource funcDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'func-ai-logs'
  scope: func
  properties: {
    workspaceId: law.id
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

output functionAppId string = func.id
output functionAppPrincipalId string = func.identity.principalId
output functionAppTenantId string = subscription().tenantId
output storageAccountName string = storage.name
output logAnalyticsWorkspaceId string = law.id
output vnetId string = vnet.id
output integrationSubnetId string = '${vnet.id}/subnets/${integrationSubnetName}'
output privateEndpointSubnetId string = '${vnet.id}/subnets/${privateEndpointSubnetName}'
output privateDnsZoneId string = privateDnsZone.id
output privateDnsZoneName string = privateDnsZone.name
output privateDnsFqdn string = privateDnsZoneName
output nsgIntegrationId string = nsgIntegration.id
output nsgPrivateEndpointId string = nsgPrivateEndpoint.id
