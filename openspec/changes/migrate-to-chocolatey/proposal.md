## Why

Winget cannot run in the correct security context when executing via Azure Run Command (SYSTEM context). The `winget install` commands fail or are unreliable because Winget is designed to run in a user context and has limited support for machine-wide installations under SYSTEM.

Chocolatey, by contrast, is designed for automation and runs reliably in SYSTEM context, making it the appropriate choice for Azure VM image building scenarios.

## What Changes

- Replace Winget-based application installation with Chocolatey for ALL applications:
  - 7-Zip (`7zip`)
  - Visual Studio Code (`vscode`)
  - Google Chrome (`googlechrome`)
  - Adobe Acrobat Reader (`adobereader`)
- Consolidate all application installations into a single Chocolatey-based stage
- Remove Winget detection and fallback logic from the customization script
- Microsoft 365 Apps installation remains unchanged (already uses Chocolatey)

## Impact

- Affected code: `CustomImage/Invoke-W365ImageCustomization.ps1`
- Affected documentation: `CustomImage/SPECIFICATION.md`, `openspec/project.md`
- **Reliability**: Eliminates SYSTEM context failures that occur with Winget
- **Simplification**: Single package manager (Chocolatey) for all applications
- **Consistency**: All apps installed via same method, same logging pattern
- **No breaking changes**: Output image contains identical applications
- Supersedes: `update-winget-installation` change (reverts to Chocolatey approach)

## Dependencies

- Requires archiving or removing the `update-winget-installation` change
- Builds on existing `add-m365-apps` change (Chocolatey already installed for M365)
