targetScope='resourceGroup'

@description('Name of the Vault')
param prefix string

@description('Location for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

resource vault 'Microsoft.DataProtection/backupVaults@2023-01-01' = {
  name: prefix
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    storageSettings: [
      {
        datastoreType: 'VaultStore'
        type: 'LocallyRedundant'
      }
    ]
    securitySettings: {
      immutabilitySettings: {
        state: 'Locked'
      }
    }
  }
}

