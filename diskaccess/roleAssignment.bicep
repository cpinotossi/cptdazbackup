param hubSubscriptionId string = '00000000-0000-0000-0000-000000000000'
param prefix string
param postfix string
param roleDefinitionId string
param principalId string

resource raVM2DiskSnapshot 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(prefix, postfix,'vm','Disk Snapshot Contributor')
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
  scope: resourceGroup()
}
