# Read Me First

GitContinuousPull will offer simple continuous delivery.

This can do only simple thing, but something enough for some usage. 

- Clone
- Pull
- PostAction

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

Prerequisite
----

1. You need to install git
2. You need to install git-credential-winstore
3. Set path to the git-credential-winstore in the .gitconfig
4. You should set your git password to Windows Credential Manager
5. [valentia](https://github.com/guitarrapc/valentia) is required as of dependencie module for Credential Management.

Installation
----

Open PowerShell or Command prompt, paste the text below and press Enter.

||
|----|
|powershell -NoProfile -ExecutionPolicy unrestricted -Command 'iex ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((irm "https://api.github.com/repos/guitarrapc/GitContinuousPull/contents/GitContinuousPull/Tools/RemoteInstall.ps1").Content))).Remove(0,1)'|

Set git-credential-wincred as helper to .gitconfig
----

Run following command to add helper information inside .gitconfig.

```
# set git-credential-wincred into .girhub. Now git.exe read github credential from Windows Credential Manager.
git config --global credential.helper wincred
```

Set git credential into Windows Credential Manager
----

Set your git credential to authenticate repository. This authentication will be used with git-credential-wincred.exe with TargetName ```git:https://USERNAME@github.com```.

Because of  ```git:https://USERNAME@github.com``` suddenly erased when git process crashed or any cause.

Module force you to set Credential TargetName as ```git``` for backup and auto restore github credential when ```git:https://USERNAME@github.com``` was flushed.

```PowerShell
# set your github authenticated user/password
Set-ValentiaCredential -TargetName git
```