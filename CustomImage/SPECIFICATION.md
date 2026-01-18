# Windows 365 Custom Image Automation - Application Specification

## Overview
Fully automated solution for creating Windows 365 custom images using Azure Managed Images (Gen 2). Deploys VM, customizes with Chocolatey, executes sysprep, and captures as managed image.

## Solution Components

### 1. Deploy-W365CustomImage.ps1
**Purpose**: Main orchestration script - fully automated end-to-end

**Features**:
- Automated Azure module installation and validation
- Azure authentication with subscription context management
- Resource provider registration
- Gen 2 VM deployment via Bicep
- VM customization via Azure Run Command
- Sysprep execution with Windows 365-compliant parameters
- Managed image capture (Gen 2)
- Temporary resource cleanup
- Comprehensive logging to `Documents\W365Customimage-YYYY-MM-DD-HH-MM.log`

**Interactive Prompts**:
- Azure subscription selection
- Azure region selection (default: southcentralus)
- Resource group name (default: rg-w365-customimage)
- VM administrator credentials (discarded after capture)

### 2. customimage.bicep
**Purpose**: Infrastructure as Code for Gen 2 VM deployment

**Resources Deployed**:
- **Virtual Network**: 10.100.0.0/16 with imagebuilder subnet
- **Network Security Group**: Allows internet access for package downloads
- **User-Assigned Managed Identity**: For VM deployment permissions
- **Role Assignment**: Contributor role on resource group
- **Build VM**: Gen 2 Windows 11 25H2 Enterprise CPC (Standard_D4s_v3)
- **Public IP**: Temporary for Azure Run Command (deleted after)
- **Network Interface**: For VM connectivity

**Outputs**: VM details (ID, name, public IP) for orchestration

### 3. Invoke-W365ImageCustomization.ps1
**Purpose**: VM customization script executed via Azure Run Command

**Source Image**: Windows 11 25H2 Enterprise Cloud PC Optimized (single-session)

**Customizations** (executed in stages):
1. **Stage 1 - Chocolatey Installation**: Install package manager
2. **Stage 2 - Application Installation** (via Chocolatey):
   - Visual Studio Code
   - 7-Zip
   - Google Chrome
   - Adobe Acrobat Reader
3. **Stage 3 - Windows Settings**: Timezone (Eastern), Explorer options, disable tips
4. **Stage 4 - Windows Updates**: Install all non-preview updates via PSWindowsUpdate
5. **Stage 5 - Optimization**: Disable telemetry, clean temp files, clear event logs

**Logging**: All operations logged to `C:\Windows\Temp\w365-customization.log`

### 4. Invoke-W365Sysprep.ps1
**Purpose**: Execute sysprep with Windows 365-compliant parameters

**Sysprep Command**: `C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown`

**Behavior**:
- Generalizes VM (removes system-specific information)
- Configures VM to boot to OOBE (Out-of-Box Experience)
- Automatically shuts down VM when complete
- Logging to `C:\Windows\Temp\w365-sysprep.log`

**Compliance**: Meets Windows 365 managed image requirements

## Deployment Flow

```
1. Check/Install Azure PowerShell modules
   ├─ Az.Accounts, Az.Resources, Az.ManagedServiceIdentity
   ├─ Az.Compute, Az.Network
   
2. Connect to Azure & verify subscription context
   └─ Interactive subscription, region, and RG name selection

3. Register Azure Resource Providers
   ├─ Microsoft.Compute
   ├─ Microsoft.Storage
   ├─ Microsoft.Network
   └─ Microsoft.ManagedIdentity

4. Prompt for VM Administrator Credentials
   └─ Used only during build, discarded after

5. Deploy Infrastructure (Bicep)
   ├─ Create Resource Group
   ├─ Deploy VNet, NSG, Subnet
   ├─ Create Managed Identity with Contributor role
   ├─ Deploy Gen 2 Windows 11 VM (Standard_D4s_v3)
   ├─ Attach Public IP and NIC
   └─ Wait for VM to be ready (2 minutes)

6. Execute Customization Script (Azure Run Command)
   ├─ Inject Invoke-W365ImageCustomization.ps1
   ├─ Install Chocolatey
   ├─ Install applications
   ├─ Configure Windows settings
   ├─ Run Windows Update
   └─ Optimize and cleanup (15-25 minutes)

7. Execute Sysprep (Azure Run Command)
   ├─ Inject Invoke-W365Sysprep.ps1
   ├─ Run sysprep /generalize /oobe /shutdown
   └─ Monitor VM power state until stopped (5-15 minutes)

8. Capture Managed Image
   ├─ Deallocate VM (if not already)
   ├─ Set VM to generalized state
   ├─ Create managed image with HyperVGeneration V2
   └─ Tag image with build timestamp (5-10 minutes)

9. Cleanup Temporary Resources
   ├─ Delete build VM
   ├─ Delete Public IP
   ├─ Delete Network Interface
   └─ Retain VNet/NSG for future builds

10. Output completion summary with image details
```

## Security & Permissions

### Managed Identity Permissions
- **Role**: Contributor on resource group
- **Purpose**: Deploy VM, create managed image, manage build resources
- **Scope**: Limited to deployment resource group

### Required Azure Permissions (User)
- Resource group creation
- Resource deployment (Owner or Contributor + User Access Administrator)
- Resource provider registration (Microsoft.Compute, Microsoft.Network, etc.)
- VM deployment and managed image creation

## Logging System

**Log Location**: `%USERPROFILE%\Documents\W365Customimage-YYYY-MM-DD-HH-MM.log`

**Log Levels**:
- **Info** (Cyan): Standard operations
- **Warning** (Yellow): Non-critical issues
- **Error** (Red): Failures
- **Success** (Green): Completed operations

**Log Content**:
- All deployment steps with timestamps
- Azure context information
- Resource deployment outputs
- Error details with stack traces

## Post-Deployment Steps

### Image is Automatically Created
The script runs fully automated - no manual build trigger required!

**Completion Time**: 30-60 minutes total

**Monitor Progress**: Watch PowerShell console or check log file in Documents folder

### Use Custom Image in Windows 365
1. Navigate to Microsoft Intune admin center
2. Go to **Windows 365** > **Provisioning Policies**
3. Create policy > Select **Custom image**
4. Choose managed image: **w365-custom-image-{timestamp}**
5. Complete configuration and assign to users

### Verify Image
```powershell
# List all managed images
Get-AzImage -ResourceGroupName 'rg-w365-customimage'

# Get specific image details
Get-AzImage -ResourceGroupName 'rg-w365-customimage' -ImageName 'w365-custom-image-20251016143000'
```

## Customization Options

### Modify Applications
Edit `Invoke-W365ImageCustomization.ps1`, find $packages array:
```powershell
$packages = @(
    @{ Name = 'vscode'; DisplayName = 'Visual Studio Code' }
    @{ Name = '7zip'; DisplayName = '7-Zip' }
    @{ Name = 'googlechrome'; DisplayName = 'Google Chrome' }
    @{ Name = 'adobereader'; DisplayName = 'Adobe Acrobat Reader' }
    @{ Name = 'notepadplusplus'; DisplayName = 'Notepad++' }  # Add new
)
```

Find package names at: https://community.chocolatey.org/packages

### Change Base Image
Update `customimage.bicep` storageProfile section:
```bicep
imageReference: {
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-11'
    sku: 'win11-25h2-ent-cpc'  // Change SKU here
    version: 'latest'
}
```

### Adjust Network Configuration
Modify `customimage.bicep` addressSpace and addressPrefix values

### Multi-Region Deployment
Managed images don't support automatic replication. To deploy in multiple regions:
1. Run the deployment script in each target region
2. Select appropriate region during deployment
3. Each region will have its own managed image

## Error Handling

The script includes comprehensive error handling:
- Module installation failures
- Authentication issues
- Resource provider registration errors
- Deployment failures with detailed logging
- Automatic rollback via Azure Resource Manager

## Prerequisites

### Azure Subscription Requirements
- Active Azure subscription
- Sufficient quota for:
  - Standard_D4s_v3 VM (4 vCPUs, DSv3 family)
  - Standard storage account
  - Public IP address
- Note: Standard_D4s_v3 is used for broad quota availability. Can be changed to other D-series VMs if needed

### Local Requirements
- Windows operating system
- PowerShell 5.1 or PowerShell 7+
- Internet connectivity
- Administrator rights (recommended)

### Supported Azure Regions
All Azure regions that support Generation 2 VMs and Windows 11 images

**Commonly Used**:
- North America: eastus, eastus2, westus, westus2, westus3, central US, Canada Central, Canada East
- Europe: northeurope, westeurope, uksouth, ukwest, francecentral
- Asia Pacific: southeastasia, japaneast, koreacentral, australiaeast
- Other: brazilsouth, southafricanorth

## Maintenance & Updates

### Update to Latest Windows Updates
Simply re-run the deployment script to create a new image with latest updates:
```powershell
.\Deploy-W365CustomImage.ps1
```

Each run creates a new timestamped managed image with current Windows Updates.

### Add New Applications
1. Edit `Invoke-W365ImageCustomization.ps1`
2. Add package to $packages array
3. Re-run deployment script

### Version Management
- Each build creates a uniquely timestamped managed image
- Example: `w365-custom-image-20251016143000`
- Keep previous images for rollback or delete manually
- No automatic versioning (managed images don't support it)

## Cost Considerations

**One-Time Costs per Build**:
- Build VM (Standard_D4s_v3): ~$0.15-0.50 per hour (1-2 hours typical)
- Temporary storage: ~$0.01
- Public IP: ~$0.01

**Ongoing Costs**:
- Managed image storage: ~$0.05/GB/month (128 GB = ~$6.40/month per image)
- No network egress costs (images are region-specific)

**Estimated Total**: $0.50-1.00 per image build, $6-7/month storage per image

## Support & Troubleshooting

### Common Issues
1. **Role assignment propagation**: Wait 60 seconds if deployment fails immediately
2. **Chocolatey package failures**: Verify package names at https://community.chocolatey.org/packages
3. **Sysprep failures**: Check customization completed successfully before sysprep
4. **Network timeouts**: Check NSG rules and internet connectivity for VM
5. **VM doesn't stop**: Sysprep may have failed, check logs on VM

### Logs Location
- **Deployment log**: Documents folder - `W365Customimage-YYYY-MM-DD-HH-MM.log`
- **Customization log**: On VM - `C:\Windows\Temp\w365-customization.log`
- **Sysprep log**: On VM - `C:\Windows\Temp\w365-sysprep.log`

### Troubleshooting Commands
```powershell
# Check VM status
Get-AzVM -ResourceGroupName 'rg-w365-customimage' -Name 'w365-build-vm-*' -Status

# List managed images
Get-AzImage -ResourceGroupName 'rg-w365-customimage'

# View deployment log
Get-Content "$env:USERPROFILE\Documents\W365Customimage-*.log" | Select-Object -Last 100
```

## Version History
- **v2.0** (2025-10-16): Migrated to managed image approach with Chocolatey
- **v1.0** (2025-10-14): Initial release with Azure VM Image Builder
