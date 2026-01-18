<#
.SYNOPSIS
    Deploys Windows 365 Custom Image using managed image approach

.DESCRIPTION
    This script automates the complete process of:
    - Deploying Gen 2 Windows 11 VM (win11-25h2-ent-cpc)
    - Customizing VM with Chocolatey packages and settings
    - Running sysprep with Windows 365-compliant parameters
    - Capturing as managed image (Gen 2)
    - Cleaning up temporary resources
    
    Supports multi-tenant scenarios for administrators with guest access to multiple tenants.
    
    All operations are logged to Documents folder as W365Customimage-YYYY-MM-DD-HH-MM.log
    
    The script will interactively prompt for:
    - Azure Tenant (if multiple accessible)
    - Azure Subscription (if multiple in tenant)
    - Azure Region (default: southcentralus)
    - Resource Group Name (default: rg-w365-customimage)
    - VM Admin Credentials

.PARAMETER TenantId
    Optional Azure AD tenant ID. If specified, skips tenant selection prompt.

.PARAMETER SubscriptionId
    Optional subscription ID. If specified, skips subscription selection prompt.

.PARAMETER StudentNumber
    Student number (1-40) for unique resource naming. Default: 1

.PARAMETER Force
    Forces clearing of all cached Azure credentials before authentication. 
    Use this if you're being redirected to the wrong tenant or need to log in with different credentials.

.EXAMPLE
    .\Deploy-W365CustomImage.ps1
    Run with interactive prompts for tenant and subscription

.EXAMPLE
    .\Deploy-W365CustomImage.ps1 -StudentNumber 5
    Deploy for student 5 with interactive prompts

.EXAMPLE
    .\Deploy-W365CustomImage.ps1 -Force
    Clear all cached credentials and force fresh login

.EXAMPLE
    .\Deploy-W365CustomImage.ps1 -Force -StudentNumber 3
    Clear credentials and deploy for student 3

.EXAMPLE
    .\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -StudentNumber 1
    Deploy for student 1 using specific tenant ID

.EXAMPLE
    .\Deploy-W365CustomImage.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -SubscriptionId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" -StudentNumber 10
    Deploy for student 10 using specific tenant and subscription
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 40)]
    [int]$StudentNumber = 1,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)


# Set strict error handling
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Initialize logging
$timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm"
$logPath = Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "W365Customimage-$timestamp.log"

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

function Test-ResourceQuota {
    param(
        [string]$ResourceGroupName,
        [string]$ResourceType,
        [int]$MaxAllowed
    )
    
    Write-Log "Checking resource quota: $ResourceType (max: $MaxAllowed)" -Level Info
    
    try {
        # Get existing resources of this type
        $existingResources = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType $ResourceType -ErrorAction SilentlyContinue
        $currentCount = ($existingResources | Measure-Object).Count
        
        Write-Log "  Current count: $currentCount" -Level Info
        
        if ($currentCount -ge $MaxAllowed) {
            Write-Log "===============================================" -Level Error
            Write-Log "  RESOURCE QUOTA EXCEEDED" -Level Error
            Write-Log "===============================================" -Level Error
            Write-Log "Resource Type: $ResourceType" -Level Error
            Write-Log "Current: $currentCount / Maximum Allowed: $MaxAllowed" -Level Error
            Write-Log "You must delete existing resources before creating new ones." -Level Warning
            Write-Log "Existing resources in ${ResourceGroupName}:" -Level Warning
            $existingResources | ForEach-Object {
                Write-Log "  - $($_.Name) (Type: $($_.ResourceType))" -Level Warning
            }
            Write-Log "To delete a VM and its resources, use:" -Level Info
            Write-Log "  Remove-AzVM -ResourceGroupName '$ResourceGroupName' -Name '<vm-name>' -Force" -Level Info
            
            throw "Resource quota exceeded: Cannot create more than $MaxAllowed $ResourceType in $ResourceGroupName"
        }
        
        Write-Log "  [OK] Quota check passed" -Level Success
        return $true
    }
    catch {
        if ($_.Exception.Message -match "quota exceeded") {
            throw
        }
        # If resource group doesn't exist yet, quota check passes
        Write-Log "  Resource group doesn't exist yet - quota check passed" -Level Success
        return $true
    }
}

# Function to select tenant and establish context
function Select-AzureTenantContext {
    param(
        [string]$TenantId,
        [string]$SubscriptionId,
        [switch]$ForceLogin
    )
    
    Write-Host "`nChecking Azure login status..." -ForegroundColor Cyan
    
    try {
        # Clear all cached credentials if Force is specified
        if ($ForceLogin) {
            Write-Host "Force login requested - clearing all Azure credentials..." -ForegroundColor Yellow
            try {
                # Disconnect all Azure accounts
                Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
                
                # Clear all contexts
                Clear-AzContext -Force -ErrorAction SilentlyContinue | Out-Null
                
                Write-Host "All cached credentials cleared successfully" -ForegroundColor Green
            }
            catch {
                Write-Host "Note: Some credentials may still be cached" -ForegroundColor Yellow
            }
        }
        
        # Ensure user is authenticated
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) {
            Write-Host "Not logged in to Azure. Initiating login..." -ForegroundColor Yellow
            Connect-AzAccount
            $context = Get-AzContext
        }
        
        Write-Host "Logged in as: $($context.Account.Id)" -ForegroundColor Green
        
        # Get all available tenants
        Write-Host "`nRetrieving available tenants..." -ForegroundColor Cyan
        $tenants = @(Get-AzTenant)
        
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
                Write-Host "  .\Deploy-W365CustomImage.ps1 -TenantId $($selectedTenant.Id)" -ForegroundColor White
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

function Select-AzureLocation {
    param(
        [string]$DefaultLocation = "southcentralus"
    )
    
    Write-Host "`n=== Azure Location Selection ===" -ForegroundColor Cyan
    
    # Image Builder supported regions
    $supportedLocations = @(
        "westus3", "eastus", "eastus2", "westus", "westus2",
        "northcentralus", "southcentralus", "westcentralus", "centralus",
        "northeurope", "westeurope", "uksouth", "ukwest",
        "francecentral", "canadacentral", "canadaeast",
        "australiaeast", "australiasoutheast",
        "southeastasia", "japaneast", "koreacentral",
        "brazilsouth", "southafricanorth"
    ) | Sort-Object
    
    Write-Host "`nSupported Azure Image Builder regions:" -ForegroundColor White
    $columns = 3
    for ($i = 0; $i -lt $supportedLocations.Count; $i += $columns) {
        $line = ""
        for ($j = 0; $j -lt $columns -and ($i + $j) -lt $supportedLocations.Count; $j++) {
            $index = $i + $j
            $line += "  [$($index + 1)] $($supportedLocations[$index])".PadRight(30)
        }
        Write-Host $line -ForegroundColor Gray
    }
    
    Write-Host ""
    $defaultIndex = [array]::IndexOf($supportedLocations, $DefaultLocation)
    if ($defaultIndex -ge 0) {
        Write-Host "Default: [$($defaultIndex + 1)] $DefaultLocation" -ForegroundColor Yellow
    }
    
    do {
        $selection = Read-Host "`nSelect location number [1-$($supportedLocations.Count)] or press Enter for default ($DefaultLocation)"
        
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $DefaultLocation
        }
        
        $index = $selection -as [int]
    } while ($index -lt 1 -or $index -gt $supportedLocations.Count)
    
    return $supportedLocations[$index - 1]
}

function Get-ResourceGroupName {
    param(
        [string]$DefaultName = "rg-w365-customimage",
        [int]$StudentNumber = 1
    )
    
    $defaultWithStudent = "rg-w365-customimage-student$StudentNumber"
    
    Write-Host "`n=== Resource Group Name ===" -ForegroundColor Cyan
    Write-Host "Default: $defaultWithStudent (Student $StudentNumber)" -ForegroundColor Yellow
    
    $name = Read-Host "`nEnter resource group name or press Enter for default ($defaultWithStudent)"
    
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $defaultWithStudent
    }
    
    return $name.Trim()
}

# Main deployment function
function Start-Deployment {
    try {
        Write-Log "=== Windows 365 Custom Image Infrastructure Deployment ===" -Level Info
        Write-Log "Log file: $logPath" -Level Info
        
        # Check if running as administrator (recommended)
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Log "Warning: Not running as administrator. Some operations may require elevation." -Level Warning
        }
        
        # Step 1: Check Azure PowerShell modules
        Write-Log "Step 1: Checking Azure PowerShell modules..." -Level Info
        $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.ManagedServiceIdentity', 'Az.Compute', 'Az.Network', 'Az.ImageBuilder')
        
        foreach ($module in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                Write-Log "Installing module: $module" -Level Info
                Install-Module -Name $module -Repository PSGallery -Force -AllowClobber -Scope CurrentUser
            } else {
                Write-Log "Module already installed: $module" -Level Info
            }
        }
        
        # Import modules (gracefully handle if already loaded)
        foreach ($module in $requiredModules) {
            try {
                Import-Module $module -ErrorAction Stop
                Write-Log "Module loaded: $module" -Level Info
            } catch {
                # Module may already be loaded, which is fine
                Write-Log "Module $module already loaded or import skipped" -Level Info
            }
        }
        Write-Log "All required modules loaded" -Level Success
        
        # Step 1.5: Check and install Bicep CLI
        Write-Log "Step 1.5: Checking Bicep CLI installation..." -Level Info
        
        try {
            $bicepVersion = bicep --version 2>$null
            if ($bicepVersion) {
                Write-Log "Bicep CLI already installed: $bicepVersion" -Level Info
            }
        }
        catch {
            Write-Log "Bicep CLI not found. Installing..." -Level Warning
            
            # Install Bicep CLI using winget or manual download
            try {
                # Try winget first (fastest method on Windows 11)
                $wingetCheck = Get-Command winget -ErrorAction SilentlyContinue
                if ($wingetCheck) {
                    Write-Log "Installing Bicep via winget..." -Level Info
                    winget install --id Microsoft.Bicep --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                    
                    # Refresh PATH
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                }
                else {
                    # Manual installation method
                    Write-Log "Installing Bicep manually..." -Level Info
                    $installPath = "$env:USERPROFILE\.bicep"
                    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
                    
                    $bicepUrl = "https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe"
                    $bicepExe = Join-Path -Path $installPath -ChildPath "bicep.exe"
                    
                    Invoke-WebRequest -Uri $bicepUrl -OutFile $bicepExe -UseBasicParsing
                    
                    # Add to PATH for current session
                    $env:Path += ";$installPath"
                    
                    # Add to user PATH permanently
                    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
                    if ($userPath -notlike "*$installPath*") {
                        [Environment]::SetEnvironmentVariable("Path", "$userPath;$installPath", "User")
                    }
                }
                
                # Verify installation
                $bicepVersion = bicep --version 2>$null
                if ($bicepVersion) {
                    Write-Log "Bicep CLI installed successfully: $bicepVersion" -Level Success
                }
                else {
                    throw "Bicep installation completed but command not found. Please restart PowerShell and try again."
                }
            }
            catch {
                Write-Log "Failed to install Bicep automatically: $($_.Exception.Message)" -Level Error
                Write-Log "Please install Bicep manually from: https://aka.ms/bicep-install" -Level Error
                throw "Bicep CLI installation failed. Please install manually and rerun the script."
            }
        }
        
        # Step 2: Connect to Azure and establish tenant/subscription context
        Write-Log "Step 2: Establishing Azure context..." -Level Info
        
        if ($Force) {
            Write-Log "Force mode enabled - clearing all cached credentials" -Level Warning
        }
        
        if (!(Select-AzureTenantContext -TenantId $TenantId -SubscriptionId $SubscriptionId -ForceLogin:$Force)) {
            throw "Failed to establish Azure context. Please check your permissions and try again."
        }
        
        $azContext = Get-AzContext
        $currentSubscriptionId = $azContext.Subscription.Id
        $currentSubscriptionName = $azContext.Subscription.Name
        Write-Log "Azure context established successfully" -Level Success
        Write-Log "  Account: $($azContext.Account.Id)" -Level Info
        Write-Log "  Tenant: $($azContext.Tenant.Id)" -Level Info
        Write-Log "  Subscription: $currentSubscriptionName" -Level Info
        Write-Log "  Subscription ID: $currentSubscriptionId" -Level Info
        
        # Interactive location selection
        $Location = Select-AzureLocation -DefaultLocation "southcentralus"
        Write-Log "Selected location: $Location" -Level Success
        
        # Interactive resource group name
        $ResourceGroupName = Get-ResourceGroupName -DefaultName "rg-w365-customimage" -StudentNumber $StudentNumber
        Write-Log "Resource group name: $ResourceGroupName (Student $StudentNumber)" -Level Success
        
        # Step 3: Register required resource providers
        Write-Log "Step 3: Registering required Azure resource providers..." -Level Info
        
        $providers = @(
            'Microsoft.Compute',
            'Microsoft.Storage',
            'Microsoft.Network',
            'Microsoft.ManagedIdentity'
        )
        
        foreach ($provider in $providers) {
            $registration = Get-AzResourceProvider -ProviderNamespace $provider
            if ($registration.RegistrationState -ne 'Registered') {
                Write-Log "Registering provider: $provider" -Level Info
                Register-AzResourceProvider -ProviderNamespace $provider | Out-Null
            } else {
                Write-Log "Provider already registered: $provider" -Level Info
            }
        }
        Write-Log "All resource providers registered" -Level Success
        
        # Step 4: Get VM administrator credentials
        Write-Log "Step 4: Getting VM administrator credentials..." -Level Info
        
        Write-Host "`n=== VM Administrator Credentials ===" -ForegroundColor Cyan
        Write-Host "Enter credentials for the build VM (will be discarded after image capture)" -ForegroundColor Yellow
        
        $credential = Get-Credential -Message "Enter VM administrator credentials"
        if (-not $credential) {
            throw "VM credentials are required to continue"
        }
        
        $adminUsername = $credential.UserName
        $adminPassword = $credential.GetNetworkCredential().Password
        
        Write-Log "VM credentials configured" -Level Success
        Write-Log "Admin username: $adminUsername" -Level Info
        
        # Step 5: Deploy infrastructure using Bicep
        Write-Log "Step 5: Deploying infrastructure (Gen 2 VM) with Bicep..." -Level Info
        
        $bicepFile = Join-Path -Path $PSScriptRoot -ChildPath "customimage.bicep"
        if (-not (Test-Path $bicepFile)) {
            throw "Bicep file not found: $bicepFile"
        }
        
        # Define deployment parameters
        $buildTimestamp = Get-Date -Format "yyyyMMddHHmmss"
        $secureAdminPassword = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force
        
        Write-Log "Creating resource group: $ResourceGroupName in $Location" -Level Info
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force
        Write-Log "Resource group created/updated" -Level Success
        
        # Check VM quota (max 1 VM per student customimage RG)
        Write-Log "Enforcing resource quota for student lab environment..." -Level Info
        Test-ResourceQuota -ResourceGroupName $ResourceGroupName `
            -ResourceType "Microsoft.Compute/virtualMachines" `
            -MaxAllowed 1
        
        Write-Log "Starting Bicep deployment (validation will occur automatically)..." -Level Info

        $deployment = $null
        $deploymentErrors = $null

        try {
            $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $bicepFile -location $Location -adminUsername $adminUsername -adminPassword $secureAdminPassword -buildTimestamp $buildTimestamp -studentNumber $StudentNumber -Name "w365-customimage-deployment-$timestamp" -ErrorVariable deploymentErrors -Verbose

            if ($deployment.ProvisioningState -eq 'Succeeded') {
                Write-Log "Infrastructure deployment completed successfully" -Level Success
            }
            else {
                throw "Deployment failed with state: $($deployment.ProvisioningState)"
            }
        }
        catch {
            Write-Log "Bicep deployment validation/execution failed" -Level Error
            Write-Log "Error: $($_.Exception.Message)" -Level Error

            if ($_.Exception.InnerException) {
                Write-Log "Inner Exception: $($_.Exception.InnerException.Message)" -Level Error
            }

            if ($deploymentErrors) {
                Write-Log "Deployment Error Details:" -Level Error
                foreach ($err in $deploymentErrors) {
                    Write-Log "  $err" -Level Error
                }
            }

            # Get deployment operation details
            $operations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $ResourceGroupName -DeploymentName "w365-customimage-deployment-$timestamp" -ErrorAction SilentlyContinue

            if ($operations) {
                Write-Log "Deployment operation details:" -Level Error
                foreach ($op in $operations) {
                    if ($op.Properties.StatusCode -ne 'OK') {
                        Write-Log "  Operation: $($op.Properties.TargetResource.ResourceType)" -Level Error
                        Write-Log "  Status: $($op.Properties.StatusCode)" -Level Error
                        if ($op.Properties.StatusMessage.error) {
                            $errorMsg = $op.Properties.StatusMessage.error
                            Write-Log "  Error Code: $($errorMsg.code)" -Level Error
                            Write-Log "  Error Message: $($errorMsg.message)" -Level Error
                        }
                    }
                }
            }

            throw "Bicep deployment failed. See errors above for details."
        }

        # Extract outputs
        $vmId = $deployment.Outputs.vmId.Value
        $vmName = $deployment.Outputs.vmName.Value
        $publicIPAddress = $deployment.Outputs.publicIPAddress.Value
        $vnetId = $deployment.Outputs.vnetId.Value
        
        Write-Log "Deployment outputs:" -Level Info
        Write-Log "  VM Name: $vmName" -Level Info
        Write-Log "  VM ID: $vmId" -Level Info
        Write-Log "  Public IP: $publicIPAddress" -Level Info
        Write-Log "  VNet ID: $vnetId" -Level Info
        
        # Step 6: Wait for VM to be ready and execute customization
        Write-Log "Step 6: Waiting for VM to be ready (2 minutes)..." -Level Info
        Start-Sleep -Seconds 120
        Write-Log "VM should now be ready" -Level Success
        
        Write-Log "Executing customization script on VM..." -Level Info
        $customizationScript = Get-Content (Join-Path -Path $PSScriptRoot -ChildPath "Invoke-W365ImageCustomization.ps1") -Raw
        
        try {
            $customizationResult = Invoke-AzVMRunCommand `
                -ResourceGroupName $ResourceGroupName `
                -VMName $vmName `
                -CommandId 'RunPowerShellScript' `
                -ScriptString $customizationScript `
                -ErrorAction Stop
            
            Write-Log "Customization script execution completed" -Level Success
            Write-Log "Script output:" -Level Info
            if ($customizationResult.Value[0].Message) {
                $customizationResult.Value[0].Message -split "`n" | ForEach-Object {
                    Write-Log "  $_" -Level Info
                }
            }
        }
        catch {
            Write-Log "Customization script execution encountered errors: $($_.Exception.Message)" -Level Warning
            Write-Log "Continuing with sysprep..." -Level Warning
        }
        
        # Step 7: Execute sysprep
        Write-Log "Step 7: Executing sysprep on VM..." -Level Info
        Write-Log "This will generalize the VM and shut it down (5-15 minutes)..." -Level Info
        
        $sysprepScript = Get-Content (Join-Path -Path $PSScriptRoot -ChildPath "Invoke-W365Sysprep.ps1") -Raw
        
        try {
            $sysprepResult = Invoke-AzVMRunCommand `
                -ResourceGroupName $ResourceGroupName `
                -VMName $vmName `
                -CommandId 'RunPowerShellScript' `
                -ScriptString $sysprepScript `
                -ErrorAction Stop
            
            Write-Log "Sysprep command sent successfully" -Level Success
        }
        catch {
            Write-Log "Sysprep execution may have started but VM is shutting down: $($_.Exception.Message)" -Level Warning
        }
        
        # Wait for VM to stop
        Write-Log "Waiting for VM to shut down after sysprep..." -Level Info
        $maxWaitMinutes = 20
        $waitInterval = 30
        $elapsed = 0
        
        do {
            Start-Sleep -Seconds $waitInterval
            $elapsed += $waitInterval
            $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Status
            $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
            
            Write-Log "VM power state: $powerState (waited $([math]::Round($elapsed/60, 1)) minutes)" -Level Info
            
            if ($powerState -eq "PowerState/stopped" -or $powerState -eq "PowerState/deallocated") {
                Write-Log "VM has stopped" -Level Success
                break
            }
            
            if ($elapsed -ge ($maxWaitMinutes * 60)) {
                throw "VM did not stop within $maxWaitMinutes minutes. Sysprep may have failed."
            }
        } while ($true)
        
        # Deallocate VM if not already deallocated
        if ($powerState -ne "PowerState/deallocated") {
            Write-Log "Deallocating VM..." -Level Info
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Force | Out-Null
            Write-Log "VM deallocated" -Level Success
        }
        
        # Step 8: Capture managed image
        Write-Log "Step 8: Capturing managed image..." -Level Info
        
        # Set VM to generalized state
        Set-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Generalized | Out-Null
        Write-Log "VM set to generalized state" -Level Success
        
        # Create managed image
        $imageName = "w365-custom-image-student$StudentNumber-$buildTimestamp"
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName
        
        $imageConfig = New-AzImageConfig -Location $Location -SourceVirtualMachineId $vm.Id -HyperVGeneration 'V2'
        $image = New-AzImage -ImageName $imageName -ResourceGroupName $ResourceGroupName -Image $imageConfig
        
        if ($image.ProvisioningState -eq 'Succeeded') {
            Write-Log "Managed image created successfully" -Level Success
            Write-Log "Image Name: $imageName" -Level Info
            Write-Log "Image ID: $($image.Id)" -Level Info
        } else {
            throw "Image capture failed: $($image.ProvisioningState)"
        }
        
        # Step 9: Cleanup temporary resources
        Write-Log "Step 9: Cleaning up temporary resources..." -Level Info
        
        Write-Log "Deleting build VM..." -Level Info
        Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Force | Out-Null
        Write-Log "Build VM deleted" -Level Success
        
        Write-Log "Deleting public IP..." -Level Info
        $pipName = "w365-build-pip-$buildTimestamp"
        Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $pipName -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Public IP deleted" -Level Success
        
        Write-Log "Deleting network interface..." -Level Info
        $nicName = "w365-build-nic-$buildTimestamp"
        Remove-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Network interface deleted" -Level Success
        
        Write-Log "VNet and NSG retained for future builds" -Level Info
        
        # Step 10: Display completion summary
        Write-Log "=== IMAGE BUILD COMPLETED SUCCESSFULLY ===" -Level Success
        Write-Host ""
        Write-Log "[OK] Gen 2 Windows 11 VM deployed and customized" -Level Success
        Write-Log "[OK] Chocolatey packages installed (VSCode, 7-Zip, Chrome, Adobe Reader)" -Level Success
        Write-Log "[OK] Windows settings configured" -Level Success
        Write-Log "[OK] VM generalized with sysprep (/generalize /oobe /shutdown)" -Level Success
        Write-Log "[OK] Managed image captured" -Level Success
        Write-Log "[OK] Temporary resources cleaned up" -Level Success
        Write-Host ""
        Write-Log "Managed Image Details:" -Level Info
        Write-Log "  Name: $imageName" -Level Info
        Write-Log "  Resource Group: $ResourceGroupName" -Level Info
        Write-Log "  Location: $Location" -Level Info
        Write-Log "  Generation: 2 (Hyper-V)" -Level Info
        Write-Log "  Image ID: $($image.Id)" -Level Info
        Write-Host ""
        Write-Log "Next Steps:" -Level Info
        Write-Log "1. Verify Windows 365 service principal has permissions:" -Level Info
        Write-Log "   .\\check-W365permissions.ps1" -Level Info
        Write-Log "2. Use this image in Windows 365 provisioning policy:" -Level Info
        Write-Log "   - Navigate to Intune admin center" -Level Info
        Write-Log "   - Windows 365 > Provisioning Policies" -Level Info
        Write-Log "   - Select 'Custom image' and choose: $imageName" -Level Info
        Write-Host ""
        Write-Log "Full log saved to: $logPath" -Level Success
        
    }
    catch {
        Write-Log "DEPLOYMENT FAILED: $($_.Exception.Message)" -Level Error
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
        Write-Log "Full log saved to: $logPath" -Level Error
        throw
    }
}

# Execute deployment
Start-Deployment
