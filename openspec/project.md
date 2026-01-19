# Project Context

## Purpose
Automated deployment solution for Windows 365 custom images using Azure Managed Images (Gen 2). Designed for **multi-student training labs** (e.g., TechMentor Orlando 2025) where each student builds and tests their own custom images in isolated environments. The solution:

- Deploys a Gen 2 Windows 11 VM with Cloud PC-optimized image
- Installs applications via Winget (VSCode, Chrome, 7-Zip, Adobe Reader)
- Installs Microsoft 365 Apps via Chocolatey (Word, Excel, PowerPoint, Outlook, OneNote, Teams)
- Configures Windows settings and optimizations
- Runs Windows 365-compliant sysprep
- Captures the VM as a managed image for Cloud PC provisioning
- Cleans up temporary resources automatically

## Tech Stack
- **PowerShell 5.1+** (PowerShell 7+ recommended) - Main scripting language
- **Azure Bicep** - Infrastructure as Code templates
- **Azure PowerShell Modules** - Az.Accounts, Az.Resources, Az.Compute, Az.Network, Az.ManagedServiceIdentity
- **Winget** - Microsoft's native Windows package manager for common applications (pre-installed on Windows 11)
- **Chocolatey** - Windows package manager for Microsoft 365 Apps (via Office Deployment Tool)
- **Azure Resource Manager (ARM)** - Resource deployment
- **PSWindowsUpdate** - Windows Update automation module

## Project Conventions

### Code Style
- **PowerShell scripts**: Use `[CmdletBinding()]` with proper parameter blocks
- **Strict mode**: All scripts set `$ErrorActionPreference = "Stop"` and `Set-StrictMode -Version Latest`
- **Comment-based help**: Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, and `.EXAMPLE` blocks
- **Logging**: Use `Write-Log` function with levels (Info, Warning, Error, Success) and color-coded console output
- **Naming conventions**:
  - Scripts: `Verb-W365Noun.ps1` (e.g., `Deploy-W365CustomImage.ps1`, `Invoke-W365Sysprep.ps1`)
  - Resources: `{prefix}-{purpose}-{suffix}` (e.g., `w365-imagebuilder-identity`, `rg-w365-customimage-student5`)
  - Variables: `$camelCase` for local, `$PascalCase` for parameters

### Architecture Patterns
- **Modular scripts**: Separation of concerns (deployment, customization, sysprep, cleanup)
- **Orchestration pattern**: Main script (`Deploy-W365CustomImage.ps1`) coordinates subsidiary scripts
- **Azure Run Command**: Execute customization scripts remotely on build VMs
- **Bicep for IaC**: Infrastructure defined declaratively, deployed via `New-AzResourceGroupDeployment`
- **Managed Identity**: User-assigned identity with Contributor role scoped to resource group
- **Multi-student isolation**: Each student gets unique resource group, VNet, and managed identity (StudentNumber 1-40)

### Testing Strategy
- **Validation scripts**: `check-W365permissions.ps1` validates RBAC configuration before deployment
- **Comprehensive logging**: All operations logged to `Documents\W365Customimage-YYYY-MM-DD-HH-MM.log`
- **VM logs**: Customization and sysprep logs stored on VM at `C:\Windows\Temp\`
- **Manual verification**: Use `Get-AzImage` to verify managed image creation
- **Troubleshooting tools**: `Get-W365CustomizationLog.ps1`, `Get-DeploymentError.ps1`

### Git Workflow
- **Main branch**: `main` is the primary branch
- **Commit style**: Descriptive commit messages explaining what changed and why
- **Documentation**: Update `SPECIFICATION.md` version history when making changes

## Domain Context
- **Windows 365**: Microsoft's Cloud PC service that provisions Windows desktops in Azure
- **Cloud PC Optimized (CPC) images**: Windows 11 SKUs optimized for Windows 365 (e.g., `win11-25h2-ent-cpc`)
- **Sysprep**: Windows tool that generalizes an image by removing system-specific information; required for creating reusable images
- **Generation 2 VMs**: UEFI-based VMs required for Windows 365 compatibility
- **Managed Images**: Azure resource containing a generalized VM disk; used as source for Cloud PC provisioning
- **Provisioning Policies**: Intune configuration that defines how Cloud PCs are created, including which image to use
- **Azure Run Command**: Feature to execute scripts on Azure VMs without RDP/SSH access

## Important Constraints
- **Azure quotas**: Standard_D4s_v3 VMs (4 vCPUs per student), public IPs, managed disks
- **Windows 365 compliance**: Images must be Gen 2, sysprep'd with `/generalize /oobe /shutdown`
- **Region-specific**: Managed images don't replicate; must deploy in same region as network connection
- **Multi-tenant support**: Must handle guest admin scenarios with MFA
- **Student isolation**: 40 concurrent students maximum without IP address conflicts
- **Build time**: 30-60 minutes per image build (fully automated)

## External Dependencies
- **Azure Resource Providers**: Microsoft.Compute, Microsoft.Network, Microsoft.Storage, Microsoft.ManagedIdentity
- **Winget**: Microsoft's native package manager (pre-installed on Windows 11) - for common applications
- **Chocolatey**: https://community.chocolatey.org/packages - package repository for Microsoft 365 Apps installation
- **Windows Update**: PSWindowsUpdate module for automated patching
- **Microsoft Intune**: For creating Windows 365 provisioning policies with custom images
- **Azure Marketplace**: Windows 11 Enterprise CPC images from MicrosoftWindowsDesktop publisher
