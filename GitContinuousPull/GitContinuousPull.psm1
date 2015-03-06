#Requires -Version 3.0

#region Main function

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
    # Run as Administrator
    Import-Module GitContinuousPull -Force -Verbose

    # Automatically Clone -> Pull GitHub repository
    $param = @(
        @{
            RepositoryUrl = "https://github.com/guitarrapc/DSCResources.git"
            GitPath = "C:\Repository"
            LogFolderPath = "C:\logs\DSCResources"
            LogName = "$((Get-Date).ToString("yyyyMMdd-HHmmss")).log"
            PostAction = {Copy-Item -Recurse -Path "C:\Repository\DSCResources\Custom\GraniResource" -Destination 'C:\Program Files\WindowsPowerShell\Modules' -Force}
        }
    )

    $param | %{Start-GitContinuousPull @_ -Verbose}
    # this will clone DSCResources and copy GraniResource to Resource directory.

.EXAMPLE
    Import-Module GitContinuousPull -Force -Verbose

    # Automatically Clone -> Pull GitHub repository
    $param = @(
        @{
            RepositoryUrl = "https://github.com/guitarrapc/valentia.git"
            GitPath = "C:\Repository"
            LogFolderPath = "C:\logs\valentia"
            LogName = "$((Get-Date).ToString("yyyyMMdd-HHmmss")).log"
            PostAction = { . C:\Repository\valentia\valentia\Tools\install.ps1}
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
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Git Repository Url")]
        [uri]$RepositoryUrl,

        [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Git Branch Name. Default : master")]
        [ValidateNotNullOrEmpty()]
        [string]$Branch = "master",

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Input Full path of Git Repository Parent Folder")]
        [string]$GitPath,
 
        [Parameter(Position = 2, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Input path of Log Folder")]
        [string]$LogFolderPath,

        [Parameter(Position = 3, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Input name of Log")]
        [ValidateNotNullOrEmpty()]
        [string]$LogName,

        [Parameter(Position = 4, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Script Block to execute when git detect change.")]
        [scriptBlock[]]$PostAction,

        [Parameter(Position = 5, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Input Git target folder name to be created in local.")]
        [string]$GitFolderName = ""
    )

    process
    {
        # Log Setup
        LogSetup -LogPath $LogFolderPath -LogName $LogName

        # Git process checking.
        KillGit

        # Git credential checking.
        GitCred

        Write-Verbose ("Starting for RepotirotyUrl '{0}'" -f $RepositoryUrl)

        # initialize
        $GitContinuousPull.firstClone = $false

        $gitParameter = @{
            Path = $GitPath
            RepositoryUrl = $RepositoryUrl
            GitFolderName = $GitFolderName
        }
        # git clone
        GitClone @gitParameter
          
        # git submodule
        GitSubmoduleUpdate @gitParameter

        # git pull
        GitPull @gitParameter -Branch $Branch

        # PostAction
        if (($PostAction | measure).Count -eq 0){ return; }
        $lastLine = $GitContinuousPull.StandardOutput | select -Last 1
        Write-Verbose ("Last line of git command output : '{0}'" -f $lastLine)

        switch ($true)
        {
            $GitContinuousPull.firstClone
            {
                "First time clone detected. Execute PostAction." | WriteMessage
                $PostAction | %{& $_}
                return;
            }
            (($GitContinuousPull.ExitCode -eq 0) -and ($lastLine -notmatch "Already up-to-date."))
            {
                "Pull detected change. Execute PostAction." | WriteMessage
                $PostAction | %{& $_}
                return;
            }
            default
            {
                "None of change for git detected. Skip PostAction."  | WriteMessage
                return;
            }
        }
    }
    
    Begin
    {
        # Argument check
        if ($RepositoryUrl.Count -ne $GitPath.Count){ throw New-Object System.ArgumentException ("Argument for Repogitory & GitPath not match exception.") }
        if (-not $RepositoryUrl.AbsoluteUri.EndsWith(".git")){ throw New-Object System.ArgumentException ("Wrong argument string found exception. RepositoryUrl '{0}' not endwith '.git'." -f $RepositoryUrl.AbsoluteUri) }

        function KillGit
        {
            $IsgitExist = Get-Process | where Name -like "git*" | Stop-Process -Force -PassThru
            if ($IsgitExist.Count -ne 0)
            {
                $IsgitExist | %{ "git process found. Killed process Name : '{0}', Id : '{1}'" -f $_.Name, $_.Id | WriteMessage }
            }
        }
                    
        function GitCred
        {
            $credential = Get-ValentiaCredential -TargetName git
            if (($credential.UserName | measure).Count -eq 0){ throw New-Object System.NullReferenceException ("Could not find Windows Credential Manager record as Target Name 'git'. Make sure you have already set credential." ) }

            $targetName = @(
                # WinCred
                ("git:https://{0}@github.com" -f $credential.UserName),
                # WinStore
                "git:https://github.com"
            )

            foreach ($x in $targetName)
            {
                # Check git credential is already exist.
                if ((Get-ValentiaCredential -TargetName $x -Type Generic -ErrorAction SilentlyContinue | measure).Count -eq 0)
                {
                    # Set git credential from backup credential
                    "git credential was missing. Set git credential to Windows Credential Manager as TargetName : {0}." -f $x | WriteMessage
                    $result = Set-ValentiaCredential -TargetName $x -Credential $Credential -Type Generic

                    # result
                    if ($result -eq $false){ throw New-Object System.InvalidOperationException ("Failed to set credential. Make sure you have set Windows Credential as targetname 'git'.") }
                    "Set credential for github into Windows Credential Manager completed." | WriteMessage
                    continue;
                }

                # return without any action
                "git credential found from Windows Credential Manager as TargetName : '{0}'." -f $x | WriteMessage; 
            }
        }

        function NewFolder ([string]$Path)
        {
            if (Test-Path $Path){ return $false; }

            $GitContinuousPull.firstClone = $true
            New-Item -Path $Path -ItemType Directory -Force | Out-String | Write-Verbose
            return $true
        }

        function LogSetup ($LogPath, $LogName)
        {
            if (-not (Test-Path $LogPath))
            {
                New-Item -ItemType Directory -Path $LogPath | Format-Table | Out-String -Stream | Write-Verbose
            }
            $GitContinuousPull.log =  @{
                FullPath = Join-Path $LogPath $logName
                tempFullPath = Join-Path $LogPath ("temp" + $logName)
                tempErrorFullPath = Join-Path $LogPath ("tempError" + $logName)
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

#endregion

#region git credential on config helper

function Set-GitContinuousPullGitConfig
{
<#
.Synopsis
    Set .gitconfig for a credential.helper.
.DESCRIPTION
    You can select credential helper from WinCred or WinStore
.EXAMPLE
    Set-GitContinuousPullGitConfig -WinCred
    # set git-credential-wincred.exe as a credential.helper.
.EXAMPLE
    Set-GitContinuousPullGitConfig -WinStore
    # set git-credential-winstore.exe as a credential.helper. Make sure you have already placed exe in \Git\libexec\git-core\git-credential-winstore.exe
.EXAMPLE
    Set-GitContinuousPullGitConfig -WinStore -DownloadWinStore
    # set git-credential-winstore.exe as a credential.helper. Also download git-credential-winstore into \Git\libexec\git-core\git-credential-winstore.exe
#>
    [OutputType([string[]])]
    [CmdletBinding(DefaultParameterSetName = "wincred")]
    param
    (
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "wincred", HelpMessage = "Use git-credential-wincred for the credential.helper")]
        [switch]$WinCred,

        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "winstore",HelpMessage = "Use git-credential-winstore for the credential.helper")]
        [switch]$WinStore,

        [Parameter(Position = 1, Mandatory = $false, ParameterSetName = "winstore",HelpMessage = "Download git credential winstore from CodePlex. https://gitcredentialstore.codeplex.com/")]
        [switch]$DownloadWinStore
    )

    function SetGitCredentialHelper ([string]$helper)
    {
        Write-Verbose ("Setting {0} as a credential.helper in .gitconfig" -f $helper)
        . git config --global credential.helper $helper
        Write-Verbose "Complete writing credential.helper into .gitconfig"
    }

    function DownloadWinStore
    {
        $outpath = 'C:\Program Files (x86)\Git\libexec\git-core\git-credential-winstore.exe'
        Write-Verbose ("Downloading git-credential-winstore.exe from CodePlex and place it in git path '{0}'." -f $outpath)
        Start-Process -Verb runas -FilePath PowerShell -ArgumentList "-Command Invoke-RestMethod -Method Get -Uri https://gitcredentialstore.codeplex.com/downloads/get/640464# -OutFile 'C:\Program Files (x86)\Git\libexec\git-core\git-credential-winstore.exe'" -Wait -WindowStyle Hidden
        Test-Path $outpath
    }

    function ShowGitConfig
    {
        Write-Verbose "Showing git config --list."
        . git config --list
    }

    switch ($true)
    {
        $wincred  { SetGitCredentialHelper -helper wincred }
        $winstore
        { 
            if ($DownloadWinStore){ DownloadWinStore }
            SetGitCredentialHelper -helper winstore
        }
    }
    ShowGitConfig
}

#endregion

#region Git Helper

function GetRepositoryName ([uri]$RepositoryUrl)
{
    return (Split-Path $RepositoryUrl -Leaf) -split "\.git" | select -First 1
}

function GetWorkingDirectory ([string]$Path, [uri]$RepositoryUrl, [string]$GitFolderName, [string]$Repository)
{
    $workingDirectory = if ($GitFolderName -eq "")
    {
        Join-Path $Path $repository
    }
    else
    {
        Join-Path $Path $GitFolderName
    }
    return $workingDirectory    
}

function GitClone ([string]$Path, [uri]$RepositoryUrl, [string]$GitFolderName)
{
    $repository = GetRepositoryName -RepositoryUrl $RepositoryUrl

    # Folder checking
    $created = if ($GitFolderName -eq "")
    {
        NewFolder -Path (Join-Path $Path $repository)
    }
    else
    {
        NewFolder -Path (Join-Path $Path $GitFolderName)
    }
    if ($created -eq $false){ "Repository already cloned to '{0}'. Skip clone repository : '{1}'." -f $created, $repository | WriteMessage; return; }

    # git command
    "Cloning Repository '{0}' to '{1}'" -f $repository, $Path | WriteMessage
    GitCommand -Arguments "clone $RepositoryUrl $GitFolderName" -WorkingDirectory $Path
}

function GitPull ([string]$Path, [uri]$RepositoryUrl, [string]$GitFolderName, [string]$Branch)
{
    $repository = GetRepositoryName -RepositoryUrl $RepositoryUrl
    $workingDirectory = GetWorkingDirectory -Path $Path -RepositoryUrl $RepositoryUrl -GitFolderName $GitFolderName -Repository $repository
            
    # git command
    "Pulling Repository '{0}' at '{1}'. Branch {2}" -f $repository, $workingDirectory, $Branch | WriteMessage
    GitCommand -Arguments "pull origin $Branch" -WorkingDirectory $workingDirectory
}

function GitSubmoduleUpdate ([string]$Path, [uri]$RepositoryUrl, [string]$GitFolderName)
{
    $repository = GetRepositoryName -RepositoryUrl $RepositoryUrl
    $workingDirectory = GetWorkingDirectory -Path $Path -RepositoryUrl $RepositoryUrl -GitFolderName $GitFolderName -Repository $repository
            
    # git command
    "Updating submodule recursively" | WriteMessage
    GitCommand -Arguments "submodule update --init --recursive" -WorkingDirectory $workingDirectory
}

function GitCommand 
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = 1, Position = 0)]
        [string]$Arguments,
        
        [Parameter(Mandatory = 0, Position = 1)]
        [string]$WorkingDirectory = ".",

        [Parameter(Mandatory = 0, Position = 2)]
        [TimeSpan]$Timeout = $GitContinuousPull.Timeout
    )

    end
    {
        try
        {
            # new GitProcess
            $gitProcess = NewGitProcess -Arguments $Arguments -WorkingDirectory $WorkingDirectory
                
            # Event Handler for Output
            $stdSb = New-Object -TypeName System.Text.StringBuilder
            $errorSb = New-Object -TypeName System.Text.StringBuilder
            $scripBlock = 
            {
                $x = $Event.SourceEventArgs.Data
                if (-not [String]::IsNullOrEmpty($x))
                {
                    [System.Console]::WriteLine($x)
                    $Event.MessageData.AppendLine($x)
                }
            }
            $stdEvent = Register-ObjectEvent -InputObject $gitProcess -EventName OutputDataReceived -Action $scripBlock -MessageData $stdSb
            $errorEvent = Register-ObjectEvent -InputObject $gitProcess -EventName ErrorDataReceived -Action $scripBlock -MessageData $errorSb

            # execution
            $gitProcess.Start() > $null
            $gitProcess.BeginOutputReadLine()
            $gitProcess.BeginErrorReadLine()

            # wait for complete
            "Waiting for git command complete. It will Timeout in {0}ms" -f $Timeout | VerboseOutput
            $isTimeout = $false
            if (-not $gitProcess.WaitForExit([int]([TimeSpan]::FromMilliseconds($GitContinuousPull.Timeout.TotalMilliseconds).TotalMilliseconds)))
            {
                $isTimeout = $true
                "Timeout detected for {0}ms. Kill process immediately" -f $timeout | VerboseOutput
                $gitProcess.Kill()
                throw New-Object System.TimeoutException
            }
            $gitProcess.WaitForExit()
            $gitProcess.CancelOutputRead()
            $gitProcess.CancelErrorRead()

            # verbose Event Result
            $stdEvent, $errorEvent | VerboseOutput

            # Unregister Event to recieve Asynchronous Event output (You should call before process.Dispose())
            Unregister-Event -SourceIdentifier $stdEvent -ErrorAction SilentlyContinue
            Unregister-Event -SourceIdentifier $errorEvent -ErrorAction SilentlyContinue

            # Write into Log
            WriteCommandResult -StandardStringBuilder $stdSb -ErrorStringBuilder $errorSb

             # Check Exit code
            "Exit Code : {0}" -f $gitProcess.ExitCode | VerboseOutput
            if ($gitProcess.ExitCode -ne 0)
            {
                $exception = ("git process Exit code detect '{0}'. Could not complete exception!" -f $gitProcess.ExitCode)
                $exception | WriteFile
                throw New-Object System.InvalidOperationException $exception
            }
            else
            {
                "Exit code '{0}' detected. Successfully complete git process." -f $gitProcess.ExitCode | WriteFile
            }
        }
        finally
        {
            if ($null -ne $gitProcess){ $gitProcess.Dispose() }
            if ($null -ne $stdEvent){ $stdEvent.Dispose() }
            if ($null -ne $errorEvent){ $errorEvent.Dispose() }
        }
    }

    begin
    {
        function NewGitProcess ([string]$Arguments, [string]$WorkingDirectory)
        {
            "Creating Git Process with Argument '{0}', WorkingDirectory '{1}'" -f $Arguments, $WorkingDirectory | VerboseOutput
            "Execute git command : 'git {0}'" -f $Arguments, $WorkingDirectory | VerboseOutput
            # ProcessStartInfo
            $psi = New-object System.Diagnostics.ProcessStartInfo 
            $psi.CreateNoWindow = $true
            $psi.LoadUserProfile = $true
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.FileName = "git.exe"
            $psi.Arguments+= $Arguments
            $psi.WorkingDirectory = $WorkingDirectory

            # Set Process
            $process = New-Object System.Diagnostics.Process 
            $process.StartInfo = $psi
            return $process
        }
        
        function WriteCommandResult ([System.Text.StringBuilder]$StandardStringBuilder, [System.Text.StringBuilder]$ErrorStringBuilder)
        {
            'Get git command result string.' | VerboseOutput
            $standardString = $StandardStringBuilder.ToString().TrimEnd()
            $errorString = $ErrorStringBuilder.ToString().TrimEnd()
            if(($process.ExitCode -eq 0) -and ($standardString -eq "") -and ($errorString -ne ""))
            {
                $standardOutput = $errorString
                $errorOutput = ""
            }
            else
            {
                $standardOutput = $standardString
                $errorOutput = $errorString
            }

            # "Already up-to-date" checking
            $GitContinuousPull.StandardOutput = $standardOutput

            # Output result to log at once. not per output line.
            $standardOutput | WriteFile
            $errorOutput | WriteFile
        }

        filter VerboseOutput
        {
            $_ | Out-String -Stream | Write-Verbose
        }

        filter WriteFile
        {
            $_ | Out-String -Stream | Out-File -FilePath $GitContinuousPull.log.FullPath -Encoding $GitContinuousPull.fileEncode -Force -Append
        }
    }
}

#endregion

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
$GitContinuousPull.Timeout = [TimeSpan]::FromMinutes(20)

Export-ModuleMember -Function * -Variable $GitContinuousPull.name