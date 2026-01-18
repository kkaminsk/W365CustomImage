<#
.SYNOPSIS
    Executes sysprep on Windows 11 VM for Windows 365 managed image

.DESCRIPTION
    This script runs sysprep with Windows 365-compliant parameters:
    - /generalize - Removes system-specific information
    - /oobe - Boots to out-of-box experience
    - /shutdown - Shuts down VM after sysprep
    
    The VM will automatically shut down when sysprep completes.

.EXAMPLE
    .\Invoke-W365Sysprep.ps1
#>

[CmdletBinding()]
param()

# Set strict error handling
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Initialize logging
$logPath = "C:\Windows\Temp\w365-sysprep.log"

function Write-SysprepLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    Write-Host $logMessage
    
    # Write to log file
    Add-Content -Path $logPath -Value $logMessage -ErrorAction SilentlyContinue
}

try {
    Write-SysprepLog "=== Windows 365 Sysprep Process Started ===" -Level Info
    Write-SysprepLog "Log file: $logPath" -Level Info
    
    # Verify sysprep executable exists
    $sysprepPath = "C:\Windows\System32\Sysprep\sysprep.exe"
    if (-not (Test-Path $sysprepPath)) {
        Write-SysprepLog "Sysprep executable not found at $sysprepPath" -Level Error
        exit 1
    }
    
    Write-SysprepLog "Sysprep executable found: $sysprepPath" -Level Success
    
    # Check if VM is already generalized
    $setupStateKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State"
    if (Test-Path $setupStateKey) {
        $imageState = Get-ItemProperty -Path $setupStateKey -Name "ImageState" -ErrorAction SilentlyContinue
        if ($imageState.ImageState -eq "IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE") {
            Write-SysprepLog "VM is already in generalized state" -Level Warning
            Write-SysprepLog "Sysprep may have already been run" -Level Warning
        }
    }
    
    # Log current VM state
    Write-SysprepLog "Current computer name: $env:COMPUTERNAME" -Level Info
    Write-SysprepLog "Current user: $env:USERNAME" -Level Info
    
    # Execute sysprep with Windows 365 compliant parameters
    Write-SysprepLog "Executing sysprep with parameters: /generalize /oobe /shutdown" -Level Info
    Write-SysprepLog "VM will shut down automatically when sysprep completes" -Level Info
    Write-SysprepLog "This may take 5-15 minutes..." -Level Info
    
    # Start sysprep process
    $sysprepArgs = "/generalize /oobe /shutdown"
    
    Write-SysprepLog "Starting sysprep..." -Level Info
    Write-SysprepLog "Command: $sysprepPath $sysprepArgs" -Level Info
    
    # Run sysprep
    Start-Process -FilePath $sysprepPath -ArgumentList $sysprepArgs -Wait -NoNewWindow
    
    # Note: This line will likely not execute because sysprep shuts down the VM
    Write-SysprepLog "Sysprep process completed" -Level Success
    Write-SysprepLog "VM should be shutting down..." -Level Info
    
    exit 0
}
catch {
    Write-SysprepLog "CRITICAL ERROR during sysprep: $($_.Exception.Message)" -Level Error
    Write-SysprepLog "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
