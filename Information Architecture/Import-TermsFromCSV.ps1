<#  
.Description  
    Import term sets from a csv file into term store
         
.Parameter - siteUrl 
    Url of site associated with term store
.Parameter - inputDir 
    Directory to input csvs from
.Usage 
    Imports csv files from a directory
     
    PS >  Import-TermsFromCSV.ps1 -siteUrl "http://my.site.url" -inputDir "c:\temp\termsets"
#>
[CmdletBinding()]
param(    
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of a site collection in the farm associated with the target managed metadata service")]
    [string] $siteUrl="http://spvm2-2013-app:2013",
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Directory to lookup termset csv. If individual csv file is specified then this attribute is ignored and vice versa.")]
    [string] $inputDir="C:\Build\Scripts\Information Architecture\TermSets",

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Termset csv to import. If directory is specified then this attribute is ignored and vice versa.")]
    [string] $termsetCSVPath
    
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

function DeleteExistingTermset($group, $termset) {
    if(($group -ne $null) -and ($termset -ne $null)) {
        try {
            Write-Host "Deleting termset '$($termset.Name)' from group '$($group.Name)'..." -ForegroundColor Black -BackgroundColor White -NoNewline

            $termset.Delete()
            $global:store.CommitAll()

            Write-Host "Done" -BackgroundColor Green

            return $true
        }
        catch {
            Write-Host "Termset '$($termset.Name)' was NOT deleted..." -BackgroundColor Red

            Write-Host $error[0] -ForegroundColor Red

            return $false
        }
    }
}

function ImportTermSet([string] $termsetname, [string]$filepath, $group, [bool]$usedForNavigation)
{
    ##CSV file 
    $file = get-item $filepath
    $filename = $file.FullName

    $reader = new-object System.IO.StreamReader($filename)
    
    $alltermsadded = $false
    $errormessage = ""
    
    write-host "Importing termset file '$filename'..." -NoNewline
    $global:manager.ImportTermSet($group, $reader, [ref] $alltermsadded, [ref] $errormessage)
    Write-Host "Done" -BackgroundColor Green
        
    $reader.Dispose()
 
	$termset = $group.TermSets[$termsetname]
    ##Checking if Site Navigation is enabled for the Term store
    ##One can add more custiom properties below depending upon the need
	if ($usedForNavigation -eq $true)
	{
		$termset.SetCustomProperty("_Sys_Nav_IsNavigationTermSet", "True")
		#$termset.SetCustomProperty("_Sys_Nav_AttachedWeb_SiteId", $site.ID.ToString())
		#$termset.SetCustomProperty("_Sys_Nav_AttachedWeb_WebId", $site.RootWeb.ID.ToString())    
		#termset.SetCustomProperty("_Sys_Nav_AttachedWeb_OriginalUrl", $site.RootWeb.Url)
	}

    if ([string]::IsNullOrEmpty($errormessage) -eq $false)
    {
        write-host $errormessage
    }

    $termsetId = $termset.Id

	$global:store.CommitAll()

    return $termsetId
}

function ProcessCSV([string] $csvPath)
{
    if(![string]::IsNullOrEmpty($csvPath))
    {
        write-host "`nProcessing csv file $csvPath..." -ForegroundColor Green
        $file = Get-Item $csvPath
        
        if ($file -ne $null) {
            $groupName = $file.BaseName.Split("_")[0]
            $termsetName = $file.BaseName.Split("_")[1]

            $useforNav = $false

            if($groupName -eq "Navigation") { $useforNav = $true }

            #### Checking the Group name, if not present and getting the Site collection group
            if($groupName -eq ""){
                Write-Host "`nNo group name provided. Termset will be created under site collection group. " -NoNewline
                $group = $global:store.GetSiteCollectionGroup($global:site)
                Write-Host "Looking for group '$($group.Name)'..." -NoNewline
            }
            else{
                Write-Host "`nLooking for group '$groupName' in selected term store...." -NoNewline
                $group = $global:store.Groups[$groupName]
            }

            if ($group -eq $null)
            {
                write-host "Group not found. Creating..." -NoNewline
                $group = $global:store.CreateGroup($groupName)
                if($group -eq $null) {
                    Write-Host "Failed" -BackgroundColor Red
                    return
                }
        
                $group = $global:store.Groups[$groupName]
            }

            Write-Host "Done" -BackgroundColor Green

            ##Getting the Termset
            $termset = $group.TermSets[$termsetname]
            [string]$termsetId = $null
            $create = $false

            if ($termset -ne $null) {
                $termsetId = $termset.Id
                Write-Host "Termset '$termsetname' with id '$termsetId' already exists. " -ForegroundColor Gray -NoNewline
        
                switch($global:duplicateAction)
                { 
                    'd' { DeleteExistingTermset $group $termset | out-Null }
                    'r' { $create = DeleteExistingTermset $group $termset }
                    's' { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White -NoNewline }
                    default { Write-Host "Skipping..." -ForegroundColor Black -BackgroundColor White -NoNewline }
                }
            }
            else {
                $create = $true
                write-host "Termset not found in this group. Creating..." -NoNewline
            }

            if ($create -eq $true) {
                $termsetId = ImportTermSet -group $group -termsetname $termsetName -filepath $csvPath -usedForNavigation $useforNav
                Write-Host "Termset: $termsetName Termset Id: $termsetId"
            }

        }
        else {
            Write-Host "Termset file not found" -ForegroundColor Red
        }
    }
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$global:defaultTermStoreName = "Managed Metadata Service"

Write-Host "`nConnecting to site '$siteUrl'...." -NoNewline
$global:site = Get-SPSite $siteUrl
Write-Host "Done" -BackgroundColor Green

Write-Host "`nConnecting to managed metadata service associated with site...." -NoNewline
$global:session = Get-SPTaxonomySession -Site $global:site.Url
Write-Host "Done" -BackgroundColor Green
    
Write-Host "`nGetting default term store associated with site. " -NoNewline	
$global:store = $global:session.DefaultKeywordsTermStore
Write-Host "Term store: $($global:store.Name)..." -NoNewline 
Write-Host "Done" -BackgroundColor Green

Write-Host "`nGetting the import manager for the term store..." -NoNewline	
$global:manager = $global:store.GetImportmanager()
Write-Host "Done" -BackgroundColor Green

Write-Host "`nSpecify the action to take if a duplicate termset is found at the installation scope.`n" -ForegroundColor White -BackgroundColor Red

$global:duplicateAction = Read-Host "What would you like to do? Delete and do not recreate [d]/Delete and recreate [r]/Skip [s]? (d|r|s)"

if(![string]::IsNullOrWhiteSpace($termsetCSVPath))
{
    ProcessCSV $termsetCSVPath
}
else 
{
    write-host "`nYou did not specify a csv file containing term set definitions...." -ForegroundColor Cyan

    $csvPathEntryReponse = Read-Host "Would you like to enter the full path of the csv file? [y|n]"
    if($csvPathEntryReponse -eq 'y') {
        do {
            $path = Read-Host "Enter full path to the csv file containing term set definitions."
        }
        until (![string]::IsNullOrWhiteSpace($path))

        ProcessCSV $path
    }
    else {

        if(![string]::IsNullOrWhiteSpace($inputDir))
        {
            Get-ChildItem $inputDir -Filter *.csv | % { ProcessCSV $_.FullName }
        }
    }
}

$global:site.Dispose()

Write-Host "`nDone - $(Get-Date)" -ForegroundColor Yellow