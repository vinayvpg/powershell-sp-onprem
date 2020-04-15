<#  
.Description  
    Configures the index components for search service 
#>
if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$ssaConfig = @{
	ssaName = "Search Service Application"                  #name of your SSA

	servers = @{ 
		"AZUSPEWEB01"   = @{ components = ("Idx");
							replicaConfig = (
                                @{ Partition=1; Path="G:\Index\IdxPartition1" }
                                #@{ Partition=2; Path="E:\Index\IdxPartition2" }
                            );
					       };
		"AZUSPEWEB02"   = @{ components = ("Idx"); 
							replicaConfig = (
                                @{ Partition=1; Path="G:\Index\IdxPartition1" }
								#@{ Partition=2; Path="E:\Index\IdxPartition2" }
							);
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

	# validate the `"RootDirectory`" path if this is an Indexer server
	$idxConfig = $ssaConfig.servers[$netbios].replicaConfig
	if ($idxConfig -ne $null) {
		if ($idxConfig -is [Hashtable]) {
			$ssaConfig.servers[$netbios].replicaConfig = @( $idxConfig )
			$idxConfig = $ssaConfig.servers[$netbios].replicaConfig 
		}
		if ($idxConfig.Count -gt 4) {
			Write-Warning ("More than 4 Index Replicas on a single server is not supported")
			$passedChecks = $false
		} else {
			foreach ($replica in $idxConfig) {
				Write-Host ("   Index Replica")
				if ($replica.Partition -ne $null) {
					Write-Host ("     - Partition (#): " + $replica.Partition)
				}
				if ($replica.Path -ne $null) {
					Write-Host ("     - RootDirectory: " + $replica.Path)
					if ($netbios -ine $ENV:COMPUTERNAME) {
						$rootDirectory = "\\" + $netbios + "\" + $replica.Path.Replace(":\","$\")
					} else {
						$rootDirectory = $replica.Path
					}
					Write-Verbose ("     Testing if RootDirectory Exists: " + $rootDirectory)
					
					if (Test-Path $rootDirectory) {
						Write-Verbose ("     RootDirectory Exists...")
						$contents = $rootDirectory | gci
						if ($contents.Count -gt 0) {
							Write-Warning ("The following RootDirectory is not empty as required: " + $replica.path)
							$passedChecks = $false
						}
					} else {
						Write-Warning ("The following RootDirectory does not exist: " + $replica.path)
						$userResponse = Read-Host ("     Would you like this script to create this path for you? [y|n]")
						if (($userResponse -ieq "y") -or ($userResponse -ieq "yes")) {
							Write-Host ("     Creating RootDirectory: " + $rootDirectory)
							New-Item -path $rootDirectory -ItemType Directory | Out-Null
						}
						$passedChecks = $(Test-Path $rootDirectory)
					}
				}
			}
		}
	}
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

$global:foo = $ssaConfig
if (-not $passedChecks) {
	Write-Warning ("One or more checks above failed... <terminating script>") 
	start-sleep 2;
	exit;
}

#toDo: Dump out settings and ask for confirmation here...
#toDo: Check that each of the component types are being added to at least one server...

$err = $null

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

Write-Host

$proceed = Read-Host "Verify all components are in healthy state and active. Proceed?[y|n]"

if($proceed -ne 'y') {
	Write-Warning ("Components not in healthy state... <terminating script>") 
	start-sleep 5;
	exit;
}

Write-Host "`nCloning existing search topology. Clone topology attributes..." -ForegroundColor Gray

$cloneTopology = New-SPEnterpriseSearchTopology -SearchApplication $ssa -Clone -SearchTopology $activeTopology
$cloneTopology

Write-Host "................................................" -ForegroundColor Gray

#------------------------------------------
# Create the new components on each server
#------------------------------------------
Write-Host -ForegroundColor Gray "`nCreating Components on specified server(s)... "
foreach ($netbios in $ssaConfig.servers.keys) {
	foreach ($type in $ssaConfig.servers[$netbios].components) {
        Write-Host ("   [" + $netbios + "] --> " + $type)
        switch ($type) {
		    "Admin" {
    			New-SPEnterpriseSearchAdminComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance
                $ssa | Get-SPEnterpriseSearchAdministrationComponent | Set-SPEnterpriseSearchAdministrationComponent -SearchServiceInstance $ssaConfig.servers[$netbios].instance
			    $ssa | Get-SPEnterpriseSearchAdministrationComponent
		    }
	    	"CC" { New-SPEnterpriseSearchCrawlComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance }
	    	"CP" { New-SPEnterpriseSearchContentProcessingComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance }
	    	"AP" { New-SPEnterpriseSearchAnalyticsProcessingComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance }
			"QP" { New-SPEnterpriseSearchQueryProcessingComponent -SearchTopology $cloneTopology -SearchServiceInstance $ssaConfig.servers[$netbios].instance }
			"Idx" { 
				$idxConfig = $ssaConfig.servers[$netbios].replicaConfig
				if ($idxConfig -ne $null) {
					foreach ($replica in $idxConfig) {
						if ($replica.Partition -eq $null) { $partition = 0 }
						else { $partition = $replica.Partition }
						
						$idxComp = (New-Object Microsoft.Office.Server.Search.Administration.Topology.IndexComponent $netbios, $partition);
						if ($replica.Path -ne $null) {
							$idxComp.RootDirectory = $replica.Path
						}
						$cloneTopology.AddComponent($idxComp)
						$idxComp
					}
				} else {
					$idxComp = (New-Object Microsoft.Office.Server.Search.Administration.Topology.IndexComponent $netbios, 0);
					$newTopo.AddComponent($idxComp)
					$idxComp
				}
			}
		}
	}
}

Write-Host -ForegroundColor Gray "`nPausing for index repartitioning...$(Get-Date)"
while(-not $ssa.PauseForIndexRepartitioning()) {
    Write-Host "." -NoNewline
    Start-Sleep 60
}

Write-Host -ForegroundColor White "`nFinished pausing for index repartitioning...$(Get-Date)" -BackgroundColor Green

#Set-SPEnterpriseSearchTopology -Identity $cloneTopology

Write-Host -ForegroundColor Gray "`nActivating new topology with partitioned index...$(Get-Date)"

$cloneTopology.Activate()

while ($cloneTopology.State -ne "Active") { 
    Write-Host "." -NoNewline
    Start-sleep 60
}
Write-Host -ForegroundColor White "`nNew topology activated...$(Get-Date)" -BackgroundColor Green

Write-Host -ForegroundColor Gray "`nResuming after index repartitioning...$(Get-Date)"
while(-not $ssa.ResumeAfterIndexRepartitioning()) {
    Write-Host "--------------Component status at $(Get-Date)..."

    Get-SPEnterpriseSearchStatus -SearchApplication $ssa | ft -AutoSize Name, State, Details

    Start-sleep 60
}
Write-Host -ForegroundColor White "`nDone...$(Get-Date)" -BackgroundColor Green

Write-Host -foregroundcolor Gray "`nCleaning up the inactive topology..."
$ssa | Get-SPEnterpriseSearchTopology | Where { $_.State -eq "Inactive" } | Remove-SPEnterpriseSearchTopology -Confirm:$false

Write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow