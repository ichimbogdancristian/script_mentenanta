# PSScriptAnalyzer settings for Windows Maintenance Automation System
# Version: 3.1
# Date: December 1, 2025

@{
    # Severity levels to include
    Severity            = @('Error', 'Warning', 'Information')
    
    # Include default rules
    IncludeDefaultRules = $true
    
    # Exclude specific rules that don't apply to this project
    ExcludeRules        = @(
        # Allow usage of Write-Host for user-facing UI messages
        'PSAvoidUsingWriteHost',
        
        # Allow ConvertTo-SecureString with -AsPlainText (used in credential handling)
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        
        # Allow hardcoded credentials in test/example code
        'PSAvoidUsingPlainTextForPassword',
        
        # Allow using positional parameters in internal functions
        'PSAvoidUsingPositionalParameters'
    )
    
    # Custom rules configuration
    Rules               = @{
        # Use approved verbs only
        PSUseApprovedVerbs                   = @{
            Enable = $true
        }
        
        # Cmdlet aliases should not be used in scripts
        PSAvoidUsingCmdletAliases            = @{
            Enable = $true
        }
        
        # Use consistent indentation (4 spaces)
        PSUseConsistentIndentation           = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }
        
        # Use consistent whitespace
        PSUseConsistentWhitespace            = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator                  = $true
            CheckParameter                  = $false
        }
        
        # Enforce using literal path when possible
        PSUseLiteralInitializerForHashtable  = @{
            Enable = $true
        }
        
        # Require [CmdletBinding()] for advanced functions
        PSUseCmdletCorrectly                 = @{
            Enable = $true
        }
        
        # Avoid using deprecated commands
        PSAvoidUsingDeprecatedManifestFields = @{
            Enable = $true
        }
        
        # Use compatible syntax
        PSUseCompatibleSyntax                = @{
            Enable         = $true
            TargetVersions = @(
                '7.0',
                '7.1',
                '7.2',
                '7.3',
                '7.4'
            )
        }
        
        # Variables should be properly initialized
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }
        
        # Use OutputType attribute when appropriate
        PSUseOutputTypeCorrectly             = @{
            Enable = $true
        }
        
        # Use proper brace placement
        PSPlaceOpenBrace                     = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        
        PSPlaceCloseBrace                    = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        
        # Align assignment statements
        PSAlignAssignmentStatement           = @{
            Enable         = $false  # Disabled - can be too strict for varied code
            CheckHashtable = $false
        }
        
        # Use singular nouns for cmdlet names
        PSUseSingularNouns                   = @{
            Enable = $true
        }
        
        # Provide comment-based help
        PSProvideCommentHelp                 = @{
            Enable                  = $true
            ExportedOnly            = $false
            BlockComment            = $true
            VSCodeSnippetCorrection = $false
            Placement               = 'before'
        }
    }
}
