## ADDED Requirements

### Requirement: Chocolatey Package Manager for M365 Deployment

The image customization script SHALL install Chocolatey package manager to enable Microsoft 365 Apps deployment via the Office Deployment Tool wrapper.

#### Scenario: Install Chocolatey
- **WHEN** the customization script executes
- **THEN** Chocolatey SHALL be installed using the official installation script from `https://chocolatey.org/install.ps1`

#### Scenario: Chocolatey installation logging
- **WHEN** Chocolatey is installed
- **THEN** the script SHALL log whether installation succeeded or failed

### Requirement: Microsoft 365 Apps Installation

The image customization script SHALL install Microsoft 365 Apps for enterprise using the Chocolatey `microsoft-office-deployment` package with enterprise-appropriate configuration.

#### Scenario: Install M365 Apps via Chocolatey ODT
- **WHEN** the customization script executes
- **THEN** Microsoft 365 Apps SHALL be installed using:
  ```
  choco install microsoft-office-deployment --params="'/64bit /Product:O365ProPlusRetail /Channel:Current /Exclude:Publisher,Groove,Access'" -y
  ```

#### Scenario: 64-bit architecture
- **WHEN** M365 Apps are installed
- **THEN** the 64-bit version SHALL be installed (not 32-bit)

#### Scenario: O365ProPlusRetail product
- **WHEN** M365 Apps are installed
- **THEN** the O365ProPlusRetail product (Microsoft 365 Apps for enterprise) SHALL be installed

#### Scenario: Current Channel updates
- **WHEN** M365 Apps are installed
- **THEN** apps SHALL be configured to receive updates from the Current Channel

#### Scenario: Excluded applications
- **WHEN** M365 Apps are installed
- **THEN** Publisher, Groove (OneDrive for Business sync client), and Access SHALL NOT be installed

#### Scenario: Core M365 Apps included
- **WHEN** M365 Apps are installed
- **THEN** Word, Excel, PowerPoint, Outlook, OneNote, and Teams SHALL be installed

#### Scenario: M365 installation logging
- **WHEN** M365 Apps installation completes
- **THEN** the script SHALL log the installation status (success/failure)

#### Scenario: Continue on M365 failure
- **WHEN** M365 Apps installation fails
- **THEN** the script SHALL log the error and continue with remaining customization stages
