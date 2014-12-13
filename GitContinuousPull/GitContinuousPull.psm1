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
        [uri]$RepositoryUrl,

        [Parameter(HelpMessage = "Input Full path of Git Repository Parent Folder", Position = 1, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$GitPath,
 
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

        Write-Verbose ("Starting for RepotirotyUrl '{0}'" -f $RepositoryUrl)

        # initialize
        $GitContinuousPull.firstClone = $false

        # git clone
        $gitClone = GitClone -Path $GitPath -RepositoryUrl $RepositoryUrl
        if (-not [String]::IsNullOrWhiteSpace($gitClone.StandardOutput)){ $gitClone.StandardOutput | WriteMessage }
        if (-not [String]::IsNullOrWhiteSpace($gitClone.ErrorOutput)){ $gitClone.ErrorOutput | WriteMessage }

        # git pull
        $gitPull = GitPull -Path $GitPath -RepositoryUrl $RepositoryUrl
        if (-not [String]::IsNullOrWhiteSpace($gitPull.StandardOutput)){ $gitPull.StandardOutput | WriteMessage }
        if ((-not [String]::IsNullOrWhiteSpace($gitPull.ErrorOutput)) -and ($gitPull.ErrorOutput -ne $gitPull.StandardOutput)){ $gitPull.ErrorOutput | WriteMessage }
            
        # PostAction
        if (($PostAction | measure).Count -eq 0){ return; }
        switch ($true)
        {
            $GitContinuousPull.firstClone
            {
                "First time clone detected. Execute PostAction." | WriteMessage
                $PostAction | %{& $_}
            }
            (($GitContinuousPull.ExitCode -eq 0) -and (($gitPull.Output | select -Last 1) -notmatch "Already up-to-date."))
            {
                "Pull detected change. Execute PostAction." | WriteMessage
                $PostAction | %{& $_}
            }
            default { "None of change for git detected. Skip PostAction."  | WriteMessage }
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
            $private:ErrorActionPreference = "Continue"

            $credential = Get-ValentiaCredential -TargetName git
            $targetName = "git:https://{0}@github.com" -f $credential.UserName

            # Check git credential is already exist.
            switch ((Get-ValentiaCredential -TargetName $targetName -Type Generic -ErrorAction SilentlyContinue | measure).Count)
            {
                1 
                {
                    # return without any action
                    "git credential found from Windows Credential Manager as TargetName : '{0}'." -f $targetName | WriteMessage; 
                    return; 
                }
                default
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
            $workingDirectory = Join-Path $Path $repository
            "Pulling Repository '{0}' at '{1}'" -f $repository, $workingDirectory | WriteMessage
            GitCommand -Arguments "pull" -WorkingDirectory $workingDirectory
        }

        function GitCommand 
        {
            [OutputType([PSCustomObject])]
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory = 1, Position = 0)]
                [string]$Arguments,
        
                [Parameter(Mandatory = 0, Position = 1)]
                [string]$WorkingDirectory = ".",

                [Parameter(Mandatory = 0, Position = 2)]
                [int]$TimeoutMS = $GitContinuousPull.TimeoutMS
            )

            end
            {
                try
                {
                    # new GitProcess
                    $gitProcess = NewGitProcess -Arguments $Arguments -WorkingDirectory $WorkingDirectory
                
                    # Event Handler for Output
                    $stdEvent = Register-ObjectEvent -InputObject $gitProcess -EventName OutputDataReceived -Action $scripBlock -MessageData $stdSb
                    $errorEvent = Register-ObjectEvent -InputObject $gitProcess -EventName ErrorDataReceived -Action $scripBlock -MessageData $errorSb

                    # execution
                    $gitProcess.Start() > $null
                    $gitProcess.BeginOutputReadLine()
                    $gitProcess.BeginErrorReadLine()

                    # wait for complete
                    WaitProcessComplete -Process $gitProcess -TimeoutMS $TimeoutMS

                    # verbose Event Result
                    $stdEvent, $errorEvent | VerboseOutput

                    # output
                    return GetCommandResult -Process $gitProcess -StandardStringBuilder $stdSb -ErrorStringBuilder $errorSb
                }
                finally
                {
                    if ($null -ne $process){ $process.Dispose() }
                    if ($null -ne $stdEvent){ Unregister-Event -SourceIdentifier $stdEvent.Name }
                    if ($null -ne $errorEvent){ Unregister-Event -SourceIdentifier $errorEvent.Name }
                    if ($null -ne $stdEvent){ $stdEvent.Dispose() }
                    if ($null -ne $errorEvent){ $errorEvent.Dispose() }        
                }
            }

            begin
            {
                # Prerequisites       
                $stdSb = New-Object -TypeName System.Text.StringBuilder
                $errorSb = New-Object -TypeName System.Text.StringBuilder
                $scripBlock = 
                {
                    if (-not [String]::IsNullOrEmpty($EventArgs.Data))
                    {
                        
                        $Event.MessageData.AppendLine($Event.SourceEventArgs.Data)
                    }
                }

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

                function WaitProcessComplete ([System.Diagnostics.Process]$Process, [int]$TimeoutMS)
                {
                    "Waiting for git command complete. It will Timeout in {0}ms" -f $TimeoutMS | VerboseOutput
                    $isComplete = $Process.WaitForExit($TimeoutMS)
                    if (-not $isComplete)
                    {
                        "Timeout detected for {0}ms. Kill process immediately" -f $timeoutMS | VerboseOutput
                        $Process.Kill()
                        $Process.CancelOutputRead()
                        $Process.CancelErrorRead()
                    }
                }

                function GetCommandResult ([System.Diagnostics.Process]$Process, [System.Text.StringBuilder]$StandardStringBuilder, [System.Text.StringBuilder]$ErrorStringBuilder)
                {
                    'Get git command result string.' | VerboseOutput
                    $standardString = $StandardStringBuilder.ToString()
                    $errorString = $ErrorStringBuilder.ToString()
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
                    return [PSCustomObject]@{
                        StandardOutput = $standardOutput
                        ErrorOutput = $errorOutput
                        ExitCode = $process.ExitCode
                    }
                }

                filter VerboseOutput
                {
                    $_ | Out-String -Stream | Write-Verbose
                }
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
$GitContinuousPull.TimeoutMS = 120000 # 2min

Export-ModuleMember -Function * -Variable $GitContinuousPull.name