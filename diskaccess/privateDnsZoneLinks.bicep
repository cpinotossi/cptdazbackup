targetScope = 'resourceGroup'

@sys.description('The Spoke Virtual Network Resource ID.')
param parVirtualNetworkResourceId string

@sys.description('The Private DNS Zone Resource IDs to associate with the spoke Virtual Network.')
param parPrivateDnsZoneResourceId string

@sys.description('The Private DNS Zone Resource IDs to associate with the spoke Virtual Network.')
param registrationEnabled bool = false

var varVirtualNetworkName = (!empty(parVirtualNetworkResourceId) && contains(parVirtualNetworkResourceId, '/providers/Microsoft.Network/virtualNetworks/') ? split(parVirtualNetworkResourceId, '/')[8] : '')
var varPrivateDnsZoneName = (!empty(parPrivateDnsZoneResourceId) && contains(parPrivateDnsZoneResourceId, '/providers/Microsoft.Network/privateDnsZones/') ? split(parPrivateDnsZoneResourceId, '/')[8] : '')


resource resPrivateDnsZoneLinkToSpoke 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (!empty(parPrivateDnsZoneResourceId)) {
  location: 'global'
  name: '${varPrivateDnsZoneName}/dnslink-to-${varVirtualNetworkName}'
  properties: {
    registrationEnabled: registrationEnabled
    virtualNetwork: {
      id: parVirtualNetworkResourceId
    }
  }
}
