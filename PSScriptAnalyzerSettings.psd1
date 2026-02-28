# PSScriptAnalyzer settings for Windows Maintenance Automation System
# Version: 3.2 - Enhanced Configuration
# Date: December 1, 2025
# Based on: PSScriptAnalyzer 1.24.0 best practices
# Reference: https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/

@{
    # ============================================================================
    # SEVERITY & RULE CONFIGURATION
    # ============================================================================
    
    # Severity levels to include (Error, Warning, Information, ParseError)
    Severity            = @('Error', 'Warning', 'Information')
    
    # Include default rules from PSScriptAnalyzer
    IncludeDefaultRules = $true
    
    # Exclude specific rules that don't apply to this project
    # Each exclusion should have a clear justification
    ExcludeRules        = @(
        # UI/UX - Allow Write-Host for user-facing UI messages and progress display
        'PSAvoidUsingWriteHost',
        
        # Security - Allow ConvertTo-SecureString with -AsPlainText (used in credential handling)
        # Note: Used carefully in controlled scenarios only
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        
        # Security - Allow plain text passwords in configuration files
        # Note: Acceptable for test/example code and non-sensitive defaults
        'PSAvoidUsingPlainTextForPassword',
        
        # Style - Allow positional parameters in internal helper functions
        'PSAvoidUsingPositionalParameters',

        # Project-defined function 'Write-Log' shadows a platform-specific module cmdlet.
        # Write-Log is intentionally defined as the project's structured logging function.
        'PSAvoidOverwritingBuiltInCmdlets'
    )
    
    # ============================================================================
    # DETAILED RULE CONFIGURATION
    # ============================================================================
    
    Rules               = @{
        
        # ------------------------------------------------------------------------
        # CMDLET DESIGN RULES
        # ------------------------------------------------------------------------
        
        # Use approved verbs only (Get, Set, New, Invoke, Test, etc.)
        PSUseApprovedVerbs                          = @{
            Enable = $true
        }
        
        # Use singular nouns for cmdlet names (Get-Item not Get-Items)
        PSUseSingularNouns                          = @{
            Enable = $true
        }
        
        # Avoid reserved characters in cmdlet names
        PSAvoidReservedCharInCmdlet                 = @{
            Enable = $true
        }
        
        # Avoid reserved parameter names
        PSAvoidReservedParams                       = @{
            Enable = $true
        }
        
        # Support ShouldProcess for state-changing functions
        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }
        
        # Require [CmdletBinding()] for advanced functions
        PSUseCmdletCorrectly                        = @{
            Enable = $true
        }
        
        # Use OutputType attribute when appropriate
        PSUseOutputTypeCorrectly                    = @{
            Enable = $true
        }
        
        # Avoid default values for switch parameters
        PSAvoidDefaultValueSwitchParameter          = @{
            Enable = $true
        }
        
        # ------------------------------------------------------------------------
        # CODE QUALITY & BEST PRACTICES
        # ------------------------------------------------------------------------
        
        # Cmdlet aliases should not be used in scripts (use full cmdlet names)
        PSAvoidUsingCmdletAliases                   = @{
            Enable = $true
        }
        
        # Avoid using deprecated WMI cmdlets (use Get-CimInstance instead)
        PSAvoidUsingWMICmdlet                       = @{
            Enable = $true
        }
        
        # Avoid using empty catch blocks
        PSAvoidUsingEmptyCatchBlock                 = @{
            Enable = $true
        }
        
        # Avoid using Invoke-Expression (security risk)
        PSAvoidUsingInvokeExpression                = @{
            Enable = $true
        }
        
        # Variables should be properly initialized and used
        PSUseDeclaredVarsMoreThanAssignments        = @{
            Enable = $true
        }
        
        # Avoid global variables (use proper scoping)
        PSAvoidGlobalVars                           = @{
            Enable = $true
        }
        
        # Avoid using deprecated manifest fields
        PSAvoidUsingDeprecatedManifestFields        = @{
            Enable = $true
        }
        
        # Missing module manifest fields (Version, Author, Description, LicenseUri)
        PSMissingModuleManifestField                = @{
            Enable = $true
        }
        
        # Avoid trailing whitespace
        PSAvoidTrailingWhitespace                   = @{
            Enable = $true
        }
        
        # Avoid semicolons as line terminators (not idiomatic PowerShell)
        PSAvoidSemicolonsAsLineTerminators          = @{
            Enable = $true
        }
        
        # Avoid using break in finally block
        PSAvoidUsingBrokenHash                      = @{
            Enable = $true
        }
        
        # ------------------------------------------------------------------------
        # SECURITY RULES
        # ------------------------------------------------------------------------
        
        # Use PSCredential type instead of Username/Password parameters
        PSUsePSCredentialType                       = @{
            Enable = $true
        }
        
        # Avoid hardcoded computer names (information disclosure)
        PSAvoidUsingComputerNameHardcoded           = @{
            Enable = $true
        }
        
        # Avoid using username and password parameters separately
        PSAvoidUsingUsernameAndPasswordParams       = @{
            Enable = $true
        }
        
        # ------------------------------------------------------------------------
        # CODE FORMATTING RULES
        # ------------------------------------------------------------------------
        
        # Use consistent indentation (4 spaces)
        PSUseConsistentIndentation                  = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }
        
        # Use consistent whitespace
        PSUseConsistentWhitespace                   = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $true  # Changed to true for cleaner code
            CheckSeparator                  = $true
            CheckParameter                  = $false
        }

        # Validate unused parameters
        PSReviewUnusedParameter                     = @{
            Enable = $true
        }

        # Enforce correct casing for cmdlets and keywords
        PSUseCorrectCasing                          = @{
            Enable = $true
        }
        
        # Use proper brace placement (K&R style - opening brace on same line)
        PSPlaceOpenBrace                            = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        
        PSPlaceCloseBrace                           = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        
        # Align assignment statements (disabled - too strict for varied code patterns)
        PSAlignAssignmentStatement                  = @{
            Enable         = $false
            CheckHashtable = $false
        }
        
        # Enforce using literal path when possible
        PSUseLiteralInitializerForHashtable         = @{
            Enable = $true
        }
        
        # Use BOM encoding for non-ASCII characters
        PSUseUTF8EncodingForHelpFile                = @{
            Enable = $true
        }
        
        # ------------------------------------------------------------------------
        # DOCUMENTATION RULES
        # ------------------------------------------------------------------------
        
        # Provide comment-based help for all functions
        PSProvideCommentHelp                        = @{
            Enable                  = $true
            ExportedOnly            = $false  # Require help for all functions, not just exported
            BlockComment            = $true
            VSCodeSnippetCorrection = $false
            Placement               = 'before'
        }
        
        # ------------------------------------------------------------------------
        # COMPATIBILITY RULES
        # ------------------------------------------------------------------------
        
        # Use compatible syntax for target PowerShell versions
        PSUseCompatibleSyntax                       = @{
            Enable         = $true
            TargetVersions = @(
                '7.0',   # PowerShell 7.0 (Windows/Linux/macOS)
                '7.1',   # PowerShell 7.1
                '7.2',   # PowerShell 7.2 LTS
                '7.3',   # PowerShell 7.3
                '7.4'    # PowerShell 7.4 LTS
            )
        }
        
        # Check cmdlet compatibility across PowerShell versions
        PSUseCompatibleCmdlets                      = @{
            Enable        = $true
            Compatibility = @(
                'core-7.0-windows',
                'core-7.2-windows',
                'core-7.4-windows'
            )
        }
        
        # Check command compatibility
        PSUseCompatibleCommands                     = @{
            Enable         = $true
            TargetProfiles = @(
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
        
        # Check .NET type compatibility
        PSUseCompatibleTypes                        = @{
            Enable         = $true
            TargetProfiles = @(
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
        
        # ------------------------------------------------------------------------
        # PERFORMANCE RULES
        # ------------------------------------------------------------------------
        
        # Avoid using `+` operator for string concatenation in loops
        PSAvoidUsingPlusForStringConcatenation      = @{
            Enable = $true
        }
        
        # Use Process block for pipeline-aware functions
        PSUseProcessBlockForPipelineCommand         = @{
            Enable = $true
        }
    }
    
    # ============================================================================
    # ADDITIONAL CONFIGURATION
    # ============================================================================
    
    # Custom rule paths (if any custom rules are added in the future)
    # CustomRulePath = @()
    
    # Include specific rules (when using custom rules)
    # IncludeRules = @()
}
