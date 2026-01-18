<#
.SYNOPSIS
    Check Windows 365 Service Principal Permissions

.DESCRIPTION
    This script checks that the Windows 365 service principal has the correct permissions for:
    - Reader on Subscription
    - Windows 365 Network Interface Contributor on Resource Group
    - Windows 365 Network User on Virtual Network
    - Reader on Azure Compute Gallery
    
    Supports multi-tenant scenarios for administrators with guest access to multiple tenants.
    
    All operations are logged to Documents folder as check-w365permissions-YYYY-MM-DD-HH-MM.log

.EXAMPLE
    .\check-W365permissions.ps1
    .\check-W365permissions.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId
)

# Set strict error handling
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Initialize logging
$timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm"
$logPath = Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "check-w365permissions-$timestamp.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $logTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    if ([string]::IsNullOrEmpty($Message)) {
        # For blank lines, just write empty line to console and log
        Write-Host ""
        Add-Content -Path $logPath -Value ""
    } else {
        $logMessage = "[$logTimestamp] [$Level] $Message"
        
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
}

# Function to select tenant
function Select-AzureTenant {
    param(
        [string]$TenantId
    )
    
    Write-Host "`nChecking Azure login status..." -ForegroundColor Cyan
    
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
        throw "No accessible tenants found."
    }
    
    # Select tenant
    $selectedTenant = $null
    
    if ($TenantId) {
        # Use explicitly specified tenant
        $selectedTenant = $tenants | Where-Object { $_.Id -eq $TenantId }
        if (!$selectedTenant) {
            throw "Specified tenant ID '$TenantId' not found or not accessible."
        }
        Write-Host "Using specified tenant: $($selectedTenant.Name) ($($selectedTenant.Id))" -ForegroundColor Green
    }
    elseif ($tenants.Count -eq 1) {
        # Only one tenant available, use it automatically
        $selectedTenant = $tenants[0]
        Write-Host "Using tenant: $($selectedTenant.Name) ($($selectedTenant.Id))" -ForegroundColor Green
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
        $errorMessage = $_.Exception.Message
        if ($errorMessage -match "Authentication failed|User interaction is required|multi-factor authentication") {
            Write-Host "Authentication required for tenant '$($selectedTenant.Name)'." -ForegroundColor Yellow
            Write-Host "This tenant requires additional authentication (possibly MFA)." -ForegroundColor Yellow
            Write-Host "`nTo access this tenant, please run:" -ForegroundColor Cyan
            Write-Host "  Connect-AzAccount -TenantId $($selectedTenant.Id)" -ForegroundColor White
            Write-Host "Then run this script again with:" -ForegroundColor Cyan
            Write-Host "  .\check-W365permissions.ps1 -TenantId $($selectedTenant.Id)" -ForegroundColor White
        }
        throw "Failed to authenticate to tenant: $_"
    }
    
    return $selectedTenant
}

function Select-AzureSubscription {
    param(
        [string]$Purpose = "selection",
        [string]$TenantId
    )
    
    Write-Host "`n=== Azure Subscription Selection ($Purpose) ===" -ForegroundColor Cyan
    
    $subscriptions = Get-AzSubscription -TenantId $TenantId | Where-Object { $_.State -eq "Enabled" } | Sort-Object Name
    
    if ($subscriptions.Count -eq 0) {
        throw "No Azure subscriptions found. Please check your account permissions."
    }
    
    if ($subscriptions.Count -eq 1) {
        Write-Host "Only one subscription available: $($subscriptions[0].Name)" -ForegroundColor Green
        return $subscriptions[0]
    }
    
    Write-Host "`nAvailable subscriptions:" -ForegroundColor White
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "  [$($i + 1)] $($subscriptions[$i].Name) ($($subscriptions[$i].Id))" -ForegroundColor Gray
    }
    
    do {
        $selection = Read-Host "`nSelect subscription number [1-$($subscriptions.Count)]"
        $index = $selection -as [int]
    } while ($index -lt 1 -or $index -gt $subscriptions.Count)
    
    return $subscriptions[$index - 1]
}

function Select-ResourceGroup {
    param(
        [string]$SubscriptionId,
        [string]$Purpose = "selection"
    )
    
    Write-Host "`n=== Resource Group Selection ($Purpose) ===" -ForegroundColor Cyan
    
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $resourceGroups = Get-AzResourceGroup | Sort-Object ResourceGroupName
    
    if ($resourceGroups.Count -eq 0) {
        throw "No resource groups found in this subscription."
    }
    
    Write-Host "`nAvailable resource groups:" -ForegroundColor White
    for ($i = 0; $i -lt $resourceGroups.Count; $i++) {
        Write-Host "  [$($i + 1)] $($resourceGroups[$i].ResourceGroupName) (Location: $($resourceGroups[$i].Location))" -ForegroundColor Gray
    }
    
    do {
        $selection = Read-Host "`nSelect resource group number [1-$($resourceGroups.Count)]"
        $index = $selection -as [int]
    } while ($index -lt 1 -or $index -gt $resourceGroups.Count)
    
    return $resourceGroups[$index - 1]
}

function Select-VirtualNetwork {
    param(
        [string]$ResourceGroupName
    )
    
    Write-Host "`n=== Virtual Network Selection ===" -ForegroundColor Cyan
    
    $vnetsResult = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    
    if (-not $vnetsResult) {
        Write-Log "No virtual networks found in resource group: $ResourceGroupName" -Level Warning
        return $null
    }
    
    # Force to array
    if ($vnetsResult -is [array]) {
        $vnets = $vnetsResult | Sort-Object Name
    } else {
        $vnets = @($vnetsResult)
    }
    
    if ($vnets.Count -eq 0) {
        Write-Log "No virtual networks found in resource group: $ResourceGroupName" -Level Warning
        return $null
    }
    
    if ($vnets.Count -eq 1) {
        Write-Host "Only one virtual network available: $($vnets[0].Name)" -ForegroundColor Green
        return $vnets[0]
    }
    
    Write-Host "`nAvailable virtual networks:" -ForegroundColor White
    for ($i = 0; $i -lt $vnets.Count; $i++) {
        $subnetCount = $vnets[$i].Subnets.Count
        Write-Host "  [$($i + 1)] $($vnets[$i].Name) (Subnets: $subnetCount, Location: $($vnets[$i].Location))" -ForegroundColor Gray
    }
    
    do {
        $selection = Read-Host "`nSelect virtual network number [1-$($vnets.Count)]"
        $index = $selection -as [int]
    } while ($index -lt 1 -or $index -gt $vnets.Count)
    
    return $vnets[$index - 1]
}

function Select-ComputeGallery {
    param(
        [string]$ResourceGroupName
    )
    
    Write-Host "`n=== Azure Compute Gallery Selection ===" -ForegroundColor Cyan
    
    $galleriesResult = Get-AzGallery -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    
    if (-not $galleriesResult) {
        Write-Log "No Azure Compute Galleries found in resource group: $ResourceGroupName" -Level Warning
        return $null
    }
    
    # Force to array
    if ($galleriesResult -is [array]) {
        $galleries = $galleriesResult | Sort-Object Name
    } else {
        $galleries = @($galleriesResult)
    }
    
    if ($galleries.Count -eq 0) {
        Write-Log "No Azure Compute Galleries found in resource group: $ResourceGroupName" -Level Warning
        return $null
    }
    
    if ($galleries.Count -eq 1) {
        Write-Host "Only one gallery available: $($galleries[0].Name)" -ForegroundColor Green
        return $galleries[0]
    }
    
    Write-Host "`nAvailable galleries:" -ForegroundColor White
    for ($i = 0; $i -lt $galleries.Count; $i++) {
        Write-Host "  [$($i + 1)] $($galleries[$i].Name) (Location: $($galleries[$i].Location))" -ForegroundColor Gray
    }
    
    do {
        $selection = Read-Host "`nSelect gallery number [1-$($galleries.Count)]"
        $index = $selection -as [int]
    } while ($index -lt 1 -or $index -gt $galleries.Count)
    
    return $galleries[$index - 1]
}

function Test-RoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$Scope,
        [string]$RoleDefinitionName,
        [string]$ResourceDescription
    )
    
    Write-Log "Checking '$RoleDefinitionName' role on $ResourceDescription..." -Level Info
    
    $roleAssignment = Get-AzRoleAssignment -ObjectId $PrincipalId -Scope $Scope -RoleDefinitionName $RoleDefinitionName -ErrorAction SilentlyContinue
    
    if ($roleAssignment) {
        Write-Log "  PASS: Role '$RoleDefinitionName' is assigned on $ResourceDescription" -Level Success
        return $true
    } else {
        Write-Log "  FAIL: Role '$RoleDefinitionName' is NOT assigned on $ResourceDescription" -Level Error
        Write-Log "  To grant access, run:" -Level Info
        Write-Log "  New-AzRoleAssignment -ObjectId '$PrincipalId' -RoleDefinitionName '$RoleDefinitionName' -Scope '$Scope'" -Level Info
        return $false
    }
}

# Main execution
try {
    Write-Log "=== Windows 365 Service Principal Permissions Check ===" -Level Info
    Write-Log "Log file: $logPath" -Level Info
    
    # Step 1: Connect to Azure and select tenant
    Write-Log "Step 1: Connecting to Azure and selecting tenant..." -Level Info
    
    $selectedTenant = Select-AzureTenant -TenantId $TenantId
    
    $azContext = Get-AzContext
    Write-Log "Connected to Azure as: $($azContext.Account.Id)" -Level Success
    Write-Log "Selected tenant: $($selectedTenant.Name) ($($selectedTenant.Id))" -Level Success
    
    # Step 2: Get Windows 365 service principal
    Write-Log "Step 2: Finding Windows 365 service principal..." -Level Info
    
    $windows365SP = Get-AzADServicePrincipal -DisplayName "Windows 365" -ErrorAction SilentlyContinue
    
    if (-not $windows365SP) {
        throw "Windows 365 service principal not found in this tenant. This may indicate Windows 365 has not been activated."
    }
    
    Write-Log "Found Windows 365 service principal" -Level Success
    Write-Log "  Display Name: $($windows365SP.DisplayName)" -Level Info
    Write-Log "  Object ID: $($windows365SP.Id)" -Level Info
    Write-Log "  App ID: $($windows365SP.AppId)" -Level Info
    
    $principalId = $windows365SP.Id
    
    # Track results
    $results = @{
        SubscriptionReader = $false
        ResourceGroupContributor = $false
        VNetUser = $false
        GalleryReader = $false
    }
    
    # Step 3: Check Subscription permissions
    Write-Log "`nStep 3: Checking Subscription permissions..." -Level Info
    
    $networkSubscription = Select-AzureSubscription -Purpose "for Network Connection" -TenantId $selectedTenant.Id
    Set-AzContext -TenantId $selectedTenant.Id -SubscriptionId $networkSubscription.Id | Out-Null
    
    Write-Log "Selected subscription: $($networkSubscription.Name)" -Level Info
    Write-Log "  Subscription ID: $($networkSubscription.Id)" -Level Info
    
    $subscriptionScope = "/subscriptions/$($networkSubscription.Id)"
    $results.SubscriptionReader = Test-RoleAssignment -PrincipalId $principalId -Scope $subscriptionScope -RoleDefinitionName "Reader" -ResourceDescription "Subscription '$($networkSubscription.Name)'"
    
    # Step 4: Check Resource Group permissions
    Write-Log "`nStep 4: Checking Resource Group permissions..." -Level Info
    
    $networkResourceGroup = Select-ResourceGroup -SubscriptionId $networkSubscription.Id -Purpose "for Network Connection"
    
    Write-Log "Selected resource group: $($networkResourceGroup.ResourceGroupName)" -Level Info
    
    $resourceGroupScope = $networkResourceGroup.ResourceId
    $results.ResourceGroupContributor = Test-RoleAssignment -PrincipalId $principalId -Scope $resourceGroupScope -RoleDefinitionName "Windows 365 Network Interface Contributor" -ResourceDescription "Resource Group '$($networkResourceGroup.ResourceGroupName)'"
    
    # Step 5: Check Virtual Network permissions
    Write-Log "`nStep 5: Checking Virtual Network permissions..." -Level Info
    
    $vnet = Select-VirtualNetwork -ResourceGroupName $networkResourceGroup.ResourceGroupName
    
    if ($vnet) {
        Write-Log "Selected virtual network: $($vnet.Name)" -Level Info
        Write-Log "  Address Space: $($vnet.AddressSpace.AddressPrefixes -join ', ')" -Level Info
        Write-Log "  Subnets: $($vnet.Subnets.Count)" -Level Info
        
        $vnetScope = $vnet.Id
        $results.VNetUser = Test-RoleAssignment -PrincipalId $principalId -Scope $vnetScope -RoleDefinitionName "Windows 365 Network User" -ResourceDescription "Virtual Network '$($vnet.Name)'"
    } else {
        Write-Log "No virtual network selected. Skipping VNet permission check." -Level Warning
    }
    
    # Step 6: Check Managed Image permissions
    Write-Log "`nStep 6: Checking Managed Image permissions..." -Level Info
    
    $imageSubscription = Select-AzureSubscription -Purpose "for Custom Managed Images" -TenantId $selectedTenant.Id
    Set-AzContext -TenantId $selectedTenant.Id -SubscriptionId $imageSubscription.Id | Out-Null
    
    Write-Log "Selected subscription: $($imageSubscription.Name)" -Level Info
    
    $imageResourceGroup = Select-ResourceGroup -SubscriptionId $imageSubscription.Id -Purpose "for Custom Managed Images"
    
    Write-Log "Selected resource group: $($imageResourceGroup.ResourceGroupName)" -Level Info
    
    # Check for Reader permission on the resource group (sufficient for managed images)
    $imageRgScope = $imageResourceGroup.ResourceId
    $results.ManagedImageReader = Test-RoleAssignment -PrincipalId $principalId -Scope $imageRgScope -RoleDefinitionName "Reader" -ResourceDescription "Resource Group '$($imageResourceGroup.ResourceGroupName)' (for managed images)"
    
    Write-Log "Note: Windows 365 needs Reader permission on the resource group containing managed images" -Level Info
    
    # Step 7: Summary
    Write-Log "`n=== PERMISSION CHECK SUMMARY ===" -Level Info
    Write-Log "Windows 365 Service Principal: $($windows365SP.DisplayName) ($($windows365SP.Id))" -Level Info
    Write-Log "" -Level Info
    
    $passCount = 0
    $totalChecks = 0
    
    if ($results.SubscriptionReader) {
        Write-Log "  [PASS] Reader on Subscription" -Level Success
        $passCount++
    } else {
        Write-Log "  [FAIL] Reader on Subscription" -Level Error
    }
    $totalChecks++
    
    if ($results.ResourceGroupContributor) {
        Write-Log "  [PASS] Windows 365 Network Interface Contributor on Resource Group" -Level Success
        $passCount++
    } else {
        Write-Log "  [FAIL] Windows 365 Network Interface Contributor on Resource Group" -Level Error
    }
    $totalChecks++
    
    if ($vnet) {
        if ($results.VNetUser) {
            Write-Log "  [PASS] Windows 365 Network User on Virtual Network" -Level Success
            $passCount++
        } else {
            Write-Log "  [FAIL] Windows 365 Network User on Virtual Network" -Level Error
        }
        $totalChecks++
    }
    
    if ($results.ManagedImageReader) {
        Write-Log "  [PASS] Reader on Resource Group (for managed images)" -Level Success
        $passCount++
    } else {
        Write-Log "  [FAIL] Reader on Resource Group (for managed images)" -Level Error
    }
    $totalChecks++
    
    Write-Log ""
    Write-Log "Checks Passed: $passCount / $totalChecks" -Level Info
    Write-Log ""
    
    # Overall status
    if ($passCount -eq $totalChecks) {
        Write-Log "========================================" -Level Success
        Write-Log "OVERALL STATUS: PASS" -Level Success
        Write-Log "========================================" -Level Success
        Write-Log "All permission checks passed! Windows 365 is correctly configured." -Level Success
    } else {
        Write-Log "========================================" -Level Error
        Write-Log "OVERALL STATUS: FAIL" -Level Error
        Write-Log "========================================" -Level Error
        Write-Log "Some permission checks failed. Review the log and grant missing permissions." -Level Warning
        Write-Log "Windows 365 will not function correctly until all permissions are granted." -Level Warning
    }
    
    Write-Log ""
    Write-Log "Full log saved to: $logPath" -Level Success
    
}
catch {
    Write-Log "PERMISSION CHECK FAILED: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    Write-Log "Full log saved to: $logPath" -Level Error
    throw
}
