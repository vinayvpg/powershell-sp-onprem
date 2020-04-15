<#  
.Description  
    Provisions content types in an SPWeb based on a csv file or individually
         
.Parameter - ctypeCSVPath 
    Full path to the csv file containing content type definitions. If this is specified, then other parameters are ignored.
.Parameter - webUrl 
    Url of the web where content type should be created. Only used if csv file is not specified.
.Parameter - ctypeName 
    Name of the content type to be created. Only used if csv file is not specified.
.Parameter - ctypeParent 
    Name of the parent of content type to be created. Only used if csv file is not specified.
.Parameter - siteColumns 
    Semicolon delimited list of display names of site columns to be included in the content type to be created. Only used if csv file is not specified.
.Usage 
    Create content types as specified in a csv file
     
    PS >  Create-ContentTypes.ps1 -ctypesCSVPath "c:\data\ctypes.csv"
.Usage 
    Create a single content type
     
    PS >  Create-ContentTypes.ps1 -webUrl "http://web.company.com" -ctypeName "My Document Content Type" -ctypeParent "Document" -siteColumns "Location; Status; Other Site Column 1"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Full path to csv file containing content type definitions")]
    [string] $ctypeCSVPath="E:\Scripts\Information Architecture\DCTM_ContentTypes_PROD.csv",
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Url of the web where content type will be created")]
    [string] $webUrl,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Name of the content type")]
    [string] $ctypeName,

    [Parameter(Mandatory=$false, Position=3, HelpMessage="Name of the parent content type")]
    [string] $ctypeParent,

    [Parameter(Mandatory=$false, Position=4, HelpMessage="Semicolon delimited list of display names of included site columns")]
    [string] $siteColumns
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null

function DeleteExistingCType([Microsoft.SharePoint.SPWeb] $web, [Microsoft.SharePoint.SPContentType] $ct)
{
    if($ct -ne $null) {
        try {
            # get the content type usage in the entire site collection
            $usages = [Microsoft.SharePoint.SPContentTypeUsage]::GetUsages($ct)

            $usages | % {
                $inUseOutsideWeb = $false
                Write-Host "`nContent type is in use at url '$($_.Url)'..." -ForegroundColor Gray
                if($_.IsUrlToList) {
                    try {
                        [Microsoft.SharePoint.SPList] $list = $web.GetList($_.Url)
                    }
                    catch {
                        Write-Host "Content type is in use in a different scope from where it is being created. " -ForegroundColor Red -NoNewline
                        Write-Host "It will NOT be deleted. " -BackgroundColor Red -NoNewline
                        Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White

                        $inUseOutsideWeb = $true

                        break
                    }

                    [Microsoft.SharePoint.SPQuery] $query = New-Object Microsoft.SharePoint.SPQuery
                    $query.Query = "<Where><Eq><FieldRef Name='ContentType'/><Value Type='Text'>" + $ct.Name + "</Value></Eq></Where>"
                    [Microsoft.SharePoint.SPListItemCollection] $listItems = $list.GetItems($query)
                    Write-Host "$($listItems.Count) items belonging to content type '$($ct.Name)' were found in list '$($list.Title)'. Deleting items" -ForegroundColor Gray -NoNewline
                    for ($i = 0; $i -lt $listItems.Count; $i++)
                    { 
                        Write-Host "." -ForegroundColor Gray
                        $listItems[$i].Delete()
                    }
                    Write-Host "Deleting list content type with id '$($_.Id)' in list named '$($list.Title)' at url '$($_.Url)'..." -ForegroundColor Gray -NoNewline
                    $list.ContentTypes.Delete($_.Id)
                    Write-Host "Done" -BackgroundColor Green
                }
            }
            
            if(!$inUseOutsideWeb) {   
                Write-Host "Deleting web content type..." -ForegroundColor Black -BackgroundColor White -NoNewline

                $web.ContentTypes.Delete($ct.Id) | Out-Null

                Write-Host "Done" -BackgroundColor Green
                
                return $true
            }
            else {
                return $false
            }
        }
        catch {
            Write-Host "It will NOT be deleted. " -BackgroundColor Red -NoNewline
            Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White
            Write-Host "Content type is in use, possibly as a parent of another content type in the same web. " -ForegroundColor Red

            Write-Host $error[0] -ForegroundColor Red

            return $false
        }
    }
}

function AddFieldLinksToCtype([Microsoft.SharePoint.SPWeb] $web, [Microsoft.SharePoint.SPContentType] $ct, [PSCustomObject] $row) 
{
    if(($web -ne $null) -and ($ct -ne $null)) {
        $serverRelUrl = $web.ServerRelativeUrl
        
        $includedSiteColumns = $row.IncludedSiteColumns -split ";"
        
        foreach($includedSiteColumn in $includedSiteColumns) {
                
            [Microsoft.SharePoint.SPField] $field = $null
                 
            # try to find field by either the display name or internal name
            $f = $web.AvailableFields | ?{($_.Title.ToString().ToUpper() -eq $includedSiteColumn.Trim().ToUpper()) -or ($_.InternalName.ToString().ToUpper() -eq $includedSiteColumn.Trim().ToUpper())}
                
            if ($f -ne $null) {
                if($f.GetType().BaseType.Name -eq 'Array'){
                    $field = $f[0]
                    Write-Host "While searching for the field, multiple site columns with the same name '$includedSiteColumn' were found. Selecting '$($field.InternalName)' of type '$($field.TypeAsString)' with ID '$($field.Id)' in group '$($field.Group)' as the one to add..." -ForegroundColor Gray -NoNewline
                }
                else {
                    $field = $f
                }
            }

            if($field -ne $null) {
                # check if the fieldlink already exists in the content type               
                [Microsoft.SharePoint.SPFieldLink] $fieldLink = $ct.FieldLinks[$field.Id]

                if($fieldLink -eq $null) {
                    Write-Host "Adding field '$($includedSiteColumn.Trim())' to content type '$($row.ContentTypeName)'..." -ForegroundColor Gray -NoNewline

                    $fieldLink = New-Object Microsoft.SharePoint.SPFieldLink($field)
                    $ct.FieldLinks.Add($fieldLink)
                    $ct.UpdateIncludingSealedAndReadOnly($true)

                    Write-Host "Done" -BackgroundColor Green
                }
                else {
                    Write-Host "Field '$($includedSiteColumn.Trim())' already exists in content type '$($row.ContentTypeName)'..." -ForegroundColor Gray -NoNewline
                    Write-Host "Skipping..." -BackgroundColor White -ForegroundColor Black
                }
            }
            else {
                Write-Host "Field '$includedSiteColumn' was not found. The field is either not available at this scope or has not been created. This field WILL NOT BE added to content type '$($row.ContentTypeName)'. " -ForegroundColor Red
            }
        }
    }
}

function DeleteAction([Microsoft.SharePoint.SPWeb] $web, [Microsoft.SharePoint.SPContentType] $ct)
{
    $result = $false

    if($global:confirmDelete -eq 'y') { 
        $result = DeleteExistingCType $web $ctype
    } 
    else { 
        Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White 
    }

    return $result
}

function AddCTypeToWeb([PSCustomObject] $row)
{
    Write-Host "`n------------------------------------------------------------------------------------------------" -ForegroundColor Gray

    $newCtype = $null

    $web = Get-SPWeb $row.WebUrl

    if($web -ne $null) {
        Write-Host "Processing content type '$($row.ContentTypeName)' for web $($row.WebUrl)`n" -ForegroundColor Green
        $serverRelUrl = $web.ServerRelativeUrl

        $create = $false

        $ctype = $null
       
        foreach($ct in $web.AvailableContentTypes)
        {
            if($ct.Name.ToUpper() -eq $row.ContentTypeName.ToUpper())
            {
                $ctype = $ct
                break
            }
        }

        if($ctype -ne $null) {
            if($serverRelUrl.ToLower() -eq $ctype.Scope.ToLower()) {
                # ctype exists and was created at the web level
                Write-Host "Content Type '$($ctype.Name)' with ID '$($ctype.Id.ToString())' already exists in this web. " -ForegroundColor Cyan -NoNewline
                
                switch($global:duplicateAction)
                { 
                    'd' { DeleteAction $web $ctype | out-Null } 
                    'r' { $create = DeleteAction $web $ctype }
                    'm' { Write-Host "Modifying..." -ForegroundColor Black -BackgroundColor White; $ct = $web.ContentTypes | ?{ $_.Id.ToString() -eq $ctype.Id.ToString() }; AddFieldLinksToCtype $web $ct $row }
                    's' { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White }
                    default { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White }
                }                                              
            }
            else {
                # ctype exists but was created at a parent level
                Write-Host "Content Type '$($ctype.Name)' with ID '$($ctype.Id.ToString())' is already available in this web from a parent site at '$($ctype.Scope)'. " -ForegroundColor Cyan -NoNewline
                Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White
            }
        }
        else {
            Write-Host "Content Type '$($row.ContentTypeName)' does not exist in this web. " -ForegroundColor Cyan
            $create = $true
        }

        if($create) {
            [Microsoft.SharePoint.SPContentType] $parent = $null

            $p = $web.AvailableContentTypes | ?{$_.Name -eq $row.ContentTypeParent}

            if($p -ne $null) {
                if($p.GetType().BaseType.Name -eq 'Array'){
                    $parent = $p[0]
                    Write-Host "While searching for the parent of this content type, multiple content types with the same name '$($row.ContentTypeParent)' were found. Selecting first one with Id '$($parent.Id.ToString())' as the parent..." -ForegroundColor Cyan
                }
                else {
                   $parent = $p
                }
            }

            if($parent -eq $null) {
                Write-Host "Parent content type '$($row.ContentTypeParent)' was not found. It either does not exist or is not available at this scope. " -ForegroundColor Cyan -NoNewline
                
                $createParent = $false

                if($global:csv -ne $null) {
                    Write-Host "Scanning for '$($row.ContentTypeParent)' definition in the csv file..." -ForegroundColor Cyan -NoNewline
                    
                    $parentRowInCSV = $global:csv | ?{ $_.ContentTypeName -eq $row.ContentTypeParent }
                    
                    if($parentRowInCSV -ne $null) {
                        $createParent = $true
                        Write-Host "Found '$($parentRowInCSV.ContentTypeName)' definition in the csv file. " -ForegroundColor Cyan -NoNewline
                        Write-Host "Creating..." -ForegroundColor Black -BackgroundColor White
                    }
                }

                if($createParent) {
                    $parent = AddCTypeToWeb $parentRowInCSV
                }
                else {
                    Write-Host "Content type '$($row.ContentTypeName)' will NOT be created. " -ForegroundColor Red -NoNewline
                    Write-Host "Skipping..." -BackgroundColor Red
                    return
                }
            }

            Write-Host "Creating content type '$($row.ContentTypeName)' in group '$($row.Group)' with '$($parent.Name)($($parent.Id.ToString()))' as parent..." -ForegroundColor Cyan -NoNewline

            $newCtype = New-Object Microsoft.SharePoint.SPContentType -ArgumentList @($parent, $web.ContentTypes, $($row.ContentTypeName))
            $newCtype.Group = $row.Group
            $newCtype.Description = $row.Description

            # make sure content type is added to content type collection of SPWeb before attempting to modify field links
            $web.ContentTypes.Add($newCtype) | Out-Null
            
            Write-Host "Done" -BackgroundColor Green

            if(![string]::IsNullOrWhiteSpace($row.IncludedSiteColumns)) {
                AddFieldLinksToCtype $web $newCtype $row
            }

            $web.Update()
        }
    }
    
    $web.Dispose()

    return $newCtype
}

function ProcessCSV([string] $csvPath)
{
    if(![string]::IsNullOrEmpty($csvPath))
    {
        write-host "`nProcessing csv file $csvPath..." -ForegroundColor Green
        $global:csv = Import-Csv -Path $csvPath
    }

    if($global:csv -ne $null)
    {
        $global:csv | % {
            AddCTypeToWeb $_ | out-null
        }
    }
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$global:csv = $null 

Write-Host "`nSpecify the action to take if a duplicate content type is found at the installation scope. Please note that if you choose the 'd' or 'r' option below, then ALL existing content in the scope (list items, documents) utilizing that content type will be PERMANENTLY DELETED. `n" -ForegroundColor White -BackgroundColor Red

$global:duplicateAction = Read-Host "What would you like to do? Delete and do not recreate [d]/Delete and recreate [r]/Modify if different [m]/Skip [s]? (d|r|m|s)"

if(($global:duplicateAction -eq 'd') -or ($global:duplicateAction -eq 'r')) {
    $global:confirmDelete = Read-Host "You are choosing to purge ALL existing content if a content type exists and is in use. Purge? [y|n]"
}
 
if(![string]::IsNullOrWhiteSpace($ctypeCSVPath))
{
    ProcessCSV $ctypeCSVPath
}
else 
{
    write-host "You did not specify a csv file containing content type definitions...." -ForegroundColor Cyan

    $csvPathEntryReponse = Read-Host "Would you like to enter the full path of the csv file? [y|n]"
    if($csvPathEntryReponse -eq 'y') {
        do {
            $path = Read-Host "Enter full path to the csv file containing content type definitions."
        }
        until (![string]::IsNullOrWhiteSpace($path))

        ProcessCSV $path
    }
    else {
        Write-Host "Creating individual content type..." -ForegroundColor Green
        if([string]::IsNullOrWhiteSpace($webUrl))
        {
            do {
                $webUrl = Read-Host "Specify the full url of the web where the content type will be created"
            }
            until (![string]::IsNullOrWhiteSpace($webUrl))
        }

        if([string]::IsNullOrWhiteSpace($ctypeName))
        {
            do {
                $ctypeName = Read-Host "Specify the name for the content type"
            }
            until (![string]::IsNullOrWhiteSpace($ctypeName))
        }

        if([string]::IsNullOrWhiteSpace($ctypeParent))
        {
            do {
                $ctypeParent = Read-Host "Specify the name of the parent content type"
            }
            until (![string]::IsNullOrWhiteSpace($ctypeParent))
        }

        if([string]::IsNullOrWhiteSpace($siteColumns))
        {
            $siteColumns = Read-Host "Specify a semicolon delimited list of site columns included in this content type. Leave empty if you simply wish to inherit the parent content type."
        }

        $row = @{WebUrl=$webUrl;ContentTypeName=$ctypeName;ContentTypeParent=$ctypeParent;
                Description=[string]::Empty;Group="Murphy Oil Documents";
                IncludedSiteColumns=$siteColumns}
    
        AddCTypeToWeb $row | Out-Null
    }
}

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow