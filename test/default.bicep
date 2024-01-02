// PARAMS
param keyvault_name string = 'kv-hub-01'
param environment string = 'dev'
param vnet_name string = 'vn-hub-01'

@description('The Url to the KeyVault Secret containing the Ssl Certificate.')
param secretUri string = 'https://kv-hub-01.vault.azure.net/secrets/cert'  //'https://kv-hub-01.vault.azure.net/secrets/wildcard' //'https://kv-hub-01.vault.azure.net/secrets/api-cert'


// VARIABLES
var randomString = uniqueString(environment, '6754')


// MODULE DEPLOYMENT
module apim '../apim.bicep' = {
  name: 'apim-deployment'
  params: {
    kv_name: keyvault_name
    keyvault_resourceGroup: 'rg-kv'
    keyvault_subscriptionId: 'dummy-s321-4eds-789s-subId6576rt'
    location: 'uksouth'
    name: 'apim-${environment}-${randomString}'
    sku: 'Developer'
    subnet_name: 'app'
    vnet_name: vnet_name
    vnet_resource_group: 'rg-network' 
    customDomain: 'api.my-customdomain.org'
    customDomainDnsZone_SubscriptionId: 'dummy-s321-4eds-789s-subId6576rt'
    customDomainDnsZone_resourceGroup: 'rg-network' 
    secretUri: secretUri     
  }
}


