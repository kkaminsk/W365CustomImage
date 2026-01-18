#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieves detailed error information from a failed Azure deployment.

.DESCRIPTION
    This script retrieves detailed error messages from a failed deployment using either
    the deployment name or the Azure tracking/correlation ID.

.PARAMETER ResourceGroupName
    The resource group where the deployment failed.

.PARAMETER DeploymentName
    The name of the failed deployment (e.g., 'w365-customimage-deployment-2025-11-16-11-55').

.PARAMETER TrackingId
    The Azure tracking/correlation ID from the error message.

.EXAMPLE
    .\Get-DeploymentError.ps1 -ResourceGroupName "rg-st1-customimage" -DeploymentName "w365-customimage-deployment-2025-11-16-11-55"

.EXAMPLE
    .\Get-DeploymentError.ps1 -TrackingId "d9597619-197f-4e4b-b02a-7d2658953fa8"
#>

[CmdletBinding(DefaultParameterSetName = 'ByDeployment')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ByDeployment')]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'ByDeployment')]
    [string]$DeploymentName,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'ByTracking')]
    [string]$TrackingId
)

$ErrorActionPreference = "Stop"

function Write-ErrorDetails {
    param(
        [object]$Error,
        [int]$Indent = 0
    )
    
    $prefix = "  " * $Indent
    
    if ($Error.code) {
        Write-Host "${prefix}Error Code: $($Error.code)" -ForegroundColor Red
    }
    
    if ($Error.message) {
        Write-Host "${prefix}Message: $($Error.message)" -ForegroundColor Yellow
    }
    
    if ($Error.target) {
        Write-Host "${prefix}Target: $($Error.target)" -ForegroundColor Gray
    }
    
    if ($Error.details) {
        Write-Host "${prefix}Details:" -ForegroundColor Cyan
        foreach ($detail in $Error.details) {
            Write-ErrorDetails -Error $detail -Indent ($Indent + 1)
        }
    }
}

try {
    # Check Azure connection
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context) {
        Write-Host "ERROR: Not connected to Azure. Run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure Deployment Error Details" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor Gray
    Write-Host ""
    
    if ($PSCmdlet.ParameterSetName -eq 'ByDeployment') {
        Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan
        Write-Host "Deployment: $DeploymentName" -ForegroundColor Cyan
        Write-Host ""
        
        # Get deployment details
        Write-Host "Fetching deployment details..." -ForegroundColor Yellow
        $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -ErrorAction Stop
        
        Write-Host "`nDeployment Status: $($deployment.ProvisioningState)" -ForegroundColor $(if ($deployment.ProvisioningState -eq 'Failed') { 'Red' } else { 'Yellow' })
        Write-Host "Timestamp: $($deployment.Timestamp)" -ForegroundColor Gray
        
        if ($deployment.Properties.Error) {
            Write-Host "`n========================================" -ForegroundColor Red
            Write-Host "ERROR DETAILS" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-ErrorDetails -Error $deployment.Properties.Error
        }
        
        # Get deployment operations
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "DEPLOYMENT OPERATIONS" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        
        $operations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $ResourceGroupName -DeploymentName $DeploymentName -ErrorAction SilentlyContinue
        
        if ($operations) {
            $failedOps = $operations | Where-Object { $_.Properties.ProvisioningState -eq 'Failed' }
            
            if ($failedOps) {
                foreach ($op in $failedOps) {
                    Write-Host "`nOperation: $($op.Properties.TargetResource.ResourceType)" -ForegroundColor Yellow
                    Write-Host "Resource: $($op.Properties.TargetResource.ResourceName)" -ForegroundColor Gray
                    Write-Host "Status: $($op.Properties.ProvisioningState)" -ForegroundColor Red
                    
                    if ($op.Properties.StatusMessage.error) {
                        Write-Host "Error Details:" -ForegroundColor Red
                        Write-ErrorDetails -Error $op.Properties.StatusMessage.error -Indent 1
                    }
                }
            }
            else {
                Write-Host "No failed operations found (validation error occurred before resource deployment)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "No deployment operations found" -ForegroundColor Yellow
        }
    }
    else {
        # Search by tracking ID in Activity Log
        Write-Host "Tracking ID: $TrackingId" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Searching Activity Log (this may take a moment)..." -ForegroundColor Yellow
        
        $endTime = Get-Date
        $startTime = $endTime.AddHours(-2)
        
        $logs = Get-AzActivityLog -StartTime $startTime -EndTime $endTime -CorrelationId $TrackingId -ErrorAction SilentlyContinue
        
        if ($logs) {
            foreach ($log in $logs) {
                Write-Host "`n========================================" -ForegroundColor Cyan
                Write-Host "Activity Log Entry" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "Operation: $($log.OperationName.Value)" -ForegroundColor Gray
                Write-Host "Status: $($log.Status.Value)" -ForegroundColor $(if ($log.Status.Value -eq 'Failed') { 'Red' } else { 'Yellow' })
                Write-Host "Resource: $($log.ResourceId)" -ForegroundColor Gray
                Write-Host "Time: $($log.EventTimestamp)" -ForegroundColor Gray
                
                if ($log.Properties) {
                    Write-Host "`nProperties:" -ForegroundColor Cyan
                    $log.Properties | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor Gray
                }
            }
        }
        else {
            Write-Host "No activity logs found for tracking ID: $TrackingId" -ForegroundColor Yellow
            Write-Host "The tracking ID may be from an older deployment (>2 hours ago)" -ForegroundColor Gray
        }
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "TIP: Check Azure Portal > Resource Group > Deployments for more details" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
