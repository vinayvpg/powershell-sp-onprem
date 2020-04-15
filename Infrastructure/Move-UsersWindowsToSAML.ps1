[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Root scope (site collection/web/web application) url whose users should be migrated")]
    [string] $webUrl,

    [Parameter(Mandatory=$false, Position=1, HelpMessage="Full path to csv report file")]
    [string] $reportCSVPath,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="New login name prefix when SPUser is an AD group")]
    [string] $newGroupPrefix="c:0-.t|adfs provider|",

    [Parameter(Mandatory=$false, Position=3, HelpMessage="New login name prefix when SPUser is an AD user")]
    [string] $newUserPrefix="i:0e.t|adfs provider|",

    [Parameter(Mandatory=$false, Position=4, HelpMessage="New login name suffix when SPUser is an AD group, e.g. when login name is based on UPN")]
    [string] $newUserSuffix="@rsrcorp.com",

    [Parameter(Mandatory=$false, Position=5, HelpMessage="Domain suffix in windows claim identity")]
    [string] $domainPrefix="CORP",

    [Parameter(Mandatory=$false, Position=6, HelpMessage="Call Move-SPUser internally?")]
    [switch] $move=$false
)

$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

if([string]::IsNullOrWhiteSpace($reportCSVPath))
{
    $currentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $reportCSVPath = $currentDir + "\" + "move-user-report.csv"
    Write-Host "You did not specify a path to the report csv file. The report will be created at '$reportCSVPath'" -ForegroundColor Cyan
}

Write-Host "Processing site '$webUrl'..." -ForegroundColor Cyan

$site = Get-SPSite $webUrl
$parentWebApp = $null
$portalSuperUserAccount = [string]::Empty
$portalSuperReaderAccount = [string]::Empty

if($site -ne $null) {
    Write-Host "Getting 'Portal Super User' and 'Portal Super Reader' properties for parent web application...." -ForegroundColor Cyan
    $parentWebApp = $site.WebApplication     # get parent web application

    if($parentWebApp -ne $null) {
        $portalSuperUserAccount = $parentWebApp.Properties["portalsuperuseraccount"]
        if (![string]::IsNullOrWhiteSpace($portalSuperUserAccount)) {
            Write-Host "Portal Super User Account:'$portalSuperUserAccount'..." -ForegroundColor Cyan
        }
        $portalSuperReaderAccount = $parentWebApp.Properties["portalsuperreaderaccount"]
        if (![string]::IsNullOrWhiteSpace($portalSuperReaderAccount)) {
            Write-Host "Portal Super Reader Account:'$portalSuperReaderAccount'..." -ForegroundColor Cyan
        }
    }
}

#Write CSV- TAB Separated File Header
"UserType `t DisplayName `t CurrentLogin `t NewLogin `t Converted?" | out-file $reportCSVPath

# Get all of the users at the root scope of specified url
$users = Get-SPUser -web $webUrl -Limit All

# Loop through each of the users in the web app
foreach($user in $users)
{
    $userType = "ADUser"
    $moved = "No"

    # Create an array that will be used to split the user name
    $a=@()

    $userlogin = $user.UserLogin
    $userDisplayName = $user.DisplayName
    Write-Host "-----------------------------------------------------------------------------------------------"
    Write-Host "Processing User:'$userDisplayName' " -NoNewline

    $username = [string]::Empty
    if($userlogin.Contains("i:0#.w")) # for users
    {   
        if($userlogin.ToUpper().Contains($domainPrefix + "\")) {
            $a = $userlogin.split('\')
            $username = $newUserPrefix + $a[1] + $newUserSuffix
        }
    }
    elseif($userlogin.Contains("c:0+.w")) # for AD groups
    {
        $a = $userlogin.split('|')
        $username = $newGroupPrefix + $a[1]
        $userType = "ADGroup"
    }
    elseif($userlogin.Contains("c:0!.s|windows")) # for well known 'Authenticated Users or Everyone' group
    {
        $username = "c:0(.s|true"
        $userType = "WellKnownGroup"
    }

    if (($username -Like ("*" + [Environment]::UserName + "*")) -or ($userlogin.ToUpper() -eq $portalSuperUserAccount) -or ($userlogin.ToUpper() -eq $portalSuperReaderAccount))
    {
        Write-Host "Skipping user '$user' so as to not lose web application policy level rights..." -BackgroundColor Green -NoNewline
        Write-Host "Skipping..." -BackgroundColor DarkMagenta -NoNewline
    }
    else
    {
        Write-Host "CurrentLogin:'$user' NewLogin:'$username'..." -NoNewline

        if (![string]::IsNullOrWhiteSpace($username)) {
            if($move) {
                Write-Host "moving user..." -BackgroundColor DarkYellow -NoNewline
                try {
                    Move-SPUser –Identity $user –NewAlias $username -ignoresid -Confirm:$false
                    $moved = "Yes"
                }
                catch {
                    Write-Host $Error[0].Exception.ToString() -ForegroundColor Red -NoNewline
                    $moved = "No"
                }
                Write-Host "ensuring new user in web..." -BackgroundColor DarkYellow -NoNewline
                try {
                    $newUser = Get-SPUser -Identity $username -Web $webUrl
                    Write-Host "Done..." -BackgroundColor Green -NoNewline
                }
                catch {
                    Write-Host $Error[0].Exception.ToString() -ForegroundColor Red -NoNewline
                    Write-Host "Failed..." -BackgroundColor Red -NoNewline
                }
            }
            else {
                $moved = "No"
            }
        }
        else {
            Write-Host "Skipping..." -BackgroundColor DarkMagenta -NoNewline
        }
    }

    "$userType `t $userDisplayName `t $userLogin `t $username `t $moved" | out-file $reportCSVPath -Append

    if($moved -eq 'Yes') {
        Write-Host "Moved? $moved" -BackgroundColor Green
    }
    else {
        Write-Host "Moved? $moved" -BackgroundColor Red
    }
}

$site.Dispose()

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow