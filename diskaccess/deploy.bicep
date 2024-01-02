targetScope='managementGroup'

param hubSubscriptionId string
param spokeSubscriptionId string
param location string = 'germanywestcentral'
param currentUserObjectId string

@description('Prefix used in the Naming for multiple Deployments in the same Subscription')
param prefix string
// load from json file

var IPAM = loadJsonContent('./IPAM.json')

module rg1 'rg.bicep' = {
  name: 'rg1'
  params: {
    name: prefix
    location: location
  }
  scope: subscription(hubSubscriptionId)
}

module rg2 'rg.bicep' = {
  name: 'rg2'
  params: {
    name: prefix
    location: location
  }
  scope: subscription(spokeSubscriptionId)
}


module infra1 'infra.hub.bicep' = {
  name: 'infra-vnet1'
  params: {
    currentUserObjectId: currentUserObjectId
    IPAM:IPAM
    prefix: prefix
    postfix: '1'
    location: location
  }
  scope: resourceGroup(hubSubscriptionId, prefix)
  dependsOn: [
    rg1
  ]
}

module infra2 'infra.spoke.bicep' = {
  name: 'infra-vnet2'
  params: {
    currentUserObjectId: currentUserObjectId
    IPAM:IPAM
    prefix: prefix
    postfix: '2'
    location: location
  }
  scope: resourceGroup(hubSubscriptionId, prefix)
  dependsOn: [
    rg1
  ]
}

module infra3 'infra.spoke.bicep' = {
  name: 'infra-vnet3'
  params: {
    currentUserObjectId: currentUserObjectId
    IPAM:IPAM
    prefix: prefix
    postfix: '3'
    location: location
  }
  scope: resourceGroup(spokeSubscriptionId, prefix)
  dependsOn: [
    rg2
  ]
}

module peering1to2 'vnetPeeringService.bicep' = {
  name: 'peering1to2'
  params: {
    hubVirtualNetworkId: infra1.outputs.vnetId
    spokeVirtualNetworkId: infra2.outputs.vnetId
  }
}

module peering1to3 'vnetPeeringService.bicep' = {
  name: 'peering1to3'
  params: {
    hubVirtualNetworkId: infra1.outputs.vnetId
    spokeVirtualNetworkId: infra3.outputs.vnetId
  }
}

module dnsLinktoVnet1 'privateDnsZoneLinksService.bicep' = {
  name: 'dnsLinktoVnet1'
  params: {
    parPrivateDnsZoneResourceId: infra1.outputs.pDnsId
    parVirtualNetworkResourceId: infra1.outputs.vnetId
  }
  dependsOn: [
    infra1
  ]
}

module dnsLinktoVnet2 'privateDnsZoneLinksService.bicep' = {
  name: 'dnsLinktoVnet2'
  params: {
    parPrivateDnsZoneResourceId: infra1.outputs.pDnsId
    parVirtualNetworkResourceId: infra2.outputs.vnetId
  }
  dependsOn: [
    infra1
    infra2
    dnsLinktoVnet1
  ]
}

module dnsLinktoVnet3 'privateDnsZoneLinksService.bicep' = {
  name: 'dnsLinktoVnet3'
  params: {
    parPrivateDnsZoneResourceId: infra1.outputs.pDnsId
    parVirtualNetworkResourceId: infra3.outputs.vnetId
  }
  dependsOn: [
    infra1
    infra3
    dnsLinktoVnet2
  ]
}


var builtInRoleNames = {
  Contributor: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  'Data Operator for Managed Disks': tenantResourceId('Microsoft.Authorization/roleDefinitions', '959f8984-c045-4866-89c7-12bf9737be2e')
  'Disk Backup Reader': tenantResourceId('Microsoft.Authorization/roleDefinitions', '3e5e47e6-65f7-47ef-90b5-e5dd4d455f24')
  'Disk Pool Operator': tenantResourceId('Microsoft.Authorization/roleDefinitions', '60fc6e62-5479-42d4-8bf4-67625fcc2840')
  'Disk Restore Operator': tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b50d9833-a0cb-478e-945f-707fcc997c13')
  'Disk Snapshot Contributor': tenantResourceId('Microsoft.Authorization/roleDefinitions', '7efff54f-a5b4-42b5-a1c5-5411624893ce')
  Owner: tenantResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
  Reader: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  'Role Based Access Control Administrator (Preview)': tenantResourceId('Microsoft.Authorization/roleDefinitions', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')
  'User Access Administrator': tenantResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
}

module roleAssignmentVm2 'roleAssignment.bicep' = {
  name: guid(prefix,'vm1','Disk Snapshot Contributor')
  params: {
    roleDefinitionId: builtInRoleNames['Disk Snapshot Contributor']
    principalId: infra2.outputs.vmPrincipalId
    prefix: prefix
    postfix: '2'
  }
  scope: resourceGroup(hubSubscriptionId, prefix)
  dependsOn: [
    infra2
  ]
}

module roleAssignmentVm3 'roleAssignment.bicep' = {
  name: guid(prefix,'vm3','Disk Snapshot Contributor')
  params: {
    roleDefinitionId: builtInRoleNames['Disk Snapshot Contributor']
    principalId: infra3.outputs.vmPrincipalId
    prefix: prefix
    postfix: '3'
  }
  scope: resourceGroup(hubSubscriptionId, prefix)
  dependsOn: [
    infra3
  ]
}
