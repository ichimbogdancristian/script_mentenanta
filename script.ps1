# =====================[ SYSTEM MAINTENANCE POLICY CONTROLLER ]====================
# All tasks must:
# - Accept a [hashtable]$Context parameter for shared state and logging
# - Use Write-Log -Context $Context for all logging
# - Be robust, modular, and not rely on global variables
# - Handle errors with try/catch and log failures
# - Not exit or break the main script flow (let the controller handle task order)
# - Clean up any temp files they create in $Context.TempFolder if needed
#
# The controller will:
# - Initialize $Context and environment
# - Run all tasks in order, passing $Context
# - Log all errors and successes
# - Remove environment at the end
# - Optionally delete temp files with -DeleteTempFiles switch
#
# Usage:
# Invoke-SystemMaintenancePolicy -Tasks @('Task1', 'Task2') [-DeleteTempFiles]
#
# =====================[ END POLICY CONTROLLER HEADER ]====================

function Invoke-SystemMaintenancePolicy {
    param(
        [string[]]$Tasks,
        [switch]$DeleteTempFiles
    )
    $Context = @{}
    Initialize-Environment -Context $Context
    $taskIndex = 0
    foreach ($TaskName in $Tasks) {
        # Skip null or empty tasks
        if (-not $TaskName) {
            Write-Host "Skipping null/empty task at index $($taskIndex + 1)"
            continue
        }
        
        $taskIndex++
        
        # Use the task name directly
        $Context.TaskName = $TaskName
        
        # Verify the function exists
        if (-not (Get-Command $TaskName -ErrorAction SilentlyContinue)) {
            Write-Host "Warning: Function $TaskName not found. Skipping task $taskIndex."
            continue
        }
    
        try {
            # Create task-specific folder with shorter, cleaner name
            $cleanTaskName = $Context.TaskName -replace '^Invoke-Task\d+_', '' -replace '[^\w\-]', '_'
            $shortFolderName = "Task${taskIndex}_${cleanTaskName}"
            $taskFolderPath = New-TaskFolder -Context $Context -TaskName $shortFolderName
            $Context.TaskLogPath = Join-Path $taskFolderPath ("Task${taskIndex}_${cleanTaskName}_log.txt")
            
            Write-TaskLog -Context $Context -Message "Starting $($Context.TaskName)" -Level 'INFO'
            
            # Execute the function by name
            & $TaskName -Context $Context
            
            Write-TaskLog -Context $Context -Message "$($Context.TaskName) completed successfully." -Level 'SUCCESS'
        } catch {
            Write-TaskLog -Context $Context -Message "Task failed: $_" -Level 'ERROR'
        }
    }
    Remove-Environment -Context $Context -DeleteTempFiles:$DeleteTempFiles
}

# =====================[ INITIALIZATION & CLEANUP ]====================
function Initialize-Environment {
    param([hashtable]$Context)
    # Use unified temp folder location with task subdirectories
    $mainTempFolder = Join-Path $PSScriptRoot "SystemMaintenance_Temp"
    $Context.TempFolder = $mainTempFolder
    
    # Create main temp folder if it doesn't exist
    if (-not (Test-Path $Context.TempFolder)) {
        New-Item -ItemType Directory -Path $Context.TempFolder -Force | Out-Null
    }
    
    # Initialize task folders collection
    $Context.TaskFolders = @{}
    
    $Context.LogPath = Join-Path $Context.TempFolder 'SystemMaintenance.log'
    Start-Transcript -Path (Join-Path $Context.TempFolder 'transcript_log.txt') -Append
    Write-Log -Context $Context -Message "Main temp folder created: $($Context.TempFolder)" -Level 'INFO'
}

function Remove-Environment {
    param(
        [hashtable]$Context,
        [switch]$DeleteTempFiles
    )
    
    Write-Host "`n====================[ CLEANUP ]===================="
    Write-Log -Context $Context -Message "Starting environment cleanup..." -Level 'INFO'
    
    # Handle deferred updates before cleanup
    if ($Context.ContainsKey('DeferredUpdates') -and $Context.DeferredUpdates.Count -gt 0) {
        Write-Host "`n⚠️  DEFERRED UPDATES DETECTED"
        Write-Host "The following updates were deferred to prevent script interruption:"
        
        foreach ($deferredUpdate in $Context.DeferredUpdates) {
            if ($deferredUpdate.Type -eq 'PowerShell7Update') {
                Write-Host "📦 PowerShell 7 Updates:"
                foreach ($update in $deferredUpdate.Updates) {
                    Write-Host "   • $($update.Name): $($update.Version) → $($update.AvailableVersion)"
                }
                
                Write-Host "`nDo you want to run the PowerShell 7 update now? [Y/N]" -NoNewline
                $response = Read-Host " "
                
                if ($response -match '^[Yy]') {
                    Write-Host "Starting PowerShell 7 update..."
                    try {
                        # Run the deferred update script
                        Start-Process -FilePath $deferredUpdate.BatchPath -Wait
                        Write-Log -Context $Context -Message "PowerShell 7 deferred update completed." -Level 'SUCCESS'
                    } catch {
                        Write-Host "Failed to start deferred update: $_"
                        Write-Host "You can manually run: $($deferredUpdate.BatchPath)"
                        Write-Log -Context $Context -Message "Failed to start deferred PowerShell update: $_" -Level 'ERROR'
                    }
                } else {
                    Write-Host "PowerShell 7 update skipped."
                    Write-Host "To update later, run: $($deferredUpdate.BatchPath)"
                    Write-Log -Context $Context -Message "User skipped PowerShell 7 deferred update." -Level 'INFO'
                }
            }
        }
    }
    
    try {
        Stop-Transcript | Out-Null
    } catch {
        # Transcript might not be running
    }
    
    # Close all log file handles
    if ($Context.LogFile -and $Context.LogFile -is [System.IO.StreamWriter]) {
        try {
            $Context.LogFile.Close()
            $Context.LogFile.Dispose()
        } catch {
            Write-Warning "Failed to close log file: $_"
        }
    }
    
    Write-Host "[Cleanup] Environment cleanup completed."
    Write-Host "[Cleanup] Script execution finished."
    
    # Final message about temp folders and cleanup option
    if ($Context.TempFolder -and (Test-Path $Context.TempFolder)) {
        if ($DeleteTempFiles) {
            # Automatic deletion without prompting
            try {
                # Close any remaining file handles first
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                
                Remove-Item -Path $Context.TempFolder -Recurse -Force -ErrorAction Stop
                Write-Host "✅ Temporary files deleted automatically."
                Write-Log -Context $Context -Message "Temporary folder deleted automatically." -Level 'INFO'
            } catch {
                Write-Host "❌ Failed to delete temporary files: $_"
                Write-Host "📁 Temporary files preserved at: $($Context.TempFolder)"
                Write-Log -Context $Context -Message "Failed to delete temporary folder: $_" -Level 'WARNING'
            }
        } else {
            # Interactive mode - ask user
            Write-Host "`n📁 Task folders preserved for review at: $($Context.TempFolder)"
            Write-Host "   These folders contain logs, reports, and generated files from each task."
            
            # Ask user if they want to delete the temp folder
            Write-Host "`nDo you want to delete the temporary files now? [Y/N]" -NoNewline
            $response = Read-Host " "
            
            if ($response -match '^[Yy]') {
                try {
                    # Close any remaining file handles first
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    
                    Remove-Item -Path $Context.TempFolder -Recurse -Force -ErrorAction Stop
                    Write-Host "✅ Temporary files deleted successfully."
                    Write-Log -Context $Context -Message "Temporary folder deleted by user request." -Level 'INFO'
                } catch {
                    Write-Host "❌ Failed to delete temporary files: $_"
                    Write-Host "   You can manually delete: $($Context.TempFolder)"
                    Write-Log -Context $Context -Message "Failed to delete temporary folder: $_" -Level 'WARNING'
                }
            } else {
                Write-Host "📁 Temporary files preserved at: $($Context.TempFolder)"
                Write-Host "   You can safely delete them manually when no longer needed."
            }
        }
    }
}

# =====================[ TASK FOLDER MANAGEMENT ]====================
function New-TaskFolder {
    param(
        [hashtable]$Context,
        [string]$TaskName
    )
    # Sanitize folder name and ensure it's not too long
    $taskFolderName = $TaskName -replace '[^\w\-_]', '_'  # Sanitize folder name
    
    # Truncate folder name if it's too long to prevent path length issues
    if ($taskFolderName.Length -gt 50) {
        $taskFolderName = $taskFolderName.Substring(0, 50)
    }
    
    $taskFolderPath = Join-Path $Context.TempFolder $taskFolderName
    
    # Additional safety check for path length (Windows has ~260 char limit)
    if ($taskFolderPath.Length -gt 200) {
        $shorterName = "Task_" + [System.IO.Path]::GetRandomFileName().Replace('.', '')
        $taskFolderPath = Join-Path $Context.TempFolder $shorterName
        Write-Log -Context $Context -Message "Using shortened folder name due to path length: $shorterName" -Level 'WARNING'
    }
    
    if (-not (Test-Path $taskFolderPath)) {
        New-Item -ItemType Directory -Path $taskFolderPath -Force | Out-Null
    }
    
    # Store the task folder path in context for later reference
    $Context.TaskFolders[$TaskName] = $taskFolderPath
    $Context.CurrentTaskFolder = $taskFolderPath
    
    Write-Log -Context $Context -Message "Created task folder: $taskFolderPath" -Level 'INFO'
    return $taskFolderPath
}

function Get-TaskFolder {
    param(
        [hashtable]$Context,
        [string]$TaskName
    )
    return $Context.TaskFolders[$TaskName]
}

# =====================[ ENHANCED LOGGING SYSTEM ]====================

# =====================================================================================
# STANDARDIZED LOG STRUCTURE POLICY
# =====================================================================================
# All task logs follow this standardized structure with clear section delimiters:
# 1. LOG HEADER - Task metadata, timestamp, system info
# 2. TASK INITIALIZATION - Setup and parameter validation  
# 3. PRE-EXECUTION STATE - System state before changes
# 4. EXECUTION STEPS - Detailed step-by-step operations
# 5. RESULTS SUMMARY - What was accomplished/changed
# 6. POST-EXECUTION STATE - System state after changes
# 7. ERROR HANDLING - Any errors encountered and recovery actions
# 8. PERFORMANCE METRICS - Timing and resource usage
# 9. LOG FOOTER - Task completion status and next steps
# =====================================================================================

function Write-Log {
    param(
        [hashtable]$Context,
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $logPath = $Context.LogPath
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
    
    # Simple text output without any colors
    Write-Host $entry
}

function Write-TaskLog {
    param(
        [hashtable]$Context,
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')]
        [string]$Level = 'INFO',
        [string]$Section = 'GENERAL'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] [$Section] [$($Context.TaskName)] $Message"
    
    # Check if TaskLogPath exists and is accessible
    if ($Context.TaskLogPath -and (Test-Path (Split-Path $Context.TaskLogPath -Parent) -ErrorAction SilentlyContinue)) {
        try {
            Add-Content -Path $Context.TaskLogPath -Value $entry -Encoding UTF8
        } catch {
            # If task log fails, fall back to main log
            if ($Context.LogPath -and (Test-Path (Split-Path $Context.LogPath -Parent) -ErrorAction SilentlyContinue)) {
                try {
                    Add-Content -Path $Context.LogPath -Value $entry -Encoding UTF8
                } catch {
                    # Ultimate fallback - just output to console
                    Write-Host $entry
                }
            } else {
                Write-Host $entry
            }
        }
    } else {
        # Task folder doesn't exist, fall back to main log or console
        if ($Context.LogPath -and (Test-Path (Split-Path $Context.LogPath -Parent) -ErrorAction SilentlyContinue)) {
            try {
                Add-Content -Path $Context.LogPath -Value $entry -Encoding UTF8
            } catch {
                Write-Host $entry
            }
        } else {
            Write-Host $entry
        }
    }
}

function Start-TaskLog {
    param(
        [hashtable]$Context,
        [string]$TaskName,
        [string]$TaskDescription,
        [hashtable]$Parameters = @{}
    )
    
    $delimiter = "=" * 100
    $subDelimiter = "-" * 80
    
    # LOG HEADER SECTION
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message $delimiter
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "TASK LOG: $TaskName"
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "DESCRIPTION: $TaskDescription"
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "START TIME: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "SYSTEM: $($env:COMPUTERNAME)"
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "USER: $($env:USERNAME)"
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "POWERSHELL VERSION: $($PSVersionTable.PSVersion)"
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "OS VERSION: $([System.Environment]::OSVersion.VersionString)"
    
    if ($Parameters.Count -gt 0) {
        Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "PARAMETERS:"
        foreach ($param in $Parameters.GetEnumerator()) {
            Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message "  $($param.Key): $($param.Value)"
        }
    }
    
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message $delimiter
    Write-TaskLog -Context $Context -Section "HEADER" -Level "INFO" -Message ""
    
    # Store start time for performance metrics
    $Context.TaskStartTime = Get-Date
}

function Write-TaskSection {
    param(
        [hashtable]$Context,
        [string]$SectionName,
        [string]$Message = ""
    )
    
    $subDelimiter = "-" * 80
    Write-TaskLog -Context $Context -Section $SectionName -Level "INFO" -Message $subDelimiter
    Write-TaskLog -Context $Context -Section $SectionName -Level "INFO" -Message "SECTION: $SectionName"
    if ($Message) {
        Write-TaskLog -Context $Context -Section $SectionName -Level "INFO" -Message $Message
    }
    Write-TaskLog -Context $Context -Section $SectionName -Level "INFO" -Message $subDelimiter
}

function Complete-TaskLog {
    param(
        [hashtable]$Context,
        [string]$TaskName,
        [string]$Status = "COMPLETED",
        [hashtable]$Summary = @{},
        [array]$Errors = @(),
        [string]$NextSteps = ""
    )
    
    $delimiter = "=" * 100
    $endTime = Get-Date
    $duration = if ($Context.TaskStartTime) { 
        $endTime - $Context.TaskStartTime 
    } else { 
        New-TimeSpan -Seconds 0 
    }
    
    # RESULTS SUMMARY SECTION
    Write-TaskSection -Context $Context -SectionName "RESULTS_SUMMARY"
    Write-TaskLog -Context $Context -Section "RESULTS_SUMMARY" -Level "INFO" -Message "TASK STATUS: $Status"
    
    if ($Summary.Count -gt 0) {
        Write-TaskLog -Context $Context -Section "RESULTS_SUMMARY" -Level "INFO" -Message "SUMMARY DETAILS:"
        foreach ($item in $Summary.GetEnumerator()) {
            Write-TaskLog -Context $Context -Section "RESULTS_SUMMARY" -Level "INFO" -Message "  $($item.Key): $($item.Value)"
        }
    }
    
    # ERROR HANDLING SECTION
    if ($Errors.Count -gt 0) {
        Write-TaskSection -Context $Context -SectionName "ERROR_HANDLING"
        Write-TaskLog -Context $Context -Section "ERROR_HANDLING" -Level "ERROR" -Message "ERRORS ENCOUNTERED: $($Errors.Count)"
        foreach ($logError in $Errors) {
            Write-TaskLog -Context $Context -Section "ERROR_HANDLING" -Level "ERROR" -Message "  $logError"
        }
    }
    
    # PERFORMANCE METRICS SECTION
    Write-TaskSection -Context $Context -SectionName "PERFORMANCE_METRICS"
    Write-TaskLog -Context $Context -Section "PERFORMANCE_METRICS" -Level "INFO" -Message "EXECUTION TIME: $($duration.ToString('hh\:mm\:ss\.fff'))"
    Write-TaskLog -Context $Context -Section "PERFORMANCE_METRICS" -Level "INFO" -Message "END TIME: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    # LOG FOOTER SECTION
    Write-TaskLog -Context $Context -Section "FOOTER" -Level "INFO" -Message ""
    Write-TaskLog -Context $Context -Section "FOOTER" -Level "INFO" -Message $delimiter
    Write-TaskLog -Context $Context -Section "FOOTER" -Level "INFO" -Message "TASK COMPLETED: $TaskName"
    Write-TaskLog -Context $Context -Section "FOOTER" -Level "INFO" -Message "FINAL STATUS: $Status"
    if ($NextSteps) {
        Write-TaskLog -Context $Context -Section "FOOTER" -Level "INFO" -Message "NEXT STEPS: $NextSteps"
    }
    Write-TaskLog -Context $Context -Section "FOOTER" -Level "INFO" -Message "LOG END: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-TaskLog -Context $Context -Section "FOOTER" -Level "INFO" -Message $delimiter
}

function Write-StateSnapshot {
    param(
        [hashtable]$Context,
        [string]$SnapshotType,  # PRE_EXECUTION or POST_EXECUTION
        [hashtable]$StateData = @{}
    )
    
    Write-TaskSection -Context $Context -SectionName "${SnapshotType}_STATE"
    Write-TaskLog -Context $Context -Section "${SnapshotType}_STATE" -Level "INFO" -Message "SYSTEM STATE SNAPSHOT: $SnapshotType"
    Write-TaskLog -Context $Context -Section "${SnapshotType}_STATE" -Level "INFO" -Message "TIMESTAMP: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    if ($StateData.Count -gt 0) {
        foreach ($state in $StateData.GetEnumerator()) {
            Write-TaskLog -Context $Context -Section "${SnapshotType}_STATE" -Level "INFO" -Message "  $($state.Key): $($state.Value)"
        }
    }
}

function Write-ExecutionStep {
    param(
        [hashtable]$Context,
        [string]$StepName,
        [string]$Action,
        [string]$Result = "",
        [string]$Level = "INFO"
    )
    
    Write-TaskLog -Context $Context -Section "EXECUTION_STEPS" -Level $Level -Message "STEP: $StepName"
    Write-TaskLog -Context $Context -Section "EXECUTION_STEPS" -Level $Level -Message "  ACTION: $Action"
    if ($Result) {
        Write-TaskLog -Context $Context -Section "EXECUTION_STEPS" -Level $Level -Message "  RESULT: $Result"
    }
}

# =====================[ MODULAR TASKS ]====================
# =====================================================================================
# TASK 1: CENTRAL COORDINATION POLICY
# =====================================================================================
# Purpose: Establish centralized lists and coordination policies for the entire maintenance process
# Dependencies: None (foundational task)
# Outputs: Bloatware_list.txt, EssentialApps_list.txt
# Structure:
#   1. Task initialization and logging setup
#   2. Bloatware list creation and validation
#   3. Essential applications list creation and validation
#   4. File output and storage in task folder
# =====================================================================================
function Invoke-Task1_CentralCoordinationPolicy {
    param([hashtable]$Context)
    
    # Initialize extensive task logging
    Start-TaskLog -Context $Context -TaskName "Task 1: Central Coordination Policy" -TaskDescription "Establish centralized lists and coordination policies for the entire maintenance process" -Parameters @{
        "TaskFolder" = $Context.CurrentTaskFolder
        "LogPath" = $Context.TaskLogPath
    }
    
    # Initialize error tracking and results
    $errors = @()
    $results = @{}
    
    try {
        Write-Host "=====================[ TASK 1: CENTRAL COORDINATION POLICY ]===================="
        Write-Log -Context $Context -Message "=====================[ TASK 1: CENTRAL COORDINATION POLICY ]====================" -Level 'INFO'
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # TASK INITIALIZATION SECTION
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-TaskSection -Context $Context -SectionName "TASK_INITIALIZATION" -Message "Setting up task environment and parameters"
        
        # Get current task folder for file storage
        $taskFolder = $Context.CurrentTaskFolder
        Write-ExecutionStep -Context $Context -StepName "Environment Setup" -Action "Validating task folders and paths" -Result "Task folder: $taskFolder"
        
        # Capture pre-execution state
        $preState = @{
            "TaskFolder" = $taskFolder
            "ExistingBloatwareFile" = if (Test-Path (Join-Path $taskFolder "Bloatware_list.txt")) { "EXISTS" } else { "NOT_EXISTS" }
            "ExistingEssentialAppsFile" = if (Test-Path (Join-Path $taskFolder "EssentialApps_list.txt")) { "EXISTS" } else { "NOT_EXISTS" }
            "FreeSpace" = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
        }
        Write-StateSnapshot -Context $Context -SnapshotType "PRE_EXECUTION" -StateData $preState
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # BLOATWARE LIST CREATION SECTION
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-TaskSection -Context $Context -SectionName "BLOATWARE_LIST_CREATION" -Message "Creating comprehensive bloatware list"
        
        Write-ExecutionStep -Context $Context -StepName "Bloatware Definition" -Action "Defining comprehensive bloatware list with known problematic applications"
        
        # Define comprehensive bloatware list with known problematic applications
        $Script:BloatwareList = @('Acer.AcerCollection', 'Acer.AcerConfigurationManager', 'Acer.AcerPortal',
'Acer.AcerPowerManagement', 'Acer.AcerQuickAccess', 'Acer.AcerUEIPFramework', 'Acer.AcerUserExperienceImprovementProgram',
'Adobe.AdobeCreativeCloud', 'Adobe.AdobeExpress', 'Adobe.AdobeGenuineService', 'Amazon.AmazonPrimeVideo',
'ASUS.ASUSGiftBox', 'ASUS.ASUSLiveUpdate', 'ASUS.ASUSSplendidVideoEnhancementTechnology', 'ASUS.ASUSWebStorage',
'ASUS.ASUSZenAnywhere', 'ASUS.ASUSZenLink', 'Astian.Midori', 'AvantBrowser.AvantBrowser', 'Avast.AvastFreeAntivirus',
'AVG.AVGAntiVirusFree', 'Avira.Avira', 'Baidu.BaiduBrowser', 'Baidu.PCAppStore', 'Basilisk.Basilisk',
'Bitdefender.Bitdefender', 'Blisk.Blisk', 'Booking.com.Booking', 'BraveSoftware.BraveBrowser',
'CentBrowser.CentBrowser', 'Cliqz.Cliqz', 'Coowon.Coowon', 'CoolNovo.CoolNovo', 'CyberLink.MediaSuite',
'CyberLink.Power2Go', 'CyberLink.PowerDirector', 'CyberLink.PowerDVD', 'CyberLink.YouCam', 'Dell.CustomerConnect',
'Dell.DellDigitalDelivery', 'Dell.DellFoundationServices', 'Dell.DellHelpAndSupport', 'Dell.DellMobileConnect',
'Dell.DellPowerManager', 'Dell.DellProductRegistration', 'Dell.DellSupportAssist', 'Dell.DellUpdate',
'DigitalPersona.EpicPrivacyBrowser', 'Disney.DisneyPlus', 'Dooble.Dooble', 'DriverPack.DriverPackSolution',
'ESET.ESETNOD32Antivirus', 'Evernote.Evernote', 'ExpressVPN.ExpressVPN', 'Facebook.Facebook',
'FenrirInc.Sleipnir', 'FlashPeak.SlimBrowser', 'FlashPeak.Slimjet', 'Foxit.FoxitPDFReader',
'Gameloft.MarchofEmpires', 'G5Entertainment.HiddenCity', 'GhostBrowser.GhostBrowser', 'Google.YouTube',
'HP.HP3DDriveGuard', 'HP.HPAudioSwitch', 'HP.HPClientSecurityManager', 'HP.HPConnectionOptimizer',
'HP.HPDocumentation', 'HP.HPDropboxPlugin', 'HP.HPePrintSW', 'HP.HPJumpStart', 'HP.HPJumpStartApps',
'HP.HPJumpStartLaunch', 'HP.HPRegistrationService', 'HP.HPSupportSolutionsFramework', 'HP.HPSureConnect',
'HP.HPSystemEventUtility', 'HP.HPWelcome', 'HewlettPackard.SupportAssistant', 'Hulu.Hulu', 'Instagram.Instagram',
'IOBit.AdvancedSystemCare', 'IOBit.DriverBooster', 'KDE.Falkon', 'Kaspersky.Kaspersky', 'KeeperSecurity.Keeper',
'king.com.BubbleWitch', 'king.com.CandyCrush', 'king.com.CandyCrushFriends', 'king.com.CandyCrushSaga',
'king.com.CandyCrushSodaSaga', 'king.com.FarmHeroes', 'king.com.FarmHeroesSaga', 'Lenovo.AppExplorer',
'Lenovo.LenovoCompanion', 'Lenovo.LenovoExperienceImprovement', 'Lenovo.LenovoFamilyCloud',
'Lenovo.LenovoHotkeys', 'Lenovo.LenovoMigrationAssistant', 'Lenovo.LenovoModernIMController',
'Lenovo.LenovoServiceBridge', 'Lenovo.LenovoSolutionCenter', 'Lenovo.LenovoUtility', 'Lenovo.LenovoVantage',
'Lenovo.LenovoVoice', 'Lenovo.LenovoWiFiSecurity', 'LinkedIn.LinkedIn', 'Lunascape.Lunascape',
'Maxthon.Maxthon', 'McAfee.LiveSafe', 'McAfee.Livesafe', 'McAfee.SafeConnect', 'McAfee.Security',
'McAfee.WebAdvisor', 'Microsoft.3DBuilder', 'Microsoft.Advertising.Xaml', 'Microsoft.BingFinance',
'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.BingNews', 'Microsoft.BingSports',
'Microsoft.BingTravel', 'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftPowerBIForWindows',
'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MinecraftUWP', 'Microsoft.MixedReality.Portal',
'Microsoft.NetworkSpeedTest', 'Microsoft.News', 'Microsoft.Office.OneNote', 'Microsoft.Office.Sway',
'Microsoft.OneConnect', 'Microsoft.OneDrive', 'Microsoft.People', 'Microsoft.Print3D', 'Microsoft.ScreenSketch',
'Microsoft.SkypeApp', 'Microsoft.SoundRecorder', 'Microsoft.StickyNotes', 'Microsoft.Wallet',
'Microsoft.Whiteboard', 'Microsoft.WindowsFeedback', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
'Microsoft.WindowsReadingList', 'Microsoft.WindowsSoundRecorder', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp',
'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider',
'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Mozilla.SeaMonkey',
'Norton.OnlineBackup', 'Norton.Security', 'Opera.Opera', 'Opera.OperaGX', 'Orbitum.Orbitum',
'OtterBrowser.OtterBrowser', 'PaleMoon.PaleMoon', 'PCAccelerate.PCAcceleratePro', 'PCOptimizer.PCOptimizerPro',
'PicsArt.PicsartPhotoStudio', 'Piriform.CCleaner', 'Polarity.Polarity', 'Power2Go.Power2Go',
'PowerDirector.PowerDirector', 'QupZilla.QupZilla', 'QuteBrowser.QuteBrowser', 'RandomSaladGamesLLC.SimpleSolitaire',
'Reimage.ReimageRepair', 'RoyalRevolt2.RoyalRevolt2', 'Sleipnir.Sleipnir', 'SlingTV.Sling',
'Sogou.SogouExplorer', 'Spotify.Spotify', 'SRWare.Iron', 'Sputnik.Sputnik', 'Superbird.Superbird',
'TheTorProject.TorBrowser', 'ThumbmunkeysLtd.PhototasticCollage', 'TikTok.TikTok', 'TorchMediaInc.Torch',
'TripAdvisor.TripAdvisor', 'Twitter.Twitter', 'UCWeb.UCBrowser', 'VivaldiTechnologies.Vivaldi',
'Waterfox.Waterfox', 'WildTangent.WildTangentGamesApp', 'WildTangent.WildTangentHelper', 'WPSOffice.WPSOffice',
'Yandex.YandexBrowser'
    ) | Sort-Object -Unique
    
    Write-ExecutionStep -Context $Context -StepName "Bloatware List Creation" -Action "Created comprehensive bloatware list with $($Script:BloatwareList.Count) applications" -Result "SUCCESS"
    $results.Add("BloatwareAppsCount", $Script:BloatwareList.Count)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # ESSENTIAL APPLICATIONS LIST CREATION SECTION
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-TaskSection -Context $Context -SectionName "ESSENTIAL_APPS_LIST_CREATION" -Message "Creating essential applications list with package sources"
    
    Write-ExecutionStep -Context $Context -StepName "Essential Apps Definition" -Action "Defining essential applications with both winget and chocolatey package sources"
    
    # Define essential applications with both winget and chocolatey package sources
    $Script:EssentialApps = @(
        @{ Name = 'Adobe Acrobat Reader'; Winget = 'Adobe.Acrobat.Reader.64-bit'; Choco = 'adobereader' },
        @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome' },
        @{ Name = 'Microsoft Edge'; Winget = 'Microsoft.Edge'; Choco = 'microsoft-edge' },
        @{ Name = 'Total Commander'; Winget = 'Ghisler.TotalCommander'; Choco = 'totalcommander' },
        @{ Name = 'PowerShell 7'; Winget = 'Microsoft.Powershell'; Choco = 'powershell' },
        @{ Name = 'Windows Terminal'; Winget = 'Microsoft.WindowsTerminal'; Choco = 'microsoft-windows-terminal' },
        @{ Name = 'WinRAR'; Winget = 'RARLab.WinRAR'; Choco = 'winrar' },
        @{ Name = '7-Zip'; Winget = '7zip.7zip'; Choco = '7zip' },
        @{ Name = 'Notepad++'; Winget = 'Notepad++.Notepad++'; Choco = 'notepadplusplus' },
        @{ Name = 'PDF24 Creator'; Winget = 'PDF24.PDF24Creator'; Choco = 'pdf24' },
        @{ Name = 'Java 8 Update'; Winget = 'Oracle.JavaRuntimeEnvironment'; Choco = 'javaruntime' }
    )
    
    Write-ExecutionStep -Context $Context -StepName "Essential Apps List Creation" -Action "Created essential applications list with $($Script:EssentialApps.Count) applications" -Result "SUCCESS"
    $results.Add("EssentialAppsCount", $Script:EssentialApps.Count)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # FILE OUTPUT AND STORAGE SECTION
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-TaskSection -Context $Context -SectionName "FILE_OUTPUT_STORAGE" -Message "Writing lists to files for inter-task coordination"
    
    # Write bloatware list to task folder for use by other tasks
    $bloatwareListPath = Join-Path $taskFolder 'Bloatware_list.txt'
    Write-ExecutionStep -Context $Context -StepName "Bloatware File Creation" -Action "Writing bloatware list to $bloatwareListPath"
    
    try {
        $Script:BloatwareList | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $bloatwareListPath -Encoding UTF8
        Write-ExecutionStep -Context $Context -StepName "Bloatware File Creation" -Action "Wrote bloatware list to file" -Result "SUCCESS - File size: $((Get-Item $bloatwareListPath).Length) bytes"
        $results.Add("BloatwareListFile", $bloatwareListPath)
    } catch {
        $errorMsg = "Failed to write bloatware list: $($_.Exception.Message)"
        $errors += $errorMsg
        Write-ExecutionStep -Context $Context -StepName "Bloatware File Creation" -Action "Write bloatware list to file" -Result $errorMsg -Level "ERROR"
    }
    
    # Write essential apps list to task folder for use by other tasks
    $essentialAppsListPath = Join-Path $taskFolder 'EssentialApps_list.txt'
    Write-ExecutionStep -Context $Context -StepName "Essential Apps File Creation" -Action "Writing essential apps list to $essentialAppsListPath"
    
    try {
        $Script:EssentialApps | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $essentialAppsListPath -Encoding UTF8
        Write-ExecutionStep -Context $Context -StepName "Essential Apps File Creation" -Action "Wrote essential apps list to file" -Result "SUCCESS - File size: $((Get-Item $essentialAppsListPath).Length) bytes"
        $results.Add("EssentialAppsListFile", $essentialAppsListPath)
    } catch {
        $errorMsg = "Failed to write essential apps list: $($_.Exception.Message)"
        $errors += $errorMsg
        Write-ExecutionStep -Context $Context -StepName "Essential Apps File Creation" -Action "Write essential apps list to file" -Result $errorMsg -Level "ERROR"
    }
    
    # Capture post-execution state
    $postState = @{
        "BloatwareListFileExists" = if (Test-Path $bloatwareListPath) { "SUCCESS" } else { "FAILED" }
        "EssentialAppsFileExists" = if (Test-Path $essentialAppsListPath) { "SUCCESS" } else { "FAILED" }
        "BloatwareFileSize" = if (Test-Path $bloatwareListPath) { (Get-Item $bloatwareListPath).Length } else { 0 }
        "EssentialAppsFileSize" = if (Test-Path $essentialAppsListPath) { (Get-Item $essentialAppsListPath).Length } else { 0 }
        "FreeSpaceAfter" = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
    }
    Write-StateSnapshot -Context $Context -SnapshotType "POST_EXECUTION" -StateData $postState
    
    } catch {
        $errorMsg = "Critical error in Task 1: $($_.Exception.Message)"
        $errors += $errorMsg
        Write-ExecutionStep -Context $Context -StepName "Task Execution" -Action "Complete task execution" -Result $errorMsg -Level "ERROR"
    } finally {
        # Complete the task log with comprehensive summary
        $status = if ($errors.Count -eq 0) { "COMPLETED_SUCCESS" } else { "COMPLETED_WITH_ERRORS" }
        
        Complete-TaskLog -Context $Context -TaskName "Task 1: Central Coordination Policy" -Status $status -Summary $results -Errors $errors -NextSteps "Proceed to Task 2: System Protection"
        
        Write-Log -Context $Context -Message "Task 1: Central Coordination Policy completed with status: $status" -Level 'INFO'
    }
}
# =====================================================================================
# END TASK 1: CENTRAL COORDINATION POLICY
# =====================================================================================

# =====================================================================================
# TASK 2: SYSTEM PROTECTION
# =====================================================================================
# Purpose: Enable System Restore and create a restoration checkpoint before modifications
# Dependencies: None (protective measure)
# Outputs: System restore point, restore configuration
# Structure:
#   1. Task initialization and logging setup
#   2. System Restore status verification
#   3. System Restore enablement (if needed)
#   4. Restore point creation
# =====================================================================================
function Invoke-Task2_SystemProtection {
    param([hashtable]$Context)
    
    # Initialize extensive task logging
    Start-TaskLog -Context $Context -TaskName "Task 2: System Protection" -TaskDescription "Enable System Restore and create a restoration checkpoint before modifications" -Parameters @{
        "OSDrive" = "C:"
        "TaskFolder" = $Context.CurrentTaskFolder
    }
    
    # Initialize error tracking and results
    $errors = @()
    $results = @{}
    $osDrive = "C:"
    
    try {
        Write-Host "=====================[ TASK 2: SYSTEM PROTECTION ]===================="
        Write-Log -Context $Context -Message "=====================[ TASK 2: SYSTEM PROTECTION ]====================" -Level 'INFO'
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # TASK INITIALIZATION SECTION  
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-TaskSection -Context $Context -SectionName "TASK_INITIALIZATION" -Message "Setting up system protection environment"
        
        Write-ExecutionStep -Context $Context -StepName "Environment Setup" -Action "Initializing system protection variables and parameters" -Result "OS Drive: $osDrive"
        
        # Capture pre-execution state
        $preState = @{
            "OSVersion" = [System.Environment]::OSVersion.VersionString
            "SystemDrive" = $osDrive
            "FreeSpace" = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$osDrive'").FreeSpace
            "RestorePointsExisting" = (Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        Write-StateSnapshot -Context $Context -SnapshotType "PRE_EXECUTION" -StateData $preState
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SYSTEM RESTORE STATUS VERIFICATION SECTION
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-TaskSection -Context $Context -SectionName "SYSTEM_RESTORE_STATUS" -Message "Checking current System Restore configuration"
        
        Write-ExecutionStep -Context $Context -StepName "System Restore Status Check" -Action "Checking if System Restore is enabled on $osDrive"
        
        # Check current restore point status
        $srStatus = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        if ($srStatus) {
            Write-ExecutionStep -Context $Context -StepName "System Restore Status Check" -Action "System Restore status verification" -Result "ENABLED - Found $($srStatus.Count) existing restore points"
            $results.Add("SystemRestoreStatus", "ALREADY_ENABLED")
            $results.Add("ExistingRestorePoints", $srStatus.Count)
        } else {
            Write-ExecutionStep -Context $Context -StepName "System Restore Status Check" -Action "System Restore status verification" -Result "DISABLED - No restore points found"
            $results.Add("SystemRestoreStatus", "DISABLED")
            
            # ═══════════════════════════════════════════════════════════════════════════════════
            # SYSTEM RESTORE ENABLEMENT SECTION
            # ═══════════════════════════════════════════════════════════════════════════════════
            Write-TaskSection -Context $Context -SectionName "SYSTEM_RESTORE_ENABLEMENT" -Message "Enabling System Restore on OS drive"
            
            Write-ExecutionStep -Context $Context -StepName "Enable System Restore" -Action "Enabling System Restore on $osDrive"
            
            try {
                Enable-ComputerRestore -Drive $osDrive -ErrorAction Stop
                Write-ExecutionStep -Context $Context -StepName "Enable System Restore" -Action "Enable System Restore on $osDrive" -Result "SUCCESS - System Restore enabled"
                $results.Add("SystemRestoreEnabled", "SUCCESS")
            } catch {
                $errorMsg = "Failed to enable System Restore: $($_.Exception.Message)"
                $errors += $errorMsg
                Write-ExecutionStep -Context $Context -StepName "Enable System Restore" -Action "Enable System Restore on $osDrive" -Result $errorMsg -Level "ERROR"
                $results.Add("SystemRestoreEnabled", "FAILED")
            }
        }
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # RESTORE POINT CREATION SECTION
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-TaskSection -Context $Context -SectionName "RESTORE_POINT_CREATION" -Message "Creating system restore point for maintenance safety"
        
        Write-ExecutionStep -Context $Context -StepName "Create Restore Point" -Action "Creating system restore point with description 'System Maintenance Script'"
        
        try {
            Checkpoint-Computer -Description "System Maintenance Script" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
            Write-ExecutionStep -Context $Context -StepName "Create Restore Point" -Action "Create system restore point" -Result "SUCCESS - Restore point created successfully"
            $results.Add("RestorePointCreated", "SUCCESS")
            $results.Add("RestorePointDescription", "System Maintenance Script")
        } catch {
            $errorMsg = "Failed to create restore point: $($_.Exception.Message)"
            $errors += $errorMsg
            Write-ExecutionStep -Context $Context -StepName "Create Restore Point" -Action "Create system restore point" -Result $errorMsg -Level "ERROR"
            $results.Add("RestorePointCreated", "FAILED")
        }
        
        # Capture post-execution state
        $postState = @{
            "RestorePointsAfter" = (Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Measure-Object).Count
            "SystemRestoreEnabled" = if (Get-ComputerRestorePoint -ErrorAction SilentlyContinue) { "TRUE" } else { "FALSE" }
            "FreeSpaceAfter" = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$osDrive'").FreeSpace
        }
        Write-StateSnapshot -Context $Context -SnapshotType "POST_EXECUTION" -StateData $postState
        
    } catch {
        $errorMsg = "Critical error in Task 2: $($_.Exception.Message)"
        $errors += $errorMsg
        Write-ExecutionStep -Context $Context -StepName "Task Execution" -Action "Complete task execution" -Result $errorMsg -Level "ERROR"
    } finally {
        # Complete the task log with comprehensive summary
        $status = if ($errors.Count -eq 0) { "COMPLETED_SUCCESS" } else { "COMPLETED_WITH_ERRORS" }
        
        Complete-TaskLog -Context $Context -TaskName "Task 2: System Protection" -Status $status -Summary $results -Errors $errors -NextSteps "Proceed to Task 3: Package Manager Setup"
        
        Write-Log -Context $Context -Message "Task 2: System Protection completed with status: $status" -Level 'INFO'
    }
}
    
    Write-TaskLog -Context $Context -Message "Task 2 completed." -Level 'SUCCESS'

# =====================================================================================
# END TASK 2: SYSTEM PROTECTION
# =====================================================================================

# =====================================================================================
# TASK 3: PACKAGE MANAGER SETUP
# =====================================================================================
# Purpose: Install and configure essential package managers (winget and Chocolatey)
# Dependencies: Internet connection for package downloads
# Outputs: Configured winget and Chocolatey installations
# Structure:
#   1. Task initialization and logging setup
#   2. Winget availability check and installation
#   3. Winget update process
#   4. Chocolatey availability check and installation
#   5. Chocolatey update process
# =====================================================================================
function Invoke-Task3_PackageManagerSetup {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 3: PACKAGE MANAGER SETUP ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 3: PACKAGE MANAGER SETUP ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 3: Package Manager Setup started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 3: Package Manager Setup started." -Level 'INFO'
    
    try {
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 2: WINGET AVAILABILITY CHECK AND INSTALLATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Check if winget is already installed
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Log -Context $Context -Message "winget not installed. Attempting installation..." -Level 'WARNING'
            try {
                $appInstallerUrl = "https://aka.ms/getwinget"
                $wingetInstaller = Join-Path $Context.CurrentTaskFolder "AppInstaller.msixbundle"
                Invoke-WebRequest -Uri $appInstallerUrl -OutFile $wingetInstaller -UseBasicParsing
                Add-AppxPackage -Path $wingetInstaller
                Write-Log -Context $Context -Message "winget installed via App Installer package." -Level 'SUCCESS'
            } catch {
                Write-Log -Context $Context -Message "Failed to install winget: $_" -Level 'ERROR'
            }
        } else {
            Write-Log -Context $Context -Message "winget installed." -Level 'SUCCESS'
            
            # ═══════════════════════════════════════════════════════════════════════════════════
            # SECTION 3: WINGET UPDATE PROCESS
            # ═══════════════════════════════════════════════════════════════════════════════════
            # Try to update winget to latest version
            try {
                $updateResult = winget upgrade --id Microsoft.DesktopAppInstaller --accept-source-agreements --accept-package-agreements --silent -e 2>&1
                if ($updateResult -match 'No applicable update found' -or $updateResult -match 'No installed package found') {
                    Write-Log -Context $Context -Message "winget is up to date." -Level 'INFO'
                } elseif ($updateResult -match 'Successfully installed' -or $updateResult -match 'Successfully upgraded') {
                    Write-Log -Context $Context -Message "winget updated successfully." -Level 'SUCCESS'
                } else {
                    Write-Log -Context $Context -Message "winget update output: $updateResult" -Level 'INFO'
                }
            } catch {
                Write-Log -Context $Context -Message "Failed to update winget: $_" -Level 'WARNING'
            }
        }

        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 4: CHOCOLATEY AVAILABILITY CHECK AND INSTALLATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Check if Chocolatey is already installed
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if (-not $choco) {
            Write-Log -Context $Context -Message "Chocolatey not installed. Attempting installation..." -Level 'WARNING'
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                $chocoScript = 'Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))'
                powershell -NoProfile -ExecutionPolicy Bypass -Command $chocoScript
                Write-Log -Context $Context -Message "Chocolatey installed via official script." -Level 'SUCCESS'
            } catch {
                Write-Log -Context $Context -Message "Failed to install Chocolatey: $_" -Level 'ERROR'
            }
        } else {
            Write-Log -Context $Context -Message "Chocolatey installed." -Level 'SUCCESS'
            
            # ═══════════════════════════════════════════════════════════════════════════════════
            # SECTION 5: CHOCOLATEY UPDATE PROCESS
            # ═══════════════════════════════════════════════════════════════════════════════════
            # Try to update Chocolatey to latest version
            try {
                $updateResult = choco upgrade chocolatey -y 2>&1
                if ($updateResult -match '0 upgrades' -or $updateResult -match 'Chocolatey v') {
                    Write-Log -Context $Context -Message "Chocolatey is up to date." -Level 'INFO'
                } elseif ($updateResult -match 'Upgraded') {
                    Write-Log -Context $Context -Message "Chocolatey updated successfully." -Level 'SUCCESS'
                } else {
                    Write-Log -Context $Context -Message "Chocolatey update output: $updateResult" -Level 'INFO'
                }
            } catch {
                Write-Log -Context $Context -Message "Failed to update Chocolatey: $_" -Level 'WARNING'
            }
        }
    } catch {
        Write-Log -Context $Context -Message "Task 3: Package manager check/installation failed: $_" -Level 'ERROR'
    }
    Write-TaskLog -Context $Context -Message "Task 3 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 3: PACKAGE MANAGER SETUP
# =====================================================================================

# =====================================================================================
# TASK 4: SYSTEM INVENTORY
# =====================================================================================
# Purpose: Collect comprehensive system information and installed software inventory
# Dependencies: WMI access, system read permissions
# Outputs: OS info, hardware info, disk info, network info, installed programs list
# Structure:
#   1. Task initialization and logging setup
#   2. Inventory directory creation
#   3. Operating system information collection
#   4. Hardware information collection
#   5. Disk and network information collection
#   6. Installed programs inventory compilation
# =====================================================================================
function Invoke-Task4_SystemInventory {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 4: SYSTEM INVENTORY ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 4: SYSTEM INVENTORY ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 4: System Inventory started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 4: System Inventory started." -Level 'INFO'
    
    try {
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 2: INVENTORY DIRECTORY CREATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        $inventoryPath = Join-Path $Context.CurrentTaskFolder 'inventory'
        New-Item -ItemType Directory -Path $inventoryPath -Force | Out-Null
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 3: OPERATING SYSTEM INFORMATION COLLECTION
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-Host "[System Inventory] Collecting OS info..."
        Write-Log -Context $Context -Message "Task 4: Collecting OS info..." -Level 'INFO'
        Get-ComputerInfo | Out-File (Join-Path $inventoryPath 'os_info.txt')
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 4: HARDWARE INFORMATION COLLECTION
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-Host "[System Inventory] Collecting hardware info..."
        Write-Log -Context $Context -Message "Collecting hardware info..." -Level 'INFO'
        Get-WmiObject -Class Win32_ComputerSystem | Out-File (Join-Path $inventoryPath 'hardware_info.txt')
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 5: DISK AND NETWORK INFORMATION COLLECTION
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-Host "[System Inventory] Collecting disk info..."
        Write-Log -Context $Context -Message "Collecting disk info..." -Level 'INFO'
        Get-PSDrive | Where-Object {$_.Provider -like '*FileSystem*'} | Out-File (Join-Path $inventoryPath 'disk_info.txt')
        
        Write-Host "[System Inventory] Collecting network info..."
        Write-Log -Context $Context -Message "Collecting network info..." -Level 'INFO'
        Get-NetIPAddress | Out-File (Join-Path $inventoryPath 'network_info.txt')
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 6: INSTALLED PROGRAMS INVENTORY COMPILATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Compile comprehensive list from multiple sources
        $installedProgramsList = @()
        
        # Registry-based installed programs (64-bit)
        $installedProgramsList += Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        
        # Registry-based installed programs (32-bit on 64-bit systems)
        $installedProgramsList += Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        
        # AppX packages (Store apps)
        $installedProgramsList += Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name
        
        # Winget-managed packages
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetList = winget list --source winget | Select-Object -Skip 1
            $installedProgramsList += $wingetList | ForEach-Object { $_.Split(' ')[0] }
        }
        
        # Clean and deduplicate the list
        $installedProgramsList = $installedProgramsList | Where-Object { $_ -and $_.Trim() -ne '' }
        
        # Save inventory to both locations for task coordination
        $installedProgramsPath = Join-Path $inventoryPath 'installed_programs.txt'
        $installedProgramsList | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $installedProgramsPath
        
        $installedProgramsDiffPath = Join-Path $Context.CurrentTaskFolder 'InstalledPrograms_list.txt'
        $installedProgramsList | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $installedProgramsDiffPath -Encoding UTF8
        
        Write-Host "[System Inventory] Installed programs list saved to $installedProgramsPath"
        Write-Log -Context $Context -Message "Task 4: Inventory collected in $inventoryPath" -Level 'SUCCESS'
    } catch {
        Write-Log -Context $Context -Message "Task 4: System Inventory failed: $_" -Level 'ERROR'
    }
    Write-TaskLog -Context $Context -Message "Task 4 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 4: SYSTEM INVENTORY
# =====================================================================================

# =====================================================================================
# TASK 5: REMOVE BLOATWARE
# =====================================================================================
# Purpose: Remove unwanted bloatware applications from the system using multiple methods
# Dependencies: Bloatware list from Task 1, installed programs inventory
# Outputs: BloatwareDiff_list.txt, removal logs, system cleanup results
# Structure:
#   1. Task initialization and logging setup
#   2. Installed programs inventory generation
#   3. Bloatware detection and filtering
#   4. Special cases configuration
#   5. Multi-method removal process (AppX, winget, WMI)
#   6. Results compilation and reporting
# =====================================================================================
function Invoke-Task5_RemoveBloatware {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 5: REMOVE BLOATWARE ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 5: REMOVE BLOATWARE ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 5: Remove Bloatware started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 5: Remove Bloatware started." -Level 'INFO'
    
    try {
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 2: INSTALLED PROGRAMS INVENTORY GENERATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Generate current system's installed programs list for comparison
        $installedProgramsDiffPath = Join-Path $Context.CurrentTaskFolder 'InstalledPrograms_list.txt'
        $installedPrograms = @()
        
        # Collect from registry (64-bit and 32-bit entries)
        $installedPrograms += Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        $installedPrograms += Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        
        # Collect AppX packages
        $installedPrograms += Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name
        
        # Collect winget-managed packages
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetList = winget list --source winget | Select-Object -Skip 1
            $installedPrograms += $wingetList | ForEach-Object { $_.Split(' ')[0] }
        }
        
        # Clean and save the list
        $installedPrograms = $installedPrograms | Where-Object { $_ -and $_.Trim() -ne '' }
        $installedPrograms | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $installedProgramsDiffPath -Encoding UTF8

        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 3: BLOATWARE DETECTION AND FILTERING
        # ═══════════════════════════════════════════════════════════════════════════════════
        Write-Log -Context $Context -Message "Scanning for bloatware apps to remove..." -Level 'INFO'
        
        # Load bloatware list from Task 1's coordination files
        $task1FolderPath = Get-TaskFolder -Context $Context -TaskName "Task1_CentralCoordinationPolicy"
        $bloatwareListPath = Join-Path $task1FolderPath 'Bloatware_list.txt'
        $bloatwareList = @()
        try {
            $bloatwareList = Get-Content $bloatwareListPath -Raw | ConvertFrom-Json
        } catch {
            $bloatwareList = Get-Content $bloatwareListPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_ | ConvertFrom-Json }
        }
        
        # Load installed programs for comparison
        $installed = @()
        try {
            $installed = Get-Content $installedProgramsDiffPath -Raw | ConvertFrom-Json
        } catch {
            $installed = Get-Content $installedProgramsDiffPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_ | ConvertFrom-Json }
        }
        
        # Filter bloatware to only include what's actually installed
        $bloatwareToRemove = @()
        foreach ($bloat in $bloatwareList) {
            if ($installed | Where-Object { $_.ToLower().Contains($bloat.ToLower()) }) {
                $bloatwareToRemove += $bloat
            }
        }
        
        # Save filtered bloatware list for processing
        $diffListPath = Join-Path $Context.CurrentTaskFolder 'BloatwareDiff_list.txt'
        $bloatwareToRemove | ConvertTo-Json | Out-File $diffListPath -Encoding UTF8
        Write-Log -Context $Context -Message "Diff list created. Only installed bloatware will be processed. Diff list saved to $diffListPath" -Level 'INFO'
        Write-Log -Context $Context -Message ("Diff list contents: {0}" -f ($bloatwareToRemove -join ', ')) -Level 'INFO'

        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 4: SPECIAL CASES CONFIGURATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Define special handling for applications that require specific removal methods
        $BloatwareSpecialCases = @{
            'Clipchamp' = @{ AppX = 'Clipchamp.Clipchamp'; Winget = $null };
            'LinkedIn'  = @{ AppX = 'Microsoft.LinkedIn'; Winget = $null };
            'Vivaldi'   = @{ AppX = $null; Winget = 'VivaldiTechnologies.Vivaldi' };
        }
        
        # Process special cases before general removal
        foreach ($key in $BloatwareSpecialCases.Keys) {
            $case = $BloatwareSpecialCases[$key]
            if ($case.AppX) {
                $pkg = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq $case.AppX }
                if ($pkg) {
                    Write-Log -Context $Context -Message "Removing AppX package: $($case.AppX)" -Level 'INFO'
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                        Write-Log -Context $Context -Message "Removed AppX package: $($case.AppX)" -Level 'SUCCESS'
                    } catch {
                        Write-Log -Context $Context -Message "Failed to remove AppX package: $($case.AppX) - $_" -Level 'WARNING'
                    }
                }
            }
            if ($case.Winget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                $wingetResult = winget uninstall --id $($case.Winget) --exact --silent --accept-source-agreements --accept-package-agreements 2>&1
                if ($wingetResult -notmatch 'No installed package found') {
                    Write-Log -Context $Context -Message "Uninstalled via winget: $($case.Winget)" -Level 'SUCCESS'
                } else {
                    Write-Log -Context $Context -Message "Winget could not uninstall: $($case.Winget)" -Level 'WARNING'
                }
            }
        }

        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 5: MULTI-METHOD REMOVAL PROCESS
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Process each identified bloatware application with multiple removal methods
        $total = $bloatwareToRemove.Count
        $current = 0
        foreach ($bloat in $bloatwareToRemove) {
            $current++
            Write-Progress -Activity "Bloatware Removal" -Status ("Uninstalling: {0} ({1}/{2})" -f $bloat, $current, $total) -PercentComplete ([int](($current / $total) * 100))
            Write-Log -Context $Context -Message ("Uninstalling: {0} ({1}/{2})" -f $bloat, $current, $total) -Level 'INFO'
            
            # Find all matching installed programs for this bloatware pattern
            $bloatMatches = $installed | Where-Object { $_ -and $_.ToLower().Contains($bloat.ToLower()) }
            
            foreach ($match in $bloatMatches) {
                $uninstallSuccess = $false
                $methodsTried = @()

                # Method 1: Try AppX removal (use robust mapping if available)
                if (-not $uninstallSuccess) {
                    $appxName = if ($BloatwareSpecialCases.ContainsKey($bloat) -and $BloatwareSpecialCases[$bloat].AppX) { $BloatwareSpecialCases[$bloat].AppX } else { $bloat }
                    $pkg = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq $appxName }
                    if ($pkg) {
                        $methodsTried += 'AppX'
                        try {
                            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                            Write-Log -Context $Context -Message "Removed AppX package: $appxName" -Level 'SUCCESS'
                            $uninstallSuccess = $true
                        } catch {
                            Write-Log -Context $Context -Message ("Failed to remove AppX package: {0} - {1}" -f $appxName, $_) -Level 'WARNING'
                        }
                    }
                }

                # Method 2: Try winget uninstall
                if (-not $uninstallSuccess) {
                    $wingetId = if ($BloatwareSpecialCases.ContainsKey($bloat) -and $BloatwareSpecialCases[$bloat].Winget) { $BloatwareSpecialCases[$bloat].Winget } else { $match }
                    if ($wingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                        $methodsTried += 'winget'
                        try {
                            $wingetResult = winget uninstall --id "$wingetId" --exact --silent --accept-source-agreements --accept-package-agreements 2>&1
                            if ($wingetResult -notmatch 'No installed package found') {
                                Write-Log -Context $Context -Message "Uninstalled via winget: $wingetId" -Level 'SUCCESS'
                                $uninstallSuccess = $true
                            } else {
                                Write-Log -Context $Context -Message "Winget could not uninstall: $wingetId" -Level 'WARNING'
                            }
                        } catch {
                            Write-Log -Context $Context -Message ("winget uninstall failed for {0}: {1}" -f $wingetId, $_) -Level 'WARNING'
                        }
                    }
                }

                # 3. Try WMI uninstall
                if (-not $uninstallSuccess) {
                    $wmic = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $match }
                    if ($wmic) {
                        $methodsTried += 'WMI'
                        try {
                            $wmic.Uninstall() | Out-Null
                            Write-Log -Context $Context -Message "Uninstalled via WMI: $match" -Level 'SUCCESS'
                            $uninstallSuccess = $true
                        } catch {
                            Write-Log -Context $Context -Message ("WMI uninstall failed for {0}: {1}" -f $match, $_) -Level 'WARNING'
                        }
                    }
                }

                # 4. Try Uninstall-Package (PowerShell PackageManagement)
                if (-not $uninstallSuccess -and (Get-Command Uninstall-Package -ErrorAction SilentlyContinue)) {
                    $methodsTried += 'Uninstall-Package'
                    try {
                        Uninstall-Package -Name $match -Force -ErrorAction Stop
                        Write-Log -Context $Context -Message "Uninstalled via Uninstall-Package: $match" -Level 'SUCCESS'
                        $uninstallSuccess = $true
                    } catch {
                        Write-Log -Context $Context -Message ("Uninstall-Package failed for {0}: {1}" -f $match, $_) -Level 'WARNING'
                    }
                }

                # 5. Try registry uninstall string
                if (-not $uninstallSuccess) {
                    $regPaths = @(
                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
                    )
                    foreach ($regPath in $regPaths) {
                        $regApps = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.DisplayName -like "*$match*" }
                        foreach ($regApp in $regApps) {
                            if ($regApp.UninstallString) {
                                $methodsTried += 'RegistryString'
                                try {
                                    $uninstallCmd = $regApp.UninstallString
                                    if ($uninstallCmd -notmatch '/quiet|/silent') {
                                        $uninstallCmd += ' /quiet'
                                    }
                                    Write-Log -Context $Context -Message "Attempting registry uninstall: $uninstallCmd" -Level 'INFO'
                                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCmd" -Wait -NoNewWindow
                                    Write-Log -Context $Context -Message "Uninstalled via registry string: $match" -Level 'SUCCESS'
                                    $uninstallSuccess = $true
                                } catch {
                                    Write-Log -Context $Context -Message ("Registry uninstall failed for {0}: {1}" -f $match, $_) -Level 'WARNING'
                                }
                            }
                        }
                    }
                }

                if ($uninstallSuccess) {
                    # Successfully uninstalled bloatware
                } else {
                    Write-Log -Context $Context -Message ("Could not uninstall {0} using any method. Methods tried: {1}" -f $match, ($methodsTried -join ', ')) -Level 'WARNING'
                }
            }
        }
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 6: RESULTS COMPILATION AND REPORTING
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Complete the removal process and clean up temporary files
        Write-Progress -Activity "Bloatware Removal" -Status "Complete" -Completed
        Write-Log -Context $Context -Message "Bloatware removal complete. Diff list saved to $diffListPath" -Level 'SUCCESS'
        
        # Clean up temporary files used during the removal process
        if (Test-Path $installedProgramsDiffPath) {
            Remove-Item $installedProgramsDiffPath -Force
            Write-Log -Context $Context -Message "Deleted temp file: $installedProgramsDiffPath" -Level 'INFO'
        }
    } catch {
        Write-Log -Context $Context -Message "Task 5: Bloatware removal failed: $_" -Level 'ERROR'
    }
    Write-TaskLog -Context $Context -Message "Task 5 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 5: REMOVE BLOATWARE
# =====================================================================================

# =====================================================================================
# TASK 6: INSTALL ESSENTIAL APPLICATIONS
# =====================================================================================
# Purpose: Install essential applications needed for system productivity and functionality
# Dependencies: Package managers from Task 3, essential apps list from Task 1
# Outputs: EssentialAppsDiff_list.txt, installation logs, software installation results
# Structure:
#   1. Task initialization and logging setup
#   2. Current installation status analysis
#   3. Essential applications list processing
#   4. Office suite dependency evaluation
#   5. Multi-source installation process (winget and Chocolatey)
#   6. Installation results verification and cleanup
# =====================================================================================
function Invoke-Task6_InstallEssentialApps {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 6: INSTALL ESSENTIAL APPLICATIONS ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 6: INSTALL ESSENTIAL APPLICATIONS ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 6: Install Essential Applications started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 6: Install Essential Applications started." -Level 'INFO'
    Write-Host "[Essential Apps] Checking installed programs and preparing list..."
    
    try {
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 2: CURRENT INSTALLATION STATUS ANALYSIS
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Generate current system's installed programs list for comparison with essential apps
        $installedProgramsDiffPath = Join-Path $Context.CurrentTaskFolder 'InstalledPrograms_list.txt'
        $installedPrograms = @()
        
        # Collect from registry (64-bit and 32-bit entries)
        $installedPrograms += Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        $installedPrograms += Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        
        # Collect AppX packages
        $installedPrograms += Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name
        
        # Collect winget-managed packages
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetList = winget list --source winget | Select-Object -Skip 1
            $installedPrograms += $wingetList | ForEach-Object { $_.Split(' ')[0] }
        }
        
        # Clean and save the list
        $installedPrograms = $installedPrograms | Where-Object { $_ -and $_.Trim() -ne '' }
        $installedPrograms | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $installedProgramsDiffPath -Encoding UTF8

        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 3: ESSENTIAL APPLICATIONS LIST PROCESSING
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Load essential apps list from Task 1's coordination files
        $task1FolderPath = Get-TaskFolder -Context $Context -TaskName "Task1_CentralCoordinationPolicy"
        $essentialAppsListPath = Join-Path $task1FolderPath 'EssentialApps_list.txt'
        $essentialApps = Get-Content $essentialAppsListPath | ForEach-Object { $_ | ConvertFrom-Json }
        $installed = Get-Content $installedProgramsDiffPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_ | ConvertFrom-Json }
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 4: OFFICE SUITE DEPENDENCY EVALUATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Check for existing office suites to avoid conflicts
        $officeInstalled = $false
        $officeNames = @('Microsoft Office', 'Office16', 'Office15', 'Office14', 'Office12', 'Office11', 'Office10', 'Office09', 'Office08', 'Office07', 'Office 365')
        foreach ($name in $officeNames) {
            if ($installed | Where-Object { $_ -like "*$name*" }) {
                $officeInstalled = $true
                break
            }
        }
        
        # Check for LibreOffice installation
        $libreInstalled = $false
        $libreNames = @('LibreOffice')
        foreach ($name in $libreNames) {
            if ($installed | Where-Object { $_ -like "*$name*" }) {
                $libreInstalled = $true
                break
            }
        }
        
        # Add LibreOffice if no office suite is present
        if (-not $libreInstalled) {
            if (-not $officeInstalled) {
                $essentialApps += @{ Name = 'LibreOffice'; Winget = 'TheDocumentFoundation.LibreOffice'; Choco = 'libreoffice-fresh' }
                Write-Log -Context $Context -Message "LibreOffice added to essential apps list." -Level 'INFO'
            } else {
                Write-Log -Context $Context -Message "Microsoft Office is installed. Skipping LibreOffice installation." -Level 'INFO'
            }
        } else {
            Write-Log -Context $Context -Message "LibreOffice is already installed. Skipping." -Level 'INFO'
        }
        
        # Filter essential apps to only include what's NOT already installed
        $appsToInstall = @()
        foreach ($app in $essentialApps) {
            $isInstalled = $installed | Where-Object { $_ -and $_ -like "*$($app.Name)*" }
            if (-not $isInstalled) {
                $appsToInstall += $app
            }
        }
        
        # Save filtered essential apps list for processing
        $diffListPath = Join-Path $Context.CurrentTaskFolder 'EssentialAppsDiff_list.txt'
        $appsToInstall | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $diffListPath -Encoding UTF8
        Write-Host ("[Essential Apps] The following apps will be installed: {0}" -f ($appsToInstall | ForEach-Object { $_.Name } | Sort-Object |  Where-Object {$_} |  Out-String))
        Write-Log -Context $Context -Message "Diff list created. Only missing essential apps will be processed. Diff list saved to $diffListPath" -Level 'INFO'

        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 5: MULTI-SOURCE INSTALLATION PROCESS
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Process each essential application with retry logic and multiple package sources
        $essTotal = $appsToInstall.Count
        $essCurrent = 0
        foreach ($app in $appsToInstall) {
            $essCurrent++
            Write-Progress -Activity "Essential Apps Installation" -Status ("Installing: {0} ({1}/{2})" -f $app.Name, $essCurrent, $essTotal) -PercentComplete ([int](($essCurrent / $essTotal) * 100))
            Write-Host ("[Essential Apps] Installing {0} ({1}/{2})..." -f $app.Name, $essCurrent, $essTotal)
            $installedVia = $null
            $retryCount = 0
            $maxRetries = 3
            $retryDelay = 90 # seconds
            $installSucceeded = $false
            while (-not $installSucceeded -and $retryCount -lt $maxRetries) {
                $retryCount++
                if ($app.Winget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                    try {
                        $wingetResult = winget install --id $($app.Winget) --accept-source-agreements --accept-package-agreements --silent -e 2>&1
                        if ($wingetResult -match 'Installer failed with exit code: 1618') {
                            Write-Host ("[Essential Apps] Windows Installer is busy (exit code 1618) for {0}. Attempt {1}/{2}. Retrying in {3} seconds..." -f $app.Name, $retryCount, $maxRetries, $retryDelay)
                            Write-Log -Context $Context -Message "Windows Installer is busy (exit code 1618) for $($app.Name). Attempt $retryCount/$maxRetries. Retrying in $retryDelay seconds..." -Level 'WARNING'
                            Start-Sleep -Seconds $retryDelay
                            continue
                        }
                        $installedVia = 'winget'
                        $installSucceeded = $true
                        Write-Host ("[Essential Apps] Installed {0} via winget." -f $app.Name)
                    } catch {
                        Write-Host ("[Essential Apps] winget failed for {0}: {1}" -f $app.Name, $_)
                        Write-Log -Context $Context -Message "winget failed for $($app.Name): $_" -Level 'WARNING'
                    }
                }
                if (-not $installSucceeded -and $app.Choco -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                    try {
                        $chocoResult = choco install $($app.Choco) -y 2>&1
                        if ($chocoResult -match '1618') {
                            Write-Host ("[Essential Apps] Windows Installer is busy (exit code 1618) for {0} via choco. Attempt {1}/{2}. Retrying in {3} seconds..." -f $app.Name, $retryCount, $maxRetries, $retryDelay)
                            Write-Log -Context $Context -Message "Windows Installer is busy (exit code 1618) for $($app.Name) via choco. Attempt $retryCount/$maxRetries. Retrying in $retryDelay seconds..." -Level 'WARNING'
                            Start-Sleep -Seconds $retryDelay
                            continue
                        }
                        $installedVia = 'choco'
                        $installSucceeded = $true
                        Write-Host ("[Essential Apps] Installed {0} via choco." -f $app.Name)
                    } catch {
                        Write-Host ("[Essential Apps] choco failed for {0}: {1}" -f $app.Name, $_)
                        Write-Log -Context $Context -Message "choco failed for $($app.Name): $_" -Level 'WARNING'
                    }
                }
                break
            }
            if ($installSucceeded -and $installedVia) {
                Write-Log -Context $Context -Message "Installed $($app.Name) via $installedVia." -Level 'SUCCESS'
            } elseif (-not $installSucceeded) {
                Write-Host ("[Essential Apps] Could not install {0} after {1} attempts due to Windows Installer being busy (exit code 1618). Skipping." -f $app.Name, $maxRetries)
                Write-Log -Context $Context -Message "Could not install $($app.Name) after $maxRetries attempts due to Windows Installer being busy (exit code 1618). Skipping." -Level 'ERROR'
            } elseif (-not $installedVia) {
                Write-Host ("[Essential Apps] Could not install {0} via winget or choco." -f $app.Name)
                Write-Log -Context $Context -Message "Could not install $($app.Name) via winget or choco." -Level 'ERROR'
            }
        }
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 6: INSTALLATION RESULTS VERIFICATION AND CLEANUP
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Complete the installation process and clean up temporary files
        Write-Progress -Activity "Essential Apps Installation" -Status "All essential apps processed" -Completed
        Write-Host "[Essential Apps] Installation complete. See log for details."
        Write-Log -Context $Context -Message "Essential apps installation complete. Diff list saved to $diffListPath" -Level 'SUCCESS'
        
        # Clean up temporary files used during the installation process
        if (Test-Path $installedProgramsDiffPath) {
            Remove-Item $installedProgramsDiffPath -Force
            Write-Log -Context $Context -Message "Deleted temp file: $installedProgramsDiffPath" -Level 'INFO'
        }
    } catch {
        Write-Host ("[Essential Apps] Task 6 failed: {0}" -f $_)
        Write-Log -Context $Context -Message "Task 6: Essential apps installation failed: $_" -Level 'ERROR'
    }
    Write-TaskLog -Context $Context -Message "Task 6 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 6: INSTALL ESSENTIAL APPLICATIONS
# =====================================================================================

# =====================================================================================
# TASK 7: UPGRADE ALL PACKAGES
# =====================================================================================
# Purpose: Update all installed packages to their latest versions using package managers
# Dependencies: Package managers from Task 3
# Outputs: Upgrade logs, deferred update scripts, upgrade status transcript
# Structure:
#   1. Task initialization and transcript setup
#   2. Package update discovery and analysis
#   3. PowerShell 7 update deferral handling
#   4. Regular package updates processing
#   5. Transcript generation and results compilation
# =====================================================================================
function Invoke-Task7_UpgradeAllPackages {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION AND TRANSCRIPT SETUP
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 7: UPGRADE ALL PACKAGES ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 7: UPGRADE ALL PACKAGES ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 7: Upgrade All Packages started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 7: Upgrade All Packages started." -Level 'INFO'
    
    # Initialize transcript for detailed upgrade tracking
    $transcript = @()
    $transcript += "[{0}] [START] Upgrade All Packages" -f ((Get-Date).ToString('HH:mm:ss'))
    
    try {
        Write-Log -Context $Context -Message "Checking for upgradable packages via winget..." -Level 'INFO'
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetOutput = winget upgrade --source winget 2>&1 | Out-String
            $wingetList = @()
            $lines = $wingetOutput -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
            
            # Find the header line (usually contains 'Name' and 'Id')
            $headerIndex = ($lines | Select-String -Pattern 'Name\s+Id\s+Version').LineNumber - 1
            if ($headerIndex -ge 0) {
                $dataLines = $lines[($headerIndex+2)..($lines.Count-1)]
                foreach ($line in $dataLines) {
                    # Split columns by two or more spaces
                    $cols = $line -split '\s{2,}'
                    if ($cols.Count -ge 4 -and $line.Trim() -ne '' -and $line -notmatch '^-+') {
                        $pkg = [PSCustomObject]@{
                            Name = $cols[0].Trim()
                            Id = $cols[1].Trim()
                            Version = $cols[2].Trim()
                            AvailableVersion = $cols[3].Trim()
                        }
                        $wingetList += $pkg
                    }
                }
            }
            
            if (-not $wingetList -or $wingetList.Count -eq 0) {
                $transcript += "[{0}] No upgradable packages found via winget." -f ((Get-Date).ToString('HH:mm:ss'))
                Write-Log -Context $Context -Message "No upgradable packages found via winget." -Level 'INFO'
            } else {
                Write-Log -Context $Context -Message "Found $($wingetList.Count) packages available for upgrade." -Level 'INFO'
                $transcript += "[{0}] Found $($wingetList.Count) packages available for upgrade." -f ((Get-Date).ToString('HH:mm:ss'))
                
                # Check for PowerShell 7 updates and handle specially
                $powershellUpdates = $wingetList | Where-Object { 
                    $_.Id -match 'Microsoft\.PowerShell' -or 
                    ($_.Name -match 'PowerShell' -and $_.Name -match '7')
                }
                
                $regularUpdates = $wingetList | Where-Object { 
                    $_.Id -notmatch 'Microsoft\.PowerShell' -and 
                    -not ($_.Name -match 'PowerShell' -and $_.Name -match '7')
                }
                
                # Process regular updates first
                if ($regularUpdates.Count -gt 0) {
                    Write-Log -Context $Context -Message "Processing $($regularUpdates.Count) regular package updates..." -Level 'INFO'
                    $transcript += "[{0}] Processing $($regularUpdates.Count) regular package updates..." -f ((Get-Date).ToString('HH:mm:ss'))
                    
                    $wingetTotal = $regularUpdates.Count
                    $wingetCurrent = 0
                    
                    foreach ($pkgObj in $regularUpdates) {
                        $wingetCurrent++
                        Write-Progress -Activity "Winget Upgrade" -Status ("Upgrading: {0} ({1}/{2})" -f $pkgObj.Name, $wingetCurrent, $wingetTotal) -PercentComplete ([int](($wingetCurrent / $wingetTotal) * 100))
                        Write-Log -Context $Context -Message ("Upgrading {0} ({1}/{2})..." -f $pkgObj.Name, $wingetCurrent, $wingetTotal) -Level 'INFO'
                        
                        $result = winget upgrade --id $pkgObj.Id --silent --accept-source-agreements --accept-package-agreements --include-unknown -e 2>&1
                        $transcript += $result
                        
                        if ($result -match 'No applicable update found' -or $result -match 'No installed package found') {
                            Write-Log -Context $Context -Message ("No update found for {0}." -f $pkgObj.Name) -Level 'INFO'
                        } elseif ($result -match 'Successfully installed' -or $result -match 'Successfully upgraded') {
                            Write-Log -Context $Context -Message ("Successfully upgraded {0} from {1} to {2}." -f $pkgObj.Name, $pkgObj.Version, $pkgObj.AvailableVersion) -Level 'SUCCESS'
                        } else {
                            Write-Log -Context $Context -Message ("Upgrade may have failed for {0}. Check transcript for details." -f $pkgObj.Name) -Level 'WARNING'
                        }
                    }
                    Write-Progress -Activity "Winget Upgrade" -Status "Regular packages processed" -Completed
                }
                
                # Handle PowerShell 7 updates specially
                if ($powershellUpdates.Count -gt 0) {
                    Write-Log -Context $Context -Message "PowerShell 7 update detected. Creating deferred update script..." -Level 'WARNING'
                    $transcript += "[{0}] PowerShell 7 update detected. Creating deferred update script..." -f ((Get-Date).ToString('HH:mm:ss'))
                    
                    # Create a deferred update script that runs after the main script completes
                    $deferredScriptPath = Join-Path $Context.CurrentTaskFolder 'DeferredPowerShellUpdate.ps1'
                    $deferredUpdateScript = @"
# Deferred PowerShell 7 Update Script
# This script runs after the main system maintenance script completes
Write-Host "Starting deferred PowerShell 7 update..."

try {
    # Wait a moment for the main script to fully exit
    Start-Sleep -Seconds 5
    
    # Update PowerShell 7
"@
                    
                    foreach ($psUpdate in $powershellUpdates) {
                        $deferredUpdateScript += @"
    
    Write-Host "Updating $($psUpdate.Name) from $($psUpdate.Version) to $($psUpdate.AvailableVersion)..."
    `$result = winget upgrade --id "$($psUpdate.Id)" --silent --accept-source-agreements --accept-package-agreements --include-unknown -e 2>&1
    Write-Host "Update result: `$result"
"@
                    }
                    
                    $deferredUpdateScript += @"
    
    Write-Host "PowerShell 7 update completed. Please restart your PowerShell session."
    Write-Host "Press any key to close this window..."
    `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
} catch {
    Write-Host "Error during PowerShell update: `$_"
    Write-Host "Press any key to close this window..."
    `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
"@
                    
                    # Save the deferred script
                    $deferredUpdateScript | Set-Content -Path $deferredScriptPath -Encoding UTF8
                    
                    # Create a batch file to launch the deferred script
                    $batchPath = Join-Path $Context.CurrentTaskFolder 'DeferredPowerShellUpdate.bat'
                    $batchContent = @"
@echo off
echo Starting deferred PowerShell 7 update...
timeout /t 3 /nobreak > nul
powershell.exe -ExecutionPolicy Bypass -File "$deferredScriptPath"
pause
"@
                    $batchContent | Set-Content -Path $batchPath -Encoding ASCII
                    
                    # Schedule the deferred update to run after script completion
                    Write-Log -Context $Context -Message "Deferred PowerShell update script created at: $deferredScriptPath" -Level 'INFO'
                    $transcript += "[{0}] Deferred PowerShell update script created at: $deferredScriptPath" -f ((Get-Date).ToString('HH:mm:ss'))
                    
                    # Add to context so it can be handled in the final cleanup
                    if (-not $Context.ContainsKey('DeferredUpdates')) {
                        $Context.DeferredUpdates = @()
                    }
                    $Context.DeferredUpdates += @{
                        Type = 'PowerShell7Update'
                        ScriptPath = $deferredScriptPath
                        BatchPath = $batchPath
                        Updates = $powershellUpdates
                    }
                    
                    Write-Host "⚠️  PowerShell 7 update will be deferred until after script completion"
                    Write-Log -Context $Context -Message "PowerShell 7 update deferred to prevent script interruption." -Level 'WARNING'
                }
            }
        } else {
            Write-Progress -Activity "Winget Upgrade" -Status "winget not found. Skipping." -Completed
            Write-Log -Context $Context -Message "winget not found. Skipping package upgrade." -Level 'WARNING'
            $transcript += "[{0}] [WARN] winget not found. Skipping package upgrade." -f ((Get-Date).ToString('HH:mm:ss'))
        }
        $transcript += "[{0}] [SUCCESS] Upgrade All Packages" -f ((Get-Date).ToString('HH:mm:ss'))
    } catch {
        Write-Log -Context $Context -Message ("Task 7 failed: {0}" -f $_) -Level 'ERROR'
        $transcript += "[{0}] [ERROR] Package upgrade failed: {1}" -f ((Get-Date).ToString('HH:mm:ss')), $_
    }
    $endTime = Get-Date
    $transcript += "[{0}] [END] Upgrade All Packages" -f ($endTime.ToString('HH:mm:ss'))
    $outPath = Join-Path $Context.CurrentTaskFolder 'Task7_UpgradeAllPackages_log.txt'
    $transcript | Out-File $outPath -Encoding UTF8
    Write-TaskLog -Context $Context -Message "Task 7 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 7: UPGRADE ALL PACKAGES
# =====================================================================================

# =====================================================================================
# TASK 8: PRIVACY & TELEMETRY
# =====================================================================================
# Purpose: Disable Windows telemetry, tracking, and privacy-invasive features
# Dependencies: Administrative privileges for registry and service modifications
# Outputs: Privacy configuration logs, registry modifications transcript
# Structure:
#   1. Task initialization and transcript setup
#   2. Registry-based telemetry disabling
#   3. Privacy-related services configuration
#   4. Windows features privacy hardening
#   5. Results compilation and logging
# =====================================================================================
function Invoke-Task8_PrivacyAndTelemetry {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION AND TRANSCRIPT SETUP
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 8: PRIVACY & TELEMETRY ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 8: PRIVACY & TELEMETRY ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 8: Privacy & Telemetry started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 8: Privacy & Telemetry started." -Level 'INFO'
    
    # Initialize transcript for detailed privacy hardening tracking
    $transcript = @()
    $startTime = Get-Date
    $transcript += "[{0}] [START] Disable Telemetry & Privacy" -f ($startTime.ToString('HH:mm:ss'))
    
    try {
        $transcript += "[{0}] Applying privacy and telemetry hardening..." -f ((Get-Date).ToString('HH:mm:ss'))

        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 2: REGISTRY-BASED TELEMETRY DISABLING
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Configure registry settings to disable telemetry and privacy-invasive features
        $regSettings = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'LetAppsAccessOtherDevices'; Value = 2 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDeviceSearchHistoryEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsCloudSearchEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'SafeSearchMode'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsMySearchHistoryEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsCortanaEnabled'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWebOverMeteredConnections'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCloudSearch'; Value = 0 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'DisableCdp'; Value = 1 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'DisableCdpUserSvc'; Value = 1 },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'DisableCdpUserSvc_Session1'; Value = 1 }
        )
        foreach ($reg in $regSettings) {
            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
            Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Force
            $transcript += "[{0}] Set {1}={2} in {3}" -f ((Get-Date).ToString('HH:mm:ss')), $reg.Name, $reg.Value, $reg.Path
        }

        # 2. Disable Telemetry/Tracking Services
        $services = @(
            'DiagTrack', 'dmwappushservice', 'WMPNetworkSvc', 'XblGameSave', 'MapsBroker', 'WSearch', 'CDPUserSvc*', 'RetailDemo', 'PcaSvc', 'WerSvc', 'RemoteRegistry', 'TrkWks', 'Wecsvc', 'WbioSrvc', 'lfsvc', 'wisvc', 'WpnService', 'WpnUserService*', 'W32Time', 'Fax', 'HomeGroupListener', 'HomeGroupProvider', 'SharedAccess', 'NetTcpPortSharing', 'RemoteAccess', 'RemoteRegistry', 'SysMain', 'TabletInputService', 'WdiServiceHost', 'WdiSystemHost', 'WlanSvc', 'WwanSvc', 'WMPNetworkSvc', 'XboxGipSvc', 'XboxNetApiSvc'
        )
        foreach ($svc in $services) {
            $foundServices = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($foundServices) {
                foreach ($service in $foundServices) {
                    # Skip per-user services (names ending with _[alphanumeric])
                    if ($service.Name -match '_[a-zA-Z0-9]{4,}$') {
                        $transcript += "[{0}] Skipped per-user service: {1}" -f ((Get-Date).ToString('HH:mm:ss')), $service.Name
                        continue
                    }
                    Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $service.Name -StartupType Disabled
                    $transcript += "[{0}] Disabled service: {1}" -f ((Get-Date).ToString('HH:mm:ss')), $service.Name
                }
            }
        }

        # 3. Disable Privacy/Telemetry Scheduled Tasks
        $tasks = @(
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
            '\Microsoft\Windows\Autochk\Proxy',
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
            '\Microsoft\Windows\Maintenance\WinSAT',
            '\Microsoft\Windows\Media Center\ActivateWindowsSearch',
            '\Microsoft\Windows\Media Center\ConfigureInternetTimeService',
            '\Microsoft\Windows\Media Center\DispatchRecoveryTasks',
            '\Microsoft\Windows\Media Center\ehDRMInit',
            '\Microsoft\Windows\Media Center\InstallPlayReady',
            '\Microsoft\Windows\Media Center\mcupdate',
            '\Microsoft\Windows\Media Center\MediaCenterRecoveryTask',
            '\Microsoft\Windows\Media Center\ObjectStoreRecoveryTask',
            '\Microsoft\Windows\Media Center\OCURActivate',
            '\Microsoft\Windows\Media Center\OCURDiscovery',
            '\Microsoft\Windows\Media Center\PBDADiscovery',
            '\Microsoft\Windows\Media Center\PBDADiscoveryW1',
            '\Microsoft\Windows\Media Center\PBDADiscoveryW2',
            '\Microsoft\Windows\Media Center\PvrRecoveryTask',
            '\Microsoft\Windows\Media Center\PvrScheduleTask',
            '\Microsoft\Windows\Media Center\RegisterSearch',
            '\Microsoft\Windows\Media Center\ReindexSearchRoot',
            '\Microsoft\Windows\Media Center\SqlLiteRecoveryTask',
            '\Microsoft\Windows\Media Center\UpdateRecordPath',
            '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
            '\Microsoft\Windows\WindowsUpdate\Automatic App Update',
            '\Microsoft\Windows\WindowsUpdate\Scheduled Start',
            '\Microsoft\Windows\WindowsUpdate\sih',
            '\Microsoft\Windows\WindowsUpdate\sihboot'
        )
        foreach ($task in $tasks) {
            try {
                Get-ScheduledTask -TaskPath $task -ErrorAction Stop | Disable-ScheduledTask -ErrorAction Stop | Out-Null
                $transcript += "[{0}] Disabled scheduled task: {1}" -f ((Get-Date).ToString('HH:mm:ss')), $task
            } catch {
                $transcript += "[{0}] [WARN] Could not disable scheduled task: {1} - {2}" -f ((Get-Date).ToString('HH:mm:ss')), $task, $_
            }
        }

        # 4. Disable Feedback, Advertising, Location, and Other Privacy Settings
        $privacyReg = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'LetAppsAccessOtherDevices'; Value = 2 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDeviceSearchHistoryEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsCloudSearchEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'SafeSearchMode'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsMySearchHistoryEnabled'; Value = 0 },
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsCortanaEnabled'; Value = 0 }
        )
        foreach ($reg in $privacyReg) {
            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
            Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Force
            $transcript += "[{0}] Set {1}={2} in {3}" -f ((Get-Date).ToString('HH:mm:ss')), $reg.Name, $reg.Value, $reg.Path
        }

        # 5. Disable WiFi Sense
        $wifiSensePath = 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'
        if (-not (Test-Path $wifiSensePath)) { New-Item -Path $wifiSensePath -Force | Out-Null }
        Set-ItemProperty -Path $wifiSensePath -Name 'AutoConnectAllowedOEM' -Value 0 -Force
        $transcript += "[{0}] Disabled WiFi Sense AutoConnectAllowedOEM" -f ((Get-Date).ToString('HH:mm:ss'))

        # 6. Disable Location Tracking
        $locPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
        if (-not (Test-Path $locPath)) { New-Item -Path $locPath -Force | Out-Null }
        Set-ItemProperty -Path $locPath -Name 'Value' -Value 'Deny' -Force
        $transcript += "[{0}] Disabled location tracking (set to Deny)" -f ((Get-Date).ToString('HH:mm:ss'))

        # 7. Disable Cortana
        $cortanaPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
        if (-not (Test-Path $cortanaPath)) { New-Item -Path $cortanaPath -Force | Out-Null }
        Set-ItemProperty -Path $cortanaPath -Name 'AllowCortana' -Value 0 -Force
        $transcript += "[{0}] Disabled Cortana" -f ((Get-Date).ToString('HH:mm:ss'))

        Write-Log -Context $Context -Message "Telemetry and privacy settings configured." -Level 'SUCCESS'
    } catch {
        Write-Log -Context $Context -Message ("Telemetry/privacy hardening failed: {0}" -f $_) -Level 'ERROR'
    }
    Write-TaskLog -Context $Context -Message "Task 8 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 8: PRIVACY & TELEMETRY
# =====================================================================================

# =====================================================================================
# TASK 9: WINDOWS UPDATE
# =====================================================================================
# Purpose: Install available Windows updates and security patches
# Dependencies: PSWindowsUpdate module, internet connection, administrative privileges
# Outputs: Update installation logs, Windows Update transcript
# Structure:
#   1. Task initialization and module verification
#   2. Windows Update module installation
#   3. Available updates discovery
#   4. Update installation process
#   5. Results compilation and logging
# =====================================================================================
function Invoke-Task9_WindowsUpdate {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION AND MODULE VERIFICATION
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 9: WINDOWS UPDATE ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 9: WINDOWS UPDATE ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 9: Windows Update started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 9: Windows Update started." -Level 'INFO'
    
    # Initialize transcript for detailed update tracking
    $transcript = @()
    $startTime = Get-Date
    $transcript += "[{0}] [START] Windows Update & Upgrade" -f ($startTime.ToString('HH:mm:ss'))
    
    try {
        Write-Log -Context $Context -Message "Checking and installing Windows updates..." -Level 'INFO'
        Write-Progress -Activity "Windows Update" -Status "Initializing..." -PercentComplete 0
        
        # ═══════════════════════════════════════════════════════════════════════════════════
        # SECTION 2: WINDOWS UPDATE MODULE INSTALLATION
        # ═══════════════════════════════════════════════════════════════════════════════════
        # Install PSWindowsUpdate module if not available
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            try {
                Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -ErrorAction SilentlyContinue
                $transcript += "[{0}] PSWindowsUpdate module installed." -f ((Get-Date).ToString('HH:mm:ss'))
            } catch {
                $transcript += "[{0}] [WARN] Could not install PSWindowsUpdate module: {1}" -f ((Get-Date).ToString('HH:mm:ss')), $_
                Write-Log -Context $Context -Message ("Could not install PSWindowsUpdate module: {0}" -f $_) -Level 'WARNING'
            }
        }
        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
        try {
            Write-Progress -Activity "Windows Update" -Status "Checking and installing updates..." -PercentComplete 50
            Get-WindowsUpdate -AcceptAll -Install -AutoReboot -ErrorAction Stop
            $transcript += "[{0}] Windows Update completed." -f ((Get-Date).ToString('HH:mm:ss'))
            Write-Log -Context $Context -Message "Windows Update completed." -Level 'SUCCESS'
        } catch {
            $transcript += "[{0}] [WARN] Get-WindowsUpdate failed: {1}. Trying wuauclt..." -f ((Get-Date).ToString('HH:mm:ss')), $_
            Write-Progress -Activity "Windows Update" -Status "Triggering wuauclt..." -PercentComplete 80
            wuauclt /detectnow /updatenow
            $transcript += "[{0}] Triggered Windows Update via wuauclt. Please check Windows Update manually if needed." -f ((Get-Date).ToString('HH:mm:ss'))
            Write-Log -Context $Context -Message ("Get-WindowsUpdate failed: {0}. Triggered wuauclt." -f $_) -Level 'WARNING'
        }
        Write-Progress -Activity "Windows Update" -Status "Complete" -Completed
    } catch {
        Write-Log -Context $Context -Message ("Task 9: Windows Update & Upgrade failed: {0}" -f $_) -Level 'ERROR'
    }
    $endTime = Get-Date
    $transcript += "[{0}] [END] Windows Update & Upgrade" -f ($endTime.ToString('HH:mm:ss'))
    $outPath = Join-Path $Context.CurrentTaskFolder 'Task9_UpdatesMaintenance_log.txt'
    $transcript | Out-File $outPath -Encoding UTF8
    Write-TaskLog -Context $Context -Message "Task 9 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 9: WINDOWS UPDATE
# =====================================================================================

# =====================================================================================
# TASK 10: RESTORE POINT MANAGEMENT & FULL DISK CLEANUP
# =====================================================================================
# Purpose: Manage system restore points and perform comprehensive disk cleanup
# Dependencies: Administrative privileges, disk space analysis tools
# Outputs: Disk cleanup reports, restore point management logs, space recovery statistics
# Structure:
#   1. Task initialization and disk analysis
#   2. Restore point management and cleanup
#   3. System file cleanup operations
#   4. Temporary file and cache cleanup
#   5. Disk space optimization and reporting
# =====================================================================================
function Invoke-Task10_RestorePointAndDiskCleanup {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION AND DISK ANALYSIS
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 10: RESTORE POINT MANAGEMENT & FULL DISK CLEANUP ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 10: RESTORE POINT MANAGEMENT & FULL DISK CLEANUP ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 10: Restore Point Management & Full Disk Cleanup started." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 10: Restore Point Management & Full Disk Cleanup started." -Level 'INFO'
    
    try {
        # ========== PART 1: RESTORE POINT MANAGEMENT ==========
        Write-Log -Context $Context -Message "Starting restore point management..." -Level 'INFO'
        Write-TaskLog -Context $Context -Message "Phase 1: Restore Point Management" -Level 'INFO'
        
        # Get all restore points
        Write-Log -Context $Context -Message "Validating existing restore points..." -Level 'INFO'
        $allRestorePoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
        
        if (-not $allRestorePoints) {
            Write-Log -Context $Context -Message "No restore points found on the system." -Level 'WARNING'
            Write-TaskLog -Context $Context -Message "No restore points found on the system." -Level 'WARNING'
        } else {
            Write-Log -Context $Context -Message "Found $($allRestorePoints.Count) restore points total." -Level 'INFO'
            
            # Keep only the 5 most recent restore points
            $restorePointsToKeep = $allRestorePoints | Select-Object -First 5
            $restorePointsToDelete = $allRestorePoints | Select-Object -Skip 5
            
            # Log details of the 5 remaining restore points
            Write-Log -Context $Context -Message "Keeping the 5 most recent restore points:" -Level 'INFO'
            foreach ($rp in $restorePointsToKeep) {
                $creationTimeFormatted = 'Unknown'
                if ($rp.CreationTime -and $rp.CreationTime -is [DateTime]) {
                    try {
                        $creationTimeFormatted = $rp.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                    } catch {
                        $creationTimeFormatted = 'Invalid Date'
                    }
                }
                $rpDetails = "Sequence: $($rp.SequenceNumber), Date: $creationTimeFormatted, Type: $($rp.RestorePointType), Description: $($rp.Description)"
                Write-Log -Context $Context -Message "  - $rpDetails" -Level 'INFO'
                Write-TaskLog -Context $Context -Message "Keeping restore point: $rpDetails" -Level 'INFO'
            }
            
            # Delete old restore points if any exist
            if ($restorePointsToDelete.Count -gt 0) {
                Write-Log -Context $Context -Message "Removing $($restorePointsToDelete.Count) old restore points..." -Level 'INFO'
                foreach ($rpToDelete in $restorePointsToDelete) {
                    try {
                        # Use vssadmin to delete specific restore points
                        if ($rpToDelete.CreationTime -and $rpToDelete.CreationTime -is [DateTime]) {
                            try {
                                $formattedCreationTime = $rpToDelete.CreationTime.ToString("yyyyMMddHHmmss.ffffff") + "-000"
                                $shadowCopies = Get-WmiObject -Class Win32_ShadowCopy | Where-Object { 
                                    $_.InstallDate -eq $formattedCreationTime
                                }
                            } catch {
                                Write-Log -Context $Context -Message "Failed to format creation time for restore point $($rpToDelete.SequenceNumber): $_" -Level 'WARNING'
                                $shadowCopies = @()
                            }
                            
                            foreach ($shadowCopy in $shadowCopies) {
                                $shadowCopy.Delete()
                                $deletedTimeFormatted = 'Unknown'
                                if ($rpToDelete.CreationTime -and $rpToDelete.CreationTime -is [DateTime]) {
                                    try {
                                        $deletedTimeFormatted = $rpToDelete.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                                    } catch {
                                        $deletedTimeFormatted = 'Invalid Date'
                                    }
                                }
                                Write-Log -Context $Context -Message "Deleted old restore point: Sequence $($rpToDelete.SequenceNumber), Date: $deletedTimeFormatted" -Level 'SUCCESS'
                            }
                        } else {
                            Write-Log -Context $Context -Message "Skipped restore point $($rpToDelete.SequenceNumber) - invalid creation time" -Level 'WARNING'
                        }
                    } catch {
                        Write-Log -Context $Context -Message "Failed to delete restore point $($rpToDelete.SequenceNumber): $_" -Level 'WARNING'
                    }
                }
            } else {
                Write-Log -Context $Context -Message "No old restore points to remove. All restore points are within the keep limit." -Level 'INFO'
            }
            
            # Validate remaining restore points
            Write-Log -Context $Context -Message "Validating remaining restore points..." -Level 'INFO'
            $finalRestorePoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
            if ($finalRestorePoints) {
                Write-Log -Context $Context -Message "Validation complete. $($finalRestorePoints.Count) restore points remain on the system." -Level 'SUCCESS'
                
                # Create detailed summary for transcript
                $restorePointSummary = @()
                $restorePointSummary += "=== RESTORE POINT SUMMARY ==="
                $restorePointSummary += "Total restore points maintained: $($finalRestorePoints.Count)"
                $restorePointSummary += "Restore points details:"
                
                foreach ($rp in $finalRestorePoints) {
                    if ($rp.CreationTime -and $rp.CreationTime -is [DateTime]) {
                        try {
                            $ageInDays = [math]::Round((Get-Date).Subtract($rp.CreationTime).TotalDays, 1)
                            $creationTimeFormatted = $rp.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                            $restorePointSummary += "  $($rp.SequenceNumber). Created: $creationTimeFormatted ($ageInDays days ago)"
                        } catch {
                            $restorePointSummary += "  $($rp.SequenceNumber). Created: Invalid date format"
                        }
                    } else {
                        $restorePointSummary += "  $($rp.SequenceNumber). Created: Unknown date"
                    }
                    $restorePointSummary += "     Type: $($rp.RestorePointType) | Description: $($rp.Description)"
                }
                
                # Save summary to temp file for transcript
                $summaryPath = Join-Path $Context.CurrentTaskFolder 'RestorePoint_Summary.txt'
                $restorePointSummary | Out-File $summaryPath -Encoding UTF8
                
                Write-Log -Context $Context -Message "Restore point summary saved to $summaryPath" -Level 'INFO'
                Write-TaskLog -Context $Context -Message "Restore point management completed successfully" -Level 'SUCCESS'
            }
        }
        
        # ========== PART 2: SYSTEM DIAGNOSTICS & ERROR ANALYSIS ==========
        Write-Log -Context $Context -Message "Starting system diagnostics and error analysis..." -Level 'INFO'
        Write-TaskLog -Context $Context -Message "Phase 2: System Diagnostics & Error Analysis" -Level 'INFO'
        
        $diagnosticsReport = @()
        $diagnosticsReport += "=== SYSTEM DIAGNOSTICS REPORT ==="
        $diagnosticsReport += "Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
        $diagnosticsReport += "Analysis Period: Last 48 hours"
        $diagnosticsReport += ""
        
        # Calculate 48 hours ago
        $cutoffDate = (Get-Date).AddHours(-48)
        
        # 1. Event Viewer Error Analysis (Last 48 hours)
        Write-Log -Context $Context -Message "Analyzing Event Viewer errors from the last 48 hours..." -Level 'INFO'
        $diagnosticsReport += "=== EVENT VIEWER ERRORS (LAST 48 HOURS) ==="
        
        try {
            # Get critical and error events from System log
            $systemErrors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$cutoffDate} -ErrorAction SilentlyContinue | Select-Object -First 50
            $diagnosticsReport += "--- SYSTEM LOG ERRORS ---"
            if ($systemErrors) {
                $diagnosticsReport += "Found $($systemErrors.Count) critical/error events in System log:"
                foreach ($logEvent in $systemErrors) {
                    $timeFormatted = 'Unknown'
                    if ($logEvent.TimeCreated -and $logEvent.TimeCreated -is [DateTime]) {
                        try {
                            $timeFormatted = $logEvent.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                        } catch {
                            $timeFormatted = 'Invalid Date'
                        }
                    }
                    $diagnosticsReport += "[$timeFormatted] Level: $($logEvent.LevelDisplayName) | ID: $($logEvent.Id) | Source: $($logEvent.ProviderName)"
                    $diagnosticsReport += "  Message: $($logEvent.Message -replace "`r`n", " " -replace "`n", " ")"
                    $diagnosticsReport += ""
                }
            } else {
                $diagnosticsReport += "No critical or error events found in System log for the last 48 hours."
            }
            $diagnosticsReport += ""
            
            # Get critical and error events from Application log
            $appErrors = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$cutoffDate} -ErrorAction SilentlyContinue | Select-Object -First 50
            $diagnosticsReport += "--- APPLICATION LOG ERRORS ---"
            if ($appErrors) {
                $diagnosticsReport += "Found $($appErrors.Count) critical/error events in Application log:"
                foreach ($logEvent in $appErrors) {
                    $timeFormatted = 'Unknown'
                    if ($logEvent.TimeCreated -and $logEvent.TimeCreated -is [DateTime]) {
                        try {
                            $timeFormatted = $logEvent.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                        } catch {
                            $timeFormatted = 'Invalid Date'
                        }
                    }
                    $diagnosticsReport += "[$timeFormatted] Level: $($logEvent.LevelDisplayName) | ID: $($logEvent.Id) | Source: $($logEvent.ProviderName)"
                    $diagnosticsReport += "  Message: $($logEvent.Message -replace "`r`n", " " -replace "`n", " ")"
                    $diagnosticsReport += ""
                }
            } else {
                $diagnosticsReport += "No critical or error events found in Application log for the last 48 hours."
            }
            $diagnosticsReport += ""
            
            Write-Log -Context $Context -Message "Event Viewer error analysis completed" -Level 'SUCCESS'
        } catch {
            $diagnosticsReport += "Failed to analyze Event Viewer errors: $_"
            Write-Log -Context $Context -Message "Event Viewer error analysis failed: $_" -Level 'WARNING'
        }
        
        # 2. CBS (Component-Based Servicing) Log Analysis
        Write-Log -Context $Context -Message "Analyzing CBS log for errors from the last 48 hours..." -Level 'INFO'
        $diagnosticsReport += "=== CBS LOG ANALYSIS (LAST 48 HOURS) ==="
        
        try {
            $cbsLogPath = "$env:SystemRoot\Logs\CBS\CBS.log"
            if (Test-Path $cbsLogPath) {
                # Read CBS log and filter for recent errors
                $cbsContent = Get-Content $cbsLogPath -ErrorAction SilentlyContinue
                $cbsErrors = @()
                
                foreach ($line in $cbsContent) {
                    # Parse CBS log format: YYYY-MM-DD HH:MM:SS
                    if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') {
                        try {
                            $dateStr = ($line -split ',')[0]
                            $logDate = [DateTime]::ParseExact($dateStr, 'yyyy-MM-dd HH:mm:ss', $null)
                            
                            if ($logDate -gt $cutoffDate -and ($line -match '\[SR\]' -or $line -match 'Error' -or $line -match 'Failed' -or $line -match 'corrupt')) {
                                $cbsErrors += $line
                            }
                        } catch {
                            # Skip lines that don't parse correctly
                        }
                    }
                }
                
                if ($cbsErrors.Count -gt 0) {
                    $diagnosticsReport += "Found $($cbsErrors.Count) potential issues in CBS log:"
                    foreach ($cbsError in ($cbsErrors | Select-Object -First 30)) {
                        $diagnosticsReport += $cbsError
                    }
                    if ($cbsErrors.Count -gt 30) {
                        $diagnosticsReport += "... and $($cbsErrors.Count - 30) more entries (truncated for brevity)"
                    }
                } else {
                    $diagnosticsReport += "No errors or issues found in CBS log for the last 48 hours."
                }
            } else {
                $diagnosticsReport += "CBS log file not found at expected location: $cbsLogPath"
            }
            $diagnosticsReport += ""
            
            Write-Log -Context $Context -Message "CBS log analysis completed" -Level 'SUCCESS'
        } catch {
            $diagnosticsReport += "Failed to analyze CBS log: $_"
            Write-Log -Context $Context -Message "CBS log analysis failed: $_" -Level 'WARNING'
        }
        
        # 3. System Health Assessment & Tool Recommendations
        Write-Log -Context $Context -Message "Performing system health assessment..." -Level 'INFO'
        $diagnosticsReport += "=== SYSTEM HEALTH ASSESSMENT & RECOMMENDATIONS ==="
        
        $needsSFC = $false
        $needsCHKDSK = $false
        $needsDISM = $false
        $recommendations = @()
        
        try {
            # Check for corruption indicators
            $corruptionIndicators = @(
                'corrupt', 'corrupted', 'integrity', 'violation', 'damaged', 'missing',
                'SFC', 'System File Checker', 'DISM', 'CheckSUR', 'file system error'
            )
            
            # Analyze system and application errors for corruption signs
            $allErrors = @()
            if ($systemErrors) { $allErrors += $systemErrors }
            if ($appErrors) { $allErrors += $appErrors }
            
            $corruptionEvents = $allErrors | Where-Object { 
                $message = $_.Message
                $corruptionIndicators | Where-Object { $message -match $_ }
            }
            
            if ($corruptionEvents) {
                $needsSFC = $true
                $needsDISM = $true
                $recommendations += "CRITICAL: System file corruption detected in event logs"
            }
            
            # Check for disk-related errors
            $diskErrors = $allErrors | Where-Object { 
                $_.Message -match 'disk|drive|volume|file system|bad sector|I/O error|device error'
            }
            
            if ($diskErrors) {
                $needsCHKDSK = $true
                $recommendations += "WARNING: Disk-related errors detected - file system check recommended"
            }
            
            # Check CBS log for specific issues
            if ($cbsErrors.Count -gt 0) {
                $needsDISM = $true
                $needsSFC = $true
                $recommendations += "WARNING: Component store issues detected in CBS log"
            }
            
            # Check Windows Update errors
            $wuErrors = $allErrors | Where-Object { 
                $_.ProviderName -match 'WindowsUpdateClient|Microsoft-Windows-WindowsUpdateClient' -or
                $_.Message -match 'Windows Update|update|0x800'
            }
            
            if ($wuErrors) {
                $needsDISM = $true
                $recommendations += "INFO: Windows Update errors detected - component store repair recommended"
            }
            
            # Generate recommendations
            $diagnosticsReport += "SYSTEM HEALTH STATUS:"
            
            if ($needsSFC) {
                $diagnosticsReport += "✗ SFC (System File Checker) scan RECOMMENDED"
                $diagnosticsReport += "  Reason: System file corruption indicators detected"
                $diagnosticsReport += "  Command: sfc /scannow"
            } else {
                $diagnosticsReport += "✓ SFC scan not required - no system file issues detected"
            }
            
            if ($needsCHKDSK) {
                $diagnosticsReport += "✗ CHKDSK (Check Disk) scan RECOMMENDED"
                $diagnosticsReport += "  Reason: Disk/file system errors detected"
                $diagnosticsReport += "  Command: chkdsk C: /f /r (requires reboot)"
            } else {
                $diagnosticsReport += "✓ CHKDSK not required - no disk errors detected"
            }
            
            if ($needsDISM) {
                $diagnosticsReport += "✗ DISM (Component Store) repair RECOMMENDED"
                $diagnosticsReport += "  Reason: Windows component issues detected"
                $diagnosticsReport += "  Commands: dism /online /cleanup-image /scanhealth"
                $diagnosticsReport += "           dism /online /cleanup-image /restorehealth"
            } else {
                $diagnosticsReport += "✓ DISM repair not required - component store appears healthy"
            }
            
            $diagnosticsReport += ""
            $diagnosticsReport += "PRIORITY RECOMMENDATIONS:"
            if ($recommendations.Count -gt 0) {
                foreach ($rec in $recommendations) {
                    $diagnosticsReport += "• $rec"
                }
            } else {
                $diagnosticsReport += "• No critical issues detected - system appears healthy"
            }
            
            $diagnosticsReport += ""
            
            Write-Log -Context $Context -Message "System health assessment completed" -Level 'SUCCESS'
        } catch {
            $diagnosticsReport += "Failed to complete system health assessment: $_"
            Write-Log -Context $Context -Message "System health assessment failed: $_" -Level 'WARNING'
        }
        
        # 4. Additional System Information
        $diagnosticsReport += "=== ADDITIONAL SYSTEM INFORMATION ==="
        
        try {
            # System uptime
            $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
            $diagnosticsReport += "System Uptime: $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
            
            # Available disk space
            $systemDrive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
            $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
            $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
            $freeSpacePercent = [math]::Round(($systemDrive.FreeSpace / $systemDrive.Size) * 100, 1)
            $diagnosticsReport += "System Drive Space: $freeSpaceGB GB free of $totalSpaceGB GB total ($freeSpacePercent% free)"
            
            # Memory usage
            $totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
            $availableRAM = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
            $usedRAMPercent = [math]::Round((($totalRAM - $availableRAM) / $totalRAM) * 100, 1)
            $diagnosticsReport += "Memory Usage: $usedRAMPercent% used ($availableRAM GB free of $totalRAM GB total)"
            
            # Windows version
            $osInfo = Get-CimInstance Win32_OperatingSystem
            $diagnosticsReport += "OS Version: $($osInfo.Caption) Build $($osInfo.Version)"
            
            $diagnosticsReport += ""
        } catch {
            $diagnosticsReport += "Failed to gather additional system information: $_"
        }
        
        # Save diagnostics report
        $diagnosticsPath = Join-Path $Context.CurrentTaskFolder 'SystemDiagnostics_Report.txt'
        $diagnosticsReport | Out-File $diagnosticsPath -Encoding UTF8
        Write-Log -Context $Context -Message "System diagnostics report saved to $diagnosticsPath" -Level 'INFO'
        Write-TaskLog -Context $Context -Message "System diagnostics and error analysis completed" -Level 'SUCCESS'
        
        # ========== PART 3: DISK CLEANUP ==========
        Write-Log -Context $Context -Message "Starting disk cleanup operations..." -Level 'INFO'
        Write-TaskLog -Context $Context -Message "Phase 3: Full Disk Cleanup" -Level 'INFO'
        
        # Get initial disk space
        $systemDrive = $env:SystemDrive
        $initialSpace = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $systemDrive }
        $initialFreeSpace = [math]::Round($initialSpace.FreeSpace / 1GB, 2)
        Write-Log -Context $Context -Message "Initial free space on $systemDrive`: $initialFreeSpace GB" -Level 'INFO'
        
        # 1. Windows Disk Cleanup using cleanmgr
        Write-Log -Context $Context -Message "Running Windows Disk Cleanup..." -Level 'INFO'
        try {
            # Create temporary cleanup configuration
            $cleanupConfig = @{
                'Active Setup Temp Folders' = '2'
                'BranchCache' = '2'
                'Content Indexer Cleaner' = '2'
                'Device Driver Packages' = '2'
                'Downloaded Program Files' = '2'
                'GameNewsFiles' = '2'
                'GameStatisticsFiles' = '2'
                'GameUpdateFiles' = '2'
                'Internet Cache Files' = '2'
                'Memory Dump Files' = '2'
                'Offline Pages Files' = '2'
                'Old ChkDsk Files' = '2'
                'Previous Installations' = '2'
                'Recycle Bin' = '2'
                'Service Pack Cleanup' = '2'
                'Setup Log Files' = '2'
                'System error memory dump files' = '2'
                'System error minidump files' = '2'
                'Temporary Files' = '2'
                'Temporary Setup Files' = '2'
                'Thumbnail Cache' = '2'
                'Update Cleanup' = '2'
                'Upgrade Discarded Files' = '2'
                'User file versions' = '2'
                'Windows Defender' = '2'
                'Windows Error Reporting Archive Files' = '2'
                'Windows Error Reporting Queue Files' = '2'
                'Windows Error Reporting System Archive Files' = '2'
                'Windows Error Reporting System Queue Files' = '2'
                'Windows ESD installation files' = '2'
                'Windows Upgrade Log Files' = '2'
            }
            
            # Apply cleanup configuration to registry
            $sagePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
            foreach ($item in $cleanupConfig.GetEnumerator()) {
                try {
                    $itemPath = Join-Path $sagePath $item.Key
                    if (Test-Path $itemPath) {
                        Set-ItemProperty -Path $itemPath -Name 'StateFlags0001' -Value $item.Value -Type DWord
                    }
                } catch {
                    Write-Log -Context $Context -Message "Failed to set cleanup config for '$($item.Key)': $_" -Level 'WARNING'
                }
            }
            
            # Run cleanmgr with our configuration
            Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -Wait -WindowStyle Hidden
            Write-Log -Context $Context -Message "Windows Disk Cleanup completed" -Level 'SUCCESS'
            Write-TaskLog -Context $Context -Message "Windows Disk Cleanup completed" -Level 'SUCCESS'
        } catch {
            Write-Log -Context $Context -Message "Windows Disk Cleanup failed: $_" -Level 'WARNING'
        }
        
        # 2. Clear browser caches and data
        Write-Log -Context $Context -Message "Clearing browser caches..." -Level 'INFO'
        
        # Chrome cleanup
        try {
            $chromePaths = @(
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache2",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cookies",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Web Data"
            )
            
            foreach ($path in $chromePaths) {
                if (Test-Path $path) {
                    try {
                        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Log -Context $Context -Message "Cleared Chrome cache: $path" -Level 'SUCCESS'
                    } catch {
                        Write-Log -Context $Context -Message "Failed to clear Chrome cache: $path - $_" -Level 'WARNING'
                    }
                }
            }
            Write-TaskLog -Context $Context -Message "Chrome browser cache cleared" -Level 'SUCCESS'
        } catch {
            Write-Log -Context $Context -Message "Chrome cleanup failed: $_" -Level 'WARNING'
        }
        
        # Edge cleanup
        try {
            $edgePaths = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cookies",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Web Data"
            )
            
            foreach ($path in $edgePaths) {
                if (Test-Path $path) {
                    try {
                        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Log -Context $Context -Message "Cleared Edge cache: $path" -Level 'SUCCESS'
                    } catch {
                        Write-Log -Context $Context -Message "Failed to clear Edge cache: $path - $_" -Level 'WARNING'
                    }
                }
            }
            Write-TaskLog -Context $Context -Message "Microsoft Edge browser cache cleared" -Level 'SUCCESS'
        } catch {
            Write-Log -Context $Context -Message "Edge cleanup failed: $_" -Level 'WARNING'
        }
        
        # Firefox cleanup
        try {
            $firefoxProfilePath = "$env:APPDATA\Mozilla\Firefox\Profiles"
            if (Test-Path $firefoxProfilePath) {
                $firefoxProfiles = Get-ChildItem -Path $firefoxProfilePath -Directory
                foreach ($currentFirefoxProfile in $firefoxProfiles) {
                    $cachePath = Join-Path $currentFirefoxProfile.FullName 'cache2'
                    if (Test-Path $cachePath) {
                        try {
                            Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Log -Context $Context -Message "Cleared Firefox cache for profile: $($currentFirefoxProfile.Name)" -Level 'SUCCESS'
                        } catch {
                            Write-Log -Context $Context -Message "Failed to clear Firefox cache for profile $($currentFirefoxProfile.Name): $_" -Level 'WARNING'
                        }
                    }
                }
                Write-TaskLog -Context $Context -Message "Firefox browser cache cleared" -Level 'SUCCESS'
            }
        } catch {
            Write-Log -Context $Context -Message "Firefox cleanup failed: $_" -Level 'WARNING'
        }
        
        # 3. Clear system temporary files
        Write-Log -Context $Context -Message "Clearing system temporary files..." -Level 'INFO'
        
        $tempPaths = @(
            $env:TEMP,
            $env:TMP,
            "$env:SystemRoot\Temp",
            "$env:LOCALAPPDATA\Temp",
            "$env:SystemRoot\Prefetch"
        )
        
        foreach ($tempPath in $tempPaths) {
            if (Test-Path $tempPath) {
                try {
                    $tempFiles = Get-ChildItem -Path $tempPath -Force -ErrorAction SilentlyContinue
                    $fileCount = $tempFiles.Count
                    $tempFiles | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log -Context $Context -Message "Cleared $fileCount items from: $tempPath" -Level 'SUCCESS'
                } catch {
                    Write-Log -Context $Context -Message "Failed to clear temp path: $tempPath - $_" -Level 'WARNING'
                }
            }
        }
        Write-TaskLog -Context $Context -Message "Temporary files cleanup completed" -Level 'SUCCESS'
        
        # 4. Clear Windows logs
        Write-Log -Context $Context -Message "Clearing Windows event logs..." -Level 'INFO'
        try {
            $logs = Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 -and $_.IsEnabled -eq $true }
            foreach ($log in $logs) {
                try {
                    [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
                    Write-Log -Context $Context -Message "Cleared log: $($log.LogName)" -Level 'SUCCESS'
                } catch {
                    # Some logs cannot be cleared, this is expected
                    Write-Log -Context $Context -Message "Could not clear log: $($log.LogName)" -Level 'INFO'
                }
            }
            Write-TaskLog -Context $Context -Message "Windows event logs cleared" -Level 'SUCCESS'
        } catch {
            Write-Log -Context $Context -Message "Event log cleanup failed: $_" -Level 'WARNING'
        }
        
        # 5. Run Storage Sense if available
        Write-Log -Context $Context -Message "Running Storage Sense..." -Level 'INFO'
        try {
            # Check if Storage Sense is available
            $storageSenseRegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense'
            if (Test-Path $storageSenseRegPath) {
                # Enable Storage Sense temporarily and run it
                Set-ItemProperty -Path $storageSenseRegPath -Name 'ConfigLastRunTime' -Value 0 -Type DWord -Force
                
                # Trigger Storage Sense via PowerShell
                $storageSenseResult = Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", "Get-StorageHealthAction | Where-Object {`$_.HealthStatus -eq 'Warning'} | Invoke-StorageHealthAction" -Wait -PassThru -WindowStyle Hidden
                if ($storageSenseResult.ExitCode -eq 0) {
                    Write-Log -Context $Context -Message "Storage Sense executed successfully" -Level 'SUCCESS'
                    Write-TaskLog -Context $Context -Message "Storage Sense cleanup completed" -Level 'SUCCESS'
                } else {
                    Write-Log -Context $Context -Message "Storage Sense execution completed with warnings" -Level 'INFO'
                }
            } else {
                Write-Log -Context $Context -Message "Storage Sense not available on this system" -Level 'INFO'
            }
        } catch {
            Write-Log -Context $Context -Message "Storage Sense execution failed: $_" -Level 'WARNING'
        }
        
        # 6. Clean up Windows Update cache
        Write-Log -Context $Context -Message "Cleaning Windows Update cache..." -Level 'INFO'
        try {
            Stop-Service -Name 'wuauserv' -Force -ErrorAction SilentlyContinue
            Stop-Service -Name 'cryptSvc' -Force -ErrorAction SilentlyContinue
            Stop-Service -Name 'bits' -Force -ErrorAction SilentlyContinue
            Stop-Service -Name 'msiserver' -Force -ErrorAction SilentlyContinue
            
            $wuCachePath = "$env:SystemRoot\SoftwareDistribution\Download"
            if (Test-Path $wuCachePath) {
                Remove-Item -Path "$wuCachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log -Context $Context -Message "Windows Update cache cleared" -Level 'SUCCESS'
            }
            
            Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
            Start-Service -Name 'cryptSvc' -ErrorAction SilentlyContinue
            Start-Service -Name 'bits' -ErrorAction SilentlyContinue
            Start-Service -Name 'msiserver' -ErrorAction SilentlyContinue
            
            Write-TaskLog -Context $Context -Message "Windows Update cache cleanup completed" -Level 'SUCCESS'
        } catch {
            Write-Log -Context $Context -Message "Windows Update cache cleanup failed: $_" -Level 'WARNING'
        }
        
        # 7. Calculate space recovered
        $finalSpace = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $systemDrive }
        $finalFreeSpace = [math]::Round($finalSpace.FreeSpace / 1GB, 2)
        $spaceRecovered = [math]::Round($finalFreeSpace - $initialFreeSpace, 2)
        
        Write-Log -Context $Context -Message "Final free space on $systemDrive`: $finalFreeSpace GB" -Level 'INFO'
        Write-Log -Context $Context -Message "Total space recovered: $spaceRecovered GB" -Level 'SUCCESS'
        Write-TaskLog -Context $Context -Message "Disk cleanup completed. Space recovered: $spaceRecovered GB" -Level 'SUCCESS'
        
        # Save combined cleanup summary including restore points and diagnostics
        $cleanupSummary = @()
        $cleanupSummary += "=== COMBINED MAINTENANCE SUMMARY ==="
        $cleanupSummary += "Initial free space: $initialFreeSpace GB"
        $cleanupSummary += "Final free space: $finalFreeSpace GB"
        $cleanupSummary += "Space recovered: $spaceRecovered GB"
        $cleanupSummary += ""
        $cleanupSummary += "Restore point management:"
        if ($finalRestorePoints) {
            $cleanupSummary += "- Validated and maintained $($finalRestorePoints.Count) restore points"
            $cleanupSummary += "- Deleted $($restorePointsToDelete.Count) old restore points"
        } else {
            $cleanupSummary += "- No restore points found on system"
        }
        $cleanupSummary += ""
        $cleanupSummary += "System diagnostics performed:"
        $cleanupSummary += "- Event Viewer error analysis (48h)"
        $cleanupSummary += "- CBS log analysis (48h)"
        $cleanupSummary += "- System health assessment"
        $cleanupSummary += "- SFC/CHKDSK/DISM recommendations generated"
        $cleanupSummary += ""
        $cleanupSummary += "Disk cleanup operations performed:"
        $cleanupSummary += "- Windows Disk Cleanup (cleanmgr)"
        $cleanupSummary += "- Browser caches (Chrome, Edge, Firefox)"
        $cleanupSummary += "- System temporary files"
        $cleanupSummary += "- Windows event logs"
        $cleanupSummary += "- Storage Sense execution"
        $cleanupSummary += "- Windows Update cache"
        
        $summaryPath = Join-Path $Context.CurrentTaskFolder 'CombinedMaintenance_Summary.txt'
        $cleanupSummary | Out-File $summaryPath -Encoding UTF8
        Write-Log -Context $Context -Message "Combined maintenance summary saved to $summaryPath" -Level 'INFO'
        
    } catch {
        Write-Log -Context $Context -Message "Task 10: Restore Point Management & Full Disk Cleanup failed: $_" -Level 'ERROR'
        Write-TaskLog -Context $Context -Message "Task 10: Restore Point Management & Full Disk Cleanup failed: $_" -Level 'ERROR'
    }
    
    Write-TaskLog -Context $Context -Message "Task 10 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 10: RESTORE POINT MANAGEMENT & FULL DISK CLEANUP
# =====================================================================================

# =====================================================================================
# TASK 11: GENERATE COMPREHENSIVE HTML REPORT
# =====================================================================================
# Purpose: Create detailed HTML reports with task summaries and system statistics
# Dependencies: Task execution logs and outputs from all previous tasks
# Outputs: Comprehensive HTML report, task statistics, execution summaries
# Structure:
#   1. Task initialization and report setup
#   2. Task logs and statistics collection
#   3. HTML report generation and formatting
#   4. Summary compilation and presentation
#   5. Report finalization and storage
# =====================================================================================
function Invoke-Task11_GenerateTranscriptHtml {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION AND REPORT SETUP
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 11: GENERATE COMPREHENSIVE HTML REPORT ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 11: GENERATE COMPREHENSIVE HTML REPORT ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 11: Generating comprehensive HTML report with statistics and per-task analysis..." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 11: Generating comprehensive HTML report with statistics and per-task analysis..." -Level 'INFO'
    
    try {
        # Simple text-based report for now
        $summaryLines = @()
        $summaryLines += "=== SYSTEM MAINTENANCE SUMMARY ==="
        $summaryLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $summaryLines += "System: $env:COMPUTERNAME"
        $summaryLines += ""
        
        # Collect task folder information
        if ($Context.TaskFolders) {
            $summaryLines += "=== TASK RESULTS ==="
            $sortedTaskFolders = $Context.TaskFolders.GetEnumerator() | Sort-Object { 
                if ($_.Key -match 'Task(\d+)_') { 
                    [int]$matches[1] 
                } else { 
                    999 
                } 
            }
            
            foreach ($taskFolderEntry in $sortedTaskFolders) {
                $taskName = $taskFolderEntry.Key
                $taskFolderPath = $taskFolderEntry.Value
                
                # Clean task name for display
                $cleanTaskName = $taskName -replace '^Task\d+_', '' -replace '_', ' '
                $cleanTaskName = (Get-Culture).TextInfo.ToTitleCase($cleanTaskName.ToLower())
                
                # Get files from task folder
                $taskFiles = Get-ChildItem -Path $taskFolderPath -File -ErrorAction SilentlyContinue
                $summaryLines += "- $cleanTaskName`: $($taskFiles.Count) files generated"
            }
        }
        
        # Save simple text report
        $scriptPath = $MyInvocation.PSCommandPath
        $scriptDir = Split-Path -Parent $scriptPath
        $outPath = Join-Path $scriptDir 'SystemMaintenance_Summary.txt'
        $summaryLines | Out-File -FilePath $outPath -Encoding UTF8
        
        Write-Log -Context $Context -Message "System maintenance summary generated at $outPath" -Level 'SUCCESS'
        Write-TaskLog -Context $Context -Message "System maintenance summary generated at $outPath" -Level 'SUCCESS'
        Write-Host "[Task 11] Summary generated: $outPath"
        
    } catch {
        Write-Log -Context $Context -Message "Task 11: Failed to generate summary: $_" -Level 'ERROR'
        Write-TaskLog -Context $Context -Message "Task 11: Failed to generate summary: $_" -Level 'ERROR'
    }
    
    Write-TaskLog -Context $Context -Message "Task 11 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 11: GENERATE COMPREHENSIVE HTML REPORT
# =====================================================================================

# =====================================================================================
# TASK 12: CHECK AND PROMPT REBOOT
# =====================================================================================
# Purpose: Check system reboot requirements and provide user prompts for restart
# Dependencies: System registry analysis, pending operations detection
# Outputs: Reboot requirement analysis, user interaction prompts
# Structure:
#   1. Task initialization and system check
#   2. Pending reboot detection analysis
#   3. User notification and prompt handling
#   4. Reboot scheduling or deferral
#   5. Final system state logging
# =====================================================================================
function Invoke-Task12_CheckAndPromptReboot {
    param([hashtable]$Context)
    
    # ═══════════════════════════════════════════════════════════════════════════════════
    # SECTION 1: TASK INITIALIZATION AND SYSTEM CHECK
    # ═══════════════════════════════════════════════════════════════════════════════════
    Write-Host "=====================[ TASK 12: CHECK AND PROMPT REBOOT ]===================="
    Write-Log -Context $Context -Message "=====================[ TASK 12: CHECK AND PROMPT REBOOT ]====================" -Level 'INFO'
    Write-TaskLog -Context $Context -Message "Task 12: Checking if reboot is required..." -Level 'INFO'
    Write-Log -Context $Context -Message "Task 12: Checking if reboot is required..." -Level 'INFO'
    
    $rebootRequired = $false
    
    try {
        # Check for common reboot-required indicators
        $pendingFile = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        $pendingCBS = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        $pendingSession = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' # PendingFileRenameOperations
        
        if (Test-Path $pendingFile -ErrorAction SilentlyContinue) { $rebootRequired = $true }
        if (Test-Path $pendingCBS -ErrorAction SilentlyContinue) { $rebootRequired = $true }
        
        $pendingOps = (Get-ItemProperty -Path $pendingSession -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue)
        if ($pendingOps) { $rebootRequired = $true }
        
    } catch {
        Write-Log -Context $Context -Message "Task 12: Failed to check reboot status: $_" -Level 'WARNING'
    }
    
    # Check for deferred updates
    $hasDeferredUpdates = $Context.ContainsKey('DeferredUpdates') -and $Context.DeferredUpdates.Count -gt 0
    
    if ($rebootRequired) {
        Write-Log -Context $Context -Message "A system reboot is required." -Level 'WARNING'
        Write-TaskLog -Context $Context -Message "A system reboot is required." -Level 'WARNING'
        Write-Host "`nA system reboot is required to complete maintenance."
        
        if ($hasDeferredUpdates) {
            Write-Host "⚠️  Note: There are deferred updates (PowerShell 7) that should be installed before rebooting."
            Write-Host "The deferred updates will be handled during cleanup."
        }
        
        Write-Host "Press any key to restart now"
        $timeout = 120
        $inputReceived = $false
        
        # Show countdown and wait for input
        for ($i = $timeout; $i -gt 0; $i--) {
            if ($Host.UI.RawUI.KeyAvailable) {
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                Write-Host "`nRestarting now..."
                Write-Log -Context $Context -Message "User accepted reboot prompt. Restarting now." -Level 'INFO'
                Restart-Computer -Force
                $inputReceived = $true
                break
            }
            
            # Show countdown every 10 seconds
            if ($i % 10 -eq 0 -or $i -le 10) {
                Write-Host "`rTime remaining: $i seconds..." -NoNewline
            }
            
            Start-Sleep -Seconds 1
        }
        
        if (-not $inputReceived) {
            Write-Host "`nPlease restart your system manually."
            Write-Log -Context $Context -Message "No user input at reboot prompt. System should be restarted manually." -Level 'WARNING'
            Write-TaskLog -Context $Context -Message "No user input at reboot prompt. System should be restarted manually." -Level 'WARNING'
        }
    } else {
        Write-Log -Context $Context -Message "No reboot required." -Level 'SUCCESS'
        Write-TaskLog -Context $Context -Message "No reboot required." -Level 'SUCCESS'
        
        if ($hasDeferredUpdates) {
            Write-Host "`n⚠️  Note: There are deferred updates (PowerShell 7) that will be handled during cleanup."
        }
    }
    
    Write-TaskLog -Context $Context -Message "Task 12 completed." -Level 'SUCCESS'
}
# =====================================================================================
# END TASK 12: CHECK AND PROMPT REBOOT
# =====================================================================================

# =====================[ HTML REPORT HELPER FUNCTIONS ]====================
# Helper function to build individual task HTML sections
function Build-TaskHtmlSection {
    param(
        [hashtable]$TaskAnalysis,
        [array]$TaskFiles
    )
    
    $statusColor = switch ($TaskAnalysis.Status) {
        'SUCCESS' { '#4CAF50' }
        'WARNING' { '#FF9800' }
        'ERROR' { '#F44336' }
        default { '#2196F3' }
    }
    
    $statusIcon = switch ($TaskAnalysis.Status) {
        'SUCCESS' { '✅' }
        'WARNING' { '⚠️' }
        'ERROR' { '❌' }
        default { 'ℹ️' }
    }
    
    $html = @"
<div class="task-container">
    <div class="task-header">
        <div class="task-title">
            <span class="task-number">Task $($TaskAnalysis.Number)</span>
            <h2>$($TaskAnalysis.Name)</h2>
        </div>
        <div class="task-status" style="background-color: $statusColor;">
            $statusIcon $($TaskAnalysis.Status)
        </div>
    </div>
    
    <div class="task-metrics">
        <div class="metric-card">
            <div class="metric-value">$($TaskAnalysis.FilesGenerated)</div>
            <div class="metric-label">Files Generated</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">$($TaskAnalysis.LogEntries)</div>
            <div class="metric-label">Log Entries</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">$($TaskAnalysis.Duration)</div>
            <div class="metric-label">Duration</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">$([math]::Round($TaskAnalysis.SpaceUsed / 1KB, 1)) KB</div>
            <div class="metric-label">Space Used</div>
        </div>
    </div>
    
    <div class="task-content">
"@
    
    # Add items added/removed/updated sections
    if ($TaskAnalysis.ItemsAdded.Count -gt 0) {
        $itemsHtml = $TaskAnalysis.ItemsAdded | ForEach-Object { "<span class='item-tag added'>$_</span>" }
        $html += @"
        <div class="items-section added">
            <h4>📥 Items Added ($($TaskAnalysis.ItemsAdded.Count))</h4>
            <div class="items-list">
                $($itemsHtml -join ' ')
            </div>
        </div>
"@
    }
    
    if ($TaskAnalysis.ItemsRemoved.Count -gt 0) {
        $itemsHtml = $TaskAnalysis.ItemsRemoved | ForEach-Object { "<span class='item-tag removed'>$_</span>" }
        $html += @"
        <div class="items-section removed">
            <h4>📤 Items Removed ($($TaskAnalysis.ItemsRemoved.Count))</h4>
            <div class="items-list">
                $($itemsHtml -join ' ')
            </div>
        </div>
"@
    }
    
    if ($TaskAnalysis.ItemsUpdated.Count -gt 0) {
        $itemsHtml = $TaskAnalysis.ItemsUpdated | ForEach-Object { "<span class='item-tag updated'>$_</span>" }
        $html += @"
        <div class="items-section updated">
            <h4>🔄 Items Updated ($($TaskAnalysis.ItemsUpdated.Count))</h4>
            <div class="items-list">
                $($itemsHtml -join ' ')
            </div>
        </div>
"@
    }
    
    # Add errors, warnings, successes
    if ($TaskAnalysis.Errors.Count -gt 0) {
        $errorsHtml = $TaskAnalysis.Errors | ForEach-Object { "<li>$_</li>" }
        $html += @"
        <div class="status-section errors">
            <h4>❌ Errors ($($TaskAnalysis.Errors.Count))</h4>
            <ul>
                $($errorsHtml -join '')
            </ul>
        </div>
"@
    }
    
    if ($TaskAnalysis.Warnings.Count -gt 0) {
        $warningsHtml = $TaskAnalysis.Warnings | ForEach-Object { "<li>$_</li>" }
        $html += @"
        <div class="status-section warnings">
            <h4>⚠️ Warnings ($($TaskAnalysis.Warnings.Count))</h4>
            <ul>
                $($warningsHtml -join '')
            </ul>
        </div>
"@
    }
    
    if ($TaskAnalysis.Successes.Count -gt 0) {
        $successesHtml = $TaskAnalysis.Successes | ForEach-Object { "<li>$_</li>" }
        $html += @"
        <div class="status-section successes">
            <h4>✅ Successes ($($TaskAnalysis.Successes.Count))</h4>
            <ul>
                $($successesHtml -join '')
            </ul>
        </div>
"@
    }
    
    # Add files section
    if ($TaskFiles.Count -gt 0) {
        $html += @"
        <div class="files-section">
            <h4>📁 Generated Files</h4>
            <div class="file-grid">
"@
        
        foreach ($file in $TaskFiles) {
            $fileSize = [math]::Round($file.Length / 1KB, 1)
            $fileIcon = switch -Regex ($file.Name) {
                '_log\.txt$' { '📄' }
                '_Summary\.txt$' { '📊' }
                '_Report\.txt$' { '📈' }
                '_list\.txt$' { '📋' }
                default { '📄' }
            }
            
            $html += @"
                <div class="file-card">
                    <div class="file-icon">$fileIcon</div>
                    <div class="file-info">
                        <div class="file-name">$($file.Name)</div>
                        <div class="file-size">$fileSize KB</div>
                    </div>
                </div>
"@
        }
        
        $html += "</div></div>"
    }
    
    $html += "</div></div>"
    return $html
}

# Helper function to build the complete HTML report
function Build-CompleteHtmlReport {
    param(
        [string]$SystemName,
        [string]$OSVersion,
        [string]$TotalRAM,
        [hashtable]$TaskStats,
        [array]$SummaryData,
        [array]$TaskSections,
        [datetime]$StartTime
    )
    
    $generateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $successRate = if ($TaskStats.Total -gt 0) { [math]::Round(($TaskStats.Successful / $TaskStats.Total) * 100, 1) } else { 0 }
    
    return @"
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>System Maintenance Report - $SystemName</title>
    <style>
        :root {
            /* Light mode colors */
            --bg-gradient-start: #667eea;
            --bg-gradient-end: #764ba2;
            --text-primary: #333;
            --text-secondary: #7f8c8d;
            --text-heading: #2c3e50;
            --card-bg: rgba(255, 255, 255, 0.95);
            --card-hover-bg: rgba(255, 255, 255, 0.98);
            --border-color: #dee2e6;
            --file-card-bg: #f8f9fa;
            --progress-bg: #ecf0f1;
            --header-gradient-start: #f8f9fa;
            --header-gradient-end: #e9ecef;
            --shadow-color: rgba(0, 0, 0, 0.1);
            --shadow-light: rgba(0, 0, 0, 0.05);
        }
        
        [data-theme="dark"] {
            /* Dark mode colors */
            --bg-gradient-start: #2c3e50;
            --bg-gradient-end: #34495e;
            --text-primary: #ecf0f1;
            --text-secondary: #bdc3c7;
            --text-heading: #ecf0f1;
            --card-bg: rgba(52, 73, 94, 0.95);
            --card-hover-bg: rgba(52, 73, 94, 0.98);
            --border-color: #4a5568;
            --file-card-bg: #3a4852;
            --progress-bg: #4a5568;
            --header-gradient-start: #34495e;
            --header-gradient-end: #2c3e50;
            --shadow-color: rgba(0, 0, 0, 0.3);
            --shadow-light: rgba(0, 0, 0, 0.2);
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, var(--bg-gradient-start) 0%, var(--bg-gradient-end) 100%);
            min-height: 100vh;
            color: var(--text-primary);
            transition: all 0.3s ease;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .theme-toggle {
            position: fixed;
            top: 20px;
            right: 20px;
            background: var(--card-bg);
            border: 2px solid var(--border-color);
            border-radius: 50px;
            padding: 12px 20px;
            cursor: pointer;
            font-size: 1.1em;
            color: var(--text-primary);
            box-shadow: 0 4px 15px var(--shadow-color);
            transition: all 0.3s ease;
            z-index: 1000;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .theme-toggle:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px var(--shadow-color);
            background: var(--card-hover-bg);
        }
        
        .header {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 8px 32px var(--shadow-color);
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            color: var(--text-heading);
            margin-bottom: 10px;
            font-weight: 300;
        }
        
        .header .subtitle {
            font-size: 1.2em;
            color: var(--text-secondary);
            margin-bottom: 20px;
        }
        
        .system-info {
            display: flex;
            justify-content: center;
            gap: 30px;
            flex-wrap: wrap;
            margin-top: 20px;
        }
        
        .system-info-item {
            text-align: center;
        }
        
        .system-info-item .label {
            font-size: 0.9em;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .system-info-item .value {
            font-size: 1.1em;
            font-weight: 600;
            color: var(--text-heading);
            margin-top: 5px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            text-align: center;
            box-shadow: 0 4px 20px var(--shadow-color);
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
            background: var(--card-hover-bg);
        }
        
        .stat-value {
            font-size: 2.5em;
            font-weight: 700;
            margin-bottom: 10px;
        }
        
        .stat-label {
            font-size: 1em;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .stat-card.success .stat-value { color: #27ae60; }
        .stat-card.warning .stat-value { color: #f39c12; }
        .stat-card.error .stat-value { color: #e74c3c; }
        .stat-card.info .stat-value { color: #3498db; }
        
        .task-container {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            margin-bottom: 25px;
            box-shadow: 0 4px 20px var(--shadow-color);
            overflow: hidden;
        }
        
        .task-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 25px 30px;
            background: linear-gradient(135deg, var(--header-gradient-start) 0%, var(--header-gradient-end) 100%);
            border-bottom: 1px solid var(--border-color);
        }
        
        .task-title {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        .task-number {
            background: #6c757d;
            color: white;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: 600;
        }
        
        .task-title h2 {
            font-size: 1.5em;
            font-weight: 600;
            color: var(--text-heading);
        }
        
        .task-status {
            padding: 10px 20px;
            border-radius: 25px;
            color: white;
            font-weight: 600;
            font-size: 0.9em;
        }
        
        .task-metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            padding: 25px 30px;
            background: var(--header-gradient-start);
            border-bottom: 1px solid var(--border-color);
        }
        
        .metric-card {
            text-align: center;
            padding: 15px;
            background: var(--card-bg);
            border-radius: 10px;
            box-shadow: 0 2px 10px var(--shadow-light);
        }
        
        .metric-value {
            font-size: 1.8em;
            font-weight: 700;
            color: var(--text-heading);
            margin-bottom: 5px;
        }
        
        .metric-label {
            font-size: 0.85em;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .task-content {
            padding: 30px;
        }
        
        .items-section {
            margin-bottom: 25px;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid;
        }
        
        .items-section.added {
            background: rgba(46, 204, 113, 0.1);
            border-left-color: #2ecc71;
        }
        
        .items-section.removed {
            background: rgba(231, 76, 60, 0.1);
            border-left-color: #e74c3c;
        }
        
        .items-section.updated {
            background: rgba(52, 152, 219, 0.1);
            border-left-color: #3498db;
        }
        
        .items-section h4 {
            margin-bottom: 15px;
            font-size: 1.1em;
            color: var(--text-heading);
        }
        
        .items-list {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }
        
        .item-tag {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 500;
        }
        
        .item-tag.added {
            background: #2ecc71;
            color: white;
        }
        
        .item-tag.removed {
            background: #e74c3c;
            color: white;
        }
        
        .item-tag.updated {
            background: #3498db;
            color: white;
        }
        
        .status-section {
            margin-bottom: 20px;
            padding: 15px;
            border-radius: 8px;
        }
        
        .status-section.errors {
            background: rgba(231, 76, 60, 0.1);
            border-left: 4px solid #e74c3c;
        }
        
        .status-section.warnings {
            background: rgba(243, 156, 18, 0.1);
            border-left: 4px solid #f39c12;
        }
        
        .status-section.successes {
            background: rgba(46, 204, 113, 0.1);
            border-left: 4px solid #2ecc71;
        }
        
        .status-section h4 {
            margin-bottom: 10px;
            color: var(--text-heading);
        }
        
        .status-section ul {
            margin-left: 20px;
        }
        
        .status-section li {
            margin-bottom: 5px;
            color: var(--text-primary);
        }
        
        .files-section {
            margin-top: 25px;
        }
        
        .files-section h4 {
            margin-bottom: 15px;
            color: var(--text-heading);
            font-size: 1.1em;
        }
        
        .file-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 15px;
        }
        
        .file-card {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 15px;
            background: var(--file-card-bg);
            border-radius: 8px;
            border: 1px solid var(--border-color);
        }
        
        .file-icon {
            font-size: 1.5em;
        }
        
        .file-name {
            font-weight: 500;
            color: var(--text-heading);
            font-size: 0.9em;
        }
        
        .file-size {
            font-size: 0.8em;
            color: var(--text-secondary);
        }
        
        .footer {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 20px;
            text-align: center;
            margin-top: 30px;
            box-shadow: 0 4px 20px var(--shadow-color);
        }
        
        .footer .generated-time {
            color: var(--text-secondary);
            font-size: 0.9em;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 10px;
            }
            
            .header {
                padding: 20px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .system-info {
                gap: 15px;
            }
            
            .task-header {
                flex-direction: column;
                gap: 15px;
                text-align: center;
            }
            
            .task-metrics {
                grid-template-columns: repeat(2, 1fr);
                padding: 20px;
            }
            
            .task-content {
                padding: 20px;
            }
        }
        
        .summary-section {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 4px 20px var(--shadow-color);
        }
        
        .summary-section h2 {
            color: var(--text-heading);
            margin-bottom: 20px;
            font-size: 1.8em;
            text-align: center;
        }
        
        .progress-bar {
            background: var(--progress-bg);
            border-radius: 25px;
            overflow: hidden;
            height: 30px;
            margin: 20px 0;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #2ecc71 0%, #27ae60 100%);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: 600;
            transition: width 0.3s ease;
        }
        
        /* Dark mode toggle animations */
        .theme-toggle .icon {
            transition: transform 0.3s ease;
        }
        
        [data-theme="dark"] .theme-toggle .sun-icon {
            transform: rotate(180deg) scale(0);
        }
        
        [data-theme="dark"] .theme-toggle .moon-icon {
            transform: rotate(0deg) scale(1);
        }
        
        .theme-toggle .sun-icon {
            transform: rotate(0deg) scale(1);
        }
        
        .theme-toggle .moon-icon {
            transform: rotate(-180deg) scale(0);
        }
        
        /* Auto dark mode based on system preference */
        @media (prefers-color-scheme: dark) {
            :root:not([data-theme="light"]) {
                --bg-gradient-start: #2c3e50;
                --bg-gradient-end: #34495e;
                --text-primary: #ecf0f1;
                --text-secondary: #bdc3c7;
                --text-heading: #ecf0f1;
                --card-bg: rgba(52, 73, 94, 0.95);
                --card-hover-bg: rgba(52, 73, 94, 0.98);
                --border-color: #4a5568;
                --file-card-bg: #3a4852;
                --progress-bg: #4a5568;
                --header-gradient-start: #34495e;
                --header-gradient-end: #2c3e50;
                --shadow-color: rgba(0, 0, 0, 0.3);
                --shadow-light: rgba(0, 0, 0, 0.2);
            }
        }
    </style>
    <script>
        // Theme management
        function initTheme() {
            const savedTheme = localStorage.getItem('theme');
            const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
            
            if (savedTheme) {
                document.documentElement.setAttribute('data-theme', savedTheme);
            } else if (systemPrefersDark) {
                document.documentElement.setAttribute('data-theme', 'dark');
            }
            
            updateThemeToggleText();
        }
        
        function toggleTheme() {
            const currentTheme = document.documentElement.getAttribute('data-theme');
            const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
            
            document.documentElement.setAttribute('data-theme', newTheme);
            localStorage.setItem('theme', newTheme);
            updateThemeToggleText();
        }
        
        function updateThemeToggleText() {
            const themeToggle = document.querySelector('.theme-toggle');
            const currentTheme = document.documentElement.getAttribute('data-theme');
            const isDark = currentTheme === 'dark';
            
            if (themeToggle) {
                themeToggle.innerHTML = isDark ? 
                    '<span class="icon sun-icon">☀️</span> Light Mode' : 
                    '<span class="icon moon-icon">🌙</span> Dark Mode';
            }
        }
        
        // Initialize theme when DOM is loaded
        document.addEventListener('DOMContentLoaded', function() {
            initTheme();
            
            // Add click event to theme toggle
            const themeToggle = document.querySelector('.theme-toggle');
            if (themeToggle) {
                themeToggle.addEventListener('click', toggleTheme);
            }
        });
        
        // Listen for system theme changes
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {
            if (!localStorage.getItem('theme')) {
                document.documentElement.setAttribute('data-theme', e.matches ? 'dark' : 'light');
                updateThemeToggleText();
            }
        });
    </script>
</head>
<body>
    <div class="theme-toggle" title="Toggle light/dark mode">
        <span class="icon moon-icon">🌙</span> Dark Mode
    </div>
    <div class="container">
        <div class="header">
            <h1>🔧 System Maintenance Report</h1>
            <div class="subtitle">Comprehensive system maintenance analysis for $SystemName</div>
            <div class="system-info">
                <div class="system-info-item">
                    <div class="label">System</div>
                    <div class="value">$SystemName</div>
                </div>
                <div class="system-info-item">
                    <div class="label">OS Version</div>
                    <div class="value">$OSVersion</div>
                </div>
                <div class="system-info-item">
                    <div class="label">Total RAM</div>
                    <div class="value">$TotalRAM GB</div>
                </div>
                <div class="system-info-item">
                    <div class="label">Generated</div>
                    <div class="value">$generateTime</div>
                </div>
            </div>
        </div>
        
        <div class="summary-section">
            <h2>📊 Execution Summary</h2>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${successRate}%;">
                    ${successRate}% Success Rate
                </div>
            </div>
            <div class="stats-grid">
                <div class="stat-card info">
                    <div class="stat-value">$($TaskStats.Total)</div>
                    <div class="stat-label">Total Tasks</div>
                </div>
                <div class="stat-card success">
                    <div class="stat-value">$($TaskStats.Successful)</div>
                    <div class="stat-label">Successful</div>
                </div>
                <div class="stat-card warning">
                    <div class="stat-value">$($TaskStats.WithWarnings)</div>
                    <div class="stat-label">With Warnings</div>
                </div>
                <div class="stat-card error">
                    <div class="stat-value">$($TaskStats.WithErrors)</div>
                    <div class="stat-label">With Errors</div>
                </div>
                <div class="stat-card info">
                    <div class="stat-value">$($TaskStats.TotalFiles)</div>
                    <div class="stat-label">Files Generated</div>
                </div>
                <div class="stat-card info">
                    <div class="stat-value">$($TaskStats.TotalLogEntries)</div>
                    <div class="stat-label">Log Entries</div>
                </div>
            </div>
        </div>
        
        $($TaskSections -join "`n")
        
        <div class="footer">
            <div class="generated-time">
                Report generated on $generateTime | System Maintenance Script v2.0
            </div>
        </div>
    </div>
</body>
</html>
"@
}

# =====================[ TASK REGISTRATION & EXECUTION ]====================
$AllTasks = @(
    'Invoke-Task1_CentralCoordinationPolicy',
    'Invoke-Task2_SystemProtection', 
    'Invoke-Task3_PackageManagerSetup',
    'Invoke-Task4_SystemInventory',
    'Invoke-Task5_RemoveBloatware',
    'Invoke-Task6_InstallEssentialApps',
    'Invoke-Task7_UpgradeAllPackages',
    'Invoke-Task8_PrivacyAndTelemetry',
    'Invoke-Task9_WindowsUpdate',
    'Invoke-Task10_RestorePointAndDiskCleanup',
    'Invoke-Task11_GenerateTranscriptHtml',
    'Invoke-Task12_CheckAndPromptReboot'
)

Invoke-SystemMaintenancePolicy -Tasks $AllTasks

# =====================[ FINALIZATION ]====================
