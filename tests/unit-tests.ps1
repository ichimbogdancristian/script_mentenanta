# unit-tests.ps1
# Unit tests for individual modules and functions

BeforeAll {
    $ScriptRoot = Split-Path $PSScriptRoot -Parent
    $ModulePath = Join-Path $ScriptRoot "modules"
    
    # Import modules for testing
    Import-Module (Join-Path $ModulePath "ConfigManager.psm1") -Force
    Import-Module (Join-Path $ModulePath "LoggingManager.psm1") -Force
    Import-Module (Join-Path $ModulePath "SystemTasks.psm1") -Force
    
    # Create test configuration
    $testConfigContent = @{
        system = @{
            requiresAdmin = $false
            minWindowsVersion = "10.0"
            logLevel = "Debug"
        }
        maintenanceTasks = @{
            testTask = @{
                enabled = $true
                description = "Test task"
                priority = 1
            }
            disabledTask = @{
                enabled = $false
                description = "Disabled task"
                priority = 2
            }
        }
    }
    
    $script:testConfigPath = Join-Path $TestDrive "test-config.json"
    $testConfigContent | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:testConfigPath -Encoding UTF8
}

Describe "ConfigManager Module Tests" {
    Context "Import-MaintenanceConfig" {
        It "Should load valid configuration file" {
            $config = Import-MaintenanceConfig -ConfigPath $script:testConfigPath
            $config | Should -Not -BeNullOrEmpty
            $config.system | Should -Not -BeNullOrEmpty
            $config.maintenanceTasks | Should -Not -BeNullOrEmpty
        }
        
        It "Should throw error for missing file" {
            $missingPath = Join-Path $TestDrive "missing-config.json"
            { Import-MaintenanceConfig -ConfigPath $missingPath } | Should -Throw
        }
        
        It "Should throw error for invalid JSON" {
            $invalidConfigPath = Join-Path $TestDrive "invalid-config.json"
            "invalid json content" | Out-File -FilePath $invalidConfigPath
            { Import-MaintenanceConfig -ConfigPath $invalidConfigPath } | Should -Throw
        }
    }
    
    Context "Get-EnabledTasks" {
        It "Should return only enabled tasks" {
            $config = Import-MaintenanceConfig -ConfigPath $script:testConfigPath
            $enabledTasks = Get-EnabledTasks -Config $config
            $enabledTasks.Count | Should -Be 1
            $enabledTasks[0].Name | Should -Be "testTask"
        }
        
        It "Should sort tasks by priority" {
            # Create config with multiple enabled tasks
            $multiTaskConfig = @{
                maintenanceTasks = @{
                    task1 = @{ enabled = $true; priority = 3; description = "Task 1" }
                    task2 = @{ enabled = $true; priority = 1; description = "Task 2" }
                    task3 = @{ enabled = $true; priority = 2; description = "Task 3" }
                }
            }
            
            $tasks = Get-EnabledTasks -Config $multiTaskConfig
            $tasks.Count | Should -Be 3
            $tasks[0].Priority | Should -Be 1
            $tasks[1].Priority | Should -Be 2
            $tasks[2].Priority | Should -Be 3
        }
    }
    
    Context "Test-SystemRequirements" {
        It "Should pass for valid system requirements" {
            $config = Import-MaintenanceConfig -ConfigPath $script:testConfigPath
            $result = Test-SystemRequirements -Config $config
            $result | Should -Be $true
        }
        
        It "Should fail for high minimum Windows version" {
            $config = @{
                system = @{
                    requiresAdmin = $false
                    minWindowsVersion = "99.0"
                }
            }
            
            $result = Test-SystemRequirements -Config $config
            $result | Should -Be $false
        }
    }
}

Describe "LoggingManager Module Tests" {
    Context "Initialize-Logger" {
        It "Should create log directory and file" {
            $logPath = Join-Path $TestDrive "logs"
            Initialize-Logger -LogPath $logPath -LogLevel "Debug"
            
            Test-Path $logPath | Should -Be $true
            $Global:LogPath | Should -Be $logPath
            $Global:LogLevel | Should -Be "Debug"
        }
    }
    
    Context "Write-LogMessage" {
        BeforeEach {
            $logPath = Join-Path $TestDrive "logs"
            Initialize-Logger -LogPath $logPath -LogLevel "Debug"
        }
        
        It "Should write message to log file" {
            Write-LogMessage -Level "Info" -Message "Test message"
            
            $logContent = Get-Content $Global:LogFile -Raw
            $logContent | Should -Match "Test message"
        }
        
        It "Should respect log level filtering" {
            # Set log level to Warning
            $Global:LogLevel = "Warning"
            
            Write-LogMessage -Level "Debug" -Message "Debug message"
            Write-LogMessage -Level "Warning" -Message "Warning message"
            
            $logContent = Get-Content $Global:LogFile -Raw
            $logContent | Should -Not -Match "Debug message"
            $logContent | Should -Match "Warning message"
        }
    }
}

Describe "SystemTasks Module Tests" {
    Context "Task Function Availability" {
        It "Should have Invoke-SystemRestorePoint function" {
            Get-Command Invoke-SystemRestorePoint -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should have Invoke-DefenderScan function" {
            Get-Command Invoke-DefenderScan -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should have Invoke-DiskCleanup function" {
            Get-Command Invoke-DiskCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should have Invoke-SystemFileCheck function" {
            Get-Command Invoke-SystemFileCheck -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Task Parameter Validation" {
        It "Should accept TaskSettings parameter for all task functions" {
            $testSettings = @{ testProperty = "testValue" }
            
            # These should not throw parameter binding errors
            { Invoke-SystemRestorePoint -TaskSettings $testSettings -WhatIf } | Should -Not -Throw
            { Invoke-DefenderScan -TaskSettings $testSettings -WhatIf } | Should -Not -Throw
            { Invoke-DiskCleanup -TaskSettings $testSettings -WhatIf } | Should -Not -Throw
            { Invoke-SystemFileCheck -TaskSettings $testSettings -WhatIf } | Should -Not -Throw
        }
    }
}
