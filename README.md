# Read Me Fast

GitContinuousPull will offer simple continuous delivery.

This can do only simple thing, but something enough for some usage. 

- Clone
- Pull
- PostAction

Prerequisite
----

    1. You need to install git
    2. You need to install git-credential-winstore
    3. Set path to the git-credential-winstore in the .gitconfig
    4. You should set your git password to Windows Credential Manager

Sample .gitconfig
----

You must specify full path to the git-credential-winstore.exe in the ```.git.config```

```
[credential]
	helper = !'C:\\Users\\USERNAME\\AppData\\Roaming\\GitCredStore\\git-credential-winstore.exe'
```

Usage
----

Automate valentia delivery for localhost.

```PowerShell
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
```