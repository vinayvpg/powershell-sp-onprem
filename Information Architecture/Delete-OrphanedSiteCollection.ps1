<#  
.Description  
    Deletes an orphaned site collection that cannot be deleted via CA
         
.Parameter - siteUrl 
    Url of site collection to delete
.Usage 
    Delete a site collection
     
    PS >  Delete-OrphanedSiteCollection.ps1 -siteUrl "http://sitecoll.company.com"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of the orphaned site collection to delete")]
    [string] $siteUrl = "http://my.murphyoilcorp.com/personal/meyerex"
)

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

$site = Get-SPSite $siteUrl

if($site -ne $null) {
    Write-Host "Retrieved site collection..."
    
    Write-Host "Url: $siteUrl"
     
    $siteId = $site.Id

    Write-Host "Id: $siteId"

    $siteDatabase = $site.ContentDatabase

    Write-Host "Database: $($siteDatabase.Name)"

    Write-Host "Deleting..." -NoNewline

    $siteDatabase.ForceDeleteSite($siteId, $false, $false)

    Write-Host "Done" -BackgroundColor Green -ForegroundColor White
}