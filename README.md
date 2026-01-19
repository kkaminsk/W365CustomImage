# Windows 365 Custom Image Automation

Fully automated solution for creating Windows 365 custom images using Azure Managed Images (Gen 2).

## What It Does

This solution automates the entire custom image creation process:

1. **Deploys** a Gen 2 Windows 11 VM with Cloud PC-optimized image
2. **Installs** applications via Winget (VSCode, 7-Zip, Chrome, Adobe Reader)
3. **Installs** Microsoft 365 Apps via Chocolatey (Word, Excel, PowerPoint, Outlook, OneNote, Teams)
4. **Configures** Windows settings (timezone, Explorer options, optimizations)
5. **Runs** Windows Update (all non-preview updates)
6. **Executes** sysprep with Windows 365-compliant parameters
7. **Captures** as a Gen 2 managed image
8. **Cleans up** temporary resources automatically

**Total time**: 30-60 minutes (fully automated, no manual steps)

## Quick Start

```powershell
cd CustomImage

# Deploy for student 1 (default)
.\Deploy-W365CustomImage.ps1

# Deploy for specific student (1-40)
.\Deploy-W365CustomImage.ps1 -StudentNumber 5

# Multi-tenant deployment
.\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

## Multi-Student Support

Designed for training labs with isolated resources per student:

| Resource | Naming Pattern |
|----------|----------------|
| Resource Group | `rg-w365-customimage-student{N}` |
| Virtual Network | `w365-image-vnet-student{N}` |
| Managed Identity | `w365-imagebuilder-identity-student{N}` |
| Managed Image | `w365-custom-image-student{N}-{timestamp}` |

## Prerequisites

- Azure subscription with Contributor permissions
- PowerShell 5.1+ (PowerShell 7+ recommended)
- Internet connectivity

The script automatically installs required Azure PowerShell modules.

## Documentation

| Document | Description |
|----------|-------------|
| [CustomImage/README.md](CustomImage/README.md) | Full documentation and customization guide |
| [CustomImage/QUICKSTART.md](CustomImage/QUICKSTART.md) | Fast-track guide for experienced users |
| [CustomImage/SPECIFICATION.md](CustomImage/SPECIFICATION.md) | Technical specifications |
| [CustomImage/Overview.md](CustomImage/Overview.md) | Solution architecture overview |
| [CustomImage/CustomImageGuide.md](CustomImage/CustomImageGuide.md) | Step-by-step how-to guide |
| [CustomImage/PERMISSIONS-AND-RESTRICTIONS.md](CustomImage/PERMISSIONS-AND-RESTRICTIONS.md) | RBAC and security policies |

## Tech Stack

- **PowerShell** - Main scripting language
- **Azure Bicep** - Infrastructure as Code
- **Winget** - Microsoft's native package manager (common applications)
- **Chocolatey** - Package manager (Microsoft 365 Apps via ODT)
- **PSWindowsUpdate** - Windows Update automation

## Cost

- **Per build**: ~$0.50-1.00 (30-60 minutes of VM time)
- **Image storage**: ~$0.10-0.20/month per image

## Version

**v2.1** (January 2026) - Hybrid Winget + Chocolatey installation approach
