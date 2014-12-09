#Requires -Version 3.0

function Start-GitContinuousPull
{
<#
.Synopsis
    Git Automation simple module for both private/public respository.
.DESCRIPTION
    You can automate git clone -> pull -> PostAction with simple definition.
    This would be usefull to temporary continuous execution without CI.

    Make sure you have don Prerequisites.
        1. You need to install git.
        2. Set git-credential-wincred as a Credential helper.
        3. Set your git password to Windows Credential Manager as TargetName : git

    See NOTES for the details.
.EXAMPLE
    Import-Module GitContinuousPull
    $param = @(
        @{
            RepositoryUrl = "https://github.com/guitarrapc/valentia.git"
            GitPath = "C:\Repository"
            LogFolderPath = "C:\logs\GitContinuousPull"
            LogName = "valentia-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss")
            PostAction = {PowerShell -File "C:\Repository\valentia\valentia\Tools\install.ps1"}
        }
    )
    $param | %{Start-GitContinuousPull @_ -Verbose}
    # this will clone valentia into C:\Repository\valentia and pull it to the latest commit.

.NOTES
    # 1. Install git. You may find it by Chocolatey, Git for Windows, SourceTree or other git tools. Below is sample to install git through chocolatey.
    cinst git

    # 2. Run this to add git-credential-wincred into .gitconfig.
    # set git-credential-wincred into .girhub. Now git.exe read github credential from Windows Credential Manager.
    git config --global credential.helper wincred

    # 3. You need to set git credential into Credential Manager as name : git
    # set your github authenticated user/password
    Set-ValentiaCredential -TargetName git
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
 
        [Parameter(HelpMessage = "Input path of Log Folder", Position = 2, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$LogFolderPath,

        [Parameter(HelpMessage = "Input name of Log", Position = 3, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogName,

        [Parameter(HelpMessage = "Script Block to execute when git detect change.", Position = 4, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [scriptBlock[]]$PostAction
    )

    process
    {
        # Log Setup
        LogSetup -LogPath $LogFolderPath -LogName $LogName

        # Git process checking.
        KillGit

        # Git credential checking.
        GitCred

        for ($i = 0; $i -lt $GitPath.Count; $i++)
        {
            Write-Verbose ("Starting for RepotirotyUrl '{0}'" -f $RepositoryUrl)

            # initialize
            $GitContinuousPull.firstClone = $false
            $GitContinuousPull.Output = $GitContinuousPull.ErrorOutput = New-Object "System.Collections.Generic.List[string]"

            # Execute
            GitClone -Path $GitPath[$i] -RepositoryUrl $RepositoryUrl[$i]
            GitPull -Path $GitPath[$i] -RepositoryUrl $RepositoryUrl[$i]

            # Normal handling
            if ($GitContinuousPull.Output.Count -ne 0){ $GitContinuousPull.Output | WriteMessage }

            # Error handling
            $isError = $GitContinuousPull.ErrorOutput.ToString() -ne $GitContinuousPull.Output.ToString()
            if (($GitContinuousPull.ErrorOutput.Count -ne 0) -and $isError){ $GitContinuousPull.ErrorOutput | WriteMessage }
            
            # PostAction
            if ($PostAction.Count -eq 0){ return; }
            switch ($true)
            {
                $GitContinuousPull.firstClone {
                    "First time clone detected. Execute PostAction." | WriteMessage
                    $PostAction | %{& $_}
                }
                (($GitContinuousPull.ExitCode -eq 0) -and (($GitContinuousPull.Output | select -Last 1) -notmatch "Already up-to-date.")) {
                    "Pull detected change. Execute PostAction." | WriteMessage
                    $PostAction | %{& $_}
                }
                default { "None of change for git detected. Skip PostAction."  | WriteMessage }
            }
        }
    }
    
    Begin
    {
        # Argument check
        if ($RepositoryUrl.Count -ne $GitPath.Count){ throw New-Object System.ArgumentException ("Argument for Repogitory & GitPath not match exception.") }

        function LogSetup ($LogPath, $LogName)
        {
            if (-not (Test-Path $LogPath))
            {
                New-Item -ItemType Directory -Path $LogPath | Format-Table | Out-String | Write-Verbose
            }
            $GitContinuousPull.log =  @{
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
            $ErrorActionPreference = "Continue"

            try
            {
                $credential = Get-ValentiaCredential -TargetName git
                $targetName = "git:https://{0}@github.com" -f $credential.UserName

                # Check git credential is already exist.
                if ((Get-ValentiaCredential -TargetName $targetName -Type Generic -ErrorAction SilentlyContinue | measure).Count -eq 1)
                {
                    "git credential found from Windows Credential Manager as TargetName : '{0}'." -f $targetName | WriteMessage; 
                    return; 
                }
                else
                {          
                    # Set git credential from backup credential
                    "git credential was missing. Set git credential to Windows Credential Manager as TargetName : {0}." -f $targetName | WriteMessage
                    $result = Set-ValentiaCredential -TargetName $targetName -Credential $Credential -Type Generic

                    # result
                    if ($result -eq $false){ throw New-Object System.InvalidOperationException ("Failed to set credential. Make sure you have set Windows Credential as targetname 'git'.") }
                    "Set credential for github into Windows Credential Manager completed." | WriteMessage
                    return;
                }
            }
            finally
            {
                $ErrorActionPreference = $GitContinuousPull.preference.ErrorActionPreference.Original
            }
        }

        function NewFolder ([string]$Path)
        {
            if (Test-Path $Path){ return $false; }

            $GitContinuousPull.firstClone = $true
            New-Item -Path $Path -ItemType Directory -Force | Out-String | Write-Verbose
            return $true
        }

        function GetRepositoryName ([uri]$RepositoryUrl)
        {
            return (Split-Path $RepositoryUrl -Leaf) -split "\.git" | select -First 1
        }

        function GitClone ([string]$Path, [uri]$RepositoryUrl)
        {
            # Folder checking
            $repository = GetRepositoryName -RepositoryUrl $RepositoryUrl
            $created = NewFolder -Path (Join-Path $Path $repository)
            if ($created -eq $false){ "Repository already cloned. Skip clone repository : '{0}'." -f $repository | WriteMessage; return; }

            # git clone
            "Cloning Repository '{0}' to '{1}'" -f $repository, $Path | WriteMessage
            GitCommand -Arguments "clone $RepositoryUrl" -WorkingDirectory $Path
        }

        function GitPull ([string]$Path, [uri]$RepositoryUrl)
        {
            $repository = GetRepositoryName -RepositoryUrl $RepositoryUrl

            # git pull
            "Pulling Repository '{0}' to '{1}'" -f $repository, $Path | WriteMessage
            GitCommand -Arguments "pull" -WorkingDirectory (Join-Path $Path $repository)
        }

        function GitCommand ([string]$Arguments, [string]$WorkingDirectory)
        {
            try
            {
                # prerequisites
                $psi = New-object System.Diagnostics.ProcessStartInfo 
                $psi.CreateNoWindow = $true
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.FileName = "git.exe"
                $psi.Arguments = $Arguments
                $psi.WorkingDirectory = $WorkingDirectory

                # execution
                $process = New-Object System.Diagnostics.Process 
                $process.StartInfo = $psi
                $process.Start() > $null
                $process.WaitForExit() 
                $process.StandardOutput.ReadToEnd() | where {"" -ne $_} | %{$GitContinuousPull.Output.Add($_)}
                $process.StandardError.ReadToEnd() | where {"" -ne $_} | %{$GitContinuousPull.ErrorOutput.Add($_)}
                $GitContinuousPull.ExitCode = $process.ExitCode
            }
            finally
            {
                if ($null -ne $process){ $process.Dispose() }
            }
        }

        filter WriteMessage
        {
            $message = "[{0}][{1}]" -f (Get-Date), $_
            $message `
            | %{
                Write-Host $_ -ForegroundColor Green
                $_ | Out-File -FilePath $GitContinuousPull.log.FullPath -Encoding $GitContinuousPull.fileEncode -Force -Append
            }
        }
    }
}


#-- Private Loading Module Parameters --#
# contains default base configuration, may not be override without version update.
$script:GitContinuousPull = [ordered]@{}
$GitContinuousPull.name = 'GitContinuousPull'
$GitContinuousPull.modulePath = Split-Path -parent $MyInvocation.MyCommand.Definition
$GitContinuousPull.fileEncode = [Microsoft.PowerShell.Commands.FileSystemCmdletProviderEncoding]'utf8'

# contains PS Build-in Preference status
$GitContinuousPull.preference = [ordered]@{
    ErrorActionPreference = @{
        original = $ErrorActionPreference
        custom   = 'Stop'
    }
    DebugPreference       = @{
        original = $DebugPreference
        custom   = 'SilentlyContinue'
    }
    VerbosePreference     = @{
        original = $VerbosePreference
        custom   = 'SilentlyContinue'
    }
    ProgressPreference = @{
        original = $ProgressPreference
        custom   = 'SilentlyContinue'
    }
}

# Script variables initialization
$GitContinuousPull.log = @{}
$GitContinuousPull.firstClone = $false
$GitContinuousPull.ExitCode = 0

Export-ModuleMember -Function * -Variable $GitContinuousPull.name