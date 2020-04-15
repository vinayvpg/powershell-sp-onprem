<#
    Script to run CAML queries over CSOM
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="CAML query")]
    [string] $camlQuery,

    [Parameter(Mandatory=$false, Position=1, HelpMessage="Web url")]
    [string] $webUrl,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Target list title")]
    [string] $listTitle
)

$ErrorActionPreference = "Continue"

#if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
#    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
#}

cls

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime") | Out-Null

$userName = ""
$password = ""

$camlQuery = "<View Scope='FilesOnly'><Query><Where><And><Eq>
<FieldRef Name='FileDirRef'/>
<Value Type='Text'>/Documentum/DCTM moc_wmtbankstm/2013/Batch02/_002</Value>
</Eq><Eq><FieldRef Name='FileLeafRef'/><Value Type='File'>000A17DB.TIF</Value></Eq></And>
</Where>
</Query></View>"

$webUrl = "http://legacydocs.murphyoilcorp.com/documentum"

$listTitle = "DCTM moc_wmtbankstm"

$clientContext = New-Object Microsoft.SharePoint.Client.ClientContext($webUrl)
$clientContext.Credentials = New-Object System.Net.NetworkCredential($userName, $password)

if($clientContext -ne $null) {
    $list = $clientContext.Web.Lists.GetByTitle($listTitle)

    if($list -ne $null) {
        $query = New-Object Microsoft.SharePoint.Client.CamlQuery
        $query.FolderServerRelativeUrl = "/Documentum/DCTM moc_wmtbankstm/2013/Batch02/_002"
        $query.ViewXml = $camlQuery

        $listItems = $list.GetItems($query)

        $clientContext.Load($listItems)
        
        $clientContext.ExecuteQuery()
        Write-Host "Query executed"
        if($listItems -ne $null) {
            Write-Host "Enumerating list items $($listItems.Count)"
            foreach($item in $listItems) {
                $item.Id
            }
        }
        
    }
}

