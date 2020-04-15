<#  
.Description  
    Creates a site (SPWeb) structure within a site collection, based on a specific termset in term store
         
.Parameter - siteURL 
    Url of the host named site collection inside which to create the site structure
.Parameter - termStoreName 
    Name of the term store where the term set resides. Default value = Managed Metadata Service
.Parameter - groupName 
    Name of the term group where the termset resides. Default value = Global
.Parameter - termSetName 
    Name of the termset containing from where site titles and urls should be extracted. Default value = Function
.Parameter - template 
    Site template for the sites. Leave empty to pick after creation
.Parameter - removeExisting 
    Should sites be removed if they exist
.Usage 
    Create a site structure based on MOC Blank site template
     
    PS >  Create-SubsiteStructureFromMMS.ps1 -siteURL "http://sitecoll.company.com"
.Usage 
    Create a site strucutre based on collaboration team site template
     
    PS >  Create-SubsiteStructureFromMMS.ps1 -siteURL "http://sitecoll.company.com" -template "STS#0"
.Usage 
    Create a site strucutre based on MOC Blank site template after removing any existing sites
     
    PS >  Create-SubsiteStructureFromMMS.ps1 -siteURL "http://sitecoll.company.com" -removeExisting
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Root site collection url")]
    [string] $siteURL = "http://what.murphyoilcorp.com",

    [Parameter(Mandatory=$false, Position=1, HelpMessage="Template identifier. Default is MOC blank site.")]
    [string] $template = "{ba37f557-5789-4b7b-98a5-38def93919a3}#MOC.BlankSite",

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Name of term store")]
    [string] $termStoreName,

    [Parameter(Mandatory=$false, Position=3, HelpMessage="Term group name")]
    [string] $groupName,

    [Parameter(Mandatory=$false, Position=4, HelpMessage="Termset name")]
    [string] $termSetName,

    [Parameter(Mandatory=$false, Position=5, HelpMessage="Should existing site be removed?")]
    [switch] $removeExisting
)

$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null


function GetSiteGroup([Microsoft.SharePoint.SPWeb] $web, [string] $name)
{
    [Microsoft.SharePoint.SPGroup] $group = $null
    [Microsoft.SharePoint.SPGroupCollection] $groups = $web.SiteGroups

    foreach($group in $groups) {
        if ($group.Name -eq $name) {
            break
        }
    }

    return $group
}

function EnsureSPGroup([Microsoft.SharePoint.SPWeb]$web, [string] $groupName)
{
    Write-Host "-----------------------------------------------------" -ForegroundColor Gray
    Write-Host "Searching for group $groupName in $($web.Title)..." -ForegroundColor Gray
    
    [Microsoft.SharePoint.SPGroup] $group = $null

    $groupQuery = @($groupName)
    $groupsFound = $web.SiteGroups.GetCollection($groupQuery)
    if (($groupsFound -ne $null) -and ($groupsFound.Count -eq 1) -and ($groupsFound[0].Name -eq $groupName))
    {
        $group = $groupsFound[0]
        Write-Host "Group $groupName already exists in $($web.Title)..." -ForegroundColor Gray
    }
    else
    {
        Write-Host "Creating group $groupName in $($web.Title)..." -ForegroundColor Gray

        $web.SiteGroups.Add($groupName, $global:siteCollectionOwnersGroup, $null, $groupName)
        $web.Update()
        $group = GetSiteGroup $web $groupName
        <#
        if ($group -ne $null)
        {
            $group.OnlyAllowMembersViewMembership = $false       # let everyone view group memberships
            $group.Update()
        }#>
    }

    return $group
}

function ProvisionSecurity($web, $webUrlStub) {

    [Microsoft.SharePoint.SPRoleDefinition] $reader = $web.RoleDefinitions["Read"]
    [Microsoft.SharePoint.SPRoleDefinition] $contributor = $web.RoleDefinitions["Contribute"]
    [Microsoft.SharePoint.SPRoleDefinition] $fullControl = $web.RoleDefinitions["Full Control"]

    $hashGroupPerms = @{$($webUrlStub + " Owners")=$fullControl; 
                    $($webUrlStub + " Members")=$contributor; 
                    $($webUrlStub + " Visitors")=$reader}

    $hashGroupPerms.Keys | % {
        [Microsoft.SharePoint.SPGroup] $spGroup = EnsureSPGroup $web $($_)
        if($spGroup -ne $null) {

            Write-Host "Assigning '$_' group '$($hashGroupPerms[$_].Name)' permission on $($web.Title)..." -ForegroundColor Gray

            [Microsoft.SharePoint.SPRoleAssignment] $roleAssignment = New-Object Microsoft.SharePoint.SPRoleAssignment $spGroup
            $roleAssignment.RoleDefinitionBindings.Add($hashGroupPerms[$_])
            $web.RoleAssignments.Add($roleAssignment)

            Write-Host "Assigning '$_' group '$($reader.Name)' permission on site collection $siteURL..." -ForegroundColor Gray

            [Microsoft.SharePoint.SPRoleAssignment] $siteRoleAssignment = New-Object Microsoft.SharePoint.SPRoleAssignment $spGroup
            $siteRoleAssignment.RoleDefinitionBindings.Add($reader)
            $web.Site.RootWeb.RoleAssignments.Add($siteRoleAssignment)
        }
    }

    $web.Update()
    $web.Site.RootWeb.Update()
}

function RemoveWeb([Microsoft.SharePoint.SPWeb] $web) {
    if($web -ne $null) {
        $subWebs = $web.GetSubwebsForCurrentUser()
        $subWebs | % { 
            RemoveWeb $_
            $_.Dispose()
        }
        
        Remove-SPWeb $web -Confirm:$false
    }
}

function CreateSubsite($webTitle, $webUrlStub, $webUrl) {

    $create = $true
     
    if(($global:allWebNames -contains $webTitle) -or ($global:allWebUrls -contains $webUrl))
    {
        Write-Host "Site with name '$webTitle' or url '$webUrl' already exists in this site collection." -ForegroundColor Red
        
        if($removeExisting)
        {
            $deleteConfirmation = Read-Host "Do you wish to permanently delete the existing site? All content within the site will be deleted. [y/n]"
            if($deleteConfirmation -eq 'y') {
                RemoveWeb (Get-SPWeb $webUrl)
                Write-Host "Site '$webTitle' has been deleted" -ForegroundColor Gray
                $createConfirmation = Read-Host "Recreate site? [y/n]"
                if($createConfirmation -eq 'n') {
                    $create = $false
                }
            }
            else {
                Write-Host "Site '$webTitle' will NOT be deleted" -ForegroundColor Gray
                $create = $false
            }
        }
        else {
            Write-Host "Site '$webTitle' will NOT be created" -ForegroundColor Gray
            $create = $false
        }
    }

    if($create)
    { 
        Write-Host "Creating site '$webTitle' with Url '$webUrl'..." -ForegroundColor Green
        
        [Microsoft.SharePoint.SPWeb] $web = New-SPWeb -Name $webTitle -Url $webUrl -Template $template -UniquePermissions -UseParentTopNav

        # provision security
        if($web -ne $null)
        {
            Write-Host "Provisioning security for site '$webTitle' with Url '$webUrl'..." -ForegroundColor Green

            ProvisionSecurity $web $webUrlStub

            $web.Dispose()
        }
    }
}

write-host "Start - $(Get-Date)" -ForegroundColor DarkYellow

$defaultTermStoreName = "Managed Metadata Service"
$defaultGroupName = "Global"
$defaultTermSetName = "Function"

# Terms in function termset are of the form 'label (xxx)'. The 'label' part should be used as web title and 'xxx' part should be used in url stub
$regExPatternForWebTitle = '^(.*?)\('
$regExPatternForUrlStub = '\((.*?)\)'

if([string]::IsNullOrEmpty($termStoreName))
{
    $termStoreName = $defaultTermStoreName
}

if([string]::IsNullOrEmpty($groupName))
{
    $groupName = $defaultGroupName
}

if([string]::IsNullOrEmpty($termSetName))
{
    $termSetName = $defaultTermSetName
}

$global:allWebNames = @()
$global:allWebUrls = @()
[Microsoft.SharePoint.SPGroup] $global:siteCollectionOwnersGroup = $null

$site = Get-SPSite $siteURL

if($site -ne $null) {
    $global:siteCollectionOwnersGroup = $site.RootWeb.AssociatedOwnerGroup
    $site.AllWebs | % {
        $global:allWebNames += $_.Title
        $global:allWebUrls += $_.Url
    }

    Write-Host "Connecting to managed metadata service..." -ForegroundColor Green

    $taxonomySession = New-Object Microsoft.SharePoint.Taxonomy.TaxonomySession $site, $true

    if($taxonomySession -ne $null)
    {
        Write-Host "Fetching term store named '$termStoreName' for the farm" -ForegroundColor Green
        $store = $taxonomySession.TermStores[$termStoreName]
    }
    else
    {
        Write-Host "Could not connect to managed metadata service for this farm. Exiting." -ForegroundColor Red
        return
    }

    if($store -eq $null)
    {
        Write-Host "Term store $termStoreName was not found in this farm. Exiting." -ForegroundColor Red
        return
    }

    $group = $store.Groups[$groupName]

    if ($group -eq $null)
    {
        write-host "Group $groupName not found. Exiting." -ForegroundColor Red
        return
    }

    #Getting the Termset
    $termset = $group.TermSets[$termSetName]

    if ($termset -ne $null)
    {
        write-host "Using terms from termset '$termSetName' in group '$groupName' for site structure." -ForegroundColor Green

        # prep site collection with relevant features enabled
        if($template.Contains("MOC")) {
            # MOC custom templates require certain site collection level features activated

            $reqdSiteFeatures = @('A44D2AA3-AFFC-4d58-8DB4-F4A3AF053188', 'A392DA98-270B-4e85-9769-04C0FDE267AA', '7C637B23-06C4-472d-9A9A-7C175762C5C4', 'AEBC918D-B20F-4a11-A1DB-9ED84D79C87E', 'F6924D36-2FA8-4f0b-B16D-06B7250180FA', '73EF14B1-13A9-416b-A9B5-ECECA2B0604C', 'f487d6c8-08c5-401a-9d9b-acce639e2aa1', '5730520b-c5bb-4c29-8cc5-fe53c957792a')
            $i = 0
            foreach($featureId in $reqdSiteFeatures) {
                
                try {
                    Get-SPFeature -Identity $featureId -Site $siteURL
                }
                catch {
                    Write-Host "Activating required feature $featureId ..." -ForegroundColor Green
                    Enable-SPFeature -Identity $featureId -Url $siteURL
                }

                $i += 1
            }
            if($reqdSiteFeatures.Count -eq $i) {
                Write-Host "All required features have been activated on $siteURL ..." -ForegroundColor Green
            }
            else {
                Write-Host "All required features have NOT been activated on $siteURL. Exiting." -ForegroundColor Red
                return
            }
        }

        $termset.Terms | % {
            Write-Host "----------------------------------------------------------------------------"

            $webTitle = ""
            
            if([regex]::Matches($_.Name, $regExPatternForWebTitle) -ne $null) {
                $webTitle = ([regex]::Matches($_.Name, $regExPatternForWebTitle).Groups[1].Value).trim()
            }
            
            $webUrlStub = ""
            
            if([regex]::Matches($_.Name, $regExPatternForUrlStub) -ne $null) {
                $webUrlStub = ([regex]::Matches($_.Name, $regExPatternForUrlStub).Groups[1].Value).trim()
            }
             
            if([string]::IsNullOrWhiteSpace($webTitle) -or [string]::IsNullOrWhiteSpace($webUrlStub)) {
                Write-Host "Term name: '$($_.Name)' is not of the correct format. Term must be of the form 'title (function code)' in order to create a site from. No site will be created for this term." -ForegroundColor Red
            }
            else {
                $webUrl = $siteURL + "/" + $webUrlStub

                CreateSubsite $webTitle $webUrlStub $webUrl
            }
        }

        if ([string]::IsNullOrEmpty($errormessage) -eq $false)
        {
            write-host $errormessage -ForegroundColor Red
        }
    }
    else
    { 
        write-host "Termset $termSetName does not exist in group $groupName. Exiting." -ForegroundColor Green
    }

    $site.Dispose()
}
write-host "Done - $(Get-Date)" -ForegroundColor DarkYellow