<#  
.Description  
    Configures any or all non-index processing components for search service 
#>
if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$ssaConfig = @{
	ssaName = "Search Service Application"                  #name of SSA

	servers = @{ 
		"AZUSPESRC01"   = @{ 
                            components = (
                               #@{type="Admin";deleteCurrent="$false"},
                                @{type="CP";deleteCurrent=$true}
                            )
                         };
		"AZUSPESRC02"   = @{ 
                            components = (
                               #@{type="Admin";deleteCurrent="$false"},
                                @{type="CP";deleteCurrent=$true}
                            )
                         };
	}
};

#---------------------
# Component Type Key:
#---------------------
  #   Admin: Admin Component
  #   CC: Crawl Component
  #   CP: Content Processing Component
  #   AP: Analytics Processing Component
  #   Idx: Index Component
  #   QP: Query Processing Component

$componentsToDeploy = @()

#---------------------------------------------------------------------------
# Start service instances on each server 
# and validate RootDirectory paths on Indexers
#---------------------------------------------------------------------------
$passedChecks = $true
foreach ($netbios in $ssaConfig.servers.keys) {	
	Write-Host ("[" + $netbios + "]") -ForegroundColor DarkCyan
	Write-Host ("   Components: " + $ssaConfig.servers[$netbios].Components)
	$componentsToDeploy += $ssaConfig.servers[$netbios].Components

	# start the Search Instances (if not already online) on the relevant servers
    if ((Get-SPServer $netbios -ErrorVariable err -ErrorAction SilentlyContinue) -eq $null) {
        Write-Warning ("The server" + $netbios + "is not found in this farm...") 
    } else {
        if ((Get-SPEnterpriseSearchServiceInstance -identity $netbios).status -ne "Online") {
			Write-Host ("   Starting `"SharePoint Server Search`" Service Instance...")
			Start-SPEnterpriseSearchServiceInstance -identity $netbios
        } 
    }

    $ssaConfig.servers[$netbios].instance = Get-SPEnterpriseSearchServiceInstance -identity $netbios
}

<#
Write-Host
$referenceComponents = ("Admin", "CC", "CP", "Idx", "AP", "QP")
$delta = Compare-Object $referenceComponents $($componentsToDeploy | SELECT -Unique)
if ($delta.Count -gt 0) {
	Write-Warning ("This requested topology is missing at least one of the following components:")
	Write-Host $( $delta | ForEach {$_.InputObject})
	$passedChecks = $false
}
#>

if (-not $passedChecks) {
	Write-Warning ("One or more checks above failed... <terminating script>") 
	start-sleep 2;
	exit;
}

#toDo: Dump out settings and ask for confirmation here...
#toDo: Check that each of the component types are being added to at least one server...

$ssa = Get-SPEnterpriseSearchServiceApplication

if($ssa -eq $null) {

	Write-Warning ("No search service application was found in this farm... <terminating script>") 
	start-sleep 5;
	exit;
}

if($ssa.IsPaused() -ne 0) {

	Write-Warning ("Search service application is paused due to a previous incomplete configuration. Please resolve existing paused state issue before proceeding... <terminating script>") 
	start-sleep 5;
	exit;
}

Write-Host "`nExisting search topology attributes..." -ForegroundColor Gray

$activeTopology = Get-SPEnterpriseSearchTopology -SearchApplication $ssa -Active
$activeTopology

Write-Host "................................................" -ForegroundColor Gray

Write-Host "`nExisting search topology component status..." -ForegroundColor Gray

Get-SPEnterpriseSearchStatus -SearchApplication $ssa -Text

Write-Host "................................................" -ForegroundColor Gray

Write-Host "`nCloning existing search topology. Clone topology attributes..." -ForegroundColor Gray

$cloneTopology = New-SPEnterpriseSearchTopology -SearchApplication $ssa -Clone -SearchTopology $activeTopology
$cloneTopology

Write-Host "................................................" -ForegroundColor Gray

#------------------------------------------
# Create the new components on each server
#------------------------------------------
Write-Host -ForegroundColor Gray "`nCreating Components on specified server(s)... "
foreach ($netbios in $ssaConfig.servers.keys) {
	foreach ($component in $ssaConfig.servers[$netbios].components) {
        $type = $component.type
        $del = $component.deleteCurrent
        Write-Host ("   [" + $netbios + "] --> " + $type + "  delete if existing -->" + $del)
        switch ($type) {
		    "Admin" {
                if($del) {
                    Write-Host "`nDeleting existing $type component..." -ForegroundColor Gray -NoNewline
                    $existing = $cloneTopology.GetComponents() | ?{ ($_.Name -like "AdminComponent*") -and ($_.ServerName -eq $netbios)}
                    if($existing -ne $null) {
                        $existing | % { $cloneTopology.RemoveComponent($_) }
                        Write-Host "Done" -BackgroundColor Green -ForegroundColor White
                    }
                    else {
                        Write-Host "No existing $type component on this server" -BackgroundColor Green -ForegroundColor White
                    }
                }

    			New-SPEnterpriseSearchAdminComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance
                $ssa | Get-SPEnterpriseSearchAdministrationComponent | Set-SPEnterpriseSearchAdministrationComponent -SearchServiceInstance $ssaConfig.servers[$netbios].instance
			    $ssa | Get-SPEnterpriseSearchAdministrationComponent
		    }
	    	"CC" { 
                if($del) {
                    Write-Host "`nDeleting existing $type component..." -ForegroundColor Gray -NoNewline
                    $existing = $cloneTopology.GetComponents() | ?{ ($_.Name -like "CrawlComponent*") -and ($_.ServerName -eq $netbios)}
                    if($existing -ne $null) {
                        $existing | % { $cloneTopology.RemoveComponent($_) }
                        Write-Host "Done" -BackgroundColor Green -ForegroundColor White
                    }
                    else {
                        Write-Host "No existing $type component on this server" -BackgroundColor Green -ForegroundColor White
                    }
                }

                New-SPEnterpriseSearchCrawlComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance 
            }
	    	"CP" { 
                if($del) {
                    Write-Host "`nDeleting existing $type component..." -ForegroundColor Gray -NoNewline
                    $existing = $cloneTopology.GetComponents() | ?{ ($_.Name -like "ContentProcessingComponent*") -and ($_.ServerName -eq $netbios)}
                    if($existing -ne $null) {
                        $existing | % { $cloneTopology.RemoveComponent($_) }
                        Write-Host "Done" -BackgroundColor Green -ForegroundColor White
                    }
                    else {
                        Write-Host "No existing $type component on this server" -BackgroundColor Green -ForegroundColor White
                    }
                }

                New-SPEnterpriseSearchContentProcessingComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance 
            }
	    	"AP" { 
                if($del) {
                    Write-Host "`nDeleting existing $type component..." -ForegroundColor Gray -NoNewline
                    $existing = $cloneTopology.GetComponents() | ?{ ($_.Name -like "AnalyticsProcessingComponent*") -and ($_.ServerName -eq $netbios)}
                    if($existing -ne $null) {
                        $existing | % { $cloneTopology.RemoveComponent($_) }
                        Write-Host "Done" -BackgroundColor Green -ForegroundColor White
                    }
                    else {
                        Write-Host "No existing $type component on this server" -BackgroundColor Green -ForegroundColor White
                    }
                }

                New-SPEnterpriseSearchAnalyticsProcessingComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance 
            }
			"QP" { 
                if($del) {
                    Write-Host "`nDeleting existing $type component..." -ForegroundColor Gray -NoNewline
                    $existing = $cloneTopology.GetComponents() | ?{ ($_.Name -like "QueryProcessingComponent*") -and ($_.ServerName -eq $netbios)}
                    if($existing -ne $null) {
                        $existing | % { $cloneTopology.RemoveComponent($_) }
                        Write-Host "Done" -BackgroundColor Green -ForegroundColor White
                    }
                    else {
                        Write-Host "No existing $type component on this server" -BackgroundColor Green -ForegroundColor White
                    }
                }
                
                New-SPEnterpriseSearchQueryProcessingComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance 
            }
		}
	}
}

Write-Host -ForegroundColor Gray "`nActivating new topology...$(Get-Date)"

$cloneTopology.Activate()

while ($cloneTopology.State -ne "Active") { 
    Write-Host "." -NoNewline
    Start-sleep 10
}

Write-Host -ForegroundColor White "`nNew topology activated...$(Get-Date)" -BackgroundColor Green

Write-Host -foregroundcolor Gray "`nCleaning up the inactive topology..."
$ssa | Get-SPEnterpriseSearchTopology | Where { $_.State -eq "Inactive" } | Remove-SPEnterpriseSearchTopology -Confirm:$false

Write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow