# EssentialAppsList.psd1 - Centralized essential applications definitions for Windows Maintenance Automation
# This file contains categorized lists of essential applications that can be installed
# Update this file to add/remove essential applications as needed

@{
    # Web browsers
    WebBrowsers = @(
        @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome'; Category = 'Browser' },
        @{ Name = 'Mozilla Firefox'; Winget = 'Mozilla.Firefox'; Choco = 'firefox'; Category = 'Browser' },
        @{ Name = 'Microsoft Edge'; Winget = 'Microsoft.Edge'; Choco = 'microsoft-edge'; Category = 'Browser' }
    )

    # Document and productivity tools
    DocumentTools = @(
        @{ Name = 'Adobe Acrobat Reader'; Winget = 'Adobe.Acrobat.Reader.64-bit'; Choco = 'adobereader'; Category = 'Document' },
        @{ Name = 'PDF24 Creator'; Winget = 'geeksoftwareGmbH.PDF24Creator'; Choco = 'pdf24'; Category = 'Document' },
        @{ Name = 'Notepad++'; Winget = 'Notepad++.Notepad++'; Choco = 'notepadplusplus'; Category = 'Editor' }
    )

    # File management and compression
    FileManagers = @(
        @{ Name = 'Total Commander'; Winget = 'Ghisler.TotalCommander'; Choco = 'totalcommander'; Category = 'FileManager' },
        @{ Name = 'WinRAR'; Winget = 'RARLab.WinRAR'; Choco = 'winrar'; Category = 'Compression' },
        @{ Name = '7-Zip'; Winget = '7zip.7zip'; Choco = '7zip'; Category = 'Compression' }
    )

    # System and development tools
    SystemTools = @(
        @{ Name = 'PowerShell 7'; Winget = 'Microsoft.Powershell'; Choco = 'powershell'; Category = 'System' },
        @{ Name = 'Windows Terminal'; Winget = 'Microsoft.WindowsTerminal'; Choco = 'microsoft-windows-terminal'; Category = 'System' },
        @{ Name = 'Java 8 Update'; Winget = 'Oracle.JavaRuntimeEnvironment'; Choco = 'javaruntime'; Category = 'Runtime' },
        @{ Name = 'Sysmon'; Winget = $null; Choco = $null; DownloadUrl = 'https://download.sysinternals.com/files/Sysmon.zip'; Category = 'Security' }
    )

    # Communication and email
    Communication = @(
        @{ Name = 'Mozilla Thunderbird'; Winget = 'Mozilla.Thunderbird'; Choco = 'thunderbird'; Category = 'Email' }
    )

    # Remote access tools
    RemoteAccess = @(
        @{ Name = 'TeamViewer'; Winget = 'TeamViewer.TeamViewer'; Choco = 'teamviewer'; Category = 'RemoteDesktop' },
        @{ Name = 'RustDesk'; Winget = 'RustDesk.RustDesk'; Choco = 'rustdesk'; Category = 'RemoteDesktop' },
        @{ Name = 'UltraViewer'; Winget = 'DucFabulous.UltraViewer'; Choco = 'ultraviewer'; Category = 'RemoteDesktop' }
    )

    # Media and entertainment
    Media = @(
        @{ Name = 'VideoLAN VLC'; Winget = 'VideoLAN.VLC'; Choco = 'vlc'; Category = 'Media' }
    )

    # Custom user-defined essential applications (can be added via config)
    CustomEssentialApps = @(
        # This can be populated from $global:Config.CustomEssentialApps
    )
}