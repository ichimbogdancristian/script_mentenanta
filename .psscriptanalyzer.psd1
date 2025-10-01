@{
    # PSScriptAnalyzer settings tailored to this repository's guidance
    IncludeRules = @(
        'PSAvoidUsingCmdletAliases',
        'PSUseApprovedVerbs',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSProvideCommentHelp',
        'PSUseDeclaredVarsMoreThanAssigments'
    )

    Rules = @{
        PSAvoidUsingCmdletAliases = @{ Enable = $true }
        PSUseApprovedVerbs = @{ 
            Enable = $true;
            ApprovedVerbs = @('Get','Set','New','Remove','Add','Install','Uninstall','Test','Start','Stop','Enable','Disable','Invoke','Export','Import')
        }
        PSUseShouldProcessForStateChangingFunctions = @{ Enable = $true }
        PSProvideCommentHelp = @{ Enable = $true }
        PSUseDeclaredVarsMoreThanAssigments = @{ Enable = $true }
    }

    Settings = @{
        Recurse = $true
    }
}
