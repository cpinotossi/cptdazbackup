targetScope = 'managementGroup'

@sys.description('The Spoke Virtual Network Resource ID.')
param parVirtualNetworkResourceId string

@sys.description('The Private DNS Zone Resource IDs to associate with the spoke Virtual Network.')
param parPrivateDnsZoneResourceId string

// var varPrivateDnsZoneName = (!empty(parPrivateDnsZoneResourceId) && contains(parPrivateDnsZoneResourceId, '/providers/Microsoft.Network/privateDnsZones/') ? split(parPrivateDnsZoneResourceId, '/')[8] : '')
var varPrivateDnsZoneResourceGroup = (!empty(parPrivateDnsZoneResourceId) && contains(parPrivateDnsZoneResourceId, '/providers/Microsoft.Network/privateDnsZones/') ? split(parPrivateDnsZoneResourceId, '/')[4] : '')
var varPrivateDnsZoneSubscriptionId = (!empty(parPrivateDnsZoneResourceId) && contains(parPrivateDnsZoneResourceId, '/providers/Microsoft.Network/privateDnsZones/') ? split(parPrivateDnsZoneResourceId, '/')[2] : '')

module modPrivateDnsZoneLinkToSpoke 'privateDnsZoneLinks.bicep' = {
  scope: resourceGroup(varPrivateDnsZoneSubscriptionId, varPrivateDnsZoneResourceGroup)
  name: 'modPrivateDnsZoneLinkToSpoke'
  params: {
    parPrivateDnsZoneResourceId: parPrivateDnsZoneResourceId
    parVirtualNetworkResourceId: parVirtualNetworkResourceId
  }
}
