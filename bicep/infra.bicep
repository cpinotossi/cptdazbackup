targetScope = 'resourceGroup'

@description('Object ID of the current user')
// https://github.com/Azure/bicep/discussions/9969
// "There's no function to get the principal ID of the user executing the deployment (though it is planned)."
param currentUserObjectId string

// Module Paramaters
@description('Location to deploy all resources')
param location string = resourceGroup().location

@description('Prefix used in the Naming for multiple Deployments in the same Subscription')
param prefix string

@description('Admin user variable')
param adminUsername string ='chpinoto'

@secure()
@description('Admin password variable')
param adminPassword string = 'demo!pass123'

// Add image reference for azure ubuntu vm

var imageReference = {
  publisher: 'Canonical'
  offer: 'UbuntuServer'
  sku: '18.04-LTS'
  version: 'latest'
}

var IPAM = {
  vnet1: '10.1.0.0/16'
  vnet2: '10.2.0.0/16'
  subnet1: '10.1.0.0/24'
  subnet1Bastion: '10.1.1.0/24'
  subnet2: '10.2.0.0/24'
  vm1: '10.1.0.4'
  vm2: '10.2.0.4'
}




// https://learn.microsoft.com/en-us/azure/templates/microsoft.network/networksecuritygroups?pivots=deployment-language-bicep
@description('Network security group in source network')
resource sourceVnetNsg 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: prefix
  location: location
  properties: {
    securityRules: [
      {
        name: 'ssh'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '22'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '10.1.0.4'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// https://learn.microsoft.com/en-us/azure/templates/Microsoft.Network/virtualNetworks?pivots=deployment-language-bicep
@description('Virtual network for the source resources')
resource vnet1 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: '${prefix}1'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        IPAM.vnet1
      ]
    }
    subnets: [
      {
        name: '${prefix}1'
        properties: {
          addressPrefix: IPAM.subnet1
          networkSecurityGroup: {
            id: sourceVnetNsg.id
          }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: IPAM.subnet1Bastion
        }
      }
    ]
  }
}

resource vnet2 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: '${prefix}2'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        IPAM.vnet2
      ]
    }
    subnets: [
      {
        name: '${prefix}2'
        properties: {
          addressPrefix: IPAM.subnet2
          networkSecurityGroup: {
            id: sourceVnetNsg.id
          }
        }
      }
    ]
  }
}

// https://learn.microsoft.com/en-us/azure/templates/microsoft.network/publicipaddresses?pivots=deployment-language-bicep
@description('Source Bastion Public IP')
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

// https://learn.microsoft.com/en-us/azure/templates/microsoft.network/bastionhosts?pivots=deployment-language-bicep
@description('Source Network Bastion to access the source Servers')
resource bastion 'Microsoft.Network/bastionHosts@2023-05-01' = {
  name: prefix
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: '${prefix}bastion'
        properties: {
          publicIPAddress: {
            id: bastionIp.id
          }
          subnet: {
            id: vnet1.properties.subnets[1].id
          }
        }
      }
    ]

  }
}

module vm1 'vm.bicep' = {
  name: '${prefix}1'
  params: {
    location: location
    vmName: '${prefix}1'
    adminUsername: adminUsername
    adminPassword: adminPassword
    vnetName: '${prefix}1'
    subnetName: '${prefix}1'
    imageReference: imageReference
    userObjectId: currentUserObjectId
    privateip: IPAM.vm1
  }
}

module vm2 'vm.bicep' = {
  name: '${prefix}2'
  params: {
    location: location
    vmName: '${prefix}2'
    adminUsername: adminUsername
    adminPassword: adminPassword
    vnetName: '${prefix}2'
    subnetName: '${prefix}2'
    imageReference: imageReference
    userObjectId: currentUserObjectId
    privateip: IPAM.vm2
  }
}
