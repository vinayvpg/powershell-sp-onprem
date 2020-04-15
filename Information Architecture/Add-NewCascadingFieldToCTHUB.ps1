add-pssnapin microsoft.sharepoint.powershell

$fieldName = "CascadingField4"
$ctHubRootUrl = "http://cthub.murphyoilcorp.com"

$ctHubWeb = Get-SPWeb $ctHubRootUrl

$cascadingField = $ctHubWeb.AvailableFields[$fieldName]

if($cascadingField -eq $null) {
   $cascadingField = $ctHubWeb.Fields.Add($fieldName, [Microsoft.SharePoint.SPFieldType]::Note, $false)
   $cascadingField.JSLink = "~layouts/MOC.SharePoint/Modular.CSR.Utils.js | ~layouts/MOC.SharePoint/CascadingField/cascadingFieldCSR2.js"
   $cascadingField.Update($true)
}
else {
    Write-Host "Field exists. Checking if it exists directly at the scope $ctHubRootUrl..."
    $cascadingField = $ctHubWeb.Fields[$fieldName]
    if($cascadingField -ne $null) {
        $cascadingField.JSLink = "~layouts/MOC.SharePoint/Modular.CSR.Utils.js | ~layouts/MOC.SharePoint/CascadingField/cascadingFieldCSR2.js"
        $cascadingField.Update($true)
    }
    else {
        Write-Host "Field does not exist at this scope. JSLink changes not applied"
    }
}

