param spokeVirtualNetworkId string

var spokeVirtualNetworkName = (!empty(spokeVirtualNetworkId) && contains(spokeVirtualNetworkId, '/providers/Microsoft.Network/virtualNetworks/') ? split(spokeVirtualNetworkId, '/')[8] : '')

resource pdns 'Microsoft.Network/privateDnsZones@2018-09-01' existing = {
  name: 'privatelink.blob.core.windows.net'
}

resource pdnsLink2 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  parent: pdns
  name: spokeVirtualNetworkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVirtualNetworkId
    }
  }
}
