# SystemConfiguration Module - Complete OS Settings Reference

## Overview
This document catalogs **every registry key, service, policy, and setting** that the SystemConfiguration Type1/Type2 modules modify on Windows 10/11 systems. Organized by category with one-line explanations and OS version dependency notes.

---

## Table of Contents
1. [System Restore Points](#system-restore-points)
2. [Registry Settings - Security](#registry-settings---security)
3. [Registry Settings - Telemetry & Privacy](#registry-settings---telemetry--privacy)
4. [Registry Settings - Optimization](#registry-settings---optimization)
5. [Windows Defender Configuration](#windows-defender-configuration)
6. [Windows Firewall Configuration](#windows-firewall-configuration)
7. [Security Policy (secedit)](#security-policy-secedit)
8. [Advanced Audit Policy (auditpol)](#advanced-audit-policy-auditpol)
9. [Services - Security (ensure enabled)](#services---security-ensure-enabled)
10. [Services - Security (ensure disabled)](#services---security-ensure-disabled)
11. [Services - Telemetry (disable)](#services---telemetry-disable)
12. [Services - Optimization (disable)](#services---optimization-disable)
13. [Scheduled Tasks (disable)](#scheduled-tasks-disable)
14. [Sysmon Installation & Configuration](#sysmon-installation--configuration)

---

## System Restore Points
| Setting | Path / Command | Purpose | Notes |
|---------|---|---------|-------|
| **Restore Point Creation** | WMI `root/default:SystemRestore` | Creates a system restore point before any changes | Unconditional; taken every run as rollback safety net |
| **Creation Frequency Throttle** | `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore` → `SystemRestorePointCreationFrequency` | Removes Windows' default 24-hour throttle | Allows multiple restore points per day |
| **Restore Point Pruning** | `vssadmin.exe` or WMI `Remove-CimInstance` | Deletes restore points older than the 5 newest | Runs LAST after all other changes succeed |
| **System Restore Enable** | WMI `Invoke-CimMethod Enable` for system drive | Ensures System Restore is active for rollback | Applied to all drives before creation |

---

## Registry Settings - Security

### Core System Security (UAC & Access Control)
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 2.3.17.1 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `FilterAdministratorToken` | DWord | `1` | Enable UAC: Admin Approval Mode for Built-in Admin account | Both |
| 2.3.17.2 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `ConsentPromptBehaviorAdmin` | DWord | `2` | UAC: Prompt for consent on secure desktop for admins | Both |
| 2.3.17.3 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `ConsentPromptBehaviorUser` | DWord | `0` | UAC: Auto deny elevation prompts for standard users | Both |
| 2.3.17.5 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `EnableLUA` | DWord | `1` | Ensure UAC is enabled | Both |
| 1.1.6 | `HKLM:\System\CurrentControlSet\Control\SAM` | `RelaxMinimumPasswordLengthLimits` | DWord | `1` | Allow passwords > 14 characters in length | Both |
| 2.3.1.1 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `NoConnectedUser` | DWord | `3` | Block Microsoft account sign-in; require local account | Both |
| 2.3.7.1 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `DisableCAD` | DWord | `0` | Require CTRL+ALT+DEL before logon | Both |
| 2.3.7.2 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `DontDisplayLastUserName` | DWord | `1` | Hide last signed-in username on logon screen | Both |
| 2.3.7.3 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `MaxDevicePasswordFailedAttempts` | DWord | `10` | Machine account lockout threshold after 10 failed attempts | Both |
| 2.3.7.4 | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System` | `InactivityTimeoutSecs` | DWord | `900` | Lock machine after 15 minutes of inactivity | Both |
| 2.3.7.5 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` | `LegalNoticeText` | String | Custom notice | Display legal warning text on logon screen | Both |
| 2.3.7.6 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` | `LegalNoticeCaption` | String | `WARNING` | Display legal warning title on logon screen | Both |
| 2.3.7.7 | `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon` | `CachedLogonsCount` | String | `4` | Cache only 4 previous logons offline | Both |
| 2.3.7.9 | `HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon` | `ScRemoveOption` | String | `1` | Lock workstation when smart card is removed | Both |

### Network Security & SMB Hardening
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 2.3.4.1 | `HKLM:\System\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers` | `AddPrinterDrivers` | DWord | `1` | Prevent users from installing printer drivers | Both |
| 2.3.8.1 | `HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters` | `RequireSecuritySignature` | DWord | `1` | MS network client: Always require digital signing of SMB | Both |
| 2.3.9.2 | `HKLM:\System\CurrentControlSet\Services\LanManServer\Parameters` | `RequireSecuritySignature` | DWord | `1` | MS network server: Always require digital signing of SMB | Both |
| 2.3.9.3 | `HKLM:\System\CurrentControlSet\Services\LanManServer\Parameters` | `EnableSecuritySignature` | DWord | `1` | MS network server: Digitally sign if client agrees | Both |
| 2.3.9.5 | `HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters` | `SMBServerNameHardeningLevel` | DWord | `1` | Validate SPN (server principal name) in SMB connections | Both |
| 18.6.11.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections` | `NC_AllowNetBridge_NLA` | DWord | `0` | Prohibit Network Bridge creation | Both |
| 18.6.11.3 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections` | `NC_ShowSharedAccessUI` | DWord | `0` | Prohibit Internet Connection Sharing | Both |
| 18.6.11.4 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections` | `NC_StdDomainUserSetLocation` | DWord | `1` | Require elevation to change network location | Both |
| 18.6.8.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation` | `AllowInsecureGuestAuth` | DWord | `0` | Disable insecure guest authentication for SMB | Both |

### NTLM & Authentication Hardening
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 2.3.10.3 | `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa` | `RestrictAnonymous` | DWord | `1` | Restrict SAM enumeration from anonymous connections | Both |
| 2.3.10.4 | `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa` | `DisableDomainCreds` | DWord | `1` | Do not store credentials for network authentication | Both |
| 2.3.11.1 | `HKLM:\System\CurrentControlSet\Control\Lsa` | `UseMachineId` | DWord | `1` | Use machine identity for NTLM authentication | Both |
| 2.3.11.7 | `HKLM:\System\CurrentControlSet\Control\Lsa` | `LmCompatibilityLevel` | DWord | `5` | Enforce NTLMv2 only; refuse LM and NTLM | Both |
| 2.3.11.11 | `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0` | `AuditReceivingNTLMTraffic` | DWord | `2` | Audit all incoming NTLM traffic to the server | Both |
| 2.3.11.12 | `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0` | `RestrictSendingNTLMTraffic` | DWord | `2` | Deny all outgoing NTLM traffic; audit enforcement | Both |

### Firewall Configuration
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 9.1.3 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile` | `DisableNotifications` | DWord | `1` | Domain Firewall: Suppress notifications | Both |
| 9.1.4 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile\Logging` | `LogFilePath` | String | `%SystemRoot%\System32\logfiles\firewall\domainfw.log` | Domain Firewall: Log file path | Both |
| 9.1.5 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile\Logging` | `LogFileSize` | DWord | `16384` | Domain Firewall: Log file max size 16 MB | Both |
| 9.1.6 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile\Logging` | `LogDroppedPackets` | DWord | `1` | Domain Firewall: Log dropped packets | Both |
| 9.1.7 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile\Logging` | `LogSuccessfulConnections` | DWord | `1` | Domain Firewall: Log successful connections | Both |
| 9.2.3 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile` | `DisableNotifications` | DWord | `1` | Private Firewall: Suppress notifications | Both |
| 9.2.4 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile\Logging` | `LogFilePath` | String | `%SystemRoot%\System32\logfiles\firewall\privatefw.log` | Private Firewall: Log file path | Both |
| 9.2.5 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile\Logging` | `LogFileSize` | DWord | `16384` | Private Firewall: Log file max size 16 MB | Both |
| 9.2.6 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile\Logging` | `LogDroppedPackets` | DWord | `1` | Private Firewall: Log dropped packets | Both |
| 9.2.7 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile\Logging` | `LogSuccessfulConnections` | DWord | `1` | Private Firewall: Log successful connections | Both |
| 9.3.3 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile` | `DisableNotifications` | DWord | `1` | Public Firewall: Suppress notifications | Both |
| 9.3.4 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile` | `AllowLocalPolicyMerge` | DWord | `0` | Public Firewall: No local firewall rules merge | Both |
| 9.3.5 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile` | `AllowLocalIPsecPolicyMerge` | DWord | `0` | Public Firewall: No local IPsec rules merge | Both |
| 9.3.6 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile\Logging` | `LogFilePath` | String | `%SystemRoot%\System32\logfiles\firewall\publicfw.log` | Public Firewall: Log file path | Both |
| 9.3.7 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile\Logging` | `LogFileSize` | DWord | `16384` | Public Firewall: Log file max size 16 MB | Both |
| 9.3.8 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile\Logging` | `LogDroppedPackets` | DWord | `1` | Public Firewall: Log dropped packets | Both |
| 9.3.9 | `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile\Logging` | `LogSuccessfulConnections` | DWord | `1` | Public Firewall: Log successful connections | Both |

### Kernel & Boot Security
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.4.4 | `HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config` | `EnableCertPaddingCheck` | DWord | `1` | Enable certificate padding check in signature validation | Both |
| 18.4.5 | `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel` | `DisableExceptionChainValidation` | DWord | `0` | Enable SEHOP (Structured Exception Handler Overflow Protection) | Both |
| 18.9.13.1 | `HKLM:\SYSTEM\CurrentControlSet\Policies\EarlyLaunch` | `DriverLoadPolicy` | DWord | `3` | Block boot drivers with unknown/bad signatures | Both |

### Network & Protocol Hardening
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.4.7 | `HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters` | `NodeType` | DWord | `2` | Use P-node only for NetBIOS (no broadcast) | Both |
| 18.5.4 | `HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Parameters` | `DisableSavePassword` | DWord | `1` | Prevent dial-up password saving | Both |
| 18.5.5 | `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters` | `EnableICMPRedirect` | DWord | `0` | Disable ICMP redirects to prevent redirect attacks | Both |
| 18.5.6 | `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters` | `KeepAliveTime` | DWord | `300000` | TCP KeepAliveTime 300 seconds for stale connection detection | Both |
| 18.5.8 | `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters` | `PerformRouterDiscovery` | DWord | `0` | Disable IRDP router discovery | Both |
| 18.5.11 | `HKLM:\SYSTEM\CurrentControlSet\Services\TCPIP6\Parameters` | `TcpMaxDataRetransmissions` | DWord | `3` | IPv6 TCP max data retransmission attempts | Both |
| 18.5.12 | `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters` | `TcpMaxDataRetransmissions` | DWord | `3` | IPv4 TCP max data retransmission attempts | Both |
| 18.6.4.4 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient` | `EnableMulticast` | DWord | `0` | Disable LLMNR (Link-Local Multicast Name Resolution) | Both |
| 18.6.19.2.1 | `HKLM:\SYSTEM\CurrentControlSet\Services\TCPIP6\Parameters` | `DisabledComponents` | DWord | `255` | Disable all IPv6 components | Both |
| 18.6.20.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WCN\Registrars` | `EnableRegistrars` | DWord | `0` | Disable Windows Connect Now registrars | Both |
| 18.6.20.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WCN\UI` | `DisableWcnUi` | DWord | `1` | Prohibit Windows Connect Now UI wizards | Both |
| 18.6.21.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy` | `fBlockNonDomain` | DWord | `1` | Block non-domain networks when connected to domain | Both |
| 18.6.5.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `EnableFontProviders` | DWord | `0` | Disable Font Provider network download | Both |
| 18.6.10.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Peernet` | `Disabled` | DWord | `1` | Turn off P2P networking services | Both |

### Device & Media Security
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.7.1.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions` | `DenyDeviceIDs` | DWord | `1` | Prevent device installation by Device ID | Both |
| 18.9.7.1.4 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions` | `DenyDeviceClasses` | DWord | `1` | Prevent device installation by device class | Both |
| 18.9.7.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata` | `PreventDeviceMetadataFromNetwork` | DWord | `1` | Prevent device metadata download from Internet | Both |
| 18.10.8.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer` | `NoAutoplayfornonVolume` | DWord | `1` | Disallow AutoPlay for non-volume devices | Both |
| 18.10.8.2 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer` | `NoAutorun` | DWord | `1` | Disable AutoRun command execution on media | Both |
| 18.10.8.3 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer` | `NoDriveTypeAutoRun` | DWord | `255` | Disable AutoPlay for all drive types | Both |
| 18.7.1 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers` | `RegisterSpoolerRemoteRpcEndPoint` | DWord | `2` | Print Spooler: No remote client connections | Both |
| 18.7.2 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers` | `RedirectionguardPolicy` | DWord | `1` | Print Spooler: Enable redirection guard | Both |
| 18.7.3 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers` | `RpcUseNamedPipeProtocol` | DWord | `1` | Print Spooler: Use named pipe for RPC | Both |
| 18.7.4 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers` | `RpcAuthentication` | DWord | `0` | Print Spooler: Default RPC authentication | Both |
| 18.7.5 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers` | `RpcProtocols` | DWord | `7` | Print Spooler: Enable multiple RPC protocols | Both |
| 18.7.7 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers` | `RpcTcpPort` | DWord | `0` | Print Spooler: Use dynamic port for RPC/TCP | Both |
| 18.7.10 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers` | `CopyFilesPolicy` | DWord | `1` | Print Spooler: Limit queue files to color profiles | Both |
| 18.7.12 | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint` | `UpdatePromptSettings` | DWord | `0` | Point and Print: Show warning & elevation prompt | Both |
| 18.7.12b | `HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint` | `NoWarningNoElevationOnInstall` | DWord | `0` | Point and Print: Do not suppress warning on driver install | Both |

### Credential & LSASS Protection
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.4.1 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters` | `AllowEncryptionOracle` | DWord | `0` | CredSSP: Force Updated Clients (prevent older client connections) | Both |
| 18.9.4.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation` | `AllowProtectedCreds` | DWord | `1` | Allow delegation of non-exportable credentials | Both |
| 18.9.26.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `AllowCustomSSPsAPs` | DWord | `0` | Disallow custom Security Support Providers in LSASS | Both |
| 18.9.26.2 | `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa` | `RunAsPPL` | DWord | `1` | Run LSASS as Protected Process Light (PPL) | Both |

### Device Guard & Virtualization-Based Security
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.5.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | `EnableVirtualizationBasedSecurity` | DWord | `1` | Enable Virtualization-Based Security (VBS) | Both (Win11 recommended) |
| 18.9.5.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | `RequirePlatformSecurityFeatures` | DWord | `3` | VBS: Require Secure Boot + DMA protection | Both (Win11 recommended) |
| 18.9.5.3 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | `HypervisorEnforcedCodeIntegrity` | DWord | `1` | VBS: Enable Hypervisor-enforced Code Integrity (HVCI) | Both (Win11 recommended) |
| 18.9.5.4 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | `HVCIMATRequired` | DWord | `1` | VBS: Require UEFI Memory Attributes Table | Both (Win11 recommended) |
| 18.9.5.5 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | `LsaCfgFlags` | DWord | `1` | VBS: Enable Credential Guard with UEFI lock | Both |

### Remote Assistance & RDP Hardening
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.35.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fAllowToGetHelp` | DWord | `0` | Disable solicited Remote Assistance | Both |
| 18.10.57.2.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `DisablePasswordSaving` | DWord | `1` | RDP: Do not allow password saving | Both |
| 18.10.57.3.3.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `EnableUiaRedirection` | DWord | `0` | RDP: Disable UI Automation redirection | Both |
| 18.10.57.3.3.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fDisableCcm` | DWord | `1` | RDP: Disable COM port redirection | Both |
| 18.10.57.3.3.3 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fDisableCdm` | DWord | `1` | RDP: Disable drive redirection | Both |
| 18.10.57.3.3.4 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fDisableLocationRedir` | DWord | `1` | RDP: Disable location redirection | Both |
| 18.10.57.3.3.5 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fDisableLPT` | DWord | `1` | RDP: Disable LPT port redirection | Both |
| 18.10.57.3.3.6 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fDisablePNPRedir` | DWord | `1` | RDP: Disable Plug and Play redirection | Both |
| 18.10.57.3.3.7 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fDisableWebAuthn` | DWord | `1` | RDP: Disable WebAuthn redirection | Both |
| 18.10.57.3.9.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fPromptForPassword` | DWord | `1` | RDP: Always prompt for password on connect | Both |
| 18.10.57.3.9.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `fEncryptRPCTraffic` | DWord | `1` | RDP: Require secure RPC communication | Both |
| 18.10.57.3.9.3 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `SecurityLayer` | DWord | `2` | RDP: Use SSL/TLS for security layer | Both |
| 18.10.57.3.10.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `MaxIdleTime` | DWord | `900000` | RDP: Idle timeout 15 minutes (900000 milliseconds) | Both |
| 18.10.57.3.10.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` | `MaxDisconnectionTime` | DWord | `60000` | RDP: Disconnected session timeout 1 minute (60000 milliseconds) | Both |

### Biometrics & Camera
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.10.9.1.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Biometrics\FacialFeatures` | `EnhancedAntiSpoofing` | DWord | `1` | Enable enhanced anti-spoofing for facial recognition | Both |
| 18.10.11.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Camera` | `AllowCamera` | DWord | `0` | Disable camera | Both |

### Local Admin Password Solution (LAPS)
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.25.1 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS` | `BackupDirectory` | DWord | `1` | LAPS: Backup admin password to Active Directory | Domain-dependent |
| 18.9.25.3 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS` | `ADPasswordEncryptionEnabled` | DWord | `1` | LAPS: Enable password encryption | Domain-dependent |
| 18.9.25.4 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS` | `PasswordComplexity` | DWord | `4` | LAPS: Complex password (uppercase+lowercase+digits+symbols) | Domain-dependent |
| 18.9.25.5 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS` | `PasswordLength` | DWord | `15` | LAPS: Minimum password length 15 characters | Domain-dependent |
| 18.9.25.6 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS` | `PasswordAgeDays` | DWord | `30` | LAPS: Reset password every 30 days | Domain-dependent |
| 18.9.25.7 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS` | `PostAuthenticationResetDelay` | DWord | `8` | LAPS: Post-authentication grace period 8 hours | Domain-dependent |
| 18.9.25.8 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS` | `PostAuthenticationActions` | DWord | `3` | LAPS: Post-auth actions (reset + logoff) | Domain-dependent |

### Group Policy Processing
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.19.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}` | `NoBackgroundPolicy` | DWord | `0` | Registry GP: Always process in background | Both |
| 18.9.19.3 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}` | `NoGPOListChanges` | DWord | `0` | Registry GP: Process even if unchanged | Both |
| 18.9.19.4 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Group Policy\{827D319E-6EAC-11D2-A4EA-00C04F79F83A}` | `NoBackgroundPolicy` | DWord | `0` | Security GP: Always process in background | Both |
| 18.9.19.5 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Group Policy\{827D319E-6EAC-11D2-A4EA-00C04F79F83A}` | `NoGPOListChanges` | DWord | `0` | Security GP: Process even if unchanged | Both |

### RPC & WinRM Security
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.36.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Rpc` | `EnableAuthEpResolution` | DWord | `1` | Enable RPC Endpoint Mapper authentication for client connections | Both |

### System Protection & Exploit Prevention
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.24.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection` | `DeviceEnumerationPolicy` | DWord | `0` | DMA: Block all devices when external DMA protection enabled | Both |
| 18.9.27.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International` | `BlockUserInputMethodsForSignIn` | DWord | `1` | Disallow copying user input methods to system | Both |

### Sign-in & Account Security
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.1.1.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization` | `NoLockScreenCamera` | DWord | `1` | Prevent lock screen camera access | Both |
| 18.1.1.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization` | `NoLockScreenSlideshow` | DWord | `1` | Prevent lock screen slide show | Both |
| 18.10.15.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredUI` | `DisablePasswordReveal` | DWord | `1` | Do not display password reveal button on sign-in | Both |
| 18.10.15.3 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `NoLocalPasswordResetQuestions` | DWord | `1` | Prevent local password reset using security questions | Both |
| 18.9.28.1 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `BlockUserFromShowingAccountDetailsOnSignin` | DWord | `1` | Block display of account details on sign-in screen | Both |
| 18.9.28.2 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `DontDisplayNetworkSelectionUI` | DWord | `1` | Hide network selection UI from sign-in screen | Both |
| 18.9.28.3 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `DontEnumerateConnectedUsers` | DWord | `1` | Do not enumerate connected users on domain PCs | Both |
| 18.9.28.5 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `DisableLockScreenAppNotifications` | DWord | `1` | Turn off app notifications on lock screen | Both |
| 18.9.28.6 | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `BlockDomainPicturePassword` | DWord | `1` | Turn off picture password sign-in | Both |
| 18.10.6.1 | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` | `MSAOptional` | DWord | `1` | Allow Microsoft accounts to be optional | Both |

### Clock Synchronization
| CIS | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|-----|---|---|---|---|---|---|
| 18.9.51.1.1 | `HKLM:\SOFTWARE\Policies\Microsoft\W32Time\TimeProviders\NtpClient` | `Enabled` | DWord | `1` | Enable Windows NTP Client for time sync | Both |

---

## Registry Settings - Telemetry & Privacy

| Setting | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|---------|---|---|---|---|---|---|
| **Telemetry Level** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `AllowTelemetry` | DWord | `0` | Disable telemetry (Enterprise/Education only; Home/Pro enforces minimum 1) | Both |
| **Legacy Telemetry Path** | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` | `AllowTelemetry` | DWord | `0` | Disable telemetry data collection (legacy location) | Both |
| **Diagnostic Log Limit** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `LimitDiagnosticLogCollection` | DWord | `1` | Limit diagnostic log collection to minimum | Both |
| **OneSettings Downloads** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `DisableOneSettingsDownloads` | DWord | `1` | Disable OneSettings telemetry downloads | Both |
| **Feedback Notifications** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `DoNotShowFeedbackNotifications` | DWord | `1` | Disable feedback and survey notifications | Both |
| **OneSettings Auditing** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `EnableOneSettingsAuditing` | DWord | `1` | Enable OneSettings auditing | Both |
| **Dump Collection Limit** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `LimitDumpCollection` | DWord | `1` | Limit dump collection for diagnostic data | Both |
| **Insider Preview** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds` | `AllowBuildPreview` | DWord | `0` | Disable user control over Insider Preview builds | Both |
| **Advertising ID** | `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo` | `Enabled` | DWord | `0` | Disable advertising ID | Both (User-level) |
| **Advertising ID Policy** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo` | `DisabledByGroupPolicy` | DWord | `1` | Disable advertising ID via Group Policy | Both |
| **Cortana** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | `AllowCortana` | DWord | `0` | Disable Cortana voice assistant | Both |
| **Web Search in Taskbar** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | `DisableWebSearch` | DWord | `1` | Disable web search from taskbar/Start Menu | Both |
| **Bing Search Results** | `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search` | `BingSearchEnabled` | DWord | `0` | Disable Bing search results in Start Menu (Win11) | Win11 |
| **Tailored Experiences** | `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy` | `TailoredExperiencesWithDiagnosticDataEnabled` | DWord | `0` | Disable personalized recommendations based on diagnostic data | Both |
| **Ink Data Collection** | `HKCU:\SOFTWARE\Microsoft\InputPersonalization` | `RestrictImplicitInkCollection` | DWord | `1` | Restrict automatic ink/handwriting data collection | Both (User-level) |
| **Text Input Collection** | `HKCU:\SOFTWARE\Microsoft\InputPersonalization` | `RestrictImplicitTextCollection` | DWord | `1` | Restrict automatic text input data collection | Both (User-level) |
| **Online Speech Recognition** | `HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization` | `AllowInputPersonalization` | DWord | `0` | Disable online speech recognition | Both |
| **Online Tips** | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer` | `AllowOnlineTips` | DWord | `0` | Disable online tips and suggestions | Both |
| **App Installer (winget)** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller` | `EnableAppInstaller` | DWord | `1` | **FORCE ENABLE** - Winget required for SoftwareManagement & Sysmon install | Both |
| **App Installer Experimental** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller` | `EnableExperimentalFeatures` | DWord | `0` | Disable App Installer experimental features | Both |
| **App Installer Hash Override** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller` | `EnableHashOverride` | DWord | `0` | Disable App Installer hash override | Both |
| **App Installer Protocol** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller` | `EnableMSAppInstallerProtocol` | DWord | `0` | Disable ms-appinstaller:// protocol | Both |
| **Non-Admin App Install** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx` | `BlockNonAdminUserInstall` | DWord | `1` | Prevent non-administrator users from installing packages | Both |
| **App Privacy - Voice Activation** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy` | `LetAppsActivateWithVoiceAboveLock` | DWord | `2` | Force deny voice activation of apps above lock screen | Both |
| **Consumer Experiences** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | `DisableConsumerAccountStateContent` | DWord | `1` | Disable cloud consumer account state synchronization | Both |
| **Cloud Optimized Content** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | `DisableCloudOptimizedContent` | DWord | `1` | Disable cloud-optimized content delivery | Both |
| **Consumer Features** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | `DisableWindowsConsumerFeatures` | DWord | `1` | Disable Microsoft consumer experiences and suggestions | Both |
| **Continue Experiences** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `EnableCdp` | DWord | `0` | Disable "Continue on other devices" feature | Both |
| **Store Access** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer` | `NoUseStoreOpenWith` | DWord | `1` | Turn off Microsoft Store "Open With" feature | Both |
| **Clipboard Sync** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `AllowCrossDeviceClipboard` | DWord | `0` | Disable clipboard sync across devices | Both |
| **User Activities Upload** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | `UploadUserActivities` | DWord | `0` | Disable uploading user activity history | Both |
| **Windows CEIP** | `HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows` | `CEIPEnable` | DWord | `0` | Disable Customer Experience Improvement Program | Both |
| **Windows Messenger CEIP** | `HKLM:\SOFTWARE\Policies\Microsoft\Messenger\Client` | `CEIP` | DWord | `2` | Disable Windows Messenger CEIP | Both |
| **Windows Error Reporting** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting` | `Disabled` | DWord | `1` | Disable Windows Error Reporting | Both |
| **News & Interests** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds` | `EnableFeeds` | DWord | `0` | Disable news and interests widget | Both |
| **OneDrive File Storage** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive` | `DisableFileSyncNGSC` | DWord | `1` | Prevent OneDrive file storage sync | Both |
| **Push To Install Service** | `HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall` | `DisablePushToInstall` | DWord | `1` | Disable Push To Install service | Both |
| **Internet Explorer Feeds** | `HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Feeds` | `DisableEnclosureDownload` | DWord | `1` | Prevent enclosure downloads in IE | Both |
| **Cloud Search** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | `AllowCloudSearch` | DWord | `0` | Disable Cloud Search (Bing) | Both |
| **Cortana Above Lock** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | `AllowCortanaAboveLock` | DWord | `0` | Disable Cortana above lock screen | Both |
| **Search Location** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | `AllowSearchToUseLocation` | DWord | `0` | Disable search using location | Both |
| **Search Encrypted Stores** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | `AllowIndexingEncryptedStoresOrItems` | DWord | `0` | Disable indexing of encrypted items | Both |
| **Web Services** | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer` | `NoWebServices` | DWord | `1` | Disable Internet download for web publishing | Both |
| **KMS Online AVS** | `HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform` | `NoGenTicket` | DWord | `1` | Disable KMS Client Online AVS Validation | Both |
| **Microsoft Account Auth** | `HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount` | `DisableUserAuth` | DWord | `1` | Block consumer Microsoft account authentication | Both |
| **UWP App WinRT Access** | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` | `BlockHostedAppAccessWinRT` | DWord | `1` | Block UWP apps from accessing WinRT on hosted content | Both |

---

## Registry Settings - Optimization

| Setting | Registry Path | Value Name | Type | Desired Value | Description | OS Dependent |
|---------|---|---|---|---|---|---|
| **Visual Effects** | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects` | `VisualFXSetting` | DWord | `3` | Set visual effects to "Balanced" preset | Both (User-level) |
| **Minimize Animations** | `HKCU:\Control Panel\Desktop` | `MinAnimate` | String | `0` | Disable window minimize animation | Both (User-level) |
| **Font Smoothing** | `HKCU:\Control Panel\Desktop` | `FontSmoothing` | String | `2` | Enable font smoothing (ClearType) | Both (User-level) |
| **Drag Window Contents** | `HKCU:\Control Panel\Desktop` | `DragFullWindows` | String | `1` | Show full window while dragging | Both (User-level) |
| **Taskbar Animations** | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `TaskbarAnimations` | DWord | `0` | Disable taskbar animations | Both (User-level) |
| **Listview Shadow** | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `ListviewShadow` | DWord | `0` | Disable listview shadow effects | Both (User-level) |
| **Transparency Effects** | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `EnableTransparency` | DWord | `0` | Disable transparency effects | Both (User-level) |
| **Desktop Background** | `HKCU:\Control Panel\Desktop` | `WallpaperStyle` | String | `10` | Set wallpaper style to "Fit" | Both (User-level) |
| **Tile Wallpaper** | `HKCU:\Control Panel\Desktop` | `TileWallpaper` | String | `0` | Disable wallpaper tiling | Both (User-level) |
| **Spotlight Lock Screen** | `HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `RotatingLockScreenEnabled` | DWord | `0` | Disable Windows Spotlight rotating lock screen | Both (User-level) |
| **Spotlight Overlay** | `HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `RotatingLockScreenOverlayEnabled` | DWord | `0` | Disable Spotlight overlay | Both (User-level) |
| **Spotlight Subscriptions** | `HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SubscribedContent-338387Enabled` | DWord | `0` | Disable Spotlight subscribed content | Both (User-level) |
| **Power Plan** | `powercfg.exe /setactive` | High Performance GUID | — | `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c` | Set active power plan to "High Performance" | Both |
| **Network in Connected Standby (Battery)** | `HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9` | `DCSettingIndex` | DWord | `0` | Disable network in connected standby on battery | Both |
| **Network in Connected Standby (Plugged)** | `HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9` | `ACSettingIndex` | DWord | `0` | Disable network in connected standby when plugged in | Both |
| **Standby States S1-S3 (Battery)** | `HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab` | `DCSettingIndex` | DWord | `0` | Disable S1-S3 sleep states on battery | Both |
| **Standby States S1-S3 (Plugged)** | `HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\abfc2519-3608-4c2a-94ea-171b0ed546ab` | `ACSettingIndex` | DWord | `0` | Disable S1-S3 sleep states when plugged in | Both |

---

## Windows Defender Configuration

| Feature | Method | Desired State | Description | Notes |
|---------|--------|---|---|---|
| **Real-Time Protection** | `Set-MpPreference -DisableRealtimeMonitoring` | `$false` (enabled) | Enable real-time malware scanning | Checked via `Get-MpComputerStatus.RealTimeProtectionEnabled` |
| **Cloud Protection** | `Set-MpPreference -MAPSReporting 2` | `2` (advanced) | Enable cloud-based protection | Checked via `Get-MpPreference.MAPSReporting` |
| **Network Protection** | `Set-MpPreference -EnableNetworkProtection 1` | `1` (block) | Block malicious IPs and domains | Checked via `Get-MpPreference.EnableNetworkProtection` |
| **PUA Protection** | `Set-MpPreference -PUAProtection 1` | `1` (block) | Block potentially unwanted applications | Checked via `Get-MpPreference.PUAProtection` |
| **Controlled Folder Access** | `Set-MpPreference -EnableControlledFolderAccess 1` | `1` (enabled) | Prevent ransomware via folder access control | Checked via `Get-MpPreference.EnableControlledFolderAccess` |
| **Automatic Sample Submission** | `Set-MpPreference -SubmitSamplesConsent 1` | `1` (send safe samples)` | Submit suspicious files to Microsoft for analysis | Checked via `Get-MpPreference.SubmitSamplesConsent` |
| **Antivirus Enabled** | `Set-Service WinDefend -StartupType Automatic && Start-Service WinDefend` + Registry | Service running | Enable Windows Defender antivirus service | Registry: `DisableAntiSpyware = 0` in `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` |
| **File Hash Computation** | Registry | `1` | Enable file hash computation for enhanced malware detection | `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine` → `EnableFileHashComputation` |
| **PUA Detection** | Registry | `1` | Detect and block potentially unwanted applications | `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` → `PUAProtection` |
| **Removable Drive Scanning** | Registry | `0` (scan enabled) | Scan removable drives for malware | `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan` → `DisableRemovableDriveScanning` |
| **Email Scanning** | Registry | `0` (scan enabled) | Enable email attachment scanning | `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan` → `DisableEmailScanning` |
| **Generic Reports Disabled** | Registry | `1` | Disable Watson event reporting | `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting` → `DisableGenericRePorts` |
| **ASR Rules Enabled** | Registry | `1` | Enable Attack Surface Reduction rules | `HKLM:\Software\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR` → `ExploitGuard_ASR_Rules` |
| **ASR: Block Office Executables** | Registry | `1` | Block Office apps from creating executable content | `HKLM:\Software\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules` → `D4F940AB-401B-4EFC-AADC-AD5F3C50688A` |
| **Network Protection (Exploit Guard)** | Registry | `1` | Block malicious IPs/domains via Exploit Guard | `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection` → `EnableNetworkProtection` |

---

## Windows Firewall Configuration

| Profile | Feature | Desired State | Description | OS Dependent |
|---------|---------|---|---|---|
| **All Profiles (Domain/Private/Public)** | **Firewall Enabled** | `$true` (enabled) | All firewall profiles must be enabled | Both |
| **Domain Profile** | Notifications disabled | `1` (disable) | Suppress firewall notifications on domain networks | Both |
| **Domain Profile** | Logging - File Path | `%SystemRoot%\System32\logfiles\firewall\domainfw.log` | Log dropped & successful connections | Both |
| **Domain Profile** | Logging - Max File Size | `16384` KB (16 MB) | Firewall log file size limit | Both |
| **Domain Profile** | Log Dropped Packets | `1` (enable) | Record all dropped packets | Both |
| **Domain Profile** | Log Successful Connections | `1` (enable) | Record all allowed connections | Both |
| **Private Profile** | Notifications disabled | `1` (disable) | Suppress firewall notifications on private networks | Both |
| **Private Profile** | Logging - File Path | `%SystemRoot%\System32\logfiles\firewall\privatefw.log` | Log dropped & successful connections | Both |
| **Private Profile** | Logging - Max File Size | `16384` KB (16 MB) | Firewall log file size limit | Both |
| **Private Profile** | Log Dropped Packets | `1` (enable) | Record all dropped packets | Both |
| **Private Profile** | Log Successful Connections | `1` (enable) | Record all allowed connections | Both |
| **Public Profile** | Notifications disabled | `1` (disable) | Suppress firewall notifications on public networks | Both |
| **Public Profile** | Logging - File Path | `%SystemRoot%\System32\logfiles\firewall\publicfw.log` | Log dropped & successful connections | Both |
| **Public Profile** | Logging - Max File Size | `16384` KB (16 MB) | Firewall log file size limit | Both |
| **Public Profile** | Allow Local Policy Merge | `0` (no merge) | Do not allow local firewall rule additions on public networks | Both |
| **Public Profile** | Allow Local IPsec Policy Merge | `0` (no merge) | Do not allow local IPsec rule additions on public networks | Both |
| **Public Profile** | Log Dropped Packets | `1` (enable) | Record all dropped packets | Both |
| **Public Profile** | Log Successful Connections | `1` (enable) | Record all allowed connections | Both |

---

## Security Policy (secedit)

Local Security Policy settings applied via `secedit` export/import. These are **CIS 1.1 & 1.2** baseline rules.

| Setting | Parameter | Desired Value | Description | OS Dependent |
|---------|-----------|---|---|---|
| **Password History** | `PasswordHistorySize` | `24` | Enforce 24-password history requirement | Both |
| **Minimum Password Age** | `MinimumPasswordAge` | `1` | Require at least 1 day before password can be changed again | Both |
| **Minimum Password Length** | `MinimumPasswordLength` | `14` | Require minimum 14-character passwords | Both |
| **Account Lockout Duration** | `LockoutDuration` | `15` | Lock account for 15 minutes after failed attempts | Both |
| **Account Lockout Threshold** | `LockoutBadCount` | `5` | Lock account after 5 failed logon attempts | Both |
| **Reset Account Lockout Counter** | `ResetLockoutCount` | `15` | Reset lockout counter after 15 minutes | Both |
| **Administrator Account Name** | `NewAdministratorName` | `CISAdmin` | Rename Administrator account (NOT applied; risky unattended) | Both (not applied) |
| **Guest Account Name** | `NewGuestName` | `CISGuest` | Rename Guest account (NOT applied; risky unattended) | Both (not applied) |

---

## Advanced Audit Policy (auditpol)

Advanced Audit Policy Configuration settings applied via `auditpol.exe`. These are **CIS 17.x** baseline rules (security event logging).

| CIS | Subcategory | Success | Failure | Description | OS Dependent |
|-----|---|---|---|---|---|
| 17.1.1 | Credential Validation | ✓ | ✓ | Audit logon attempts with credentials | Both |
| 17.2.1 | Application Group Management | ✓ | ✓ | Audit changes to application group membership | Both |
| 17.2.3 | User Account Management | ✓ | ✓ | Audit user account creation/deletion/change | Both |
| 17.3.1 | Plug and Play Events | ✓ | ✗ | Audit PnP device installation (success only) | Both |
| 17.3.2 | Process Creation | ✓ | ✗ | Audit process creation with command line (success only) | Both |
| 17.5.1 | Account Lockout | ✗ | ✓ | Audit account lockout events (failure only) | Both |
| 17.5.2 | Group Membership | ✓ | ✗ | Audit group membership changes (success only) | Both |
| 17.5.5 | Other Logon/Logoff Events | ✓ | ✓ | Audit logon/logoff events (success & failure) | Both |
| 17.6.1 | Detailed File Share | ✗ | ✓ | Audit detailed SMB file share access (failure only) | Both |
| 17.6.2 | File Share | ✓ | ✓ | Audit SMB file share access | Both |
| 17.6.3 | Other Object Access Events | ✓ | ✓ | Audit other object access events | Both |
| 17.6.4 | Removable Storage | ✓ | ✓ | Audit removable media access | Both |
| 17.7.3 | Authorization Policy Change | ✓ | ✗ | Audit permission/privilege changes (success only) | Both |
| 17.7.4 | MPSSVC Rule-Level Policy Change | ✓ | ✓ | Audit Windows Firewall rule changes | Both |
| 17.7.5 | Other Policy Change Events | ✗ | ✓ | Audit other policy changes (failure only) | Both |
| 17.8.1 | Sensitive Privilege Use | ✓ | ✓ | Audit use of sensitive privileges | Both |
| 17.9.1 | IPsec Driver | ✓ | ✓ | Audit IPsec driver events | Both |
| 17.9.4 | Security System Extension | ✓ | ✗ | Audit security system extensions (success only) | Both |

**Note:** `SCENoApplyLegacyAuditPolicy = 1` is set in registry to prevent legacy category-level audit policy from overriding these subcategory settings.

---

## Services - Security (ensure enabled)

| Service Name | Display Name | Startup Type | Description | OS Dependent |
|---|---|---|---|---|
| `WinDefend` | Windows Defender Antivirus Service | Automatic | Real-time malware protection | Both |
| `MpsSvc` | Windows Defender Firewall | Automatic | Firewall service for all profiles | Both |
| `EventLog` | Windows Event Log | Automatic | Event logging for audit/security events | Both |

---

## Services - Security (ensure disabled)

| Service Name | Display Name | Reason Disabled | OS Dependent |
|---|---|---|---|
| `RemoteRegistry` | Remote Registry | Reduces attack surface; prevents unauthorized registry access | Both |
| `Telnet` | Telnet Server | Insecure protocol; SSH/RDP is preferred | Both |
| `BTAGService` | Bluetooth Audio Gateway Service | Reduces attack surface; not needed unless Bluetooth audio required | Both |
| `bthserv` | Bluetooth Support Service | Reduces attack surface; not needed unless Bluetooth required | Both |
| `lltdsvc` | Link-Layer Topology Discovery Mapper | Reduces attack surface; network discovery not needed in hardened config | Both |
| `MSiSCSI` | iSCSI Initiator Service | Reduces attack surface; not needed unless iSCSI storage is used | Both |
| `PNRPsvc` | PNRP Machine Name Publication Service | Reduces attack surface; P2P not needed | Both |
| `p2psvc` | Peer Networking Grouping | Reduces attack surface; P2P not needed | Both |
| `p2pimsvc` | Peer Networking Identity Manager | Reduces attack surface; P2P not needed | Both |
| `PNRPAutoReg` | PNRP Auto Registration Service | Reduces attack surface; P2P not needed | Both |
| `Spooler` | Print Spooler | Prevents print spooler vulnerabilities; disable if no printing needed | Both |
| `wercplsupport` | Problem Reports and Solutions Control Panel Support | Reduces attack surface | Both |
| `RasAuto` | Remote Access Auto Connection Manager | Reduces attack surface | Both |
| `SessionEnv` | Remote Desktop Services Session Environment | Disables Remote Desktop features | Both |
| `TermService` | Remote Desktop Services | Disables Remote Desktop for security | Both |
| `UmRdpService` | Remote Desktop Services UserMode Port Redirector | Disables Remote Desktop port redirection | Both |
| `RpcLocator` | Remote Procedure Call (RPC) Locator | Reduces RPC attack surface | Both |
| `LanmanServer` | Server (SMB) | Disables file/print sharing; reduces attack surface | Both |
| `SSDPSRV` | SSDP Discovery | Reduces UPnP attack surface | Both |
| `upnphost` | UPnP Device Host | Disables UPnP to reduce attack surface | Both |
| `Wecsvc` | Windows Event Collector | Disables remote event log forwarding | Both |
| `icssvc` | Internet Connection Sharing (ICS) | Disables ICS; reduces attack surface | Both |
| `WpnService` | Windows Push Notifications User Service | Reduces telemetry attack surface | Both |
| `PushToInstall` | Push To Install Service | Reduces telemetry and app delivery overhead | Both |
| `WinRM` | Windows Remote Management (WS-Management) | Disables remote PowerShell; reduces attack surface | Both |

---

## Services - Telemetry (disable)

| Service Name | Display Name | Purpose Disabled | OS Dependent |
|---|---|---|---|
| `DiagTrack` | DiagTrack (Diagnostic Tracking Service) | Prevents telemetry & diagnostic data collection | Both |
| `dmwappushservice` | dmwappushservice | Stops app push notifications and telemetry | Both |
| `PcaSvc` | Program Compatibility Assistant Service | Disables compatibility telemetry | Both |
| `WerSvc` | Windows Error Reporting Service | Disables error crash reporting to Microsoft | Both |
| `WMPNetworkSvc` | Windows Media Player Network Sharing Service | Disables media sharing and related telemetry | Both |
| `MapsBroker` | Downloaded Maps Manager | Disables map updates and location telemetry | Both |
| `lfsvc` | Geolocation Service | Disables location services and telemetry | Both |
| `NetTcpPortSharing` | Net.Tcp Port Sharing Service | Reduces network telemetry surface | Both |
| `Fax` | Fax Service | Optional; disabled to reduce telemetry surface | Both |

---

## Services - Optimization (disable)

### Common (All Versions)
| Service Name | Display Name | Purpose Disabled | OS Dependent |
|---|---|---|---|
| `RetailDemo` | Retail Demo Service | Disables retail demo mode (saves resources) | Both |
| `XblAuthManager` | Xbox Live Auth Manager | Disables Xbox Live services | Both |
| `XblGameSave` | Xbox Live Game Save Service | Disables Xbox Live cloud save | Both |
| `XboxGipSvc` | Xbox Game Input Service | Disables Xbox game controller support | Both |
| `XboxNetApiSvc` | Xbox Live Networking Service | Disables Xbox Live networking | Both |

### Windows 11 Only
| Service Name | Display Name | Purpose Disabled | OS Dependent |
|---|---|---|---|
| `WidgetService` | Windows Widget Service | Disables Windows 11 widgets (saves resources) | Win11 |
| `DevHomeService` | Dev Home Service | Disables developer home features (reduces clutter) | Win11 |

---

## Scheduled Tasks (disable)

| Task Path | Purpose Disabled | OS Dependent |
|---|---|---|
| `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser` | Stops compatibility data collection | Both |
| `\Microsoft\Windows\Application Experience\ProgramDataUpdater` | Stops program data telemetry | Both |
| `\Microsoft\Windows\Autochk\Proxy` | Disables autochk proxy (reduced disk checks) | Both |
| `\Microsoft\Windows\Customer Experience Improvement Program\Consolidator` | Disables CEIP data consolidation | Both |
| `\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip` | Disables USB device telemetry | Both |
| `\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | Disables disk diagnostics telemetry | Both |
| `\Microsoft\Windows\Feedback\Siuf\DmClient` | Disables feedback client | Both |
| `\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload` | Disables feedback downloads | Both |

---

## Sysmon Installation & Configuration

| Component | Action | Details | OS Dependent |
|---|---|---|---|
| **Installation** | Via winget | `Microsoft.Sysinternals.Sysmon` package installed if service absent | Both |
| **Binary Resolution** | Locate real executable | Prefers `%windir%\Sysmon64.exe` or `Sysmon.exe`; avoids App-Execution-Alias shim | Both |
| **Configuration File** | Apply XML config | `config/sysmon/sysmonconfig.xml` applied with `-i` (install) or `-c` (update) | Both |
| **EULA Acceptance** | Auto-accept | `-accepteula` flag used to prevent prompts in unattended runs | Both |
| **Idempotency** | Update-safe | If service exists, config is reapplied without reinstall | Both |

---

## Summary by Change Category

| Category | Count | Notes |
|----------|-------|-------|
| **Registry (Security)** | 115+ | CIS 2.x, 9.x, 18.x hardening entries |
| **Registry (Telemetry & Privacy)** | 45+ | Disables telemetry, advertising, Cortana, cloud sync |
| **Registry (Optimization)** | 17+ | Visual effects, power plans, desktop background |
| **Windows Defender Settings** | 11+ | Real-time protection, cloud, ASR rules, PUA |
| **Windows Firewall Settings** | 18+ | All 3 profiles enabled with logging |
| **Security Policy (secedit)** | 8 entries | Password policy, account lockout |
| **Audit Policy (auditpol)** | 18 subcategories | Comprehensive logging of security events |
| **Services (Security enabled)** | 3 | WinDefend, MpsSvc, EventLog |
| **Services (Security disabled)** | 20+ | Attack surface reduction |
| **Services (Telemetry disabled)** | 9 | Stops data collection services |
| **Services (Optimization disabled)** | 9 | Xbox, widgets, dev tools |
| **Scheduled Tasks (disabled)** | 8 | Telemetry, feedback, diagnostics |
| **Sysmon** | Install + config | Advanced threat detection logging |
| **Restore Points** | Create + prune | Every run (5 newest kept) |

---

## OS Version Dependencies Summary

### Both Windows 10 & 11
- All registry security hardening (CIS 2.3.x - 18.10.x)
- All security policy (secedit) settings
- All audit policy (auditpol) settings
- Windows Defender & Firewall configuration
- All services (except Win11-specific ones)
- Most scheduled task disabling
- Restore point management
- Sysmon installation

### Windows 11 Only
- `WidgetService` and `DevHomeService` (not present on Win10)
- Bing search results in Start Menu (`BingSearchEnabled` - Win11 specific UI)

### Domain-Dependent (LAPS)
- LAPS registry settings only applied on domain-joined machines
- Standalone machines skip LAPS configuration

---

## Notes

- **Restore Points:** Created FIRST (rank 0), pruned LAST (rank 4) to ensure rollback safety
- **Security settings:** Applied SECOND (rank 1) so protection is re-enabled early
- **Telemetry:** Applied THIRD (rank 2) after security hardening
- **Optimization:** Applied FOURTH (rank 3) as low-priority cosmetic changes
- **winget requirement:** `EnableAppInstaller` is **forcibly set to 1** despite CIS recommendation of 0, because SoftwareManagement and Sysmon install depend on it
- **User-level settings:** Marked as `(User-level)` in tables; applied in current user context only
- **Unattended safety:** All settings avoid prompts, confirmations, or blocking operations
