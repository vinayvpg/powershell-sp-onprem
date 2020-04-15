<#  
.Description  
    Provisions lists and libraries in an SPWeb based on a csv file or individually
         
.Parameter - listDataCSVPath 
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
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Full path to csv file containing details of lists to provision")]
    [string] $listDataCSVPath = "E:\Scripts\Information Architecture\DCTM_Lists_PROD_Load_AfterEMC.csv",
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Url of the web where list will be provisioned")]
    [string] $webUrl,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Name of the list")]
    [string] $listTitle,

    [Parameter(Mandatory=$false, Position=3, HelpMessage="TemplateId of the list")]
    [string] $listTemplateId,

    [Parameter(Mandatory=$false, Position=4, HelpMessage="Default content type for the list")]
    [string] $defaultCTypeName
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null

function DeleteExistingList([Microsoft.SharePoint.SPWeb] $web, [Microsoft.SharePoint.SPList] $list)
{
    if($list -ne $null) {
        try {   
            Write-Host "Deleting list..." -ForegroundColor Black -BackgroundColor White -NoNewline

            $web.Lists.Delete($list.Id) | Out-Null

            Write-Host "Done" -BackgroundColor Green
                
            return $true
        }
        catch {
            Write-Host "It will NOT be deleted. " -BackgroundColor Red -NoNewline
            Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White

            Write-Host $error[0] -ForegroundColor Red

            return $false
        }
    }
}

function DeleteAction([Microsoft.SharePoint.SPWeb] $web, [Microsoft.SharePoint.SPList] $list)
{
    $result = $false

    if($global:confirmDelete -eq 'y') { 
        $result = DeleteExistingList $web $list
    } 
    else { 
        Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White 
    }

    return $result
}

function AddIndexesToList([Microsoft.SharePoint.SPWeb] $web, [Microsoft.SharePoint.SPList] $list, [PSCustomObject] $row)
{
    if(($web -ne $null) -and ($list -ne $null) -and ($row -ne $null)) {
        $indexedColumns = $row.IndexedColumns -split ";"
        
        foreach($indexedColumn in $indexedColumns) {
            [Microsoft.SharePoint.SPField] $field = $null
                 
            # try to find field by either the display name or internal name
            $f = $web.AvailableFields | ?{($_.Title.ToString().ToUpper() -eq $indexedColumn.Trim().ToUpper()) -or ($_.InternalName.ToString().ToUpper() -eq $indexedColumn.Trim().ToUpper())}
                
            if ($f -ne $null) {
                if($f.GetType().BaseType.Name -eq 'Array'){
                    $field = $f[0]
                    Write-Host "--While searching for the field, multiple site columns with the same name '$indexedColumn' were found. Selecting '$($field.InternalName)' of type '$($field.TypeAsString)' with ID '$($field.Id)' in group '$($field.Group)' as the one to index..." -ForegroundColor Gray -NoNewline
                }
                else {
                    $field = $f
                }
            }

            if($field -ne $null) {
                Write-Host "--Creating index on field '$($indexedColumn.Trim())' for list '$($row.ListTitle)'..." -ForegroundColor Gray -NoNewline

                # check if the column has been indexed for the list
                $idxField = $list.FieldIndexes[$field.Id]

                if($idxField -eq $null) {
                    [Microsoft.SharePoint.SPField] $lf = $list.Fields[$($indexedColumn.Trim())]
                    if($lf -ne $null) {
                        if($lf.Indexable) {
                            $lf.Indexed = $true
                            $lf.Update()
                            $list.FieldIndexes.Add($lf)

                            Write-Host "Done" -BackgroundColor Green
                        }
                        else {
                            Write-Host "This field is NOT indexable..." -ForegroundColor Gray -NoNewline
                            Write-Host "Skipping..." -BackgroundColor White -ForegroundColor Black
                        }
                    }
                }
                else {
                    Write-Host "Index already exists on field '$($indexedColumn.Trim())' for list '$($row.ListTitle)'..." -ForegroundColor Gray -NoNewline
                    Write-Host "Skipping..." -BackgroundColor White -ForegroundColor Black
                }
            }
            else {
                Write-Host "Field '$indexedColumn' was not found. The field is either not available at this scope or has not been created. This field WILL NOT indexed." -ForegroundColor Red
            }

            $list.Update()
        }
    }
}

function ModifyExistingList([Microsoft.SharePoint.SPWeb] $web, [Microsoft.SharePoint.SPList] $list, [PSCustomObject] $row)
{
    if(($web -ne $null) -and ($list -ne $null) -and ($row -ne $null)) {
        # Manage quick launch setting
        if(![string]::IsNullOrWhiteSpace($row.OnQuickLaunch)) {
            Write-Host "-Setting OnQuickLaunch to '$($row.OnQuickLaunch)' for list or library..." -ForegroundColor Cyan -NoNewline

            if($row.OnQuickLaunch.Trim().ToUpper() -eq "TRUE") {
                $list.OnQuickLaunch = $true
            }
            else {
                $list.OnQuickLaunch = $false
            }

            $list.Update()

            Write-Host "Done" -BackgroundColor Green
        }

        # Manage versioning setting
        if(![string]::IsNullOrWhiteSpace($row.EnableVersioning)) {
            Write-Host "-Setting versioning to '$($row.EnableVersioning)' for list or library..." -ForegroundColor Cyan -NoNewline

            if($row.EnableVersioning.Trim().ToUpper() -eq "TRUE") {
                $list.EnableVersioning = $true
            }
            else {
                $list.EnableVersioning = $false
            }

            $list.Update()

            Write-Host "Done" -BackgroundColor Green
        }

        # Enable management of content types if default ctype specified
        if(![string]::IsNullOrWhiteSpace($row.DefaultContentTypeName)) {

            $ctype = $null

            foreach($ct in $web.AvailableContentTypes)
            {
                if($ct.Name.ToUpper() -eq $row.DefaultContentTypeName.Trim().ToUpper())
                {
                    $ctype = $ct
                    break
                }
            }

            if($ctype -ne $null) {
                Write-Host "-Adding content type '$($row.DefaultContentTypeName)' as default content type to list or library..." -ForegroundColor Cyan -NoNewline

                if($list.ContentTypesEnabled) {
                    # content types already enabled, check if new default already exists in the list
                    $cntType = $list.ContentTypes | ? { $_.Name.Trim().ToUpper() -eq $row.DefaultContentTypeName.Trim().ToUpper() }
                    if($cntType -ne $null) {
                       Write-Host "Already exists...Skipping" -ForegroundColor Black -BackgroundColor White
                    }
                    else {
                        $list.ContentTypes.Add($cntType)
                        $list.Update()

                        Write-Host "Done" -BackgroundColor Green
                    }
                }
                else {

                    $list.ContentTypesEnabled = $true
                    $listCType = $list.ContentTypes.Add($ctype)

                    Write-Host "Done" -BackgroundColor Green

                    Write-Host "Removing other content types from list or library..." -ForegroundColor Gray -NoNewline
                        
                    $existingCTypes = [System.Collections.ArrayList] @()
                    $list.ContentTypes | % { $existingCTypes.Add($_) }
                    $existingCTypes | % { if(($_.Name -ne 'Folder') -and ($listCType.ID -ne $_.ID)) { Write-Host "Removing '$($_.Name)'..." -ForegroundColor Black -BackgroundColor White -NoNewLine; $newList.ContentTypes.Delete($($_.ID)); Write-Host "Done" -BackgroundColor Green } }

                    $list.Update()
                }
            }
            else {
                Write-Host "Content type '$($row.DefaultContentTypeName)' was not found in this web. It has not been added to this list or library..." -ForegroundColor Gray -NoNewline
            }
        }

        # Enable indexed columns if specified
        if(![string]::IsNullOrWhiteSpace($row.IndexedColumns)) {
            Write-Host "-Creating index(es) for columns '$($row.IndexedColumns)' on list..." -ForegroundColor Cyan

            AddIndexesToList $web $list $row
        }
    }
}

function AddListToWeb([PSCustomObject] $row)
{
    Write-Host "`n------------------------------------------------------------------------------------------------" -ForegroundColor Gray

    $newList = $null

    $web = Get-SPWeb $row.WebUrl

    if($web -ne $null) {
        Write-Host "Processing '$($row.ListTitle)' for web $($row.WebUrl)`n" -ForegroundColor Green
        
        $serverRelUrl = $web.ServerRelativeUrl

        $list = $web.Lists.TryGetList($($row.ListTitle))

        $create = $false

        if($list -ne $null) {
            # list already exists at the web level
            Write-Host "List or library with name '$($row.ListTitle)' already exists in this web. " -ForegroundColor Cyan
                
            switch($global:duplicateAction)
            { 
                'd' { DeleteAction $web $list | out-Null } 
                'r' { $create = DeleteAction $web $list }
                'm' { ModifyExistingList $web $list $row | Out-Null }
                's' { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White }
                default { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White }
            }
        }
        else {
            Write-Host "List or library '$($row.ListTitle)' does not exist in this web. " -ForegroundColor Cyan
            $create = $true
        }

        if($create) {
            Write-Host "Creating list or library '$($row.ListTitle)'..." -ForegroundColor Cyan -NoNewline

            $newListGuid = $web.Lists.Add($($row.ListTitle), $($row.ListDescription), $($row.ListTemplateId))

            if($newListGuid -ne $null) {
                Write-Host "Done" -BackgroundColor Green

                $newList = $web.Lists.TryGetList($($row.ListTitle))

                ModifyExistingList $web $newList $row | Out-Null
            }
            
            $web.Update()
        }
    }
    
    $web.Dispose()

    return $newList
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
            AddListToWeb $_ | out-null
        }
    }
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$global:csv = $null 

Write-Host "`nSpecify the action to take if a duplicate list/library is found at the installation scope. Please note that if you choose the 'd' or 'r' option below, then ALL existing content in the scope (list items, documents) will be PERMANENTLY DELETED. `n" -ForegroundColor White -BackgroundColor Red

$global:duplicateAction = Read-Host "What would you like to do? Delete and do not recreate [d]/Delete and recreate [r]/Modify [m]/Skip [s]? (d|r|m|s)"

if(($global:duplicateAction -eq 'd') -or ($global:duplicateAction -eq 'r')) {
    $global:confirmDelete = Read-Host "You are choosing to purge ALL existing content if a list/library exists. Purge? [y|n]"
}
 
if(![string]::IsNullOrWhiteSpace($listDataCSVPath))
{
    ProcessCSV $listDataCSVPath
}
else 
{
    write-host "You did not specify a csv file containing information about the lists/libraries to provision...." -ForegroundColor Cyan

    $csvPathEntryReponse = Read-Host "Would you like to enter the full path of the csv file? [y|n]"
    if($csvPathEntryReponse -eq 'y') {
        do {
            $path = Read-Host "Enter full path to the csv file containing list information."
        }
        until (![string]::IsNullOrWhiteSpace($path))

        ProcessCSV $path
    }
    else {
        Write-Host "Creating individual list/library..." -ForegroundColor Green
        if([string]::IsNullOrWhiteSpace($webUrl))
        {
            do {
                $webUrl = Read-Host "Specify the full url of the web where the list/library will be provisioned"
            }
            until (![string]::IsNullOrWhiteSpace($webUrl))
        }

        if([string]::IsNullOrWhiteSpace($listTitle))
        {
            do {
                $listTitle = Read-Host "Specify the name of the list/library"
            }
            until (![string]::IsNullOrWhiteSpace($listTitle))
        }

        if([string]::IsNullOrWhiteSpace($listTemplateId))
        {
            do {
                $listTemplateId = Read-Host "Specify the numeric template Id of the list/library to be provisioned. Generic custom list = 100, Document library = 101 (Refer the following link for template Ids - https://msdn.microsoft.com/en-us/library/dd958106(v=office.12).aspx)"
            }
            until (![string]::IsNullOrWhiteSpace($listTemplateId))
        }

        if([string]::IsNullOrWhiteSpace($defaultCTypeName))
        {
            $defaultCTypeName = Read-Host "Specify a default content type for the list/library. This will also enable managment of content types on the list or library. Leave empty if you do not wish to enable this setting."
        }
        
        $row = @{WebUrl=$webUrl;ListTitle=$listTitle;ListTemplateId=$listTemplateId;DefaultContentTypeName=$defaultCTypeName;OnQuickLaunch='FALSE';EnableVersioning='FALSE';IndexedColumns=[string]::Empty}
    
        AddListToWeb $row | Out-Null
    }
}

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow