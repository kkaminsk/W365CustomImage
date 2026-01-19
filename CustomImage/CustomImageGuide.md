# Windows 365 Custom Image Guide

Creating custom images for Windows 365 using **Azure Managed Images** is a fully automated way to ensure your Cloud PCs are provisioned with the exact applications, settings, and updates your organization needs from the start.

This guide explains the managed image approach and how to use the automated deployment solution.

-----

## What are Azure Managed Images?

Azure Managed Images are Generation 2 VM images that can be used to deploy Windows 365 Cloud PCs. Unlike Azure Compute Gallery images, managed images:
- ✅ Are simpler and faster to create
- ✅ Work directly with Windows 365 provisioning
- ✅ Support full automation with scripting
- ✅ Use a direct VM → Sysprep → Capture workflow
- ✅ Are region-specific (create in your target region)

-----

## Automated Deployment Process

The solution uses **`Deploy-W365CustomImage.ps1`** which fully automates the entire process:

### What the Script Does

1. **Environment Setup**
   - Installs/validates Azure PowerShell modules
   - Connects to Azure and selects subscription
   - Registers required resource providers

2. **Infrastructure Deployment** (via Bicep)
   - Creates resource group
   - Deploys Virtual Network and NSG
   - Creates User-Assigned Managed Identity with Contributor role
   - Deploys Gen 2 Windows 11 24H2 VM (Standard_D4s_v3)
   - Attaches Public IP and NIC

3. **VM Customization** (via Azure Run Command)
   - Installs applications via Winget: Visual Studio Code, 7-Zip, Google Chrome, Adobe Acrobat Reader
   - Installs Microsoft 365 Apps via Chocolatey (Word, Excel, PowerPoint, Outlook, OneNote, Teams)
   - Configures Windows settings (timezone, Explorer options, disables tips)
   - Runs Windows Update (all non-preview updates)
   - Optimizes and cleans up (disable telemetry, clean temp files, clear event logs)

4. **Sysprep and Capture**
   - Executes sysprep with Windows 365-compliant parameters: `/generalize /oobe /shutdown`
   - Monitors VM shutdown
   - Deallocates VM
   - Captures as Generation 2 managed image
   - Tags image with build timestamp

5. **Cleanup**
   - Deletes build VM
   - Deletes Public IP
   - Deletes Network Interface
   - Retains VNet/NSG for future builds

### Prerequisites

Before running the script, ensure you have:

- **Azure Subscription** with permissions to:
  - Create resource groups
  - Deploy resources (Owner or Contributor + User Access Administrator)
  - Register resource providers
  - Create VMs and managed images

- **PowerShell 5.1 or later**

- **Internet connectivity** for:
  - Azure PowerShell module installation
  - Package downloads (Chocolatey, applications)
  - Windows Updates

- **For Multi-Tenant Scenarios**:
  - Guest access to target Azure tenant
  - MFA configured for guest account (if required by tenant)
  - Contributor role on target subscription or resource group

-----

## Running the Deployment

### Step 1: Execute the Script

**Interactive Mode (Default)**:
```powershell
cd CustomImage
# Deploy for student 1 (default)
.\Deploy-W365CustomImage.ps1

# Deploy for student 5
.\Deploy-W365CustomImage.ps1 -StudentNumber 5
```

**Multi-Student Pod Support**:
- Specify `-StudentNumber` (1-40) to create isolated resources per student
- Each student gets unique resource group, VNet, and managed identity
- Resource Group: `rg-w365-customimage-student{N}`
- VNet: `w365-image-vnet-student{N}`
- Image Name: `w365-custom-image-student{N}-{timestamp}`

**Multi-Tenant Mode**:
```powershell
# Interactive tenant selection for student 1
.\Deploy-W365CustomImage.ps1 -StudentNumber 1

# Specify tenant explicitly for student 5
.\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -StudentNumber 5

# Specify both tenant and subscription for student 10 (fully automated)
.\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -SubscriptionId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" -StudentNumber 10
```

### Step 2: Respond to Prompts

The script will interactively prompt for:

1. **Azure Tenant** - Select from accessible tenants (if multiple)
2. **Azure Subscription** - Select from enabled subscriptions in selected tenant
3. **Azure Region** - Default: southcentralus (or choose another)
4. **Resource Group Name** - Default: rg-w365-customimage-student{N} (where N = student number)
5. **VM Administrator Credentials** - Used only during build, discarded after

**Multi-Tenant Authentication**:
- Script automatically handles MFA prompts when switching tenants
- If MFA is required, follow on-screen instructions
- Script provides helpful guidance for authentication failures

### Step 3: Monitor Progress

The script provides detailed console output:
- ✅ Green for successful operations
- ℹ️ Cyan for informational messages
- ⚠️ Yellow for warnings
- ❌ Red for errors

**Estimated Time**: 30-60 minutes total
- Infrastructure deployment: 5-10 minutes
- VM customization: 15-25 minutes
- Sysprep and capture: 10-20 minutes
- Cleanup: 2-5 minutes

All operations are logged to:
```
%USERPROFILE%\Documents\W365Customimage-YYYY-MM-DD-HH-MM.log
```

-----

## Using Your Custom Image in Windows 365

Once the build completes successfully:

### Step 1: Verify the Image

```powershell
# For student 1
Get-AzImage -ResourceGroupName 'rg-w365-customimage-student1'

# For student 5
Get-AzImage -ResourceGroupName 'rg-w365-customimage-student5'
```

### Step 2: Configure Windows 365 Provisioning Policy

1. Navigate to **Microsoft Intune admin center**
2. Go to **Windows 365** > **Provisioning Policies**
3. Select **Create policy**
4. On the **General** tab, give your policy a name
5. On the **Image** tab:
   - **Image type**: Select **Custom image**
   - Click **Select** and choose your managed image: `w365-custom-image-{timestamp}`
6. Complete the rest of the policy configuration (network connection, size, assignments)
7. Assign to a user group

### Step 3: Provision Cloud PCs

When users in the assigned group are licensed, their Cloud PCs will be provisioned using your custom image with:
- ✅ Pre-installed applications via Winget (VSCode, 7-Zip, Chrome, Adobe Reader)
- ✅ Microsoft 365 Apps (Word, Excel, PowerPoint, Outlook, OneNote, Teams)
- ✅ Configured Windows settings
- ✅ Latest Windows Updates
- ✅ Optimizations applied

-----

## Customizing the Solution

### Modify Applications

Edit `Invoke-W365ImageCustomization.ps1`:

```powershell
$packages = @(
    @{ Id = '7zip.7zip'; DisplayName = '7-Zip' }
    @{ Id = 'Microsoft.VisualStudioCode'; DisplayName = 'Visual Studio Code' }
    @{ Id = 'Google.Chrome'; DisplayName = 'Google Chrome' }
    @{ Id = 'Adobe.Acrobat.Reader.64-bit'; DisplayName = 'Adobe Acrobat Reader' }
    @{ Id = 'Notepad++.Notepad++'; DisplayName = 'Notepad++' }  # Add new
)
```

Find Winget package IDs using: `winget search <app-name>` or https://winget.run/

### Change Base Image

Edit `customimage.bicep` storageProfile section:

```bicep
imageReference: {
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-11'
    sku: 'win11-24h2-ent'  // Change SKU here
    version: 'latest'
}
```

### Adjust VM Size

Edit `customimage.bicep`:

```bicep
hardwareProfile: {
    vmSize: 'Standard_D4s_v3'  // Change to another D-series VM
}
```

-----

## Troubleshooting

### Common Issues

1. **Role assignment propagation**: Wait 60 seconds if deployment fails immediately
2. **Winget package failures**: Verify package IDs using `winget search <app-name>`
3. **Chocolatey/M365 package failures**: Verify package names at https://community.chocolatey.org/packages
4. **Sysprep failures**: Check customization completed successfully before sysprep
5. **VM doesn't stop**: Sysprep may have failed, check VM logs

### View Logs

**Deployment log**:
```powershell
Get-Content "$env:USERPROFILE\Documents\W365Customimage-*.log" | Select-Object -Last 100
```

**Check VM status** (for student 1):
```powershell
Get-AzVM -ResourceGroupName 'rg-w365-customimage-student1' -Status
```

**List managed images** (for student 1):
```powershell
Get-AzImage -ResourceGroupName 'rg-w365-customimage-student1'
```

-----

## Additional Resources

- See `README.md` for quick start guide
- See `QUICKSTART.md` for step-by-step walkthrough
- See `SPECIFICATION.md` for technical details
- Windows 365 documentation: https://learn.microsoft.com/windows-365/