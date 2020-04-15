<#
    This script should be scheduled to run after every user profile incremental or full import job run.
    The script will create 3 jpg thumbnails for each base64 encoded profile image imported from AD thumbnail photo attribute.
    The thumbnails will be stored in Profile Pictures folder of User Photos library of the my site host.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of my site host")]
    [string] $mySiteHostUrl = "http://my.murphyoilcorp.com"
)

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

if([string]::IsNullOrWhiteSpace($mySiteHostUrl))
{
    do {
        $mySiteHostUrl = Read-Host "Specify the url of my site host"
    }
    until (![string]::IsNullOrWhiteSpace($mySiteHostUrl))
}

Write-Verbose "Creating thumbnails for SP user profile and my site from AD imported profile pictures..."

Update-SPProfilePhotoStore -CreateThumbnailsForImportedPhotos 1 -MySiteHostLocation $mySiteHostUrl

Write-Host "Done" -BackgroundColor Green

$VerbosePreference = "SilentlyContinue"

Write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow