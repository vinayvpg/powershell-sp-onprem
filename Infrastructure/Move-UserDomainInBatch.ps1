[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Full path to csv containing information about user accounts")]
    [string] $userAccountsCSVPath,
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Full path to csv report file")]
    [string] $reportCSVPath,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Current login name of SPUser to migrate")]
    [string] $oldAccount="HOU\wittbx",

    [Parameter(Mandatory=$false, Position=3, HelpMessage="New login name of SPUser after migration")]
    [string] $newAccount="MOC\wittbx",

    [Parameter(Mandatory=$false, Position=4, HelpMessage="New login name of SPUser after migration")]
    [string] $oldADForest="murphyoilcorp.com",

    [Parameter(Mandatory=$false, Position=5, HelpMessage="New login name of SPUser after migration")]
    [string] $newADForest="murphyoilcorp.org",

    [Parameter(Mandatory=$false, Position=6, HelpMessage="Call SPFarm.MigrateUserAccount or SPFarm.MigrateGroup internally?")]
    [switch] $move=$true
)

$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

if ((Get-Module | ? { $_.Name -eq "ActiveDirectory" }) -eq $null) {
    Import-Module ActiveDirectory
}

cls

function GetGroupSID($groupName, $forest)
{
    $sid = @{}

    $forest.Domains | % {
        try {
            $sid = Get-ADGroup -Identity $groupName -Server $_ | Select SID
            Write-Host "Found object with identity: '$groupName' under: '$_'" -BackgroundColor Green
        }
        catch {
            Write-Host $Error[0].Exception.Message -ForegroundColor Red
        }
    }

    return $sid.SID
}

function MigrateUser([PSCustomObject] $row)
{
    if($row.ProcessToday) {

        if($global:allSiteColls -ne $null) 
        { 
            $oldIdentity = [string]::Empty
            $newIdentity = [string]::Empty
            $enforceSIDHistory = $false

            $userType = $($row.PrincipalType.Trim())
            $oldLoginName = $($row.OldAccount.Trim())
            $newLoginName = $($row.NewAccount.Trim())

            switch($userType)
            {
                'ADUser'{
                    $oldIdentity = "i:0#.w|$oldLoginName"
                    $newIdentity = "i:0#.w|$newLoginName"
                }
                'ADGroup' {
                    $oldgr = [string]::Empty
                    if($oldLoginName -match '\\') {
                        $oldgr = $oldLoginName.Split("\")[1]
                    }
                    else {
                        $oldgr = $oldLoginName
                    }

                    $oldSID = GetGroupSID -groupName $oldgr -forest $global:sourceADForest

                    $newgr =[string]::Empty
                    if($newLoginName -match '\\') {
                        $newgr = $newLoginName.Split("\")[1]
                    }
                    else {
                        $newgr = $newLoginName
                    }
                    
                    $newSID = GetGroupSID -groupName $newgr -forest $global:targetADForest

                    $oldIdentity = "c:0+.w|$oldSID"
                    $newIdentity = "c:0+.w|$newSID"
                }
                default {}
            }

            $existsInColl = New-Object System.Collections.ArrayList

            Write-Host "-----------------------------------------------------------------------------------------------"

            Write-Host "Processing $userType principal ---> Name:'$oldLoginName' Current Identity:'$oldIdentity' New Identity:'$newIdentity' " -BackgroundColor Magenta

            foreach($siteColl in $global:allSiteColls) 
            {                
                $webUrl = $siteColl.url
                Write-Host "---> Checking site collection '$webUrl' " -NoNewline

                $found = "No"
                $moved = "No"
                $userDisplayName = [string]::Empty
                $user = $null
                    
                if($userType -eq "ADUser") {
                    #$user = Get-SPUser -Identity $oldIdentity -web $webUrl -Limit All
                    $user = Get-SPUser -web $webUrl -Limit All | ? { $_.UserLogin.ToUpper() -eq $oldIdentity.ToUpper() }
                }
                else {
                    $user = Get-SPUser -web $webUrl -Limit All | ? { ($_.IsDomainGroup) -and ($_.UserLogin.ToUpper() -eq $oldIdentity.ToUpper()) }
                }

                if($user -ne $null) {
                    $found = "Yes"

                    $userDisplayName = $user.DisplayName
                    Write-Host " $userType found. " -BackgroundColor Green -NoNewline
                    Write-Host " Display Name:'$userDisplayName' "
                    
                    $existsInColl.Add($webUrl) > $null

                    "$userType `t $userDisplayName `t $oldIdentity `t $newIdentity `t $webUrl `t $found" | out-file $global:reportPath -Append 

                }
                else {
                    Write-Host " $userType not found" -BackgroundColor White -ForegroundColor Black
                }
            }
            
            # only attempt to move a user principal if it has access anywhere in the farm  
            if($existsInColl.Count -gt 0) {
                if($global:move) {
                    $step1Success = $false

                    Write-Host "`nAttempting to migrate $userType identity across farm..." -BackgroundColor Yellow -ForegroundColor Black -NoNewline
                    
                    try {
                        switch($userType)
                        {
                            'ADUser'{
                                # verify that new identity is not an empty alias
                                if ($newIdentity -ne "i:0#w.|") {
                                    #Move-SPUser –Identity $user –NewAlias $newIdentity -ignoresid -Confirm:$false
                                    $global:SPFarm.MigrateUserAccount($oldIdentity, $newIdentity, $enforceSIDHistory)
                                    $step1Success = $true
                                }
                                else {
                                    Write-Host "Empty identity. New login invalid. Skipping..." -BackgroundColor Red
                                }
                            }
                            'ADGroup' {
                                if($newIdentity -ne "c:0+.w|") {
                                    $global:SPFarm.MigrateGroup($oldIdentity, $newIdentity)
                                    $step1Success = $true
                                }
                                else {
                                    Write-Host "Empty identity. New group invalid. Skipping..." -BackgroundColor Red
                                }
                            }
                            default {}
                        }
                    }
                    catch {
                        Write-Host $Error[0].Exception.ToString() -ForegroundColor Red -NoNewline
                    }

                    if($step1Success) {
                        Write-Host "Done" -BackgroundColor Green
                        Write-Host "`nEnsuring new $userType in site collection(s)..." -BackgroundColor Yellow -ForegroundColor Black -NoNewline
                        
                        try {
                                $existsInColl | % { Get-SPUser -Identity $newIdentity -Web $_ }
                                $moved = "Yes"
                                Write-Host "Done" -BackgroundColor Green

                                if($userType -eq 'ADGroup') {
                                    Write-Host "`nSetting display name of new $userType in site collection(s)..." -BackgroundColor Yellow -ForegroundColor Black -NoNewline
                                    Write-Host " New Display Name: $newLoginName " -NoNewline
                                    $existsInColl | % { Set-SPUser -Identity $newIdentity -Web $_ -DisplayName $newLoginName }
                                    Write-Host "Done" -BackgroundColor Green
                                }
                        }
                        catch {
                            Write-Host $Error[0].Exception.ToString() -ForegroundColor Red -NoNewline
                            Write-Host "Failed" -BackgroundColor Red
                        }
                    }
                }
            }

            if($moved -eq 'Yes') {
                Write-Host "`nMigrated? $moved" -BackgroundColor Green
            }
            else {
                Write-Host "`nMigrated? $moved" -BackgroundColor Red
            }
        }
    }
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
            MigrateUser $_ | out-null
        }
    }
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$timestamp = Get-Date -Format s | % { $_ -replace ":", "-" }

if([string]::IsNullOrWhiteSpace($reportCSVPath))
{
    $currentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $reportCSVPath = $currentDir + "\Move-UserDomain-Reports\Move-UserDomain-Report-" + $timestamp + ".csv"
    Write-Host "You did not specify a path to the report csv file. The report will be created at '$reportCSVPath'" -ForegroundColor Cyan
}

$global:reportPath = $reportCSVPath

#Write CSV - TAB Separated File Header
"UserType `t DisplayName `t CurrentLogin `t NewLogin `t WebUrl `t UserExisted?" | out-file $global:reportPath

$global:csv = $null 
$global:move = $move
$global:SPFarm = Get-SPFarm
$global:sourceADForest = Get-ADForest -server $oldADForest
$global:targetADForest = Get-ADForest -server $newADForest
$global:allSiteColls = Get-SPSite -Limit All

if(![string]::IsNullOrWhiteSpace($userAccountsCSVPath))
{
    ProcessCSV $userAccountsCSVPath
}
else 
{
    write-host "You did not specify a csv file containing user accounts to migrate...." -ForegroundColor Cyan

    $csvPathEntryReponse = Read-Host "Would you like to enter the full path of the csv file? [y|n]"
    if($csvPathEntryReponse -eq 'y') {
        do {
            $path = Read-Host "Enter full path to the csv file containing user accounts to migrate."
        }
        until (![string]::IsNullOrWhiteSpace($path))

        ProcessCSV $path
    }
    else {
        Write-Host "Migrating individual user account or AD group..." -BackgroundColor White -ForegroundColor Black
        Write-Host "1: Press '1' if migrating user account"
        Write-Host "2: Press '2' if migrating AD group"
        $input = Read-Host "What are you migrating?"
        $type = [string]::Empty
        
        switch ($input)
        {
            '1'{
                $type = "ADUser"
            }
            '2' {
                $type = "ADGroup"
            }
            default {
                $type = "ADUser"
            }
        }

        Write-Host "You selected $type migration" -BackgroundColor White -ForegroundColor Black

        if([string]::IsNullOrWhiteSpace($oldAccount))
        {
            do {
                $oldAccount = Read-Host "Specify the current login (domain\alias) of the user principal to migrate"
            }
            until (![string]::IsNullOrWhiteSpace($oldAccount))
        }

        if([string]::IsNullOrWhiteSpace($newAccount))
        {
            do {
                $newAccount = Read-Host "Specify the new login (domain\alias) of the user principal after migration"
            }
            until (![string]::IsNullOrWhiteSpace($newAccount))
        }

        $row = @{OldAccount=$oldAccount;NewAccount=$newAccount;PrincipalType=$type;ProcessToday=$true}
    
        MigrateUser $row | Out-Null
    }
}

<#
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
#>

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow