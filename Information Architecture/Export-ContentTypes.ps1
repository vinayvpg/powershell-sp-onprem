<#  
.Description  
    Exports content types created in a web into a csv file
         
.Parameter - ctypeCSVFileName 
    File name including extention for the csv file containing content type definitions.
.Parameter - webUrl 
    Url of the web from which to extract content types.
.Parameter - ctypeGroup 
    Content type group to export.
.Usage 
    Exports content types in a single group of a web into a csv file
     
    PS >  Export-ContentTypes.ps1 -webUrl "http://my.site.url" -ctypeCSVFileName "ctypes.csv" -ctypeGroup "Custom Content Types"
#>
[CmdletBinding()]
param(    
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of the web whose content types will be exported (could be root web url to export site collection)")]
    [string] $webUrl="http://cthub.murphyoilcorp.com",
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Full path to csv file containing content type definitions")]
    [string] $ctypeCSVFileName,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Content type group to export")]
    [string] $ctypeGroup
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null

#-----------------------------main script--------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$defaultReportDir = "$([IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition))\CTypeExports"

if(-not (Test-Path $defaultReportDir -PathType Container)) {
    Write-Host "Creating export folder....$defaultReportDir"
    md -Path $defaultReportDir
}

$global:defaultTermStoreName = "Managed Metadata Service"

# guid pattern - 32 char digits or letters format 8,4,4,4,12 hyphenated or not beginning and ending with curly brackets or not
$regExPatternForGuid = '^[{]?[0-9a-zA-Z]{8}[-]?([0-9a-zA-Z]{4}[-]?){3}[0-9a-zA-Z]{12}[}]?$'

try {
    $web = Get-SPWeb $webUrl

    if($web -ne $null) {
        [System.Collections.ArrayList]$data = New-Object System.Collections.ArrayList($null)

        [System.Collections.ArrayList]$ctypeCollection = New-Object System.Collections.ArrayList($null)

        #$web = $site.RootWeb
        $webUrl = $web.Url
        $webName = $web.Title

        if([string]::IsNullOrWhiteSpace($ctypeGroup)) {
            $ctypeGroup = Read-Host "Please enter the name of the content type group to export (leave blank to export ALL content types)"
        }

        # only export what was created at that scope
        $groupName = $ctypeGroup
        if([string]::IsNullOrWhiteSpace($groupName)) {
            $groupName = "ALL"
            $ctypeCollection = $web.ContentTypes
        }
        else {
            $ctypeCollection = $web.ContentTypes | ?{$_.Group.ToUpper() -eq $groupName.Trim().ToUpper()}
        }
        
        # sort ctypes by ctype id so parent ctypes are at top of export file
        $ctypeCollection = $ctypeCollection | Sort-Object -Property Id

        Write-Host "`nExporting content types in group '$groupName' for web '$webUrl'...." -ForegroundColor Green

        Write-Host "`nFound '$($ctypeCollection.Count)' content types..." -BackgroundColor White -ForegroundColor Black

        $fileLocation = $defaultReportDir + "\" + $webName + "_" + $groupName + "_ContentTypes.csv"

        Write-Host "`nExport file $fileLocation" -ForegroundColor Cyan

        $ctypeCollection | %{
                    Write-Host "----------------------------------------------------------------------------------"
                    Write-Host "Exporting content type '$($_.Name)'" -ForegroundColor Cyan
                    $itemdata = @{}
                    $itemdata.WebUrl = $webUrl + $($_.Scope)
                    $itemdata.ContentTypeName = $_.Name
                    $itemdata.ContentTypeParent = $_.Parent.Name
                    $itemdata.Description = $_.Description
                    $itemdata.Group = $_.Group
                    
                    $parentFieldsString = [string]::Empty
                    $includedFieldsString = [string]::Empty
                    $includedFieldsTitle = [string]::Empty

                    $trimChars = @(';')
                    $_.Parent.FieldLinks | % { $parentFieldsString = $parentFieldsString + $_.Name + ";" }
                    $_.FieldLinks | % { $includedFieldsString = $includedFieldsString + $_.Name + ";" }
                    
                    Write-Host "`nExisting fields in content type : $includedFieldsString. " -ForegroundColor Gray

                    if(![string]::IsNullOrWhiteSpace($includedFieldsString))  {
                        Write-Host "`nExcluding fields coming from parent content type '$($_.Parent.Name)': $parentFieldsString. " -ForegroundColor Gray -NoNewline
                        # convert to system.collection in order to support add/remove  
                        $includedFieldColl = {$includedFieldsString.Trim($trimChars) -split ";"}.Invoke() 
                        if(![string]::IsNullOrWhiteSpace($parentFieldsString)) {
                            $parentFieldArray = $parentFieldsString.Trim($trimChars) -split ";"
                            $parentFieldArray | % { $includedFieldColl.Remove($_) | Out-Null }
                        }
                        Write-Host "Done" -BackgroundColor Green

                        # Additional fields added to a ctype when a managed metadata field is added include 'TaxCatchAll', 'TaxCatchAllLabel' and 1 note field per managed metdata column whose internal name is a guid. Need to exclude these fields
                        $excludedFieldColl = $includedFieldColl | ?{ ($_.ToUpper() -like 'TAXCATCHALL*') -or ([regex]::Matches($_.ToUpper(), $regExPatternForGuid) -ne $null) }

                        Write-Host "`nExcluding '$($excludedFieldColl.Count)' fields related to managed metadata columns (these fields are generated by SharePoint during content type provisioning): $excludedFieldColl. " -ForegroundColor Gray -NoNewline

                        $excludedFieldColl | %{ $includedFieldColl.Remove($_) | Out-Null }

                        Write-Host "Done" -BackgroundColor Green

                        $includedFieldColl | % {
                                $fieldLinkName = $_
                                
                                # find display names of fields. For some reason, the display names on field links show internal name of field
                                [Microsoft.SharePoint.SPField] $field = $null
                                
                                $f = $web.AvailableFields | ?{ $_.InternalName.ToString().ToUpper() -eq $fieldLinkName.ToUpper() }
                
                                if ($f -ne $null) {
                                    if($f.GetType().BaseType.Name -eq 'Array'){
                                        $field = $f[0]
                                        Write-Host "While searching for the field, multiple site columns with the same internal name '$fieldLinkName' were found. Selecting '$($field.InternalName)' of type '$($field.TypeAsString)' with ID '$($field.Id)' in group '$($field.Group)' as the one to export..." -ForegroundColor Gray -NoNewline
                                    }
                                    else {
                                        $field = $f
                                    }
                                }

                                if($field -ne $null) {
                                    $includedFieldsTitle = $includedFieldsTitle + $field.Title + ";"
                                }
                            }

                        $includedFieldsTitle = $includedFieldsTitle.Trim($trimChars)
                    }

                    $itemdata.IncludedSiteColumns = $includedFieldsTitle

                    $itemdata | ft
                    
                    $data.Add((New-Object PSObject -Property $itemdata)) | out-Null
                }

        Write-Host "Creating CSV file $fileLocation" -ForegroundColor Cyan
        
        $data | Select WebUrl, ContentTypeName, ContentTypeParent, Description, Group, IncludedSiteColumns | Export-csv -LiteralPath $fileLocation -NoTypeInformation
        
        $web.Dispose()

        #$site.Dispose()
    }
}
catch {
    Write-Host $error[0] -ForegroundColor Red
}

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow