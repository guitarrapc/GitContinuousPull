Import-Module GitContinuousPull -Force -Verbose

# Automatically Clone -> Pull GitHub repository
$param = @(
    @{
        RepositoryUrl = "https://github.com/guitarrapc/valentia.git"
        GitPath = "C:\Repository"
        LogPath = "C:\logs\valentia"
        LogName = "valentia-$((Get-Date).ToString("yyyyMMdd-HHmmss")).log"
        PostAction = {PowerShell -File "C:\Repository\valentia\valentia\Tools\install.ps1"}
    }
)

$param | %{Start-GitContinuousPull @_ -Verbose}
