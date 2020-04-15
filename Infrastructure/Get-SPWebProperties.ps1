<#
    Script to obtain site attributes that are not available in UI
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Url of the site collection")]
    [string] $siteCollUrl
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

 $siteColl = Get-SPSite -Identity $siteCollUrl

 if($siteColl -ne $null){
    $siteColl | Get-SPWeb -Limit All | %{$_} | ft Title, Url, Created, Locale, WebTemplate

    $siteColl.Dispose()
 }