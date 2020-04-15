Add-PSSnapin Microsoft.SharePoint.PowerShell 
cls
Start-SPAssignment -Global 

$OutputFile = "e:\DocCount1YearAgo.csv" 

$results = @() 


$webApp = Get-SPWebApplication -Identity http://portal.murphyoilcorp.com

if($webApp -ne $null)
{ 
    foreach($siteColl in $webApp.Sites) 
    {
        Write-Host "Processing site collection $($siteColl.url)....$($($siteColl.ContentDatabase.DiskSizeRequired)/1GB)"

        foreach($web in $siteColl.AllWebs) 
        { 
                $webUrl = $web.url
                Write-Host "---> Processing web...$webUrl"
                $docLibs = $web.Lists | ?{$_.baseType -eq "DocumentLibrary"}

                $docLibs | Add-Member -MemberType ScriptProperty -Name WebUrl -Value {$webUrl} 
                $docLibs | Add-Member -MemberType NoteProperty -Name "12MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "11MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "10MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "9MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "8MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "7MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "6MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "5MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "4MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "3MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "2MonthOld" -Value 0
                $docLibs | Add-Member -MemberType NoteProperty -Name "1MonthOld" -Value 0


                $docLibs | % {
                    Write-Host "------> Processing Lib: $($_.Title)..."
                    $lib = $_

                    for($i = 1; $i -le 12; $i++) {
                        $spQuery = New-Object Microsoft.SharePoint.SPQuery 
                    
                        #CAML Query Using a DateTime Value and and Offset of Today

                        $itemsCount = 0
                        $itemsColl = $null
                        $label = "$($i)MonthOld"
                        $query =[string]::Empty

                        if ($i -lt 12) {
                            $query = @('<Where>
                                        <And>
                                            <Leq>
                                                <FieldRef Name="Created" />
                                                <Value Type="DateTime"><Today OffsetDays="' + ($i*-30) + '" /></Value>
                                            </Leq>
                                            <Gt>
                                                <FieldRef Name="Created" />
                                                <Value Type="DateTime"><Today OffsetDays="' + ($i+1) * -30 + '" /></Value>
                                            </Gt>
                                        </And>
                                    </Where>')
                        }
                        else {
                            $query = @('<Where>
                                    <Leq>
                                        <FieldRef Name="Created" />
                                        <Value Type="DateTime"><Today OffsetDays="-365" /></Value>
                                    </Leq>
                                </Where>')
                        }

                        $spQuery.ViewAttributes = "Scope = 'Recursive'" 
                        $spQuery.Query = $query
                        $spQuery.RowLimit = $lib.ItemCount

                        $itemsColl = $lib.GetItems($spQuery)

                        if($itemsColl -ne $null) {
                            $itemsCount = $itemsColl.Count
                        }

                        $lib."$label" = $itemsCount
                    }
                }
                
                $results += ($docLibs | Select-Object -Property WebUrl, Title, ItemCount, 12MonthOld, 11MonthOld, 10MonthOld, 9MonthOld, 8MonthOld, 7MonthOld, 6MonthOld, 5MonthOld, 4MonthOld, 3MonthOld, 2MonthOld, 1MonthOld)

                $web.Dispose()
            }

        $siteColl.Dispose()
    } 
} 

$results | Export-Csv -Path $OutputFile -NoTypeInformation 
  

Stop-SPAssignment -Global 