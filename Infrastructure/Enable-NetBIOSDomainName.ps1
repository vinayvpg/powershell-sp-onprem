<#
    Script to enabled NetBIOSDomainName on user profile service application
    This is required because Murphy has a multiple domain forest and root domain name (moc_w2k) and forest name (murphyoilcorp.com) are different
    Ideally, this should be done BEFORE establishing a sync connection and performing the first sync. If not you'll have to
    delete the connection and re-establish it in which case the sync will delete and the profiles that came in with incorrect NetBIOSDomain names
#>

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

Write-Host "Getting user profile service application for the farm..." -NoNewline

$upsa = Get-SPServiceApplication | ? { $_.TypeName -like "User Profile Service*" }

if($upsa -ne $null) {
    Write-Host "Done" -BackgroundColor Green

    Write-Host "Setting NetBIOSDomainNamesEnabled = 1..." -NoNewline

    $upsa.NetBIOSDomainNamesEnabled = 1

    $upsa.Update()

    Write-Host "Done" -BackgroundColor Green
}
else {
    Write-Host "Not found. Quitting." -BackgroundColor Red
}