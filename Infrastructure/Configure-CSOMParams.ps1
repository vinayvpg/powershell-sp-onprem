<#
    Script to configure parameters related to CSOM calls executed against the web application.
    These parameters are aggregated in SPWebApplication.ClientCallableSettings object
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Url of the web application")]
    [string] $webAppUrl
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

 $wa = Get-SPWebApplication -Identity $webAppUrl

 if($wa -ne $null){
    Write-Host "`nSetting CSOM parameters for web application $webAppUrl..."

    # Default timeout for CSOM calls is 90 seconds. Even if RequestTimeout is set on ClientContext object of CSOM request,
    # this parameter takes precedence. Set to 60 mins so long running synchronous CSOM operations such as file upload using
    # SaveBinaryDirect do not time out.

    Write-Host "`nSetting default CSOM call execution timeout..."
    Write-Host "Current value: $($wa.ClientCallableSettings.ExecutionTimeout)" -ForegroundColor Magenta

    $wa.ClientCallableSettings.ExecutionTimeout = [System.Timespan]::FromMinutes(60)
    $wa.Update();

    Write-Host "New value: $($wa.ClientCallableSettings.ExecutionTimeout)" -ForegroundColor Green
    Write-Host "Done!" -BackgroundColor Green
}
