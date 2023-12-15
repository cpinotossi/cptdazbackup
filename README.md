# Azure Backup 

## immutability test

~~~bash
sudo hwclock -s
sudo ntpdate time.windows.com
prefix=cptdazbackup
location=germanywestcentral
az group create -n $prefix -l $location
az deployment group create -g $prefix -w -n $prefix -p prefix=$prefix location=$location -f vault.bicep
~~~


## azure disk & snapshot copy protection

> **Note:** Deployment has been done partly with bicep partly via the Azure portal. I will fix this in the future to be pure bicep.

usefull links:
- [how to get it done with bicep](https://stackoverflow.com/questions/68385774/how-to-set-os-disks-networking-to-allowprivate-private-endpoint-through-disk)
- [protect os disk issue](https://github.com/Azure/azure-rest-api-specs/issues/21325)

### Azure Disk & Snapshot Copy Protection
The networkAccessPolicy and publicNetworkAccess properties of an Azure Disk control how the disk can be accessed over the network.

networkAccessPolicy: This property can have one of three values:
 1. AllowAll: The disk can be accessed from all networks.
 2. DenyAll: The disk cannot be accessed from any network.
 3. AllowPrivate: The disk can only be accessed from a specific subnet in a virtual network. This is achieved by associating the disk with a DiskAccess resource that is linked to the subnet.

(source: https://learn.microsoft.com/en-us/rest/api/compute/disks/create-or-update?view=rest-compute-2023-04-02&tabs=HTTP#networkaccesspolicy)

publicNetworkAccess: This property can have one of two values:
 1. Enabled: The disk can be accessed from the public internet.
 2. Disabled: The disk cannot be accessed from the public internet.

### Test Cases
We will run through several SAS Copy cases which tries to cover all possible variations of how to configure snapshot network access policy in a table

Environment:
~~~mermaid
flowchart LR 
vnet1 <--Peering--> vnet2
vnet3 <--Peering--> vnet2
vnet1[vnet1
Sub#1
vm1 10.1.0.4]
vnet2[vnet2
Sub#1
vm2 10.2.0.4
disk2
PE 10.2.0.5
diskAccess]
vnet3[vnet3
Sub#2
vm3 10.3.0.4
]
~~~

| Case | Source | Subscription | Destination | networkAccessPolicy | publicNetworkAccess |Disk Access Resource | Private Endpoint | HTTP Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | vm2SnapId | sub1 | local PC | AllowPrivate | Disable | vm2DiskAccess1Id | vm2pe1Id | 403 |
| 2 | vm2SnapId | sub1 | vm1 | AllowPrivate | Disable | vm2DiskAccess1Id | vm2pe1Id | 200 |
| 3 | vm2SnapId | sub2 | vm3 | AllowPrivate | Disable | vm2DiskAccess1Id | vm2pe1Id | 200 |

### Create Azure Resources with Azure Bicep Resource Templates and Azure CLI
~~~bash
# Define prefix and suffix for all azure resources
prefix=cptdazdisk # replace sm with your own prefix
location=germanywestcentral
currentUserObjectId=$(az ad signed-in-user show --query id -o tsv)
adminPassword='demo!pass123!'
adminUsername='chpinoto'
# Create Azure Resources with Azure Bicep Resource Templates and Azure CLI 
az group create -n $prefix -l $location
az deployment group create -g $prefix --template-file ./bicep/infra.bicep --parameters prefix=$prefix currentUserObjectId=$currentUserObjectId 
~~~

### Create disk access resource and private endpoint

~~~bash
# Create a disk access resource which will be used to secure the snapshot by private link
az disk-access create -n ${prefix}vm2diskaccess1 -g $prefix -l $location
# Get the disk access resource id which will be used during the snapshot creation
diskAccess=$(az disk-access show -n ${prefix}vm2diskaccess1 -g $prefix --query id -o tsv)
# Create a private endpoint for the disk access object
az network private-endpoint create -g $prefix --name ${prefix}vm2pe1 --vnet-name ${prefix}2 --subnet ${prefix}2 --private-connection-resource-id $vm2DiskAccess1 --group-ids disks --connection-name ${prefix}vm2pecon1
vm2pe1Id=$(az network private-endpoint show -g $prefix --name ${prefix}vm2pe1 --query id -o tsv)
# Create a private DNS zone for the disk access object
az network private-dns zone create -g $prefix --name "privatelink.blob.core.windows.net"
# Assign pdns to vnet1
az network private-dns link vnet create -g $prefix --zone-name "privatelink.blob.core.windows.net" --name ${prefix}1dnslink1 --virtual-network ${prefix}1 --registration-enabled false
# Assign pdns to vnet2
az network private-dns link vnet create -g $prefix --zone-name "privatelink.blob.core.windows.net" --name ${prefix}2dnslink1 --virtual-network ${prefix}2 --registration-enabled false
# switch subscription
az account set --subscription "sub-myedge-01"
# Assign pdns to vnet3 in a different subscription
vnet3Id=$(az network vnet show -g $prefix -n ${prefix}3 --query id -o tsv)
# switch subscription
az account set --subscription "vse-sub"
az network private-dns link vnet create -g $prefix --zone-name "privatelink.blob.core.windows.net" --name ${prefix}3dnslink1 --virtual-network $vnet3Id --registration-enabled false
# Assing the private endpoint to the private DNS zone via an dns-zone-group
az network private-endpoint dns-zone-group create -g $prefix --endpoint-name ${prefix}vm2pe1 --name ${prefix}2 --private-dns-zone "privatelink.blob.core.windows.net" --zone-name disks
# list all vnets which are linked to the private DNS zone
az network private-dns link vnet list -g $prefix --zone-name "privatelink.blob.core.windows.net" --query "[].{name:name, virtualNetwork:virtualNetwork.id}" | sed 's|/subscriptions/.*/providers||g'
~~~

Output should look as follow:

~~~json
[
  {
    "name": "cptdazdisk1dnslink1",
    "virtualNetwork": "/Microsoft.Network/virtualNetworks/cptdazdisk1"
  },
  {
    "name": "cptdazdisk2dnslink1",
    "virtualNetwork": "/Microsoft.Network/virtualNetworks/cptdazdisk2"
  },
  {
    "name": "cptdazdisk3dnslink1",
    "virtualNetwork": "/Microsoft.Network/virtualNetworks/cptdazdisk3"
  }
]
~~~

### Create snapshot from disk2 with private link enabled

~~~bash
# Get the disk ID which will be used during the snapshot creation
disk2Id=$(az disk show -g $prefix -n ${prefix}2 --query id -o tsv)
# Lookup the disk access details
az disk show --ids $disk2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'| sed 's|/subscriptions/.*/providers||g'
~~~

Output should look as follow:

~~~json
{
  "diskAccessId": "/Microsoft.Compute/diskAccesses/cptdazdiskvm2diskaccess1",
  "networkAccessPolicy": "AllowPrivate",
  "publicNetworkAccess": "Disabled"
}
~~~

Create the snapshot from disk2 with private link enabled

~~~bash
# Create the snapshot
disk2SnapId=$(az snapshot create -g $prefix -n ${prefix}vm2snap --source $disk2Id --incremental true --sku Standard_ZRS --network-access-policy AllowPrivate --public-network-access Disabled --disk-access $diskAccess --query id -o tsv)
# Show the snapshot access details
az snapshot show --ids $disk2SnapId --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}' | sed 's|/subscriptions/.*/providers||g'
~~~

Output should look as follow:

~~~json
{
  "diskAccessId": "/Microsoft.Compute/diskAccesses/cptdazdiskvm2diskaccess1",
  "networkAccessPolicy": "AllowPrivate",
  "publicNetworkAccess": "Disabled"
}
~~~

### [CASE1] Download Snapshot from my local PC

~~~bash
disk2SnapSASUrlLocalPC=$(az snapshot grant-access --ids $disk2SnapId --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
# extract hostname from SAS URL
disk2SnapSASUrlLocalPCFQDN=$(echo $disk2SnapSASUrlLocalPC | sed 's|https://||g' | sed 's|/.*||g')
echo $disk2SnapSASUrlLocalPCFQDN
dig $disk2SnapSASUrlLocalPCFQDN # public IP
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2SnapSASUrlLocalPC # HTTP 403
~~~

### [CASE2] Download Snapshot from VM1 peered with VNET2 where the private link is deployed

~~~bash
# login to the VM
vm1Id=$(az vm show -g $prefix -n ${prefix}1 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm1Id --auth-type AAD

# install azure cli
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-get update
sudo apt-get install azure-cli -y

# login with managed identity of VM1
az login --identity

# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
# retrieve the disk access resource id
vm2SnapId=$(az snapshot show -g $prefix -n ${prefix}vm2snap --query id -o tsv)
# Verify snapshit access policy to allow private access only
az snapshot show --ids $vm2SnapId --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'| sed 's|/subscriptions/.*/providers||g'
~~~

Output should look as follow:
~~~json
{
  "diskAccessId": "/Microsoft.Compute/diskAccesses/cptdazdiskvm2diskaccess1",
  "networkAccessPolicy": "AllowPrivate",
  "publicNetworkAccess": "Disabled"
}
~~~

Download via SAS URL

~~~bash
disk2SnapSASUrlVM1=$(az snapshot grant-access --ids $vm2SnapId --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
# extract hostname from SAS URL
disk2SnapSASUrlVM1FQDN=$(echo $disk2SnapSASUrlVM1 | sed 's|https://||g' | sed 's|/.*||g')
echo $disk2SnapSASUrlVM1FQDN
dig $disk2SnapSASUrlVM1FQDN # private IP 10.2.0.5
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2SnapSASUrlVM1 # HTTP 200
logout
~~~

### [CASE3] Download Snapshot from VM3 (different Subscription) peered with VNET2 where the private link is deployed

~~~bash
# switch subscription
az account set --subscription "sub-myedge-01"
# log into the VM1
vm3Id=$(az vm show -g $prefix -n ${prefix}3 --query id -o tsv)
# switch subscription
az account set --subscription "vse-sub"
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm3Id --auth-type AAD
az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
# retrieve the disk access resource id
vm2SnapId=$(az snapshot show -g $prefix -n ${prefix}vm2snap --query id -o tsv)
disk2SnapSASUrlVM3=$(az snapshot grant-access --ids $vm2SnapId --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
# extract hostname from SAS URL
disk2SnapSASUrlVM3FQDN=$(echo $disk2SnapSASUrlVM3 | sed 's|https://||g' | sed 's|/.*||g')
echo $disk2SnapSASUrlVM3FQDN
dig $disk2SnapSASUrlVM3FQDN # private IP 10.2.0.5
ping 10.2.0.4
curl -v -I $disk2SnapSASUrlVM3 # HTTP 200
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2SnapSASUrlVM3 # HTTP 200
logout
~~~




## Misc

### Git

~~~bash

git init main
gh repo create cptdazbackup --public
git remote add origin https://github.com/cpinotossi/cptdazbackup.git
git status
git add .
git commit -m"init"
git push origin main

git tag //list local repo tags
git ls-remote --tags origin //list remote repo tags
git fetch --all --tags // get all remote tags into my local repo
git log --oneline --decorate // List commits
git log --pretty=oneline //list commits
git tag -a v2 b20e80a //tag my last commit

git checkout v1
git switch - //switch back to current version
co //Push all my local tags
git push origin <tagname> //Push a specific tag
git commit -m"not transient"
git tag v1
git push origin v1
git tag -l
git fetch --tags
git clone -b <git-tagname> <repository-url> 
~~~