if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

Get-SPDatabase | % {$db=0} {$db +=$_.disksizerequired; $_.name + " - " + $_.disksizerequired/1GB}
Write-Host "`nTotal Storage (in GB) =" ("{0:n0}" -f ($db/1GB))