# System Maintenance Automation Project Documentation

## Overview
This project automates a comprehensive set of Windows maintenance tasks using two main scripts:
- `script.bat`: A batch file that orchestrates the download, extraction, and execution of the PowerShell script.
- `script.ps1`: A robust PowerShell script that performs system protection, inventory, debloating, essential app installation, privacy hardening, updates, cleanup, logging, and finalization.

---

## 1. `script.bat` — Batch Orchestration

### Purpose
`script.bat` is the entry point for the automation. It ensures the latest version of the maintenance script is used, handles extraction, and launches the PowerShell script with proper error handling.

### Step-by-Step Logic
1. **Script Directory Detection**
   - Determines the directory where the batch file is located, removing any trailing backslash for consistency.

2. **Variable Setup**
   - Sets variables for the GitHub repository URL, zip file name, extraction directory, and PowerShell script name.

3. **Package Manager & PowerShell 7 Setup**
   - Checks for Winget and installs it if missing.
   - Checks for PowerShell 7 and installs it if missing (using Winget).

4. **Repository Download**
   - Uses PowerShell to download the latest version of the repository as a zip file from GitHub, enforcing TLS 1.2 for compatibility.
   - Handles download errors and exits if the download fails.

5. **Previous Extraction Cleanup**
   - Removes any previously extracted folder to ensure a clean state before extraction.

6. **Zip Extraction**
   - Uses PowerShell's `Expand-Archive` to extract the downloaded zip file to the target directory.
   - Handles extraction errors and exits if extraction fails.

7. **Zip File Deletion**
   - Deletes the zip file after extraction to save space.

8. **Move Extracted Content**
   - Moves the actual script files from the extracted subfolder to the main extraction directory, ensuring the PowerShell script is in the expected location.

9. **Run PowerShell Script in PowerShell 7**
   - Executes `script.ps1` from the extracted directory using PowerShell 7 (`pwsh`), with elevated privileges and verbose output.
   - Captures the exit code and reports any errors.

10. **Finalization**
   - Prints a completion message and prompts the user to press Enter to close the window.

---

## 2. `script.ps1` — PowerShell Maintenance Logic

### Purpose
`script.ps1` is a modular, task-driven PowerShell script that automates a wide range of system maintenance operations. It is organized into functions for clarity and maintainability. This script is now intended to be run in PowerShell 7, as ensured by the batch script.

### Main Components & Logic

#### 2.1. Central Coordination
- **Function:** `Invoke-CentralCoordinationPolicy`
- **Logic:**
  - Creates a unique temporary folder for logs and intermediate files.
  - Generates a unified, sorted list of bloatware and essential apps, saving them as JSON for later processing.

#### 2.2. Globals & Initialization
- **Global Variables:**
  - Paths for error logs and task reports are set for consistent logging.
- **Functions:**
  - `Write-ErrorLog`: Logs errors with timestamps and function names, both to the console (in red) and to a file.
  - `Write-TaskReport`: Logs task status (start, success, error) with colorized output and section headers.
  - `Test-Admin`: Checks for administrator rights and exits if not present.
  - `Initialize-Environment`: Creates the temp folder and starts a transcript log.
  - `Remove-Environment`: Cleans up the temp folder and stops the transcript.

#### 2.3. Error Handling & Task Execution
- **Function:** `Invoke-Task`
  - Wraps each major operation in a try/catch block, logs status, and prints colorized output for clarity.

#### 2.4. Task Modules
Each major maintenance area is implemented as a function:

- **System Protection**
  - `Test-SystemRestore`: Checks and logs the status of System Restore protection.

- **System Inventory**
  - `Get-Inventory`: Collects hardware, disk, network, and installed program information, saving results to files.

- **Debloating & App Management**
  - `Uninstall-Bloatware`: Reads the bloatware list, compares it to installed programs, and removes matches. Logs all actions and results.
  - `Install-EssentialApps`: Installs missing essential apps using Winget, with retry logic for installer busy errors.

- **Privacy & Telemetry**
  - `Disable-Telemetry`: Applies registry and service changes to disable Windows telemetry and tracking features.

- **Updates & Maintenance**
  - `Update-Windows`: Runs Windows Update and upgrade operations.
  - `Update-AllPackages`: Upgrades all packages via Winget.

- **Cleanup**
  - `Clear-BrowserData`: Cleans browser cache and cookies.
  - `Clear-DnsCache`: Flushes the DNS cache.

- **Logging & Restore Points**
  - `Get-LogSurvey`: Surveys Event Viewer and CBS logs for issues.
  - `Protect-RestorePoints`: Validates system restore points.

- **Full Disk Cleanup**
  - `Optimize-Disk`: Performs comprehensive disk cleanup operations.

- **Transcript Generation**
  - `Export-Transcript`: Creates a detailed HTML report of all maintenance actions, with dark mode styling and a summary table.

- **Finalization**
  - `Request-RebootIfNeeded`: Prompts the user to reboot if required.

#### 2.5. Main Execution Flow
- The script checks for admin rights, sets up the environment, and then sequentially executes each maintenance task using `Invoke-Task` for robust error handling and logging.
- After all tasks, it generates the transcript and cleans up the environment.

---

## Error Handling & Logging
- All errors are logged with timestamps and function context, both to the console and to log files.
- Task status (start, success, error) is tracked for each operation, making troubleshooting straightforward.

---

## Output & Artifacts
- **Log Files:** Each task writes detailed logs to the temp folder for review.
- **HTML Transcript:** A comprehensive, searchable report is generated at the end, summarizing all actions and results.

---

## Extensibility
- The modular structure allows easy addition of new maintenance tasks or customization of existing ones.
- Lists of bloatware and essential apps can be updated in the PowerShell script for different environments.

---

## Usage
1. Run `script.bat` as Administrator.
2. The batch file will download, extract, and execute the PowerShell script.
3. Follow prompts and review the HTML transcript for a summary of all actions performed.

---

## Security & Safety
- The script checks for admin rights before making system changes.
- All destructive actions (like uninstalling apps or deleting files) are logged and summarized for review.

---

## Troubleshooting
- If errors occur, consult the error log and task report files in the temp folder.
- Ensure you have administrator privileges and Winget installed.

---

## Conclusion
This project provides a reliable, extensible, and well-documented solution for automating Windows system maintenance, with robust error handling, logging, and reporting for transparency and safety.
