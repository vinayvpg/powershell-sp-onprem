#=============================================
# Project		: Search Health Reports (SRx)
#---------------------------------------------
# File Name 	: Enable-SRxIndexDiag.psm1
# Author		: Brian Pendergrass
# Contributors	: Dan Pandre, Eric Dixon	
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

function Enable-SRxIndexDiag {
<#
.SYNOPSIS
	Enables detailed methods and properties relating to Search Index diagnostics

.DESCRIPTION
	This Enable-SRxIndexDiag enables all of the methods and properties used
	by the Get-SRxIndexReports module

.INPUTS
	$SSA [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]

.OUTPUTS
	$xSSA (with Index Diagnostic methods/properties)

.EXAMPLE
	$xSSA | Enable-SRxIndexDiag 
	Extends the $xSSA with the core Index Diagnostic methods/properties

.EXAMPLE
	$xSSA | Enable-SRxIndexDiag -DiskReport
	Extends the $xSSA with the core Index Diagnostic methods/properties and generates 
	a new Disk Report for each Index replica (*assuming it is accessible)
#>

[CmdletBinding()]
param ( 
  		[parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
			[alias("SearchServiceApplication")]$SSA = $xSSA,
		[alias("DiskReport")][switch]$IncludeDiskReport,
		[alias("Extended")][switch]$ExtendedObjects
	)
	#== Variables ===
	$moduleMsgPrefix = "[Enable-SRxIndexDiag]"	
	
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
    } elseif ($targetSSA.CloudIndex) { 
        Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " This module does not apply to a Cloud SSA")
		return $targetSSA
    }
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded `$xSSA..." } ) | Out-Null }

	$ssaStatusInfo = $targetSSA._GetSearchStatusInfo()
	#-- Extended Methods/Properties: Only added if the $targetSSA is not yet SRx enabled for Index Diagnostics
	if (-not $targetSSA._hasSRxIndexDiagnostics) {
		Write-SRx INFO $(" * " + $moduleMsgPrefix + " Extending `$xSSA...")
		
		if ($global:___SRxCache -isNot [hashtable]) { $global:___SRxCache = @{} }
		if ($global:___SRxCache[$targetSSA.Name] -isNot [hashtable]) { $global:___SRxCache[$targetSSA.Name] = @{} }

		#--- Methods: Visualize Master Merge History ---
		$targetSSA | Add-Member -Force -MemberType ScriptMethod -Name _GetRecentMasterMergeVisualizationData -Value {
			param ([int]$hoursBack = 48, [int]$minutesPerSlice = 1, [string]$endtime=$null)

            if(-not $global:SRxEnv.RemoteUtilities.LogParser.Initialized) {
                Write-SRx ERROR "LogParser not initialized."
                return
            }

            $indexers = New-Object System.Collections.ArrayList
            if([string]::IsNullOrWhiteSpace($endtime)){
                $endTimeObj = Get-Date
            } else {
                $endTimeObj = Get-Date $endtime
            }

            # get the files with our matches on -Filter
            if($global:SRxEnv.Product -eq "SP2013"){
                $files = $xssa._Servers | ? {$_.hasIndexer -and $_.canPing()} | Invoke-SRxULSLogParser -Filter "EventID='acdru'" -OutputParams @("Timestamp","Message") -HoursBack $hoursBack -EndTime $endTimeObj
            }
            elseif($global:SRxEnv.Product -eq "SP2016"){
                $files = $xssa._Servers | ? {$_.hasIndexer -and $_.canPing()} | Invoke-SRxULSLogParser -Filter "EventID='amtqx'" -OutputParams @("Timestamp","Message") -HoursBack $hoursBack -EndTime $endTimeObj
            } else {
                Write-SRx ERROR "The Product '$($global:SRxEnv.Product)' is not supported for this operation."
                return
            }
         
            Write-SRx INFO "[GetRecentMasterMergeVisualizationData] Parsing gathered files..."
            $files.FullName | Import-Csv -Delimiter "`t" | % {
                # for each file parse the 'Message' for time in seconds, type and component
                $matched = $_.Message -match "^(?<type>.*?)\s"
                if($matched){
                    $type = $matches['type']
                }
                if($type -ne "%default") {
                    return
                }

                if($global:SRxEnv.Product -eq "SP2013"){
                    #   12/01/2016 08:57:05.59	%default MergeSet[IndexComponent1-aaaaedc2-86d0-4d11-870c-4a8dcad3e1dc-SPb1be265d7dbf.I.0.0](E5D7143C-0FC2-4484-A1C2-8B9E5AECBCEF) MergeId:0x00000021. Master merge exit after 188 ms (0:00:00.000)  [merge.cxx:1192]  search\foundation\searchcore\fastserver\fastserver\src\merge\merge.cxx	
                    $matched = $_.Message -match ".*ms \((?<timespan>.*?)\)"
                }
                elseif($global:SRxEnv.Product -eq "SP2016"){
                    # 01/06/2017 01:23:38.40	Microsoft.Ceres.SearchCore.Indexes.FastServerIndex.Merger.MergeJob: Master merge ended after 01:05:17.2498049: MergeJob[Group=%default,Type=master,Level=5,Target=a7c7170f-c7a9-4471-b894-f6e151a7c04d,Sources=Id: b4515dd5-0b02-4bc8-afb1-b6bc9da751c2, TotalDocs: 385264, RemainingSize: 385264, Id: 4e6b73fa-09ae-4e1b-bce9-63d13d07026d, TotalDocs: 338648, RemainingSize: 338640, Id: 9ce0384a-a2d0-4b35-83ca-dca9ea6a3f7e, TotalDocs: 294973, RemainingSize: 294973, TotalMergeSize: 1018877, CorrelationId: 078803ad-b1f8-441e-aef6-2d6a02ff0e37].
                    $matched = $_.Message -match ".*ended after (?<timespan>.*?)\: MergeJob"
                } else {
                    Write-SRx ERROR "The Product '$($global:SRxEnv.Product)' is not supported for this operation."
                    return
                }
                if($matched){
                    $matched = $matches['timespan'] -match "^(?<hours>\d*)\:(?<mins>\d*)\:(?<secs>\d*)\.(?<milli>\d*)$"
                    if($matched){
                        $seconds = ([int]$matches['hours'] * 60 * 60) + ([int]$matches['mins'] * 60) + [int]$matches['secs'] + $(if($matches['milli'] -gt 500){1}else{0})
                    }
                }
                # if seconds equal 0, continue
                if($seconds -eq 0){
                    return
                }
                $matched = $_.Message -match ".*MergeSet\[(?<component>.*?)-"
                if($matched){
                    $component = $matches['component']
                }
                # store time stamp temporarily in 'd'
                $count = [int]($seconds/($minutesPerSlice*60))
                # round count up to 1 if necessary
                if($count -eq 0){$count=1}
                $dataObj = @{count=$count;type=$type;d=$(Get-Date $_.Timestamp)}
                $componentObj = $indexers | ? { $_.Name -eq $component}
                if($componentObj -eq $null){
                    # create the first one
                    $componentObj = @{Name=$component;DataSet=$(New-Object System.Collections.ArrayList)}
                    $indexers.Add($componentObj) | Out-Null
                }

                $o = $componentObj.DataSet[-1]
                if($o -eq $null){
                    # get timestamp for the idle time, for first one
                    $d = $endTimeObj.AddHours(-$hoursBack)
                } else {
                    # get timestamp for the idle time, using the previous span
                    $d = $o.d
                    # clean up 'd'
                    $o.Remove('d')
                }
                if($d -lt $dataObj.d.AddMinutes(-$dataObj.Count)) {
                    # add the idle span and the span for the type in dataObj
                    $idle = @{count=[int](New-TimeSpan $d $dataObj.d.AddMinutes(-$dataObj.Count)).TotalMinutes;type="idle"}
                    # the visualization graph looks best when drawing 2879 minutes and not 48*60 = 2880
                    $idle.Count -= 1
                    $componentObj.DataSet.Add($idle) | Out-Null
                    $componentObj.DataSet.Add($dataObj) | Out-Null
                 } else {
                    # the visualization graph looks best when drawing 2879 minutes and not 48*60 = 2880
                    $dataObj.Count -= 1
                    $componentObj.DataSet.Add($dataObj) | Out-Null
                 }
            }

            # finally, add ending idle spans and clean up last timestamps in 'd'
            $indexers | %{
                $o = $_.DataSet[-1]
                if($o -eq $null){
                    # get timestamp for the idle time, for first one
                    $d = $endTimeObj.AddHours(-$hoursBack)
                } else {
                    # get timestamp for the idle time, using the previous span
                    $d = $o.d
                    # clean up 'd'
                    $o.Remove('d')
                }
                $idle = @{count=[int](New-TimeSpan $d $endTimeObj).TotalMinutes;type="idle"}
                $_.DataSet.Add($idle) | Out-Null
            }


			$reportTime = $global:SRxEnv.h.GetDiscreteTime( $($endTimeObj).ToUniversalTime(), $minutesPerSlice )
			$windowOpen = $global:SRxEnv.h.GetDiscreteTime( $($reportTime).AddHours( (-1) * $hoursBack ), $minutesPerSlice )
			$mmReport = $(New-Object PSObject -Property @{
				"minutesPerSlice" = $minutesPerSlice;
				"reportTime" = $reportTime;
				"windowOpen" = $windowOpen;
				"totalMinutes" = $(New-TimeSpan $windowOpen $reportTime).TotalMinutes;
				"maxTimeSlices" = [int]$([math]::Round( $(New-TimeSpan $windowOpen $reportTime).TotalMinutes / $minutesPerSlice ));
				#"incompleteDataSet" = ($candidates.Count -eq $queryLimit); #we likely hit the upper bound
				"values" = $indexers;
			})
            Write-SRx INFO "[GetRecentMasterMergeVisualizationData] Done parsing files."

            return $mmReport
        }

		#--- Methods: Get Index Components by state ---
		$targetSSA | Add-Member -Force ScriptMethod -Name _GetAdminReport  -Value {
			#== Has dependency on this System Manager (e.g. system status)
			$primary = $this._GetPrimaryAdminComponent()
            if ($primary) {
                return $primary._GetHealthReport()
            } else { 'Unknown' } 
		}

		$targetSSA | Add-Member -Force ScriptMethod -Name _GetIndexServerReport  -Value {
			$this._GetIndexer() | foreach {
				if (-not $_._hasSRxDiskReport) { $($_._BuildDiskReportData()) | Out-Null }
			}
			
			$this._GetIndexer() | Where {$_._hasSRxDiskReport} |
				Group ServerName, _DriveLetter |
				foreach { 
					$serverReport = New-Object PSObject -Property @{
						"ServerName" = $_.Group[0].ServerName;
						"_DriveLetter" = $_.Group[0]._DriveLetter;
					}
					$serverReport | Add-Member "_Capacity"					$($_.Group._Capacity | Where {(-not $global:SRxEnv.h.isUnknownOrNull($_))} | Sort -Descending | SELECT -First 1)
					$serverReport | Add-Member "_FileSizeSum"				$($_.Group._FileSize | Where {(-not $global:SRxEnv.h.isUnknownOrNull($_))} | Measure-Object -Sum).Sum
                    $serverReport | Add-Member "_MMEstSum"				    $($_.Group._EstimatedMMTotalFileSize | Where {(-not $global:SRxEnv.h.isUnknownOrNull($_))} | Measure-Object -Sum).Sum
                    $serverReport | Add-Member "_MMPendingSum"			    $($_.Group._EstimatedMMPendingGrowth | Where {(-not $global:SRxEnv.h.isUnknownOrNull($_))} | Measure-Object -Sum).Sum
					$serverReport | Add-Member "_FreeSpace"					$($_.Group._FreeSpace | Where {(-not $global:SRxEnv.h.isUnknownOrNull($_))} | Sort -Descending | SELECT -First 1)
					$serverReport | Add-Member "_TotalPctMMToFree"			$(
                        if ((-not ($global:SRxEnv.h.isUnknownOrZero($serverReport._MMPendingSum))) -and (-not ($global:SRxEnv.h.isUnknownOrZero($serverReport._FreeSpace)))) {
                            ([decimal]::Round( $( $serverReport._MMPendingSum / $serverReport._FreeSpace), 4)) * 100
                        }
                    )
					$serverReport | Add-Member "_UnreachableVolumeInfo"		$($status = $false; $_.Group._UnreachableVolumeInfo | foreach {$status = $($status -or $_)}; $status)
					$serverReport | Add-Member "_UnreachableFilePath"		$($status = $false; $_.Group._UnreachableFilePath | foreach {$status = $($status -or $_)}; $status)
					$serverReport | Add-Member "IndexerSummary"  $(New-Object System.Collections.ArrayList)
					
					if ($_.Group[0]._IndexersOnSameVolume) {
						$tmpIndexerList = $_.Group[0]._IndexersOnSameVolume
					} else {
						$tmpIndexerList = @( $_.Group[0].Name )
					}
					
					foreach ($indexerName in $tmpIndexerList) {
						$idx = $this._GetIndexer($indexerName)
						$serverReport.IndexerSummary.Add(  $(New-Object PSObject -Property @{
							"Name"		 = $idx.Name;
							"_CellName"	 = $idx._CellName;
							"_Partition" = $idx._Partition;
							"_FileSize"  = $idx._FileSize;
							"_CellPath"	 = $idx._CellPath;						
						}) ) | Out-Null
					}
					$serverReport
				}
		}

        $targetSSA | Add-Member -Force ScriptMethod -Name _GetMMTriggerCheck -Value {
            Write-SRx INFO ("~~~[`$xSSA._GetMMTriggerCheck] This method has not yet been implemented... ")
            #param ([bool]$bypassCache = $false)

            #$ttl = $global:SRxEnv.MMTriggerCheckCacheTTL 
            #if ((-not $global:SRxEnv.h.isNumeric($ttl)) -or ($ttl -le 0)) { 
            #	$ttl = 15 #minutes
            #}

            #if ((-not $bypassCache) -and ($global:___SRxCache[$this.Name].MasterMergeTrigger -ne $null)) {
            #	$timeOfLastReport = $($global:___SRxCache[$this.Name].MasterMergeTrigger.Keys)[0]
            #	$reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalMinutes
	
            #	if ($reportAge -lt $ttl) {
            #		$mmTriggerReport = $global:___SRxCache[$this.Name].MasterMergeTrigger[$timeOfLastReport]
            #        Write-SRx INFO $("--[GetMMTriggerCheck] Using cache until " + $(Get-Date).AddMinutes($ttl - $reportAge)) -ForegroundColor Cyan
            #		return $mmTriggerReport
            #	}
            #} 

            #$mergeTriggerWindow = $(Get-Date).AddMinutes((-1) * $ttl)  
            #$ulsActionAbbrev = "MMTrigger"

            #if (-not $bypassCache) {
            #    $mergedLogFilePath = Get-SRxRecentULSExport $mergeTriggerWindow $ulsActionAbbrev
            #}
            #if ($mergedLogFilePath -eq $null) {
            #	$mergedLogFilePath = Get-SRxMergeULSbyEvent $mergeTriggerWindow.AddMinutes(-2) $ulsActionAbbrev @("aie8k","aie8l")
            #}

            ##$mergedLogFilePath could still be null if the merge-splogfile gets 0 results...
            #if (($mergedLogFilePath -ne $null) -and (Test-Path $mergedLogFilePath)) {
            #	Write-SRx VERBOSE ("Parsing log file: " + $mergedLogFilePath)
            #	$parsedULSObjects = gc $mergedLogFilePath | 
            #                    foreach {[regex]::match($_,"(.*)OWSTIMER.*(IndexComponent\d+).*\) (.*), total=(\d+), master=(\d+), ratio=(\d+.\d+%), targetRatio=(\d+%)")} |
            #	                where {$_.Success} | foreach { 
            #		                New-Object PSObject -Property @{
            #			                Time = [datetime]$_.groups[1].value;
            #			                Component = $_.groups[2].value;
            #			                UpdateGroup = $_.groups[3].value;
            #			                Total = [int]$_.groups[4].value;
            #			                Master = [int]$_.groups[5].value;
            #			                Ratio = $_.groups[6].value;
            #			                TargetRatio = $_.groups[7].value;
            #		                }
            #	                }
                
            #    if ($parsedULSObjects.Count -gt 0) {
            #        $mostRecentCheck = $($parsedULSObjects | Sort Time -Descending | SELECT -first 1).Time
            #        #To avoid duplicates, only use the events beyond 10 minutes of the most recent system check (which occur every 15 minutes)
            #	    $results = $($parsedULSObjects | Sort Time -Descending | Where {$_.Time -ge $mostRecentCheck.AddMinutes(-10)})
            #    }
            #}

            #if ($results -ne $null) {
            #	#then cache this result set with the $mostRecentCheck time as the key
            #    Write-SRx VERBOSE ("Master Merge most recently checked by system: " + $mostRecentCheck)
            #	$global:___SRxCache[$this.Name].MasterMergeTrigger = @{ $mostRecentCheck = $results }
            #} else {
            #    $results = @()
            #}
            #return $results
        }

		#--- Properties: Index Component ---		
		if (-not $global:SRxEnv.h.isUnknownOrNull($ssaStatusInfo)) {
			$targetSSA | Set-SRxCustomProperty "_IndexSystem" $($targetSSA._GetAdminReport() | 
                Where {(-not $global:SRxEnv.h.isUnknownOrNull($_)) -and ($_.Name.StartsWith("active_index"))} | 
                foreach {$_.Name -replace '.*\[(.*)\]','$1'})
		}
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Called `$xSSA._GetSearchStatusInfo()..." } ) | Out-Null }
	}
		
	if ($ExtendedObjects -or $IncludeDiskReport -or (-not $targetSSA._hasSRxIndexDiagnostics)) {
        foreach ($indexer in $($targetSSA._GetIndexer())) {
			Write-SRx VERBOSE $("    - Extending `$indexer " + $indexer.Name)
            if ($global:___SRxCache[$targetSSA.Name][$indexer.Name] -isNot [hashtable]) { $global:___SRxCache[$targetSSA.Name][$indexer.Name] = @{} }

            if (-not $targetSSA._hasSRxIndexDiagnostics) {
			    Write-SRx DEBUG $(" --> Adding methods to `$indexer " + $indexer.Name)
                #--- Methods: Get Index Reports ---
			    $indexer | Add-Member -Force ScriptMethod -Name _GetCellReport  -Value {
				    $this | Sort _Partition,_CellNumber | 
						    ft -auto ServerName,Name,
									    @{l='Cell';			e={$_._CellName}},
									    @{l='Part';			e={$_._Partition}},
									    @{l='State'; 		e={$_._JunoState}},
									    @{l='Primary';		e={$_._JunoDetails.Primary}},
									    @{l='Generation'; 	e={("{0:N0}" -f$_._Generation)}},
                                        @{l='Docs(+dups)'; 	e={("{0:N0}" -f$_._TotalDocs)}},
									    @{l='Searchable';	e={("{0:N0}" -f $_._ActiveDocs)}},
									    @{l='AvgDoc';       e={("{0:N0}" -f ($_._AvgDocSize / 1KB)) + " KB"}},
									    @{l='Merging';		e={$_._MasterMerging}},
									    @{l='CheckpointSize';e={("{0:N0}" -f ($_._CheckpointSize / 1MB)) + " MB"}}
			    }
				
			    $indexer | Add-Member -Force ScriptMethod -Name _BuildDiskReportData  -Value {
				    param ([bool]$bypassCache = $false)
					
				    if ((-not $bypassCache) -and ($global:___SRxCache[$this._ParentSSAName][$this.Name].DiskReport -ne $null)) {
					    $timeOfLastReport = $($global:___SRxCache[$this._ParentSSAName][$this.Name].DiskReport.Keys)[0]
					    $reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
					    if ($reportAge -lt 300) {
						    Write-SRx VERBOSE $("--[`$(" + $this.Name + ")._BuildDiskReportData] Using cache until " + $(Get-Date).AddSeconds(60 - $reportAge)) -ForegroundColor Cyan
						    $diskReport = $global:___SRxCache[$this._ParentSSAName][$this.Name].DiskReport[$timeOfLastReport]
						    return $diskReport
					    }
				    }

				    Write-SRx VERBOSE $("--[`$(" + $this.Name + ")._BuildDiskReportData] Generating fresh data...") -ForegroundColor Cyan
				    try { 
					    Initialize-SRxIndexerDiskReport $this
					    $SizeDecorator = $( if ($this._ActiveDocs -ge 1000000) { "GB" } else { "MB"} )
                        switch ($SizeDecorator) {
                            "KB"    { $sizeDecoratorValue = 1KB; $sizeDecoratorLabel = " KB" }
                            "MB"    { $sizeDecoratorValue = 1MB; $sizeDecoratorLabel = " MB" }
                            default { $sizeDecoratorValue = 1GB; $sizeDecoratorLabel = " GB" }
                        }

                        if ($this._UnreachableVolumeInfo -or $this._UnreachableFilePath) {
                            Write-Warning ("~~~[`$(" + $this.Name + ")._BuildDiskReportData] Unreachable file path or volume info for this cell")
                        } else {
					        $diskReport = $this | Sort _Partition,_CellNumber | 
											        ft -auto ServerName,Name,
											        @{l='Cell';			e={$_._CellName}},
											        @{l='Part';			e={$_._Partition}},
											        @{l='Checkpoint';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._CheckpointSize)) {'Unknown'} else {("{0:N0}" -f ($_._CheckpointSize / $sizeDecoratorValue)) +  $sizeDecoratorLabel} )}},
											        @{l='Index Files';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FileSize)) {'Unknown'} else {("{0:N0}" -f ($_._FileSize / $sizeDecoratorValue)) +  $sizeDecoratorLabel} )}},
											        @{l='MM (Est.)';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._EstimatedMMTotalFileSize)) {''} else {("{0:N0}" -f ($_._EstimatedMMTotalFileSize / $sizeDecoratorValue)) +  $sizeDecoratorLabel} )}},
											        @{l='MM (Pending)';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._EstimatedMMPendingGrowth)) {'Unknown'} else {("{0:N0}" -f ($_._EstimatedMMPendingGrowth / $sizeDecoratorValue)) +  $sizeDecoratorLabel} )}},
											        @{l='Free Space';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FreeSpace)) {'Unknown'} else {("{0:N0}" -f ($_._FreeSpace / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
											        @{l='%(MM/Free)';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._PctMMPendingToFreeSpace)) {'Unknown'} else {("{0:N2}" -f ($_._PctMMPendingToFreeSpace)) +  "%"} ) }}

					        $global:___SRxCache[$this._ParentSSAName][$this.Name].DiskReport = @{ $(Get-Date) = $diskReport } 
					        return $diskReport
                        }
				    } catch {
					    Write-Warning ("~~~[`$(" + $this.Name + ")._BuildDiskReportData] Unable to retrieve disk report information")
					    throw 
				    }
			    }

                Write-SRx DEBUG $(" --> Adding properties to `$indexer " + $indexer.Name)
			    #--- Properties: Index System Name
			    $indexer | Set-SRxCustomProperty "_IndexSystem" $targetSSA._IndexSystem
	
			    #--- Properties: Handling multiple Index Components on the same server and same drive
			    $localIndexers = $($xSSA._Servers | 
				    Where {($_.hasIndexer -gt 1) -and ($_.Name -ieq $indexer.ServerName)}).Components | 
				    Where {$_ -match "IndexComponent"} 

			    if ($localIndexers.Count -gt 1) {
				    $indexer | Set-SRxCustomProperty "_IndexersOnSameServer" 	$localIndexers
					
				    $usesSameDrive = New-Object System.Collections.ArrayList
				    foreach ($idxName in $localIndexers) {
					    if ($idxName -eq $indexer.Name) {
						    $usesSameDrive.Add($idxName) | Out-Null
					    } else {
						    $rootDirForPeerIndexer = ($targetSSA._GetIndexer($idxName)).RootDirectory
						    #if the RootDirectory 
						    if (($rootDirForPeerIndexer -eq $indexer.RootDirectory) -or 
							    (   #neither are null and the first character (e.g. drive letter) is the same 
								    (-not ([string]::IsNullOrEmpty($rootDirForPeerIndexer))) -and 
								    (-not ([string]::IsNullOrEmpty($indexer.RootDirectory))) -and
								    ($rootDirForPeerIndexer[0] -eq $($indexer.RootDirectory)[0])
							    ))
						    {
							    #then these share a common drive path
							    $usesSameDrive.Add($idxName) | Out-Null
						    }
					    }
						
					    if ($usesSameDrive.Count -gt 1) {
						    $indexer | Set-SRxCustomProperty "_IndexersOnSameVolume"	$usesSameDrive
					    }
				    }
			    }
			}

			#-- For this Indexer component, build the reports as applicable
			if ($ExtendedObjects -or $IncludeDiskReport) {
				Write-SRx DEBUG $(" --> Building extended reports for `$indexer " + $indexer.Name)		
                if (-not $indexer._hasSRxDiskReport) { $($indexer._BuildDiskReportData()) | Out-Null }

                if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Called [`$(" + $indexer.Name + ")._BuildDiskReportData]" } ) | Out-Null }
			}			
		}
	}
    if ($ExtendedObjects -or $IncludeDiskReport -or (-not $targetSSA._hasSRxIndexDiagnostics)) {
        $targetSSA | Set-SRxCustomProperty "_hasSRxIndexDiagnostics" $true
        
        $targetSSA | Add-Member -Force ScriptProperty -Name _hasSRxIndexDiskReport	-Value {
		    $ssaHasDiskReports = $true

            $this._GetIndexer() | foreach { 
                if ($global:___SRxCache[$this.Name][$_.Name].DiskReport -ne $null) {
				    $timeOfLastReport = $($global:___SRxCache[$this.Name][$_.Name].DiskReport.Keys)[0]
				    $reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
                    #verify that each report (if it exists) is less than 5 minutes old (300 seconds)
                    $ssaHasDiskReports = $ssaHasDiskReports -and ($reportAge -lt 300)
			    } else { 
                    $ssaHasDiskReports = $false
                }
            }
            return $ssaHasDiskReports
		}
    }
	
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Ending $moduleMsgPrefix" } ) | Out-Null }
	return $targetSSA
}

function Get-SRxIndexReports {
<#
.SYNOPSIS
	Builds SRx Health Report for analysis and troubleshooting the SharePoint Search 2013 Index

.DESCRIPTION
	This Get-SRxIndexReports module can be used to retrieve detailed diagnostic information
	for monitoring and managing both the overall topology of the search system and Search 
	Index states. This provides a broad SSA-level report and component-level reports for 
	each Index replica that is not in an "Unknown" state. 

	This module combines SSA-level reports (e.g. Get-SPEnterpriseSearchStatus), the current 
	topology information, detailed component-level reports, and volume (disk) level info. It
	then reports into a single summary that can be used to check the overall status of the 
	SSA's Search Ondex and helps interpret ULS log events relating to that search index by
	surfacing details such as an Index Component's "cell" name.
	
	This module automatically invokes Enable-SRxIndexDiag if the Index Diagnostic
	methods and properties are not present on the applicable $xSSA 
	
.NOTES
	The underlying core of this report is directly based on the work from Dan Pandre:
	   Monitoring an SSA's index
	   http://social.technet.microsoft.com/wiki/contents/articles/30598.monitoring-an-ssa-s-index.aspx

.INPUTS
	$SSA [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]

.OUTPUTS
	Formatted Report

.EXAMPLE
	$xSSA | Get-SRxIndexReports 
	Generates a simplified report 

.EXAMPLE
	$xSSA | Get-SRxIndexReports -DiskReport
	Generates a detailed report including disk level diagnostics for each Index replica (*assuming it is accessible)
	
#>

[CmdletBinding()]
param ( 
  		[parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
			[alias("SearchServiceApplication")]$SSA,
		[alias("DiskReport")][switch]$IncludeDiskReport,
        [ValidateSet("GB","MB","KB")][String]$SizeDecorator = $( if (($xSSA._Partitions -gt 0) -and (($xSSA._ActiveDocsSum / $xSSA._Partitions) -ge 1000000)) { "GB" } else { "MB"} ),
		[alias("Extended")][switch]$ExtendedObjects	
	)
	#== Variables ===
	$moduleMsgPrefix = "[Get-SRxIndexReports]"
	
	if ($global:SRxEnv.DebugTimings -is [hashtable]) { 
		$TrackDebugTimings = $true
		$global:SRxEnv.DebugTimings[$moduleMsgPrefix] = $(New-Object System.Collections.ArrayList)
		$global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Beginning $moduleMsgPrefix..." } ) | Out-Null
	}
	
	#== Ensure the [target]SSA has the extended index diagnostic properties ===
	Write-SRx VERBOSE $($moduleMsgPrefix + " Ensuring `$xSSA has extended Index Diagnostics...")
	$targetSSA = Enable-SRxIndexDiag -SSA $SSA -DiskReport:$IncludeDiskReport -Extended:$ExtendedObjects	
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Loaded `$xSSA..." } ) | Out-Null }

	#-- toggles visibility of Index Disk Reports (e.g. if cached, show them even if not explicitly requested)
	$displayDiskReport = $IncludeDiskReport -or $ExtendedObjects -or $(($targetSSA._GetIndexer() | Where {$_._hasSRxDiskReport}).count -gt 0)
		
	if ($targetSSA -eq $null) {
		Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " Missing Prerequisite: No `$SSA specified as an argument")
		return $null
	} elseif ($targetSSA.CloudIndex) {
        Write-SRx WARNING $("~~~" + $moduleMsgPrefix + " This report does not apply to a Cloud SSA")
        return $null
    }else {
		Write-SRx
		Write-SRx INFO $('-' * ($targetSSA.Name.length + 28)) -ForegroundColor DarkCyan 
		Write-SRx INFO ("[ " + $targetSSA.Name + " | Constellation: " + $targetSSA._ConstellationID + " ]") -ForegroundColor DarkCyan 
		Write-SRx INFO $('-' * ($targetSSA.Name.length + 28)) -ForegroundColor DarkCyan 
	
		$ssaStatusInfo = $targetSSA._GetSearchStatusInfo()
        switch ($SizeDecorator) {
            "KB"    { $sizeDecoratorValue = 1KB; $sizeDecoratorLabel = " KB" }
            "MB"    { $sizeDecoratorValue = 1MB; $sizeDecoratorLabel = " MB" }
            default { $sizeDecoratorValue = 1GB; $sizeDecoratorLabel = " GB" }
        } 

		if (-not $global:SRxEnv.h.isUnknownOrNull($ssaStatusInfo)) {	
			$targetSSA._GetAdmin() | 
				Sort _isPrimaryAdmin -Descending | 
				ft -auto ServerName, Name,
							@{l='State'; 		e={$_._JunoState}},
							@{l='Primary';		e={$_._isPrimaryAdmin}},			
							@{l='SystemMgr';	e={ $( $_.ServerName -eq $targetSSA.SystemManagerLocations.Host ) }},
							@{l='Legacy Admin';	e={ $( $_.ServerName -eq $targetSSA._LegacyAdmin.ServerName ) }}

			$outputProperties = @("ServerName", "Name",
							@{l='Cell';			e={$_._CellName}},
							@{l='Part';			e={$_._Partition}},
							@{l='State'; 		e={$_._JunoState}},
							@{l='Primary';		e={$_._JunoDetails.Primary}},
							@{l='Generation'; 	e={("{0:N0}" -f$_._Generation)}},
                            @{l='Docs(+dups)'; 	e={("{0:N0}" -f$_._TotalDocs)}},
							@{l='Searchable';	e={("{0:N0}" -f $_._ActiveDocs)}},
							@{l='AvgDoc';       e={("{0:N0}" -f ($_._AvgDocSize / 1KB)) + " KB"}},
							@{l='Merging';		e={$_._MasterMerging}},
							@{l='Checkpoint';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._CheckpointSize)) {'Unknown'} else {("{0:N0}" -f ($_._CheckpointSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}})
			#if ($displayDiskReport) { $outputProperties += @{l='Index Files';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FileSize)) {'Unknown'} else {("{0:N0}" -f ($_._FileSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}} }
			
		    Write-SRx INFO $('--[ Search System Diagnostics') -ForegroundColor DarkCyan 
			$targetSSA._GetIndexer() | 
                Where { $_._JunoState -ne 'Unknown' } |
				Sort _Partition,_CellNumber | 
				ft -auto $outputProperties	
		} else {
			Write-SRx WARNING ("The attempt to retrieve Search Status Info from the System Manager failed...")
		}
		
		$unknownIndexer = $targetSSA._GetIndexer() | Where {$global:SRxEnv.h.isUnknownOrNull($_._JunoState)}
		if (($unknownIndexer).Count -gt 0) {			
			Write-SRx WARNING ("The following components have an `"UNKNOWN`" status:")
			$unknownIndexer | Sort _Partition,_CellNumber |
				ft -AutoSize ServerName, Name, 
								@{l='Cell';	e={$_._CellName}}, 
								@{l='Part';	e={$_._Partition}},
								@{l='Ping';	e={$targetSSA._GetServer($_.ServerName).canPing()}}
		}
		
        Write-SRx INFO $('--[ Master Merge Diagnostics') -ForegroundColor DarkCyan 
		$targetSSA._GetIndexer() | 
            Where {$_._hasSRxDiskReport -and ($_._JunoState -ne 'Unknown')} |
			Sort _Partition,_CellNumber | 
			ft -auto ServerName,Name,
						@{l='Cell';			e={$_._CellName}},
						@{l='Part';			e={$_._Partition}},
						@{l='Checkpoint';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._CheckpointSize)) {'Unknown'} else {("{0:N0}" -f ($_._CheckpointSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
						@{l='Index Files';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FileSize)) {'Unknown'} else {("{0:N0}" -f ($_._FileSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
						@{l='MM (Est.)';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._EstimatedMMTotalFileSize)) {''} else {("{0:N0}" -f ($_._EstimatedMMTotalFileSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
						@{l='MM (Pending)';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._EstimatedMMPendingGrowth)) {'Unknown'} else {("{0:N0}" -f ($_._EstimatedMMPendingGrowth / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
						@{l='Free Space';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FreeSpace)) {'Unknown'} else {("{0:N0}" -f ($_._FreeSpace / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
						@{l='%(MM/Free)';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._PctMMPendingToFreeSpace)) {'Unknown'} else {("{0:N2}" -f ($_._PctMMPendingToFreeSpace)) + "%"} ) }}
		
		$displayMultiplePerVolume = $false
		$targetSSA._GetIndexer() | 
			Where {$_._hasSRxDiskReport -and $_._IndexersOnSameServer -and ($_._JunoState -ne 'Unknown')} | 
			foreach {
				$displayMultiplePerVolume = $displayMultiplePerVolume -or ($_._IndexersOnSameVolume -and ($_._IndexersOnSameVolume.Count -gt 1))
			}
		
        Write-SRx INFO $('--[ Disk Volume Diagnostics') -ForegroundColor DarkCyan	
		if ($displayMultiplePerVolume) {
			$targetSSA._GetIndexServerReport() | 
                Where {(-not $_._UnreachableVolumeInfo) -and (-not $_._UnreachableFilePath)} |
				Sort ServerName, _DriveLetter | 
				foreach {
					$volumeReport = $_ 
					$volumeReport | 
						ft -auto ServerName, 
									@{l='Vol';				e={$_._DriveLetter}},
                                    @{l='Block';			e={$( if($global:SRxEnv.h.isUnknownOrNull($_._BlockSize)) {'Unknown'} else {("{0:N0}" -f ($_._BlockSize / 1KB)) + " KB"} )}},
                                    @{l='Idx';				e={$( if($_._DriveIndexing) {"Yes"} else {"No"} )}},
                                    @{l='Cmp';				e={$( if($_._Compressed) {"Yes"} else {"No"} )}},
									@{l='Capacity';			e={$( if($global:SRxEnv.h.isUnknownOrNull($_._Capacity)) {'Unknown'} else {("{0:N0}" -f ($_._Capacity / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
                    				@{l='Idx Files (Sum)';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FileSizeSum)) {'Unknown'} else {("{0:N0}" -f ($_._FileSizeSum / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
                    			    @{l='Free Space';		e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FreeSpace)) {'Unknown'} else {("{0:N0}" -f ($_._FreeSpace / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}}

					$volumeReport.IndexerSummary | 
						Sort _Partition,_CellNumber | 
						ft -auto @{l=$("--->");Expression={}; Width=4},Name,
								 @{l='Cell';		e={$_._CellName}},
								 @{l='Part';		e={$_._Partition}},
								 @{l='Index Files';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FileSize)) {'Unknown'} else {("{0:N0}" -f ($_._FileSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
								 @{l='Path';		e={$_._CellPath}}
				}
		} else {
			$targetSSA._GetIndexer() | 
                Where {$_._hasSRxDiskReport -and (-not $_._UnreachableVolumeInfo) -and (-not $_._UnreachableFilePath)} |
				Sort _Partition,_CellNumber | 
				ft -auto ServerName,Name,
							@{l='Cell';			e={$_._CellName}},
							@{l='Part';			e={$_._Partition}},
							@{l='Vol';			e={$_._DriveLetter}},
                            @{l='Block';		e={$( if($global:SRxEnv.h.isUnknownOrNull($_._BlockSize)) {'Unknown'} else {("{0:N0}" -f ($_._BlockSize / 1KB)) + " KB"} )}},
                            @{l='Idx';			e={$( if($_._DriveIndexing) {"Yes"} else {"No"} )}},
                            @{l='Cmp';			e={$( if($_._Compressed) {"Yes"} else {"No"} )}},
							@{l='Capacity';		e={$( if($global:SRxEnv.h.isUnknownOrNull($_._Capacity)) {'Unknown'} else {("{0:N0}" -f ($_._Capacity / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
							@{l='Index Files';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FileSize)) {'Unknown'} else {("{0:N0}" -f ($_._FileSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
							@{l='Path';			e={$_._CellPath}}
		}
		
		$unknownDiskInfo = $targetSSA._GetIndexer() | Where {$_._hasSRxDiskReport -and ($_._UnreachableVolumeInfo -or $_._UnreachableFilePath)}
		if (($unknownDiskInfo).Count -gt 0) {			
			Write-SRx WARNING ("The following servers/components have an underlying disk issue preventing a complete report:")
			$unknownDiskInfo | Sort ServerName, _DriveLetter | 
				ft -auto ServerName,Name,
					@{l='Cell';			e={$_._CellName}},
					@{l='Part';			e={$_._Partition}},
					@{l='Ping';			e={$targetSSA._GetServer($_.ServerName).canPing()}},
					@{l='NoVolInfo';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._UnreachableVolumeInfo)) {$true} else {$_._UnreachableVolumeInfo} )}},
					@{l='NoFileInfo';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._UnreachableFilePath)) {$true} else {$_._UnreachableFilePath} )}},
					@{l='Index Files';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FileSize)) {'Unknown'} else {("{0:N0}" -f ($_._FileSize / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
					@{l='Free Space';	e={$( if($global:SRxEnv.h.isUnknownOrNull($_._FreeSpace)) {'Unknown'} else {("{0:N0}" -f ($_._FreeSpace / $sizeDecoratorValue)) + $sizeDecoratorLabel} )}},
					@{l='Path'; 		e={$( if($global:SRxEnv.h.isUnknownOrNull($_._CellPath)) {'Unknown'} else {$_._CellPath} )}}
		}

		Write-SRx INFO $("Admin Health Report for Index System {0} of Constellation {1}" -f $targetSSA._IndexSystem,$targetSSA._ConstellationID) -ForegroundColor DarkCyan
		Write-SRx INFO $("---------------------------------------------------------------------------")  -ForegroundColor DarkCyan
		$targetSSA._GetAdminReport() | sort name | ft -auto Name,Message,Level
	}
	
	if ($ExtendedObjects) {
		#Currently, there are no additional "extended" defined...
	}
	
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Ending $moduleMsgPrefix" } ) | Out-Null }
}

function Initialize-SRxIndexerDiskReport {
<#
.SYNOPSIS
	Internal method

.DESCRIPTION
    Initializes a disk report for a given index component

.INPUTS
	IndexComponent object [Microsoft.Office.Server.Search.Administration.Topology.Component]

#>

[CmdletBinding()]
param ($idx)

	#== Variables ===
	$moduleMsgPrefix = "[Initialize-SRxIndexerDiskReport " + $idx.Name + "]"

	if ($global:SRxEnv.DebugTimings -is [hashtable]) { 
		$TrackDebugTimings = $true
		$global:SRxEnv.DebugTimings[$moduleMsgPrefix] = $(New-Object System.Collections.ArrayList)
		$global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Beginning $moduleMsgPrefix..." } ) | Out-Null
	}
	
    if (($targetSSA -eq $null) -and ($xSSA._hasSRx)) { $targetSSA = $xSSA }

	#-- figure out the file path where the Index files exist
	if (-not $global:SRxEnv.h.isUnknownOrNull($idx._CellPath)) {
		$cellUnc = "\\" + $idx.ServerName + "\" + $idx._CellPath.Replace(":\","$\")
		Write-SRx DEBUG $(" --> " + $moduleMsgPrefix + " Re-using UNC Path: " + $cellUnc)
	} else {
		$cellPath = $idx.RootDirectory
        #the RootDirectory will be null for an index deployed to the default path, so we need to dig in further...
		
        if (($cellPath -eq $null) -or ($cellPath -eq "")) {
			if ($idx._DataDirectory) {
                $cellPath = Join-Path $idx._DataDirectory "Applications\Search\Nodes"
            } elseif ($idx._ApplicationsSearchPath) { 
				$cellPath = Join-Path $idx._ApplicationsSearchPath "Nodes"
			} elseif ($targetSSA._hasSRx) {
                $idxServer = $targetSSA._GetServerEx($idx.ServerName)
			    if ($idxServer.DataDirectory) { 
				    $cellPath = Join-Path $idxServer.DataDirectory "Applications\Search\Nodes"
			    } elseif ($idxServer.ApplicationsSearchPath) { 
				    $cellPath = Join-Path $idxServer.ApplicationsSearchPath "Nodes"
			    } else {
				    #this is a best effort attempt... but not reliable
                    $cellPath = Join-Path $targetSSA.AdminComponent.IndexLocation "\Search\Nodes\"
				    $tmpCellPath = Join-Path $cellPath $($targetSSA._ConstellationID + "\" + $idx.Name + "\storage\data")
				    $tmpCellUnc = "\\" + $idx.ServerName + "\" + $tmpCellPath.Replace(":\","$\")
				    if (-not (Test-Path $tmpCellUnc)) {
					    Write-SRx WARNING ("~~~" + $moduleMsgPrefix + $idx.Name + ")] Unable to verify the registry values for `"DefaultApplicationsPath`" or `"DataDirectory`"")
					    Write-SRx WARNING ("     Deferring to the value of `$xSSA.AdminComponent.IndexLocation (which may not be accurate for " + $idx.ServerName +")")
					    Write-SRx WARNING ("       > " + $targetSSA.AdminComponent.IndexLocation)
				    }	
			    }
			    $cellPath = Join-Path $cellPath $($targetSSA._ConstellationID + "\" + $idx.Name + "\storage\data")
		    } else { 
                $cellPath = 'Unknown'
            }
		} 	

        #if we have a path at this point (e.g. not null or 'unknown')
		if (-not $global:SRxEnv.h.isUnknownOrNull($cellPath)) {
		    if (-not $cellPath.EndsWith("\")) { $cellPath += "\" }
		    $cellUnc = "\\" + $idx.ServerName + "\" + $cellPath.Replace(":\","$\")
		
            #then test if the path is valid...
		    if (Test-Path $cellUnc) {
			    if (($idx._CellName -ne $null) -and ($idx._CellNumber -ne "?")) {
				    $cellNameValue = $idx._CellName.Substring(1, $($idx._CellName.Length - 2) ) #strip off the surrounding [ ] brackets
				    $cellFolder = (Get-ChildItem -Directory -path $($cellUnc + "\" + $idx._IndexSystem + "*" + $cellNameValue) | sort -Descending | SELECT -First 1).Name + "\"
				    Write-SRx DEBUG $(" --> " + $moduleMsgPrefix + " Using Cell Folder " + $cellFolder + " (based on " + $cellNameValue + ")")
			    } else {
				    #give a best effort to figure out which path belongs to this indexer...
				    $cellFolder = (Get-ChildItem -Directory -path $($cellUnc + "\" + $idx._IndexSystem + "*." + $indexer.IndexPartitionOrdinal) | sort -Descending | SELECT -First 1).Name + "\"
				    Write-SRx DEBUG $(" --> " + $moduleMsgPrefix + " Using Cell Folder " + $cellFolder + " (based on directories in Cell Path)")
			    }

			    if ($cellFolder) {
				    $cellUnc = [System.IO.Path]::Combine($cellUnc, $cellFolder)
				    $cellPath = [System.IO.Path]::Combine($cellPath,$cellFolder)
			    }

			    Write-SRx VERBOSE $($moduleMsgPrefix + " Setting Cell Path: " + $cellPath)
			    Write-SRx VERBOSE $($moduleMsgPrefix + " Using UNC Path: " + $cellUnc)

		    } else {
                $cellPath = 'Unknown'
		    }
            if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Determined Cell Path..." } ) | Out-Null }
        }
        $idx | Set-SRxCustomProperty "_CellPath"	$cellPath
	}

    if ((-not $global:SRxEnv.h.isUnknownOrNull($cellPath)) -and (-not $global:SRxEnv.h.isUnknownOrNull($cellUnc))) {
	    #-- Sum the files sizes in that Index path
	    Write-SRx Verbose $("-- Measuring size of Index files on disk: " + $cellUnc)
	    Write-SRx DEBUG $("   (Original Cell Path: " + $idx._CellPath + " )")
	    try {
		    $utilizedSize = $(Get-ChildItem -path $($cellUnc + "*") -Recurse | measure -sum Length).Sum
		    if (($utilizedSize -ne $null) -and ($utilizedSize -ge 0)) { 
			    $idx | Set-SRxCustomProperty "_FileSize" $utilizedSize

			    #only if this flag was previously set, then undo the flag now (b/c it was successful this time)
			    if ($idx._UnreachableFilePath -is [bool]) { $idx._UnreachableFilePath = $false }

		    } else { 
			    Write-SRx DEBUG $("  Utilized size is zero or null when measuring size: " + $cellUnc)
			    $idx | Set-SRxCustomProperty "_FileSize"			'Unknown'
			    $idx | Set-SRxCustomProperty "_UnreachableFilePath"	$true
		    }
		
	    } catch {
		    Write-SRx DEBUG $("  Caught Exception measuring size of Index files on disk: " + $cellUnc)
		    $idx | Set-SRxCustomProperty "_FileSize" 			'Unknown'
		    $idx | Set-SRxCustomProperty "_UnreachableFilePath"	$true
	    }
	    if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Measured size of Index files on disk..." } ) | Out-Null }

	    #-- Using Get-WMI, get the volume information from the win32_volume class for the drive matching the Index file path
		Write-SRx VERBOSE $("-- Checking disk volume info: " + $idx.ServerName + " (DriveLetter: " + $(($idx._CellPath)[0]) + ")")
		try {
			$volInfo = Get-WmiObject win32_volume -ComputerName $idx.ServerName -ErrorAction SilentlyContinue | Where {$($_.DriveLetter) -and $_.DriveLetter.ToLower().StartsWith($($idx._CellPath.ToLower())[0])}
		} catch {
			Write-SRx DEBUG $("  Caught Exception checking disk volume info: " + $idx.ServerName + " (DriveLetter: " + $(($idx._CellPath)[0]) + ")")
			$volInfo = $null
		}
        if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Retrieved disk volume info..." } ) | Out-Null }

    } else {
        $idx | Set-SRxCustomProperty "_FileSize" 	'Unknown'
        $idx | Set-SRxCustomProperty "_UnreachableFilePath"	$true
	}

	if ($volInfo -ne $null) {
		$idx | Set-SRxCustomProperty "_DriveLetter"		$volInfo.DriveLetter		
		$idx | Set-SRxCustomProperty "_Capacity"		$volInfo.Capacity
		$idx | Set-SRxCustomProperty "_FreeSpace"		$volInfo.FreeSpace
        $idx | Set-SRxCustomProperty "_BlockSize"		$volInfo.BlockSize
        $idx | Set-SRxCustomProperty "_Compressed"		$volInfo.Compressed
        $idx | Set-SRxCustomProperty "_DriveIndexing"	$volInfo.IndexingEnabled
		
		#only if this flag was previously set, then undo the flag now (b/c it was successful this time)
		if ($idx._UnreachableVolumeInfo  -is [bool]) { $idx._UnreachableVolumeInfo = $false }
		
	} else {
		$idx | Set-SRxCustomProperty "_DriveLetter"	$( $( if ($idx.RootDirectory) { $($idx.RootDirectory)[0] } else { "?" } ) + ":" )
		$idx | Set-SRxCustomProperty "_UnreachableVolumeInfo"	$true
		$idx | Set-SRxCustomProperty "_Capacity"		'Unknown'	
		$idx | Set-SRxCustomProperty "_FreeSpace"		'Unknown'
        $idx | Set-SRxCustomProperty "_BlockSize"		'Unknown'
        $idx | Set-SRxCustomProperty "_Compressed"		'Unknown'
        $idx | Set-SRxCustomProperty "_DriveIndexing"	'Unknown'
	}

	#-- Try to calculate an estimated size needed to complete Master Merge based on the CheckPoint Size * 2.5       *Note: 2.5x for SP2013; 1.5x for SP2016
	if (-not $global:SRxEnv.h.isUnknownOrZero($idx._CheckpointSize)) {
		Write-SRx DEBUG $(" --> Calculating an estimated size needed to complete Master Merge")
        $tmpMMOverhead = $idx._CheckpointSize
        if ($global:SRxEnvProduct -eq "SP2013") {
            $tmpMMOverhead *= 1.5 
            #if MM is running, we expect the FileSize to be MUCH bigger than normal... but if it's not running and it's still huge
		    if ((-not $idx._MasterMerging) -and (-not $idx._UnreachableFilePath) -and ($idx._FileSize -gt $tmpMMOverhead)) {
		        #MM may be continually failing, so so we shouldn't use the checkpoint reliably for estimates
                $tmpMMOverhead = $idx._FileSize #this is sort of a worst case scenario
		    }
        } else {
            $tmpMMOverhead *= 0.5 #the MM overhead is much smaller in SP2016
        }
		
		#the custom weight allows a user to configure a decimal multipler (e.g. -0.2) to increase/decrease the weight of $tmpMMOverhead
		if ($global:SRxEnv.h.isNumeric($global:SRxEnv.CustomMMOverheadWeight)) { 
			$customMMOverheadWeight = $global:SRxEnv.CustomMMOverheadWeight * $tmpMMOverhead 
		} else { $customMMOverheadWeight = 0 }

		#generally, the total estimated size for MM would be ~equal to (Checkpoint size * 2.5)      *Note: 2.5x for SP2013; 1.6x for SP2016
		$tmpMMTotalSizeEstimate = $idx._CheckpointSize + $tmpMMOverhead + $customMMOverheadWeight
		
		#estimated amount of space not yet allocated by the next MM (useful for comparing against free space on the drive)
		if (-not $idx._UnreachableFilePath) {
			$tmpMMPendingAllocEstimate = $tmpMMTotalSizeEstimate - $idx._FileSize
            if ($tmpMMPendingAllocEstimate -le 0) { 
                $tmpMMPendingAllocEstimate = 'Unknown'
            }
		} else {
			$tmpMMPendingAllocEstimate = 'Unknown'
		}
		
		$idx | Set-SRxCustomProperty "_EstimatedMMTotalFileSize"	$tmpMMTotalSizeEstimate
		$idx | Set-SRxCustomProperty "_EstimatedMMGrowthOverhead"	$tmpMMOverhead
		$idx | Set-SRxCustomProperty "_EstimatedMMPendingGrowth"	$tmpMMPendingAllocEstimate
		
		if ((-not ($global:SRxEnv.h.isUnknownOrZero($idx._FreeSpace))) -and (-not ($global:SRxEnv.h.isUnknownOrNull($idx._EstimatedMMPendingGrowth)))) {
			$idx | Set-SRxCustomProperty "_PctMMPendingToFreeSpace"		$(([decimal]::Round( $($idx._EstimatedMMPendingGrowth / $idx._FreeSpace), 4)) * 100)
		} else {
			$idx | Set-SRxCustomProperty "_PctMMPendingToFreeSpace"		'Unknown'
		}
        if ((-not ($global:SRxEnv.h.isUnknownOrZero($idx._FreeSpace))) -and (-not ($global:SRxEnv.h.isUnknownOrNull($idx._EstimatedMMGrowthOverhead)))) {
			$idx | Set-SRxCustomProperty "_PctMMOverheadToFreeSpace"	$(([decimal]::Round( $($idx._EstimatedMMGrowthOverhead / $idx._FreeSpace), 4)) * 100)
		} else {
			$idx | Set-SRxCustomProperty "_PctMMOverheadToFreeSpace"	'Unknown'
		}	
	} else {
		Write-SRx DEBUG $(" --> Checkpoint is `$null - Unable to calculate an estimated size for Master Merge")
        #if the checkpoint size were unavailable here, that is a potential problem state that should be further investigated outside of a MM check
		$idx | Set-SRxCustomProperty "_EstimatedMMTotalFileSize"	'Unknown'
		$idx | Set-SRxCustomProperty "_EstimatedMMGrowthOverhead"	'Unknown'
		$idx | Set-SRxCustomProperty "_EstimatedMMPendingGrowth"	'Unknown'
		$idx | Set-SRxCustomProperty "_PctMMPendingToFreeSpace"		'Unknown'
		$idx | Set-SRxCustomProperty "_PctMMOverheadToFreeSpace"	'Unknown'
	}
		
    $idx | Set-SRxCustomProperty "_hasSRxDiskReport" (
        (-not $idx._UnreachableVolumeInfo) -and (-not $idx._UnreachableFilePath) -and (-not $global:SRxEnv.h.isUnknownOrNull($idx._CellPath))
    )
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings[$moduleMsgPrefix].Add( @{ $(Get-Date) = "Ending $moduleMsgPrefix" } ) | Out-Null }
}

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBJdZ+aJ5sUVq5h
# 8nDFM86O50Ie6J7IMnoW/ZPQr7XdNKCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIMLvz68RNGqcD53O/FHBa3Vn1NfK7PUWuuDfpMEdUqstMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAE2nLw6zdeMt3Yqhsq0XtiCj
# nmtYB5Ka/3m/5igZwEQiICoabJYlX1R5Dt007LTVrYsGrrIaeJ0WgOdGDvzZlWDv
# I/3rPz3slQu7WjtV7v9FqAjEEPbYDuonjnRgxcbH3ADdvtMZwZHRNUYwW49hcniH
# 6mKS85H7gGllBgsEh4jKsLF/ikfcibjhfLEz53HG0d97Ga2CZbab2KztYyicjI0f
# DVGQzQKHKybp9RIP1xNxeOdY+JFLaqz7NTa8ITMXbqpDZ/LwByTb+DlBKIOP7Z2f
# jXaoRGc/iqvtZ/3p3JX7UAM8LOE0N6dLfcTL7pITd9C5yoahS6d65uiVj7Lufj+h
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgmWi9bWf+Hua26QFpuxLs
# P+I2Tswz9mg+NR0ryTKqv0MCBljVOtTJ2hgTMjAxNzA0MjYyMzU0MDQuMjE1WjAH
# AgEBgAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjcy
# OEQtQzQ1Ri1GOUVCMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
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
# 7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNowggPCoAMCAQICEzMAAACy
# NQVoNyIcDacAAAAAALIwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU3WhcNMTgwOTA3MTc1NjU3WjCBszEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjcyOEQtQzQ1Ri1GOUVCMSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAmEoBu9FY9X90kULpoS5TXfIsIG8SLpvT15WV3J1v
# iXwOa3ApTbAuDzVW9o8CS/h8VW1QzT/HqnjyEAeoB2sDu/wr8Kolnd388WNwJGVv
# hPpLRF7Ocih9wrMfxW+GapmHrrr+zAWYvm++FYJHZbcvdcq82hB6mzsyT9odSJIO
# IuexsUJtWcJiniwqCvA1NyACCezhFOO1F+OAflTuXVEOk9maSjPJryYN6/ZrI5Uv
# P10SITdKJM+OvQ+bUz/u6e6McHvaO/VquZk8t9sBfBLLP1XO9K/WBrk6PN98J9Ry
# lM2vSgk2xiLsXXO9OuKAGh31vXdwjWNwe8DA9u6eNGmHtwIDAQABo4IBGzCCARcw
# HQYDVR0OBBYEFDNkvmdrHNz5Y0QGSOTFQ8mQ9oKVMB8GA1UdIwQYMBaAFNVjOlyK
# MZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3
# LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEu
# Y3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcN
# AQELBQADggEBAEHgsqCgyvQob8yN3f7bvSBViWwgKXZ2P9QnyV57g/vBwkc2jfZ6
# IUxEGzpxY6sjJr9ErqIZ7yfWWIa6enD6L7RL5HFIOlfStf+jEBuaCcNfHgnoMM2R
# 61RcwQtZ/vTqUi+oejVrYLaDOAmmmnbblrPXNYeoZDpcBs9MEw3GIhi3AGOMuHWx
# ReGpR1rb//y7Gh1UOdsVX+ZX5DSeeC/9tNwg39ITEKPOPXHZ4bBeZVl7jmzulbOZ
# 3/CoHGEPTE9XqtbEMfZ8DWLrbGsAoQqE0nxxKScipNgTD8B6yJ3dOjnq3icG3ARh
# jjxqhJrfTraa7bBM4fpRjYBCBaYm9oNvAeahggN2MIICXgIBATCB46GBuaSBtjCB
# szELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxME
# TU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjcyOEQtQzQ1Ri1GOUVCMSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4D
# AhoFAAMVAL3/xZVjkPETnGDWGcCv6bieHiAdoIHCMIG/pIG8MIG5MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYD
# VQQLEx5uQ2lwaGVyIE5UUyBFU046NERFOS0wQzVFLTNFMDkxKzApBgNVBAMTIk1p
# Y3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQAC
# BQDcq0/oMCIYDzIwMTcwNDI2MTY1NzEyWhgPMjAxNzA0MjcxNjU3MTJaMHQwOgYK
# KwYBBAGEWQoEATEsMCowCgIFANyrT+gCAQAwBwIBAAICHMgwBwIBAAICGegwCgIF
# ANysoWgCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQAC
# AxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEASQFtaOOEu/QY2w7k
# q/HVZ4Vk09m47nWp0s+cBKzFeMO/8j7DRsLVpNzgLe6Wz+bi2oRe0UrBpVT3gOW9
# w66oaovIX9rEYww0u/YIjXnVKCt8uDFHPFHQBKp9OcmOUaNbmD+PHvB/sKdGFHMA
# MACqYesHlT429nyq+Tozz/XWkISu8WEu6QxYjrhCDdWBtIAjKIqcZF97uceeaPGx
# 0vaXkeKYdcvs+vNrGWf0spNEAGooi0ZEKMrAMrlzrw0o8PQNLC88kkokaYql1z5B
# OvlvdXmOSif/CTe4fDC+GeEpvQ/8FIhjKm7eDK6UZZ1NitBrTdsO8/QmyB5+wBtH
# lCEcjzGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAAsjUFaDciHA2nAAAAAACyMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIFdSGGuyn8xYvxzi
# GBfSTpdJ0pY3STMKmDn0v9uWTdFaMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUvf/FlWOQ8ROcYNYZwK/puJ4eIB0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAALI1BWg3IhwNpwAAAAAAsjAWBBSRrnb7XKTtB5IW
# rfee9hkzrTNhXzANBgkqhkiG9w0BAQsFAASCAQBTrBPcCDfjcmoVR3uaIsra34y9
# Sw+ceK5AYknlZO7g0R3j0baaImsp8m3tQ9tlymlRKSeLchQLw3Ogd5RZttiI6RNb
# Qh9YueRVUqAnYUZ88xU1T2rsXlA63pwFtNt2tD1sEPxaM/oBoNPe3/uuSZTUKs3c
# uGgMHq/8zoH363ubC2Ob6mkWB7PE4nYKx8H/WFeqSV7Z/OJsK9cctKJU+iuSIJ9/
# ciGI6POoXSqV1zHwc2fYiZqwgl0kFSY4tTH1/oB1MJaPk+jiMRWOMlItkV58RvF+
# c3Q3C9gwAZIzT/Otz4NRFRiIgHiT8gdMtYgpTGikteUJF1VRC2HMIgFDe+lX
# SIG # End signature block
