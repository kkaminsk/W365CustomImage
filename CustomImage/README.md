# Windows 365 Custom Image Automation

Automated deployment solution for Windows 365 custom images using Azure Managed Images (Gen 2).

## 🚀 Quick Start

### One-Command Deployment

```powershell
# Deploy for student 1 (default)
.\Deploy-W365CustomImage.ps1

# Deploy for student 5
.\Deploy-W365CustomImage.ps1 -StudentNumber 5

# Deploy for student 10
.\Deploy-W365CustomImage.ps1 -StudentNumber 10
```

This single command:
- ✅ Installs required Azure PowerShell modules
- ✅ Authenticates to Azure
- ✅ Deploys Gen 2 Windows 11 VM (win11-25h2-ent-cpc)
- ✅ Installs applications via Chocolatey (VSCode, 7-Zip, Chrome, Adobe Reader)
- ✅ Configures Windows settings and optimizations
- ✅ Runs sysprep with Windows 365-compliant parameters
- ✅ Captures as managed image (Gen 2)
- ✅ Cleans up temporary resources
- ✅ Logs everything to Documents folder

The script runs interactively and prompts for:
- Azure tenant selection (if you have access to multiple tenants)
- Azure subscription selection (if multiple in selected tenant)
- Azure region (default: southcentralus)
- Resource group name (default: rg-w365-customimage-student{N} where N=student number)
- VM administrator credentials (used only during build, discarded after)

### Multi-Student Pod Support

Each student gets isolated resources to prevent conflicts:
- **Student Number**: 1-40 (specify with `-StudentNumber` parameter)
- **Resource Group**: `rg-w365-customimage-student{N}`
- **VNet**: `w365-image-vnet-student{N}`
- **Managed Identity**: `w365-imagebuilder-identity-student{N}`
- **Image Name**: `w365-custom-image-student{N}-{timestamp}`

This allows multiple students to build custom images in the same subscription without resource conflicts.

### Multi-Tenant Support

For guest administrators working with multiple Azure tenants:

```powershell
# Interactive tenant selection (recommended for first-time use)
.\Deploy-W365CustomImage.ps1 -StudentNumber 1

# Specify tenant explicitly (automation-friendly)
.\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -StudentNumber 5

# Specify both tenant and subscription (fully automated)
.\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -SubscriptionId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" -StudentNumber 10
```

**How it works:**
- Script enumerates all accessible tenants via `Get-AzTenant`
- Authenticates to selected tenant (handles MFA prompts)
- Retrieves enabled subscriptions within that tenant
- Establishes correct context before deployment
- Single tenant users see no change—automatic selection continues

## 📋 Prerequisites

- Azure subscription with permissions to create resources
- PowerShell 5.1 or later
- Internet connectivity
- Permissions to register resource providers (Microsoft.Compute, Microsoft.Network, etc.)

**For Guest Administrators (Multi-Tenant Scenarios):**
- Guest access to target Azure tenant
- MFA configured for guest account (if required by tenant)
- Contributor role on target subscription or resource group

**That's it!** The script handles all Azure module installations and resource provider registrations automatically.

## 📦 What Gets Deployed

| Resource | Purpose | Naming |
|----------|---------|---------|
| **Resource Group** | Container for all resources | `rg-w365-customimage-student{N}` |
| **Virtual Network** | Isolated network for build VM (10.100.0.0/16) | `w365-image-vnet-student{N}` |
| **Network Security Group** | Security rules for VM connectivity | `w365-nsg-student{N}` |
| **Managed Identity** | Service principal with Contributor role | `w365-imagebuilder-identity-student{N}` |
| **Build VM** | Gen 2 Windows 11 25H2 Enterprise CPC (temporary) | `w365-build-vm-{timestamp}` |
| **Public IP** | Temporary connectivity for customization (deleted after) | `w365-build-pip-{timestamp}` |
| **Managed Image** | Final Gen 2 custom image for Windows 365 | `w365-custom-image-student{N}-{timestamp}` |

## 🔨 Build Process

The script automates the entire process:

1. **Deploy Infrastructure** - VNet, NSG, Managed Identity
2. **Deploy Build VM** - Gen 2 Windows 11 25H2 Enterprise CPC (Standard_D4s_v3)
3. **Execute Customization** - Run script via Azure Run Command:
   - Install Chocolatey
   - Install applications (VSCode, 7-Zip, Chrome, Adobe Reader)
   - Configure Windows settings (timezone, Explorer, disable tips)
   - Run Windows Update
   - Optimize and cleanup
4. **Run Sysprep** - Execute `/generalize /oobe /shutdown`
5. **Wait for Shutdown** - Monitor VM power state (5-15 minutes)
6. **Capture Image** - Create Gen 2 managed image from VM
7. **Cleanup** - Delete build VM, Public IP, NIC

**Total Time**: 30-60 minutes (fully automated)

**No manual steps required!** The entire process runs start-to-finish.

## 📝 Logging

All operations are logged to:
```
%USERPROFILE%\Documents\W365Customimage-YYYY-MM-DD-HH-MM.log
```

Log includes:
- Detailed step-by-step progress
- Resource IDs and names
- Error messages with stack traces
- Next steps and commands

## 🎨 Customizations Included

### Base Image
- Windows 11 25H2 Enterprise (Cloud PC Optimized)
- Single-session OS (not multi-session)
- Generation 2 Hyper-V
- Optimized for Windows 365

### Applications Installed (via Winget)
- Visual Studio Code
- 7-Zip
- Google Chrome
- Adobe Acrobat Reader

### Microsoft 365 Apps (via Chocolatey ODT)
- Word, Excel, PowerPoint
- Outlook, OneNote, Teams
- 64-bit, Current Channel
- Excluded: Publisher, Groove, Access

### Windows Configuration
- Timezone: Eastern Standard Time
- Show file extensions in Explorer
- Show hidden files
- Disable Windows tips and suggestions
- Install all Windows Updates (excluding previews)

### Optimizations
- Disabled telemetry services
- Configured power settings for virtual environment
- Cleaned temporary files and event logs

## 🛠️ Customization Guide

### Add/Remove Applications

Edit `Invoke-W365ImageCustomization.ps1`, find the `$packages` array:

```powershell
$packages = @(
    @{ Id = '7zip.7zip'; DisplayName = '7-Zip' }
    @{ Id = 'Microsoft.VisualStudioCode'; DisplayName = 'Visual Studio Code' }
    @{ Id = 'Google.Chrome'; DisplayName = 'Google Chrome' }
    @{ Id = 'Adobe.Acrobat.Reader.64-bit'; DisplayName = 'Adobe Acrobat Reader' }
    @{ Id = 'Microsoft.PowerBI.Desktop'; DisplayName = 'Power BI Desktop' }  # Add new package
)
```

Find Winget package IDs using: `winget search <app-name>`

### Customize Microsoft 365 Apps

Edit the Chocolatey ODT parameters in `Invoke-W365ImageCustomization.ps1`:

```powershell
choco install microsoft-office-deployment --params="'/64bit /Product:O365ProPlusRetail /Channel:Current /Exclude:Publisher,Groove,Access'" -y
```

**Available parameters:**
- `/64bit` or `/32bit` - Architecture
- `/Product:` - O365ProPlusRetail, O365BusinessRetail, VisioProRetail, ProjectProRetail
- `/Channel:` - Current, MonthlyEnterprise, SemiAnnual
- `/Exclude:` - Comma-separated list (Word, Excel, PowerPoint, Outlook, OneNote, Teams, Publisher, Access, Groove, Lync)

### Change Base Image

Edit `customimage.bicep`, modify the VM `storageProfile` section:

```bicep
imageReference: {
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-11'
    sku: 'win11-25h2-ent-cpc'  // Change SKU here
    version: 'latest'
}
```

**Available SKUs:**
- `win11-25h2-ent-cpc` - Windows 11 25H2 Enterprise CPC (recommended)
- `win11-23h2-ent` - Windows 11 23H2 Enterprise
- `win10-22h2-ent` - Windows 10 22H2 Enterprise

### Add Custom Settings

Add PowerShell commands to `Invoke-W365ImageCustomization.ps1` in Stage 3:

```powershell
# Example: Set custom registry setting
Set-ItemProperty -Path "HKLM:\SOFTWARE\YourCompany" -Name "Setting" -Value "Value"

# Example: Copy files
Copy-Item -Path "\\\\server\\share\\file.txt" -Destination "C:\\Temp\\"
```

### Modify Network Settings

Edit `customimage.bicep` to change VNet address space:

```bicep
addressSpace: {
    addressPrefixes: [
        '10.200.0.0/16'  // Change this
    ]
}
```

## 📋 File Structure

```
CustomImage/
├── Deploy-W365CustomImage.ps1           # Main orchestration script
├── Invoke-W365ImageCustomization.ps1    # VM customization script
├── Invoke-W365Sysprep.ps1               # Sysprep execution script
├── check-W365permissions.ps1            # Windows 365 permissions validator
├── customimage.bicep                    # Infrastructure template (Gen 2 VM)
├── SPECIFICATION.md                     # Detailed technical specification
├── CustomImageGuide.md                  # Original guide documentation
└── README.md                            # This file
```

## 🔐 Security & Permissions

### Managed Identity
- **Role**: Contributor (scoped to resource group only)
- **Purpose**: Create build resources and save images
- **Lifetime**: Persists after deployment for future builds

### Required User Permissions

#### For Deploy-W365CustomImage.ps1
- **Subscription Contributor** OR **Resource Group Owner**
- **User Access Administrator** (for creating role assignments)
- **Resource Provider Registration** rights (automatically registers):
  - Microsoft.Compute
  - Microsoft.Storage
  - Microsoft.Network
  - Microsoft.ManagedIdentity

**Tip**: The script runs fully automated and completes in 30-60 minutes.

### Windows 365 Service Principal Permissions

For Windows 365 to access managed images and provision Cloud PCs, the Windows 365 service principal requires:

- **Reader** on the Subscription (for network connection)
- **Windows 365 Network Interface Contributor** on the Resource Group
- **Windows 365 Network User** on the Virtual Network
- **Reader** on the Resource Group containing managed images

**Validate Permissions**: Use the automated checker to verify all permissions are correctly configured:

```powershell
# Interactive tenant selection
.\check-W365permissions.ps1

# Specify tenant explicitly
.\check-W365permissions.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

The script will:
- Select Azure tenant (if multiple accessible)
- Find the Windows 365 service principal in that tenant
- Prompt you to select subscriptions, resource groups, and resources
- Check each required permission
- Display PASS/FAIL status for each check
- Provide PowerShell commands to fix any missing permissions
- Show overall PASS/FAIL status
- Log results to `Documents\check-w365permissions-YYYY-MM-DD-HH-MM.log`

Run this script whenever you experience issues with Windows 365 connectivity or custom image visibility.

## 💰 Cost Estimate

**Per Image Build**:
- Build VM (Standard_D4s_v3, 4 vCPUs, 16 GB RAM): ~$0.30-0.50
- Temporary storage: ~$0.01
- Network: ~$0.01

**Ongoing Monthly**:
- Image storage: ~$0.10-0.20

**Total per build**: Less than $1.00

**Note**: VM size can be changed in `customimage.bicep` if needed. Standard_D4s_v3 is used for broad quota availability.

## 🎯 Using the Custom Image

### In Windows 365

1. Open **Microsoft Intune admin center**
2. Navigate to **Windows 365** → **Provisioning Policies**
3. Create new policy
4. Select **Image type**: Custom image
5. Choose your managed image: **w365-custom-image-{timestamp}**
6. Complete configuration and assign to users

### In Azure Virtual Desktop

1. Create new host pool
2. Select **Virtual machine images** → **See all images**
3. Choose **My items** → **Managed images**
4. Select: **w365-custom-image-{timestamp}**

## 🔄 Update Process

### Rebuild with Latest Updates

Simply run the deployment script again to create a new image:

```powershell
.\Deploy-W365CustomImage.ps1
```

New image will include:
- Latest Windows Updates
- Updated applications
- Any customization script changes you made

Each build creates a timestamped managed image (e.g., `w365-custom-image-20251016143000`)

### Multi-Region Deployment

Managed images are region-specific. To deploy in multiple regions:

1. Run the deployment script in each target region
2. Select the appropriate region during deployment
3. Each region will have its own managed image

**Note**: Unlike galleries, managed images don't support automatic replication.

## 🐛 Troubleshooting

### Deployment Fails Immediately
- **Cause**: Role assignment not propagated
- **Fix**: Wait 60 seconds and try again

### Chocolatey Package Installation Fails
- **Cause**: Package not found or network issue
- **Fix**: Verify package name at https://community.chocolatey.org/packages
- **Fix**: Check build VM has internet connectivity

### Sysprep Fails
- **Cause**: VM not properly configured or customization errors
- **Fix**: Check customization log in VM: `C:\Windows\Temp\w365-customization.log`
- **Fix**: RDP to build VM before sysprep runs to troubleshoot

### Build Times Out
- **Cause**: Customization script taking too long
- **Fix**: Reduce Windows Update scope or package count

### Can't Find Image in Windows 365
- **Cause**: Image not in same region as network connection, or missing permissions
- **Fix**: 
  1. Check if image is in same region as network connection
  2. Verify Windows 365 permissions:
     ```powershell
     .\check-W365permissions.ps1
     ```
  3. Rebuild in the correct region

**Permissions Checker**: The `check-W365permissions.ps1` script validates that the Windows 365 service principal has all required permissions:
- Reader on Subscription
- Windows 365 Network Interface Contributor on Resource Group
- Windows 365 Network User on Virtual Network
- Reader on Resource Group (for managed images)

Run this script anytime you have connectivity or image visibility issues.

### Check Logs

```powershell
# View deployment log
Get-Content "$env:USERPROFILE\Documents\W365Customimage-*.log" | Select-Object -Last 50

# List managed images
Get-AzImage -ResourceGroupName 'rg-w365-customimage' | Select-Object Name, ProvisioningState, HyperVGeneration
```

## 📚 Additional Resources

- [Azure Managed Images Documentation](https://learn.microsoft.com/azure/virtual-machines/capture-image-resource)
- [Windows 365 Custom Images](https://learn.microsoft.com/windows-365/enterprise/custom-image)
- [Chocolatey Package Repository](https://community.chocolatey.org/packages)
- [Windows 11 Enterprise Images](https://learn.microsoft.com/azure/virtual-machines/windows/windows-desktop-images)

## 🤝 Contributing

To add features or fix issues:
1. Test changes in non-production subscription
2. Update SPECIFICATION.md with changes
3. Update version history in SPECIFICATION.md
4. Submit changes with detailed description

## 📄 License

Use freely for Windows 365 and Azure Virtual Desktop deployments.

## ⚡ Quick Reference

```powershell
# Deploy and build custom image for student 1 (fully automated)
.\Deploy-W365CustomImage.ps1 -StudentNumber 1

# Deploy for student 5
.\Deploy-W365CustomImage.ps1 -StudentNumber 5

# Deploy to specific tenant for student 10 (multi-tenant scenario)
.\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -StudentNumber 10

# Verify Windows 365 permissions (troubleshooting)
.\check-W365permissions.ps1

# Verify permissions in specific tenant
.\check-W365permissions.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Remove resources from specific tenant
.\Remove-W365RG.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# List managed images for student 1
Get-AzImage -ResourceGroupName 'rg-w365-customimage-student1' | Select-Object Name, ProvisioningState, HyperVGeneration, Location

# List all student images
1..40 | ForEach-Object { Get-AzImage -ResourceGroupName "rg-w365-customimage-student$_" -ErrorAction SilentlyContinue } | Select-Object Name, ProvisioningState, HyperVGeneration, Location

# Get specific image details
Get-AzImage -ResourceGroupName 'rg-w365-customimage-student1' -ImageName 'w365-custom-image-student1-20251016143000'

# View recent deployment log
Get-Content "$env:USERPROFILE\Documents\W365Customimage-*.log" | Select-Object -Last 50

# Delete everything for student 1 (cleanup)
Remove-AzResourceGroup -Name 'rg-w365-customimage-student1' -Force

# Delete resources for specific student
Remove-AzResourceGroup -Name 'rg-w365-customimage-student5' -Force
```

---

**Ready to deploy?** Just run `.\Deploy-W365CustomImage.ps1` and follow the prompts! 🚀
