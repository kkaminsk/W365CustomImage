<#
.SYNOPSIS
    Customizes Windows 11 VM for Windows 365 managed image

.DESCRIPTION
    This script runs on the build VM to:
    - Install applications via Winget (VSCode, 7-Zip, Chrome, Adobe Reader)
    - Install Microsoft 365 Apps via Chocolatey (Word, Excel, PowerPoint, Outlook, OneNote, Teams)
    - Configure Windows settings (timezone, Explorer, disable tips)
    - Run Windows Update
    - Optimize system (disable telemetry, clean temp files)

    All operations are logged.

.EXAMPLE
    .\Invoke-W365ImageCustomization.ps1
#>

[CmdletBinding()]
param()

# Set strict error handling
$ErrorActionPreference = "Continue"  # Continue on errors to complete as much as possible
Set-StrictMode -Version Latest

# Initialize logging
$logPath = "C:\Windows\Temp\w365-customization.log"

function Write-CustomLog {
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
    Write-CustomLog "=== Windows 365 Image Customization Started ===" -Level Info
    Write-CustomLog "Log file: $logPath" -Level Info
    
    # Stage 1: Install Applications via Winget
    Write-CustomLog "Stage 1: Installing applications via Winget..." -Level Info

    # Find winget executable - required for SYSTEM context (Invoke-AzVMRunCommand)
    $wingetPath = $null
    $wingetSearchPaths = @(
        "${env:ProgramFiles}\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe",
        "${env:LOCALAPPDATA}\Microsoft\WindowsApps\winget.exe",
        "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    )
    
    foreach ($searchPath in $wingetSearchPaths) {
        $found = Get-Item -Path $searchPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $wingetPath = $found.FullName
            break
        }
    }
    
    if (-not $wingetPath) {
        Write-CustomLog "Winget not found. Attempting to install/repair Windows Package Manager..." -Level Warning
        
        # Try to register the AppX package for SYSTEM context
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            
            # Search again
            foreach ($searchPath in $wingetSearchPaths) {
                $found = Get-Item -Path $searchPath -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $wingetPath = $found.FullName
                    break
                }
            }
        }
        catch {
            Write-CustomLog "Failed to register AppInstaller: $($_.Exception.Message)" -Level Warning
        }
    }
    
    if ($wingetPath) {
        Write-CustomLog "Found winget at: $wingetPath" -Level Info
    }
    else {
        Write-CustomLog "Winget not available - skipping winget installations" -Level Error
        Write-CustomLog "Packages will need to be installed manually or via alternative method" -Level Warning
    }

    $packages = @(
        @{ Id = '7zip.7zip'; DisplayName = '7-Zip' }
        @{ Id = 'Microsoft.VisualStudioCode'; DisplayName = 'Visual Studio Code' }
        @{ Id = 'Google.Chrome'; DisplayName = 'Google Chrome' }
        @{ Id = 'Adobe.Acrobat.Reader.64-bit'; DisplayName = 'Adobe Acrobat Reader' }
    )

    if ($wingetPath) {
        foreach ($package in $packages) {
            try {
                Write-CustomLog "Installing $($package.DisplayName)..." -Level Info
                
                # Use full path to winget and --scope machine for SYSTEM context
                $processArgs = @(
                    "install"
                    $package.Id
                    "--silent"
                    "--accept-package-agreements"
                    "--accept-source-agreements"
                    "--scope", "machine"
                    "--disable-interactivity"
                )
                
                $process = Start-Process -FilePath $wingetPath -ArgumentList $processArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget_stdout.txt" -RedirectStandardError "$env:TEMP\winget_stderr.txt"
                
                $stdout = Get-Content "$env:TEMP\winget_stdout.txt" -Raw -ErrorAction SilentlyContinue
                $stderr = Get-Content "$env:TEMP\winget_stderr.txt" -Raw -ErrorAction SilentlyContinue
                
                if ($process.ExitCode -eq 0) {
                    Write-CustomLog "$($package.DisplayName) installed successfully" -Level Success
                }
                else {
                    Write-CustomLog "$($package.DisplayName) installation returned exit code $($process.ExitCode)" -Level Warning
                    if ($stdout) { Write-CustomLog "Output: $stdout" -Level Warning }
                    if ($stderr) { Write-CustomLog "Error: $stderr" -Level Warning }
                }
            }
            catch {
                Write-CustomLog "Failed to install $($package.DisplayName): $($_.Exception.Message)" -Level Error
            }
        }
    }

    # Stage 2: Install Microsoft 365 Apps via Chocolatey
    Write-CustomLog "Stage 2: Installing Microsoft 365 Apps..." -Level Info

    try {
        # Install Chocolatey package manager
        Write-CustomLog "Installing Chocolatey package manager..." -Level Info
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

            # Refresh environment to pick up choco
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            Write-CustomLog "Chocolatey installed successfully" -Level Success
        }
        else {
            Write-CustomLog "Chocolatey already installed" -Level Info
        }

        # Install Microsoft 365 Apps using Office Deployment Tool via Chocolatey
        Write-CustomLog "Installing Microsoft 365 Apps (64-bit, O365ProPlusRetail, Current Channel)..." -Level Info
        Write-CustomLog "Excluding: Publisher, Groove (OneDrive sync), Access" -Level Info

        $chocoResult = choco install microsoft-office-deployment --params="'/64bit /Product:O365ProPlusRetail /Channel:Current /Exclude:Publisher,Groove,Access'" -y 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-CustomLog "Microsoft 365 Apps installed successfully" -Level Success
        }
        else {
            Write-CustomLog "Microsoft 365 Apps installation returned exit code $LASTEXITCODE" -Level Warning
            Write-CustomLog "Output: $chocoResult" -Level Warning
        }
    }
    catch {
        Write-CustomLog "Failed to install Microsoft 365 Apps: $($_.Exception.Message)" -Level Error
        Write-CustomLog "Continuing with remaining customizations..." -Level Warning
    }

    # Stage 3: Configure Windows Settings
    Write-CustomLog "Stage 3: Configuring Windows settings..." -Level Info
    
    try {
        # Set timezone to Eastern
        Write-CustomLog "Setting timezone to Eastern Standard Time..." -Level Info
        Set-TimeZone -Id "Eastern Standard Time" -ErrorAction SilentlyContinue
        Write-CustomLog "Timezone configured" -Level Success
    }
    catch {
        Write-CustomLog "Failed to set timezone: $($_.Exception.Message)" -Level Error
    }
    
    try {
        # Configure Explorer settings
        Write-CustomLog "Configuring Explorer settings..." -Level Info
        
        # Show file extensions
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -ErrorAction SilentlyContinue
        
        # Show hidden files
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -ErrorAction SilentlyContinue
        
        Write-CustomLog "Explorer settings configured" -Level Success
    }
    catch {
        Write-CustomLog "Failed to configure Explorer settings: $($_.Exception.Message)" -Level Error
    }
    
    try {
        # Disable Windows tips and suggestions
        Write-CustomLog "Disabling Windows tips and suggestions..." -Level Info
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0 -ErrorAction SilentlyContinue
        Write-CustomLog "Windows tips disabled" -Level Success
    }
    catch {
        Write-CustomLog "Failed to disable Windows tips: $($_.Exception.Message)" -Level Error
    }
    
    # Stage 4: Run Windows Update
    Write-CustomLog "Stage 4: Running Windows Update..." -Level Info
    try {
        # Install PSWindowsUpdate module if not present
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-CustomLog "Installing PSWindowsUpdate module..." -Level Info
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
            Install-Module -Name PSWindowsUpdate -Force -ErrorAction SilentlyContinue
        }
        
        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
        
        Write-CustomLog "Installing Windows Updates (excluding previews)..." -Level Info
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -NotCategory "Preview" -ErrorAction SilentlyContinue
        Write-CustomLog "Windows Updates completed" -Level Success
    }
    catch {
        Write-CustomLog "Windows Update process encountered errors: $($_.Exception.Message)" -Level Warning
        Write-CustomLog "Continuing with remaining customizations..." -Level Warning
    }
    
    # Stage 5: Optimization and Cleanup
    Write-CustomLog "Stage 5: Optimizing and cleaning up..." -Level Info
    
    try {
        # Disable telemetry
        Write-CustomLog "Disabling telemetry..." -Level Info
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -ErrorAction SilentlyContinue
        Write-CustomLog "Telemetry disabled" -Level Success
    }
    catch {
        Write-CustomLog "Failed to disable telemetry: $($_.Exception.Message)" -Level Error
    }
    
    try {
        # Clean temp files
        Write-CustomLog "Cleaning temporary files..." -Level Info
        Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-CustomLog "Temporary files cleaned" -Level Success
    }
    catch {
        Write-CustomLog "Failed to clean temp files: $($_.Exception.Message)" -Level Error
    }
    
    try {
        # Clear event logs
        Write-CustomLog "Clearing event logs..." -Level Info
        Get-EventLog -LogName * -ErrorAction SilentlyContinue | ForEach-Object { Clear-EventLog -LogName $_.Log -ErrorAction SilentlyContinue }
        Write-CustomLog "Event logs cleared" -Level Success
    }
    catch {
        Write-CustomLog "Failed to clear event logs: $($_.Exception.Message)" -Level Error
    }
    
    Write-CustomLog "=== Customization Completed Successfully ===" -Level Success
    Write-CustomLog "VM is ready for sysprep" -Level Success
    
    exit 0
}
catch {
    Write-CustomLog "CRITICAL ERROR: $($_.Exception.Message)" -Level Error
    Write-CustomLog "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
