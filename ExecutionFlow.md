# Execution Flow - Windows 365 Custom Image Deployment

This document provides a detailed overview of all events that occur when deploying the CustomImage solution.

## High-Level Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Deploy-W365CustomImage.ps1                              │
│                        (Main Orchestrator)                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌───────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  Environment  │         │  Infrastructure │         │  Image Capture  │
│    Setup      │         │   Deployment    │         │   & Cleanup     │
│  (Steps 1-4)  │         │   (Step 5)      │         │  (Steps 8-9)    │
└───────────────┘         └─────────────────┘         └─────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │   Azure Run Command (Steps 6-7)│
                    ├───────────────────────────────┤
                    │ Invoke-W365ImageCustomization │
                    │        (5 Stages)             │
                    ├───────────────────────────────┤
                    │    Invoke-W365Sysprep         │
                    │   (Generalize + Shutdown)     │
                    └───────────────────────────────┘
```

---

## Detailed Execution Steps

### Step 1: Azure PowerShell Module Validation
**Duration**: 1-3 minutes (first run) / seconds (subsequent runs)

| Action | Description |
|--------|-------------|
| Check modules | Verify required Az modules are installed |
| Install missing | Auto-install: Az.Accounts, Az.Resources, Az.Compute, Az.Network, Az.ManagedServiceIdentity, Az.ImageBuilder |
| Import modules | Load modules into PowerShell session |

**Required Modules**:
- `Az.Accounts` - Azure authentication
- `Az.Resources` - Resource group and deployment management
- `Az.Compute` - VM and image operations
- `Az.Network` - VNet and NSG management
- `Az.ManagedServiceIdentity` - Managed identity creation
- `Az.ImageBuilder` - Image builder operations

---

### Step 1.5: Bicep CLI Validation
**Duration**: 1-2 minutes (first run) / seconds (subsequent runs)

| Action | Description |
|--------|-------------|
| Check Bicep | Verify Bicep CLI is installed |
| Install via Winget | If missing, install using `winget install Microsoft.Bicep` |
| Fallback install | Manual download from GitHub if Winget unavailable |
| Verify | Confirm `bicep --version` returns valid output |

---

### Step 2: Azure Authentication & Context
**Duration**: 30 seconds - 2 minutes (depends on MFA)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Authentication Flow                          │
├─────────────────────────────────────────────────────────────────┤
│  1. Check existing Azure context                                │
│  2. If no context → Connect-AzAccount (browser popup)           │
│  3. Enumerate accessible tenants (Get-AzTenant)                 │
│  4. Select tenant (auto if single, prompt if multiple)          │
│  5. Re-authenticate to selected tenant (handles MFA)            │
│  6. Enumerate subscriptions in tenant                           │
│  7. Select subscription (auto if single, prompt if multiple)    │
│  8. Set-AzContext with selected tenant + subscription           │
└─────────────────────────────────────────────────────────────────┘
```

**Interactive Prompts** (if applicable):
- Tenant selection (if multiple tenants accessible)
- MFA authentication (if required by tenant)
- Subscription selection (if multiple subscriptions)

---

### Step 3: Resource Provider Registration
**Duration**: 30 seconds - 2 minutes

| Provider | Purpose |
|----------|---------|
| `Microsoft.Compute` | VMs, managed images, disks |
| `Microsoft.Storage` | Storage accounts (if needed) |
| `Microsoft.Network` | VNets, NSGs, NICs, public IPs |
| `Microsoft.ManagedIdentity` | User-assigned managed identities |

**Process**: Check registration state → Register if not "Registered"

---

### Step 4: Credential Collection
**Duration**: 30 seconds (user input)

| Prompt | Description |
|--------|-------------|
| Azure Location | Select from supported regions (default: southcentralus) |
| Resource Group | Enter name (default: rg-w365-customimage-student{N}) |
| VM Credentials | Username and password for build VM |

**Note**: VM credentials are used only during build and discarded after image capture.

---

### Step 5: Infrastructure Deployment (Bicep)
**Duration**: 5-10 minutes

```
┌─────────────────────────────────────────────────────────────────┐
│                   customimage.bicep Deployment                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Resource Group                                              │
│     └─ rg-w365-customimage-student{N}                          │
│                                                                 │
│  2. Virtual Network                                             │
│     └─ w365-image-vnet-student{N}                              │
│     └─ Address space: 10.100.{N}.0/24                          │
│     └─ Subnet: imagebuilder (10.100.{N}.0/24)                  │
│                                                                 │
│  3. Network Security Group                                      │
│     └─ w365-nsg-student{N}                                     │
│     └─ Rules: Allow internet outbound for package downloads    │
│                                                                 │
│  4. User-Assigned Managed Identity                              │
│     └─ w365-imagebuilder-identity-student{N}                   │
│     └─ Role: Contributor (scoped to resource group)            │
│                                                                 │
│  5. Public IP Address (temporary)                               │
│     └─ w365-build-pip-{timestamp}                              │
│                                                                 │
│  6. Network Interface                                           │
│     └─ w365-build-nic-{timestamp}                              │
│                                                                 │
│  7. Virtual Machine (Gen 2)                                     │
│     └─ w365-build-vm-{timestamp}                               │
│     └─ Size: Standard_D4s_v3 (4 vCPU, 16 GB RAM)               │
│     └─ Image: Windows 11 25H2 Enterprise CPC                   │
│     └─ OS Disk: Premium SSD                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Outputs**:
- VM ID and Name
- Public IP Address
- VNet ID

---

### Step 6: VM Customization (Azure Run Command)
**Duration**: 15-25 minutes

The `Invoke-W365ImageCustomization.ps1` script is executed on the VM via Azure Run Command.

```
┌─────────────────────────────────────────────────────────────────┐
│              Invoke-W365ImageCustomization.ps1                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Stage 1: Application Installation (Winget)         ~5-8 min   │
│  ─────────────────────────────────────────────────────────────  │
│  │ For each package:                                           │
│  │   winget install <PackageId> --silent                       │
│  │     --accept-package-agreements --accept-source-agreements  │
│  │                                                             │
│  │ Packages:                                                   │
│  │   • 7zip.7zip (7-Zip)                                       │
│  │   • Microsoft.VisualStudioCode (VS Code)                    │
│  │   • Google.Chrome (Chrome)                                  │
│  │   • Adobe.Acrobat.Reader.64-bit (Adobe Reader)              │
│  └─────────────────────────────────────────────────────────────│
│                                                                 │
│  Stage 2: Microsoft 365 Apps (Chocolatey)           ~8-12 min  │
│  ─────────────────────────────────────────────────────────────  │
│  │ 1. Install Chocolatey (if not present)                      │
│  │    └─ Download from chocolatey.org/install.ps1              │
│  │                                                             │
│  │ 2. Install Office Deployment Tool package                   │
│  │    └─ choco install microsoft-office-deployment             │
│  │    └─ Parameters: /64bit /Product:O365ProPlusRetail         │
│  │                   /Channel:Current                          │
│  │                   /Exclude:Publisher,Groove,Access          │
│  │                                                             │
│  │ Apps Installed:                                             │
│  │   • Word, Excel, PowerPoint                                 │
│  │   • Outlook, OneNote, Teams                                 │
│  └─────────────────────────────────────────────────────────────│
│                                                                 │
│  Stage 3: Windows Configuration                     ~1-2 min   │
│  ─────────────────────────────────────────────────────────────  │
│  │ • Set timezone: Eastern Standard Time                       │
│  │ • Explorer: Show file extensions                            │
│  │ • Explorer: Show hidden files                               │
│  │ • Disable Windows tips and suggestions                      │
│  └─────────────────────────────────────────────────────────────│
│                                                                 │
│  Stage 4: Windows Update                            ~5-10 min  │
│  ─────────────────────────────────────────────────────────────  │
│  │ 1. Install NuGet package provider                           │
│  │ 2. Install PSWindowsUpdate module                           │
│  │ 3. Get-WindowsUpdate -Install -AcceptAll                    │
│  │    └─ -IgnoreReboot -NotCategory "Preview"                  │
│  └─────────────────────────────────────────────────────────────│
│                                                                 │
│  Stage 5: Optimization & Cleanup                    ~1-2 min   │
│  ─────────────────────────────────────────────────────────────  │
│  │ • Disable telemetry (registry setting)                      │
│  │ • Clean C:\Windows\Temp\*                                   │
│  │ • Clean user temp files                                     │
│  │ • Clear Windows event logs                                  │
│  └─────────────────────────────────────────────────────────────│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Log Location** (on VM): `C:\Windows\Temp\w365-customization.log`

---

### Step 7: Sysprep Execution
**Duration**: 5-15 minutes

The `Invoke-W365Sysprep.ps1` script is executed on the VM via Azure Run Command.

```
┌─────────────────────────────────────────────────────────────────┐
│                   Invoke-W365Sysprep.ps1                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Verify sysprep.exe exists                                   │
│     └─ C:\Windows\System32\Sysprep\sysprep.exe                 │
│                                                                 │
│  2. Check current VM state                                      │
│     └─ Verify not already generalized                          │
│                                                                 │
│  3. Execute sysprep                                             │
│     └─ sysprep.exe /generalize /oobe /shutdown                 │
│                                                                 │
│     Parameters:                                                 │
│     • /generalize - Remove system-specific info (SIDs, etc.)   │
│     • /oobe - Configure for Out-of-Box Experience on next boot │
│     • /shutdown - Shut down VM when complete                   │
│                                                                 │
│  4. VM automatically shuts down                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Log Location** (on VM): `C:\Windows\Temp\w365-sysprep.log`

**Post-Sysprep Monitoring**:
```
┌─────────────────────────────────────────────────────────────────┐
│  Monitor VM Power State (every 30 seconds, max 20 minutes)     │
│  ───────────────────────────────────────────────────────────── │
│  PowerState/running → PowerState/stopped → PowerState/deallocated │
└─────────────────────────────────────────────────────────────────┘
```

---

### Step 8: Image Capture
**Duration**: 5-10 minutes

```
┌─────────────────────────────────────────────────────────────────┐
│                    Image Capture Process                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Deallocate VM (if not already)                              │
│     └─ Stop-AzVM -Force                                        │
│                                                                 │
│  2. Set VM to generalized state                                 │
│     └─ Set-AzVM -Generalized                                   │
│                                                                 │
│  3. Create image configuration                                  │
│     └─ New-AzImageConfig                                       │
│     └─ -HyperVGeneration 'V2' (Gen 2 required for W365)        │
│     └─ -SourceVirtualMachineId $vm.Id                          │
│                                                                 │
│  4. Create managed image                                        │
│     └─ New-AzImage                                             │
│     └─ Name: w365-custom-image-student{N}-{timestamp}          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Image Properties**:
- **Type**: Azure Managed Image
- **Generation**: 2 (Hyper-V Gen 2, UEFI boot)
- **Region**: Same as deployment location

---

### Step 9: Resource Cleanup
**Duration**: 2-3 minutes

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cleanup Operations                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DELETED (temporary resources):                                 │
│  ├─ Virtual Machine (w365-build-vm-{timestamp})                │
│  ├─ OS Disk (attached to VM)                                   │
│  ├─ Public IP (w365-build-pip-{timestamp})                     │
│  └─ Network Interface (w365-build-nic-{timestamp})             │
│                                                                 │
│  RETAINED (for future builds):                                  │
│  ├─ Resource Group                                              │
│  ├─ Virtual Network                                             │
│  ├─ Network Security Group                                      │
│  ├─ Managed Identity                                            │
│  └─ Managed Image ← THE OUTPUT                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Complete Timeline

| Phase | Step | Duration | Cumulative |
|-------|------|----------|------------|
| Setup | 1. Module validation | 0-3 min | 3 min |
| Setup | 1.5. Bicep CLI | 0-2 min | 5 min |
| Setup | 2. Azure auth | 0.5-2 min | 7 min |
| Setup | 3. Resource providers | 0.5-2 min | 9 min |
| Setup | 4. Credentials | 0.5 min | 10 min |
| Deploy | 5. Infrastructure | 5-10 min | 20 min |
| Deploy | (VM boot wait) | 2 min | 22 min |
| Customize | 6. Customization | 15-25 min | 47 min |
| Capture | 7. Sysprep | 5-15 min | 62 min |
| Capture | 8. Image capture | 5-10 min | 72 min |
| Cleanup | 9. Cleanup | 2-3 min | 75 min |

**Total**: 30-75 minutes (typical: 45-60 minutes)

---

## Logging

All operations are logged to:
```
%USERPROFILE%\Documents\W365Customimage-YYYY-MM-DD-HH-MM.log
```

**Log Format**:
```
[2026-01-18 14:30:00] [Info] Step 5: Deploying infrastructure...
[2026-01-18 14:35:00] [Success] Infrastructure deployment completed
[2026-01-18 14:35:00] [Error] Deployment failed: <error message>
```

**Log Levels**:
- `[Info]` - Informational messages (cyan)
- `[Success]` - Successful operations (green)
- `[Warning]` - Non-fatal issues (yellow)
- `[Error]` - Fatal errors (red)

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Module install fails | Script stops with error |
| Azure auth fails | Script stops, suggests manual login |
| Bicep deployment fails | Detailed error output, script stops |
| Customization fails | Warning logged, continues to sysprep |
| Sysprep fails | Script stops (VM may need manual cleanup) |
| Image capture fails | Script stops, VM retained for debugging |

---

## Post-Deployment

After successful completion:

1. **Verify Image**:
   ```powershell
   Get-AzImage -ResourceGroupName 'rg-w365-customimage-student1'
   ```

2. **Check Windows 365 Permissions**:
   ```powershell
   .\check-W365permissions.ps1
   ```

3. **Use in Provisioning Policy**:
   - Microsoft Intune Admin Center → Windows 365 → Provisioning Policies
   - Select "Custom image" → Choose your managed image
