# 🔧 Script.bat Crash Troubleshooting Guide

## 📋 Most Common Crash Causes & Solutions

### 🚨 **CRITICAL: Administrator Privileges Required**
**CAUSE:** Running script.bat without administrator privileges
**SOLUTION:** 
- Right-click `script.bat` → Select "Run as administrator"
- Accept the UAC (User Account Control) prompt when it appears

### 🛡️ **Antivirus/Windows Defender Interference**
**CAUSE:** Security software blocking PowerShell execution or file downloads
**SOLUTION:**
1. Add the script folder to Windows Defender exclusions:
   ```powershell
   Add-MpPreference -ExclusionPath "C:\path\to\script\folder"
   ```
2. Temporarily disable real-time protection during first run
3. For corporate environments: Contact IT to whitelist the script

### 🌐 **Network/Firewall Connectivity Issues**  
**CAUSE:** Cannot download repository from GitHub or install dependencies
**SOLUTION:**
1. Test connectivity: `ping github.com`
2. Check corporate firewall settings
3. Try running on different network (mobile hotspot)
4. Ensure these URLs are accessible:
   - `github.com`
   - `api.github.com`
   - `objects.githubusercontent.com`

### ⚡ **PowerShell Execution Policy**
**CAUSE:** Restrictive PowerShell execution policy
**SOLUTION:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 💾 **Insufficient Disk Space**
**CAUSE:** Less than 1GB free space on system drive
**SOLUTION:** Free up disk space (minimum 1GB recommended)

### 🔄 **Corrupted Download/Files**
**CAUSE:** Incomplete or corrupted script.bat download
**SOLUTION:** Re-download fresh copy from GitHub repository

## 🔍 **Diagnostic Steps**

### Step 1: Run the Diagnostic Tool
1. Copy `Diagnose-ScriptCrash.bat` to the same folder as `script.bat`
2. Right-click → "Run as administrator"
3. Review the diagnostic results

### Step 2: Enable Detailed Logging
If the crash persists, capture detailed logs:
```cmd
# Run as Administrator
cd /d "C:\path\to\script\folder"
script.bat >debug_log.txt 2>&1
```

### Step 3: Check Common Error Patterns

**Error: "Access Denied"**
- Not running as administrator
- Antivirus blocking execution

**Error: "Execution Policy"** 
- PowerShell execution policy too restrictive
- Run: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

**Error: "Network/Download Failed"**
- Internet connectivity issues
- Firewall blocking GitHub access
- Corporate proxy settings

**Error: "File Not Found"**
- Corrupted script.bat file
- Missing dependencies
- Antivirus quarantined files

## 🚀 **Quick Fix Checklist**

Before running script.bat on a new PC:

- [ ] ✅ Right-click script.bat → "Run as administrator"
- [ ] ✅ Accept UAC prompt when it appears  
- [ ] ✅ Add script folder to antivirus exclusions
- [ ] ✅ Ensure internet connectivity (test: `ping github.com`)
- [ ] ✅ Have at least 1GB free disk space
- [ ] ✅ Set PowerShell execution policy: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

## 🏢 **Corporate Environment Considerations**

### Group Policy Restrictions
- PowerShell execution may be disabled by policy
- Package managers (winget, chocolatey) may be blocked
- Contact IT administrator for policy exceptions

### Proxy/Firewall Configuration  
- Corporate proxies may block GitHub access
- Request IT to whitelist required domains
- Consider using corporate package management tools

### Alternative Deployment Methods
For heavily restricted environments:
1. Download complete repository manually
2. Extract to local folder
3. Run `MaintenanceOrchestrator.ps1` directly with PowerShell 7

## 📞 **Getting Additional Help**

If crashes persist after following this guide:

1. **Run diagnostic tool:** `Diagnose-ScriptCrash.bat`
2. **Capture full logs:** `script.bat >debug_log.txt 2>&1`
3. **Check Windows Event Viewer:** Look for PowerShell or application errors
4. **Submit issue** with diagnostic results and log files

## 🔧 **Advanced Troubleshooting**

### Manual Dependency Installation
If automatic dependency installation fails:

```powershell
# Install PowerShell 7
winget install Microsoft.PowerShell

# Install NuGet provider
Install-PackageProvider -Name NuGet -Force

# Set PSGallery as trusted
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install PSWindowsUpdate module
Install-Module PSWindowsUpdate -Force
```

### Manual Repository Download
If GitHub download fails:
1. Visit: https://github.com/ichimbogdancristian/script_mentenanta
2. Click "Code" → "Download ZIP"
3. Extract to desired location
4. Run `MaintenanceOrchestrator.ps1` directly

### Clean Environment Reset
If multiple attempts fail:
1. Delete script folder completely
2. Clear PowerShell module cache: `Remove-Item $env:PSModulePath -Recurse -Force`
3. Reset execution policy: `Set-ExecutionPolicy Default -Force`
4. Reboot system
5. Re-download and try again