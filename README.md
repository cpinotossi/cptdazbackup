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

The networkAccessPolicy and publicNetworkAccess properties of an Azure Disk control how the disk can be accessed over the network.

networkAccessPolicy: This property can have one of three values:
 1. AllowAll: The disk can be accessed from all networks.
 2. DenyAll: The disk cannot be accessed from any network.
 3. AllowPrivate: The disk can only be accessed from a specific subnet in a virtual network. This is achieved by associating the disk with a DiskAccess resource that is linked to the subnet.

(source: https://learn.microsoft.com/en-us/rest/api/compute/disks/create-or-update?view=rest-compute-2023-04-02&tabs=HTTP#networkaccesspolicy)

publicNetworkAccess: This property can have one of two values:
 1. Enabled: The disk can be accessed from the public internet.
 2. Disabled: The disk cannot be accessed from the public internet.

We will run through several SAS Copy cases which tries to cover all possible variations of how to configure snapshot network access policy in a table

| Case | Source | Destination | networkAccessPolicy | publicNetworkAccess |Disk Access Resource | Private Endpoint | HTTP Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | vm2Snap1Id | local PC | AllowAll | Enabled | none | none | 200 |
| 2 | vm2Snap2Id | vm2Snap2IdWEU | AllowPrivate | Enabled | vm2DiskAccess1Id | vm2pe1Id | OK |
| 3 | vm2Snap2Id | local PC | AllowPrivate | Enabled | vm2DiskAccess1Id | vm2pe1Id | 403 |
| 4 | vm2Snap2Id | vm2 | AllowPrivate | Enabled | vm2DiskAccess1Id | vm2pe1Id | 200 |
| 5 | vm2Snap2Id | vm1 | AllowPrivate | Enabled | vm2DiskAccess1Id | vm2pe1Id | 403 |
| 6 | vm2Snap3Id | local PC | AllowAll | Disable | none | none | NOK |
| 7 | vm2Snap3Id | vm2Snap3IdWEU | AllowAll | Disable | none | none | OK |
| 8 | vm2Snap3Id | vm1 | AllowAll | Disable | none | none | NOK |
| 9 | vm2Snap3Id | vm2 | AllowAll | Disable | none | none | 409 Access not permitted|
| 10 | vm2Disk2_1Id | local PC | AllowAll | Enabled | none | none | 200 |
| 11 | vm2Disk2_2Id | local PC | AllowAll | Disable | none | none | 409 Access not permitted |
| 12 | vm2Disk2_2Id | vm2 | AllowAll | Disable | none | none | 409 Access not permitted |
| 13 | vm2DiskId | vm2 | AllowPrivate | Enabled | vm2DiskAccess1Id | vm2pe1Id | 409 attached |
| 14 | vm2Disk2_3Id | vm2 | AllowPrivate | Disable | vm2DiskAccess1Id | vm2pe1Id | 200 |
| 15 | vm2Disk2_3Id | vm1 | AllowPrivate | Disable | vm2DiskAccess1Id | vm2pe1Id | 200 | 
| 16 | vm2Disk2_3Id | vm3 | AllowPrivate | Disable | vm2DiskAccess1Id | vm2pe1Id | 403 |


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



### Case#1 snapshot is not secured

~~~bash 
# get the disc ID
# az account set --subscription "sub-myedge-01"
vm2DiskId=$(az vm show -g $prefix --name ${prefix}2 --query "storageProfile.osDisk.managedDisk.id" -o tsv)
# Create the snapshot
az snapshot create -g $prefix -n ${prefix}vm2snap1 --source $vm2DiskId --incremental true --sku Standard_ZRS
# Show the snapshot
vm2Snap1Id=$(az snapshot show -g $prefix -n ${prefix}vm2snap1 --query id -o tsv)
# show disk access details
az snapshot show --ids $vm2Snap1Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
# Get the disk ID
az snapshot show -g $prefix -n ${prefix}vm2snap1 --query creationData.sourceResourceId
# copy the snapshot to a different region
az snapshot create -g $prefix -n ${prefix}vm2snap1WEU -l westeurope --source $vm2Snap1Id --incremental --copy-start
# Export/Copy a snapshot to a storage account in different region with CLI
vm2Snap1SASUrl=$(az snapshot grant-access --ids $vm2Snap1Id --duration-in-seconds 3600 --query accessSas -o tsv)
curl -o /dev/null -s -w "%{http_code}\n" -I $vm2Snap1SASUrl # should return 200
~~~

### Cse#2 Secure the snapshot with private link.
Based on https://learn.microsoft.com/en-us/azure/virtual-machines/linux/disks-export-import-private-links-cli

~~~bash
# create disk access resource
az disk-access create -n ${prefix}vm2diskaccess1 -g $prefix -l $location
vm2DiskAccess1=$(az disk-access show -n ${prefix}vm2diskaccess1 -g $prefix --query id -o tsv)
# Azure deploys resources to a subnet within a virtual network, so you need to update the subnet to disable private endpoint network policies.
az network vnet subnet show -g $prefix --name ${prefix}2 --vnet-name ${prefix}2 --query privateEndpointNetworkPolicies # should be "Disabled"
az network vnet subnet update -g $prefix --name ${prefix}2 --vnet-name ${prefix}2 --disable-private-endpoint-network-policies true # This command is not really needed if the subnet is setup with default values.
az network vnet subnet show -g $prefix --name ${prefix}2 --vnet-name ${prefix}2 --query privateEndpointNetworkPolicies # should be "Disabled"

# Create a private endpoint for the disk access object
az network private-endpoint create -g $prefix --name ${prefix}vm2pe1 --vnet-name ${prefix}2 --subnet ${prefix}2 --private-connection-resource-id $vm2DiskAccess1 --group-ids disks --connection-name ${prefix}vm2pecon1
vm2pe1Id=$(az network private-endpoint show -g $prefix --name ${prefix}vm2pe1 --query id -o tsv)
# Create a private DNS zone for the disk access object
az network private-dns zone create -g $prefix --name "privatelink.blob.core.windows.net"
az network private-dns link vnet create -g $prefix --zone-name "privatelink.blob.core.windows.net" --name ${prefix}2dnslink1 --virtual-network ${prefix}2 --registration-enabled false
az network private-endpoint dns-zone-group create -g $prefix --endpoint-name ${prefix}vm2pe1 --name ${prefix}2 --private-dns-zone "privatelink.blob.core.windows.net" --zone-name disks

# Assign the Disk Access resource to the disk
az disk update --ids $vm2DiskId --network-access-policy AllowPrivate --disk-access $vm2DiskAccess1

# Create again a snaphot
az snapshot update -h -g $prefix -n ${prefix}vm2snap2 --source $vm2DiskId --incremental true --sku Standard_ZRS #works

# retrieve the snapshot ID
vm2Snap2Id=$(az snapshot show -g $prefix -n ${prefix}vm2snap2 --query id -o tsv)
# Change the network access policy to allow private access only
az snapshot update --ids $vm2Snap2Id --network-access-policy AllowPrivate
az snapshot show --ids $vm2Snap2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
# Export/Copy a snapshot to a storage account in different region with CLI
vm2Snap2SASUrl=$(az snapshot grant-access --ids $vm2Snap2Id --duration-in-seconds 3600 --query accessSas -o tsv)
echo $vm2Snap2SASUrl
curl -o /dev/null -s -w "%{http_code}\n" -I $vm2Snap2SASUrl # should return 403
~~~

### Cse#3 Copy the snapshot to a different region.
NOTE: We will still be able to copy the snapshot from one region to another.

~~~bash
# We will need to create a new disk access resource in the target region as this is a hard requirement for the copy operation.
az disk-access create -n ${prefix}vm2diskaccess1WEU -g $prefix -l westeurope
vm2DiskAccess1IdWEU=$(az disk-access show -n ${prefix}vm2diskaccess1WEU -g $prefix --query id -o tsv)
# copy the snapshot to a different region
az snapshot create -g $prefix -n ${prefix}vm2snap2_2WEU -l westeurope --source $vm2Snap2Id --incremental --copy-start --disk-access $vm2DiskAccess1IdWEU # works
~~~

### Cse#4 Secure the snapshot with private link and access from inside same vnet and subnet

~~~bash
# login to the VM
vm2Id=$(az vm show -g $prefix -n ${prefix}2 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm2Id --auth-type AAD

# install azure cli
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-get update
sudo apt-get install azure-cli -y
az login --use-device-code

# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
# retrieve the disk access resource id
vm2Snap2Id=$(az snapshot show -g $prefix -n ${prefix}vm2snap2 --query id -o tsv)
# Change the network access policy to allow private access only
az snapshot show --ids $vm2Snap2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'

# Export/Copy a snapshot to a storage account in different region with CLI
vm2Snap2SASUrl=$(az snapshot grant-access --ids $vm2Snap2Id --duration-in-seconds 3600 --query accessSas -o tsv)
curl -o /dev/null -s -w "%{http_code}\n" -I $vm2Snap2SASUrl # expect 200 OK
logout
~~~

### Case#5 Secure the snapshot with private link and access from different vnet and subnet

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
az login --use-device-code # note we should use --indentity to use the VM identity instead of the user identity

# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
# retrieve the disk access resource id
vm2Snap2Id=$(az snapshot show -g $prefix -n ${prefix}vm2snap2 --query id -o tsv)
# Change the network access policy to allow private access only
az snapshot show --ids $vm2Snap2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'

# Export/Copy a snapshot to a storage account in different region with CLI
vm2Snap2SASUrl=$(az snapshot grant-access --ids $vm2Snap2Id --duration-in-seconds 3600 --query accessSas -o tsv)
curl -o /dev/null -s -w "%{http_code}\n" -I $vm2Snap2SASUrl # expect 403 OK
logout
~~~

### Case#6 snapshot public access is disabled

~~~bash 
# get the disc ID
vm2DiskId=$(az vm show -g $prefix --name ${prefix}2 --query "storageProfile.osDisk.managedDisk.id" -o tsv)
# Create the snapshot
vm2Snap3Id=$(az snapshot create -g $prefix -n ${prefix}vm2snap3 --source $vm2DiskId --incremental true --sku Standard_ZRS --query id -o tsv --network-access-policy AllowAll --public-network-access Disabled)
# show disk access details
az snapshot show --ids $vm2Snap3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
# copy the snapshot to a different region
az snapshot create -g $prefix -n ${prefix}vm2snap3WEU -l westeurope --source $vm2Snap3Id --incremental --copy-start # works
# Export/Copy a snapshot to a storage account in different region with CLI
vm2Snap3SASUrl=$(az snapshot grant-access --ids $vm2Snap3Id --duration-in-seconds 3600 --query accessSas -o tsv) # ERROR: (PublicNetworkAccessDisabled) Access not permitted for resource
~~~

### Case#7 snapshot public access is disabled, export to storage account in different region

~~~bash 
# copy the snapshot to a different region
az snapshot create -g $prefix -n ${prefix}vm2snap3WEU -l westeurope --source $vm2Snap3Id --incremental --copy-start # works
~~~

### Case#8 snapshot public access is disabled, access from different vnet and subnet

~~~bash
# login to the VM
vm1Id=$(az vm show -g $prefix -n ${prefix}1 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm1Id --auth-type AAD

az login --identity # note we should use --indentity to use the VM identity instead of the user identity

# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
# retrieve the disk access resource id
vm2Snap3Id=$(az snapshot show -g $prefix -n ${prefix}vm2snap3 --query id -o tsv)
# Change the network access policy to allow private access only
az snapshot show --ids $vm2Snap3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'

# Export/Copy a snapshot to a storage account in different region with CLI
az snapshot grant-access --ids $vm2Snap3Id --duration-in-seconds 3600 --debug
vm2Snap3SASUrl=$(az snapshot grant-access --ids $vm2Snap3Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 409 (PublicNetworkAccessDisabled) Access not permitted for resource
logout
~~~

### Case#9 snapshot public access is disabled, access from same vnet and subnet

~~~bash
# login to the VM
vm2Id=$(az vm show -g $prefix -n ${prefix}2 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm2Id --auth-type AAD
az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
# retrieve the disk access resource id
vm2Snap3Id=$(az snapshot show -g $prefix -n ${prefix}vm2snap3 --query id -o tsv)
# Change the network access policy to allow private access only
az snapshot show --ids $vm2Snap3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
# Export/Copy a snapshot to a storage account in different region with CLI
az snapshot grant-access --ids $vm2Snap3Id --duration-in-seconds 3600 --debug
vm2Snap3SASUrl=$(az snapshot grant-access --ids $vm2Snap3Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 409 (PublicNetworkAccessDisabled) Access not permitted for resource
logout
~~~

### Case#10 disc public access is enabled access from local PC

~~~bash
# Create new disk
az disk create -g $prefix -n ${prefix}2_1 --size-gb 1 --sku Standard_LRS --query id -o tsv
# Get Disk ID
disk2_1Id=$(az disk show -g $prefix -n ${prefix}2_1 --query id -o tsv)
az disk show --ids $disk2_2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
disk2_1SASUrl=$(az disk grant-access --ids $disk2_1Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 409 (PublicNetworkAccessDisabled) Access not permitted for resource
~~~

### Case#11 disc public access is disabled access from local PC

~~~bash
# Create new disk
disk2_2Id=$(az disk create -g $prefix -n ${prefix}2_2 --size-gb 1 --sku Standard_LRS --query id -o tsv --network-access-policy AllowAll --public-network-access Disabled)
az disk show --ids $disk2_2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
disk2_2SASUrl=$(az disk grant-access --ids $disk2_2Id --duration-in-seconds 3600 --query accessSas -o tsv) 
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2_2SASUrl # HTTP 409 (PublicNetworkAccessDisabled) Access not permitted for resource
echo $disk2_2SASUrl
~~~

### Case#12 disc public access is disabled access from VM2

~~~bash
vm2Id=$(az vm show -g $prefix -n ${prefix}2 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm2Id --auth-type AAD
az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
disk2_2Id=$(az disk show -n ${prefix}2_2 -g $prefix --query id -o tsv)
az disk show --ids $disk2_2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
disk2_2SASUrl=$(az disk grant-access --ids $disk2_2Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 409 (PublicNetworkAccessDisabled) Access not permitted for resource
logout
~~~

### Case#13 disc public access is disabled access from VM2

~~~bash
vm2Id=$(az vm show -g $prefix -n ${prefix}2 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm2Id --auth-type AAD
az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
disk2Id=$(az disk show -g $prefix -n ${prefix}2 --query id -o tsv)
az disk show --ids $disk2Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
az disk grant-access --ids $disk2Id --duration-in-seconds 3600 --query accessSas -o tsv --debug
disk2SASUrl=$(az disk grant-access --ids $disk2Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 409 disk currently attached to running VM
logout
~~~

### Case#14 disc public access is disabled access from VM2

~~~bash
# Create new disk with disk access resource
vm2DiskAccess1Id=$(az disk-access show -n ${prefix}vm2diskaccess1 -g $prefix --query id -o tsv)
az disk create -g $prefix -n ${prefix}2_3 --size-gb 1 --sku Standard_LRS --network-access-policy AllowPrivate --public-network-access Disabled --disk-access $vm2DiskAccess1Id
# log into the VM2
vm2Id=$(az vm show -g $prefix -n ${prefix}2 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm2Id --auth-type AAD
az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
disk2_3Id=$(az disk show -g $prefix -n ${prefix}2_3 --query id -o tsv)
az disk show --ids $disk2_3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
az disk grant-access --ids $disk2_3Id --duration-in-seconds 3600 --query accessSas -o tsv --debug
disk2_3SASUrl=$(az disk grant-access --ids $disk2_3Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2_3SASUrl # HTTP 409 (PublicNetworkAccessDisabled) Access not permitted for resource
echo $disk2_3SASUrl
logout
~~~

DNS Lookup of SAS URL
~~~bash
dig md-impexp-qt0gwj0r2bck.z50.blob.storage.azure.net
md-impexp-qt0gwj0r2bck.z50.blob.storage.azure.net. 40 IN CNAME md-impexp-qt0gwj0r2bck.privatelink.blob.core.windows.net.
md-impexp-qt0gwj0r2bck.privatelink.blob.core.windows.net. 10 IN A 10.2.0.5
~~~

### Case#15 disc public access is disabled access from VM1

~~~bash
# log into the VM1
vm1Id=$(az vm show -g $prefix -n ${prefix}1 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm1Id --auth-type AAD
az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
disk2_3Id=$(az disk show -g $prefix -n ${prefix}2_3 --query id -o tsv)
az disk show --ids $disk2_3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
disk2_3SASUrl=$(az disk grant-access --ids $disk2_3Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2_3SASUrl # HTTP 200
echo $disk2_3SASUrl
dig md-impexp-qt0gwj0r2bck.z50.blob.storage.azure.net # public IP
logout
~~~

### Case#15.1 disc public access is disabled access from VM1 via PE

~~~bash
# Assign pdns to vnet1
az network private-dns link vnet create -g $prefix --zone-name "privatelink.blob.core.windows.net" --name ${prefix}1dnslink1 --virtual-network ${prefix}1 --registration-enabled false
# log into the VM1
vm1Id=$(az vm show -g $prefix -n ${prefix}1 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm1Id --auth-type AAD
az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
disk2_3Id=$(az disk show -g $prefix -n ${prefix}2_3 --query id -o tsv)
az disk show --ids $disk2_3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
disk2_3SASUrl=$(az disk grant-access --ids $disk2_3Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2_3SASUrl # HTTP 200
echo $disk2_3SASUrl
dig md-impexp-qt0gwj0r2bck.z50.blob.storage.azure.net # private IP 10.2.0.5
logout
~~~

### Case#16 disc public access is disabled, networkAccessPolicy   access from VM1 via PE

~~~bash
az disk create --network-access-policy ??
# Assign pdns to vnet1
az network private-dns link vnet create -g $prefix --zone-name "privatelink.blob.core.windows.net" --name ${prefix}1dnslink1 --virtual-network ${prefix}1 --registration-enabled false
# log into the VM1
vm1Id=$(az vm show -g $prefix -n ${prefix}1 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm1Id --auth-type AAD

# install azure cli
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-get update
sudo apt-get install azure-cli -y

az login --identity # use the VM identity instead of the user identity
# inside the vm we need to setup the environment varaibles again.
prefix=cptdazdisk
disk2_3Id=$(az disk show -g $prefix -n ${prefix}2_3 --query id -o tsv)
az disk show --ids $disk2_3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
disk2_3SASUrl=$(az disk grant-access --ids $disk2_3Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2_3SASUrl # HTTP 200
echo $disk2_3SASUrl
dig md-impexp-qt0gwj0r2bck.z50.blob.storage.azure.net # private IP 10.2.0.5
logout
~~~

### Case#17 disc public access is disabled, networkAccessPolicy  access from VM3 via PE from different subscription

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
disk2_3Id=$(az disk show -g $prefix -n ${prefix}2_3 --query id -o tsv)
az disk show --ids $disk2_3Id --query '{publicNetworkAccess:publicNetworkAccess, networkAccessPolicy:networkAccessPolicy, diskAccessId:diskAccessId}'
disk2_3SASUrl=$(az disk grant-access --ids $disk2_3Id --duration-in-seconds 3600 --query accessSas -o tsv) # HTTP 200 running VM
curl -o /dev/null -s -w "%{http_code}\n" -I $disk2_3SASUrl # HTTP 200
echo $disk2_3SASUrl
dig md-impexp-qt0gwj0r2bck.z50.blob.storage.azure.net # private IP 10.2.0.5
logout
~~~



###

~~~bash
# Calculate the disk size
vm2DiskSizeSnapShot=$(az snapshot show -g $prefix -n ${prefix}vm2snap1 --query diskSizeGB -o tsv)
diskSize=$(expr $vm2DiskSizeSnapShot + 2)
echo $diskSize
#Provide the OS type
osType=linux

#Create a new Managed Disks using the snapshot Id
az disk create -g $prefix --name ${prefix}1 --sku Standard_LRS --size-gb $diskSize --source $snapId

#Create VM by attaching created managed disks as OS
az vm create --name ${prefix}1 -g $prefix --attach-os-disk ${prefix}1 --os-type linux --vnet-name $prefix --subnet default 

# Grant read access to the disk
sas=$(az disk grant-access -n MyDisk -g MyResourceGroup --access-level Read --duration-in-seconds 3600 --query [accessSas] -o tsv)

# Copy the disk to a storage account as a VHD
az storage blob copy start --destination-blob MyVHD.vhd --destination-container vhds --account-name mystorageaccount --source-uri $sas
~~~


~~~bash
# Create an disk access resource
az disk-access create -n ${prefix}1 -g $prefix -l $location
diskAccessId=$(az disk-access show -n ${prefix}1 -g $prefix --query id -o tsv)


# Get VM Id
vm1Id=$(az vm show -g $prefix -n ${prefix}1 --query id -o tsv)
vm2Id=$(az vm show -g $prefix -n ${prefix}2 --query id -o tsv)
az network bastion ssh -n $prefix -g $prefix --target-resource-id $vm1Id --auth-type AAD
~~~





## Misc

## Git

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