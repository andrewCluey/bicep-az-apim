/*
 vNet integrated mode requires:
 - subnet with no delegations
 - public IP to be created and assigned to the APIM
 - NSG with required rules (see below.)

Source / Destination Port(s)	Direction	Transport protocol	Service tags
Source / Destination	Purpose	VNet type
* / [80], 443	Inbound	TCP	Internet / VirtualNetwork	Client communication to API Management	External only
* / 3443	Inbound	TCP	ApiManagement / VirtualNetwork	Management endpoint for Azure portal and PowerShell	External & Internal
* / 6390	Inbound	TCP	AzureLoadBalancer / VirtualNetwork	Azure Infrastructure Load Balancer	External & Internal
* / 443	Inbound	TCP	AzureTrafficManager / VirtualNetwork	Azure Traffic Manager routing for multi-region deployment	External only
* / 443	Outbound	TCP	VirtualNetwork / Storage	Dependency on Azure Storage	External & Internal
* / 1433	Outbound	TCP	VirtualNetwork / SQL	Access to Azure SQL endpoints	External & Internal
* / 443	Outbound	TCP	VirtualNetwork / AzureKeyVault	Access to Azure Key Vault	External & Internal
* / 1886, 443	Outbound	TCP	VirtualNetwork / AzureMonitor	Publish Diagnostics Logs and Metrics, Resource Health, and Application Insights	External & Internal

- A Private DNS Zone for the custom domain is required to register A records for `Gateway` & `Portal`.

*/

 @description('The name to assign to the new APIM instance.')
param name string

@description('The Azure region for the APIM.')
param location string = resourceGroup().location

param tags object = {}

@description('The email address of the owner of the service')
@minLength(1)
param publisherEmail string = 'noreply@microsoft.com'

@description('The name of the owner of the service')
@minLength(1)
param publisherName string = 'n/a'

@description('The pricing tier of this API Management service')
@allowed([
  'Consumption'
  'Developer'
  'Standard'
  'Premium'
])
param sku string = 'Consumption'

@description('The instance size of this API Management service.')
@allowed([ 0, 1, 2 ])
param skuCount int = 0

@description('The name of the Subnet where APIM endpoints will be created.')
param subnet_name string

@description('The name of the vNET that hosts the subnet for the new APIM instance.')
param vnet_name string

param createAppInsightsLogger bool = false

@description('Azure Application Insights Name')
param applicationInsightsId string = ''

@description('The Instrumentation Key for the App Insights instance that APIM will report to.')
param appInsightsInstrumentationKey string = ''

param publicIpSku string = 'Standard'

@description('''
Unique DNS name for the public IP address that is created for Management access to APIM. 
NOTE: This does not mean the APIM is accessible publicly, it is for Azure management plane access via the Azure backbone.
''')
param dnsLabelPrefix string = toLower('${name}-${uniqueString(resourceGroup().id)}')

@allowed([
  'Enabled'
  'Disabled'
])
param management_pubAccess string = 'Enabled'

@description('Url to the KeyVault Secret containing the Ssl Certificate. If absolute URL contains the version of the secret/cert, then auto-update of the SSL certificate will not work. This requires API Management service to be configured with aka.ms/apimmsi. The secret should be of type application/x-pkcs12')
param secretUri string 

@description('The custom domain to use for the APIM Gateway & Portal endpoints.')
param customDomain string

@description('The name of the Key Vault where the certificate secret is stored.')
param kv_name string


// VARIABLES
var nsgName = 'apimnsg${uniqueString(resourceGroup().id)}'
var dns_records = [
  'gateway'
  'portal'
]


// RESOURCES
resource userIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${name}-identity'
  location: location 
}

resource apimService 'Microsoft.ApiManagement/service@2023-03-01-preview' = {
  name: name
  location: location
  tags: tags

  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userIdentity.id}': {}
    }
  }

  sku: { 
    name: sku
    capacity: (sku == 'Consumption') ? 0 : ((sku == 'Developer') ? 1 : skuCount)
  } 
  
  properties: {
    developerPortalStatus: 'Enabled'
    publicNetworkAccess: management_pubAccess
    publicIpAddressId: publicIp.id
    virtualNetworkType: 'Internal'
    
    virtualNetworkConfiguration: {
      subnetResourceId: associateNsg.outputs.subnetId
    }

    hostnameConfigurations: [
      {
        hostName: 'gateway.${customDomain}'
        type: 'Proxy'
        certificateSource: 'KeyVault'
        keyVaultId: secretUri
        identityClientId: userIdentity.properties.clientId
      }
      {
        hostName: 'portal.${customDomain}'
        type: 'DeveloperPortal'
        certificateSource: 'KeyVault'
        keyVaultId: secretUri
        identityClientId: userIdentity.properties.clientId
      }
    ]
    customProperties: {
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
        'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'false'
      }
      publisherEmail: publisherEmail
      publisherName: publisherName
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = if ((createAppInsightsLogger == true)) {
  name: 'app-insights-logger'
  parent: apimService
  properties: {
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    description: 'Logger to Azure Application Insights'
    isBuffered: false
    loggerType: 'applicationInsights'
    resourceId: applicationInsightsId
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-06-01' = {
  name: '${name}-pip'
  location: location
  sku: {
    name: publicIpSku
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-06-01' = {
  name: nsgName
  location: location
  properties: { 
    securityRules: [
      {
        name: 'Management_endpoint_for_Azure_portal_and_Powershell'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'Dependency_on_Redis_Cache'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6381-6383'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'Dependency_to_sync_Rate_Limit_Inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '4290'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 135
          direction: 'Inbound'
        }
      }
      {
        name: 'Dependency_on_Azure_SQL'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          priority: 140
          direction: 'Outbound'
        }
      }
      {
        name: 'Dependency_for_Log_to_event_Hub_policy'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '5671'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'EventHub'
          access: 'Allow'
          priority: 150
          direction: 'Outbound'
        }
      }
      {
        name: 'Dependency_on_Redis_Cache_outbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6381-6383'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 160
          direction: 'Outbound'
        }
      }
      {
        name: 'Dependency_To_sync_RateLimit_Outbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '4290'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 165
          direction: 'Outbound'
        }
      }
      {
        name: 'Dependency_on_Azure_File_Share_for_GIT'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '445'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 170
          direction: 'Outbound'
        }
      }
      {
        name: 'Azure_Infrastructure_Load_Balancer'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 180
          direction: 'Inbound'
        }
      }
      {
        name: 'Publish_DiagnosticLogs_And_Metrics'
        properties: {
          description: 'API Management logs and metrics for consumption by admins and your IT team are all part of the management plane'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 185
          direction: 'Outbound'
          destinationPortRanges: [
            '443'
            '12000'
            '1886'
          ]
        }
      }
      {
        name: 'Connect_To_SMTP_Relay_For_SendingEmails'
        properties: {
          description: 'APIM features the ability to generate email traffic as part of the data plane and the management plane'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 190
          direction: 'Outbound'
          destinationPortRanges: [
            '25'
            '587'
            '25028'
          ]
        }
      }
      {
        name: 'Authenticate_To_Azure_Active_Directory'
        properties: {
          description: 'Connect to Azure Active Directory for developer portal authentication or for OAuth 2 flow during any proxy authentication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
          access: 'Allow'
          priority: 200
          direction: 'Outbound'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
      {
        name: 'Dependency_on_Azure_Storage'
        properties: {
          description: 'APIM service dependency on Azure blob and Azure table storage'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'Publish_Monitoring_Logs'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 300
          direction: 'Outbound'
        }
      }
      {
        name: 'Access_KeyVault'
        properties: {
          description: 'Allow API Management service control plane access to Azure Key Vault to refresh secrets'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
          access: 'Allow'
          priority: 350
          direction: 'Outbound'
          destinationPortRanges: [
            '443'
          ]
        }
      }
      {
        name: 'Deny_All_Internet_Outbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Internet'
          access: 'Deny'
          priority: 999
          direction: 'Outbound'
        }
      }
    ]
  }
}


// Get existing vnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-06-01' existing = {
  name: vnet_name
}

// Get existing subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = {
  name: subnet_name
  parent: vnet
}

// Associate NSG with the Subnet
module associateNsg 'updateSubnet.bicep' = {
  name: 'associateNSG-${guid(nsgName, subnet_name)}'
  params: {
    vnetName: vnet.name
    subnetName: subnet_name
    properties: union(subnet.properties, {
      networkSecurityGroup: {
        id: apimNsg.id
      }
    })
  }
}

// Get the Private DNS Zone for the Custom Domain
resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: customDomain
}

resource registerApimNames 'Microsoft.Network/privateDnsZones/A@2020-06-01' = [for record in dns_records: {
  parent: zones
  name: record
  properties: {
    ttl: 3600 
    aRecords: [
      {
        ipv4Address: apimService.properties.privateIPAddresses[0]  
      } 
    ] 
  }
}]

// KV Role Assignment
module kv 'kv.bicep' = {
  name: 'deployment-${guid(kv_name, userIdentity.id)}'
  params: {
    apim_userAssignedId_clientId: userIdentity.properties.principalId
    kv_name: kv_name
  }
}


// OUTPUTS
output apimServiceName string = apimService.name

output nsgId string = apimNsg.id

output apimId string = apimService.id

output apimGatewayUrl string = apimService.properties.gatewayUrl

output apimPlatformVersion string = apimService.properties.platformVersion

@description('The client ID of the User Assigned Identity that has been assigned to the APIM Instance.')
output userAssignedIdentity_clientId string = userIdentity.properties.principalId

output userAssignedIdentity_resourceId string = userIdentity.id

output ApimGatewayIP string = apimService.properties.privateIPAddresses[0]

output apimGatewayFQDN string = apimService.properties.gatewayUrl

output apimDeveloperPortal string = apimService.properties.developerPortalUrl

