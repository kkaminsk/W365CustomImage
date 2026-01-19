# Windows 365 Custom Image Builder - Solution Overview

## Purpose

This solution automates the creation of custom Windows 11 managed images for Windows 365 Cloud PC provisioning. It's designed for **multi-student training labs** where each student needs to build and test their own custom images in an isolated environment.

## Target Audience

- **IT Training Instructors** - Teaching Windows 365 deployment and customization
- **Lab Administrators** - Managing multi-student Azure training environments
- **Students** - Learning Windows 365 custom image creation hands-on
- **Cloud Administrators** - Building standardized Windows 365 images for organizations

## Solution Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Student Administrator (admin1-30@domain.ca)                │
│  ↓ Runs Deploy-W365CustomImage.ps1 -StudentNumber N        │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Azure Subscription (W365Lab)                               │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Resource Group: rg-w365-customimage-studentN       │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ 1. Build VM (Temporary)                      │ │    │
│  │  │    - Windows 11 25H2 Enterprise CPC (Gen 2) │ │    │
│  │  │    - Automated customization via scripts    │ │    │
│  │  │    - Sysprep with W365-compliant params     │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  │                      ↓                             │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ 2. Managed Image (Persistent)                │ │    │
│  │  │    - w365-custom-image-studentN-timestamp   │ │    │
│  │  │    - Gen 2 compatible                        │ │    │
│  │  │    - Ready for W365 provisioning            │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  │                      ↓                             │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ 3. Windows 365 Provisioning                  │ │    │
│  │  │    - Use image in provisioning policy       │ │    │
│  │  │    - Deploy Cloud PCs for users            │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Key Features

### 🎓 Multi-Student Isolation
- **30 student pods** (expandable to 40)
- Each student gets their own resource group, VNet, and managed identity
- No resource conflicts or naming collisions
- Clean separation of work across students

### 🔄 Fully Automated Workflow
1. **Deploy** - Gen 2 Windows 11 VM with CPC image
2. **Customize** - Install apps via Winget (VSCode, Chrome, 7-Zip, Adobe Reader) and Microsoft 365 Apps via Chocolatey
3. **Configure** - Apply Windows optimizations and settings
4. **Sysprep** - Windows 365-compliant generalization
5. **Capture** - Create Gen 2 managed image
6. **Cleanup** - Remove temporary resources (VM, NICs, disks)

### 🏢 Multi-Tenant Support
- Interactive tenant selection for guest administrators
- Handles MFA authentication flows
- Supports `-TenantId` parameter for automation
- Works across multiple Azure AD tenants

### 🔒 Least Privilege RBAC
- Custom role: **"Windows 365 Custom Image Builder"**
- Scoped to subscription level (allows RG creation)
- Minimum permissions required for image building
- Students cannot access other students' resources

### 📝 Complete Logging
- Timestamped log files in Documents folder
- Detailed operation tracking
- Error reporting with context
- Audit trail for compliance

## Core Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **Deploy-W365CustomImage.ps1** | Main deployment orchestrator | Root of CustomImage folder |
| **Invoke-W365ImageCustomization.ps1** | Application installation & settings | Executed on build VM |
| **Invoke-W365Sysprep.ps1** | Windows generalization | Executed on build VM |
| **customimage.bicep** | Infrastructure as Code template | Deployed by main script |
| **Get-W365CustomizationLog.ps1** | Retrieve logs from build VM | Manual troubleshooting |
| **Remove-W365RG.ps1** | Clean up student resource groups | Administrative cleanup |
| **check-W365permissions.ps1** | Verify RBAC configuration | Pre-deployment validation |

## Resource Naming Convention

| Resource Type | Naming Pattern | Example |
|---------------|----------------|---------|
| Resource Group | `rg-w365-customimage-student{N}` | `rg-w365-customimage-student5` |
| Virtual Network | `w365-image-vnet-student{N}` | `w365-image-vnet-student5` |
| Managed Identity | `w365-imagebuilder-identity-student{N}` | `w365-imagebuilder-identity-student5` |
| Build VM (temp) | `w365-build-vm-{timestamp}` | `w365-build-vm-20250110-143022` |
| Managed Image | `w365-custom-image-student{N}-{timestamp}` | `w365-custom-image-student5-20250110-143500` |

**Note:** Student number (N) ranges from 1-40 to prevent IP conflicts in hub-spoke networking scenarios.

## Deployment Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| **Infrastructure** | 3-5 min | Deploy RG, VNet, NSG, Managed Identity, VM |
| **Provisioning** | 2-3 min | Windows installation and initial setup |
| **Customization** | 10-15 min | Install apps, configure settings, optimizations |
| **Sysprep** | 3-5 min | Generalize Windows (VM shuts down) |
| **Image Capture** | 5-7 min | Create managed image from deallocated VM |
| **Cleanup** | 1-2 min | Remove VM, disks, NICs, public IPs |
| **Total** | **25-35 min** | Complete end-to-end process |

## Prerequisites

### Required Permissions
- **Azure Subscription Access**: Contributor role (or custom "Windows 365 Custom Image Builder" role)
- **Resource Provider Registration**: Microsoft.Compute, Microsoft.Network, Microsoft.Storage, Microsoft.ManagedIdentity

### Technical Requirements
- PowerShell 5.1 or later (PowerShell 7+ recommended)
- Internet connectivity
- Azure PowerShell modules (auto-installed by script)

### Azure Quotas (Per Region)
- Standard DSv3 Family vCPUs: **4 per student** (8 for 2 concurrent builds)
- Total vCPUs: **4-8 per student**
- Public IPs: **1 per student** (temporary during build)
- Standard HDD Managed Disks: **1 per student** (temporary during build)

## Security & Compliance

### Data Protection
- VM admin credentials used only during build (never persisted)
- Build VM deallocated before image capture
- Temporary resources cleaned up automatically
- Managed identity scoped to resource group

### Network Isolation
- Private VNet per student (10.100.{N}.0/24)
- Network Security Group with RDP rule (customizable)
- No public endpoints in final image
- Hub-spoke architecture support (optional peering)

### Role-Based Access Control
- Students assigned custom role at subscription scope
- Permissions limited to:
  - Create/manage resource groups
  - Create/manage VMs and images
  - Register resource providers
- Cannot access other students' resources
- Cannot modify subscription settings

## Cost Optimization

### During Build
- **VM**: Standard_D2s_v3 ($0.096/hour in South Central US)
- **Storage**: Premium SSD OS disk (temporary)
- **Network**: Public IP (temporary)
- **Estimated cost per build**: **$0.05-0.10** (25-35 minutes)

### After Build
- **Image Storage**: Managed image storage (minimal, ~$0.50-1/month)
- **Resource Group**: No cost (empty after cleanup)
- **Total monthly cost per student**: **<$1.00**

### Cost Savings
- Automatic cleanup of temporary resources
- No persistent compute costs
- Students can delete resource groups when done
- Managed images cheaper than Azure Compute Gallery

## Integration Points

### Windows 365 Provisioning
1. Navigate to **Microsoft Intune Admin Center** → **Windows 365** → **Provisioning Policies**
2. Create/edit provisioning policy
3. Under **Image**, select **Gallery image** and choose your custom image
4. Save and assign to users
5. New Cloud PCs provision with custom image

### Hub-Spoke Networking (Optional)
- Build VMs can peer with hub VNet for enterprise connectivity
- Set `hubVnetId` parameter in deployment
- Useful for domain join during image build
- Supports hybrid identity scenarios

### CI/CD Integration
```powershell
# Automation-friendly example
.\Deploy-W365CustomImage.ps1 `
    -TenantId $env:AZURE_TENANT_ID `
    -SubscriptionId $env:AZURE_SUBSCRIPTION_ID `
    -StudentNumber $env:STUDENT_NUMBER `
    -Force
```

## Common Use Cases

### Training Lab Setup
1. **Students**: Each student logs in as `admin{N}@domain.ca`
2. **Students**: Run `Deploy-W365CustomImage.ps1 -StudentNumber {N}`
3. **Students**: Use resulting image in Windows 365 provisioning


### Custom Image Development
1. Deploy base image with standard apps
2. Modify `Invoke-W365ImageCustomization.ps1` for additional apps
3. Test deployment in isolated resource group
4. Use image for production Cloud PC provisioning

### Multi-Tenant Service Provider
1. Guest admin has access to multiple customer tenants
2. Use `-TenantId` parameter to specify target tenant
3. Build custom images per customer requirements
4. Maintain separation between customer environments

## Troubleshooting Resources

| Issue | Resource |
|-------|----------|
| Permission errors | `check-W365permissions.ps1` |
| Build VM logs | `Get-W365CustomizationLog.ps1` |
| Resource conflicts | `Remove-W365RG.ps1` (cleanup) |
| Tenant authentication | `Deploy-W365CustomImage.ps1 -Force` |
| Detailed guidance | `CustomImageGuide.md` |

## Quick Links

- **[README.md](README.md)** - Getting started and detailed documentation
- **[QUICKSTART.md](QUICKSTART.md)** - Fast track guide for experienced users
- **[CustomImageGuide.md](CustomImageGuide.md)** - Comprehensive how-to guide
- **[SPECIFICATION.md](SPECIFICATION.md)** - Technical specifications and requirements
- **[PERMISSIONS-AND-RESTRICTIONS.md](PERMISSIONS-AND-RESTRICTIONS.md)** - RBAC and security policies

## Support & Contributions

This solution is designed for the **TechMentor Orlando 2025 Windows 365 Lab**. For issues or questions:
1. Check existing documentation files
2. Review PowerShell script help (e.g., `Get-Help .\Deploy-W365CustomImage.ps1 -Full`)
3. Examine log files in Documents folder
4. Run validation scripts (`check-W365permissions.ps1`)

---

**Solution Version**: 2.1
**Last Updated**: January 2026
**Target Platform**: Windows 365 Enterprise
**Azure Region**: South Central US (default)
