targetScope = 'managementGroup'

// Peering Modules Parameters
@sys.description('Virtual Network ID of Hub Virtual Network, or Azure Virtuel WAN hub ID.')
param spokeVirtualNetworkId string

// Peering Modules Parameters
@sys.description('Virtual Network ID of Hub Virtual Network, or Azure Virtuel WAN hub ID.')
param hubVirtualNetworkId string

var hubVirtualNetworkName = (!empty(hubVirtualNetworkId) && contains(hubVirtualNetworkId, '/providers/Microsoft.Network/virtualNetworks/') ? split(hubVirtualNetworkId, '/')[8] : '')
var hubVirtualNetworkResourceGroup = (!empty(hubVirtualNetworkId) && contains(hubVirtualNetworkId, '/providers/Microsoft.Network/virtualNetworks/') ? split(hubVirtualNetworkId, '/')[4] : '')
var hubVirtualNetworkSubscriptionId = (!empty(hubVirtualNetworkId) && contains(hubVirtualNetworkId, '/providers/Microsoft.Network/virtualNetworks/') ? split(hubVirtualNetworkId, '/')[2] : '')

var spokeVirtualNetworkName = (!empty(spokeVirtualNetworkId) && contains(spokeVirtualNetworkId, '/providers/Microsoft.Network/virtualNetworks/') ? split(spokeVirtualNetworkId, '/')[8] : '')
var spokeVirtualNetworkResourceGroup = (!empty(spokeVirtualNetworkId) && contains(spokeVirtualNetworkId, '/providers/Microsoft.Network/virtualNetworks/') ? split(spokeVirtualNetworkId, '/')[4] : '')
var spokeVirtualNetworkSubscriptionId = (!empty(spokeVirtualNetworkId) && contains(spokeVirtualNetworkId, '/providers/Microsoft.Network/virtualNetworks/') ? split(spokeVirtualNetworkId, '/')[2] : '')

// Module - Hub to Spoke peering.
module modHubPeeringToSpoke 'vnetPeering.bicep' = {
  scope: resourceGroup(hubVirtualNetworkSubscriptionId, hubVirtualNetworkResourceGroup)
  name: 'modHubPeeringToSpoke'
  params: {
    parDestinationVirtualNetworkId: spokeVirtualNetworkId
    parDestinationVirtualNetworkName: spokeVirtualNetworkName
    parSourceVirtualNetworkName: hubVirtualNetworkName
  }
}

// Module - Spoke to Hub peering.
module modSpokePeeringToHub 'vnetPeering.bicep' = {
  scope: resourceGroup(spokeVirtualNetworkSubscriptionId, spokeVirtualNetworkResourceGroup)
  name: 'modSpokePeeringToHub'
  params: {
    parDestinationVirtualNetworkId: hubVirtualNetworkId
    parDestinationVirtualNetworkName: hubVirtualNetworkName
    parSourceVirtualNetworkName: spokeVirtualNetworkName
  }
}


