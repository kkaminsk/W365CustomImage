## Why

Windows 365 Cloud PCs are typically used for productivity workloads that require Microsoft 365 Apps (Word, Excel, PowerPoint, Outlook, OneNote, Teams). Including M365 Apps in the custom image ensures users have a ready-to-use productivity environment without waiting for app deployment after provisioning.

## What Changes

- Add Microsoft 365 Apps installation to the image customization script using Chocolatey's `microsoft-office-deployment` package
- Install Chocolatey package manager (required for M365 deployment since Winget lacks ODT integration)
- Configure M365 installation with:
  - 64-bit architecture
  - O365ProPlusRetail product (Microsoft 365 Apps for enterprise)
  - Current Channel for updates
  - Exclude Publisher, Groove (OneDrive for Business sync), and Access to reduce image size

## Impact

- Affected code: `CustomImage/Invoke-W365ImageCustomization.ps1`
- Affected specs: `application-installation`
- **Image size increase**: ~2-3 GB for M365 Apps
- **Build time increase**: ~10-15 minutes additional for M365 installation
- **Dependency**: Requires Chocolatey installation (adds ~1-2 minutes)
- **Licensing**: M365 Apps require valid Microsoft 365 licenses assigned to end users
