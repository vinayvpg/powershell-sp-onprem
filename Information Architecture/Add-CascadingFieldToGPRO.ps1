add-pssnapin microsoft.sharepoint.powershell

$site = Get-SPSite http://teams.murphyoilcorp.com

$cascadingField = $site.RootWeb.AvailableFields["CascadingField2"]

$listName = "QSL/Procurement Plan Database"

$webUrl = "http://teams.murphyoilcorp.com/gpro/purchasing"

$web = Get-SPWeb $webUrl

if($web -ne $null) {
    $list = $web.Lists[$listName]

    if($list -ne $null) {
        $list.Fields.Add($cascadingField)
        $list.Update()
    }
}

$web.Dispose()

$site.Dispose()
