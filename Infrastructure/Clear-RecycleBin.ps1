<#  
.Description  
    Clears first or second stage recycle bin in batches
         
.Parameter - url  
    Url of the site collection whose recycle bin is to be cleared
.Parameter - rowLimit 
    Number of items to grab per batch
.Parameter - days 
    Items older than these many number of days will be purged
.Parameter - secondStage 
    Should second stage recycle bin be purged
.Parameter - reportDir 
    Report directory path
.Usage 
    Clear first stage recycle bin
     
    PS >  Clear-RecycleBin.ps1 -url "http://sitecollection.company.url"
.Usage 
    Clear second stage recycle bin in batch of 10
     
    PS >  Clear-RecycleBin.ps1 -url "http://sitecollection.company.url" -rowLimit 10 -secondStage
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Site collection url")]
    [string] $url = "http://teams.murphyoilcorp.com",

    [Parameter(Mandatory=$false, Position=1, HelpMessage="How many items to grab per batch")]
    [int] $rowlimit = 5,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Items older than these many days will be purged")]
    [int] $days = 0,

    [Parameter(Mandatory=$false, Position=3, HelpMessage="Which recycle bin to purge. Default = first stage")]
    [switch] $secondStage = $true,

    [Parameter(Mandatory=$false, Position=4, HelpMessage="Report file folder path")]
    [string] $reportDir
)

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null

cls

$defaultReportDir = "$([IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition))\RecyclebinCleanupReports"

if([string]::IsNullOrWhiteSpace($reportDir))
{
    $reportDir = $defaultReportDir
}

[regex]$r="[^a-zA-Z0-9]"
$today = Get-Date -format d
$sanitizedDate = $r.Replace($today,"-")

if(-not (Test-Path $reportDir -PathType Container)) {
    Write-Host "Creating report folder....$reportDir"
    md -Path $reportDir
}

$stage = "FirstStage"
if($secondStage -eq $true) {
    $stage = "SecondStage"
}

$sanitizedUrl = [System.Web.HttpUtility]::UrlEncode($url)

$global:filelocation = $reportDir + "\" + $sanitizedDate + "_" + $sanitizedUrl + "_" + $stage  + ".csv"

$global:totalPurgeCount = 0

function out-CSV ($LogFile, $Append = $false) {
	
	Foreach ($item in $input){
		# Get all the Object Properties
		$Properties = $item.PsObject.get_properties()

        if($Properties -ne $null) {
		    # Create Empty Strings - Start Fresh
		    $Headers = ""
		    $Values = ""
		    # Go over each Property and get it's Name and value
		    $Properties | %{ 
			    $Headers += $_.Name+"`t"
			    $Values += $_.Value.ToString()+"`t"
		    }
		    # Output the Object Values and Headers to the Log file
		    If($Append -and (Test-Path $LogFile)) {
			    $Values | Out-File -Append -FilePath $LogFile -Encoding Unicode
		    }
		    else {
			    # Used to mark it as a Powershell Custom object - you can Import it later and use it
			    # "#TYPE System.Management.Automation.PSCustomObject" | Out-File -FilePath $LogFile
			    $Headers | Out-File -FilePath $LogFile -Encoding Unicode
			    $Values | Out-File -Append -FilePath $LogFile -Encoding Unicode
		    }
        }
	}
}

function ProcessRecycleBin($siteCollection, $reportData) {

    [Microsoft.SharePoint.SPRecycleBinQuery] $recycleQuery = New-Object Microsoft.SharePoint.SPRecycleBinQuery;

    if($secondStage -eq $true) {
        $recycleQuery.ItemState = [Microsoft.SharePoint.SPRecycleBinItemState]::SecondStageRecycleBin
    }
    else {
        $recycleQuery.ItemState = [Microsoft.SharePoint.SPRecycleBinItemState]::FirstStageRecycleBin
    }
    
    $recycleQuery.OrderBy = [Microsoft.SharePoint.SPRecycleBinOrderBy]::DeletedDate
    $recycleQuery.RowLimit = $rowlimit

    [Microsoft.SharePoint.SPRecycleBinItemCollection] $recycledItems = $siteCollection.GetRecycleBinItems($recycleQuery);

    $count = $recycledItems.Count;

    $purgeCount = 0

    Write-Host "Items grabbed in this batch : $count"

    if ($count -gt 0) {
        for($i = 0; $i -lt $count; $i++){
            [Microsoft.SharePoint.SPRecycleBinItem] $recycledItem = $recycledItems[$i] 
            $age = ((Get-Date) - $recycledItem.DeletedDate).Days;

			$itemdata = @{};
            $itemdata.ItemName = $recycledItem.Title
            $itemdata.WebUrl = $recycledItem.web.URL
			$itemdata.DeletedDate = $recycledItem.DeletedDate
            $itemdata.DeletedBy = $recycledItem.DeletedByName
            $itemdata.CreatedBy = $recycledItem.AuthorName
            $itemdata.OriginalLocation = $recycledItem.DirName
			$itemdata.FileSize_Bytes = $recycledItem.Size

            if($age -ge $days){
                $g = New-Object System.Guid($recycledItem.ID)
				Write-Host "Item: $($recycledItem.Title) Size: $($recycledItem.Size) delete started on $(Get-Date)"
				$recycledItems.Delete($g)
				Write-Host "$($recycledItem.Title) delete completed on $(Get-Date)"
                $itemdata.Purged = "Yes"
                $purgeCount += 1
                $global:totalPurgeCount += 1
                Write-Host "Item : $($recycledItem.Title) was deleted $age days ago.....Purged"
            }
            else {
                $itemdata.Purged = "No"
                Write-Host "Item : $($recycledItem.Title) was deleted $age days ago.....Not Purged"
            }

            $reportData.Add((New-Object PSObject -Property $itemdata));
        }

        if($purgeCount -gt 0) {
            ProcessRecycleBin $siteCollection $reportData
        }
    }
}

Write-Host "-----Starting recycle bin cleanup--------------$(Get-Date)"

Write-Host "Items in recycle bin deleted more than $days days ago will be purged"

$siteCollection = New-Object Microsoft.SharePoint.SPSite($url);

if($siteCollection -ne $null) {
    
    [System.Collections.ArrayList]$reportData = New-Object System.Collections.ArrayList($null)

    ProcessRecycleBin $siteCollection $reportData
    
    $reportData | out-CSV -LogFile $filelocation -Append $true -Input $_

    $siteCollection.Dispose()
}
else {
    Write-Host "-------No site collection at url $url------------------"
}

Write-Host "-----Completed recycle bin cleanup--------------$(Get-Date)"
Write-Host "Total items purged: $global:totalPurgeCount"
Write-Host "Report available at: $global:filelocation"