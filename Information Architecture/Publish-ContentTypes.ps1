<#  
.Description  
    Publishes content types in content type hub by group or individually
         
.Parameter - cthubUrl 
    Url of the content type hub site collection. Mandatory.
.Parameter - ctypeName 
    Name of the content type to be published.
.Parameter - ctypeGroup 
    Name of the content type group from which to publish.
.Usage 
    Publish ALL content types in a group
     
    PS >  Publish-ContentTypes.ps1 -cthubUrl "http://cthuburl" -ctypeGroup "My Custom Group"
.Usage 
    Publish a single content type
     
    PS >  Publish-ContentTypes.ps1 -cthubUrl "http://cthuburl" -ctypeName "My Document Content Type"
#>
[CmdletBinding()]
param(    
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Url of the content type hub")]
    [string] $cthubUrl,

    [Parameter(Mandatory=$false, Position=1, HelpMessage="Name of the group that contains the content type(s) to publish")]
    [string] $ctypeGroup,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Name of the content type to publish")]
    [string] $ctypeName,

    [Parameter(Mandatory=$false, Position=3, HelpMessage="Unpublish existing content type? This will create an unsealed copy of the content type in subscribing site collections")]
    [switch] $unpublish
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

$global:unpublish = $unpublish

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null

function Publish-PerformAction
{
    param
    (
        [parameter(mandatory=$true)][Microsoft.SharePoint.Taxonomy.ContentTypeSync.ContentTypePublisher]$ctPublisher,
        [parameter(mandatory=$true)][Microsoft.SharePoint.SPContentType]$ct
    )

    if($ctPublisher -ne $null) {
        if($global:unpublish) {
            Write-Host "Unpublishing content type '$($ct.Name)'. " -ForegroundColor Cyan -NoNewline
            Write-Host "This will create an unsealed copy of this content type in each subscribing site collection..." -BackgroundColor DarkGray -NoNewline
            $ctPublisher.Unpublish($ct)
        }
        else {
            Write-Host "Publishing content type '$($ct.Name)'..." -ForegroundColor Cyan -NoNewline
            $ctPublisher.Publish($ct)
        }

        Write-Host "Done" -BackgroundColor Green
    }
}

function Publish-CTFromHub 
{
    param
    (
        [parameter(mandatory=$true)][string]$CTHUrl,
        [parameter(mandatory=$false)][string]$Group,
        [parameter(mandatory=$false)][string]$ctName
    )

    $success = $false

    Write-Host "Connecting to content type hub $CTHUrl..." -ForegroundColor Gray

    try {
        $site = Get-SPSite $CTHUrl

        if($site -ne $null)
        {   
            $contentTypePublisher = New-Object Microsoft.SharePoint.Taxonomy.ContentTypeSync.ContentTypePublisher($site)
            if($contentTypePublisher -ne $null) {
                $count = 0
                $allCTypes = $site.RootWeb.ContentTypes
                if(![string]::IsNullOrWhiteSpace($Group)) {
                    if(![string]::IsNullOrWhiteSpace($ctName)) {
                        $allCTypes | ? {($_.Group -match $Group) -and ($_.Name.ToUpper() -eq $ctName.ToUpper().Trim())} | % { $count++; Publish-PerformAction $contentTypePublisher $_ }
                    }
                    else {
                        $allCTypes | ? {($_.Group -match $Group)} | % { $count++; Publish-PerformAction $contentTypePublisher $_ }
                    }
                }
                else {
                    $allCTypes | ? {($_.Name.ToUpper() -eq $ctName.ToUpper().Trim())} | % { $count++; Publish-PerformAction $contentTypePublisher $_ }
                }
            }
            else {
                Write-Host "Content type hub was not found at $CTHUrl. Exiting..." -ForegroundColor Red
            }
        }

        if($count -gt 0) {
            $success = $true
        }
        else {
            Write-Host "No content types were found. Nothing to publish..." -ForegroundColor Red
        }
    }
    catch {
        Write-Host $error[0] -ForegroundColor Red
    }

    return $success
}

function StartContentTypeHubTimerJob
{     
    $job = Get-SPTimerJob | ?{$_.Name -match "MetadataHubTimerJob"}
    
    if($job -ne $null)
    {
        $started = $job.LastRunTime
        Write-Host -ForegroundColor Gray -NoNewLine "Running '$($job.DisplayName)' Timer Job."
        Start-SPTimerJob $job
        while (($started) -eq $job.LastRunTime)
        {
            Write-Host -NoNewLine -ForegroundColor Gray "."
            Start-Sleep -Seconds 2
        }
        $lastrun = $job.historyentries | select-object -first 1

        if($lastrun.status -eq "Succeeded")
        {
            Write-Host -BackgroundColor Green "Done"
        }

        else 
        {
            Write-Host -BackgroundColor Red "Failed"
            Write-Host $error[0] -ForegroundColor Red
            exit
        }

    }
}

function StartContentTypeSubcriberTimerJob([Microsoft.SharePoint.Administration.SPWebApplication]$wa) 
{
    Write-Host "Starting content type subscriber timer job for web application '$($wa.Name)' @ $($wa.Url). " -ForegroundColor Cyan

    $job = Get-SPTimerJob -WebApplication $wa | ?{ $_.Name -like "MetadataSubscriberTimerJob"}
     
    if($job -ne $null  )
    {
        $started = $job.LastRunTime
        Write-Host -ForegroundColor Gray -NoNewLine "Running '$($job.DisplayName)' Timer Job."
        Start-SPTimerJob $job
        while (($started) -eq $job.LastRunTime)
        {
            Write-Host -NoNewLine -ForegroundColor Gray "."
            Start-Sleep -Seconds 2
        }
        $lastrun = $job.historyentries | select-object -first 1

        if($lastrun.status -eq "Succeeded")
        {
            Write-Host -BackgroundColor Green "Done"
        }

        else 
        {
            Write-Host -BackgroundColor Red "Failed"
            Write-Host $error[0] -ForegroundColor Red
        }

    }
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)" -ForegroundColor Yellow

if([string]::IsNullOrWhiteSpace($ctypeName) -and [string]::IsNullOrWhiteSpace($ctypeGroup))
{
    Write-Host "`nNeither a content type group nor a content type name has been specified. You must specify at least one of these parameters..." -ForegroundColor Cyan
    do {
        $ctypeGroup = Read-Host "Specify the content type group to publish"
        $ctypeName = Read-Host "Specify the name of the content type to publish"
    }
    until ((![string]::IsNullOrWhiteSpace($ctypeName)) -or (![string]::IsNullOrWhiteSpace($ctypeGroup)))
}

if([string]::IsNullOrWhiteSpace($ctypeGroup)) {
    Write-Host "`nAll content types named '$ctypeName' will be published..." -ForegroundColor Cyan
}
else {
    if([string]::IsNullOrWhiteSpace($ctypeName)) {
        Write-Host "`nAll content types in the group '$ctypeGroup' will be published..." -ForegroundColor Cyan
    }
    else {
        Write-Host "`nContent type named '$ctypeName' in group '$ctypeGroup' will be published..." -ForegroundColor Cyan
    }
}

if(Publish-CTFromHub $cthubUrl $ctypeGroup $ctypeName) {
    sleep(10)

    StartContentTypeHubTimerJob

    Get-SPWebApplication | %{
        StartContentTypeSubcriberTimerJob $_
    }
}
write-host "Done - $(Get-Date)" -ForegroundColor Yellow