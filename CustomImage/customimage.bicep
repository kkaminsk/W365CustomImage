// Windows 365 Custom Image Infrastructure
// This Bicep template deploys Gen 2 VM for creating managed images

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Prefix for resource naming')
param resourcePrefix string = 'w365'

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'Windows 365 Custom Image'
  Environment: 'Production'
  ManagedBy: 'Bicep'
}

@description('VM administrator username')
param adminUsername string

@description('VM administrator password')
@secure()
param adminPassword string

@description('Build timestamp for unique naming')
param buildTimestamp string = utcNow('yyyyMMddHHmmss')

@description('Student number (1-40) for unique resource naming')
@minValue(1)
@maxValue(40)
param studentNumber int = 1

// Variables
var managedIdentityName = '${resourcePrefix}-imagebuilder-identity-student${studentNumber}'
var vnetName = 'w365-image-vnet-student${studentNumber}'
var subnetName = 'imagebuilder-subnet'
var nsgName = '${resourcePrefix}-nsg-student${studentNumber}'
var vmName = 'w365-build-vm-${buildTimestamp}'
var computerName = 'w365-${substring(buildTimestamp, 6, 8)}'  // Last 8 digits = w365-MMDDHHMMSS (14 chars)
var pipName = 'w365-build-pip-${buildTimestamp}'
var nicName = 'w365-build-nic-${buildTimestamp}'
var osDiskName = '${vmName}-osdisk'

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          description: 'Allow outbound to Azure Cloud services'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowInternetOutbound'
        properties: {
          description: 'Allow outbound internet for Windows Updates and downloads'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.100.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.100.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Role Assignment: Contributor on Resource Group
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}


// Public IP Address (temporary for build VM)
resource pip 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Network Interface Card
resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip.id
          }
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Build VM (Generation 2, Windows 11 25H2 Enterprise CPC)
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D4s_v3'
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-ent'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        diskSizeGB: 127
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        osType: 'Windows'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

// Outputs
output managedIdentityId string = managedIdentity.id
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId
output vmId string = vm.id
output vmName string = vm.name
output vmResourceId string = vm.id
output publicIPAddress string = pip.properties.ipAddress
output vnetId string = vnet.id
output vnetName string = vnet.name
output subnetId string = '${vnet.id}/subnets/${subnetName}'
output subnetName string = subnetName
output nsgId string = nsg.id
output resourceGroupName string = resourceGroup().name
output location string = location
