<#  
.Description  
    Add a MIME Type as inline downloadable in browser
         
.Parameter - webAppUrl 
    Url of the SharePoint web application being updated
.Parameter - mimeType 
    MIME Type to be added as permissible

.Usage 
    Add html as allowed for inline download
     
    PS >  Add-AllowedMIMEType.ps1 -webAppUrl "http://webapp.company.com" -mimeType "text/html"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Web application url")]
    [string] $webAppUrl,

    [Parameter(Mandatory=$true, Position=1, HelpMessage="MIMEType")]
    [string] $mimeType
)

$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

$webApp = Get-SPWebApplication $webAppUrl

Write-Host "Adding MIME Type '$mimeType' as allowed for inline download to web application '$webAppUrl'..." -NoNewline

if($webApp -ne $null) {
    if ($webApp.AllowedInlineDownloadedMimeTypes -notcontains $mimeType)
    {
        $webApp.AllowedInlineDownloadedMimeTypes.Add($mimeType)
        $webApp.Update()
        Write-Host "Done" -BackgroundColor Green
    } 
    else {
        Write-Host "Skipping. Already Exists" -BackgroundColor Magenta 
    }
}