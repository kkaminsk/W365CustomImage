## 1. Implementation

- [x] 1.1 Add Chocolatey installation function to `Invoke-W365ImageCustomization.ps1`
- [x] 1.2 Add M365 Apps installation stage after Winget packages
- [x] 1.3 Configure installation parameters (64-bit, O365ProPlusRetail, Current Channel, exclusions)
- [x] 1.4 Add logging for M365 installation progress and status
- [x] 1.5 Update documentation in README.md to document M365 inclusion

## 2. Validation

- [ ] 2.1 Test full image build with M365 Apps installation
- [ ] 2.2 Verify M365 Apps launch correctly in captured image
- [ ] 2.3 Confirm excluded apps (Publisher, Groove, Access) are not present
- [ ] 2.4 Validate image can be used in Windows 365 provisioning policy
