<#  
.Description  
    Clears select syscache files that are not removed by StoragePoint timer jobs 
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="StoragePoint SYSCACHE root folder or subfolder path")]
    [string] $syscachePath,

    [Parameter(Mandatory=$false, Position=1, HelpMessage="File extension(s) of files to be removed. Comma separated list.")]
    [string] $fileExt,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Items older than these many days will be purged")]
    [int] $days
)

cls

$global:totalPurgeCount = 0

$defaultFileExt = "blnk"
if([string]::IsNullOrWhiteSpace($fileExt))
{
    $fileExt = $defaultFileExt
}

$defaultDays = 30
if($days -eq 0)
{
    $days = $defaultDays
}

Write-Host "-----Starting StoragePoint syscache cleanup--------------$(Get-Date)"

    $currentDate = Get-Date

    $dateToDelete = $currentDate.AddDays($($days * -1))

    $fileExtFilter = [string]::Empty
    $fileExts = $fileExt -split ","
    $fileExts | %{ $fileExtFilter = $fileExtFilter + "*." + $_.ToString().Trim() + "," }
    $fileExtFilter = $fileExtFilter.TrimEnd(",")

    $files = Get-ChildItem $syscachePath -Recurse -include $fileExtFilter| ? { $_.LastWriteTime -lt $dateToDelete }

    Write-Host "Syscache items of type $fileExt older than $dateToDelete will be purged..."

    Write-Host "Found $($files.Length) such items..."
    
    foreach($file in $files) {
        Write-Host "Removing file $($file.FullName)..." -NoNewline
        $file.Delete()
        Write-Host "Done" -ForegroundColor White -BackgroundColor Green

        $global:totalPurgeCount += 1
    }

Write-Host "-----Completed StoragePoint syscache cleanup--------------$(Get-Date)"
Write-Host "Total items purged: $global:totalPurgeCount"