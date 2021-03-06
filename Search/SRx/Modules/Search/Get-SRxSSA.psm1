function Get-SRxSSA {	
<#
.SYNOPSIS 
	Extends the out-of-the-box [SearchServiceApplication] object with custom methods and properties (e.g. $ssa => $xSSA)

.DESCRIPTION 
	The extended SSA object, or $xSSA for short, provides many new methods and properties 
	that empowers an engineer to dive deep into the Search Service Application. This module
	also extends each of the Search components associated with this SSA, and when run with
	the "-Extended" flag, captures system level information such as CPU cores, RAM, volume
	(disk) information, and registry keys related to Search. 
	
	All extended properties have an underscore "_" prefix, such as $xSSA._Components or 
	$xSSA._GetPrimaryAdminComponent(). All extended properties can be seen by running:
		$xSSA | get-member
	
.NOTES
	=========================================
	Project		: Search Health Reports (SRx)
	-----------------------------------------
	File Name 	: Get-SRxSSA.psm1
    Author		: Brian Pendergrass
	Requires	: 
		PowerShell Version 3.0, Search Health Reports (SRx), Microsoft.SharePoint.PowerShell
	
	========================================================================================
	This Sample Code is provided for the purpose of illustration only and is not intended to 
	be used in a production environment.  
	
		THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY
		OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
		WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.

	We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to 
	reproduce and distribute the object code form of the Sample Code, provided that You agree:
		(i) to not use Our name, logo, or trademarks to market Your software product in 
			which the Sample Code is embedded; 
		(ii) to include a valid copyright notice on Your software product in which the 
			 Sample Code is embedded; 
		and 
		(iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against
			  any claims or lawsuits, including attorneys' fees, that arise or result from 
			  the use or distribution of the Sample Code.

	========================================================================================
	--- REGARDING MULTIPLE SSAs ---
	Although it is supported to have multiple SSAs in a single farm), it is against
	best practices to provision multiple SSAs in a single farm. Therefore, this
	module and methods only provides a best effort to support multiple SSAs
	   - The ideal usage and most tested cases for this module involes one SSA
	
	As documented in this TechNet article...
	   Create and configure a Search service application in SharePoint Server 2013
	   https://technet.microsoft.com/en-us/library/gg502597%28v=office.15%29.aspx

		"Each Search service application has its own search topology. If you
		 create more than one Search service application in a farm, we recommend
		 that you allocate dedicated servers for the search topology of each 
		 Search service application. Deploying several Search service applications
		 to the same servers will significantly increase the resource requirements
		 (CPU and memory) on those servers."

 	In other words, if your organization has a very specific business requirement for
	multiple SSAs, then keep in mind that there is no substantial benefit to multiple
	SSAs in one farm because you still need additional hardware/servers to facilitate
	the second SSA. Meaning, there is no real drawback (other than the overhead of a 
	second Central Admin, which is minimal at best) to putting these in separate farms
	Further, if data isolation is the business requirement, separate farms arguably 
	provides better isolation (namely service accounts, which are configured farm-wide)
	-------------------------------
	
.INPUTS
	$SSA [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]

.OUTPUTS
	$xSSA : An extended Search Service Application object

.EXAMPLE
	Get-SRxSSA $targetSSA
	Specify a single SSA object, name, or ID of an SSA provisioned in this farm (creates $SSA object in the global scope)
	
	#Equivalent invocations...
	$targetSSA | Get-SRxSSA 
	Get-SRxSSA "-the-name-of-my-SSA-"
	Get-SRxSSA "f9ed646c-e520-4fc2-91fb-2ec963fae67a"
	Get-SRxSSA         #assums only one SSA in the farm

.EXAMPLE
	Get-SRxSSA -Extended
	The $xSSA is generated, but an extended SRx server object is generated for each server
	with a Search component and cached in $xSSA._Servers. A single server object can be 
	retrieved using $xSSA._GetServer("serverName")

.EXAMPLE
	The $xSSA also enhances each component and provides shortcuts to each component type:
		$xSSA._Components	: Lists all components in the Active topology
		$xSSA._GetCC()		: Gets all of the Crawl Components
		$xSSA._GetCPC()		: Gets all of the Content Processing Components
		$xSSA._GetAPC()		: Gets all of the Analytics Processing Components
		$xSSA._GetQPC()		: Gets all of the Query Processing Components
		$xSSA._GetIndexer()	: Gets all of the Index Components
			$xSSA._GetPrimaryIndexReplica()		: Gets the "Primary" Index Component from each Partition
		$xSSA._GetAdmin()	: Gets all of the Admin Components
			$xSSA._GetPrimaryAdminComponent()	: Gets the "Primary" Admin Component

#>
[CmdletBinding()]
param ( 
  		[parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
			[AllowEmptyString()]
			[alias("SearchServiceApplication")]$SSA,
		[alias("Extended")][switch]$ExtendedConfig,
		[alias("Rebuild")][switch]$RebuildSRxSSA
	)
	
	BEGIN { 		
		#== Variables ===
		$moduleMsgPrefix = "[Get-SRxSSA]"
		
		if ($global:SRxEnv.DebugTimings -is [hashtable]) { 
			$TrackDebugTimings = $true
			$global:SRxEnv.DebugTimings[$moduleMsgPrefix] = $(New-Object System.Collections.ArrayList)
			$global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Beginning $moduleMsgPrefix..." } ) | Out-Null
		}
			
		#== Create the result set (e.g. for handling pipelined input)
		$results = New-Object System.Collections.ArrayList
		
		Write-SRx VERBOSE $($moduleMsgPrefix +" Beginning...")
	} 

	#if this farm has multiple SSAs and the were pipelined in, such as:  $SSAs | Get-SRxSSA
	# then this PROCESS block will handle a single SSA ...one by one
	PROCESS {
		#== Check for request to rebuild the xSSA ===
        if ($RebuildSRxSSA -and ($xSSA._hasSRx -or $SSA._hasSRx)) {                                         #if "rebuild"...
            if (-not ([String]::IsNullOrEmpty($SSA.Name))) { $SSA = $SSA.Name }                                 #then either use the name of the incoming SSA  
            elseif ((-not $SSA) -and (-not ([String]::IsNullOrEmpty($xSSA.Name)))) { $SSA = $xSSA.Name }        #or the name of the xSSA (if SSA is null)
            #else { $SSA = $SSA }                                                                           #or use the [string] value specified w/ $SSA
            $xSSA = $null                                                                                   #then nullify the xSSA
        } 

        #== Determine the [target]SSA context ===
		#Regardless of the incoming object type (e.g. string, array, SP SSA, or $null), 
		#   here we [try to] normalize $SSA into an SSA object (e.g. $targetSSA)
		if (([String]::IsNullOrEmpty($SSA)) -or (-not $SSA) -or ($SSA.Count -eq 0)) {
			#if this farm has multiple SSAs, this would return multiple SSAs here...
			Write-SRx VERBOSE $($moduleMsgPrefix + " Calling: Get-SPEnterpriseSearchServiceApplication...")
			if ($xSSA._hasSRx -and (-not $RebuildSRxSSA)) { 
                $targetSSA = $xSSA #only reuse if not trying to rebuild it
            } else { 
                try {
                    $targetSSA = Get-SPEnterpriseSearchServiceApplication
                } catch {
                    Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Failed to load an SSA object from: Get-SPEnterpriseSearchServiceApplication") 
                }
            }
		} elseif ($SSA -is [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]) {
			Write-SRx VERBOSE $($moduleMsgPrefix + " Re-using SSA Object for: " + $SSA.Name)
			$targetSSA = $SSA
		} else {
			try {
				Write-SRx VERBOSE $($moduleMsgPrefix + " Calling: Get-SPEnterpriseSearchServiceApplication " + $SSA) -ForegroundColor Cyan
				$targetSSA = Get-SPEnterpriseSearchServiceApplication $SSA
			} catch {
				Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Failed to load an SSA object named '" + $SSA + "'") 
				return
			}
		}
		
		#if we have multiple SSAs at this point, then it is an ambiguous state...
		if ($targetSSA.Count -gt 1) {
			#... so drop out of processing (e.g. we should only have a single SSA object for this PROCESS block)
			Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Invalid Command-line argument (Multiple SSAs) : Please specify a specific SSA as the target...")  
			return
		}
		
		#if we have multiple SSAs at this point, then this is a problem...
		if ($targetSSA -eq $null) {
			$nullSSAException = New-Object NullReferenceException("!!!" + $moduleMsgPrefix + " Missing Prerequisite: SharePoint SearchServiceApplication not found !!!")
			throw ($nullSSAException)
		}

		#we may still have a valid item, but the Search Admin DB may not be accessible, which is a problem...
		try {
            $targetSSA.Topologies | Out-Null  #this will fail if the DB is not accessible
        } catch {
            $errorMsg = $_.Exception.Message
   			if ($errorMsg.startsWith("An error occurred while enumerating through a collection: ")) {
                $errorMsg = $errorMsg.substring(58)
            }
            if ($errorMsg.endsWith("..")) { 
                $errorMsg = $errorMsg.Substring(0, $errorMsg.length-2) 
            }

            $nullSSAException = New-Object AccessViolationException("!!!" + $moduleMsgPrefix + " Search Admin Database:`n" + $errorMsg)
			throw ($nullSSAException)
        }
        
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded `$xSSA..." } ) | Out-Null }

		#== From here, we now have a specific [target] SSA that we can extend ====
		$RebuildSRxSSA = $RebuildSRxSSA -or (-not $targetSSA._hasSRx)
		#-- ensure the cache structures exist (and create if not)
		if ($RebuildSRxSSA) {
			Write-SRx VERBOSE $($moduleMsgPrefix + " Creating extended `$xSSA object for: " + $targetSSA.Name) -ForegroundColor DarkCyan
            if ($global:___SRxCache -isNot [hashtable]) { $global:___SRxCache = @{} } 
			#always [re]build this when [re]creating the $xSSA
			$global:___SRxCache[$targetSSA.Name] = @{}
		}
		#-- set the flags accordingly
		if ($RebuildSRxSSA -and $targetSSA._hasSRx) { $targetSSA._hasSRx = $false }
		if ($RebuildSRxSSA -and $targetSSA._hasSRxExtendedConfig) { $targetSSA._hasSRxExtendedConfig = $false }
		
		if ($targetSSA._hasSRx) {
			Write-SRx VERBOSE $($moduleMsgPrefix + " The `$xSSA has already been extended with core methods and properties.")
		} else {
			Write-SRx INFO $($moduleMsgPrefix + " Extending `$xSSA with core methods and properties")
			#==========================================================
			#== Append core custom methods to the $targetSSA object  ==
			#==========================================================
			#-- Methods: Only added if the $targetSSA is not yet SRx Enabled
			Write-SRx VERBOSE $($moduleMsgPrefix + " Appending core methods...")

			#== Create core ScriptMethod for getting the [Juno] System Manager status
			Write-SRx DEBUG $(" --> [Methods: System Manager]")
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetSearchStatusInfo -Value { 
				param ([bool]$isDetailed = $false, [bool]$includeJobStatus = $false)
				
				#avoid the cache if requesting the job status
				if (-not $includeJobStatus) { 
					if ($global:___SRxCache[$this.Name].ssaStatusInfo -ne $null) {
						$timeOfLastReport = $($global:___SRxCache[$this.Name].ssaStatusInfo.Keys)[0]
						$reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
						if ($reportAge -lt 20) {
							$ssaStatusInfo = $global:___SRxCache[$this.Name].ssaStatusInfo[$timeOfLastReport]
							Write-SRx DEBUG $(" --> [GetSearchStatusInfo] Using cache until " + $(Get-Date).AddSeconds(20 - $reportAge)) -ForegroundColor Cyan
							return $ssaStatusInfo
						}
					}
				}
							
				try {
					Write-SRx VERBOSE $("[`$xSSA._GetSearchStatusInfo()] Retrieving System Status Info")
					$ssaStatusInfo = $this | Get-SPEnterpriseSearchStatus -Detailed:$isDetailed -JobStatus:$includeJobStatus -ErrorAction Stop
					
					#only if this flag was previously set, then undo the flag now (b/c it was successful this time)
					if ($this._isDegradedSRxSSA -is [bool]) { $this._isDegradedSRxSSA = $false }
				} catch {
					Write-SRx WARNING $("~~~[`$xSSA._GetSearchStatusInfo] Attempt to retrieve Search Status Info from the System Manager failed") 
					Write-SRx ERROR ($_.Exception.Message) 
					Write-SRx VERBOSE ($_.Exception) 
					Write-SRx WARNING ("~~~ (Note: The previous error may be expected/temporary if the Search Admin currently failing over)") 
					Write-SRx
					$this | Set-SRxCustomProperty "_isDegradedSRxSSA" $true
					
					$ssaStatusInfo = 'unknown'
				}

                if (-not $includeJobStatus) {
					$global:___SRxCache[$this.Name].ssaStatusInfo = @{ $(Get-Date) = $ssaStatusInfo }
				}
				return $ssaStatusInfo
			}

			Write-SRx DEBUG $(" --> [Methods: EndPoints]")
			#-- Methods: Get EndPoint Info (Juno System Manager)
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetSystemManagerUris		-Value { return $($this.SystemManagerLocations) }
			#-- Methods: Get EndPoint Info (SQ&SS)
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetSQSSSearchSvcAppPool	-Value { return $($this.ApplicationPool) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetSQSSSearchSvcUris		-Value { return $($this.Endpoints | foreach {$_.ListenUris.AbsoluteUri}) }
			#-- Methods: Get EndPoint Info (Search Admin)
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetCrawlAdminWebSvcAppPool	-Value { return $($(Get-SPServiceApplication -Name $this.Id).ApplicationPool) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetCrawlAdminWebSvcUris		-Value { return $($(Get-SPServiceApplication -Name $this.Id).Endpoints | foreach {$_.ListenUris.AbsoluteUri}) }
			
			#-- Methods: Get Search Job States
			Write-SRx DEBUG $(" --> [Methods: Get Search Job States]")
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetJobForSPAdminSync		-Value { return $(Get-SPTimerJob job-application-server-admin-service)}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetJobStatusFromJuno		-Value { return $($this._GetSearchStatusInfo($false, $true) | Where {$_.Name -ne "Not available"}) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetJobDefinitions		-Value { 
				param ([string]$serverNameFilter = "")
				if ([string]::IsNullOrEmpty($serverNameFilter)) { return $($this._FarmSearchService.JobDefinitions) }	
				else { return $($this._FarmSearchService.JobDefinitions | Where {$_.Server.Name -ieq $serverNameFilter}) }
			}

			#--- Methods: Query resources ---
			Write-SRx DEBUG $(" --> [Methods: Query Resources]")
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetResultSources  -Value {
				$fdm = [Microsoft.Office.Server.Search.Administration.Query.FederationManager] $this 
				$sol = [Microsoft.Office.Server.Search.Administration.SearchObjectLevel]::ssa
				$soo = [Microsoft.Office.Server.Search.Administration.SearchObjectOwner] $sol
				return $fdm.listsources($soo,$false) 
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetLinguisticComponentsStatus  -Value {
				#== Has dependency on this System Manager (e.g. system status)
				$ssaStatusInfo = $this._GetSearchStatusInfo()
				if (-not $global:SRxEnv.h.isUnknownOrNull($ssaStatusInfo)) {			
					$(Get-SPEnterpriseSearchLinguisticComponentsStatus -SearchApplication $this -ErrorAction SilentlyContinue)
				}
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetQuerySpellingCorrection  -Value {
				#== Has dependency on this System Manager (e.g. system status)
				$ssaStatusInfo = $this._GetSearchStatusInfo()
				if (-not $global:SRxEnv.h.isUnknownOrNull($ssaStatusInfo)) {			
					$(Get-SPEnterpriseSearchQuerySpellingCorrection -SearchApplication $this -ErrorAction SilentlyContinue)
				}
			}

            #--- Methods: Databases 
            $targetSSA | Add-Member -Force ScriptMethod -Name _GetSearchDBs  -Value {
                return $($this.CrawlStores + $this.LinksStores + $this.SearchAdminDatabase + $this.AnalyticsReportingDatabases) |  
                    SELECT Name, Id, Type, FullName, DatabaseConnectionString, LegacyDatabaseConnectionString, FailoverServer
			}

            $targetSSA | Add-Member -Force ScriptMethod -Name _GetSearchDBsEx  -Value {
                return $($this.CrawlStores + $this.LinksStores + $this.SearchAdminDatabase + $this.AnalyticsReportingDatabases) 
			}

			#--- Methods: Get Component by type (optionally by component number)
			Write-SRx DEBUG $(" --> [Methods: Topology - Components by Type]")
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetAdminComponent -Value { 
				param($component = $null)
				if ([string]::IsNullOrEmpty($component)) { return $this._Components | WHERE { $_.Name -match "Admin"} }
				else { 
					$filterString = $( if($component.ToString().StartsWith("AdminComponent")) { $component } 
										else { $component = "AdminComponent" + $component } )
					return $this._Components | WHERE { $_.Name -ieq $component } 
				}
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetCrawlComponent -Value { 
				param($component = $null)
				if ([string]::IsNullOrEmpty($component)) { return $this._Components | WHERE { $_.Name -match "Crawl"} }
				else { 
					$filterString = $( if($component.ToString().StartsWith("CrawlComponent")) { $component } 
										else { $component = "CrawlComponent" + $component } )
					return $this._Components | WHERE { $_.Name -ieq $component } 
				}
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetContentProcessingComponent -Value { 
				param($component = $null)
				if ([string]::IsNullOrEmpty($component)) { return $this._Components | WHERE { $_.Name -match "ContentProcessing"} }
				else { 
					$filterString = $( if($component.ToString().StartsWith("ContentProcessingComponent")) { $component } 
										else { $component = "ContentProcessingComponent" + $component } )
					return $this._Components | WHERE { $_.Name -ieq $component } 
				}
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetAnalyticsProcessingComponent	-Value { 
				param($component = $null)
				if ([string]::IsNullOrEmpty($component)) { return $this._Components | WHERE { $_.Name -match "AnalyticsProcessing"} }
				else { 
					$filterString = $( if($component.ToString().StartsWith("AnalyticsProcessingComponent")) { $component } 
										else { $component = "AnalyticsProcessingComponent" + $component } )
					return $this._Components | WHERE { $_.Name -ieq $component } 
				}
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetQueryProcessingComponent	-Value { 
				param($component = $null)
				if ([string]::IsNullOrEmpty($component)) { return $this._Components | WHERE { $_.Name -match "QueryProcessing"} }
				else { 
					$filterString = $( if($component.ToString().StartsWith("QueryProcessingComponent")) { $component } 
										else { $component = "QueryProcessingComponent" + $component } )
					return $this._Components | WHERE { $_.Name -ieq $component } 
				}
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetIndexComponent	-Value { 
				param($component = $null, $indexPartition = $null)
				if ([string]::IsNullOrEmpty($component))  {
					if ($indexPartition -eq $null) { return $this._Components | WHERE { $_.Name -match "Index"} }
					else { return $this._Components | WHERE { ($_.Name -match "Index") -and ($_.IndexPartitionOrdinal -eq $indexPartition)} }		
				} else { 
					$filterString = $( if($component.ToString().StartsWith("IndexComponent")) { $component } 
										else { $component = "IndexComponent" + $component } )
					return $this._Components | WHERE { $_.Name -ieq $component }
				}
			}

			#-- Methods: Get Component (short-hand wrapper methods)
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetAdmin 	-Value { param($component = $null) $this._GetAdminComponent($component) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetCC		-Value { param($component = $null) $this._GetCrawlComponent($component) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetCPC		-Value { param($component = $null) $this._GetContentProcessingComponent($component) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetAPC		-Value { param($component = $null) $this._GetAnalyticsProcessingComponent($component) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetQPC		-Value { param($component = $null) $this._GetQueryProcessingComponent($component) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetIndexer	-Value { param($component = $null) $this._GetIndexComponent($component) }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetReplica	-Value { param($indexPartition  = $null) $this._GetIndexComponent($null, $indexPartition) }
			
			#-- Methods: Get Primary Components
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetPrimaryAdminComponent   -Value { return $this._GetAdminComponent() | WHERE {$_._isPrimaryAdmin -eq $true} }
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetPrimaryIndexReplica    -Value { 
				param($indexPartition = $null)
				if ([string]::IsNullOrEmpty($indexPartition)) { return $this._GetIndexComponent() | WHERE {$_._JunoDetails.Primary} }
				else { return $this._GetIndexComponent() | WHERE {($_._JunoDetails.Primary) -and ($_.IndexPartitionOrdinal -eq $indexPartition)} }
			}

            #-- Methods: Topology Report ---
            $targetSSA | Add-Member -Force ScriptMethod -Name _GetTopologyReportData -Value {
                $partitions = @()
                if ($this._Partitions -gt 0) { 
                    for ($i=0; $i -lt $this._Partitions; $i++) { 
                        $partitions += $( "IP" +  $i )
                    } 
                } else { #this is a problem 
                    $partitions += "Index"
                }

                $topoReport = New-Object PSObject -Property @{
                    "schema" = @("ServerName", "Admin", "APC", "CAC", "CAWS", "CC", "CPC") + $partitions + @("QPC", "SQSS", "WFE");
                    "partitions" = $this._Partitions;
                    "values" = $(New-Object System.Collections.ArrayList);
                }

                foreach ($SRxServer in $($this._Servers | Sort Name)) {
                    $r = New-Object PSObject -Property @{ 
                        "ServerName" = $SRxServer.Name
                        "Components" = @{};
                    }
                    $propertyBag = $( $SRxServer | gm  -MemberType NoteProperty | Where {$_.Name -like "has*"} ).Name
	                foreach ($propName in $propertyBag) {
                        switch ($propName) {
                            "hasIndexer" {
                                if($this._Partitions -gt 0) {
                                    for ($i=0; $i -lt $this._Partitions; $i++) { $r | Add-Member $("IP" + $i) 0 }  #add a property per partition
                                } else { $r | Add-Member "Index" $($SRxServer.$propName) } #this is a problem condition
                            }
                            "hasCrawlAdmin"   { 
                                $r | Add-Member "CAC" $($SRxServer.$propName) 
                                if ($SRxServer.$propName) {
                                    $c = $(New-Object PSObject -Property @{ 
                                                                    "ServerName" = $SRxServer.Name; 
                                                                    "Name" = $propName;
                                                                    "ComponentType" = "(Legacy) Crawl Admin Component";
                                                                    "ComponentNumber" = $this._CrawlAdmin.Name;
                                                                    "SRxState" = $( if ($this._CrawlAdmin.Initialized) { "Active" } else { "Uninitialized" } );
                                                                    "SRxMessage" = "";
                                                                })
                                    $r.Components["CAC"] = @( $c )
                                }
                            }
                            "hasCrawlAdminWS" { 
                                $r | Add-Member "CAWS" $($SRxServer.$propName) 
                                if ($SRxServer.$propName) {
                                    $c = $(New-Object PSObject -Property @{ 
                                                                    "ServerName" = $SRxServer.Name; 
                                                                    "Name" = "SearchAdmin.svc";
                                                                    "ComponentType" = "Search Administration Web Service";
                                                                    "ComponentNumber" = $this._SSAAdminWebServiceApp.Id.GUID;
                                                                    "SRxState" = "Provisioned";
                                                                    "SRxMessage" = $comp._SRxMessage;
                                                                })
                                    $r.Components["CAWS"] = @( $c )
                                }
                            }
                            "hasCrawler"      { 
                                $r | Add-Member "CC" $($SRxServer.$propName) 
                            }
                            "hasSQSS" { 
                                $r | Add-Member "SQSS" $($SRxServer.$propName) 
                                if ($SRxServer.$propName) {
                                    $c = $(New-Object PSObject -Property @{ 
                                                                    "ServerName" = $SRxServer.Name; 
                                                                    "Name" = "SearchService.svc";
                                                                    "ComponentType" = "Search Query & Site Settings Web Service";
                                                                    "ComponentNumber" = $this.Id.GUID;
                                                                    "SRxState" = "Provisioned";
                                                                    "SRxMessage" = $comp._SRxMessage;
                                                                })
                                    $r.Components["SQSS"] = @( $c )
                                }
                            }
                            "hasWFE" { 
                                $r | Add-Member "WFE" $($SRxServer.$propName) 
                                if ($SRxServer.$propName) {
                                    $c = $(New-Object PSObject -Property @{ 
                                                                    "ServerName" = $SRxServer.Name; 
                                                                    "Name" = "WebFrontEnd";
                                                                    "ComponentType" = "Microsoft SharePoint Foundation Web Application";
                                                                    "ComponentNumber" = "";
                                                                    "SRxState" = "Provisioned";
                                                                    "SRxMessage" = $comp._SRxMessage;
                                                                })
                                    $r.Components["WFE"] = @( $c )
                                }
                            }
                            default { $r | Add-Member $propName.Substring(3) $($SRxServer.$propName) }
                        }
                    }
                    $components = $this._Components | Where {$_.ServerName -eq $SRxServer.Name}
                    foreach ($comp in $components) {  
                        $shortName = $(
                            switch ($comp._ComponentType) {
                                "AdminComponent"               { "Admin" } 
                                "AnalyticsProcessingComponent" { "APC" } 
                                "CrawlComponent"               { "CC" } 
                                "ContentProcessingComponent"   { "CPC" } 
                                "IndexComponent"               { 
                                    if ($this._Partitions -gt 0) { $("IP" + $comp.IndexPartitionOrdinal) } else { "Index" }
                                } 
                                "QueryProcessingComponent"     { "QPC" } 
                            } 
                        ) 
                        $c = $(New-Object PSObject -Property @{ 
                                                        "ServerName" = $comp.ServerName; 
                                                        "Name" = $comp.Name;
                                                        "ComponentType" = $comp._ComponentType;
                                                        "ComponentNumber" = $comp._ComponentNumber;
                                                        "SRxState" = $comp._SRxState;
                                                        "SRxMessage" = $comp._SRxMessage;
                                                    })
                        if ($comp._JunoDetails.Primary -or $comp._isPrimaryAdmin) { $c | Add-Member "isPrimary" $true }

                        if ($r.Components[$shortName] -ne $null) { 
                            $r.Components[$shortName] += @( $r.Components[$shortName], $c )
                        } else {
                            $r.Components[$shortName] = @( $c ) 
                        } 

		                if ($comp._ComponentType -eq "IndexComponent") {
                            if($this._Partitions -gt 0) {
				                $r.$("IP" + $comp.IndexPartitionOrdinal) += 1
                            } else {
                                $r["Index"]++
                            }
                        }
                    }
                    $topoReport.values.Add($r) | Out-Null
                }
                return $topoReport
            }

            #--- Methods: Show Topology Report ---
		    $targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _ShowTopologyReport -Value {
			    param ([bool]$detailed = $false)
                
                $t = $this._GetTopologyReportData()
                $topoReport = $(New-Object System.Collections.ArrayList)
                
                $propertyBag = $( $t.values[0] | gm  -MemberType NoteProperty ).Name
                foreach ($row in $t.values) {
	                $report = New-Object PSObject
	                $propertyBag | foreach {
		                $propName = $_
		                $value = $( 
			                if ($row.Components.$propName.SRxState -ne $null) {
				                if ($row.Components.$propName.isPrimary) { "P" } else { $row.Components.$propName.SRxState }
			                } else {
				                $row.$propName
			                }
		                )
		                $statusLabel = $(switch ($value) {
							                'Active'		{ "@" } 
							                'Degraded'		{ "!" }
                                            'Failed'        { "x" }
							                'Unknown'		{ "?" }
                                            'Provisioned' 	{ "*" }
                                            'Uninitialized' { "-" }
							                1				{ "+" }
							                0				{ " " }
							                default	{ $value }
						                })
                        if ($propName.StartsWith("IP")) {
                            if ($t.partitions -gt 20) {
                                $propName = $propName.Substring(2)
                            } elseif ($t.partitions -gt 15) {
                                $propName = $propName.Substring(1)
                            } 
                        }
		                $report | Add-Member $propName $statusLabel
	                }
	                $topoReport.Add($report) | Out-Null
                }
                $schema = @("ServerName") + $( ($topoReport[0] | gm  -MemberType NoteProperty ).Name | Where {($_ -ne "Components") -and ($_ -ne "ServerName")} )

                if ($detailed) {
                    #not yet implemented...
                    $topoReport
                } else {
                    $topoReport | ft -AutoSize $schema
                    Write-SRx INFO "`n--[Legend]--------------------" -ForegroundColor Cyan
                    Write-SRx INFO $("   @ --> Active" )
                    Write-SRx INFO $("   ! --> Degraded" )
                    Write-SRx INFO $("   x --> Failed" )
                    Write-SRx INFO $("   ? --> Unknown" )
                    Write-SRx INFO $("   * --> Provisioned" )
                    Write-SRx INFO $("   - --> Uninitialized" )
                    Write-SRx INFO $("   + --> Exists" )
                }
            }

			#-- Methods: Topology Changes ---
			Write-SRx DEBUG $(" --> [Methods: Topology Changes]")
			$targetSSA | Add-Member -Force ScriptMethod -Name _CloneActiveTopo -Value {
				$this | New-SPEnterpriseSearchTopology –Clone –SearchTopology $this.ActiveTopology
			}
			$targetSSA | Add-Member -Force ScriptMethod -Name _RemoveInactiveTopologies -Value {
				$this.Topologies | where {$_.State -eq "Inactive" } | Remove-SPEnterpriseSearchTopology -confirm:$false
			}
			
			#--- Methods: [Diagnostic] Topology ---
			Write-SRx DEBUG $(" --> [Methods: Diagnostic Topology]")
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetComponentsWithMismatchedServerIds -Value {
				$mismatchedList = @() 
				foreach($component in $this._Components) {
					if ($(Get-SPFarm).Servers[$component.ServerName] -eq $null) {
						$mismatchedList += $component
					} else {   
						if ([string]$component.ServerId -ine [string]$(Get-SPFarm).Servers[$component.ServerName].Id) {
							$mismatchedList += $component
						}
					}
				}
				return $mismatchedList 
			}

			#--- Methods: Servers ---
			Write-SRx DEBUG $(" --> [Methods: Servers]")
			$targetSSA | Add-Member -Force ScriptMethod -Name _GetServer -Value {
				param($serverName = $ENV:Computername, $ExtendedProperties = $false)
				
                if ($serverName -is [bool]) {
				    #Assume this was invoked such as: $xSSA._GetServerEx($true)  
				    #...which should imply $serverName "*" and $true was intended for the $bypassCache flag
				    $ExtendedProperties = $serverName
				    $serverName = $ENV:Computername
			    }

                if ($serverName -eq "*") {
                    $srxServerList = $( $this._Servers | foreach { $this._GetServer($_, $ExtendedProperties) } )
                    return $srxServerList    
                }

				if ($serverName._hasSRx) { 
                    $srxServerObject = $serverName
                }  else {
                    $srxServerObject = $($this._Servers | Where {$_.Name -ieq $serverName})
                }
				
                if (-not $srxServerObject) {
					#it's not a Search server... but will get a report with System Specs if applicable (e.g. skip search reg keys)
					$srxServerObject = $(New-SRxSearchServerObject -Host $serverName -Specs:$ExtendedProperties)
				} elseif ($ExtendedProperties -and (-not $srxServerObject._hasSRxExtendedConfig)) {
					#we have Search server object, but it is not extended with System Specs and Search Reg Keys
					$newServerObject = $(New-SRxSearchServerObject -Host $srxServerObject -Extended:$ExtendedProperties)					
					
					#persist it to the applicable server object...
					$propertyBag = $newServerObject | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue
					foreach ($propName in $propertyBag.Name) {
						$srxServerObject | Set-SRxCustomProperty $propName $newServerObject.$propName
					}
				}
				return $srxServerObject
			}

            $targetSSA | Add-Member -Force ScriptMethod -Name _GetServerEx -Value {
				param($serverName = $ENV:Computername)
			    return $this._GetServer($serverName, $true) 
			}

			$targetSSA | Add-Member -Force ScriptMethod -Name _GetAvailableServers -Value {
				return $($this._Servers | Where {$_.canPing()})
			}

            $targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _QuerySystemMetrics -Value {
        	    param ($additionalFilter = "*", $minutesBack = 31, $endDateTimeinUTC = (Get-Date).ToUniversalTime())

	            #normalize incoming parameter (e.g. if user calls $s._QuerySystemMetrics( 360 ) , then assume a filter of "*" and set minutes back to 360 )
                if (($minutesBack -eq 31) -and ($additionalFilter -is [Int])) {
	                $minutesBack = $additionalFilter
	                $additionalFilter = "*"
	            }
	            if ($endDateTimeinUTC -is [string]) {
	                try {
		                $endDateTimeinUTC = (Get-Date $endDateTimeinUTC)
	                } catch {
		                $endDateTimeinUTC= (Get-Date).ToUniversalTime()
	                }
	            }
	            $queryTemplate = '.\search\usageDB\SearchSystemMetrics.sql'
	            $db = $($(Get-SPUsageService).Applications)[0].UsageDatabase
                $dbConnectionString = $db.DatabaseConnectionString
	            $queryVariables = @{
		            "**USAGEDB**" = $db.Name;
		            "**MINUTES**" = [string]$("-" + $minutesBack);
		            "**UTCENDTIME**" = "'" + $endDateTimeinUTC.ToString("yyyy-MM-dd HH:mm:ss") + "'";
		            "**FILTER**" = $(
			            if (@("","*",$null).contains($additionalFilter)) {
			                ""
			            } elseif (
			                #If the filter matches one of the known Crawl Servers, assume the user is trying to filter on that
			                ($this._Servers.Name.toUpper()).Contains(($additionalFilter).toUpper())
			            ) {
			                $(" AND MachineName = '" + $additionalFilter.toUpper() + "'")
			            } else {
			                $(" AND " + $additionalFilter)
			            }
		            );
	            }
	            return $( $queryTemplate | Invoke-SRxSQLQuery $dbConnectionString -v $queryVariables )
            }
			if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded core methods..." } ) | Out-Null }

			#================================================================
			#== Append/Set core custom properties to the $targetSSA object ==
			#================================================================	
			#-- Properties: Only created if the $targetSSA is not yet SRx Enabled
			Write-SRx VERBOSE $($moduleMsgPrefix + " Appending core properties...")

			#-- Properties: Administrative
			Write-SRx DEBUG $(" --> [Properties: Administrative]")
			$targetSSA | Set-SRxCustomProperty "_SystemManager" $(
                if ($targetSSA.SystemManagerLocations -ne $null) { (($targetSSA.SystemManagerLocations[0]).Segments[2]).replace("/","") } else { 'unknown' }
            )
			$targetSSA | Set-SRxCustomProperty "_ConstellationID" $(
                if ($targetSSA.SystemManagerLocations -ne $null) { (($targetSSA.SystemManagerLocations[0]).Segments[1]).replace("/","") } else { 'unknown' }
            )
			$targetSSA | Add-Member -Force AliasProperty -Name _SystemName -Value _ConstellationID
			
			$targetSSA | Set-SRxCustomProperty "_Partitions" $($targetSSA.ActiveTopology.GetComponents().IndexPartitionOrdinal | SELECT -Unique).count

			$targetSSA | Add-Member -Force AliasProperty -Name _LegacyAdmin	-Value AdminComponent
			$targetSSA | Add-Member -Force AliasProperty -Name _CrawlAdmin	-Value AdminComponent
			$targetSSA | Set-SRxCustomProperty "_SSAAdminWebServiceApp" $(Get-SPServiceApplication -Name $targetSSA.Id)

			#-- Properties: SharePoint Farm-level Services
			Write-SRx DEBUG $(" --> [Properties: SharePoint Farm-level Services]")
			$targetSSA | Set-SRxCustomProperty "_SSPJobControlService"	$($(Get-SPFarm).Services | where {$_.TypeName -like "*SSP Job*"})
			$targetSSA | Set-SRxCustomProperty "_FarmSearchService" 	$(Get-SPEnterpriseSearchService)

			#-- Properties: Crawl and Content Processing 
			Write-SRx DEBUG $(" --> [Properties: Crawl and Content Processing]")
			$targetSSA | Set-SRxCustomProperty "_CrawlAccount" 		$((New-Object Microsoft.Office.Server.Search.Administration.Content $targetSSA).DefaultGatheringAccount)
			$targetSSA | Set-SRxCustomProperty "_CrawlerWebProxy" 	$($targetSSA._FarmSearchService.WebProxy)
			$targetSSA | Set-SRxCustomProperty "_CEWSConfig" 		$($targetSSA | Get-SPEnterpriseSearchContentEnrichmentConfiguration -WarningAction SilentlyContinue)

			#-- Properties: Topology
			Write-SRx DEBUG $(" --> [Properties: Active Topology Components]")
			$targetSSA | Set-SRxCustomProperty "_Components" 		$($targetSSA.ActiveTopology.GetComponents())

			if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded core properties..." } ) | Out-Null }
		}
		
		#-- Properties: Only created if the $targetSSA is not yet SRx Enabled or if requesting extended configuration ($ExtendedConfig = $true)
		if ($ExtendedConfig -or $RebuildSRxSSA) {
			Write-SRx INFO $($moduleMsgPrefix + " Extending SRx Server objects...")
			$targetSSA | Set-SRxCustomProperty "_Servers" 	@() #collection of custom "server" objects (e.g. earch server object instantiated below)

			#-- [Server] Properties: Component Counts
			foreach ($serverName in $($targetSSA._Components.ServerName | SELECT -Unique)) {
				$searchServer = $(New-SRxSearchServerObject -Host $serverName -Extended:$ExtendedConfig)
				$searchServer | Set-SRxCustomProperty "Components"      $(New-Object System.Collections.ArrayList)
				$searchServer | Set-SRxCustomProperty "hasAdmin"        $($targetSSA._Components | Where {($_.ServerName -eq $serverName) -and ($_.Name -match "Admin")} | Measure).Count
                $searchServer | Set-SRxCustomProperty "hasCrawlAdmin"   $( if ($targetSSA._CrawlAdmin.ServerName -eq $serverName) {1} else {0} )
                $searchServer | Set-SRxCustomProperty "hasCrawlAdminWS" $( if ($searchServer.GetSPServiceInstances("Search Administration Web Service").Status -eq "Disabled") {0} else {1} )
				$searchServer | Set-SRxCustomProperty "hasCrawler"           $($targetSSA._Components | Where {($_.ServerName -eq $serverName) -and ($_.Name -match "Crawl")} | Measure).Count
				$searchServer | Set-SRxCustomProperty "hasCPC"          $($targetSSA._Components | Where {($_.ServerName -eq $serverName) -and ($_.Name -match "Content")} | Measure).Count
				$searchServer | Set-SRxCustomProperty "hasAPC"          $($targetSSA._Components | Where {($_.ServerName -eq $serverName) -and ($_.Name -match "Analytics")} | Measure).Count
				$searchServer | Set-SRxCustomProperty "hasIndexer"      $($targetSSA._Components | Where {($_.ServerName -eq $serverName) -and ($_.Name -match "Index")} | Measure).Count
				$searchServer | Set-SRxCustomProperty "hasQPC"          $($targetSSA._Components | Where {($_.ServerName -eq $serverName) -and ($_.Name -match "Query")} | Measure).Count
                $searchServer | Set-SRxCustomProperty "hasSQSS"         $( if ($searchServer.GetSPServiceInstances("Search Query and Site Settings Service").Status -eq "Disabled") {0} else {1} )
                $searchServer | Set-SRxCustomProperty "hasWFE"          $( if ($searchServer.GetSPServiceInstances("Microsoft SharePoint Foundation Web Application").Status -eq "Disabled") {0} else {1} )

				if ($searchServer._ApplicationsSearchPath -ne $null) {
					$searchServer | Set-SRxCustomProperty "_ConstellationPath" -Value $( [System.IO.Path]::Combine($searchServer._ApplicationsSearchPath, $("Nodes\" + $targetSSA._ConstellationID + "\")) )
				}
				$targetSSA._Servers += $searchServer
				if ($TrackDebugTimings -and $ExtendedConfig) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded Extended SRx Server for $serverName..." } ) | Out-Null }
			}
			if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded SRx Server objects..." } ) | Out-Null }
		}
		
		#========================================
		#== Validate the current System Status ==
		#========================================		
		Write-SRx VERBOSE $($moduleMsgPrefix + " Calling `$xSSA._GetSearchStatusInfo()")
		$ssaStatusInfo = $targetSSA._GetSearchStatusInfo()
		if (($global:SRxEnv.h.isUnknownOrNull($ssaStatusInfo)) -and (-not $targetSSA.__AdminDBAccessVerified)) {
			Write-SRx INFO ($moduleMsgPrefix + " On System Manager connection failure, attempting to verify access to the Search Admin DB...")
			try { 
				$hasAccess = $targetSSA.SearchAdminDatabase | Get-SPShellAdmin -ErrorAction Stop
				Write-SRx INFO ($moduleMsgPrefix + " ...successfully connected to " + $targetSSA.SearchAdminDatabase.Name)
                $targetSSA | Set-SRxCustomProperty "__AdminDBAccessVerified" $true
			} catch { 
				Write-SRx ERROR ($_.Exception.Message)
				Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Insufficient Privileges on " + $targetSSA.SearchAdminDatabase.Name)
				Write-SRx WARNING ("~~~ Using `"Add-SPShellAdmin`", have an Administrator add " + $global:SRxEnv.CurrentUser.Name + " to the")
				Write-SRx WARNING ("~~~ database role `"SharePoint_Shell_Access`" for " + $targetSSA.SearchAdminDatabase.Name)
				Write-SRx INFO ("               PS> `$(Get-SPDatabase " + $targetSSA.SearchAdminDatabase.Id + ") | Add-SPShellAdmin " + $global:SRxEnv.CurrentUser.Name) DarkCyan 
				if ($global:SRxEnv.Exists -and (-not $global:SRxEnv.isBuiltinAdmin)) {
					Write-SRx INFO
					Write-SRx WARNING ("~~~ Also, because PowerShell is not currently running with elevated permissions, you can alternatively try")
					Write-SRx WARNING ("~~~ launching PowerShell.exe using the `"Run as Administrator`" option to see if the previous error persists")
				}
			}
			Write-SRx INFO
			Write-SRx WARNING ("~~~[Get-SRxSSA] ...continuing in degraded mode (`$xSSA._isDegradedSRxSSA = `$true)")
			$targetSSA | Set-SRxCustomProperty "_isDegradedSRxSSA" $true
			Write-SRx INFO
		} else {
			#only if this flag was previously set, then undo the flag now (b/c it was successful this time)
			if ($targetSSA._isDegradedSRxSSA -is [bool]) { $targetSSA._isDegradedSRxSSA = $false }
		}
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Called `$xSSA._GetSearchStatusInfo()..." } ) | Out-Null }
		
		#===================================================
		#== Append/set Component level properties/methods ==
		#===================================================
		if ($ExtendedConfig -or $RebuildSRxSSA) {
			Write-SRx INFO $($moduleMsgPrefix + " Extending SRx Components...")
			
			foreach ($ssaComp in $targetSSA._Components) {
				Write-SRx VERBOSE $("---[" + $ssaComp.Name + " (" + $ssaComp.ServerName + ")] Configuring " + $(if($ExtendedConfig) {"extended "}) + "SRx Component...")
				$srxServerObject = $targetSSA._GetServer($ssaComp.ServerName, $ExtendedConfig)  #$($targetSSA._Servers | Where {$_.Name -ieq $ssaComp.ServerName})				
				Write-SRx DEBUG $(" --> [Retrieved SRxServer]")
				
				if ($RebuildSRxSSA) {
					#-- Properties: Common to all components regardless of type or state
					$ssaComp | Set-SRxCustomProperty "_ParentSSAName"	$targetSSA.Name
					$ssaComp | Set-SRxCustomProperty "_LegacyAdminName"	$targetSSA._LegacyAdmin.Name
                    
                    #-- Properties: Useful for generalizing the "type" of components (e.g. "AdminComponent", "CrawlComponent", etc) 
                    $splitLocation = $ssaComp.Name.indexOf("Component") + 9
                    $ssaComp | Set-SRxCustomProperty "_ComponentType"	$ssaComp.Name.Substring(0,$splitLocation)
                    $ssaComp | Set-SRxCustomProperty "_ComponentNumber"	$ssaComp.Name.Substring($splitLocation)
				}
				
				if ($srxServerObject) {
					@("InstallationPath","NativePath","RuntimeDirectory","DataDirectory","DefaultApplicationsPath","TempPath","ApplicationsSearchPath") | foreach {
						if ($srxServerObject.$_ -ne $null) {
							$ssaComp | Set-SRxCustomProperty $("_" + $_)	$srxServerObject.$_
						}
					}
				}
							
				#-- Implment component specific properties/methods
				if ($ssaComp.Name -match "Crawl") {

					#=========================================
					#== Properties/Methods: Crawl Component ==
					#=========================================
					if ($RebuildSRxSSA) {
						#-- Methods: Only added if the $targetSSA is not yet SRx Enabled
						$ssaComp | Add-Member -Force ScriptMethod -Name _GetProcess -Value {
							$osearch = Get-Process mssdmn*,mssearch* -ComputerName $this.ServerName -ErrorAction SilentlyContinue
							foreach ($proc in $osearch ) {
								$proc | Set-SRxCustomProperty "_Component" $this.Name 
							}
							return $osearch 
						}
						
						$ssaComp | Add-Member -Force ScriptMethod -Name _GetGathererShare -Value {
							Write-SRx INFO ("~~~[`$(" + $this.Name + ")._GetGathererShare] This method has not yet been implemented... ")
						}
					
						#-- Properties: Only created if explicitly requested to rebuild or the $targetSSA is not yet SRx Enabled
						$ssaComp | Set-SRxCustomProperty "_UserAgent" $([string]($(Get-SPEnterpriseSearchService).InternetIdentity))
					
						$ssaComp | Set-SRxCustomProperty "_JunoState" "" #intentionally empty...
						#Note: The state of a crawl component is not controlled/managed by Juno,
						#      however, the state of a crawl component is sync'ed with Juno (via
						#      the Application Server Administration Services timer job running
						#      on the primary Admin Component)
						#       - thus, appending this property gives us a uniform look across components
						
						#A script property that overloads the JunoState and the LegacyState into common property
						$ssaComp | Add-Member -Force ScriptProperty -Name _SRxState		-Value {
							if ($this._LegacyState -eq "Ready") { "Active" } 
                            elseif ($global:SRxEnv.h.isUnknownOrNull($this._LegacyState)) { 'unknown' } 
                            else  { "Degraded" }
                            #else  { $this._LegacyState }
						}
						
						#A script property that overloads the JunoMessage and the LegacyDesiredState into common property
						$ssaComp | Add-Member -Force ScriptProperty -Name _SRxMessage	-Value {
							if ($this._SRxState -ne "Active") {
                                $("State: " + $this._LegacyState + "; Desired State: " + $this._LegacyDesiredState)
                            }
						}
					}

					#-- Properties: Created/set each time we run Get-SRxSSA
					$ssaComp | Set-SRxCustomProperty "_LegacyState"			$(($targetSSA.CrawlComponents | WHERE {$_.ServerName -ieq $ssaComp.ServerName }).State)
					$ssaComp | Set-SRxCustomProperty "_LegacyDesiredState"	$(($targetSSA.CrawlComponents | WHERE {$_.ServerName -ieq $ssaComp.ServerName }).DesiredState)
									
					#-- Properties: Pulled on each server and copied to this Crawl Component
					if ($ExtendedConfig -and $srxServerObject -and ($srxServerObject.spsLegacyObjKeys.Count -gt 0)) {
						#Just being paranoid about the Legacy Admin being null (or being in a problem state)...
						if ($ssaComp._LegacyAdminName -eq $null) {
							$ssaComp._LegacyAdminName = $($targetSSA.CrawlComponents | WHERE {$_.Name -ieq $ssaComp.Name }).Name.substring(0,36)
							if ($ssaComp._LegacyAdminName -eq $null) {
								$ssaComp._LegacyAdminName = 'unknown'
							} 
						}
					
						$legacyObjects = $srxServerObject.spsLegacyObjKeys[$ssaComp._LegacyAdminName]
						if (($legacyObjects.Count -gt 0) -and $legacyObjects[$ssaComp.Name]) {
							$legacyObjects[$ssaComp.Name] | foreach {
								$ssaComp | Set-SRxCustomProperty $("_" + $_)	$srxServerObject.$_
							}
						}	
					}

				} else {

					#====================================================================
					#== Properties/Methods: Common to all Juno [noderunner] Components ==
					#====================================================================
					#-- (e.g. everything but the Crawl Component)
					if ($RebuildSRxSSA) {
					
						#-- Methods: Only added if the $targetSSA is not yet SRx Enabled			
						$ssaComp | Add-Member -Force ScriptMethod -Name _GetSearchStatusInfo -Value { 
							param ([bool]$isDetailed = $false)

							if ($global:___SRxCache[$this._ParentSSAName].ssaStatusInfo -ne $null) {
								$timeOfLastReport = $($global:___SRxCache[$this._ParentSSAName].ssaStatusInfo.Keys)[0]
								$reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
								if ($reportAge -lt 20) {
									$ssaStatusInfo = $global:___SRxCache[$this._ParentSSAName].ssaStatusInfo[$timeOfLastReport]
									return $ssaStatusInfo
								}
							}
										
							try { 
								$ssaStatusInfo = Get-SPEnterpriseSearchStatus -SearchApplication $this._ParentSSAName -Detailed:$isDetailed -ErrorAction Stop
							} catch {
								Write-SRx ERROR ($_.Exception.Message)
								Write-SRx WARNING $("~~~[(" + $this.Name +")._GetSearchStatusInfo] Attempt to retrieve Search Status Info from the System Manager failed")
								Write-SRx VERBOSE ($_.Exception)
								$ssaStatusInfo = 'unknown'
							}
                            $global:___SRxCache[$this._ParentSSAName].ssaStatusInfo = @{ $(Get-Date) = $ssaStatusInfo }
							return $ssaStatusInfo
						}
						
						$ssaComp | Add-Member -Force ScriptMethod -Name _GetHealthReport -Value	{
							param ([bool]$bypassCache = $false)

							Write-SRx DEBUG $(" --> [`$(" + $this.Name + ")._GetHealthReport] Starting...")
							if ($global:___SRxCache[$this._ParentSSAName][$this.Name] -isNot [hashtable]) { 
								$global:___SRxCache[$this._ParentSSAName][$this.Name] = @{} 
							}
								
							if ($this._JunoState -ne 'unknown') {
								Write-SRx DEBUG $(" --> [`$(" + $this.Name + ")._GetHealthReport] Component is not 'unknown'; continuing...")
								if ((-not $bypassCache) -and ($global:___SRxCache[$this._ParentSSAName][$this.Name].HealthReport -ne $null)) {
									Write-SRx DEBUG $(" --> [`$(" + $this.Name + ")._GetHealthReport] Found HealthReport in cache...")
									
									$timeOfLastReport = $($global:___SRxCache[$this._ParentSSAName][$this.Name].HealthReport.Keys)[0]
									$reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
									if ($reportAge -lt 20) {
										Write-SRx DEBUG $(" --> [`$(" + $this.Name + ")._GetHealthReport] Using cache until " + $(Get-Date).AddSeconds(20 - $reportAge)) -ForegroundColor Cyan
										return $( $global:___SRxCache[$this._ParentSSAName][$this.Name].HealthReport[$timeOfLastReport] )
									}
								}
									
								try { 
									Write-SRx DEBUG $(" --> [`$(" + $this.Name + ")._GetHealthReport] Building new report...")
									$healthReport = $(Get-SPEnterpriseSearchStatus -SearchApplication $this._ParentSSAName -HealthReport -Component $this.Name)
									$global:___SRxCache[$this._ParentSSAName][$this.Name].HealthReport = @{ $(Get-Date) = $healthReport }
									return $healthReport
								} catch {
									Write-SRx DEBUG ("~~~[`$(" + $this.Name + ")._GetHealthReport] Unable to load Search Status Info")
									throw 
								}  
							} else {
								Write-SRx DEBUG ("~~~[`$(" + $this.Name + ")._GetHealthReport] This component has no report because it is currently in an `"Unknown`" state") -ForegroundColor Yellow
							}
						}
						
						$ssaComp | Add-Member -Force ScriptMethod -Name _GetNodeRunnerProcess -Value	{ 
							$noderunnerProcess = $null
							foreach ($noderunner in (Get-Process noderunner* -ComputerName $this.ServerName -ErrorAction SilentlyContinue)) {
								$noderunner | Set-SRxCustomProperty "_ProcessCommandLine" $(
									(Get-WmiObject Win32_Process -ComputerName $this.ServerName | where {$_.processId -eq $noderunner.id}).CommandLine
								)
								if ($noderunner._ProcessCommandLine -match $this.Name) { 
									$noderunner | Set-SRxCustomProperty "_Component" $this.Name 
									$noderunnerProcess = $noderunner 
								}
							}
							return $noderunnerProcess
						}
						$ssaComp | Add-Member -Force ScriptMethod -Name _GetProcess -Value { return $this._GetNodeRunnerProcess() }
					
						#-- Properties: Only created if the $targetSSA is not yet SRx Enabled
						#ScriptProperty properties are updated EVERY time you view them
						$ssaComp | Add-Member -Force ScriptProperty -Name _JunoState	-Value {
							$cStatusInfo = $this._GetSearchStatusInfo() | Where {$_.Name -ieq $this.Name }
							if (-not $global:SRxEnv.h.isUnknownOrNull($cStatusInfo)) { $cStatusInfo.State } else { $null }
						}
						$ssaComp | Add-Member -Force ScriptProperty -Name _JunoLevel	-Value {
							$cStatusInfo = $this._GetSearchStatusInfo() | Where {$_.Name -ieq $this.Name }
							if (-not $global:SRxEnv.h.isUnknownOrNull($cStatusInfo)) { $cStatusInfo.Level } else { $null }
						}
						$ssaComp | Add-Member -Force ScriptProperty -Name _JunoMessage	-Value {
							$cStatusInfo = $this._GetSearchStatusInfo() | Where {$_.Name -ieq $this.Name }
							if (-not $global:SRxEnv.h.isUnknownOrNull($cStatusInfo)) { $cStatusInfo.Message } else { $null }
						}
						$ssaComp | Add-Member -Force ScriptProperty -Name _JunoDetails	-Value {
							$cStatusInfo = $this._GetSearchStatusInfo() | Where {$_.Name -ieq $this.Name }
							if ($global:SRxEnv.h.isUnknownOrNull($cStatusInfo)) { $null }
							else {
								$details = New-Object PSObject
								$cStatusInfo.Details | foreach {
									if ($_.Value -ieq "True") { $rowValue = $true } else { $rowValue = $_.Value }
									if ($_.Value -ieq "False") { $rowValue = $false } else { $rowValue = $_.Value }
									#if we find duplicate properties, convert this to an ArrayList
									if ( $( $details | Get-Member -Name $_.Key) -ne $null ) {
										if ($details.($_.Key) -isNot [System.Collections.ArrayList]) {
											$originalValue = $details.($_.Key)
											$details.($_.Key) = $(New-Object System.Collections.ArrayList)
											$details.($_.Key).Add($originalValue) | Out-Null
										}
										$details.($_.Key).Add($rowValue) | Out-Null
									} else {
										$details | Add-Member $_.Key $rowValue
									}
								}
								$details
							}
						}
						#A property that overloads the JunoState and the LegacyState
						$ssaComp | Add-Member -Force ScriptProperty -Name _SRxState		-Value {
							if ($global:SRxEnv.h.isUnknownOrNull($this._JunoState)) { 'unknown' } else { $this._JunoState }
						}
						
						#A script property that overloads the JunoMessage and the LegacyDesiredState into common property
						$ssaComp | Add-Member -Force ScriptProperty -Name _SRxMessage	-Value {
                            if ((-not [string]::isNullOrEmpty($this._CellMessage)) -and ($this._CellMessage.Contains("ary index cell)"))) { 
                                $cellMsg = $this._CellMessage.Substring($this._CellMessage.IndexOf("ary index cell)") + 16) 
                            }
                            
                            if ($this._JunoMessage -and $cellMsg) {
                                @( $this._JunoMessage , $cellMsg )
                            } else { $this._JunoMessage + $cellMsg } 
						}
					}
                
					#-- Properties: Common to components, but has dependency on the System Manager
					if ((-not $targetSSA._isDegradedSRxSSA) -and ($RebuildSRxSSA -or (-not $ssaComp._hasSRx))) {

						#=============================================================
						#== Component specific properties/methods (Juno components) ==
						#=============================================================

						#-- Properties/Methods: Component Specific 
						switch -wildcard ($ssaComp.Name) {
							"Admin*" {
								$ssaComp | Add-Member -Force ScriptProperty -Name _isPrimaryAdmin -Value {
									if (-not $global:SRxEnv.h.isUnknownOrNull($this._JunoState)) {
										$isPrimary = $(Get-SPEnterpriseSearchStatus -SearchApplication $this._ParentSSAName -Primary -Component $this.Name -ErrorAction SilentlyContinue)
										if (-not $global:SRxEnv.h.isUnknownOrNull($isPrimary)) { $isPrimary } else { $null }
									} else { $false }
								}
							}
							"Query*"       { }  #no specific alterations needed for the QPC
							"Analytics*"   {
								$ssaComp | Add-Member -Force ScriptMethod -Name _GetAnalyticsShare -Value {
									Write-SRx INFO ("~~~[`$(" + $this.Name + ")._GetAnalyticsShare] This method has not yet been implemented... ")
								}
							}
							"ContentProcessing*" { 
								if (-not $targetSSA.CloudIndex) {
                                    #These ScriptProperty properties are updated EVERY time you view them
								    $ssaComp | Add-Member -Force ScriptProperty -Name _RejectCount		-Value {
									    $stat = $this._GetHealthReport() | where {$_.Name.StartsWith("reject_count")}
									    if ($stat -eq $null) { 0 } else { [long]$stat.message }
								    }
								    $ssaComp | Add-Member -Force ScriptProperty -Name _SuccessfulGroups		-Value {
									    $stat = $this._GetHealthReport() | where {$_.Name.StartsWith("successful_groups")}
									    if ($stat -eq $null) { 0 } else { [long]$stat.message }
								    }
								    $ssaComp | Add-Member -Force ScriptProperty -Name _FailedGroups		-Value {
									    $stat = $this._GetHealthReport() | where {$_.Name.StartsWith("failed_groups")}
									    if ($stat -eq $null) { 0 } else { [long]$stat.message }
								    }
								    $ssaComp | Add-Member -Force ScriptProperty -Name _SubmittedGroups		-Value {
									    $stat = $this._GetHealthReport() | where {$_.Name.StartsWith("submitted_groups")}
									    if ($stat -eq $null) { 0 } else { [long]$stat.message }
								    }
								    $ssaComp | Add-Member -Force ScriptProperty -Name _PendingCallbacks		-Value {
									    $stat = $this._GetHealthReport() | where {$_.Name.StartsWith("pending_callbacks")}
									    if ($stat -eq $null) { 0 } else { [long]$stat.message }
								    }
								    $ssaComp | Add-Member -Force ScriptProperty -Name _TimeSinceLastCallback		-Value {
									    $stat = $this._GetHealthReport() | where {$_.Name.StartsWith("time_since_last_callback")}
									    if ($stat -eq $null) { 0 } else { [long]$stat.message }
								    }
                                }
							}                                        
							"Index*"       { 
								$ssaComp | Add-Member -Force AliasProperty -Name _Partition -Value IndexPartitionOrdinal
                                $ssaComp | Add-Member -Force ScriptProperty -Name _CellNumber			-Value { 
									if ($global:SRxEnv.h.isUnknownOrNull($this._JunoState)) {
										$cellNumber = "?"			
									} else {
										$cellNumber = $((($this._GetHealthReport() | Where {$_.Name.StartsWith("plugin: initialized[SP")}).Name -split '\.')[2])	
									}
									if ([String]::IsNullOrEmpty($cellNumber)) {"?"} else {$cellNumber}
								}

								if ((-not $targetSSA.CloudIndex) -and ($ssaStatusInfo -ne $null) -and ($ssaComp._JunoState -ne 'unknown')) {
									
                                    #--- Properties: Index Cell Info
									$ssaComp | Add-Member -Force ScriptProperty -Name _CellName			-Value { 
										("[I.{0}.{1}]" -f $this._CellNumber,$this._Partition)
									}
                                    $ssaComp | Add-Member -Force ScriptProperty -Name _Cell	-Value {
							            $cStatusInfo = $this._GetSearchStatusInfo() | Where {($_.Name -Match "Cell") -and ($_.Name -Match $this.Name)}
							            if ($global:SRxEnv.h.isUnknownOrNull($cStatusInfo)) { $null } else { $cStatusInfo.Name } 
                                    }
                                    $ssaComp | Add-Member -Force ScriptProperty -Name _CellMessage	-Value {
							            $cStatusInfo = $this._GetSearchStatusInfo() | Where {($_.Name -Match "Cell") -and ($_.Name -Match $this.Name)}
                                        if ($global:SRxEnv.h.isUnknownOrNull($cStatusInfo)) { $null } else { $cStatusInfo.Message }
						            }
                                                            
                                    #--- Properties: Index Cell Stats
									$ssaComp | Add-Member -Force ScriptProperty -Name _Generation		-Value {
										$stat = $this._GetHealthReport() | where {$_.Name.StartsWith("plugin: newest generation id")}
										if ($stat -eq $null) { 0 } else { [long]$stat.message }
									}
									$ssaComp | Add-Member -Force ScriptProperty -Name _CheckpointSize	-Value { 
										$stat = $this._GetHealthReport() | where {$_.Name.StartsWith("plugin: size of newest checkpoint")}
							            if ($stat -eq $null) { 0 } 
                                        elseif ($global:SRxEnv.Product -eq "SP2016") { [long]($stat.message) * 1MB }
                                        else { [long]($stat.message) }
									}
                                    $ssaComp | Add-Member -Force ScriptProperty -Name _TotalDocs			-Value { 
										$stat = $($this._GetHealthReport() | where {$_.Name.StartsWith("part: number of documents including duplicate")} | % {[long]$_.message} | measure-object -sum).sum
										if ($stat -eq $null) { 0 } else { [long]$stat }
									}
									$ssaComp | Add-Member -Force ScriptProperty -Name _ActiveDocs			-Value { 
										$stat = $this._GetHealthReport() | where {$_.Name.StartsWith("plugin: number of documents")}
										if ($stat -eq $null) { 0 } else { [long]$stat.message }
									}
									$ssaComp | Add-Member -Force ScriptProperty -Name _AvgDocSize			-Value { 
										$totalDocs = $this._TotalDocs
                                        if ($totalDocs -gt 0) { [math]::ceiling($this._CheckpointSize / $totalDocs) } else { 0 }
									}
									$ssaComp | Add-Member -Force ScriptProperty -Name _Initialized		-Value {
										$stat = $this._GetHealthReport() | where {$_.Name.StartsWith("plugin: initialized")}
										if ($stat -eq $null) { $false } else { $($stat.message.ToLower() -eq 'true') }
									}
									$ssaComp | Add-Member -Force ScriptProperty -Name _MasterMerging	-Value { 
										$stat = $this._GetHealthReport() | where {$_.Name.StartsWith("plugin: master merge running")}
										if ($stat -eq $null) { $false } else { $($stat.message.ToLower() -eq 'true') }
									}
									$ssaComp | Add-Member -Force ScriptProperty -Name _Unrecoverable	-Value { 
										$stat = $this._GetHealthReport() | where {$_.Name.StartsWith("plugin: unrecoverable error detected")}
										if ($stat -eq $null) { $false } else { $($stat.message.ToLower() -eq 'true') }
									}
									$ssaComp | Add-Member -Force ScriptProperty -Name _Shutdown			-Value { 
										$stat = $this._GetHealthReport() | where {$_.Name.StartsWith("plugin: shutting down")}
										if ($stat -eq $null) { $false } else { $($stat.message.ToLower() -eq 'true') }
									}
								}
							} 
						}
						$ssaComp | Set-SRxCustomProperty "_hasSRx" $true
					}
				}
				
				Write-SRx DEBUG $(" --> [Extended Component]")
				if (-not ($($targetSSA._Servers | Where {$_.Name -ieq $ssaComp.ServerName}).Components -contains $ssaComp.Name)) {
					$($targetSSA._Servers | Where {$_.Name -ieq $ssaComp.ServerName}).Components.Add($ssaComp.Name) | Out-Null
				}
				Write-SRx DEBUG $(" --> [Extended Component with SRxServer reference]")

			}
			Write-SRx VERBOSE "Ending $moduleMsgPrefix"
			if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Extended components..." } ) | Out-Null }
		
            #-- Properties: Topology Scale Category (has dependency on the Indexer's property $idx._JunoDetails.Primary)	
            Write-SRx DEBUG $(" --> [Properties: Topology Scale Category]")
            $targetSSA | Set-SRxCustomProperty "_TopologyScale" $(
                #$primaryReplicas = $($targetSSA._GetPrimaryIndexReplica())
                $partitionCount = $targetSSA._Partitions  #$primaryReplicas.count
 
                if (($partitionCount -eq $null) -or ($partitionCount -eq 0)) {  $scale = 0    #something is wrong if 0 
                } elseif ($partitionCount -eq 1) {  $scale = 1      # 1 =  1 partition,   10M [SP2013] /  20M [SP2016]
                } elseif ($partitionCount -le 4) {  $scale = 4      # 4 =  4 partitions,  40M [SP2013] /  80M [SP2016]            		
                } elseif ($partitionCount -le 10) { $scale =  10    #10 = 10 partitions, 100M [SP2013] / 200M [SP2016]
                } else { $scale = 25 }                              #25 = 25 partitions, 250M [SP2013] / 500M [SP2016]
                $scale #the return value
            )
            if (-not $targetSSA.CloudIndex) {
                $targetSSA | Set-SRxCustomProperty "_ActiveDocsSum" $( ($targetSSA._GetPrimaryIndexReplica()._ActiveDocs | Measure -Sum).Sum )
            }
        }

		#== Then finally, add this $targetSSA to the $results array ===
		$targetSSA | Set-SRxCustomProperty "_hasSRx" $true
		if ($ExtendedConfig -or $targetSSA._hasSRxExtendedConfig) {
			$targetSSA | Set-SRxCustomProperty "_hasSRxExtendedConfig" $true
		} else {
			$targetSSA | Set-SRxCustomProperty "_hasSRxExtendedConfig" $false
		}
		
		$results.add($targetSSA) | Out-Null
	}

	END {
		Write-SRx VERBOSE $($moduleMsgPrefix +" Ending")

		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Ending $moduleMsgPrefix" } ) | Out-Null }
		if ($results.Count -gt 1) {
			Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Results include multiple SSA objects...")
			return $results
		} else {
			return $results[0]
		}
	}
}

######################################
Export-ModuleMember Get-SRxSSA

# SIG # Begin signature block
# MIIktQYJKoZIhvcNAQcCoIIkpjCCJKICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDEoikR7Q8f2PPU
# cqm831WE8O57BWSOYKtEYhR7tZhXp6CCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
# pFcaX8o+AAAAAACOMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMTYxMTE3MjIwOTIxWhcNMTgwMjE3MjIwOTIxWjCBgzEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEeMBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEA0IfUQit+ndnGetSiw+MVktJTnZUXyVI2+lS/qxCv
# 6cnnzCZTw8Jzv23WAOUA3OlqZzQw9hYXtAGllXyLuaQs5os7efYjDHmP81LfQAEc
# wsYDnetZz3Pp2HE5m/DOJVkt0slbCu9+1jIOXXQSBOyeBFOmawJn+E1Zi3fgKyHg
# 78CkRRLPA3sDxjnD1CLcVVx3Qv+csuVVZ2i6LXZqf2ZTR9VHCsw43o17lxl9gtAm
# +KWO5aHwXmQQ5PnrJ8by4AjQDfJnwNjyL/uJ2hX5rg8+AJcH0Qs+cNR3q3J4QZgH
# uBfMorFf7L3zUGej15Tw0otVj1OmlZPmsmbPyTdo5GPHzwIDAQABo4IBgDCCAXww
# HwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0OBBYEFKvI1u2y
# FdKqjvHM7Ww490VK0Iq7MFIGA1UdEQRLMEmkRzBFMQ0wCwYDVQQLEwRNT1BSMTQw
# MgYDVQQFEysyMzAwMTIrYjA1MGM2ZTctNzY0MS00NDFmLWJjNGEtNDM0ODFlNDE1
# ZDA4MB8GA1UdIwQYMBaAFEhuZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0Nv
# ZFNpZ1BDQTIwMTFfMjAxMS0wNy0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsG
# AQUFBzAChkVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y0NvZFNpZ1BDQTIwMTFfMjAxMS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkq
# hkiG9w0BAQsFAAOCAgEARIkCrGlT88S2u9SMYFPnymyoSWlmvqWaQZk62J3SVwJR
# avq/m5bbpiZ9CVbo3O0ldXqlR1KoHksWU/PuD5rDBJUpwYKEpFYx/KCKkZW1v1rO
# qQEfZEah5srx13R7v5IIUV58MwJeUTub5dguXwJMCZwaQ9px7eTZ56LadCwXreUM
# tRj1VAnUvhxzzSB7pPrI29jbOq76kMWjvZVlrkYtVylY1pLwbNpj8Y8zon44dl7d
# 8zXtrJo7YoHQThl8SHywC484zC281TllqZXBA+KSybmr0lcKqtxSCy5WJ6PimJdX
# jrypWW4kko6C4glzgtk1g8yff9EEjoi44pqDWLDUmuYx+pRHjn2m4k5589jTajMW
# UHDxQruYCen/zJVVWwi/klKoCMTx6PH/QNf5mjad/bqQhdJVPlCtRh/vJQy4njpI
# BGPveJiiXQMNAtjcIKvmVrXe7xZmw9dVgh5PgnjJnlQaEGC3F6tAE5GusBnBmjOd
# 7jJyzWXMT0aYLQ9RYB58+/7b6Ad5B/ehMzj+CZrbj3u2Or2FhrjMvH0BMLd7Hald
# G73MTRf3bkcz1UDfasouUbi1uc/DBNM75ePpEIzrp7repC4zaikvFErqHsEiODUF
# he/CBAANa8HYlhRIFa9+UrC4YMRStUqCt4UqAEkqJoMnWkHevdVmSbwLnHhwCbww
# ggd6MIIFYqADAgECAgphDpDSAAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3Nv
# ZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5
# MDlaFw0yNjA3MDgyMTA5MDlaMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIw
# MTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQ
# TTS68rZYIZ9CGypr6VpQqrgGOBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULT
# iQ15ZId+lGAkbK+eSZzpaF7S35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYS
# L+erCFDPs0S3XdjELgN1q2jzy23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494H
# DdVceaVJKecNvqATd76UPe/74ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZ
# PrGMXeiJT4Qa8qEvWeSQOy2uM1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5
# bmR/U7qcD60ZI4TL9LoDho33X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGS
# rhwjp6lm7GEfauEoSZ1fiOIlXdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADh
# vKwCgl/bwBWzvRvUVUvnOaEP6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON
# 7E1JMKerjt/sW5+v/N2wZuLBl4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xc
# v3coKPHtbcMojyyPQDdPweGFRInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqw
# iBfenk70lrC8RqBsmNLg1oiMCwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMC
# AQAwHQYDVR0OBBYEFEhuZOVQBdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQM
# HgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1Ud
# IwQYMBaAFHItOgIxkEO5FAVO4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0
# dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0Nl
# ckF1dDIwMTFfMjAxMV8wM18yMi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUF
# BzAChkJodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0Nl
# ckF1dDIwMTFfMjAxMV8wM18yMi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGC
# Ny4DMIGDMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# b3BzL2RvY3MvcHJpbWFyeWNwcy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcA
# YQBsAF8AcABvAGwAaQBjAHkAXwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZI
# hvcNAQELBQADggIBAGfyhqWY4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4s
# PvjDctFtg/6+P+gKyju/R6mj82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKL
# UtCw/WvjPgcuKZvmPRul1LUdd5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7
# pKkFDJvtaPpoLpWgKj8qa1hJYx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft
# 0N3zDq+ZKJeYTQ49C/IIidYfwzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4
# MnEnGn+x9Cf43iw6IGmYslmJaG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxv
# FX1Fp3blQCplo8NdUmKGwx1jNpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG
# 0QaxdR8UvmFhtfDcxhsEvt9Bxw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf
# 0AApxbGbpT9Fdx41xtKiop96eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkY
# S//WsyNodeav+vyL6wuA6mk7r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrv
# QQqxP/uozKRdwaGIm1dxVk5IRcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIW
# eDCCFnQCAQEwgZUwfjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAA
# AI6HkaRXGl/KPgAAAAAAjjANBglghkgBZQMEAgEFAKCCAWkwGQYJKoZIhvcNAQkD
# MQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJ
# KoZIhvcNAQkEMSIEIH0olYk3mk/8ZR5bVKr0cmXmE/7Ic5tOxqgeaJ6f/OvLMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAHtMafTCQaKhjphe6e8ypF96
# S5gId5Gd4OEjZxuxoxzBRYbP8h7Crep+BgNnyrqD5vVTtNqUk/zBXeeLyO0OilDj
# bfsSPzmLnZLCFHT29XmP/XGEtSMIPxkMz4PCDe8x4AHc36K9SddI1Dta5DMvZkbT
# CovEJHndaXyUgSCkzD8eT0TDcjuzTc7mhSS2/7OZCNj36F7VT8dlZn8UTTPwd2CN
# p+Eht40BcDaohrzpDXWhz5MjBzFxofkQ8R2fQQVYyK9M4Dmu3I13GEny0FvXkhs1
# g8sJv7+gT6kwAg+fpmaQlKJMFlZOQ3VbvY37ON0iiMO5kkgJRQz3q6mtMofubRuh
# ghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG9w0BBwKgghMfMIITGwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBOgYLKoZIhvcNAQkQAQSgggEpBIIBJTCCASEC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgT0TgqwrJpAs8LFaYCTn+
# EmO4iVak1yAhlvdqQr8YsWkCBljwlST/+BgTMjAxNzA0MjYyMzU0MDUuNjYyWjAE
# gAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjE0OEMt
# QzRCOS0yMDY2MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIOzDCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1p
# Y3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcw
# MTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs
# /BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUd
# zgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAy
# WGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJy
# GiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqx
# qPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4W
# nAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU
# 1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEw
# CwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/o
# olxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNy
# b3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYt
# MjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIB
# FjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQu
# aHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8A
# UwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG
# 4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m8
# 7WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/
# 8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kp
# vLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlK
# cWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsi
# OCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw
# 4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995yfmFrb3epgcun
# Caw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1
# wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvH
# Ia9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2g
# UDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNowggPCoAMCAQICEzMAAAC0Qzoc
# /ra6UokAAAAAALQwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwHhcNMTYwOTA3MTc1NjU4WhcNMTgwOTA3MTc1NjU4WjCBszELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9QUjEn
# MCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjE0OEMtQzRCOS0yMDY2MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEA4IFPu7XRMDo/gwC3zFaf95usurNdZBEegtZ61+4g+7PR
# CAFjl1enwuJMVqi1V9ugxt+z0RixHn6RrBkZUW1z/p4tbSRCIMTI70Zp0G8cTGFq
# lDMPlD7bom8lKr8Z0s4DOlIVgEVlG/3Ptf83smhmmWWt7v++gU1Dngt4CdYqjz2K
# tAcz2bBQJFHvf/Uk1BUMj3YY2Fa8tW2jKXTYdQdIQBmOZhiRAgJwG0Hb+SehGXXG
# lqj6QS+7esU0pjCgl5PHGmwAWoK2jABnksvMTdJsqePEXnkLAZWuqKS5Iv75RV4/
# fRkbYZw3dNmjUcXuSNlUMxSDX7LnD3uwH8mXvpmFcQIDAQABo4IBGzCCARcwHQYD
# VR0OBBYEFAyTq0XUbAt3L/MrV/PpJMSHB/RfMB8GA1UdIwQYMBaAFNVjOlyKMZDz
# Q3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9z
# b2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAx
# LmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggEBAAK1YVugp9JqrCYvtsI0o3T7qHuQsYItqIkSXaT2ggtZPSfneh15LPjL
# cs9Ha+9v3uuSbe6v+16hkYR4419Re8SXMeBQje26mfeIKr9RauIj5DdH3WbixYUI
# 7P51cet6bUmJJSEdnY4W5Fik5qiVtZu0k6GKLLicITq8AVEfmOCf8+3qUMy7N4Qp
# avAibKVPrhMReWZkcCejDPq03ky7UH7En3/pgVEE3q4UX+YODBCBukasO2IS57XR
# CjDw0yns+tNwMW4KeiRRwiLmDiK3Q1GqU1Ui9SS159N1eCmhOltpCuCtfJnPn7SS
# KAd+qnDEMoZbSg7YRLb1PmcfecPyK1OhggN1MIICXQIBATCB46GBuaSBtjCBszEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjE0OEMtQzRCOS0yMDY2MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4DAhoF
# AAMVAAfAlZeuLk5uydN19tmJUZiLIG06oIHCMIG/pIG8MIG5MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYDVQQL
# Ex5uQ2lwaGVyIE5UUyBFU046NERFOS0wQzVFLTNFMDkxKzApBgNVBAMTIk1pY3Jv
# c29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDc
# q0/MMCIYDzIwMTcwNDI2MTY1NjQ0WhgPMjAxNzA0MjcxNjU2NDRaMHMwOQYKKwYB
# BAGEWQoEATErMCkwCgIFANyrT8wCAQAwBgIBAAIBGjAHAgEAAgIbvTAKAgUA3Kyh
# TAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMBoAowCAIBAAIDB6Eg
# oQowCAIBAAIDB6EgMA0GCSqGSIb3DQEBBQUAA4IBAQCQe9PKXULbqzlmdE24dGIc
# 8bSJ/Ie+hW23ROMlLzvsitgKa98E/2GZcf0yZ7XTAbaggbsjfUB/Z73E4X8VZHxS
# LhJYg4wPvXWZb0Flb0Tcr6ZGo2+ESuWT3ZuQ/hx+jSBmKCtiU/NdQZbfOVKW/JN1
# YWdfWgolAyCDfQN+FDtjeHW25GCbmV4IvQ8HWMQLQJzQFHNTsVXM9qJzmI1KpVN9
# 5Gltop+J/V5PMX6Hh249uGEMNq0w78+uzTCXJroyaWZtZc6ggqtlUmX5Y7UK7rvo
# 73yhg3p5ndpV+A/5rDpTsyIeZWieZLWpff58EMH/Bug6DqhqstUcMU5SiK+GzVcy
# MYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAC0Qzoc/ra6UokAAAAAALQwDQYJYIZIAWUDBAIBBQCgggEyMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg9cyBv93agrE8YIZc8g1x
# PMBJu7sO2dyZzsreYXZtkZkwgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGxBBQH
# wJWXri5ObsnTdfbZiVGYiyBtOjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAAAtEM6HP62ulKJAAAAAAC0MBYEFD0IHYltP9HRvAmIbEZV
# 8WGBDMOvMA0GCSqGSIb3DQEBCwUABIIBAIgx4dno/qFxc4n2XmztuU9p3s7G6PPq
# xkSR4yULBn78lJ7tbMe+awe64OYdDDuAHpDdqYfuMzDGsh7CeyVOisnk9PtZ/J3u
# iLK6i5101h1ACaYp3AlCjMOAF5idcPGublPwTFnwX3K7IG/ialME99E6x6hcTt38
# q2FnOmKjQe8Nof4GzTNd7S1pOeGuVTmKuc72Dc3iTE4Qto69VFoEdqW3UKNNqJzE
# +GR0KfbDzFaUsMX/fdVJWaa3zLrL/Lu/bKP7ctL/+ZYYd58fImqpXfswpGamYdCi
# 6EB7yhY5sEu7HKxeIIRuFf3GQuqbUPYkXcWkT+qO8oXTV5/j2yC2JDc=
# SIG # End signature block
