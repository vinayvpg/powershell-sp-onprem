<#  
.Description  
    Creates a host named site collection with an associated database within a web application
         
.Parameter - webAppUrl  
    Url of the web application
.Parameter - siteURL 
    Url of the host named site collection to create inside the web application
.Parameter - siteCollectionName 
    Title of the site collection
.Parameter - ownerAlias 
    Login alias of the primary site collection owner
.Parameter - siteDatabase 
    Name of content database for the site collection
.Parameter - template 
    Site template for the root site of the site collection. Leave empty to pick after creation
.Parameter - CompatibilityLevel 
    Compatibility level for the site collection. Leave empty to get SP2013 experience
.Usage 
    Create a BI Center site collection as HNSC
     
    PS >  Create-HNSC.ps1 -webAppUrl "http://my.weapp.url" -siteURL "http://portal.company.com" -siteCollectionName "Company Portal" -ownerAlias "domain\user" -siteDatabase "db_name" -template "BICenterSite#0"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Url of the web application")]
    [string] $webAppUrl = "http://portal.murphyoilcorp.com",

    [Parameter(Mandatory=$true, Position=1, HelpMessage="Url of the host named site collection to create inside the web application")]
    [string] $siteURL = "http://legacydocs.murphyoilcorp.com",

    [Parameter(Mandatory=$true, Position=2, HelpMessage="Title of the site collection")]
    [string] $siteCollectionName = "Murphy Enterprise Legacy Documents Center",

    [Parameter(Mandatory=$true, Position=3, HelpMessage="Login alias of the primary site collection owner")]
    [string] $ownerAlias = "SP2013\Administrator",

    [Parameter(Mandatory=$true, Position=4, HelpMessage="Name of content database for the site collection")]
    [string] $siteDatabase = "PORTAL_PROD_Content_LegacyDocs",

    [Parameter(Mandatory=$false, Position=5, HelpMessage="Site template for the root site of the site collection. Leave empty to pick after creation")]
    [string] $template = "BDR#0",

    [Parameter(Mandatory=$false, Position=6, HelpMessage="Compatibility level for the site collection. Leave empty to get SP2013 experience")]
    [string] $CompatibilityLevel
)

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

$webApp = Get-SPWebApplication $webAppUrl

if ($webApp -ne $null)
{
        $getSPSiteCollection = $null
		$siteExisting = Get-SPSite -Identity $siteURL -ErrorAction SilentlyContinue
        if (!$siteExisting)
        {
            if (!([string]::IsNullOrEmpty($CompatibilityLevel))) # Check the Compatibility Level if it's been specified
            {
                $CompatibilityLevelSwitch = @{CompatibilityLevel = $CompatibilityLevel}
            }
            else {$CompatibilityLevelSwitch = @{}}

            $LCID = 1033 
            $siteCollectionLocale = "en-us" 
            $siteCollectionTime24 = $false 

            If (($template -ne $null) -and ($template -ne ""))
            {
                $templateSwitch = @{Template = $template}
            }
            else {$templateSwitch = @{}}

            $hostHeaderWebAppSwitch = @{HostHeaderWebApplication = $webAppUrl+":"+$($webApp.port)}

            Write-Host -ForegroundColor White " - Checking for Site Collection `"$siteURL`"..."
            $getSPSiteCollection = Get-SPSite -Limit ALL | Where-Object {$_.Url -eq $siteURL}
            If (($getSPSiteCollection -eq $null) -and ($siteURL -ne $null))
            {
                    $siteDatabaseExists = Get-SPContentDatabase -Identity $siteDatabase -ErrorAction SilentlyContinue
                    if (!$siteDatabaseExists)
                    {
                        Write-Host -ForegroundColor White " - Creating new content database `"$siteDatabase`"..."
                        New-SPContentDatabase -Name $siteDatabase -WebApplication (Get-SPWebApplication $webApp.url) | Out-Null
                    }
                    Write-Host -ForegroundColor White " - Creating Site Collection `"$siteURL`"..."
                    $site = New-SPSite -Url $siteURL -OwnerAlias $ownerAlias -SecondaryOwner $env:USERDOMAIN\$env:USERNAME -ContentDatabase $siteDatabase -Description $siteCollectionName -Name $siteCollectionName -Language $LCID @templateSwitch @hostHeaderWebAppSwitch @CompatibilityLevelSwitch -ErrorAction Stop

                    # set database and collection quotas
                    Get-SPContentDatabase -site $siteURL | Set-SPContentDatabase -MaxSiteCount 1 -WarningSiteCount 0
                    Get-SPSite $siteURL | Set-SPSite -MaxSize 214748364800

                    $primaryUser = $site.RootWeb.EnsureUser($ownerAlias)
                    $secondaryUser = $site.RootWeb.EnsureUser("$env:USERDOMAIN\$env:USERNAME")
                    $title = $site.RootWeb.title
                    Write-Host -ForegroundColor White " - Ensuring default groups are created..."
                    $site.RootWeb.CreateDefaultAssociatedGroups($primaryUser, $secondaryUser, $title)

                    # Add the Portal Site Connection to the web app, unless of course the current web app *is* the portal
                    $portalSiteColl = $webApp.SiteCollections.SiteCollection | Select-Object -First 1
                    If ($site.URL -ne $portalSiteColl.siteURL)
                    {
                        Write-Host -ForegroundColor White " - Setting the Portal Site Connection for `"$siteCollectionName`"..."
                        $site.PortalName = $portalSiteColl.Name
                        $site.PortalUrl = $portalSiteColl.siteUrl
                    }
                    If ($siteCollectionLocale)
                    {
                        Write-Host -ForegroundColor White " - Updating the locale for `"$siteCollectionName`" to `"$siteCollectionLocale`"..."
                        $site.RootWeb.Locale = [System.Globalization.CultureInfo]::CreateSpecificCulture($siteCollectionLocale)
                    }
                    If ($siteCollectionTime24)
                    {
                        Write-Host -ForegroundColor White " - Updating 24 hour time format for `"$siteCollectionName`" to `"$siteCollectionTime24`"..."
                        $site.RootWeb.RegionalSettings.Time24 = $([System.Convert]::ToBoolean($siteCollectionTime24))
                    }
                    $site.RootWeb.Update()

                    # enable branding feature
                    Enable-SPFeature -Url $siteURL -Identity "MOC.SharePoint_Branding"
                #}
            }
        }
        Else {Write-Host -ForegroundColor White " - Skipping creation of site `"$siteCollectionName`" - already provisioned."}
}
else
{
    Write-Host -ForegroundColor Yellow " - No web application found at $webAppUrl - skipping."
}