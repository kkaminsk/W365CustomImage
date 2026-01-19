# 🚀 Quick Start Guide - Windows 365 Custom Image

## What Was Built

A complete automated solution for creating Windows 365 custom images with **just ONE script**.

## Files Created

| File | Purpose |
|------|----------|
| **Deploy-W365CustomImage.ps1** | Main orchestration script |
| **Invoke-W365ImageCustomization.ps1** | VM customization with Winget & Chocolatey |
| **Invoke-W365Sysprep.ps1** | Sysprep automation |
| **customimage.bicep** | Infrastructure (Gen 2 VM) |
| **check-W365permissions.ps1** | Permissions validator |
| **SPECIFICATION.md** | Technical details |
| **README.md** | Full documentation |
| **QUICKSTART.md** | This guide |

## Deployment Steps

### Step 1: Open PowerShell
Right-click PowerShell → **Run as Administrator** (recommended)

### Step 2: Navigate to Folder
```powershell
cd "C:\Users\KevinKaminski\OneDrive - Big Hat Group Inc\Documents\GitHub\TechmentorOrlando-2025-Windows365\CustomImage"
```

### Step 3: Run Deployment
```powershell
# Deploy for student 1 (default)
.\Deploy-W365CustomImage.ps1

# Deploy for specific student (1-40)
.\Deploy-W365CustomImage.ps1 -StudentNumber 5
```

**Student Number Support:**
- Specify `-StudentNumber` (1-40) to create isolated resources per student
- Default: Student 1 if not specified
- Resource Group: `rg-w365-customimage-student{N}`
- VNet: `w365-image-vnet-student{N}`
- Image: `w365-custom-image-student{N}-{timestamp}`

**What it does:** The script will (fully automated, 30-60 minutes):
- ✅ Install required Azure modules
- ✅ Connect to Azure
- ✅ Register resource providers
- ✅ Deploy Gen 2 Windows 11 VM (win11-25h2-ent-cpc)
- ✅ Install applications via Winget (VSCode, 7-Zip, Chrome, Adobe Reader)
- ✅ Install Microsoft 365 Apps via Chocolatey (Word, Excel, PowerPoint, Outlook, OneNote, Teams)
- ✅ Configure Windows settings
- ✅ Run Windows Update
- ✅ Execute sysprep (/generalize /oobe /shutdown)
- ✅ Capture as managed image (Gen 2)
- ✅ Clean up temporary resources
- ✅ Log everything to Documents folder

### Step 4: Wait for Completion

The script runs fully automated (no manual steps!):

**Progress indicators:**
- Step 1-5: Infrastructure deployment (~5 minutes)
- Step 6: VM customization (~15-25 minutes)
- Step 7: Sysprep execution (~5-15 minutes)
- Step 8: Image capture (~5-10 minutes)
- Step 9: Cleanup (~2 minutes)

**Total Time**: 30-60 minutes

You can monitor progress:
- Watch the PowerShell console for colored status updates
- Check log file: `Documents\W365Customimage-YYYY-MM-DD-HH-MM.log`
- View resources in Azure Portal

### Step 5: Use in Windows 365

Once build completes:
1. Go to **Microsoft Intune admin center**
2. **Windows 365** → **Provisioning Policies** → **Create policy**
3. Select **Custom image** → **w365-custom-image-{timestamp}**
4. Complete and assign to users

## What's in the Custom Image

### Base Image
- **Windows 11 25H2 Enterprise** (Cloud PC Optimized)
- Single-session OS (not multi-session)
- Generation 2 Hyper-V

### Pre-installed Applications (via Winget)
- ✅ Visual Studio Code
- ✅ 7-Zip
- ✅ Google Chrome
- ✅ Adobe Acrobat Reader

### Microsoft 365 Apps (via Chocolatey)
- ✅ Word, Excel, PowerPoint
- ✅ Outlook, OneNote, Teams
- ✅ 64-bit, Current Channel

### Windows Configuration
- ✅ Eastern timezone
- ✅ Show file extensions
- ✅ Show hidden files
- ✅ Disabled Windows tips
- ✅ All Windows Updates installed

### Optimizations
- ✅ Disabled telemetry
- ✅ Optimized power settings
- ✅ Cleaned temp files
- ✅ AVD-optimized base image

## Log File Location

Check your deployment log at:
```
C:\Users\KevinKaminski\Documents\W365Customimage-YYYY-MM-DD-HH-MM.log
```

## Custom Parameters

Deploy to different region or resource group:

```powershell
.\Deploy-W365CustomImage.ps1 `
    -Location "westus2" `
    -ResourceGroupName "rg-my-custom-images"
```

## Need to Customize?

### Add More Applications
Edit `Invoke-W365ImageCustomization.ps1` → Find `$packages` array → Add Winget packages:
```powershell
@{ Id = 'Notepad++.Notepad++'; DisplayName = 'Notepad++' }
```
Find Winget packages using: `winget search <app-name>` or https://winget.run/

### Change Settings
Edit `Invoke-W365ImageCustomization.ps1` → Stage 3 section → Add PowerShell commands

### Different Base Image
Edit `customimage.bicep` → Find `imageReference` section → Change `sku` value

See **README.md** for detailed customization examples.

## Troubleshooting

### "Module not found"
The script auto-installs modules. If it fails, install manually:
```powershell
Install-Module Az -Repository PSGallery -Force
```

### "Insufficient permissions"
You need Contributor + User Access Administrator on the subscription, plus permission to register resource providers

### "Deployment failed"
Check the log file in Documents folder for detailed error messages

### Sysprep fails
VM may not have completed customization. Check log: `C:\Windows\Temp\w365-customization.log` on VM

### Build takes too long
Normal build time is 30-60 minutes. Check Azure Portal for VM status and customization progress.

### Can't find image in Windows 365
- Ensure build completed successfully (check for "IMAGE BUILD COMPLETED SUCCESSFULLY" in log)
- Check image is in same region as your network connection
- Rebuild in the correct region if needed
- **Verify permissions**: Run the permission checker:
  ```powershell
  .\check-W365permissions.ps1
  ```
  This validates that Windows 365 has correct access to your managed image

## Quick Commands

```powershell
# Verify Windows 365 permissions
.\check-W365permissions.ps1

# Check deployment status for student 1
Get-AzResourceGroup -Name 'rg-w365-customimage-student1'

# List managed images for student 1
Get-AzImage -ResourceGroupName 'rg-w365-customimage-student1' | Select-Object Name, ProvisioningState, HyperVGeneration

# Get specific image
Get-AzImage -ResourceGroupName 'rg-w365-customimage-student1' -ImageName 'w365-custom-image-student1-20251016143000'

# View log
notepad "$env:USERPROFILE\Documents\W365Customimage-$(Get-Date -Format 'yyyy-MM-dd')*.log"

# Clean up everything for student 1
Remove-AzResourceGroup -Name 'rg-w365-customimage-student1' -Force
```

## Cost

**Per build**: ~$0.50-1.00
- Build VM: Standard_D4s_v3 (4 vCPUs, 16 GB RAM)
- Build time: 30-60 minutes

**Monthly storage**: ~$0.10-0.20 per managed image

Very affordable for custom image management!

**Note**: VM size can be adjusted in `customimage.bicep` if you have quota for other VM families.

## Next Steps After Deployment

1. ✅ Run the deployment script (fully automated!)
2. ✅ Wait 30-60 minutes
3. ✅ Create Windows 365 provisioning policy
4. ✅ Select your custom managed image
5. ✅ Assign to users
6. ✅ Users get custom Cloud PCs!

## Support

- **Technical Details**: See SPECIFICATION.md
- **Full Documentation**: See README.md
- **Original Guide**: See CustomImageGuide.md

---

**Ready?** Just run `.\Deploy-W365CustomImage.ps1` and you're on your way! 🎉
