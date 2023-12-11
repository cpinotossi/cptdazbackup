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



~~~bash
# Define prefix and suffix for all azure resources
prefix=cptdazdisk # replace sm with your own prefix
location=germanywestcentral
currentUserObjectId=$(az ad signed-in-user show --query id -o tsv)
adminPassword='demo!pass123!'
adminUsername='microhackadmin'
# Create Azure Resources with Azure Bicep Resource Templates and Azure CLI 
az group create -n $prefix -l $location
az deployment group create -g $prefix --template-file ./bicep/infra.bicep --parameters prefix=$prefix currentUserObjectId=$currentUserObjectId 
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