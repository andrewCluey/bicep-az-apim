// PARAMS
param keyvault_name string = 'kv-hub-01'
param environment string = 'dev'
param vnet_name string = 'vn-hub-01'

@description('The Url to the KeyVault Secret containing the SSL Certificate.')
param secretUri string = 'https://kv-hub-01.vault.azure.net/secrets/san'

// VARIABLES
var randomString = uniqueString(environment, '46')


// MODULE DEPLOYMENT
module apim '../apim.bicep' = {
  name: 'apim-deployment'
  params: {
    kv_name: keyvault_name 
    location: 'uksouth'
    name: 'apim-${environment}-${randomString}'
    sku: 'Developer'
    subnet_name: 'app'
    vnet_name: vnet_name
    customDomain: 'api.your-domain.co.uk'
    secretUri: secretUri     
  }
}


