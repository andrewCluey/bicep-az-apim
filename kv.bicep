param kv_name string

param apim_userAssignedId_clientId string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kv_name
}

resource kv_ac 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: kv
  name: 'add'
  properties: {
    accessPolicies: [
      {
        objectId: apim_userAssignedId_clientId
        permissions: {
          secrets: [
            'get'
            'list'  
          ]
          certificates: [
            'get'
            'list'  
          ] 
        }
        tenantId: tenant().tenantId
      } 
    ]
  }
}
