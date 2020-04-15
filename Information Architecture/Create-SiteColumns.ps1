<#  
.Description  
    Provisions site columns in an SPWeb based on a csv file or individually
         
.Parameter - siteColumnsCSVPath 
    Full path to the csv file containing site column definitions. If this is specified, then other parameters are ignored.
.Parameter - webUrl 
    Url of the web where site column should be created. Only used if csv file is not specified.
.Parameter - siteColumnName 
    Internal name of the site column to be created. Only used if csv file is not specified.
.Parameter - siteColumnDisplayName 
    Display name of the site column to be created. Only used if csv file is not specified.
.Parameter - siteColumnFieldType 
    SharePoint field type of the site column to be created. Only used if csv file is not specified.
.Parameter - termSetName 
    Name of the termset associated with the site column if site column is a 'Taxonomy' field type. Only used if csv file is not specified and siteColumnFieldType is 'TaxonomyFieldType' or 'TaxonomyFieldTypeMulti'
.Usage 
    Create site columns as specified in a csv file
     
    PS >  Create-SiteColumns.ps1 -siteColumnsCSVPath "c:\data\sitecolumns.csv"
.Usage 
    Create a single site column
     
    PS >  Create-SiteColumns.ps1 -webUrl "http://sitecoll.company.com" -siteColumnName "myColumn" -siteColumnDisplayName "My Name" -siteColumnFieldType "TaxonomyFieldType" -termSetName "Department"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Full path to csv file containing site column definitions")]
    [string] $siteColumnsCSVPath="E:\Scripts\Information Architecture\DCTM_SiteColumns_PROD.csv",
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Url of the web where site columns will be created")]
    [string] $webUrl,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Internal name of site column")]
    [string] $siteColumnName,

    [Parameter(Mandatory=$false, Position=3, HelpMessage="Display name of site column")]
    [string] $siteColumnDisplayName,

    [Parameter(Mandatory=$false, Position=4, HelpMessage="Field type of site column. Case-sensitive.")]
    [string] $siteColumnFieldType,

    [Parameter(Mandatory=$false, Position=5, HelpMessage="Name of associated termset if field is TaxonomyFieldType or TaxonomyFieldTypeMulti")]
    [string] $termSetName
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null

function DeleteExistingField([Microsoft.SharePoint.SPWeb]$web, [Microsoft.SharePoint.SPField] $field)
{
    if(($web -ne $null) -and ($field -ne $null)) {
        
        try {
            if(($field.TypeAsString -eq "TaxonomyFieldType") -or ($field.TypeAsString -eq "TaxonomyFieldTypeMulti")) {
                # delete the note field associated with taxonomy field
                $noteFieldId = $field.TextField
                $noteFields = $web.Fields | ?{$_.Id -eq $noteFieldId}
                if($noteFields -ne $null) {
                    foreach($noteField in $noteFields) {
                        Write-Host "Deleting note field with Id '$noteField' associated with taxonomy field '$($field.Title)'..." -ForegroundColor Black -BackgroundColor White -NoNewline
                        $noteField.Delete()
                    }
                }
                Write-Host "Done" -BackgroundColor Green
            } 
            # delete main field
            Write-Host "Deleting field..." -ForegroundColor Black -BackgroundColor White -NoNewline

            $web.Fields.Delete($field.InternalName)

            Write-Host "Done" -BackgroundColor Green

            return $true
        }
        catch {
            Write-Host "Field '$($field.Title)' was NOT deleted..." -BackgroundColor Red

            Write-Host $error[0] -ForegroundColor Red

            return $false
        }
    }
}

function MapTaxonomyField([Microsoft.SharePoint.SPWeb]$web, [Microsoft.SharePoint.SPField] $field, [PSCustomObject] $row)
{
    $termStoreName = $global:defaultTermStoreName

    Write-Host "'$($row.Name)' is a taxonomy field. Connecting to managed metadata service..." -ForegroundColor Gray -NoNewline

    $site = $web.Site

    $taxonomySession = New-Object Microsoft.SharePoint.Taxonomy.TaxonomySession $site, $true

    if($taxonomySession -ne $null)
    {
        Write-Host "Done" -BackgroundColor Green
        Write-Host "Fetching term store named '$termStoreName' for the farm. " -ForegroundColor Gray -NoNewline
        $store = $taxonomySession.TermStores[$termStoreName]
    }
    else
    {
        Write-Host "Failed" -BackgroundColor Red
        Write-Host "Could not connect to managed metadata service for this farm. The site column '$($row.Name)' will not be associated with the term set. Exiting...." -ForegroundColor Red
        return
    }

    if($store -eq $null)
    {
        Write-Host "Failed" -BackgroundColor Red
        Write-Host "Term store '$termStoreName' was not found in this farm. The site column '$($row.Name)' will not be associated with the term set. Exiting...." -ForegroundColor Red
        return
    }
    else
    {
        Write-Host "Done" -BackgroundColor Green
    }

    $termSetColl = $store.GetTermSets($row.TermSet, 1033)

    if($termSetColl -ne $null) {
        if($termSetColl.Count -gt 0) {
            if($termSetColl.Count -gt 1) {
                Write-Host "Multiple termsets with the name $($row.TermSet) were found. Using the first one..." -ForegroundColor Cyan
            }

            $termSet = $termSetColl[0]

            Write-Host "Termset '$($termSet.Name)' with Id '$($termSet.Id)' will be associated with the site column '$($row.Name)'..." -ForegroundColor Gray -NoNewline

            [Microsoft.SharePoint.Taxonomy.TaxonomyField] $taxField = $field -as [Microsoft.SharePoint.Taxonomy.TaxonomyField]
            $taxField.SspId = $store.Id
            $taxField.TermSetId = $termSet.Id

            try {
                if(![string]::IsNullOrWhiteSpace($row.Default)) {
                    $defaultsString = [string]::Empty
                    $trimChars = @(';', '#')

                    $defs = $row.Default -split ";"
                    if($defs.Count -gt 0) {
                        $defs | %{
                            $def = $_.Trim()
                            
                            $terms = $termSet.GetTerms($def, 1033, $false)
                
                            if($terms -ne $null) {
                                if($terms.Count -gt 0) {
                                    $defaultTerm = $terms[0]
                                    
                                    if($defaultTerm -ne $null) {
                                        # taxonomy field values are in format wssid;#term label|term guid
                                        # taxonomy multi select field values are in format wssid;#term label|term guid;#wssid1;#term label1|term guid1
                                        $wssId = -1
                                
                                        # check if the term is present in taxonomy  hidden list. If present, get the wssId from there
                                        $wssIds = [Microsoft.SharePoint.Taxonomy.TaxonomyField]::GetWssIdsOfTerm($site, $store.Id, $termSet.Id, $defaultTerm.Id, $false, 1)

                                        if($wssIds -ne $null) {
                                            $wssId = $wssIds[0]
                                        }
                                        if($wssId -eq -1) {
                                            # term is not present in taxonomy hidden list of site collection. Invoke the private method to create the entry and return wssId.
                                            [System.Reflection.MethodInfo] $mi_AddTaxonomyGuidToWss = $taxField.GetType().GetMethod("AddTaxonomyGuidToWss", @([System.Reflection.BindingFlags]::NonPublic, [System.Reflection.BindingFlags]::Static), $null, @( $site.GetType(), $defaultTerm.GetType(), [System.Type]::GetType("System.Boolean")), $null)
                                            if ($mi_AddTaxonomyGuidToWss -ne $null) {
                                                $wssId = $mi_AddTaxonomyGuidToWss.Invoke($null, @( $site, $defaultTerm, $false )) -as [System.Int32]
                                            }
                                        }
                                
                                        $defaultsString = $defaultsString + $wssId + ";#" + $($defaultTerm.Name) + "|" + $($defaultTerm.Id.ToString()) + ";#"
                                    }
                                }
                            }
                        }

                        if(![string]::IsNullOrWhiteSpace($defaultsString)) {
                            $defaultsString = $defaultsString.Trim($trimChars)
                        }

                        $taxField.DefaultValue = $defaultsString
                        
                        Write-Host "Taxonomy site column '$($row.Name)' default value set to '$($taxField.DefaultValue)'. " -ForegroundColor Gray -NoNewline
                    }
                }
            }
            catch {
                Write-Host "Default value for taxonomy site column '$($row.Name)' could not be set..." -ForegroundColor Red

                Write-Host $error[0] -ForegroundColor Red
            }

            $taxField.Update($true)
            
            Write-Host "Done" -BackgroundColor Green
        }
        else {
            Write-Host "Termset '$($termSet.Name)' was not found in this term store. The site column '$($row.Name)' will not be associated with the term set." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Termset '$($termSet.Name)' was not found in this term store. The site column '$($row.Name)' will not be associated with the term set." -ForegroundColor Red
    }

    $site.Dispose()
}

function AddSiteColumnToWeb([PSCustomObject] $row)
{
    $regExPatternForFieldId = '\{(.*?)\}'
    $fieldId = [string]::Empty

    if(![string]::IsNullOrWhiteSpace($row.ID)) {
        if([regex]::Matches($row.ID, $regExPatternForFieldId) -ne $null) {
            $fieldId = ([regex]::Matches($row.ID, $regExPatternForFieldId).Groups[1].Value).trim()
        }
    }

    Write-Host "`n-----------------------------------------------------------" -ForegroundColor Gray
    $web = Get-SPWeb $row.WebUrl

    if($web -ne $null) {
        Write-Host "Processing field '$($row.DisplayName)' for web $($row.WebUrl)`n" -ForegroundColor Green

        $serverRelUrl = $web.ServerRelativeUrl

        $fieldXML = '<Field '
        if(![string]::IsNullOrWhiteSpace($row.ID)) {
            $fieldXML += 'ID="'+$row.ID.Trim()+'" '
        }
        $fieldXML += 'Type="'+$row.FieldType.Trim()+'" '
        if($row.FieldType -eq "TaxonomyFieldTypeMulti") {
            $fieldXML += 'Mult="TRUE" Sortable="FALSE" '
        }
        $fieldXML += 'Name="'+$row.Name.Trim()+'" '
        $fieldXML += 'StaticName="'+$row.StaticName.Trim()+'" '
        $fieldXML += 'DisplayName="'+$row.DisplayName.Trim()+'" '
        $fieldXML += 'Description="'+$row.Description.Trim()+'" '
        if(![string]::IsNullOrWhiteSpace($row.Group)) {
            $fieldXML += 'Group="'+$row.Group.Trim()+'" '
        }
        else {
            $fieldXML += 'Group="Murphy Columns" '
        }
        $fieldXML += 'EnforceUniqueValues="'+$row.EnforceUniqueValues.Trim()+'" '
        $fieldXML += 'Hidden="'+$row.Hidden.Trim()+'" '
        $fieldXML += 'Required="'+$row.Required.Trim()+'" '
        $fieldXML += 'Sealed="'+$row.Sealed.Trim()+'" '
        $fieldXML += 'ShowInDisplayForm="'+$row.ShowInDisplayForm.Trim()+'" '
        $fieldXML += 'ShowInEditForm="'+$row.ShowInEditForm.Trim()+'" '
        $fieldXML += 'ShowInNewForm="'+$row.ShowInNewForm.Trim()+'" '
        $fieldXML += 'ShowInListSettings="'+$row.ShowInListSettings.Trim()+'" '
        $fieldXML += '>'
        if($row.FieldType -eq "Choice") {
            if(![string]::IsNullOrWhiteSpace($row.Choices)) {
                $choices = $row.Choices -split ";"
                if($choices.Count -gt 0) {
                    # this xml is case sensitive
                    $fieldXML += '<CHOICES>'
                    $choices | %{
                        $fieldXML += '<CHOICE>'+$_.Trim()+'</CHOICE>'
                    }
                    $fieldXML += '</CHOICES>'
                }
            }
        }
        $fieldXML += '<Default>'+$row.Default.Trim()+'</Default>'
        $fieldXML += '</Field>'

        #encode any special characters
        $fieldXML = $fieldXML.Replace("&", "&amp;")

        $create = $false

        [Microsoft.SharePoint.SPField] $field = $null

        # $web.AvailableFields.GetField and $web.AvailableFields.GetFieldByInternalName are case sensitive so
        # fields with internal name of 'MyColumn' and 'mycolumn' are treated as different fields.
        # If you try to create them through the browser UI, then sharepoint treats them as same if 'MyColumn' and 'mycolumn' are display names (title) of the field
        # We need to do a case neutral comparison of incoming field internal name/display name with all available field internal names/display name to find out if a field exists
        foreach($f in $web.AvailableFields)
        {
            if(($f.ID.ToString().ToUpper() -eq $fieldId.ToUpper()) -or ($f.InternalName.ToUpper() -eq $row.Name.Trim().ToUpper()) -or ($f.Title.ToUpper() -eq $row.DisplayName.Trim().ToUpper())) 
            {
                $field = $f
                break
            }
        }
        
        if($field -ne $null) {
            if($serverRelUrl.ToLower() -eq $field.Scope.ToLower()) {
                # field exists and was created at the web level
                Write-Host "Field '$($field.InternalName)' of type '$($field.TypeAsString)' with ID '$($field.Id)' and display name '$($field.Title)' already exists in this web. " -ForegroundColor Gray -NoNewline
                                
                switch($global:duplicateAction)
                { 
                    'd' { DeleteExistingField $web $field | out-Null }
                    'r' { $create = DeleteExistingField $web $field }
                    's' { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White -NoNewline }
                    default { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White -NoNewline }
                }
            }
            else {
                # field exists but was created at a parent level
                Write-Host "Field '$($field.InternalName)' of type '$($field.TypeAsString)' with ID '$($field.Id)' and display name '$($field.Title)' is already available in this web from a parent site at '$($field.Scope)'. Skipping..." -ForegroundColor Cyan
            }
        }
        else {
            Write-Host "Field '$($row.Name)' of type '$($row.FieldType)' with ID '$($row.ID)' and display name '$($row.DisplayName)' does not exist in this web. " -ForegroundColor Gray -NoNewline
            $create = $true
        }

        if($create) {
            Write-Host "Creating..." -ForegroundColor Black -BackgroundColor White -NoNewline

            $web.Fields.AddFieldAsXml($fieldXML) | Out-Null
            $web.Update()

            Write-Host "Done" -BackgroundColor Green

            $newField = $web.Fields.GetFieldByInternalName($row.Name)

            # need extra mapping if it is a taxonomy field
            if($row.FieldType.ToUpper() -like "TAXONOMY*") {
                MapTaxonomyField $web $newField $row
            }   
        }
    }

    $web.Dispose()
}

function ProcessCSV([string] $csvPath)
{
    if(![string]::IsNullOrEmpty($csvPath))
    {
        write-host "`nProcessing csv file $csvPath..." -ForegroundColor Green
        $csv = Import-Csv -Path $csvPath
    }

    if($csv -ne $null)
    {
        $csv | %{
            AddSiteColumnToWeb $_
        }
    }
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$global:defaultTermStoreName = "Managed Metadata Service"

Write-Host "`nSpecify the action to take if a duplicate site column is found at the installation scope. Please note that if you choose the 'd' or 'r' option below, then the site column will be deleted ONLY if it is NOT in use in the site collection. `n" -ForegroundColor White -BackgroundColor Red

$global:duplicateAction = Read-Host "What would you like to do?. Delete and do not recreate [d]/Delete and recreate [r]/Skip [s]? (d|r|s)"

if(![string]::IsNullOrWhiteSpace($siteColumnsCSVPath))
{
    ProcessCSV $siteColumnsCSVPath
}
else 
{
    write-host "`nYou did not specify a csv file containing site column definitions...." -ForegroundColor Cyan

    $csvPathEntryReponse = Read-Host "Would you like to enter the full path of the csv file? [y|n]"
    if($csvPathEntryReponse -eq 'y') {
        do {
            $path = Read-Host "Enter full path to the csv file containing site column definitions."
        }
        until (![string]::IsNullOrWhiteSpace($path))

        ProcessCSV $path
    }
    else {
        Write-Host "`nCreating individual site column..." -ForegroundColor Green
        if([string]::IsNullOrWhiteSpace($webUrl))
        {
            do {
                $webUrl = Read-Host "Specify the full url of the web where the site column will be created"
            }
            until (![string]::IsNullOrWhiteSpace($webUrl))
        }

        if([string]::IsNullOrWhiteSpace($siteColumnName))
        {
            do {
                $siteColumnName = Read-Host "Specify the internal name for the site column"
            }
            until (![string]::IsNullOrWhiteSpace($siteColumnName))
        }

        if([string]::IsNullOrWhiteSpace($siteColumnDisplayName))
        {
            do {
                $siteColumnDisplayName = Read-Host "Specify the display name for the site column"
            }
            until (![string]::IsNullOrWhiteSpace($siteColumnDisplayName))
        }

        if([string]::IsNullOrWhiteSpace($siteColumnFieldType))
        {
            do {
                $siteColumnFieldType = Read-Host "Specify the field type of the site column (Case sensitive - Refer the link for more information https://msdn.microsoft.com/en-us/library/office/aa979575.aspx)"
            }
            until (![string]::IsNullOrWhiteSpace($siteColumnFieldType))
        }

        if([string]::IsNullOrWhiteSpace($termSetName))
        {
            if($siteColumnFieldType.ToUpper().Contains("TAXONOMY")) {
                do {
                    $termSetName = Read-Host "Specify the name of the term set associated with this site column"
                }
                until (![string]::IsNullOrWhiteSpace($termSetName))
            }
        }

        $row = @{WebUrl=$webUrl;Name=$siteColumnName;
                    StaticName=$siteColumnName;DisplayName=$siteColumnDisplayName;
                    FieldType=$siteColumnFieldType;TermSet=$termSetName;
                    Description=[string]::Empty;Group="Murphy Columns";
                    EnforceUniqueValues="FALSE";Required="FALSE";
                    Sealed="FALSE";Hidden="FALSE";
                    ShowInDisplayForm="TRUE";ShowInEditForm="TRUE";
                    ShowInNewForm="TRUE";ShowInListSettings="TRUE";
                    Default=[string]::Empty;Choices=[string]::Empty
                }
    
        AddSiteColumnToWeb $row
    }
}

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow