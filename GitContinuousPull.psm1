#Requires -Version 3.0

function Start-GitContinuousPull
{
<#
.Synopsis
    Git Automation simple module for both private/public respository.
.DESCRIPTION
    You can automate git clone / pull with simple function execution.
    Prerequisite:
        1. You need to install git
        2. You need to install git-credential-winstore
        3. Set path to the git-credential-winstore in the .gitconfig
        4. You should set your git password to Windows Credential Manager
.EXAMPLE
    Import-Module Start-Git
    $param = @(
        @{
            RepositoryUrl = "https://github.com/guitarrapc/valentia.git"
            GitPath = "C:\Repository"
            LogPath = "C:\logs\valentia"
            LogName = "valentia-$((Get-Date).ToString("yyyyMMdd-HHmmss")).log"
            PostAction = {PowerShell -File "C:\Repository\valentia\valentia\Tools\install.ps1"}
        }
    )
    # this will clone valentia into C:\Repository\valentia and pull it.

$param | %{Start-Git @_ -Verbose}

.NOTES
    # .gitconfig sample
    [credential]
	    helper = !'C:\\Users\\USERNAME\\AppData\\Roaming\\GitCredStore\\git-credential-winstore.exe'
#>
    [OutputType([String[]])]
    [CmdletBinding(  
        SupportsShouldProcess = $false,
        ConfirmImpact = "none",
        DefaultParameterSetName = "")]
    param
    (
        [Parameter(HelpMessage = "Git Repository Url", Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [uri[]]$RepositoryUrl,

        [Parameter(HelpMessage = "Input Full path of Git REpository Parent Folder", Position = 1, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$GitPath,
 
        [Parameter(HelpMessage = "Input path of Log", Position = 2, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$LogPath,

        [Parameter(HelpMessage = "Input name of Log", Position = 3, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogName,

        [Parameter(HelpMessage = "Script Block to execute when git detect change.", Position = 4, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [scriptBlock[]]$PostAction
    )

    process
    {
        # Log Setup
        $script:log = LogSetup -LogPath $LogPath -LogName $LogName

        # Git process checking.
        KillGit

        # Git credential checking.
        GitCred

        for ($i = 0; $i -lt $GitPath.Count; $i++)
        {
            # initialize first clone flag
            $script:firstClone = $false

            # Execute
            GitClone -Path $GitPath[$i] -RepositoryUrl $RepositoryUrl[$i]
            GitPull -Path $GitPath[$i] -RepositoryUrl $RepositoryUrl[$i]

            # Normal handling
            if (Test-Path $script:log.tempFullPath)
            {
                $success = Get-Content $script:log.tempFullPath |WriteMessage
                Remove-Item $script:log.tempFullPath -Force
            }

            # Error handling
            if (Test-Path $script:log.tempErrorFullPath)
            {
                $fail = Get-Content $script:log.tempErrorFullPath | WriteMessage
                Remove-Item $script:log.tempErrorFullPath -Force
            }

            # PostAction
            if ($PostAction.Count -eq 0){ return; }
            switch ($true)
            {
                $script:firstClone{
                    "First time clone detected. Execute PostAction" | WriteMessage
                    $PostAction | %{& $_}
                }
                (("Already up-to-date." -ne ($success | select -Last 1)) -and ($null -eq $fail)){
                    "Pull detected change. Execute PostAction" | WriteMessage
                    $PostAction | %{& $_}
                }
                default {}
            }
        }
    }
    
    Begin
    {
        # argument check
        if ($RepositoryUrl.Count -ne $GitPath.Count){ throw New-Object System.ArgumentException ("Argument for Repogitory & GitPath not match exception.") }

        function LogSetup ($LogPath, $LogName)
        {
            if (-not (Test-Path $LogPath))
            {
                New-Item -ItemType Directory -Path $LogPath
            }
            return @{
                FullPath = Join-Path $LogPath $logName
                tempFullPath = Join-Path $LogPath ("temp" + $logName)
                tempErrorFullPath = Join-Path $LogPath ("tempError" + $logName)
            }
        }

        function KillGit
        {
            $IsgitExist = Get-Process | where Name -like "git*" | Stop-Process -Force -PassThru
            if ($IsgitExist)
            {
                "git process found. Killed process Name '{0}'" -f ($IsgitExist.Name -join ",") | WriteMessage
            }
        }
                    
        function GitCred
        {
            if ($null -eq (Get-ValentiaCredential -TargetName "git:https://GitHub.com" -Type Generic -ErrorAction SilentlyContinue))
            {
                "git credential was missing. Set git credential to Windows Credential Manager." | WriteMessage
                $Credential = Get-ValentiaCredential -TargetName git
                Set-ValentiaCredential -TargetName "git:https://GitHub.com" -Credential $Credential -Type Generic
            }
        }

        function NewFolder ([string]$Path)
        {
            if (-not (Test-Path $Path))
            {
                $script:firstClone = $true
                New-Item -Path $Path -ItemType Directory -Force | Out-String | Write-Verbose
            }
        }

        function GetRepositoryName ([uri]$RepositoryUrl)
        {
            return (Split-Path $RepositoryUrl -Leaf) -split "\.git" | select -First 1
        }

        function GitClone ([string]$Path, [uri]$RepositoryUrl)
        {
            try
            {
                # Folder checking
                $repository = GetRepositoryName -RepositoryUrl $RepositoryUrl
                NewFolder -Path (Join-Path $Path $repository)

                Push-Location -Path $Path
                "{0} : Cloning Repository '{1}'" -f (Get-Date), $repository |WriteMessage
                $gitClone = Start-Process "git" -ArgumentList "clone $RepositoryUrl" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $script:log.tempFullPath -RedirectStandardError $script:log.tempErrorFullPath
            }
            finally
            {
                Pop-Location
            }
        }

        function GitPull ([string]$Path, [uri]$RepositoryUrl)
        {
            try
            {
                $repository = GetRepositoryName -RepositoryUrl $RepositoryUrl

                Push-Location -Path (Join-Path $Path $repository)
                "{0} : Pulling Repository '{1}'" -f (Get-Date), $repository | WriteMessage
                $gitPull = Start-Process "git" -ArgumentList "pull" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $script:log.tempFullPath -RedirectStandardError $script:log.tempErrorFullPath            
            }
            finally
            {
                Pop-Location
            }
        }

        filter WriteMessage
        {
            $_ | Add-Content -PassThru -Path $script:log.FullPath -Force
        }
    }
}

Export-ModuleMember -Function *