## MODIFIED Requirements

### Requirement: Application Installation via Chocolatey

The image customization script SHALL install all applications using Chocolatey package manager with silent, non-interactive flags. Chocolatey is required because it operates reliably in SYSTEM context (Azure Run Command), unlike Winget which has security context limitations.

#### Scenario: Install Chocolatey package manager
- **WHEN** the customization script executes
- **THEN** Chocolatey SHALL be installed using the official installation script from `https://chocolatey.org/install.ps1` if not already present

#### Scenario: Install 7-Zip via Chocolatey
- **WHEN** the customization script executes
- **THEN** 7-Zip SHALL be installed using `choco install 7zip -y`

#### Scenario: Install Visual Studio Code via Chocolatey
- **WHEN** the customization script executes
- **THEN** Visual Studio Code SHALL be installed using `choco install vscode -y`

#### Scenario: Install Google Chrome via Chocolatey
- **WHEN** the customization script executes
- **THEN** Google Chrome SHALL be installed using `choco install googlechrome -y`

#### Scenario: Install Adobe Acrobat Reader via Chocolatey
- **WHEN** the customization script executes
- **THEN** Adobe Acrobat Reader SHALL be installed using `choco install adobereader -y`

#### Scenario: Installation logging
- **WHEN** each application is installed
- **THEN** the script SHALL log the installation status (success/failure) with the application name

#### Scenario: Continue on failure
- **WHEN** an application installation fails
- **THEN** the script SHALL log the error and continue installing remaining applications

## REMOVED Requirements

### Requirement: Winget Application Installation

**Reason**: Winget cannot run reliably in SYSTEM security context when executed via Azure Run Command. The package manager is designed for user-context operations and fails or behaves unpredictably when running as SYSTEM.

**Migration**: Replace all Winget install commands with equivalent Chocolatey commands. Remove Winget path detection and fallback logic.

**Affected scenarios being removed**:
- Install 7-Zip via Winget
- Install Visual Studio Code via Winget
- Install Google Chrome via Winget
- Install Adobe Acrobat Reader via Winget
