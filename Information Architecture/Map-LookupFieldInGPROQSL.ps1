[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of the target web")]
    [string] $webUrl = "http://teams.murphyoilcorp.com/gpro/purchasing",

    [Parameter(Mandatory=$false, Position=1, HelpMessage="Source list for lookup")]
    [string] $sourceListName = "ISN",

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Child list where lookup value needs to be set")]
    [string] $childListName = "QSL/Procurement Plan Database",

    [Parameter(Mandatory=$false, Position=3, HelpMessage="Source list field *internal* name")]
    [string] $sourceFieldInternalName="Title",

    [Parameter(Mandatory=$false, Position=4, HelpMessage="Source list field type for CAML query")]
    [string] $sourceFieldType="Text",

    [Parameter(Mandatory=$false, Position=5, HelpMessage="Source list additional CAML query filter")]
    [string] $sourceAdditionalCAMLQueryFilter="<IsNotNull><FieldRef Name='VendorName' /></IsNotNull>",

    [Parameter(Mandatory=$false, Position=6, HelpMessage="Child list field name to set")]
    [string] $childTargetFieldName="ISN",

    [Parameter(Mandatory=$false, Position=7, HelpMessage="Child list field name that contains the lookup value to search in parent list")]
    [string] $childLookupValueFieldName="ISNCompanyID"
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

function OutputMessage($msg)
{
    if($global:logPath) {
        $msg | Out-File $global:logPath -Append
    }
}

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null

$timestamp = Get-Date -Format s | % { $_ -replace ":", "-" }
$currentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$global:logPath = $currentDir + "\MapLookupInQSLLog\MapQSL-To-ISN-Log-" + $timestamp + ".txt"

Write-Host "The log file will be created at '$global:logPath'" -ForegroundColor Cyan

$msg = [string]::Empty

$msg = "Script started ---> $(Get-Date)`n"
Write-Host $msg -ForegroundColor Yellow
OutputMessage $msg 

$web = Get-SPWeb $webUrl

if($web -ne $null) {
    $parentList = $web.Lists.TryGetList($sourceListName)
    $childList = $web.Lists.TryGetList($childListName)
 
    if($parentList -ne $null -and $childList -ne $null) {
        $msg = "Processing list '$childListName' linking to lookup list '$sourceListName' in '$webUrl'..."
        Write-Host $msg
        OutputMessage $msg

        for($i=0; $i -lt $childList.ItemCount; $i++) {
            $childItem = $childList.Items[$i];

            [Microsoft.SharePoint.SPFieldCalculated] $parentListLookupValueObject = $childItem.Fields[$childLookupValueFieldName] -as [Microsoft.SharePoint.SPFieldCalculated]; #important to use .Fields

            $parentListLookupValue = $parentListLookupValueObject.GetFieldValueAsText($childItem[$childLookupValueFieldName]);

            $msg = "---> Processing '$childListName' item id '$($childItem.ID)' with '$childLookupValueFieldName = $parentListLookupValue'.... "
            Write-Host $msg -NoNewline
            OutputMessage $msg

            if(![string]::IsNullOrWhiteSpace($parentListLookupValue)) {
                #Get Lookup Item from Parent List
          
                $parentListQuery = New-Object Microsoft.SharePoint.SPQuery
                if([string]::IsNullOrWhiteSpace($sourceAdditionalCAMLQueryFilter)) { 
                    $parentListQuery.Query =  
                        "<Where> 
                            <Eq> 
                                <FieldRef Name='$sourceFieldInternalName' /> 
                                <Value Type='$sourceFieldType'>$parentListLookupValue</Value> 
                            </Eq> 
                        </Where>"
                }
                else {
                    $parentListQuery.Query =  
                        "<Where>
                            <And>
                                <Eq> 
                                    <FieldRef Name='$sourceFieldInternalName' /> 
                                    <Value Type='$sourceFieldType'>$parentListLookupValue</Value> 
                                </Eq>
                                $sourceAdditionalCAMLQueryFilter
                            </And> 
                        </Where>"
                }

                $parentListQuery.ViewFields = "<FieldRef Name='Id' /><FieldRef Name='$sourceFieldInternalName' />" 
                $parentListQuery.ViewFieldsOnly = $true 
                $parentListLookupItem = $parentList.GetItems($parentListQuery)[0];  #only get first item if multiple items found

                if($parentListLookupItem -ne $null) {
                    $msg = "Found '$sourceListName' item '$sourceFieldInternalName = $parentListLookupValue and ID = $($parentListLookupItem.ID)'..."
                    Write-Host $msg -NoNewline
                    OutputMessage $msg

                    $msg = "Setting lookup in child list to value "
                    Write-Host $msg -NoNewline
                    OutputMessage $msg

                    $lookupValueToSet = New-Object Microsoft.SharePoint.SPFieldLookupValue($parentListLookupItem.ID, $parentListLookupValue);

                    $childItem[$childTargetFieldName] = $lookupValueToSet; #$parentListLookupItem.ID

                    $msg = "$lookupValueToSet..."
                    Write-Host $msg -NoNewline
                    OutputMessage $msg
                    
                    $childItem.SystemUpdate();   # systemupdate avoids changes to modified date and modified by
                    
                    $msg = "Done!"
                    write-host $msg -BackgroundColor Green -ForegroundColor White
                    OutputMessage $msg
                }
                else {
                    $msg = "Item NOT found in '$sourceListName' list. '$childListName' item could not be linked to '$sourceListName' list."
                    Write-Host $msg -BackgroundColor Red -ForegroundColor White
                    OutputMessage $msg
                }
            }
            else {
                $msg = "Empty lookup value. '$childListName' item could not be linked to '$sourceListName' list."
                Write-Host $msg -BackgroundColor DarkMagenta -ForegroundColor White
                OutputMessage $msg
            }
        }
    }
}

$web.Dispose()

$msg = "`nScript Ended ---> $(Get-Date)"
Write-Host $msg -ForegroundColor Yellow
OutputMessage $msg 