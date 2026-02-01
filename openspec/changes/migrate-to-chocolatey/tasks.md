## 1. Change Management

- [x] 1.1 Archive `update-winget-installation` change (superseded by this change)

## 2. Implementation

- [x] 2.1 Update `Invoke-W365ImageCustomization.ps1`:
  - Remove Winget detection and path resolution logic (lines 56-100)
  - Replace Winget package list with Chocolatey package list:
    - `7zip` (7-Zip)
    - `vscode` (Visual Studio Code)
    - `googlechrome` (Google Chrome)
    - `adobereader` (Adobe Acrobat Reader)
  - Replace Winget install loop with Chocolatey install commands
  - Update stage comments to reflect Chocolatey usage
- [x] 2.2 Consolidate Stage 1 (Applications) and Stage 2 (M365 Apps) into single Chocolatey installation stage
- [x] 2.3 Update logging messages to reference Chocolatey instead of Winget

## 3. Documentation

- [x] 3.1 Update `CustomImage/SPECIFICATION.md`:
  - Change "via Winget" to "via Chocolatey" in Stage 1 description
  - Update "Customization Options" section with Chocolatey package names
  - Update version history
- [x] 3.2 Update `openspec/project.md`:
  - Remove Winget as primary package manager
  - Update Tech Stack to reflect Chocolatey-only approach
  - Update External Dependencies section

## 4. Validation

- [ ] 4.1 Test script execution on a Windows 11 VM via Azure Run Command
- [ ] 4.2 Verify all four applications install successfully under SYSTEM context
- [ ] 4.3 Verify M365 Apps continue to install successfully
- [ ] 4.4 Verify log output shows correct status for each installation
