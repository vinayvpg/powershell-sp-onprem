Add-PSSnapin Microsoft.SharePoint.PowerShell 
cls
Start-SPAssignment -Global 

$append = "$($(Get-Date).Month)$($(Get-Date).Day)$($(Get-Date).Year)_$($(Get-Date).Hour)$($(Get-Date).Minute)$($(Get-Date).Second)"
$OutputFile = "e:\DocCount_documentum_$append.csv" 

$results = @() 


$webApp = Get-SPWebApplication -Identity http://portal.murphyoilcorp.com

if($webApp -ne $null) 
{ 
    foreach($siteColl in $webApp.Sites) 
    {
        $siteCollUrl = $siteColl.url

        Write-Host "Processing site collection $siteCollUrl....$($($siteColl.ContentDatabase.DiskSizeRequired)/1GB)"

        if($siteCollUrl -like "*legacydocs*") {
        
            foreach($web in $siteColl.AllWebs) 
            { 
                $webUrl = $web.url
                if($webUrl -like "*documentum*") {
                    Write-Host "-----> Processing web...$webUrl"
                    $docLibs = $web.Lists | Where-Object { ($_.baseType -eq "DocumentLibrary") -and ($_.Title -like "*DCTM*")} 
                    $docLibs | Add-Member -MemberType ScriptProperty -Name WebUrl -Value { $webUrl } 
                    $results += ($docLibs | Select-Object -Property WebUrl, Title, ItemCount)
                } 
            }
        }
    } 
} 

$results | Export-Csv -Path $OutputFile -NoTypeInformation 
  

Stop-SPAssignment -Global 