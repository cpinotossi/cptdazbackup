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
  subnet1Firewall: '10.1.2.0/24'
  subnet1FirewallManagement: '10.1.3.0/24'
  subnet2_1: '10.2.0.0/24'
  subnet2_2: '10.2.1.0/24'
  vm1: '10.1.0.4'
  vm2: '10.2.0.4'
  vm3: '10.2.1.4'
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
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: IPAM.subnet1Firewall
        }
      }
      {
        name: 'AzureFirewallManagementSubnet'
        properties: {
          addressPrefix: IPAM.subnet1FirewallManagement
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
          addressPrefix: IPAM.subnet2_1
          networkSecurityGroup: {
            id: sourceVnetNsg.id
          }
        }
      }
      {
        name: '${prefix}3'
        properties: {
          addressPrefix: IPAM.subnet2_2
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
            id: resourceId(prefix, 'Microsoft.Network/virtualNetworks/subnets', '${prefix}1', 'AzureBastionSubnet')
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

module vm3 'vm.bicep' = {
  name: '${prefix}3'
  params: {
    location: location
    vmName: '${prefix}3'
    adminUsername: adminUsername
    adminPassword: adminPassword
    vnetName: '${prefix}2'
    subnetName: '${prefix}3'
    imageReference: imageReference
    userObjectId: currentUserObjectId
    privateip: IPAM.vm3
  }
}


// peering between vnet1 and vnet2
// https://learn.microsoft.com/en-us/azure/templates/microsoft.network/virtualnetworkpeerings?pivots=deployment-language-bicep
@description('Peering between vnet1 and vnet2')
resource vnet1ToVnet2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-05-01' = {
  name: '${prefix}1To${prefix}2'
  parent: vnet1
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet2.id
    }
  }
}

resource vnet2ToVnet1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-05-01' = {
  name: '${prefix}2To${prefix}1'
  parent: vnet2
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet1.id
    }
  }
}

// https://learn.microsoft.com/en-us/azure/templates/microsoft.network/publicipaddresses?pivots=deployment-language-bicep
@description('Source Bastion Public IP')
resource firewallIp 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${prefix}firewall'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource firewallManagementIp 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${prefix}firewallManagement'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}
// Azure firewall basic
// https://learn.microsoft.com/en-us/azure/templates/microsoft.network/azurefirewalls?pivots=deployment-language-bicep
@description('Azure Firewall')
resource firewall 'Microsoft.Network/azureFirewalls@2022-05-01' = {
  name: prefix
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'AzureFirewallIpConfiguration'
        properties: {
          subnet: {
            id: resourceId(prefix, 'Microsoft.Network/virtualNetworks/subnets', '${prefix}1', 'AzureFirewallSubnet')
          }
          publicIPAddress: {
            id: firewallIp.id
          }
        }
      }
    ]
    managementIpConfiguration: {
      name:'${prefix}firewall'
      properties:{
        subnet: {
          id: resourceId(prefix, 'Microsoft.Network/virtualNetworks/subnets', '${prefix}1', 'AzureFirewallManagementSubnet')
        }
        publicIPAddress: {
          id: firewallManagementIp.id
        }
      }
    }
    threatIntelMode: 'Alert'
    sku: {
      name: 'AZFW_VNet'
      tier:'Basic'
    }
  }
}


