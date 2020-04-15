<#  
.Description  
    Exports site columns created in a web into a csv file
         
.Parameter - siteColumnCSVFileName 
    File name including extention for the csv file containing site column definitions.
.Parameter - webUrl 
    Url of the web from which to extract site columns.
.Parameter - siteColumnGroup 
    Site column group to export.
.Usage 
    Exports site columns in a single group in a web into a csv file
     
    PS >  Export-SiteColumns.ps1 -webUrl "http://my.site.url" -siteColumnCSVFileName "sitecolumns.csv" -siteColumnGroup "Custom Columns"
#>
[CmdletBinding()]
param(    
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of the web whose site columns will be exported (could be root web url to export site collection)")]
    [string] $webUrl="http://cthub.murphyoilcorp.com",

    [Parameter(Mandatory=$false, Position=1, HelpMessage="Full path to csv file containing site column definitions")]
    [string] $siteColumnCSVFileName,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Site column group to export")]
    [string] $siteColumnGroup="Murphy Columns"
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null

function GetTaxonomyFieldAttributes([Microsoft.SharePoint.SPWeb]$web, [Microsoft.SharePoint.Taxonomy.TaxonomyField] $taxonomyField)
{
    $termStoreName = "Managed Metadata Service"

    Write-Host "'$($taxonomyField.Title)' is a taxonomy field. Connecting to managed metadata service..." -ForegroundColor Gray -NoNewline

    $taxonomySession = New-Object Microsoft.SharePoint.Taxonomy.TaxonomySession $web.Site, $true

    if($taxonomySession -ne $null)
    {
        Write-Host "Done" -BackgroundColor Green
        Write-Host "Fetching term store with Id '$($taxonomyField.SspId)' for the farm. " -ForegroundColor Gray -NoNewline
        $store = $taxonomySession.TermStores[$($taxonomyField.SspId)]
    }
    else
    {
        Write-Host "Failed" -BackgroundColor Red
        Write-Host "Could not connect to managed metadata service for this farm. The associated attributes cannot be found. Exiting...." -ForegroundColor Red
        return
    }

    if($store -eq $null)
    {
        Write-Host "Failed" -BackgroundColor Red
        Write-Host "Term store with Id '$($taxonomyField.SspId)' was not found in this farm. The associated attributes cannot be found. Exiting...." -ForegroundColor Red
        return
    }
    else
    {
        Write-Host "Done" -BackgroundColor Green
    }

    $termSet = $store.GetTermSet($($taxonomyField.TermSetId))

    if($termSet -ne $null) {
        Write-Host "Found termset with name '$($termSet.Name)' and Id '$($taxonomyField.TermSetId)' in this term store. This termset is associated with the field. " -ForegroundColor Gray -NoNewline
        
        $obj = @{}
        $obj.DefaultValueTyped = $taxonomyField.DefaultValueTyped
        $obj.TermSet = $termSet.Name

        Write-Host "Done" -BackgroundColor Green

        return $obj
    }
    else {
        Write-Host "Termset '$($taxonomyField.TermSetId)' was not found in this term store. No term set will be associated with this site column." -ForegroundColor Red
    }
}

#-----------------------------main script--------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$defaultReportDir = "$([IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition))\SiteColumnExports"

if(-not (Test-Path $defaultReportDir -PathType Container)) {
    Write-Host "Creating export folder....$defaultReportDir"
    md -Path $defaultReportDir
}

$global:defaultTermStoreName = "Managed Metadata Service"

try {
    $web = Get-SPWeb $webUrl

    if($web -ne $null) {
        [System.Collections.ArrayList]$data = New-Object System.Collections.ArrayList($null)
        
        [System.Collections.ArrayList]$fieldsCollection = New-Object System.Collections.ArrayList($null)

        #$web = $site.RootWeb

        $webUrl = $web.Url
        $webName = $web.Title

        if([string]::IsNullOrWhiteSpace($siteColumnGroup)) {
            $siteColumnGroup = Read-Host "Please enter the name of the site column group to export (leave blank to export ALL site columns)"
        }

        # only export what was created at that scope
        $groupName = $siteColumnGroup
        if([string]::IsNullOrWhiteSpace($groupName)) {
            $groupName = "ALL"
            $fieldsCollection = $web.Fields
        }
        else {
            $fieldsCollection = $web.Fields | ?{$_.Group.ToUpper() -eq $groupName.Trim().ToUpper()}
        }

        # sort by group then title
        $fieldsCollection = $fieldsCollection | Sort-Object -Property Group, Title

        Write-Host "`nExporting site columns in group '$groupName' for web '$webUrl'...." -ForegroundColor Green

        Write-Host "`nFound '$($fieldsCollection.Count)' site columns..." -BackgroundColor White -ForegroundColor Black

        $fileLocation = $defaultReportDir + "\" + $webName + "_" + $groupName + "_SiteColumns.csv"

        Write-Host "`nExport file $fileLocation `n" -ForegroundColor Cyan

        $fieldsCollection | %{
                    Write-Host "--------------------------------------------------------------------------------"
                    Write-Host "Exporting field '$($_.Title)'" -ForegroundColor Cyan
                    $itemdata = @{}
                    $itemdata.WebUrl = $webUrl + $($_.Scope)
			        $itemdata.ID = "{" + $_.ID + "}"
                    $itemdata.FieldType = $_.TypeAsString
                    $itemdata.Name = $_.InternalName
                    $itemdata.StaticName = $_.StaticName
			        $itemdata.DisplayName = $_.Title
                    $itemdata.Description = $_.Description
                    $itemdata.Group = $_.Group
                    $itemdata.Default = $_.DefaultValue
                    $itemdata.EnforceUniqueValues = $_.EnforceUniqueValues
                    $itemdata.Hidden = $_.Hidden
                    $itemdata.Required = $_.Required
                    $itemdata.Sealed = $_.Sealed
                    $itemdata.ShowInDisplayForm = $(if($_.ShowInDisplayForm -ne $null) {$_.ShowInDisplayForm} else {$true})
                    $itemdata.ShowInEditForm = $(if($_.ShowInEditForm -ne $null) {$_.ShowInEditForm} else {$true})
                    $itemdata.ShowInListSettings = $(if($_.ShowInListSettings -ne $null) {$_.ShowInListSettings} else {$true})
                    $itemdata.ShowInNewForm = $(if($_.ShowInNewForm -ne $null) {$_.ShowInNewForm} else {$true})

                    if($_.TypeAsString -eq "Choice") {
                        [Microsoft.SharePoint.SPFieldChoice] $choiceField = $_ -as [Microsoft.SharePoint.SPFieldChoice]
                        $choicesString = [string]::Empty
                        $trimChars = @(';')
                        $choiceField.Choices | %{ $choicesString = $choicesString + $_ + ";" }
                        if(![string]::IsNullOrWhiteSpace($choicesString)) {
                            $choicesString = $choicesString.Trim($trimChars)
                        }
                        $itemdata.Choices = $choicesString
                    }
                    else {
                        $itemdata.Choices = [string]::Empty
                    }

                    if($_.TypeAsString.ToUpper() -like "TAXONOMY*") {
                        [Microsoft.SharePoint.Taxonomy.TaxonomyField] $taxonomyField = $_ -as [Microsoft.SharePoint.Taxonomy.TaxonomyField]
                        
                        $attrib = GetTaxonomyFieldAttributes $web $taxonomyField
                        $defaultsString = [string]::Empty
                        $trimChars = @(';')
                        $attrib.DefaultValueTyped | %{ $defaultsString = $defaultsString + $($_.Label) + ";" }
                        
                        if(![string]::IsNullOrWhiteSpace($defaultsString)) {
                            $defaultsString = $defaultsString.Trim($trimChars)
                        }

                        $itemdata.Default = $defaultsString
                        $itemdata.TermSet = $attrib.TermSet
                    }
                    else {
                        $itemdata.TermSet = [string]::Empty
                    }

                    $itemdata | ft
                    
                    $data.Add((New-Object PSObject -Property $itemdata)) | out-Null
                }

        Write-Host "Creating CSV file $fileLocation" -ForegroundColor Cyan
        
        $data | Select WebUrl, ID, FieldType, Name, StaticName, DisplayName, Description, Group, EnforceUniqueValues, Hidden, Required, Sealed, ShowInDisplayForm, ShowInEditForm, ShowInNewForm, ShowInListSettings, Default, TermSet, Choices | Export-csv -LiteralPath $fileLocation -NoTypeInformation
        
        $web.Dispose()

        #$site.Dispose()
    }
}
catch {
    Write-Host $error[0] -ForegroundColor Red
}

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow