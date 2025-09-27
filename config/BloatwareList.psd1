# BloatwareList.psd1 - Centralized bloatware definitions for Windows Maintenance Automation
# This file contains categorized lists of bloatware applications that can be removed
# Update this file to add/remove bloatware entries as needed

@{
    # Microsoft built-in bloatware applications
    MicrosoftBloatware = @(
        "Microsoft.3DBuilder"
        "Microsoft.BingFinance"
        "Microsoft.BingFoodAndDrink"
        "Microsoft.BingHealthAndFitness"
        "Microsoft.BingNews"
        "Microsoft.BingSports"
        "Microsoft.BingTravel"
        "Microsoft.BingWeather"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.HelpAndTips"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftPowerBIForWindows"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MinecraftEducationEdition"
        "Microsoft.MinecraftUWP"
        "Microsoft.MixedReality.Portal"
        "Microsoft.MSN"
        "Microsoft.NetworkSpeedTest"
        "Microsoft.News"
        "Microsoft.Office.OneNote"
        "Microsoft.Office.Sway"
        "Microsoft.OneConnect"
        "Microsoft.PowerAutomateDesktop"
        "Microsoft.Print3D"
        "Microsoft.StickyNotes"
        "Microsoft.ToDo"
        "Microsoft.Wallet"
        "Microsoft.Whiteboard"
        "Microsoft.WindowsFeedback"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsReadingList"
        "Microsoft.WindowsTips"
    )

    # OEM-specific bloatware from various manufacturers
    OEMBloatware = @(
        # Acer
        "Acer.AcerPowerManagement"
        "Acer.AcerQuickAccess"
        "Acer.AcerUEIPFramework"
        "Acer.AcerUserExperienceImprovementProgram"
        # ASUS
        "ASUS.ASUSGiftBox"
        "ASUS.ASUSLiveUpdate"
        "ASUS.ASUSSplendidVideoEnhancementTechnology"
        "ASUS.ASUSWebStorage"
        "ASUS.ASUSZenAnywhere"
        "ASUS.ASUSZenLink"
        "ASUS.MyASUS"
        "ASUS.GlideX"
        "ASUS.ASUSDisplayControl"
        # Dell
        "Dell.CustomerConnect"
        "Dell.DellDigitalDelivery"
        "Dell.DellFoundationServices"
        "Dell.DellHelpAndSupport"
        "Dell.DellMobileConnect"
        "Dell.DellPowerManager"
        "Dell.DellProductRegistration"
        "Dell.DellSupportAssist"
        "Dell.DellUpdate"
        "Dell.MyDell"
        "Dell.DellOptimizer"
        "Dell.CommandUpdate"
        # HP
        "HP.HP3DDriveGuard"
        "HP.HPAudioSwitch"
        "HP.HPClientSecurityManager"
        "HP.HPConnectionOptimizer"
        "HP.HPDocumentation"
        "HP.HPDropboxPlugin"
        "HP.HPePrintSW"
        "HP.HPJumpStart"
        "HP.HPJumpStartApps"
        "HP.HPJumpStartLaunch"
        "HP.HPRegistrationService"
        "HP.HPSupportSolutionsFramework"
        "HP.HPSureConnect"
        "HP.HPSystemEventUtility"
        "HP.HPWelcome"
        "HP.HPSmart"
        "HP.HPQuickActions"
        "HewlettPackard.SupportAssistant"
        # Lenovo
        "Lenovo.AppExplorer"
        "Lenovo.LenovoCompanion"
        "Lenovo.LenovoExperienceImprovement"
        "Lenovo.LenovoFamilyCloud"
        "Lenovo.LenovoHotkeys"
        "Lenovo.LenovoMigrationAssistant"
        "Lenovo.LenovoModernIMController"
        "Lenovo.LenovoServiceBridge"
        "Lenovo.LenovoSolutionCenter"
        "Lenovo.LenovoUtility"
        "Lenovo.LenovoVantage"
        "Lenovo.LenovoVoice"
        "Lenovo.LenovoWiFiSecurity"
        "Lenovo.LenovoNow"
        "Lenovo.ImController.PluginHost"
    )

    # Gaming and social media applications
    GamingSocial = @(
        "king.com.BubbleWitch"
        "king.com.BubbleWitch3Saga"
        "king.com.CandyCrush"
        "king.com.CandyCrushFriends"
        "king.com.CandyCrushSaga"
        "king.com.CandyCrushSodaSaga"
        "king.com.FarmHeroes"
        "king.com.FarmHeroesSaga"
        "Gameloft.MarchofEmpires"
        "G5Entertainment.HiddenCity"
        "RandomSaladGamesLLC.SimpleSolitaire"
        "RoyalRevolt2.RoyalRevolt2"
        "WildTangent.WildTangentGamesApp"
        "WildTangent.WildTangentHelper"
        "Facebook.Facebook"
        "Instagram.Instagram"
        "LinkedIn.LinkedIn"
        "TikTok.TikTok"
        "Twitter.Twitter"
        "Discord.Discord"
        "Snapchat.Snapchat"
        "Telegram.TelegramDesktop"
    )

    # Xbox and gaming-related applications
    XboxGaming = @(
        "Microsoft.Xbox.TCUI"
        "Microsoft.XboxApp"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.GamingApp"
        "Microsoft.XboxGameCallableUI"
    )

    # Third-party security/antivirus bloatware
    SecurityBloatware = @(
        "Avast.AvastFreeAntivirus"
        "AVG.AVGAntiVirusFree"
        "Avira.Avira"
        "ESET.ESETNOD32Antivirus"
        "Kaspersky.Kaspersky"
        "McAfee.LiveSafe"
        "McAfee.Livesafe"
        "McAfee.SafeConnect"
        "McAfee.Security"
        "McAfee.WebAdvisor"
        "Norton.OnlineBackup"
        "Norton.Security"
        "Norton.NortonSecurity"
        "Malwarebytes.Malwarebytes"
        "IOBit.AdvancedSystemCare"
        "IOBit.DriverBooster"
        "Piriform.CCleaner"
        "PCAccelerate.PCAcceleratePro"
        "PCOptimizer.PCOptimizerPro"
        "Reimage.ReimageRepair"
    )

    # Communication and messaging applications
    Communication = @(
        "Microsoft.Messaging"
        "Microsoft.People"
        "Microsoft.SkypeApp"
        "Microsoft.YourPhone"
    )

    # Media and entertainment applications
    MediaEntertainment = @(
        "Microsoft.WindowsAlarms"
        "Microsoft.WindowsCamera"
        "Microsoft.WindowsMaps"
        "Microsoft.WindowsSoundRecorder"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
    )

    # Legacy and deprecated applications
    LegacyApps = @(
        # Add any legacy applications here that are no longer needed
    )

    # Custom user-defined bloatware (can be added via config)
    CustomBloatware = @(
        # This can be populated from $global:Config.CustomBloatwareList
    )
}