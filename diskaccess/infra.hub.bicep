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
          addressPrefix: IPAM['subnet${postfix}']
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: IPAM['subnet${postfix}Bastion']
        }
      }
    ]
  }
}

resource bastionIp 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${prefix}bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-05-01' = {
  name: prefix
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    enableIpConnect: true
    ipConfigurations: [
      {
        name: '${prefix}bastion'
        properties: {
          publicIPAddress: {
            id: bastionIp.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', '${prefix}${postfix}', 'AzureBastionSubnet')
          }
        }
      }
    ]
  }
}

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
// COMPUTE
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++

module vm 'vm.dao.bicep' = {
  name: '${prefix}${postfix}'
  params: {
    location: location
    vmName: '${prefix}${postfix}'
    vnetName: '${prefix}${postfix}'
    subnetName: '${prefix}${postfix}'
    userObjectId: currentUserObjectId
    privateip: IPAM['vm${postfix}']
    diskAccessName: prefix
    identityName: identity.name
  }
}

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++
// DISK
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++

resource diskAccesses 'Microsoft.Compute/diskAccesses@2023-01-02' = {
  name: prefix
  location: location
  properties: {}
}

resource pdns 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

// resource pdnsLink1 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
//   parent: pdns
//   name: '${prefix}1'
//   location: 'global'
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: resourceId('Microsoft.Network/virtualNetworks', '${prefix}1')
//     }
//   }
// }

// resource pdnsLink2 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
//   parent: pdns
//   name: '${prefix}2'
//   location: 'global'
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: resourceId('Microsoft.Network/virtualNetworks', '${prefix}2')
//     }
//   }
// }

resource peDisk 'Microsoft.Network/privateEndpoints@2023-06-01' = {
  name: prefix
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: prefix
        properties: {
          privateLinkServiceId: diskAccesses.id
          groupIds: [
            'disks'
          ]
        }
      }
    ]
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', '${prefix}${postfix}', '${prefix}${postfix}')
    }
  }
}

resource peDNSZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-06-01' = {
  name: prefix
  parent: peDisk
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'disks'
        properties: {
          privateDnsZoneId: pdns.id
        }
      }
    ]
  }
}

// resource diskAccessesPEConnection 'Microsoft.Compute/diskAccesses/privateEndpointConnections@2023-01-02' = {
//   parent: diskAccesses
//   name: prefix
// }


// resource disk2snapshot 'Microsoft.Compute/snapshots@2023-01-02' = {
//   name: '${prefix}2snapshot'
//   location: location
//   sku: {
//     name: 'Standard_ZRS'
//   }
//   properties: {
//     osType: 'Linux'
//     hyperVGeneration: 'V1'
//     supportedCapabilities: {
//       diskControllerTypes: 'SCSI, NVMe'
//       acceleratedNetwork: true
//       architecture: 'x64'
//     }
//     creationData: {
//       createOption: 'Copy'
//       sourceResourceId: resourceId('Microsoft.Compute/disks', '${prefix}2')
//     }
//     diskSizeGB: 30
//     encryption: {
//       type: 'EncryptionAtRestWithPlatformKey'
//     }
//     incremental: true
//     networkAccessPolicy: 'AllowAll'
//     publicNetworkAccess: 'Enabled'
//     diskAccessId: diskAccesses.id
//   }
// }

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${prefix}${postfix}'
  location: location
}

resource raMID2VMContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id,identity.id,'Virtual Machine Contributor')
  properties: {
    roleDefinitionId: builtInRoleNames['Virtual Machine Contributor']
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
   }
  scope: resourceGroup()
}

resource raMID2Reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id,identity.id,'Reader')
  properties: {
    roleDefinitionId: builtInRoleNames['Reader']
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
   }
  scope: resourceGroup()
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
  'Virtual Machine Contributor': tenantResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')
}

output vnetId string = vnet.id
output vmId string = vm.outputs.vmId
output pDnsId string = pdns.id


