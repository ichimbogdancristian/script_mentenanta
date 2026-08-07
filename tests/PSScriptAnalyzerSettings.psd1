@{
    # PSScriptAnalyzer settings for tests/ ONLY.
    #
    # Test code never ships to a target machine and never runs there: script.bat downloads
    # the repo zip, the orchestrator imports only modules/, and Stage 5 deletes the whole
    # extracted tree. So the compatibility rules - which exist to protect the target-machine
    # runtime - have nothing to protect here, and they produce ~300 false positives because
    # PSScriptAnalyzer cannot see Pester's dynamically-bound Should parameters
    # (-Be / -Not / -Throw / -Because / -BeGreaterThan / -BeOfType / ...).
    #
    # The shipped code is still analysed with the strict settings in the repo root.

    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Pester's Should is a dynamic-parameter command; the compat profiles flag every
        # assertion in every test file.
        'PSUseCompatibleCommands',
        'PSUseCompatibleCmdlets',
        'PSUseCompatibleSyntax',
        'PSUseCompatibleTypes',

        # Pester test files are declarative blocks, not a module surface.
        'PSProvideCommentHelp',
        'PSUseSingularNouns',

        # $script:-scoped fixtures set in BeforeAll and read inside It are the documented
        # Pester 5+ pattern, but the analyzer reads them as assigned-but-never-used.
        'PSUseDeclaredVarsMoreThanAssignments',

        # Test helpers legitimately create fixture files and temp directories. Supporting
        # -WhatIf on a fixture builder is meaningless, and these helpers never touch machine
        # state - only the per-run temp folder they clean up in AfterAll.
        'PSUseShouldProcessForStateChangingFunctions',

        # Formatting-only; not worth failing a test file over.
        'PSUseConsistentWhitespace',
        'PSAvoidTrailingWhitespace'
    )
}
