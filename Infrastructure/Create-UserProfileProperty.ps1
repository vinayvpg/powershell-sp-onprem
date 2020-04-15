[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of my site host")]
    [string] $mySiteHostUrl = "http://my.murphyoilcorp.com/",

    [Parameter(Mandatory=$false, Position=1, HelpMessage="User profile property name")]
    [string] $propertyName = "Country",

    [Parameter(Mandatory=$false, Position=2, HelpMessage="User profile property display name")]
    [string] $propertyDisplayName = "Country",

    [Parameter(Mandatory=$false, Position=3, HelpMessage="User profile property data type")]
    [string] $propertyDataType = "string",

    [Parameter(Mandatory=$false, Position=4, HelpMessage="User profile property privacy type")]
    [string] $propertyPrivacyType = "public",

    [Parameter(Mandatory=$false, Position=5, HelpMessage="User profile property privacy policy")]
    [string] $propertyPrivacyPolicy = "OptIn",

    [Parameter(Mandatory=$false, Position=6, HelpMessage="Source (AD/BCS) attribute mapped to this property")]
    [string] $mappedAttributeName="co",

    [Parameter(Mandatory=$false, Position=7, HelpMessage="Import/Export. Default=import. Export valid for ActiveDirectory connection type only.")]
    [string] $mappedAttributeDirection
)

$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Office.Server") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Office.Server.UserProfiles") | Out-Null

function GetDefaultLengthForProperty($propertyDataType) {
    $defaultLength = 25

    switch($propertyDataType){
        'html'{$defaultLength = 2000}
        default{}
    }

    return $defaultLength
}

function DeleteUserProfileProperty($propertyName) {
    if(![string]::IsNullOrWhiteSpace($propertyName)) {
        <#Write-Host "profile subtype for property..." -NoNewline
        $global:profileSubTypePropertyManager.RemovePropertyByName($propertyName)
        Write-Host "Done..." -BackgroundColor Green -NoNewline

        Write-Host "profile type for property..." -NoNewline
        $global:profileTypePropertyManager.RemovePropertyByName($propertyName)
        Write-Host "Done..." -BackgroundColor Green -NoNewline#>

        Write-Host "core property..." -NoNewline
        $global:corePropertyManager.RemovePropertyByName($propertyName)
        Write-Host "Done" -BackgroundColor Green
    }
}

function UpdateProfilePropertyTypeAttributes([Microsoft.Office.Server.UserProfiles.ProfileTypeProperty] $profileTypeProperty, [PSCustomObject] $row) {
    if(($profileTypeProperty -ne $null) -and ($row -ne $null)) {
        Write-Host "ShowOnEditPageInUserMySite:'$($row.ShowInEditor)' ShowInProfilePropertiesForUser:'$($row.ShowInViewer)' ShowPropertyUpdateInNewsFeed:'$($row.InEventLog)'..." -NoNewline
        $profileTypeProperty.IsVisibleOnEditor = $row.ShowInEditor
        $profileTypeProperty.IsVisibleOnViewer = $row.ShowInViewer
        $profileTypeProperty.IsEventLog = $row.InEventLog
    }

    return $profileTypeProperty
}

function UpdateProfilePropertySubTypeAttributes([Microsoft.Office.Server.UserProfiles.ProfileSubtypeProperty] $profileSubTypeProperty, [PSCustomObject] $row) {
    if(($profileSubTypeProperty -ne $null) -and ($row -ne $null)) {
        Write-Host "Default Privacy:'$($row.PrivacyType.Trim())' Privacy Policy:'$($row.PrivacyPolicy.Trim())'..." -NoNewline
        $profileSubTypeProperty.DefaultPrivacy = [Microsoft.Office.Server.UserProfiles.Privacy]::$($row.PrivacyType.Trim())
        $profileSubTypeProperty.PrivacyPolicy = [Microsoft.Office.Server.UserProfiles.PrivacyPolicy]::$($row.PrivacyPolicy.Trim())
    }

    return $profileSubTypeProperty
}

function AddOrUpdateAttributeMapping($propertyName, $attributeName, $mappingDirection) {
    if($global:syncConnection -ne $null) {
        $connectionType = $global:syncConnection.Type

        Write-Host "'$propertyName' will be mapped to '$attributeName'..." -NoNewline
        if($connectionType -eq 'ActiveDirectory') {
            if($mappingDirection -eq 'Export') {
                $global:syncConnection.PropertyMapping.AddNewExportMapping([Microsoft.Office.Server.UserProfiles.ProfileType]::User,$propertyName,$attributeName)
            }
            else {
                $global:syncConnection.PropertyMapping.AddNewMapping([Microsoft.Office.Server.UserProfiles.ProfileType]::User,$propertyName,$attributeName)
            }
        }

        if($connectionType -eq 'ActiveDirectoryImport') {
            $global:syncConnection.AddPropertyMapping($attributeName, $propertyName)
            $global:syncConnection.Update()
        }
    }
}

function AddUserProfileProperty([PSCustomObject] $row)
{
    $create = $true
    $update = $false

    $propertyName = $row.PropertyName.Trim()
    $mappedAttribute = $row.MappedAttributeName.Trim()
    $mappedAttributeDirection = $row.MappedAttributeDirection.Trim()

    [Microsoft.Office.Server.UserProfiles.CoreProperty] $coreProperty = $global:corePropertyManager.GetPropertyByName($propertyName)

    if($coreProperty -ne $null) {
        Write-Host "User profile property '$propertyName' already exists with DisplayName:'$($coreProperty.DisplayName)' and DataType:'$($coreProperty.Type)'..." -ForegroundColor Magenta -NoNewline
        switch($global:duplicateAction)
        {
            'r' { Write-Host "Recreating..." -ForegroundColor Black -BackgroundColor White; $create= $true; $update = $false } 
            'u' { Write-Host "Updating..." -ForegroundColor Black -BackgroundColor White; $create= $false; $update = $true }
            default { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White -NoNewline; $create = $false; $update = $false }
        }
    }

    if($create) {
        Write-Host "User profile property '$propertyName' does not exist. " -ForegroundColor Magenta
        
        # create core property
        Write-Host "Creating core property. Name:'$propertyName' DisplayName:'$($row.PropertyDisplayName.Trim())' DataType:'$($row.PropertyDataType.Trim())'..." -NoNewline
        $coreProperty = $global:corePropertyManager.Create($false)

        $coreProperty.Name = $row.PropertyName.Trim()
        $coreProperty.DisplayName = $row.PropertyDisplayName.Trim()
        $coreProperty.Type = $row.PropertyDataType.Trim()
        $coreProperty.Length = GetDefaultLengthForProperty $($row.PropertyDataType.Trim())
        $global:corePropertyManager.Add($coreProperty)
        Write-Host "Done" -BackgroundColor Green

        # create Profile Type Property from core property
        Write-Host "Creating profile type property..." -NoNewline
        [Microsoft.Office.Server.UserProfiles.ProfileTypeProperty] $profileTypeProperty = $global:profileTypePropertyManager.Create($coreProperty)
        [Microsoft.Office.Server.UserProfiles.ProfileTypeProperty] $updatedProfileTypeProperty = UpdateProfilePropertyTypeAttributes $profileTypeProperty $row
        $global:profileTypePropertyManager.Add($updatedProfileTypeProperty)
        Write-Host "Done" -BackgroundColor Green

        # create Profile Sub Type Property
        Write-Host "Creating profile sub type property..." -NoNewline
        [Microsoft.Office.Server.UserProfiles.ProfileSubtypeProperty] $profileSubTypeProperty = $global:profileSubTypePropertyManager.Create($profileTypeProperty)
        [Microsoft.Office.Server.UserProfiles.ProfileSubtypeProperty] $updatedProfileSubTypeProperty = UpdateProfilePropertySubTypeAttributes $profileSubTypeProperty $row
        $global:profileSubTypePropertyManager.Add($updatedProfileSubTypeProperty)
        Write-Host "Done" -BackgroundColor Green

        # create sync attribute mapping if specified
        if((![string]::IsNullOrWhiteSpace($mappedAttribute)) -and ($global:syncConnection -ne $null)) {
            Write-Host "Creating attribute mapping for profile property..." -NoNewline
            AddOrUpdateAttributeMapping $propertyName $mappedAttribute $mappedAttributeDirection
            Write-Host "Done" -BackgroundColor Green
        }
        else {
            Write-Warning "Property mapping not created either because it was not specified or synchronization connection was not found"
        }
    }

    if ($update) {
        Write-Host "Updating profile type attributes for the property..." -NoNewline
        [Microsoft.Office.Server.UserProfiles.ProfileTypeProperty] $profileTypeProperty = $global:profileTypePropertyManager.GetPropertyByName($propertyName)
        [Microsoft.Office.Server.UserProfiles.ProfileTypeProperty] $updatedProfileTypeProperty = UpdateProfilePropertyTypeAttributes $profileTypeProperty $row
        $updatedProfileTypeProperty.Commit()
        Write-Host "Done" -BackgroundColor Green

        Write-Host "Updating profile sub type attributes for the property..." -NoNewline
        [Microsoft.Office.Server.UserProfiles.ProfileSubtypeProperty] $profileSubTypeProperty = $global:profileSubTypePropertyManager.GetPropertyByName($propertyName)
        [Microsoft.Office.Server.UserProfiles.ProfileSubtypeProperty] $updatedProfileSubTypeProperty = UpdateProfilePropertySubTypeAttributes $profileSubTypeProperty $row
        $updatedProfileSubTypeProperty.Commit()
        Write-Host "Done" -BackgroundColor Green

        if((![string]::IsNullOrWhiteSpace($mappedAttribute)) -and ($global:syncConnection -ne $null)) {
            Write-Host "Updating attribute mapping for profile property..." -NoNewline
            AddOrUpdateAttributeMapping $propertyName $mappedAttribute $mappedAttributeDirection
            Write-Host "Done" -BackgroundColor Green
        }
        
        else {
            Write-Warning "Property mapping not updated either because it was not specified or synchronization connection was not found"
        }
    }
}

#------------------ main script --------------------------------------------------
Write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

if([string]::IsNullOrWhiteSpace($mySiteHostUrl))
{
    do {
        $mySiteHostUrl = Read-Host "Specify the url of my site host"
    }
    until (![string]::IsNullOrWhiteSpace($mySiteHostUrl))
}

Write-Host "Getting my site host..." -NoNewline
$global:site = Get-SPSite $mySiteHostUrl
Write-Host "Done" -BackgroundColor Green

Write-Host "Getting service context..." -NoNewline
$global:serviceContext = [Microsoft.SharePoint.SPServiceContext]::GetContext($global:site)
Write-Host "Done" -BackgroundColor Green

Write-Host "Getting the user profile configuration manager..." -NoNewline
$global:userProfileConfigManager = New-Object Microsoft.Office.Server.UserProfiles.UserProfileConfigManager($global:serviceContext)

Write-Host "Getting the user profile property manager..." -NoNewline
$global:profilePropertyManager = $global:userProfileConfigManager.ProfilePropertyManager
Write-Host "Done" -BackgroundColor Green

Write-Host "Getting the core property manager..." -NoNewline
$global:corePropertyManager = $global:profilePropertyManager.GetCoreProperties()
Write-Host "Done" -BackgroundColor Green

Write-Host "Getting user profile type properties..." -NoNewline
$global:profileTypePropertyManager = $global:profilePropertyManager.GetProfileTypeProperties([Microsoft.Office.Server.UserProfiles.ProfileType]::User)
Write-Host "Done" -BackgroundColor Green

Write-Host "Getting user profile subtypes manager..." -NoNewline
$global:profileSubTypeManager = [Microsoft.Office.Server.UserProfiles.ProfileSubTypeManager]::Get($global:serviceContext)
Write-Host "Done" -BackgroundColor Green

Write-Host "Getting the default user profile name for the subtype..." -NoNewline
$global:defaultSubType = [Microsoft.Office.Server.UserProfiles.ProfileSubtypeManager]::GetDefaultProfileName([Microsoft.Office.Server.UserProfiles.ProfileType]::User)
Write-Host "Done" -BackgroundColor Green

Write-Host "Getting the property manager for the default user profile subtype..." -NoNewline
$global:profileSubType = $global:profileSubTypeManager.GetProfileSubtype($global:defaultSubType)
$global:profileSubTypePropertyManager = $global:profileSubType.Properties
Write-Host "Done" -BackgroundColor Green

$proceed = $true

Write-Host "`nSpecify the action to take if a duplicate profile property is found. Please note that if you choose the 'd', 'r' or 'u' option then the corresponding profile value update may not happen until the next profile synchronization.`n" -ForegroundColor White -BackgroundColor Red
$global:duplicateAction = Read-Host "What would you like to do? Delete [d]/Delete & Recreate [r]/Update [u]/Skip [s]? (d|r|u|s)"

if([string]::IsNullOrWhiteSpace($propertyName))
{
    do {
        $propertyName = Read-Host "Specify a unique name for the user profile property"
    }
    until (![string]::IsNullOrWhiteSpace($propertyName))
}

[Microsoft.Office.Server.UserProfiles.CoreProperty] $coreProperty = $global:corePropertyManager.GetPropertyByName($propertyName)
if($coreProperty -ne $null) {
    Write-Host "User profile property '$propertyName' already exists with DisplayName:'$($coreProperty.DisplayName)' and DataType:'$($coreProperty.Type)'..." -ForegroundColor Magenta -NoNewline

    switch($global:duplicateAction)
    { 
        'd' { Write-Host "Deleting..." -ForegroundColor Black -BackgroundColor White -NoNewline; DeleteUserProfileProperty $propertyName; $proceed = $false }
        'r' { Write-Host "Deleting..." -ForegroundColor Black -BackgroundColor White -NoNewline; DeleteUserProfileProperty $propertyName; $proceed = $true }
        's' { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White; $proceed = $false }
        default {}
    }
}

if($proceed) {
    Write-Host "`nCreating/Updating individual user profile property..." -ForegroundColor Green

    if([string]::IsNullOrWhiteSpace($propertyDisplayName))
    {
        do {
            $propertyDisplayName = Read-Host "Specify a display name for the property"
        }
        until (![string]::IsNullOrWhiteSpace($propertyDisplayName))
    }

    if([string]::IsNullOrWhiteSpace($propertyDataType))
    {
        do {
            $propertyDataType = Read-Host "Specify property data type [biginteger|binary|boolean|date|datenoyear|datetime|email|float|guid|html|integer|person|string|stringmultivalue|timezone|url]"
        }
        until (![string]::IsNullOrWhiteSpace($propertyDataType))
    }

    if([string]::IsNullOrWhiteSpace($propertyPrivacyType))
    {
        do {
            $propertyPrivacyType = Read-Host "Specify property privacy type. Who can view the property value? [contacts|manager|notset|organization|public|private]"
        }
        until (![string]::IsNullOrWhiteSpace($propertyPrivacyType))
    }

    if([string]::IsNullOrWhiteSpace($propertyPrivacyPolicy))
    {
        do {
            $propertyPrivacyPolicy = Read-Host "Specify property privacy policy [disabled|mandatory|optin|optout]"
        }
        until (![string]::IsNullOrWhiteSpace($propertyPrivacyPolicy))
    }

    $global:syncConnection = $null
    $syncConnectionName = Read-Host "Please enter the name of the user profile synchronization connection you'd like to use. Leave empty if not mapping the user profile property"
    if(![string]::IsNullOrWhiteSpace($syncConnectionName)) {
        Write-Warning "Getting the synchronization connection. You may see an error if this is a FIM connection and FIM Service is running under a different credential than the one running this script. If that happens, then temporarily switch the FIM service to run under the account that is running this script and add this account to 'User Profile Service Application' administrator group in Central Administration..."
        $global:syncConnection = $global:userProfileConfigManager.ConnectionManager[$syncConnectionName]
        if($global:syncConnection -ne $null) {
            Write-Host "Successfully obtained connection named '$($global:syncConnection.DisplayName)' of type '$($global:syncConnection.Type)'..." -NoNewline
            Write-Host "Done" -BackgroundColor Green
        
            $mappedAttributeDirection = "Import"
            if([string]::IsNullOrWhiteSpace($mappedAttributeName))
            {
                $mappingResponse = Read-Host "Should this property be mapped to a source attribute from the synchronization connection (AD/BCS etc)?[y|n]"
        
                if($mappingResponse -eq 'y') {
                    $mappedAttributeName = Read-Host "Specify the name of the mapped attribute (may be case-sensitive based on source)"
                    try {
                        [ValidateSet('i','e')] $mappingDirectionResponse = Read-Host "Mapping type import(i) or export(e)? [i|e]"
                    }
                    catch {}
                    if($mappingDirectionResponse -eq 'e') {
                        $mappedAttributeDirection = "Export"
                    }
                }
            }
        }
    }

    if($global:syncConnection -eq $null) {
        Write-Warning "This user profile property will NOT be mapped or synchronized. Either the connection name was not specified or no connection with the specified name was found."
    }

    $row = @{PropertyName=$propertyName;PropertyDisplayName=$propertyDisplayName;
                PropertyDataType=$propertyDataType;
                PrivacyType=$propertyPrivacyType;PrivacyPolicy=$propertyPrivacyPolicy;
                ShowInEditor=$false;ShowInViewer=$true;InEventLog=$false;
                MappedAttributeName=$mappedAttributeName;MappedAttributeDirection=$mappedAttributeDirection
            }
    
    AddUserProfileProperty $row
}

Write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow