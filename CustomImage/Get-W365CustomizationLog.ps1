#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieves Azure Image Builder customization logs from staging storage account.

.DESCRIPTION
    Downloads Packer customization logs from the Azure Image Builder staging resource group
    to help troubleshoot build failures. Prompts for storage account details and saves
    logs to the Documents folder with a timestamp.

.EXAMPLE
    .\Get-W365CustomizationLog.ps1

.NOTES
    Author: Windows 365 Custom Image Automation
    Version: 1.0
    Requires: Az.Storage PowerShell module
#>

[CmdletBinding()]
param()

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $colors = @{
        Info = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error = 'Red'
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Show-Menu {
    param(
        [string]$Title,
        [array]$Items,
        [string]$PropertyName
    )
    
    Write-Log "" -Level Info
    Write-Log "=== $Title ===" -Level Info
    Write-Log "" -Level Info
    
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($PropertyName) {
            Write-Host "  [$($i + 1)] $($Items[$i].$PropertyName)"
        }
        else {
            Write-Host "  [$($i + 1)] $($Items[$i])"
        }
    }
    
    Write-Log "" -Level Info
    
    do {
        $selection = Read-Host "Select number [1-$($Items.Count)]"
        $selectedIndex = $selection -as [int]
        
        if ($selectedIndex -ge 1 -and $selectedIndex -le $Items.Count) {
            return $Items[$selectedIndex - 1]
        }
        else {
            Write-Log "Invalid selection. Please choose a number between 1 and $($Items.Count)" -Level Warning
        }
    } while ($true)
}

# Main script execution
try {
    Write-Log "=== Azure Image Builder Customization Log Retrieval ===" -Level Info
    Write-Log "" -Level Info
    
    # Check if Az.Storage module is available
    Write-Log "Checking for Az.Storage module..." -Level Info
    if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
        Write-Log "Installing Az.Storage module..." -Level Warning
        Install-Module -Name Az.Storage -Repository PSGallery -Force -AllowClobber -Scope CurrentUser
    }
    
    Import-Module Az.Storage -Force
    Write-Log "Az.Storage module loaded" -Level Success
    Write-Log "" -Level Info
    
    # Connect to Azure if not already connected
    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $azContext) {
        Write-Log "No Azure context found. Connecting to Azure..." -Level Warning
        Connect-AzAccount
        $azContext = Get-AzContext
    }
    
    Write-Log "Connected to Azure as: $($azContext.Account.Id)" -Level Success
    Write-Log "Subscription: $($azContext.Subscription.Name)" -Level Info
    
    # Step 1: Select Resource Group
    Write-Log "Retrieving resource groups..." -Level Info
    $allResourceGroups = Get-AzResourceGroup
    
    # Filter for Image Builder staging resource groups (starting with IT_)
    $stagingResourceGroups = $allResourceGroups | Where-Object { $_.ResourceGroupName -like "IT_*" }
    
    if ($stagingResourceGroups.Count -eq 0) {
        Write-Log "No Image Builder staging resource groups found (starting with IT_)" -Level Warning
        Write-Log "Showing all resource groups instead..." -Level Info
        $resourceGroupsToShow = $allResourceGroups
    }
    else {
        Write-Log "Found $($stagingResourceGroups.Count) Image Builder staging resource group(s)" -Level Success
        $resourceGroupsToShow = $stagingResourceGroups
    }
    
    $selectedRG = Show-Menu -Title "Select Resource Group" -Items $resourceGroupsToShow -PropertyName "ResourceGroupName"
    $resourceGroup = $selectedRG.ResourceGroupName
    Write-Log "Selected: $resourceGroup" -Level Success
    
    # Step 2: Select Storage Account
    Write-Log "Retrieving storage accounts in resource group..." -Level Info
    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $resourceGroup
    
    if ($storageAccounts.Count -eq 0) {
        Write-Log "No storage accounts found in resource group: $resourceGroup" -Level Error
        throw "No storage accounts available"
    }
    
    Write-Log "Found $($storageAccounts.Count) storage account(s)" -Level Success
    $selectedSA = Show-Menu -Title "Select Storage Account" -Items $storageAccounts -PropertyName "StorageAccountName"
    $storageAccount = $selectedSA.StorageAccountName
    Write-Log "Selected: $storageAccount" -Level Success
    
    # Get storage account key
    Write-Log "Retrieving storage account key..." -Level Info
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccount)[0].Value
    $context = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageKey
    Write-Log "Storage context created" -Level Success
    
    # Step 3: Select Container
    Write-Log "Retrieving containers..." -Level Info
    $containers = Get-AzStorageContainer -Context $context
    
    if ($containers.Count -eq 0) {
        Write-Log "No containers found in storage account: $storageAccount" -Level Error
        throw "No containers available"
    }
    
    Write-Log "Found $($containers.Count) container(s)" -Level Success
    $selectedContainer = Show-Menu -Title "Select Container" -Items $containers -PropertyName "Name"
    $container = $selectedContainer.Name
    Write-Log "Selected: $container" -Level Success
    
    # Step 4: Select Blob
    Write-Log "Retrieving blobs from container..." -Level Info
    $blobs = Get-AzStorageBlob -Container $container -Context $context
    
    if ($blobs.Count -eq 0) {
        Write-Log "No blobs found in container: $container" -Level Error
        throw "No blobs available"
    }
    
    Write-Log "Found $($blobs.Count) blob(s)" -Level Success
    
    # Filter for .log files if there are many blobs
    $logBlobs = $blobs | Where-Object { $_.Name -like "*.log" }
    if ($logBlobs.Count -gt 0 -and $logBlobs.Count -lt $blobs.Count) {
        Write-Log "Filtering to show only .log files ($($logBlobs.Count) found)" -Level Info
        $blobsToShow = $logBlobs
    }
    else {
        $blobsToShow = $blobs
    }
    
    $selectedBlob = Show-Menu -Title "Select Blob (Log File)" -Items $blobsToShow -PropertyName "Name"
    $blobName = $selectedBlob.Name
    Write-Log "Selected: $blobName" -Level Success
    
    Write-Log "" -Level Info
    Write-Log "Configuration Summary:" -Level Info
    Write-Log "  Storage Account: $storageAccount" -Level Info
    Write-Log "  Resource Group: $resourceGroup" -Level Info
    Write-Log "  Container: $container" -Level Info
    Write-Log "  Blob: $blobName" -Level Info
    Write-Log "" -Level Info
    
    # Generate timestamped filename
    $timestamp = Get-Date -Format 'yyyy-MM-dd-HH-mm'
    $logFileName = "get-w365customization-$timestamp.log"
    $logFilePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath $logFileName
    
    Write-Log "Output file: $logFilePath" -Level Info
    Write-Log "" -Level Info
    
    # Download the blob
    Write-Log "Downloading customization log..." -Level Info
    try {
        Get-AzStorageBlobContent `
            -Container $container `
            -Blob $blobName `
            -Destination $logFilePath `
            -Context $context `
            -Force `
            -ErrorAction Stop | Out-Null
        
        Write-Log "Log downloaded successfully!" -Level Success
    }
    catch {
        Write-Log "Failed to download blob. Error: $($_.Exception.Message)" -Level Error
        throw
    }
    
    Write-Log "" -Level Info
    Write-Log "=== Log File Contents (Last 100 lines) ===" -Level Info
    Write-Log "" -Level Info
    
    # Display the log content
    $logContent = Get-Content $logFilePath -Tail 100
    foreach ($line in $logContent) {
        Write-Host $line
    }
    
    Write-Log "" -Level Info
    Write-Log "=== Summary ===" -Level Success
    Write-Log "Full log saved to: $logFilePath" -Level Success
    Write-Log "Total lines in log: $((Get-Content $logFilePath).Count)" -Level Info
    Write-Log "" -Level Info
    Write-Log "To view the full log:" -Level Info
    Write-Log "  notepad `"$logFilePath`"" -Level Info
    Write-Log "" -Level Info
    Write-Log "Look for errors related to:" -Level Info
    Write-Log "  - PowerShell script execution failures" -Level Info
    Write-Log "  - Winget installation errors" -Level Info
    Write-Log "  - Windows Update failures" -Level Info
    Write-Log "  - Network connectivity issues" -Level Info
    
}
catch {
    Write-Log "" -Level Error
    Write-Log "Failed to retrieve customization log: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
