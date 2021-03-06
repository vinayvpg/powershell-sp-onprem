#=============================================
# Project		: Search Health Reports (SRx)
#---------------------------------------------
# File Name 	: Enable-SRxCrawlDiag.psm1
# Author		: Brian Pendergrass
# Contributors	: Eric Dixon, Anthony Casillas
# Requires: 
#	PowerShell Version 3.0, Search Health Reports (SRx), Microsoft.SharePoint.PowerShell
#
#==========================================================================================
# This Sample Code is provided for the purpose of illustration only and is not intended to 
# be used in a production environment.  
#
#	THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY
#	OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
#	WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#
# We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to 
# reproduce and distribute the object code form of the Sample Code, provided that You agree:
#	(i) to not use Our name, logo, or trademarks to market Your software product in 
#		which the Sample Code is embedded; 
#	(ii) to include a valid copyright notice on Your software product in which the 
#		 Sample Code is embedded; 
#	and 
#	(iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against
#		  any claims or lawsuits, including attorneys' fees, that arise or result from 
#		  the use or distribution of the Sample Code.
#
#==========================================================================================

function Enable-SRxCrawlDiag {	
<#
.SYNOPSIS
	Enables detailed methods and properties relating to Search Crawl diagnostics
       
.DESCRIPTION
	The crawl diagnostic enhancements largely revolves around extensions to the
	Content Source object(s) and creates methods for accessing each:
		Basic:		$xSSA._GetContentSource() | SELECT *
		Extended: 	$xSSA._GetContentSourceEx() | SELECT *

.INPUTS
	$SSA [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]

.OUTPUTS
	$xSSA (with Crawl Diagnostic methods/properties)
	
.EXAMPLE
	$xSSA | Enable-SRxCrawlDiag
	Extends the $xSSA with the core Crawl Diagnostic methods/properties

.EXAMPLE
	$xSSA | Enable-SRxCrawlDiag -ThreadReport
	Extends the $xSSA with the core Crawl Diagnostic methods/properties and 
	also calculates the threads per host being crawled. These thread reports
	get appended to each of the crawl component objects (after running this,
	see the output to $xSSA._GetCC() and $xSSA._ContentSourceUniqueHosts)

#>

[CmdletBinding()]
param ( 
  		[parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
			[alias("SearchServiceApplication")]$SSA = $xSSA,
		[alias("ThreadReport")][switch]$IncludeThreadReport,
		[alias("Extended")][switch]$ExtendedObjects
	)
	#== Variables ===	
	$moduleMsgPrefix = "[Enable-SRxCrawlDiag]"

	if ($global:SRxEnv.DebugTimings -is [hashtable]) { 
		$TrackDebugTimings = $true
		$global:SRxEnv.DebugTimings[$moduleMsgPrefix] = $(New-Object System.Collections.ArrayList)
		$global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Beginning $moduleMsgPrefix..." } ) | Out-Null
	}

	#== Determine the [target]SSA context ===
    try {
		if (-not [String]::IsNullOrEmpty($SSA)) {
			#Regardless of the incoming object type (e.g. string, array, SP SSA, or $null) ...should handle any of them
            $targetSSA = Get-SRxSSA -SSA $SSA
		} else { 
            #if $null, but there is an $xSSA variable defined with _hasSRx property set as $true, then just assume it
            $targetSSA = Get-SRxSSA
        }
	} catch {
		Write-SRx ERROR ($_.Exception.Message)
		Write-SRx VERBOSE ($_.Exception)
	}

    if ($targetSSA -eq $null) {
  		Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Missing Prerequisite: Initialize the SRx environment by running the initSRx.ps1 configuration script")
		return
    }

	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded `$xSSA..." } ) | Out-Null }

	#-- Extended Methods/Properties: Only added if the $targetSSA is not yet SRx Enabled for Crawl Reports
	if (-not $targetSSA._hasSRxCrawlDiagnostics) {
		Write-SRx INFO $(" * " + $moduleMsgPrefix + " Extending `$xSSA...")

		#== From here, we now have a specific [target] SSA that we can extend ====
		#-- ensure the cache structures exist (and create if not)
		if ($global:___SRxCache -isNot [hashtable]) { $global:___SRxCache = @{} }
		if ($global:___SRxCache[$targetSSA.Name] -isNot [hashtable]) { $global:___SRxCache[$targetSSA.Name] = @{} }

		#-- Methods: Crawl Resources
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetCrawlRules			-Value { return $($this | Get-SPEnterpriseSearchCrawlRule) }
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetSiteHitRules			-Value { return $($this | Get-SPEnterpriseSearchSiteHitRule) }	
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetServerNameMappings	-Value { return $($this | Get-SPEnterpriseSearchCrawlMapping) }
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetCrawlFileFormats  -Value {
			$ssaStatusInfo = $this._GetSearchStatusInfo()
			if (-not $global:SRxEnv.h.isUnknownOrNull($ssaStatusInfo)) {
				$(Get-SPEnterpriseSearchFileFormat -SearchApplication $this -ErrorAction SilentlyContinue)
			}
		}

		#--- Methods: Content Source Configuration ---	
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _QueryMSSCrawlHistory -Value {
			param ($contentSourceID = "*", $ignoreIdleCrawls = $true, $resultLimit = 10, $columns = "", $minCrawlID = 2)
			  #Note: the crawlID's 1 and 2 are for continuous crawls (all other regular crawls will some higher value)... 
			  #      ...so by setting "$minCrawlID = 2" above, I'm effectively having this query ignore the continuous crawls by default
			
			$queryTemplate = '.\search\adminDB\CrawlHistory.sql'
			$dbConnectionString = $this.SearchAdminDatabase.DatabaseConnectionString
			
			if ($resultLimit -gt 0) { $queryParameters += "Top " + $resultLimit + " " }
			if ([String]::IsNullOrEmpty($columns)) { 
				$queryParameters += "*"
			}
			
			$delim = ""
			$columns | foreach {
				$queryParameters += $delim + $_.toString(); $delim = ","
			}
			
			$queryVariables = @{ 
				"**SEARCHADMIN**" = $this.SearchAdminDatabase.Name;
				"**TOP**" = $( if([String]::IsNullOrEmpty($queryParameters)) {""} else {$queryParameters} ) 		
			}
			
			if ($contentSourceID -eq "*") {
				$queryVariables["**WHERE**"] = "WHERE MSSCrawlHistory.CrawlId > " + $minCrawlID; 
			} elseif ($global:SRxEnv.h.isNumeric($contentSourceID)) {
					$queryVariables["**WHERE**"] = "WHERE MSSCrawlHistory.ContentSourceId = " + $contentSourceID + 
													" AND MSSCrawlHistory.CrawlId >= " + $minCrawlID;
				} else {
					$queryVariables["**WHERE**"] = "WHERE MSSCrawlHistory.ContentSourceId in ("
					$delim = ""; 
					$contentSourceID | foreach {
					$queryVariables["**WHERE**"] += $delim + $_.toString(); $delim = ","
					}; 
					$queryVariables["**WHERE**"] += ")"
				}
			
			if ($ignoreIdleCrawls) {
				$queryVariables["**WHERE**"] +=  " AND MSSCrawlHistory.Status Not In (5,11,12)"
			} else {
				$queryVariables["**WHERE**"] +=  " AND MSSCrawlHistory.Status <> 5"
			}

    	    return $( $queryTemplate | Invoke-SRxSQLQuery $dbConnectionString -v $queryVariables )
		}
		
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _QueryCrawlStats -Value {
			param ($crawlID)
			
			$queryTemplate = '.\search\adminDB\CrawlStats.sql'
			$dbConnectionString = $this.SearchAdminDatabase.DatabaseConnectionString
			$queryVariables = @{ "**SEARCHADMIN**" = $this.SearchAdminDatabase.Name; }
			
			if ($global:SRxEnv.h.isNumeric($crawlID)) {
				$queryVariables["**WHERE**"] = "WHERE CrawlId = " + $crawlID
			} else {
				$queryVariables["**WHERE**"] = "WHERE CrawlId in ("
				$delim = ""; 
				$crawlID | foreach {
					$queryVariables["**WHERE**"] += $delim + $_.toString(); $delim = ","
				} 
				$queryVariables["**WHERE**"] += ")"
			}
			
			return $( $queryTemplate | Invoke-SRxSQLQuery $dbConnectionString -v $queryVariables )
		}

		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _QueryActiveCrawlStats -Value {
			param ($contentSourceID = "*", $resultLimit = 1000)
			
			$queryTemplate = '.\search\adminDB\ActiveCrawlStats.sql'
			$dbConnectionString = $this.SearchAdminDatabase.DatabaseConnectionString
			$queryVariables = @{ 
				"**SEARCHADMIN**" = $this.SearchAdminDatabase.Name;
				"**TOP**" = "Top " + $resultLimit;
			}
			
			if ($contentSourceID -eq "*") {
				$queryVariables["**WHERE**"] = "WHERE MSSCrawlHistory.CrawlId > " + $minCrawlID; 
			} else {
				$queryVariables["**WHERE**"] = "WHERE MSSCrawlHistory.ContentSourceId = " + $contentSourceID + 
												" AND MSSCrawlHistory.CrawlId >= " + $minCrawlID;
			}

			return $( $queryTemplate | Invoke-SRxSQLQuery $dbConnectionString -v $queryVariables )
		}		
		
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _QueryMSSCrawlComponentsState -Value {
			param ($crawlID = "*")
			
			$queryTemplate = '.\search\adminDB\CrawlComponentsState.sql'
			$dbConnectionString = $this.SearchAdminDatabase.DatabaseConnectionString
			$queryVariables = @{ "**SEARCHADMIN**" = $this.SearchAdminDatabase.Name }
			
			if ($crawlID -eq "*") {
				$queryVariables["**WHERE**"] = ""
			} else {
				$queryVariables["**WHERE**"] = "AND hist.CrawlId = " + $crawlID; 
			}	
			
			return $( $queryTemplate | Invoke-SRxSQLQuery $dbConnectionString -v $queryVariables )
		}

        $targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _QueryCrawlLoad -Value {
        	param ($additionalFilter = "*", $minutesBack = 31, $endDateTimeinUTC = (Get-Date).ToUniversalTime())

	        #normalize incoming parameter (e.g. if user calls $s._QueryCrawlLoad( 360 ) , then assume a filter of "*" and set minutes back to 360 )
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

	        $queryTemplate = '.\search\usageDB\CrawlLoad.sql'
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
			            ($this._Servers | ? {$_.hasCrawler}).Name.toUpper().Contains(($additionalFilter).toUpper())
			        ) {
			            $(" AND MachineName = '" + $additionalFilter.toUpper() + "'")
			        } else {
			            $(" AND " + $additionalFilter)
			        }
		        );
	        }
	        return $( $queryTemplate | Invoke-SRxSQLQuery $dbConnectionString -v $queryVariables )
        }

		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetContentSourceEx -Value {
			param ($targetContentSource = "*", $ExcludeTarget = $false)

			if ($targetContentSource -is [bool]) {
				#Assume this was invoked such as: $xSSA._GetContentSourceEx($true)  
				#...which should imply $targetContentSource "*" and $true was intended for the $ExcludeTarget flag
				$ExcludeTarget = $targetContentSource
				$targetContentSource = "*"
			}
			
			$srcEx = $this._GetContentSource($targetContentSource, $true, $ExcludeTarget)
			return $srcEx
		}

		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetContentSourceReport -Value {
			param ($targetContentSource = "*")
			$this._GetContentSourceEx($targetContentSource) | SELECT *
		}

		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetContentSourceSummary -Value {
            $this._GetContentSource() | foreach { 
	            $(New-Object PSObject -Property @{
		            "Name" = $_.Name;
                    "Id" = $_.Id;
		            "Type" = $_.Type;
                    "CrawlState" = $_.CrawlState;
		            "StartAddresses" = $_.StartAddresses.Count;
		            "TotalItems" = $($_.SuccessCount + $_.WarningCount + $_.ErrorCount);
	            })
            }
        }

		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetContentSource  -Value {
			param (
				$targetContentSource = @( "*" ),
                [bool]$Extended = $false, 
                [bool]$ExcludeTarget = $false,
				[ValidateSet("All","MSSCrawlHistory","procGetCrawlStats","HostDetails")]
					[String]$IncludeDataSource = $( if ($Extended) { "All" } else { "HostDetails" } ),
				[bool]$bypassCache = $false
			)
			
			if ($targetContentSource -is [bool]) {
				#Assume this was invoked such as: $xSSA._GetContentSource($true)  
				#...which should imply $targetContentSource "*" and $true was intended for the $Extended flag
				$Extended = $targetContentSource
				$targetContentSource = @( "*" )
			} elseif (($targetContentSource -is [Array]) -or ($targetContentSource -is [System.Collections.ArrayList])) {
                #With an array, the user is looking for some sub-set of all content sources
                if ($ExcludeTarget) {
                    $global:ContentSourceFilter = $targetContentSource   #treat the "target" as a list of excludes
                	$targetContentSource = @( "*" )
                }
            } else {
			    if ($ExcludeTarget) {
                    $global:ContentSourceFilter = @( $targetContentSource )
                    $targetContentSource = @( "*" )
                } else {
                    $targetContentSource = @( $targetContentSource )
                }
            }

		
			if ($global:SRxEnv.DebugTimings -is [hashtable]) { 
				$TrackDebugTimings = $true
				$methodMsgPrefix = "_GetContentSource"
				$global:SRxEnv.DebugTimings[$methodMsgPrefix] = $(New-Object System.Collections.ArrayList)
				$global:SRxEnv.DebugTimings[$methodMsgPrefix].Add( @{ $(Get-Date) = "Beginning $moduleMsgPrefix..." } ) | Out-Null
			}

			if ((-not $bypassCache) -and ($targetContentSource[0] -eq "*") -and ($global:___SRxCache[$this.Name].ContentSourceEx -ne $null)) {
				$timeOfLastReport = $($global:___SRxCache[$this.Name].ContentSourceEx.Keys)[0]
				$reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
				
				$ttl = $global:SRxEnv.ContentSourceCacheTTL 
				if ((-not $global:SRxEnv.h.isNumeric($ttl)) -or ($ttl -le 0)) { 
					$ttl = 1200 #1200 seconds = 20 minutes
				}
				
				if ($reportAge -lt $ttl) {
					Write-SRx INFO $("--[GetContentSource] Using cache until " + $(Get-Date).AddSeconds($ttl - $reportAge)) -ForegroundColor Cyan
					if ($ExcludeTarget) {
                        $filtered = $global:___SRxCache[$this.Name].ContentSourceEx[$timeOfLastReport] | Where {
                            (-not $($ContentSourceFilter -contains $_.Id)) -and (-not $($ContentSourceFilter -contains $_.Name))
                        }
                        return $filtered
                    } else {
                        return $global:___SRxCache[$this.Name].ContentSourceEx[$timeOfLastReport]
                    } 
				}
			}
			
			#determine how to extend the content source objects
			if ($Extended) {
				if ($IncludeDataSource -ne "All") {
					$Extended = $false; #disable [fully] $Extended, and only extend with the specific data source specified below
					switch ($IncludeDataSource) {
						"MSSCrawlHistory"	{ $ExtendedWithMSSCrawlHistory = $true; break }
						"procGetCrawlStats"	{ 
							$ExtendedWithMSSCrawlHistory = $true;
							$ExtendedWithProcGetCrawlStats = $true; 
							break 
						}
						"HostDetails"		{ $ExtendedWithHostDetails = $true; break }
					}
				}
			} elseif ((-not $ExcludeTarget) -and ($targetContentSource[0] -ne "*")) { 
				#if targeting a specific host, go ahead and get the host details (even if $Extended is $false)
				$ExtendedWithHostDetails = $true 
			}
		
			if (($targetContentSource[0] -eq "*") -or ([string]::IsNullOrEmpty($targetContentSource[0]))) {
				$SRxContentSources = $this | Get-SPEnterpriseSearchCrawlContentSource
			
				#-- also build a container to track all the unique hosts if $Extended mode and it does not exist
				if ((($Extended) -or ($ExtendedWithHostDetails)) -and (-not ($this._ContentSourceUniqueHosts))) {
					$this | Set-SRxCustomProperty "_ContentSourceUniqueHosts" $(New-Object System.Collections.ArrayList)
					$rebuildUniqueHostsLists = $true
				}
				
			} else {
                $SRxContentSources = $(New-Object System.Collections.ArrayList)
				foreach ($target in @( $targetContentSource )) {
                    try {
					    $SSAContentSource = $this | Get-SPEnterpriseSearchCrawlContentSource $target
                        Write-SRx VERBOSE $("---[`$xSSA._GetContentSource()] Loaded content source: " + $SSAContentSource.Name)
                        $SRxContentSources.Add($SSAContentSource) | Out-Null
				    } catch {
                        Write-SRx WARNING $("~~~[`$xSSA._GetContentSource()] Failure loading Content Source `"" + $target + "`"")
                        Write-SRx ERROR "$_"
				    }
                }
			}
			
			foreach ($contentSource in $SRxContentSources) {
				if ($Extended -or $ExtendedWithHostDetails) {
				    Write-SRx VERBOSE $("-" * 50)
					Write-SRx VERBOSE $("[csId: " + $contentSource.id + "] Extending content source: " + $contentSource.Name)
					
					foreach ($startUri in $contentSource.StartAddresses) {
					    Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Start Address: " + $startUri)
                        #-- As we go through each content source, populate the container tracking all the unique hosts
					    if ($rebuildUniqueHostsLists) {
						    $ssaHostReport = $this._ContentSourceUniqueHosts | Where {$_.Host -eq $startUri.Authority}
						    if (-not $ssaHostReport) {
							    Write-SRx VERBOSE $("Creating SSA Host Report for: " + $startUri.Authority)
							    $ssaHostReport = New-Object PSObject -Property @{
								    "Host" = $startUri.Authority;
								    "ContentSource" = @( $contentSource.Name );
							    }
							    $this._ContentSourceUniqueHosts.Add($ssaHostReport) | Out-Null
						    } elseif (-not ($ssaHostReport.ContentSource)) {
							    $ssaHostReport | Set-SRxCustomProperty "ContentSource" @( $contentSource.name )
						    } elseif (-not ($ssaHostReport.ContentSource.ToLower().Contains($contentSource.Name.ToLower()))) {
							    $ssaHostReport.ContentSource += $contentSource.name
						    }
					    }
					
					    #-- For SharePoint content, we can modify the StartAddresses further...
					    #switch ($contentSource.Type) { #"Web" {} "File" {} "BDC" {} "Custom" {} "SharePoint" {} default {} }
					    if ($contentSource.Type -eq "SharePoint") { 	
						    switch -wildcard ($startUri.Scheme) {
							    "sps*" {} # [Profile "People" Crawl]
							    "http*" { # [Content (Portal) Crawl] 
								    $matchedAAM = foreach ($farmAAM in $(Get-SPFarm).AlternateUrlCollections) { $farmAAM | Where { $_.Uri.isBaseOf($startUri.AbsoluteUri) } } 
								    if ($matchedAAM) {	
									    #toDo: Does this look any different for "Externally Mapped" AAMs?
									    $startUri | Set-SRxCustomProperty "_inLocalAAMs"			 $([bool]$true)
									    $startUri | Set-SRxCustomProperty "_AAMZone" 				 $matchedAAM.UrlZone
									    $startUri | Set-SRxCustomProperty "_AAMZonePublicUrl"		 $(($matchedAAM.Collection | Where {$_.UrlZone -eq $matchedAAM.UrlZone } | Get-Unique).PublicUrl)
									    $startUri | Set-SRxCustomProperty "_AAMDefaultZonePublicUrl" $(($matchedAAM.Collection | Where {$_.UrlZone -eq "Default" } | Get-Unique).PublicUrl)

									    if ($Extended -and (($webApp = Get-SPWebApplication $startUri.aamDefaultPublicUrl -ErrorAction SilentlyContinue) -ne $null)) {
										    $IISsettings = $webApp.IisSettings[[Microsoft.SharePoint.Administration.SPUrlZone]::($matchedAAM.UrlZone)]

										    $startUri | Set-SRxCustomProperty "_WebAppUserPolicies"		$($webApp.Policies)
										    $startUri | Set-SRxCustomProperty "_WebAppClaimsBased"		$($webApp.UseClaimsAuthentication)
										    $startUri | Set-SRxCustomProperty "_WebAppSiteDataServers"	$($webApp.SiteDataServers)
																		
										    if ($webApp.UseClaimsAuthentication) { 
											    $startUri | Set-SRxCustomProperty "_WebAppClaimsAuthProviders" $($IISsettings.ClaimsAuthenticationProviders)
										    } else {
											    # Authentication Type: [Classic]
											    if ($IISsettings.DisableKerberos) { 
												    $startUri | Set-SRxCustomProperty "_WebAppClassicAuthProvider" "[Windows:NTLM]"
											    }
											    else {
												    $startUri | Set-SRxCustomProperty "_WebAppClassicAuthProvider" "[Windows:Negotiate(Kerberos)]"
											    }
										    }
									    }
									}
								}
							}
						}
					}
				}
				
				if ($Extended -or $ExtendedWithMSSCrawlHistory) {
					Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Running QueryMSSCrawlHistory...")
                    $mssCrawlHistory = $this._QueryMSSCrawlHistory($contentSource.id, ($contentSource.CrawlState -ne "Idle"), 1)
					if ($mssCrawlHistory -and $mssCrawlHistory.CrawlId) {
						#$propertyBag = $mssCrawlHistory | Get-Member -MemberType Property -ErrorAction SilentlyContinue  #| Where { $_.MemberType -eq "Property" }
						$propertyBag = $mssCrawlHistory | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue  #| Where { $_.MemberType -eq "Property" }
						foreach ($columnName in $propertyBag.Name) {
							$duplicateProperties = $contentSource | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue | Where { $_.Name -ieq $("_" + $columnName) }
							if ($duplicateProperties.Count -eq 0) {
								Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Set Custom Property: " + $columnName)
                                $contentSource | Set-SRxCustomProperty $("_" + $columnName) $mssCrawlHistory.$columnName
							}
						}

						$contentSource | Set-SRxCustomProperty "_CrawlStatusDetailed" $(
							$this._ConvertCrawlStateToString($mssCrawlHistory.Status, $mssCrawlHistory.Substatus)
						)
						$contentSource | Set-SRxCustomProperty "_CrawlComponentsState" $( 
							if (($contentSource.CrawlState -ne "Idle") -and ($contentSource._Status -gt 0) -and ($contentSource._CrawlId -gt 0)) {
								Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Running QueryMSSCrawlComponentsState...")
                                $states = $this._QueryMSSCrawlComponentsState($contentSource._CrawlId)
								if($states){ @($states) } else { @() } 
							} else { @() } #empty array
						)
						$contentSource | Set-SRxCustomProperty "_CrawlTypeEnum" $(
							switch ($mssCrawlHistory.CrawlType) {
								"1" { "Full" }
								"2" { "Incremental" }
								"6" { "Delete Crawl" }
								"8" { "Continuous" } #the CrawlType in MSSCrawlHistory will never be set to this type (this is here for documentation purposes only)
								default { $("Crawl type [" + $mssCrawlHistory.CrawlType + "] is not defined in SRx") }
							}
						)
						
						#Only get crawl statistics if the crawl status is not 0 [initial request] or 1 [starting]
						if (($contentSource._Status -gt 1) -and ($contentSource._CrawlId -gt 0)) {
							Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Running QueryCrawlStats...")
                            $mmsCrawlStats = $this._QueryCrawlStats($mssCrawlHistory.CrawlId)
						}
						
						if ($mmsCrawlStats -and $mmsCrawlStats.CrawlId) {
							#$propertyBag = $mmsCrawlStats | Get-Member -MemberType Property -ErrorAction SilentlyContinue
							$propertyBag = $mmsCrawlStats | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue
							foreach ($columnName in $propertyBag.Name) {
								$duplicateProperties = $contentSource | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue | Where { $_.Name -ieq $("_" + $columnName) }
								if ($duplicateProperties.Count -eq 0) {
									Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Set Custom Crawl Stat Property: " + $columnName)
                                    $contentSource | Set-SRxCustomProperty $("_" + $columnName) $mmsCrawlStats.$columnName
                                }
							}
						} else {
                            Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Setting Crawl Stats to -1 (*this crawl is likely starting, so we have no real stats yet)")
							$contentSource | Set-SRxCustomProperty "_Successes"    -1 #setting a default value
							$contentSource | Set-SRxCustomProperty "_Errors"       -1 #setting a default value
							$contentSource | Set-SRxCustomProperty "_Warnings"     -1 #setting a default value
							$contentSource | Set-SRxCustomProperty "_Retries"      -1 #setting a default value
							$contentSource | Set-SRxCustomProperty "_Deletes"      -1 #setting a default value
							$contentSource | Set-SRxCustomProperty "_SecurityOnly" -1 #setting a default value
							$contentSource | Set-SRxCustomProperty "_NotModified"  -1 #setting a default value
						}
						
						$contentSource | Add-Member -Force ScriptProperty -Name _CurrentTimeUTC -Value { $(Get-Date).ToUniversalTime() }

                        $contentSource | Set-SRxCustomProperty "_CrawlDuration" $(
                            if (($contentSource._Status -gt 0) -and (-not [String]::isNullOrEmpty($contentSource._StartTime))) {
                                $start = $( $contentSource._StartTime)
                                if (-not [String]::isNullOrEmpty($contentSource._EndTime)) {
                                    $end = $contentSource._EndTime
                                } else {
                                    $end = $contentSource._CurrentTimeUTC
                                }
                                Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Calculating Crawl Duration")
                                $duration = New-TimeSpan $start $end
                            } else {
                                #in this case, we are in the process of requesting a new crawl, so there is no duration
                                Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] No Crawl Duration *(the crawl has only been requested)")
                                $duration = New-TimeSpan  #will be a zero length timespan object
                            }
                            $duration
                        )

                        #_AverageCrawlRate:    (_Successes + _Warnings + _Errors + _NotModified + _Deletes + _SecurityOnly) / _CrawlDuration
                           # -this needs to be 0 if the crawl is currently starting or if avgCrawlRate lt 0
                        $contentSource | Set-SRxCustomProperty "_AverageCrawlRate" $( 
                            $crawlDuration = $($contentSource._CrawlDuration).TotalSeconds
                            Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Calculating Average Crawl Rate")
                            if (($crawlDuration -ne $null) -and ($crawlDuration -gt 0)) { 
                            $itemsProcessed = [long]$contentSource._Successes + [long]$contentSource._Warnings + [long]$contentSource._Errors + 
                                                [long]$contentSource._NotModified + [long]$contentSource._Deletes + [long]$contentSource._SecurityOnly
                                if (($itemsProcessed -gt 0) -and ($crawlDuration -gt 0)) {
                                    $dps = $itemsProcessed / $crawlDuration
                                } else {
                                    $dps = 0
                                }
                            } else { $dps = 0 }
                            $dps 
                        )
					} else {
                        Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] QueryMSSCrawlHistory returned no rows")
                    }
				}
				Write-SRx DEBUG
			}
			
			if ($Extended -and (($targetContentSource[0] -eq "*") -or ([string]::IsNullOrEmpty($targetContentSource[0])))) {
                #cache this result
				Write-SRx DEBUG $(" --> [Content Source Id: " + $contentSource.id + "] Caching the extended Content Sources")
                $global:___SRxCache[$this.Name].ContentSourceEx = @{ $(Get-Date) = $SRxContentSources }
            }

            if ($ExcludeTarget -and ($ContentSourceFilter.Count -gt 0)) {
                $filtered = $SRxContentSources | Where { (-not $($ContentSourceFilter -contains $_.Id)) -and (-not $($ContentSourceFilter -contains $_.Name)) }
                $SRxContentSources = $filtered
            }
			
			return $SRxContentSources 
		}

		#--- Methods: Visualize Recent Crawl History ---
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetRecentCrawlVisualizationData -Value {
			param ([int]$hoursBack = 48, [int]$minutesPerSlice = 1, [Object[]]$excludeFilter = @())

            if($excludeFilter.Count -gt 0) {
    			$contentSources = $this._GetContentSource($excludeFilter, $true, $true) | SELECT Name, ID, EnableContinuousCrawls
            } else {
    			$contentSources = $this._GetContentSource() | SELECT Name, ID, EnableContinuousCrawls
            }
			
			$queryLimit = $global:SRxEnv.Override.CrawlVisualizationQueryLimit #users can set a static number 
			if ((-not $global:SRxEnv.h.isNumeric($queryLimit)) -or ($queryLimit -le 0)) { 
				if ($contentSources.Count -le 0) { $queryLimit = 100 } 
				else { $queryLimit = $contentSources.Count * 15 } #there would be 6 crawls-per-day if firing every 4hrs ...and 12 in 48hr span
			}
			
			Write-SRx Verbose ("[GetRecentCrawlVisualizationData] Making query to MSSCrawlHistory")
			$mssCrawlHistory = $this._QueryMSSCrawlHistory("*", $false, $queryLimit, @(
				"CrawlID", "CrawlType", "ContentSourceID", "RequestTime", "StartTime", "EndTime"
			))

			$reportTime = $global:SRxEnv.h.GetDiscreteTime( $(Get-Date).ToUniversalTime(), $minutesPerSlice )
			$windowOpen = $global:SRxEnv.h.GetDiscreteTime( $($reportTime).AddHours( (-1) * $hoursBack ), $minutesPerSlice )
            if($excludeFilter.Count -gt 0) {
    			$candidates = $mssCrawlHistory | ? {((-not [String]::isNullOrEmpty($_.RequestTime)) -and (($_.RequestTime -gt $windowOpen) -or ([String]::isNullOrEmpty($_.EndTime)) -or ($_.EndTime -gt $windowOpen))) -and $_.ContentSourceId -in $contentSources.Id }
            } else {
    			$candidates = $mssCrawlHistory | ? {((-not [String]::isNullOrEmpty($_.RequestTime)) -and (($_.RequestTime -gt $windowOpen) -or ([String]::isNullOrEmpty($_.EndTime)) -or ($_.EndTime -gt $windowOpen))) }
            }

			$crawlReports = $(New-Object PSObject -Property @{
				"minutesPerSlice" = $minutesPerSlice;
				"reportTime" = $reportTime;
				"windowOpen" = $windowOpen;
				"totalMinutes" = $(New-TimeSpan $windowOpen $reportTime).TotalMinutes;
				"maxTimeSlices" = [int]$([math]::Round( $(New-TimeSpan $windowOpen $reportTime).TotalMinutes / $minutesPerSlice ));
				"incompleteDataSet" = ($candidates.Count -eq $queryLimit); #we likely hit the upper bound
				"values" = $(New-Object System.Collections.ArrayList);
			})

            if ($crawlReports.incompleteDataSet) {
                $global:SRxEnv.PersistCustomProperty("Override.CrawlVisualizationQueryLimit", ($queryLimit + 200))
            }

			Write-SRx Verbose ("[GetRecentCrawlVisualizationData] Iterating through " + $candidates.count + " crawls...") -ForegroundColor DarkCyan
			$srcCache = @{}
			foreach ($crawl in $($candidates | Sort CrawlID)) {
				$csId = $crawl.ContentSourceID
				if (-not $csId) { 
					#If we have no content source Id for this crawl, log an error and just skip this $crawl 
					Write-SRx ERROR $("[`$xSSA._GetRecentCrawlVisualizationData()] Crawl with no content source ID (CrawlID: " + $crawl.CrawlId + ")")
				} else {
					if (-not $srcCache[$csId]) { $srcCache[$csId] = @{ "pointer" = $windowOpen; "mapOfSlices" = $(New-Object System.Collections.ArrayList) } }
					
					#set the current pointer to the end of the last crawl
					$currentPointer = $srcCache[$csId]["pointer"]

					#define the various points of time related to this crawl
					$requestTime = $global:SRxEnv.h.GetDiscreteTime( 
						$(if ($crawl.RequestTime -lt $currentPointer) {$currentPointer} else {$crawl.RequestTime}),
						$minutesPerSlice )
					$startTime = $global:SRxEnv.h.GetDiscreteTime(
						$(if ([String]::isNullOrEmpty($crawl.StartTime) -or ($crawl.StartTime -gt $reportTime)) { $reportTime }
						  elseif ($crawl.StartTime -lt $requestTime) {$requestTime} else {$crawl.StartTime}
						), $minutesPerSlice )
					$endTime = $global:SRxEnv.h.GetDiscreteTime(
						$(if ([String]::isNullOrEmpty($crawl.EndTime) -or ($crawl.EndTime -gt $reportTime)) { $reportTime }
						  elseif ($crawl.EndTime -lt $startTime) { $startTime } 
						  else { $crawl.EndTime }
						), $minutesPerSlice )
					
					#cache this endTime for a point of reference for the next crawl to compare
					$srcCache[$csId]["pointer"] = $endTime
					
					$isActive = $( if ([String]::isNullOrEmpty($crawl.EndTime)) { 1 } else { -1 } )
					$timeSpans = @( 
						@{$currentPointer = 0}, 								#Idle (0)
						@{$requestTime = ($isActive * 10)},						#Starting (10)
						@{$startTime = ($isActive * (40 + $crawl.CrawlType))},	#Crawling + [Full(1) | Inc(2) | Del(6)]
						@{$endTime = 0}
					)

					Write-SRx DEBUG "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"				
					for ($i=1; $i -lt $timeSpans.Length; $i++)  {
						#ensure the start time for this time span is before (or equal) the current time (...skip it otherwise)
						if ($timeSpans[($i - 1)].Keys[0] -le $reportTime) {
							$t0 = [datetime]$( $timeSpans[($i - 1)].Keys[0] )

							#if the end time for this time span after the current time, then just fall back to the current time
							$t1 = [datetime]$( if ($timeSpans[$i].Keys[0] -gt $reportTime) {$reportTime} else {$timeSpans[$i].Keys[0]} )
							
							#calculate the number of slices between t0 and t1
							$timeSlices = [math]::Round( $(New-TimeSpan $t0 $t1).TotalMinutes / $minutesPerSlice )
							Write-SRx DEBUG $("csId: " + $crawl.ContentSourceID + " [" + $crawl.CrawlID + "] t" + ($i - 1) + ": " + $t0 + " type: " + [int]$($timeSpans[($i - 1)].Values[0]) + " count: " + $timeSlices)
							
							$srcCache[$csId]["mapOfSlices"].Add( @{ "count" = $timeSlices; "type" = [int]$($timeSpans[($i - 1)].Values[0]) } ) | Out-Null
						}
					}
					Write-SRx DEBUG $("[csId: " + $crawl.ContentSourceID + "|crawl:" + $crawl.CrawlID + "] " +
											"ptr --> " + $srcCache[$csId]["mapOfSlices"][0]["Count"] +
											" --> req --> " + $srcCache[$csId]["mapOfSlices"][1]["Count"] + 
											" --> start --> " + $srcCache[$csId]["mapOfSlices"][2]["Count"] + 
											" [end] " + $endTime) -ForegroundColor DarkCyan
					Write-SRx DEBUG "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
					Write-SRx DEBUG
				}
			}

			Write-SRx Verbose $("[GetRecentCrawlVisualizationData] Building crawl visualization report...") -ForegroundColor DarkCyan
			foreach ($csId in $srcCache.Keys) {
				$loopStart = Get-Date
				$csName = $($contentSources | ? {$_.Id -eq $csId}).Name
                Write-SRx DEBUG $("[csId: " + $crawl.ContentSourceID + "] Adding crawl visualization report (" + $loopStart + ")")
				$cs = @{ 
					"name" = $(if([string]::isNullOrEmpty($csName)) {"nameIsNull-[id:" + $csId + "]"} else {$csName});
					"csId" = $csId;
					"dataSet" = $srcCache[$csId]["mapOfSlices"];
                    "continuousEnabled" = $($contentSources | ? {$_.Id -eq $csId}).EnableContinuousCrawls;
				}
				$timeSlices = [int]($srcCache[$csId]["mapOfSlices"] | foreach {[int]$_["Count"]} | measure -sum).Sum
				
				if ($timeSlices -lt $crawlReports.maxTimeSlices) {
					$cs.dataSet.Add( @{ "count" = $($crawlReports.maxTimeSlices - $timeSlices); "type" = 0 } ) | Out-Null
				}
				$crawlReports.values.Add($cs) | Out-Null
			}
			return $crawlReports
		}
		
		#--- Methods: Visualize Recent Crawl History ---
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _ShowRecentCrawlVisualization -Value {
			param ([int]$hoursBack = 24, [int]$minutesPerSlice = 15)
		 	
			Write-SRx INFO
			$crawlReports = $this._GetRecentCrawlVisualizationData($hoursBack, $minutesPerSlice)
			foreach ($cs in $crawlReports.values) {
				Write-SRx INFO $("[CS: " + $cs.csId + "] " + $cs.name) -ForegroundColor Cyan
				Write-SRx INFO " " -NoNewline
				$cs.dataSet | foreach { 
					$symbol = switch ([int]$_["type"]) { 
						0 {"."} -10 {"="} 11 {"~"} -41 {"f"} 41 {"F"} -42 {"i"} 42 {"I"} -46 {"d"} 46 {"D"}
					}
					if ([int]$_["type"] -gt 0) {
						Write-Host $($symbol * [int]$_["count"]) -NoNewline -ForegroundColor Green
					} else {
						Write-Host $($symbol * [int]$_["count"]) -NoNewline
					}
				}
				Write-SRx INFO
			}
			
			switch ($minutesPerSlice) {
				15 {
				  $majorMarker = "#---"
				  $intervalMarkers = "|---"
				  Write-SRx INFO ((($majorMarker + ($intervalMarkers * 11)) * 2) + "|")
				  Write-SRx INFO ("(-24hr)                 (-18hr)                 (-12hr)                 (-6hr)                  (now)")
				  break;
				}
				1  { 
				  $majorMarker = "#---------"
				  $intervalMarkers = "|---------"
				  Write-Host (($majorMarker + ($intervalMarkers * 2)) * (2 * $hoursBack) + "|")
				  if ($hoursBack -eq 1) {
					  Write-SRx INFO ("(-1hr)                        (-0.5hr)                      (now)")
				  } else {
					  Write-SRx INFO ("(-2hr)                        (-1.5hr)                      (-1hr)                        (-0.5hr)                      (now)")				  
				  }
				  break;
				}
			
			}
			Write-SRx INFO
		}
				
		#--- Methods: [Diagnostic] Crawl State "translation" ---
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _ConvertCrawlStateToString -Value {
			param ([int]$crawlStatus, [int]$crawlSubstatus)
			$statusString = ""
			switch ($crawlStatus) {
				"0" { $statusString = "Initiating request to start..." }
				"1" { 
					switch ($crawlSubstatus) {
						"1" { $statusString = "Starting, Add Start Address(es)" }
						"2" { $statusString = "Starting, waiting on Crawl Component(s)" }
						default { $statusString = "Starting"} 
					}
				}
				"4" { 
					switch ($crawlSubstatus) {
						"1" { $statusString = "Crawling" }
						"2" { $statusString = "Crawling, Unvisited to Queue" }
						"3" { $statusString = "Crawling, Delete Unvisited" }
						"4" { $statusString = "Crawling, Wait for All Databases" }
						default { $statusString = "Crawling"}
					}						
				}
				"5" { $statusString = "Failed to Start (e.g. Another Crawl Already Running)" }
				"7" { $statusString = "Resuming" }
				"8" { 
					switch ($crawlSubstatus) {
						"1" { $statusString = "Pausing, Waiting on Crawl Component(s) to Pause" }
						"2" { $statusString = "Pausing, Complete Pause" }
						default { $statusString = "Pausing"} 
					}
				}
				"9" { $statusString = "Paused" }
				"11" { $statusString = "Completed" }
				"12" { $statusString = "Stopped" }
				"13" {
					switch ($crawlSubstatus) {
						"1" { $statusString = "Stopping, Waiting on Crawl Component(s) to Stop" }
						"2" { $statusString = "Stopping, Complete Stop" }
						default { $statusString = "Stopping"} 
					}
				}
				"14" {
					"Completing"
					switch ($crawlSubstatus) {
						"1" { $statusString = "Completing, Waiting on Crawl Component(s) to Complete" }
						"2" { $statusString = "Completing" }
						"4" { $statusString = "Completing, Get Deletes Pending" }
						default { $statusString = "Completing"} 
					}
				}
				default { $statusString = "This enumeration not defined in SRx" }
			}
			$statusString += " [Status: " + $crawlStatus + "][Substatus: " + $crawlSubstatus + "]"
			$statusString
		}
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded core methods..." } ) | Out-Null }
	}
	
	#-- For each crawl component, build the host reports as applicable
	if ($ExtendedObjects -or $IncludeThreadReport) {
		$perfLevel = (Get-SPEnterpriseSearchService).PerformanceLevel
	
		#Calling GetContentSource with "HostDetails" will ensure $xSSA._ContentSourceUniqueHosts is populated
		$uniqueHosts = $($targetSSA._GetContentSource("*",$true,$false,"HostDetails")).StartAddresses.Authority | SELECT -Unique
		
		foreach ($crawler in $($targetSSA._GetCC())) {
			$srxServer = $targetSSA._GetServer($crawler.ServerName, $true)
			if ($global:SRxEnv.h.isUnknownOrNull($srxServer.Cores)) {
				$crawler | Set-SRxCustomProperty "_Cores" 'unknown'
				$crawler | Set-SRxCustomProperty "_MaxThreads"			'unknown'
				$crawler | Set-SRxCustomProperty "_MaxThreadsPerHost"	'unknown'
			} else {
				$crawler | Set-SRxCustomProperty "_Cores" $($srxServer.Cores | Measure -Sum).Sum
				$crawler | Set-SRxCustomProperty "_ThreadsPerHost" $(New-Object System.Collections.ArrayList)
		
				switch ($perfLevel) {
					"Reduced" { 
						$crawler | Set-SRxCustomProperty "_MaxThreads"			1
						$crawler | Set-SRxCustomProperty "_MaxThreadsPerHost"	1
					} 
					"PartlyReduced" { 
						if (($crawler._Cores * 16) -gt 256) { 
							$crawler | Set-SRxCustomProperty "_MaxThreads" 256
						} else {
							$crawler | Set-SRxCustomProperty "_MaxThreads" $($crawler._Cores * 16)
						}
						$crawler | Set-SRxCustomProperty "_MaxThreadsPerHost" $($crawler._Cores + 8)
					} 
					"Maximum" {
						if (($crawler._Cores * 32) -gt 256) { 
							$crawler | Set-SRxCustomProperty "_MaxThreads" 256
						} else {
							$crawler | Set-SRxCustomProperty "_MaxThreads" $($crawler._Cores * 32)
						}
						$crawler | Set-SRxCustomProperty "_MaxThreadsPerHost" $($crawler._Cores + 8)
					}
			 	}

				#Add this to the SRx Server object as well...
				$srxServer | Set-SRxCustomProperty "maxGathererThreads"			$crawler._MaxThreads
				$srxServer | Set-SRxCustomProperty "maxGathererThreadsPerHost"	$crawler._MaxThreadsPerHost

				#toDo: temporarily cache this during the enable and reuse for each CC with same number of cores
				foreach ($hostUrl in $uniqueHosts) {
					$ssaHostReport = $targetSSA._ContentSourceUniqueHosts | Where {$_.Host -eq $hostUrl}
					if (-not $($ssaHostReport.ImpactHitRate)) {
						$impactRule = $(Get-SPEnterpriseSearchSiteHitRule $hostUrl -ErrorAction Ignore)
						$ssaHostReport | Set-SRxCustomProperty "ImpactHitRate" $impactRule.hitRate
					}
					$ccHostReport = New-Object PSObject -Property @{
						"Host" = $hostUrl;
						"MaxThreads" = $(
							if ($ssaHostReport.ImpactHitRate) { $ssaHostReport.ImpactHitRate }
							else { $crawler._MaxThreadsPerHost } 
						);
					}
					$crawler._ThreadsPerHost.Add($ccHostReport) | Out-Null
				}
			}
		}
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Built thread report..." } ) | Out-Null }
        $targetSSA | Set-SRxCustomProperty "_hasSRxCrawlDiagnosticsEx" $true
	}

	$targetSSA | Add-Member -Force ScriptProperty -Name "_CrawlLog" -Value { $(New-Object Microsoft.Office.Server.Search.Administration.CrawlLog $this) }
	$targetSSA | Set-SRxCustomProperty "_hasSRxCrawlDiagnostics" $true

	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Ending $moduleMsgPrefix" } ) | Out-Null }
	return $targetSSA
}

function Get-SRxCrawlReports {
<#
.SYNOPSIS
	Builds SRx Health Report for analysis and troubleshooting the SharePoint Search 2013 Crawls
	
.DESCRIPTION
	
.INPUTS
	$SSA [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]

.OUTPUTS
	Formatted Report
#>

[CmdletBinding()]
param ( 
  		[parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
			[alias("SearchServiceApplication")]$SSA,
		[alias("ThreadReport")][switch]$IncludeThreadReport,
		[alias("Extended")][switch]$ExtendedObjects	

	)
	#== Variables ===
	$moduleMsgPrefix = "[Get-SRxCrawlReports]"

	#== Ensure the [target]SSA has the extened crawl diagnostic properties ===
	$targetSSA = Enable-SRxCrawlDiag -SSA $SSA -ThreadReport:$IncludeThreadReport -Extended:$ExtendedObjects
	
	if (($targetSSA -eq $null) -or (-not $targetSSA._hasSRxCrawlDiagnostics)) {  
		Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Missing Prerequisite: No `$SSA specified as an argument")
		return $null
	}
	
	$targetSSA._GetCC() | 
		foreach { 
			$services = $targetSSA._GetServer($_.ServerName).GetServices(); 
			$_
		} | ft -auto ServerName, Name,
			@{l='State'; 		e={$_._LegacyState}},
			@{l='Desired';		e={$_._LegacyDesiredState}},
			@{l='SPTimerV4';	e={$($services | ? {$_.Name -eq "SPTimerV4"}).Status}},
			@{l='SPAdminV4';	e={$($services | ? {$_.Name -eq "SPAdminV4"}).Status}},
			@{l='OSearch15';	e={$($services | ? {$_.Name -eq "OSearch15"}).Status}}

	$targetSSA._ShowRecentCrawlVisualization(2,1)
	$targetSSA._QueryMSSCrawlComponentsState()
	$targetSSA._ContentSourceUniqueHosts | ft -auto
	
}

function Get-SRxContentSourceReport {
<#
.SYNOPSIS
	Builds SRx Health Report for analysis and troubleshooting the SharePoint Search 2013 Content Sources
		
.DESCRIPTION

.INPUTS
	$SSA [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]

.OUTPUTS
	Formatted Report
#>

[CmdletBinding()]
param ( 
  		[parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
			[alias("Source","cID","Name")]$ContentSource,
  		[parameter(Mandatory=$false,ValueFromPipeline=$false)]
			[alias("SearchServiceApplication")]$SSA,
		[alias("AsObject")][switch]$ReturnObjectWithoutReport,
	
		#Logical parameter set "ExtendedContentSource" 
			[alias("Extended")][switch]$ExtendedObjects,

		#Logical parameter set "GetCrawledUrls"
			[alias("CrawlLog")][switch]$GetCrawledUrls,
			[alias("Limit")][int32]$MaxRowsToRetrieve = 1000000,
			[alias("Start")][datetime]$StartTime = [datetime]::minvalue,
			[alias("End")][datetime]$EndTime = [datetime]::maxvalue,
			[ValidateSet("All","Successes","Warnings","Errors","Deleted","TopLevelErrors")] 
				[alias("Level")][String]$ErrorLevel = "All",
			[alias("CSV")][switch]$ExportCSV
			
	)
	BEGIN { 		
		#== Variables ===
		$moduleMsgPrefix = "[Get-SRxContentSourceReport]"

		if ($global:SRxEnv.DebugTimings -is [hashtable]) { 
			$TrackDebugTimings = $true
			$global:SRxEnv.DebugTimings[$moduleMsgPrefix] = $(New-Object System.Collections.ArrayList)
			$global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Beginning $moduleMsgPrefix..." } ) | Out-Null
		}
	
		#== Ensure the [target]SSA has the extened crawl diagnostic properties ===
		Write-SRx VERBOSE $($moduleMsgPrefix + " Ensuring `$xSSA has extended Crawl Diagnostics...")
		$targetSSA = Enable-SRxCrawlDiag -SSA $SSA
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded `$xSSA..." } ) | Out-Null }
		Write-SRx VERBOSE $($moduleMsgPrefix + " Loaded `$xSSA...")
		
		if (($targetSSA -eq $null) -or (-not $targetSSA._hasSRxCrawlReports)) {  
			Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Missing Prerequisite: No `$SSA specified as an argument")
			return $null
		}
	
		if ($GetCrawledUrls -and (-not $ExportCSV)) {
			Write-SRx VERBOSE $($moduleMsgPrefix + " Caching Crawl Error messages")
			$cachedMessages = Join-Path $global:SRxEnv.Paths.TSQL "Search\AdminDB\cached\MSSCrawlErrorList.csv"
			$CrawlLogMessages = Import-Csv $cachedMessages
		}
	
		#== Create the result set (e.g. for handling pipelined input)
		$results = New-Object System.Collections.ArrayList
	} 
	
	
	PROCESS {	
		if ($ContentSource -isNot [Microsoft.Office.Server.Search.Administration.ContentSource]) {
			$targetContentSource = $ContentSource
			if ($ExtendedObjects) { 
				$ContentSource = $targetSSA._GetContentSourceEx($targetContentSource)
			} else {
				$ContentSource = $targetSSA._GetContentSource($targetContentSource)
			}	
		}
		Write-SRx VERBOSE $($moduleMsgPrefix + " Using content source: " + $contentSource.Name)
		
		if ($GetCrawledUrls) {
			Write-SRx VERBOSE $($moduleMsgPrefix + " Getting Crawled URLs from the CrawlLog object")
			$errorLevelId = $( switch ($ErrorLevel) { 
				"All"				{ -1; break }	# -1 Do not filter by error level. 
				"Successes"			{  0; break }	#  0 Return only successfully crawled URLs.
				"Warnings"			{  1; break }	#  1 Return URLs that generated a warning when crawled.
				"Errors"			{  2; break }	#  2 Return URLs that generated an error when crawled.
				"Deleted"			{  3; break }	#  3 Return URLs that have been deleted.
				"TopLevelErrors" 	{  4; break }	#  4 Return URLs that generated a top level error.
			})
			
			$omCrawledUrls = $targetSSA._CrawlLog.GetCrawledUrls($false,$MaxRowsToRetrieve,"",$false,$contentSource.id,$errorLevelId,-1,$StartTime,$EndTime)
			if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = $("Retrieved Crawled URLs from the CrawlLog object [" + $contentSource.Name + "]") } ) | Out-Null }
			
			if ($ExportCSV) {
			    $timestamp = $(Get-Date -format "yyyyMMdd_HHmmss")
    			$csvOutFileName = "CS" + $ContentSource.Id + "-CrawlLog-" + $ErrorLevel + "-" + $timestamp + ".csv"
				$csvOutPath = Join-Path $global:SRxEnv.Paths.Log "CrawlLog"
				if (-not (Test-Path $csvOutPath)) { 
					New-Item -path $csvOutPath -ItemType Directory | Out-Null
				}
				$csvOutPath = Join-Path $csvOutPath $csvOutFileName
				
				Write-SRx INFO $("[" + $contentSource.Name + "] Writing results to: ") -ForegroundColor DarkCyan -NoNewline
				Write-SRx INFO $csvOutPath			
				
				$omCrawledUrls | Export-Csv -Path $csvOutPath -Encoding ascii -NoTypeInformation				
				$results.Add($omCrawledUrls) | Out-Null 
				
				if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = $("Exported Crawled URLs to CSV [" + $contentSource.Name + "]") } ) | Out-Null }
			} else {
				Write-SRx INFO $("[" + $contentSource.Name + "] Grouping\Counting each Crawled URL...")
				$itemsByErrorId = $omCrawledUrls | Group-Object -Property ErrorId | Sort-Object Count -Descending | SELECT @{l='ErrorId';e={$_.Name}}, Count			
					
				$report = $(New-Object System.Collections.ArrayList)
				foreach ($i in $itemsByErrorId) { 
					$report.Add( $($i | SELECT ErrorId,Count, 
											@{l='Message';e={$($CrawlLogMessages | ? {$_.ErrorId.ToString() -eq $i.ErrorId}).ErrorMsg}}, 
											@{l='csID';e={$($contentSource.Id)}} ) 
								) | Out-Null
				}
				
				if ($ReturnObjectWithoutReport) { $results.Add($report) | Out-Null }
				else { $report | ft -autosize }
				
				if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = $("Summarized Crawled URLs [" + $contentSource.Name + "]") } ) | Out-Null }
			}
		} else {
			if ($ReturnObjectWithoutReport) { $results.Add($ContentSource) | Out-Null }
			else { $ContentSource | select * }
			
			if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = $("Returned Content Source [" + $contentSource.Name + "]") } ) | Out-Null }
		}		
	}
	
	END {
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Ending $moduleMsgPrefix" } ) | Out-Null }
		
		if ($ReturnObjectWithoutReport) { return $results }
	}
}


# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB8hISNnsO1cEJu
# P2AB8h7Y0IxIXNF/KgI3oZjUmTMBaKCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# fDCCFngCAQEwgZUwfjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAA
# AI6HkaRXGl/KPgAAAAAAjjANBglghkgBZQMEAgEFAKCCAWkwGQYJKoZIhvcNAQkD
# MQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJ
# KoZIhvcNAQkEMSIEIKUmefqzx/u9ZlSPx6l8ZLwT685zITnUzj44fowOSO5yMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAGmdntkn2UwHXkLTPQMcvOcb
# 941pl29hzQEvwvF+yD1tFT/hI8lIPq9NbLc/L3bQ7hgrWfzt4ZUQ8QBxUIKlt0Hp
# dhwy7i9FAH9dju4a2nZvCo2FQu5iu6PVFB9vRQvrbVZH78BXH4yjdxv6JdgsjbVB
# RG0ZOqWMedbrexcgpH3FV1l6BiFRKGeND5TkWseNx7cAE9vmBuOWsndan+t1x6lJ
# BTcRJqNAqa4McChZzTuAzOgE1eEbN5HPz+QZtrEsi+K/RTkSBuRbKx8D4mZ4BVfT
# Q4n43bPob0o1YlHne2qtDao5wFV78kA+67k0TBEYA9Wq3/9xOAQUOaBjP9aFaEih
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQg8IRAvUxWyysuxySU75TD
# cTEQKHyzxlKz5hEg93rnY9MCBljVN9c/TRgTMjAxNzA0MjYyMzU0MDMuNjQ5WjAH
# AgEBgAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkIx
# QjctRjY3Ri1GRUMyMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
# aWNloIIOzTCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAw
# gYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMT
# KU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEw
# MDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGK
# OiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0Eb
# GpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/
# JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0k
# ZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7l
# msqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlE
# XV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4E
# FgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBD
# AEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZW
# y4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5t
# aWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAt
# MDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0y
# My5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUF
# BwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1
# bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5
# AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohR
# DeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l
# 4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/
# f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WW
# j1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI5
# 7BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1
# gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9Dv
# fYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995yfmFrb3ep
# gcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMu
# Ein1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmK
# LxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu
# 7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNowggPCoAMCAQICEzMAAACx
# cRN533X2NcgAAAAAALEwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU3WhcNMTgwOTA3MTc1NjU3WjCBszEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkIxQjctRjY3Ri1GRUMyMSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAqqQklG1Y1lu8ob0P7deumuRn4JvRi2GErmK94vgb
# nWPmd0j/9arA7539HD1dpG1uhYbmnAxc+qsuvMM0fpEvttTK4lZSU7ss5rJfWmbF
# n/J8kSGI8K9iBaB6hQkJuIX4si9ppNr9R3oZI3HbJ/yRkKUPk4hozpY6CkehRc0/
# Zfu6tQiyqI7mClXYZTXjw+rLsh3/gdBvYDd38zFBllaf+3uimKQgUTXGjbKfqZZk
# 3tEU3ibWVPUxAmmxlG3sWTlXmU31fCw/6TVzGg251lq+Q46OjbeH9vB2TOcqEso4
# Nai3J1CdMAYUdlelVVtgQdIx/c+5Hvrw0Y6W7uGBAWnW5wIDAQABo4IBGzCCARcw
# HQYDVR0OBBYEFE5XPfeLLhRLV7L8Il7Tz7cnRBA7MB8GA1UdIwQYMBaAFNVjOlyK
# MZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3
# LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEu
# Y3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcN
# AQELBQADggEBAHPujfu0W8PBTpjfYaPrAKIBLKcljT4+YnWbbgGvmXU8OvIUDBkk
# v8gNGGHRO5DSySaCARIzgn2yIheAqh6GwM2yKrfb4eVCYPe1CTlCseS5TOv+Tn/9
# 5mXj+NxTqvuNmrhgCVr0CQ7b3xoKcwDcQbg7TmerDgbIv2k7cEqbYbU/B3MtSX8Z
# jjf0ZngdKoX0JYkAEDbZchOrRiUtDJItegPKZPf6CjeHYjrmKwvTOVCzv3lW0uyh
# 1yb/ODeRH+VqENSHCboFiEiq9KpKMOpek1VvQhmI2KbTlRvK869gj1NwuUHH8c3W
# Xu4A0X1+CBmU8t0gvd/fFlQvw04veKWh986hggN2MIICXgIBATCB46GBuaSBtjCB
# szELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxME
# TU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkIxQjctRjY3Ri1GRUMyMSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4D
# AhoFAAMVADq635MoZeR60+ej9uKnRG5YqlPSoIHCMIG/pIG8MIG5MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYD
# VQQLEx5uQ2lwaGVyIE5UUyBFU046NERFOS0wQzVFLTNFMDkxKzApBgNVBAMTIk1p
# Y3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQAC
# BQDcq0/xMCIYDzIwMTcwNDI2MTY1NzIxWhgPMjAxNzA0MjcxNjU3MjFaMHQwOgYK
# KwYBBAGEWQoEATEsMCowCgIFANyrT/ECAQAwBwIBAAICGrMwBwIBAAICG1wwCgIF
# ANysoXECAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQAC
# AxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEAUtLxgsP6xHmVydla
# ZH/QcJV9sqBtqvZnvnCs5CShOY2gLfVYBTUNcl/ESV5GDUemMhod1pQwGTM56Kbw
# AYTUS4GHseL1hR5lxkoZJ9+EcWWN/D47mAb7ayUXz+Qw/8wxBbm9UdYS8TUTVZFn
# OYdzYV2V75YLAUwF9jRUTxbujJiHkv51hcRHfqikbbT0My6kv2qWaBv4JS2xubn4
# Da+T1U35MZpl4slIKr46u5MVM2qs6KeHWUknm1oXwD8Xt4zydqS6YYqphJEMrrjj
# G91A2btCMJNJ5EIDuOSPn0RBE03doKd1YezMDXzhWSm6IgXtrKLPIqSfiXKQdvGf
# SO8tCTGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAAsXETed919jXIAAAAAACxMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIPQ9XVLeDwXbSqYE
# XXVlWjBykA6oQgUPq+Yhu/6mBqUEMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUOrrfkyhl5HrT56P24qdEbliqU9IwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAALFxE3nfdfY1yAAAAAAAsTAWBBRXV36EgLDB2SYu
# /HDV85RhGvEqDzANBgkqhkiG9w0BAQsFAASCAQCKskwyFBNXQXiiCm0J61d1Yor3
# nEL5irQgIT5q3w1tAitO/PNbIEaUQ7SXWCjhNpYtJfc+tUX+1x+QC8NcuToKTIgm
# 6if2pqvDqqeNUuIN1HIsP9sjf326S3mUtExYoiViOTMgsJXtUi8TfkJY7d1OjKLc
# Aoc8tRgIeqyhaeuFLNOgPmdZBxwK1ybc//3vt5jQ0gfKBq1UUnicmJtrmG9brKYC
# ic5vmW8syB7Icj5gIqH79jYxNWUZWGyri1wO7fAWCSxXdej6N9+3d1C+paSvwSlV
# oPhwP9VADR5qvrB8bcYQ/8+fYPbH6SbHxS26FW3sVHvuMr7W8+OKIFFY5mCg
# SIG # End signature block
