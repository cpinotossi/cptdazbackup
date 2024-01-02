targetScope = 'resourceGroup'

@description('Object ID of the current user')
param currentUserObjectId string

// Module Paramaters
@description('Location to deploy all resources')
param location string = resourceGroup().location

@description('Prefix used in the Naming for multiple Deployments in the same Subscription')
param prefix string
param postfix string
param IPAM object

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
// NETWORK
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: '${prefix}${postfix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        IPAM['vnet${postfix}']
      ]
    }
    subnets: [
      {
        name: '${prefix}${postfix}'
        properties: {
          privateEndpointNetworkPolicies: 'Disabled'
          addressPrefix: IPAM['subnet${postfix}']
        }
      }
    ]
  }
}


// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
// COMPUTE
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++

module vm 'vm.bicep' = {
  name: '${prefix}${postfix}'
  params: {
    location: location
    vmName: '${prefix}${postfix}'
    vnetName: '${prefix}${postfix}'
    subnetName: '${prefix}${postfix}'
    userObjectId: currentUserObjectId
    privateip: IPAM['vm${postfix}']
    // customData: loadTextContent('vm.azcli.yaml')
    // diskAccessName: prefix
    // identityName: identity.name
  }
}

// resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
//   name: '${prefix}${postfix}'
//   location: location
// }

// resource raMID2VMContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(resourceGroup().id,identity.id,'Virtual Machine Contributor')
//   properties: {
//     roleDefinitionId: builtInRoleNames['Virtual Machine Contributor']
//     principalId: identity.properties.principalId
//     principalType: 'ServicePrincipal'
//    }
//   scope: resourceGroup()
// }

// resource raMID2Reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(resourceGroup().id,identity.id,'Reader')
//   properties: {
//     roleDefinitionId: builtInRoleNames['Reader']
//     principalId: identity.properties.principalId
//     principalType: 'ServicePrincipal'
//    }
//   scope: resourceGroup()
// }

// var builtInRoleNames = {
//   Contributor: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
//   'Data Operator for Managed Disks': tenantResourceId('Microsoft.Authorization/roleDefinitions', '959f8984-c045-4866-89c7-12bf9737be2e')
//   'Disk Backup Reader': tenantResourceId('Microsoft.Authorization/roleDefinitions', '3e5e47e6-65f7-47ef-90b5-e5dd4d455f24')
//   'Disk Pool Operator': tenantResourceId('Microsoft.Authorization/roleDefinitions', '60fc6e62-5479-42d4-8bf4-67625fcc2840')
//   'Disk Restore Operator': tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b50d9833-a0cb-478e-945f-707fcc997c13')
//   'Disk Snapshot Contributor': tenantResourceId('Microsoft.Authorization/roleDefinitions', '7efff54f-a5b4-42b5-a1c5-5411624893ce')
//   Owner: tenantResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
//   Reader: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
//   'Role Based Access Control Administrator (Preview)': tenantResourceId('Microsoft.Authorization/roleDefinitions', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')
//   'User Access Administrator': tenantResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
//   'Virtual Machine Contributor': tenantResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')
// }

output vnetId string = vnet.id
output vmId string = vm.outputs.vmId
output vmPrincipalId string = vm.outputs.vmPrincipalId
