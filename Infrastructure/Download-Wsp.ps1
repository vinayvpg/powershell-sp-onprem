if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

$farm = Get-SPFarm

if($farm -ne $null) {
    $farm.Solutions | %{
        $_.SolutionFile.SaveAs("e:\scripts\wsps\" + $_.Name)
    }
}