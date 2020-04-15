<#
    Script to configure parameters related to People Picker.
    Note that the [Microsoft.SharePoint.SPSecurity]::SetApplicationCredentialKey($key) credential encryption key command mucst be run on EACH WFE and APP server in the farm
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of web application whose people picker settings to modify")]
    [string] $webAppUrl = "http://portal.murphyoilcorp.com"
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

function GetSearchADDomainObject()
{
    $adSearchObj = New-Object Microsoft.SharePoint.Administration.SPPeoplePickerSearchActiveDirectoryDomain

    if($adSearchObj -ne $null) {
        do {
            $domainName = Read-Host -Prompt "Specify the full DNS name of the domain or forest (e.g. murphyoilcorp.com)"
        }
        until (![string]::IsNullOrWhiteSpace($domainName))

        $adSearchObj.DomainName = $domainName

        try {
            [ValidateSet('y','n')]$isForestResponse = Read-Host "Is this an AD forest? [y|n]"
        }
        catch {}

        $isForest = $false
        if($isForestResponse -eq 'y') {
            $isForest = $true
        }

        $adSearchObj.IsForest = $isForest

        do {
            $loginName = Read-Host "Specify the login name of the account that can query this domain/forest (e.g. moc\john.doe)"
        }
        until (![string]::IsNullOrWhiteSpace($loginName))

        $adSearchObj.LoginName = $loginName

        do {
            $pwd = Read-Host "Specify the password for the account (credential will be encrypted using the key specified earlier)" -AsSecureString
        }
        until (![string]::IsNullOrWhiteSpace($pwd))

        $adSearchObj.SetPassword($pwd)
    }

    return $adSearchObj

    <#
    $key = ConvertTo-SecureString "Password1" -AsPlainText -Force
    [Microsoft.SharePoint.SPSecurity]::SetApplicationCredentialKey($key)

    $adsearchobj = New-Object Microsoft.SharePoint.Administration.SPPeoplePickerSearchActiveDirectoryDomain
    $userpassword = ConvertTo-SecureString "UserPassword1" -AsPlainText -Force #Password for the user account CONTOSO\s-useraccount
    $adsearchobj.DomainName = "contoso.com"
    $adsearchobj.ShortDomainName = "CONTOSO" #Optional
    $adsearchobj.IsForest = $true #$true for Forest, $false for Domain
    $adsearchobj.LoginName = "s-useraccount"
    $adsearchobj.SetPassword($userpassword)

    $wa.PeoplePickerSettings.SearchActiveDirectoryDomains.Add($adsearchobj)
    $wa.Update()
    #>
}

#------------------ main script --------------------------------------------------
Write-Host "Start - $(Get-Date)`n" -ForegroundColor Yellow

if([string]::IsNullOrWhiteSpace($webAppUrl))
{
    do {
        $webAppUrl = Read-Host "Specify the url of web application whose people picker settings you wish to modify"
    }
    until (![string]::IsNullOrWhiteSpace($webAppUrl))
}

$webApp = Get-SPWebApplication $webAppUrl

if($webApp -ne $null) {

    Write-Host "Enumerating current people picker settings..." -BackgroundColor DarkMagenta

    $peoplePickerSettings = $webApp.PeoplePickerSettings

    $peoplePickerSettings.PSObject.Properties | Select Name, Value

    Write-Host "`n"
    
    try {
        [ValidateSet('y','n')] $adCustomQueryResponse = Read-Host "Would you like to modify 'ActiveDirectoryCustomQuery' property? This is used to specify the LDAP query. [y|n]"
    }
    catch {}
    if($adCustomQueryResponse -eq 'y') {
        $adCustomQuery = Read-Host "Enter the new value for 'ActiveDirectoryCustomQuery' [e.g. For people picker to only query for AD users, specify '(&(objectCategory=person)(objectClass=user))'. Type nothing and press enter to clear existing value]"

        Write-Host "Updating..." -NoNewline

        $peoplePickerSettings.ActiveDirectoryCustomQuery = $adCustomQuery
        $webApp.Update()
        
        Write-Host "Done" -BackgroundColor Green
    }

    Write-Host "`n"
    try {
        [ValidateSet('y','n')] $adCustomFilterResponse = Read-Host "Would you like to modify 'ActiveDirectoryCustomFilter' property? This is used to specify the LDAP filter to go with the custom query. [y|n]"
    }
    catch {}
    if($adCustomFilterResponse -eq 'y') {
        $adCustomFilter = Read-Host "Enter the new value for 'ActiveDirectoryCustomFilter' [e.g. For people picker to only find ACTIVE users, specify '(!userAccountControl:1.2.840.113556.1.4.803:=2)'. Type nothing and press enter to clear existing value]"

        Write-Host "Updating..." -NoNewline

        $peoplePickerSettings.ActiveDirectoryCustomFilter = $adCustomFilter
        $webApp.Update()
        
        Write-Host "Done" -BackgroundColor Green
    }

    Write-Host "`n"
    try {
        [ValidateSet('y','n')]$resolveInSiteCollResponse = Read-Host "Would you like to modify 'PeopleEditorOnlyResolveWithinSiteCollection' property? This is used to specify whether people picker will search only within the UserInfoList of the site collection or within the entire AD. [y|n]"
    }
    catch {}
    if($resolveInSiteCollResponse -eq 'y') {
        
        try {
            [ValidateSet('y','n')]$resolveInSiteColl = Read-Host "Resolve only within site collection? [y|n]"
        }
        catch {}

        $result = $false
        if($resolveInSiteColl -eq 'y') {
            $result = $true
        }

        Write-Host "Updating..." -NoNewline

        $peoplePickerSettings.PeopleEditorOnlyResolveWithinSiteCollection = $result
        $webApp.Update()
        
        Write-Host "Done" -BackgroundColor Green
    }

    Write-Host "`n"
    try {
        [ValidateSet('y','n')]$setSearchADForestResponse = Read-Host "Would you like to modify 'SearchActiveDirectoryDomains' property? This is to specify the AD domains and/or forests that the people picker should query. [y|n]"
    }
    catch {}
    if($setSearchADForestResponse -eq 'y') {
        Write-Host "First, specify a key (new text value) that will be used to encrypt the credential(s) used to query the domains/forests you will specify. You can set a new value every time you modify this property." -ForegroundColor Yellow
        do {
            $key = Read-Host -Prompt "Specify the new encryption key" -AsSecureString
        }
        until (![string]::IsNullOrWhiteSpace($key))

        Write-Host "Setting encryption key..." -NoNewline
        
        [Microsoft.SharePoint.SPSecurity]::SetApplicationCredentialKey($key)
        
        Write-Host "Done" -BackgroundColor Green

        try {
            [ValidateSet('y','n')]$setToDefaultResponse = Read-Host "Clear current settings and set to default value?[y|n]"
        }
        catch {}

        if($setToDefaultResponse -eq 'y') {
            Write-Host "Setting people picker to default AD search..." -NoNewline

            $webApp.PeoplePickerSettings.SearchActiveDirectoryDomains.Clear()
            $webApp.Update()

            Write-Host "Done" -BackgroundColor Green
        }
        else {
            do {
                $adObj = GetSearchADDomainObject

                if($adObj -ne $null) {
                    Write-Host "Adding search domain/forest '$($adObj.DomainName)' to people picker..." -NoNewline

                    $webApp.PeoplePickerSettings.SearchActiveDirectoryDomains.Add($adObj)
                    $webApp.Update()

                    Write-Host "Done" -BackgroundColor Green
                }

                $addMore = Read-Host "Add more domains/forests to search? [y|n]"
            }
            until ($addMore -ne 'y')
        }
    }
}

$webApp2 = Get-SPWebApplication $webAppUrl

if($webApp2 -ne $null) {

    Write-Host "`nEnumerating new people picker settings..." -BackgroundColor DarkMagenta

    $webApp2.PeoplePickerSettings.PSObject.Properties | Select Name, Value
}

Write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow