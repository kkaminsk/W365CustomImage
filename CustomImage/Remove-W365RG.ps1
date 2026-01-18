<#
.SYNOPSIS
    Removes Windows 365 Custom Image infrastructure and resources

.DESCRIPTION
    This script safely removes all resources created by Deploy-W365CustomImage.ps1:
    - Azure VM Image Builder template
    - Azure Compute Gallery and Image Definition
    - User-Assigned Managed Identity and role assignments
    - Virtual Network and Subnet
    - Resource Group
    
    Supports multi-tenant scenarios for administrators with guest access to multiple tenants.
    
    All operations are logged to Documents folder as W365CustomimageRemoval-YYYY-MM-DD-HH-MM.log
    
    The script will interactively prompt for:
    - Azure Tenant (if multiple accessible)
    - Azure Subscription (if multiple in tenant)
    - Resource Group to remove

.EXAMPLE
    .\Remove-W365RG.ps1
    .\Remove-W365RG.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    .\Remove-W365RG.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -SubscriptionId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId
)

# Set strict error handling
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Initialize logging
$timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm"
$logPath = Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "W365CustomimageRemoval-$timestamp.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to log file
    Add-Content -Path $logPath -Value $logMessage
}

# Function to select tenant and establish context
function Select-AzureTenantContext {
    param(
        [string]$TenantId,
        [string]$SubscriptionId
    )
    
    Write-Host "`nChecking Azure login status..." -ForegroundColor Cyan
    
    try {
        # Ensure user is authenticated
        $context = Get-AzContext
        if (!$context) {
            Write-Host "Not logged in to Azure. Initiating login..." -ForegroundColor Yellow
            Connect-AzAccount
            $context = Get-AzContext
        }
        
        Write-Host "Logged in as: $($context.Account.Id)" -ForegroundColor Green
        
        # Get all available tenants
        Write-Host "`nRetrieving available tenants..." -ForegroundColor Cyan
        $tenants = Get-AzTenant
        
        if ($tenants.Count -eq 0) {
            Write-Host "No accessible tenants found." -ForegroundColor Red
            return $false
        }
        
        # Select tenant
        $selectedTenant = $null
        
        if ($TenantId) {
            # Use explicitly specified tenant
            $selectedTenant = $tenants | Where-Object { $_.Id -eq $TenantId }
            if (!$selectedTenant) {
                Write-Host "Specified tenant ID '$TenantId' not found or not accessible." -ForegroundColor Red
                return $false
            }
            Write-Host "Using specified tenant: $($selectedTenant.Name) ($($selectedTenant.Id))" -ForegroundColor Green
            
            # Re-authenticate to ensure proper access
            Write-Host "`nAuthenticating to tenant..." -ForegroundColor Cyan
            try {
                Connect-AzAccount -TenantId $selectedTenant.Id -ErrorAction Stop | Out-Null
                Write-Host "Successfully authenticated to tenant." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to authenticate to tenant: $_" -ForegroundColor Red
                Write-Host "Please ensure you have access to this tenant and complete any required MFA." -ForegroundColor Yellow
                return $false
            }
        }
        elseif ($tenants.Count -eq 1) {
            # Only one tenant available, use it automatically
            $selectedTenant = $tenants[0]
            Write-Host "Using tenant: $($selectedTenant.Name) ($($selectedTenant.Id))" -ForegroundColor Green
            
            # Re-authenticate to ensure proper access
            Write-Host "`nAuthenticating to tenant..." -ForegroundColor Cyan
            try {
                Connect-AzAccount -TenantId $selectedTenant.Id -ErrorAction Stop | Out-Null
                Write-Host "Successfully authenticated to tenant." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to authenticate to tenant: $_" -ForegroundColor Red
                Write-Host "Please ensure you have access to this tenant and complete any required MFA." -ForegroundColor Yellow
                return $false
            }
        }
        else {
            # Multiple tenants available, prompt for selection
            Write-Host "`nAvailable Tenants:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $tenants.Count; $i++) {
                $tenant = $tenants[$i]
                Write-Host "  [$($i + 1)] $($tenant.Name) ($($tenant.Id))" -ForegroundColor White
            }
            
            do {
                $selection = Read-Host "`nSelect tenant number (1-$($tenants.Count))"
                $selectionIndex = [int]$selection - 1
            } while ($selectionIndex -lt 0 -or $selectionIndex -ge $tenants.Count)
            
            $selectedTenant = $tenants[$selectionIndex]
            Write-Host "Selected tenant: $($selectedTenant.Name) ($($selectedTenant.Id))" -ForegroundColor Green
        }
        
        # Re-authenticate to the selected tenant to ensure proper access (MFA, etc.)
        Write-Host "`nAuthenticating to tenant..." -ForegroundColor Cyan
        try {
            Connect-AzAccount -TenantId $selectedTenant.Id -ErrorAction Stop | Out-Null
            Write-Host "Successfully authenticated to tenant." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to authenticate to tenant: $_" -ForegroundColor Red
            Write-Host "Please ensure you have access to this tenant and complete any required MFA." -ForegroundColor Yellow
            return $false
        }
        
        # Get subscriptions in selected tenant
        Write-Host "`nRetrieving subscriptions in tenant..." -ForegroundColor Cyan
        
        $subscriptions = @()
        try {
            $subscriptions = @(Get-AzSubscription -TenantId $selectedTenant.Id -WarningAction SilentlyContinue -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" })
        }
        catch {
            $errorMessage = $_.Exception.Message
            
            # Check if this is an authentication/MFA error
            if ($errorMessage -match "Authentication failed|User interaction is required|multi-factor authentication") {
                Write-Host "`nAuthentication required for tenant '$($selectedTenant.Name)'." -ForegroundColor Yellow
                Write-Host "This tenant requires additional authentication (possibly MFA)." -ForegroundColor Yellow
                Write-Host "`nTo access this tenant, please run:" -ForegroundColor Cyan
                Write-Host "  Connect-AzAccount -TenantId $($selectedTenant.Id)" -ForegroundColor White
                Write-Host "Then run this script again with:" -ForegroundColor Cyan
                Write-Host "  .\Remove-W365RG.ps1 -TenantId $($selectedTenant.Id)" -ForegroundColor White
                return $false
            }
            else {
                Write-Host "Failed to retrieve subscriptions: $errorMessage" -ForegroundColor Red
                return $false
            }
        }
        
        if ($subscriptions.Count -eq 0) {
            Write-Host "No accessible subscriptions found in tenant '$($selectedTenant.Name)'." -ForegroundColor Red
            Write-Host "Please ensure you have appropriate access permissions." -ForegroundColor Yellow
            return $false
        }
        
        # Select subscription
        $selectedSubscription = $null
        
        if ($SubscriptionId) {
            # Use explicitly specified subscription
            $selectedSubscription = $subscriptions | Where-Object { $_.Id -eq $SubscriptionId }
            if (!$selectedSubscription) {
                Write-Host "Specified subscription ID '$SubscriptionId' not found in tenant." -ForegroundColor Red
                return $false
            }
            Write-Host "Using specified subscription: $($selectedSubscription.Name) ($($selectedSubscription.Id))" -ForegroundColor Green
        }
        elseif ($subscriptions.Count -eq 1) {
            # Only one subscription available, use it automatically
            $selectedSubscription = $subscriptions[0]
            Write-Host "Using subscription: $($selectedSubscription.Name) ($($selectedSubscription.Id))" -ForegroundColor Green
        }
        else {
            # Multiple subscriptions available, prompt for selection
            Write-Host "`nAvailable Subscriptions:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $subscriptions.Count; $i++) {
                $sub = $subscriptions[$i]
                Write-Host "  [$($i + 1)] $($sub.Name) ($($sub.Id))" -ForegroundColor White
            }
            
            do {
                $selection = Read-Host "`nSelect subscription number (1-$($subscriptions.Count))"
                $selectionIndex = [int]$selection - 1
            } while ($selectionIndex -lt 0 -or $selectionIndex -ge $subscriptions.Count)
            
            $selectedSubscription = $subscriptions[$selectionIndex]
            Write-Host "Selected subscription: $($selectedSubscription.Name) ($($selectedSubscription.Id))" -ForegroundColor Green
        }
        
        # Set Azure context to selected tenant and subscription
        Write-Host "`nSwitching to selected context..." -ForegroundColor Cyan
        $newContext = Set-AzContext -TenantId $selectedTenant.Id -SubscriptionId $selectedSubscription.Id
        
        if (!$newContext) {
            Write-Host "Failed to set Azure context." -ForegroundColor Red
            return $false
        }
        
        # Confirm context
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  Active Azure Context" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Account:      $($newContext.Account.Id)" -ForegroundColor White
        Write-Host "Tenant:       $($newContext.Tenant.Id)" -ForegroundColor White
        Write-Host "Subscription: $($newContext.Subscription.Name)" -ForegroundColor White
        Write-Host "              $($newContext.Subscription.Id)" -ForegroundColor White
        Write-Host "========================================" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Host "Failed to establish Azure context: $_" -ForegroundColor Red
        return $false
    }
}

function Select-ResourceGroup {
    Write-Host "`n=== Resource Group Selection ===" -ForegroundColor Cyan
    
    # Get resource groups that match W365 custom image pattern
    $allResourceGroups = Get-AzResourceGroup | Where-Object { 
        $_.ResourceGroupName -like "*w365*customimage*" -or 
        $_.ResourceGroupName -like "rg-w365-*" 
    } | Sort-Object ResourceGroupName
    
    if ($allResourceGroups.Count -eq 0) {
        Write-Log "No W365 custom image resource groups found. Showing all resource groups..." -Level Warning
        $allResourceGroups = Get-AzResourceGroup | Sort-Object ResourceGroupName
    }
    
    if ($allResourceGroups.Count -eq 0) {
        throw "No resource groups found in this subscription."
    }
    
    Write-Host "`nAvailable resource groups:" -ForegroundColor White
    for ($i = 0; $i -lt $allResourceGroups.Count; $i++) {
        $rg = $allResourceGroups[$i]
        Write-Host "  [$($i + 1)] $($rg.ResourceGroupName) - Location: $($rg.Location)" -ForegroundColor Gray
    }
    Write-Host "  [$($allResourceGroups.Count + 1)] ⚠️  DELETE ALL RESOURCE GROUPS IN SUBSCRIPTION ⚠️" -ForegroundColor Red
    
    do {
        $selection = Read-Host "`nSelect resource group number [1-$($allResourceGroups.Count + 1)]"
        $index = $selection -as [int]
    } while ($index -lt 1 -or $index -gt ($allResourceGroups.Count + 1))
    
    # Check if user selected "delete all" option
    if ($index -eq ($allResourceGroups.Count + 1)) {
        return "DELETE_ALL"
    }
    
    return $allResourceGroups[$index - 1]
}

# ============================================================================
# Main Script
# ============================================================================

try {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Windows 365 Custom Image Infrastructure Removal Script       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    Write-Log "Starting W365 Custom Image infrastructure removal process"
    Write-Log "Log file: $logPath"
    
    # Step 1: Check and install required modules
    Write-Log "Checking required Azure PowerShell modules..."
    
    $requiredModules = @(
        'Az.Accounts',
        'Az.Resources',
        'Az.Compute',
        'Az.Network',
        'Az.ManagedServiceIdentity',
        'Az.ImageBuilder'
    )
    
    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            Write-Log "Installing module: $moduleName" -Level Warning
            Install-Module -Name $moduleName -Repository PSGallery -Force -AllowClobber -Scope CurrentUser
        }
        Import-Module $moduleName -Force
    }
    
    Write-Log "All required modules are available" -Level Success
    
    # Step 2: Establish Azure context
    Write-Log "Establishing Azure context..."
    
    if (!(Select-AzureTenantContext -TenantId $TenantId -SubscriptionId $SubscriptionId)) {
        throw "Failed to establish Azure context. Please check your permissions and try again."
    }
    
    $context = Get-AzContext
    Write-Log "Azure context established successfully" -Level Success
    Write-Log "  Account: $($context.Account.Id)" -Level Info
    Write-Log "  Tenant: $($context.Tenant.Id)" -Level Info
    Write-Log "  Subscription: $($context.Subscription.Name)" -Level Info
    
    # Step 4: Select resource group
    $selectedResourceGroup = Select-ResourceGroup
    
    # Check if user selected "DELETE ALL" option
    $deleteAll = $false
    if ($selectedResourceGroup -eq "DELETE_ALL") {
        $deleteAll = $true
        $allResourceGroups = Get-AzResourceGroup | Sort-Object ResourceGroupName
        Write-Log "User selected to DELETE ALL resource groups in subscription" -Level Warning
    } else {
        $resourceGroupName = $selectedResourceGroup.ResourceGroupName
        Write-Log "Selected resource group: $resourceGroupName" -Level Success
    }
    
    # Step 5: Confirm deletion
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                    ⚠️  WARNING  ⚠️                              ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    if ($deleteAll) {
        Write-Host "`nYou are about to DELETE ALL RESOURCE GROUPS in:" -ForegroundColor Red
        Write-Host "  • Subscription: $($context.Subscription.Name)" -ForegroundColor White
        Write-Host "  • Subscription ID: $($context.Subscription.Id)" -ForegroundColor White
        Write-Host "`nThis will remove ALL $($allResourceGroups.Count) resource groups including:" -ForegroundColor Red
        foreach ($rg in $allResourceGroups) {
            Write-Host "  - $($rg.ResourceGroupName) ($($rg.Location))" -ForegroundColor Gray
        }
        Write-Host "`nThis action CANNOT be undone!`n" -ForegroundColor Red
        Write-Host "⚠️  THIS WILL DELETE EVERYTHING IN THE SUBSCRIPTION! ⚠️`n" -ForegroundColor Red
        
        $confirmation = Read-Host "Type 'DELETE-ALL-RESOURCE-GROUPS' to confirm complete removal"
        
        if ($confirmation -ne 'DELETE-ALL-RESOURCE-GROUPS') {
            Write-Log "Removal cancelled by user" -Level Warning
            Write-Host "`nRemoval cancelled. No changes were made." -ForegroundColor Yellow
            exit 0
        }
    } else {
        Write-Host "`nYou are about to DELETE the following:" -ForegroundColor Yellow
        Write-Host "  • Resource Group: $resourceGroupName" -ForegroundColor White
        Write-Host "  • Subscription: $($context.Subscription.Name)" -ForegroundColor White
        Write-Host "  • Location: $($selectedResourceGroup.Location)" -ForegroundColor White
        Write-Host "`nThis will remove ALL resources in this resource group including:" -ForegroundColor Yellow
        Write-Host "  - Image Builder templates" -ForegroundColor Gray
        Write-Host "  - Compute Gallery and images" -ForegroundColor Gray
        Write-Host "  - Virtual networks" -ForegroundColor Gray
        Write-Host "  - Managed identities" -ForegroundColor Gray
        Write-Host "  - All other resources" -ForegroundColor Gray
        Write-Host "`nThis action CANNOT be undone!`n" -ForegroundColor Red
        
        $confirmation = Read-Host "Type 'DELETE' to confirm removal"
        
        if ($confirmation -ne 'DELETE') {
            Write-Log "Removal cancelled by user" -Level Warning
            Write-Host "`nRemoval cancelled. No changes were made." -ForegroundColor Yellow
            exit 0
        }
    }
    
    Write-Log "User confirmed deletion" -Level Warning
    
    if ($deleteAll) {
        # Delete ALL resource groups in subscription
        Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║        Deleting ALL Resource Groups in Subscription           ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Red
        
        $totalRGs = $allResourceGroups.Count
        $currentRG = 0
        
        foreach ($rg in $allResourceGroups) {
            $currentRG++
            Write-Log "[$currentRG/$totalRGs] Removing resource group: $($rg.ResourceGroupName)" -Level Warning
            Write-Host "`n[$currentRG/$totalRGs] Removing: $($rg.ResourceGroupName)..." -ForegroundColor Yellow
            
            try {
                # Check for Image Builder templates in this RG
                $imageTemplates = Get-AzImageBuilderTemplate -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
                if ($imageTemplates) {
                    foreach ($template in $imageTemplates) {
                        Write-Log "  Removing Image Builder template: $($template.Name)" -Level Warning
                        Remove-AzImageBuilderTemplate -ResourceGroupName $rg.ResourceGroupName -Name $template.Name -ErrorAction SilentlyContinue
                    }
                }
                
                # Remove the resource group
                Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force -AsJob | Out-Null
                Write-Log "  Resource group removal job started: $($rg.ResourceGroupName)" -Level Success
            }
            catch {
                Write-Log "  Failed to remove resource group $($rg.ResourceGroupName): $($_.Exception.Message)" -Level Error
            }
        }
        
        Write-Host "`nAll resource group removal jobs have been started." -ForegroundColor Yellow
        Write-Host "Deletions are running in the background and may take several minutes to complete." -ForegroundColor Yellow
        
        # Summary
        Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║         ✅ All Resource Group Deletions Initiated              ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
        
        Write-Log "=== Removal Summary ===" -Level Success
        Write-Log "Total Resource Groups: $totalRGs" -Level Success
        Write-Log "All resource group deletions have been initiated" -Level Success
        Write-Log "Deletions are running as background jobs" -Level Info
        Write-Log "Log file saved to: $logPath" -Level Info
        
    } else {
        # Delete single resource group
        # Step 6: Remove Image Builder template (if exists)
        Write-Log "Checking for Image Builder templates..."
        
        $imageTemplates = Get-AzImageBuilderTemplate -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
        
        if ($imageTemplates) {
            foreach ($template in $imageTemplates) {
                Write-Log "Removing Image Builder template: $($template.Name)" -Level Warning
                Remove-AzImageBuilderTemplate -ResourceGroupName $resourceGroupName -Name $template.Name -Verbose
                Write-Log "Image Builder template removed: $($template.Name)" -Level Success
            }
        } else {
            Write-Log "No Image Builder templates found" -Level Info
        }
        
        # Step 7: Check for staging resource groups
        Write-Log "Checking for Image Builder staging resource groups..."
        
        $stagingRGs = Get-AzResourceGroup | Where-Object { 
            $_.ResourceGroupName -like "IT_$resourceGroupName*" 
        }
        
        if ($stagingRGs) {
            Write-Log "Found $($stagingRGs.Count) staging resource group(s)" -Level Warning
            foreach ($stagingRG in $stagingRGs) {
                Write-Log "Removing staging resource group: $($stagingRG.ResourceGroupName)" -Level Warning
                Remove-AzResourceGroup -Name $stagingRG.ResourceGroupName -Force -Verbose
                Write-Log "Staging resource group removed: $($stagingRG.ResourceGroupName)" -Level Success
            }
        } else {
            Write-Log "No staging resource groups found" -Level Info
        }
        
        # Step 8: Remove main resource group
        Write-Log "Removing main resource group: $resourceGroupName" -Level Warning
        Write-Host "`nRemoving resource group... This may take several minutes." -ForegroundColor Yellow
        
        Remove-AzResourceGroup -Name $resourceGroupName -Force -Verbose
        
        Write-Log "Resource group removed successfully: $resourceGroupName" -Level Success
        
        # Summary
        Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║              ✅ Removal Completed Successfully                 ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
        
        Write-Log "=== Removal Summary ===" -Level Success
        Write-Log "Resource Group: $resourceGroupName - REMOVED" -Level Success
        Write-Log "All associated resources have been deleted" -Level Success
        Write-Log "Log file saved to: $logPath" -Level Info
    }
    
    Write-Host "`nLog file: $logPath" -ForegroundColor Cyan
    
} catch {
    Write-Log "ERROR: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Write-Host "`n❌ Removal failed. Check the log file for details: $logPath" -ForegroundColor Red
    throw
}
