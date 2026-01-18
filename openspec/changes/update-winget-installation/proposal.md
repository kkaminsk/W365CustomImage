## Why

The current image customization uses Chocolatey for application installation. Winget (Windows Package Manager) is Microsoft's native package manager, pre-installed on Windows 11, providing a more integrated and reliable installation experience without requiring third-party package manager setup.

## What Changes

- Replace Chocolatey package installation with Winget commands for:
  - 7-Zip
  - Visual Studio Code
  - Google Chrome
  - Adobe Acrobat Reader
- Remove Chocolatey installation stage from `Invoke-W365ImageCustomization.ps1`
- Update package installation logic to use `winget install` with appropriate flags

## Impact

- Affected code: `CustomImage/Invoke-W365ImageCustomization.ps1`
- **Simplification**: Removes Chocolatey as a dependency (no need to install package manager first)
- **Reliability**: Winget is pre-installed on Windows 11, reducing failure points
- **Maintenance**: Microsoft-maintained package sources are typically more current
- **No breaking changes**: Output image contains same applications
