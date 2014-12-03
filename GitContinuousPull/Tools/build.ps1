$Script:module = [ordered]@{}
$module.name = 'GitContinuousPull'
$module.ExportPath = Split-Path $PSCommandPath -Parent
$module.modulePath = Split-Path -parent $module.ExportPath
$module.fileEncode = [Microsoft.PowerShell.Commands.FileSystemCmdletProviderEncoding]'utf8'

$module.moduleVersion = "1.0.0"
$module.description = "PowerShell simple git continuous delivery module.";
$module.RequiredModules = @("valentia")

$module.clrVersion = "4.0.0.0" # .NET 4.0 with StandAlone Installer "4.0.30319.1008" or "4.0.30319.1" , "4.0.30319.17929" (Win8/2012)

$module.functionToExport = @("*")
$script:moduleManufest = @{
    Path = "{0}.psd1" -f $module.name
    Author = "guitarrapc";
    CompanyName = "guitarrapc"
    ModuleVersion = $module.moduleVersion
    Description = $module.description
    PowerShellVersion = "3.0";
    DotNetFrameworkVersion = "4.0";
    ClrVersion = $module.clrVersion;
    RequiredModules = $module.RequiredModules;
    NestedModules = "{0}.psm1" -f $module.name;
    FunctionsToExport = $module.functionToExport
    VariablesToExport = $module.name
}

New-ModuleManifest @moduleManufest

# As Installer place on ModuleName\Tools.
$psd1 = Join-Path $module.ExportPath ("{0}.psd1" -f $module.name);
$newpsd1 = Join-Path $module.ModulePath ("{0}.psd1" -f $module.name);
if (Test-Path -Path $psd1)
{
    Get-Content -Path $psd1 -Encoding $module.fileEncode -Raw -Force | Out-File -FilePath $newpsd1 -Encoding default -Force
    Remove-Item -Path $psd1 -Force
}
