# Windows 365 Custom Image - Minimum Permissions & Resource Restrictions

This document outlines the absolute minimum permissions required for administrators to deploy the Custom Image solution and recommended restrictions to limit resource sprawl and costs.

---

## Minimum Required Permissions

### Approach 1: Custom Role (Most Restrictive - Recommended)

Deploy the custom role definition for least-privilege access:

```powershell
# Create custom role scoped to specific resource group
$subscriptionId = "your-subscription-id"
$roleDefinition = Get-Content "CustomImage-MinimumRole.json" | ConvertFrom-Json
$roleDefinition.AssignableScopes[0] = "/subscriptions/$subscriptionId/resourceGroups/rg-w365-customimage"

# Create the custom role
New-AzRoleDefinition -InputFile "CustomImage-MinimumRole.json"

# Assign to user
New-AzRoleAssignment `
    -SignInName "admin@contoso.com" `
    -RoleDefinitionName "Windows 365 Custom Image Builder" `
    -ResourceGroupName "rg-w365-customimage"
```

**Permissions Included:**
- ✅ Create/manage VMs, images, disks, networking
- ✅ Create managed identities and role assignments (within RG only)
- ✅ Deploy Bicep templates
- ❌ Cannot affect resources outside designated RG
- ❌ Cannot modify subscription-level settings
- ❌ Cannot access other resource groups

---

### Approach 2: Built-in Roles (Simpler, Less Restrictive)

If custom roles aren't feasible, use these built-in roles **scoped to a single resource group**:

```powershell
$rgName = "rg-w365-customimage"
$adminUser = "admin@contoso.com"

# Contributor - for resource creation/management
New-AzRoleAssignment `
    -SignInName $adminUser `
    -RoleDefinitionName "Contributor" `
    -ResourceGroupName $rgName

# User Access Administrator - for managed identity role assignments
New-AzRoleAssignment `
    -SignInName $adminUser `
    -RoleDefinitionName "User Access Administrator" `
    -ResourceGroupName $rgName
```

**⚠️ Important:** Always scope to resource group, never subscription level.

---

### Resource Provider Registration

**One-time setup** (requires Subscription-level permissions):

```powershell
# Pre-register providers (done by subscription admin)
Register-AzResourceProvider -ProviderNamespace Microsoft.Compute
Register-AzResourceProvider -ProviderNamespace Microsoft.Network
Register-AzResourceProvider -ProviderNamespace Microsoft.Storage
Register-AzResourceProvider -ProviderNamespace Microsoft.ManagedIdentity
```

If administrators cannot register providers, these must be pre-registered by a subscription owner.

---

## Resource Restrictions & Limits

### 1. Azure Policy - Restrict VM SKUs

Prevent expensive VM SKUs from being deployed:

**Policy: Allowed VM SKUs**

```powershell
# Define allowed VM sizes
$allowedSKUs = @(
    'Standard_D2s_v3',
    'Standard_D4s_v3',
    'Standard_D8s_v3'
)

# Create policy assignment
$policyDef = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Allowed virtual machine size SKUs' }

New-AzPolicyAssignment `
    -Name 'restrict-customimage-vm-skus' `
    -DisplayName 'Custom Image: Allowed VM SKUs' `
    -Scope "/subscriptions/$subscriptionId/resourceGroups/rg-w365-customimage" `
    -PolicyDefinition $policyDef `
    -PolicyParameter @{
        listOfAllowedSKUs = @{ value = $allowedSKUs }
    }
```

---

### 2. Azure Policy - Restrict Regions

Limit deployments to specific Azure regions:

```powershell
$allowedLocations = @('eastus', 'westus3', 'southcentralus')

$policyDef = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Allowed locations' }

New-AzPolicyAssignment `
    -Name 'restrict-customimage-locations' `
    -DisplayName 'Custom Image: Allowed Regions' `
    -Scope "/subscriptions/$subscriptionId/resourceGroups/rg-w365-customimage" `
    -PolicyDefinition $policyDef `
    -PolicyParameter @{
        listOfAllowedLocations = @{ value = $allowedLocations }
    }
```

---

### 3. Azure Policy - Require Tags

Enforce tagging for cost tracking:

```json
{
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Compute/virtualMachines"
        },
        {
          "field": "tags['CostCenter']",
          "exists": "false"
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  }
}
```

Apply with:

```powershell
New-AzPolicyAssignment `
    -Name 'require-costcenter-tag' `
    -DisplayName 'Custom Image: Require CostCenter Tag' `
    -Scope "/subscriptions/$subscriptionId/resourceGroups/rg-w365-customimage" `
    -PolicyDefinition $policyDef
```

---

### 4. Resource Quotas

Set hard limits on resource counts:

**Subscription-level quotas (requires support ticket):**
- Max Standard_D4s_v3 VMs: 2 per region
- Max vCPU count: 16 per region
- Max Public IPs: 5 per region
- Max managed disks: 10 per region

**Request quota via Azure Portal:**
1. Navigate to **Subscriptions** → **Usage + quotas**
2. Filter to region and resource type
3. Click **Request increase** and set limits

---

### 5. Budget Alerts

Create budget to prevent cost overruns:

```powershell
# Create budget for the resource group
$budgetScope = "/subscriptions/$subscriptionId/resourceGroups/rg-w365-customimage"

$budget = @{
    name = "customimage-monthly-budget"
    amount = 100  # $100 USD per month
    timeGrain = "Monthly"
    timePeriod = @{
        startDate = (Get-Date).ToString("yyyy-MM-01")
        endDate = "2026-12-31"
    }
    category = "Cost"
    notifications = @{
        "Actual_80_Percent" = @{
            enabled = $true
            operator = "GreaterThan"
            threshold = 80
            contactEmails = @("admin@contoso.com")
            thresholdType = "Actual"
        }
        "Actual_100_Percent" = @{
            enabled = $true
            operator = "GreaterThan"
            threshold = 100
            contactEmails = @("admin@contoso.com", "finance@contoso.com")
            thresholdType = "Actual"
        }
    }
}

# Use Azure CLI (Az PowerShell doesn't support budget creation)
az consumption budget create `
    --budget-name "customimage-monthly-budget" `
    --amount 100 `
    --time-grain Monthly `
    --start-date (Get-Date).ToString("yyyy-MM-01") `
    --end-date "2026-12-31" `
    --resource-group "rg-w365-customimage"
```

---

### 6. Resource Locks

Protect persistent resources from accidental deletion:

```powershell
# Lock the resource group (delete protection)
New-AzResourceLock `
    -LockName "prevent-rg-deletion" `
    -LockLevel CanNotDelete `
    -ResourceGroupName "rg-w365-customimage" `
    -LockNotes "Prevents accidental deletion of custom image infrastructure"

# Lock VNet specifically (read-only)
New-AzResourceLock `
    -LockName "vnet-readonly" `
    -LockLevel ReadOnly `
    -ResourceName "w365-image-vnet" `
    -ResourceType "Microsoft.Network/virtualNetworks" `
    -ResourceGroupName "rg-w365-customimage" `
    -LockNotes "VNet should not be modified"
```

**⚠️ Note:** Admin must remove locks before deleting resources. Use `CanNotDelete` instead of `ReadOnly` to allow modifications.

---

### 7. Network Restrictions

Limit network exposure:

**Option A: Remove Public IP requirement** (modify `customimage.bicep`):
- Use Azure Bastion or Azure Run Command exclusively
- No Public IP resource = lower attack surface

**Option B: NSG restrictive rules** (already implemented):
- Outbound to Azure Cloud and Internet only
- No inbound rules (VM uses Azure Run Command, not RDP)

---

### 8. Enforce Resource Naming Convention

Use Azure Policy to enforce naming standards:

```json
{
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Compute/virtualMachines"
        },
        {
          "not": {
            "field": "name",
            "like": "w365-*"
          }
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  }
}
```

---

## Permission Summary Matrix

| Operation | Custom Role | Contributor + UAA | Subscription Admin |
|-----------|-------------|-------------------|-------------------|
| **Deploy infrastructure** | ✅ (RG-scoped) | ✅ (RG-scoped) | ✅ |
| **Register resource providers** | ❌ (pre-register) | ❌ (pre-register) | ✅ |
| **Create managed identity** | ✅ | ✅ | ✅ |
| **Assign RBAC roles** | ✅ (within RG) | ✅ (within RG) | ✅ |
| **Create/delete VMs** | ✅ | ✅ | ✅ |
| **Capture managed images** | ✅ | ✅ | ✅ |
| **Access other RGs** | ❌ | ❌ | ✅ |
| **Modify subscription settings** | ❌ | ❌ | ✅ |

---

## Cost & Resource Constraints Summary

### Per Image Build
- **VM Size:** Standard_D4s_v3 (4 vCPU, 16 GB RAM)
- **VM Runtime:** ~30-60 minutes
- **Storage:** 128 GB Premium SSD (temporary)
- **Network:** 1 Standard Public IP (temporary)
- **Cost:** ~$0.40-0.70 per build

### Persistent Resources
- **VNet:** 10.100.0.0/16 with single /24 subnet
- **NSG:** Basic outbound rules only
- **Managed Identity:** 1 per resource group
- **Images:** ~5-10 GB each (minimal ongoing cost)

### Recommended Limits
- **Max concurrent builds:** 1
- **Max images retained:** 5-10
- **Max monthly cost:** $50-100
- **Build frequency:** Weekly or on-demand

---

## Deployment Checklist

### 1. Pre-deployment (Subscription Admin)
- [ ] Pre-register resource providers
- [ ] Create dedicated resource group: `rg-w365-customimage`
- [ ] Apply Azure Policies (VM SKU, region, tagging)
- [ ] Set resource quotas
- [ ] Create budget with alerts

### 2. Grant Permissions (IAM Admin)
- [ ] Create custom role or use Contributor + UAA
- [ ] Scope role assignment to specific resource group only
- [ ] Verify admin cannot access other resource groups

### 3. Apply Restrictions
- [ ] Apply resource locks to VNet (optional)
- [ ] Configure NSG rules (default is secure)
- [ ] Enable Activity Log alerts for high-risk operations

### 4. Validate
- [ ] Admin runs `Deploy-W365CustomImage.ps1` successfully
- [ ] Admin cannot deploy outside allowed regions
- [ ] Admin cannot deploy unauthorized VM SKUs
- [ ] Budget alerts trigger at 80% threshold
- [ ] Admin cannot delete locked resources

---

## Troubleshooting Permission Issues

### "Insufficient permissions to register resource provider"
**Solution:** Pre-register providers at subscription level, or grant `Microsoft.Resources/subscriptions/providers/register/action`

### "Authorization failed for role assignment"
**Solution:** Grant `User Access Administrator` role scoped to resource group

### "Cannot create VM with SKU 'Standard_D16s_v3'"
**Solution:** Azure Policy blocking unauthorized SKU. Update policy or use allowed SKU.

### "Quota exceeded for Standard_D4s_v3"
**Solution:** Request quota increase or wait for existing VMs to be deleted

---

## Security Best Practices

1. **Principle of Least Privilege:** Use custom role scoped to single RG
2. **Time-bound Access:** Use Azure PIM for JIT admin elevation
3. **Separation of Duties:** Different admins for deployment vs. approval
4. **Audit Logging:** Enable Activity Log and Log Analytics
5. **Regular Review:** Review role assignments quarterly
6. **MFA Required:** Enforce MFA for all administrators
7. **Conditional Access:** Restrict access to trusted networks/devices

---

## Quick Reference Commands

```powershell
# Check current permissions
Get-AzRoleAssignment -SignInName "admin@contoso.com" -ResourceGroupName "rg-w365-customimage"

# Check applied policies
Get-AzPolicyAssignment -Scope "/subscriptions/$subscriptionId/resourceGroups/rg-w365-customimage"

# Check resource locks
Get-AzResourceLock -ResourceGroupName "rg-w365-customimage"

# Check budget status
az consumption budget list --resource-group "rg-w365-customimage"

# Check resource provider registration
Get-AzResourceProvider -ProviderNamespace Microsoft.Compute | Select-Object RegistrationState

# Audit recent deployments
Get-AzResourceGroupDeployment -ResourceGroupName "rg-w365-customimage" | Select-Object DeploymentName, ProvisioningState, Timestamp
```

---

**For questions or issues, refer to the main README.md or contact your Azure administrator.**
