
param customDomain string

param dns_records array

param apim_private_ipAddresses string

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
        ipv4Address: apim_private_ipAddresses
      } 
    ] 
  }
}]
