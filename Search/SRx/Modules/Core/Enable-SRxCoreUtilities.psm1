#=============================================
# Project		: Search Health Reports (SRx)
#---------------------------------------------
# File Name 	: Enable-SRxCoreUtilities.psm1
# Author		: Brian Pendergrass
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


function Set-SRxCustomProperty {
<#
.SYNOPSIS
	Internal helper for adding or refreshing a property to an existing object 
	
.DESCRIPTION

.EXAMPLE
	$targetObject | Set-SRxCustomProperty "_CustomPropertyName" $propertyValue

#>
[CmdletBinding()]
param (
	[parameter(Mandatory=$true,ValueFromPipeline=$true)]$object, 
	[parameter(Mandatory=$true,ValueFromPipeline=$false,Position=0)][String]$propertyName, 
	[parameter(Mandatory=$false,ValueFromPipeline=$false,Position=1)]$propertyValue
)
	if ($propertyName.Contains(".")) {
		Write-SRx VERBOSE ("[Set-SRxCustomProperty] `$propertyName contains '.' (" + $propertyName + ")")
		if ($propertyName.Contains("..") -or $propertyName.EndsWith(".")) {
			Write-SRx WARNING ("[Set-SRxCustomProperty] Skipping Invalid Property Name: " + $propertyName)
			return
		} else {
			$firstPos = $propertyName.indexOf(".")
			$parent = $propertyName.Substring(0, $firstPos)
			$child = $propertyName.Substring($firstPos + 1)
			Write-SRx DEBUG (" --> [Set-SRxCustomProperty] `$propertyName contains tokens ( p: " + $parent + " , c: " + $child +" )")
			
			if (($object.$parent -ne $null) -and (($object.$parent -is [PSObject]) -or ($object.$parent -is [Hashtable]))) {
				Write-SRx DEBUG (" --> [Set-SRxCustomProperty] Recursing... ( p: " + $parent + " , c: " + $child +" )")
				$object.$parent | Set-SRxCustomProperty $child $propertyValue
			}
		}
	} else {
        if ($object -is [Hashtable]) {
            $object.$propertyName = $propertyValue
        } elseif ($object -is [PSObject]) {
		    if ( $( $object | Get-Member -Name $propertyName) -ne $null ) { 
	            #if the property already exists, just set it
			    $object.$propertyName = $propertyValue
		    } else {
			    #add the new member property and set it
			    $object | Add-Member -Force -MemberType "NoteProperty" -Name $propertyName -Value $propertyValue 
		    }
        }
	}
}

function New-SRxServer {
<#
.SYNOPSIS
	Internal helper for creating a new [custom] SRx Server object
#>
[CmdletBinding()]
param ( [parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]$Server = $ENV:ComputerName )

	BEGIN { 				
		#== Create the result set (e.g. for handling pipelined input)
		$results = New-Object System.Collections.ArrayList
	} 

	#if this cmdlet receives an array of servers pipelined in, such as:  $xSSA._Servers | Get-SRxServerSpecs
	# then this PROCESS block will handle a single SRxServer ...one by one
	PROCESS {	
        if ($Server._hasSRx) {
            #just add it and keep going...
            $results.add($Server) | Out-Null
        } else {
            #otherwise, try to build a new SRxServer object
            if ($Server -is [String]) {	
                $srxServer = New-Object PSObject -Property @{ "Name" = $Server }
                $returnObject = $true
            } elseif ($Server.Name -ne $null) {
                $srxServer = $Server
            } else {
                $srxServer = $null
            }

            if ($srxServer -ne $null) {
                #--- Methods: 'LogParserQuery' server
	            $srxServer | Add-Member -Force -MemberType ScriptMethod -Name LogParserQuery -Value {
                    param ($queryString = "SELECT * FROM SOME-LOG-FILE", $outparams = @())
                    if($outparams.Count -gt 0 -and (-not [string]::IsNullOrEmpty($queryString))){
                        $results = this | Invoke-SRxRemoteTool -ToolName "LogParser" -Operation $queryString

                        Write-Host ("...results are being copied from [" + $this.name + "] " + " to " + $srxenv.paths.Tmp)
                    }
                }

                #--- Methods: 'canPing' server
	            $srxServer | Add-Member -Force -MemberType ScriptMethod -Name canPing -Value {
                    param ([bool]$bypassCache = $false)

                    if ($global:___SRxCache[$this.Name] -isNot [hashtable]) { 
	                    $global:___SRxCache[$this.Name] = @{} 
                    }

                    if ((-not $bypassCache) -and ($global:___SRxCache[$this.Name].canPing -ne $null)) {
					    Write-SRx DEBUG $(" --> [`$(" + $this.Name + ").canPing] Found canPing in cache...")
						$timeOfLastReport = $($global:___SRxCache[$this.Name].canPing.Keys)[0]
						$reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
						
                        #keep a can ping in cache for 20 seconds, but a failed ping in cache for 2 minutes
                        if ($global:___SRxCache[$this.Name].canPing[$timeOfLastReport] -and ($reportAge -lt 20)) {
							Write-SRx DEBUG $(" --> [`$(" + $this.Name + ").canPing] Using cache until " + $(Get-Date).AddSeconds(20 - $reportAge)) -ForegroundColor Cyan
							return $( $global:___SRxCache[$this.Name].canPing[$timeOfLastReport] )
						} elseif ((-not $global:___SRxCache[$this.Name].canPing[$timeOfLastReport]) -and ($reportAge -lt 120)) {
                            Write-SRx DEBUG $(" --> [`$(" + $this.Name + ").canPing] Using cache failure until " + $(Get-Date).AddSeconds(120 - $reportAge)) -ForegroundColor Magenta
							return $( $global:___SRxCache[$this.Name].canPing[$timeOfLastReport] )
						}
					}

                    try { 
						Write-SRx DEBUG $(" --> [`$(" + $this.Name + ").canPing] New ping...")
                        $pingMe = Test-Connection $this.Name -Count 1 -AsJob
                        Wait-Job $pingMe| Out-Null
                        $global:response = Receive-Job $pingMe
                        $r = $response | SELECT IPV4Address, IPV6Address
                        $canPing = $( if (($response.StatusCode -eq 0) -and (($r.IPV4Address) -or ($r.IPV4Address))) { $true } else { $false } )
                        $global:___SRxCache[$this.Name].canPing = @{ $(Get-Date) = $canPing }
                        Write-SRx DEBUG $(" --> [`$(" + $this.Name + ").canPing] completed")
                        return $canPing
					} catch {
						Write-SRx DEBUG (" ~~> [`$(" + $this.Name + ").canPing] Unable to ping server")
						throw 
					}
	            }

                #--- Methods: System Specs
	            $srxServer | Add-Member -Force -MemberType ScriptMethod -Name GetServerSpecs -Value {
		            if ($this.canPing()) {
			            $this | Get-SRxServerSpecs 
		            } else {
			            Write-SRx WARNING ("~~~[" + $this.Name + "] Failed to ping server - skipping retrieval of the Server Specs")
		            }
	            }

                #--- Methods: System Specs
	            $srxServer | Add-Member -Force -MemberType ScriptMethod -Name GetSQLAlias -Value {
                    $serverName = $this.Name
                    try {
                        $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$serverName) #'LocalMachine' is HKLM
                        $regPath = "SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo\"
                        $regKey = $reg.openSubKey($regPath)

                        $aliasMap = @{}
                        if ($regKey -ne $null) {
                            foreach ($aliasName in @( $regKey.GetValueNames() ) ) {
                                $tokenizedValue =  $( [string] $regKey.GetValue($aliasName) ).split(",")
                                if (-not [String]::isNullOrEmpty($tokenizedValue)) {
                                    $aliasMap[$aliasName] = $tokenizedValue
                                }
                            }
                        }
                        return $aliasMap
                    } catch {
				        Write-SRx WARNING ("~~~[" + $serverName + "] Unable to retrieve Search-related registry keys")
                    }
                }

	            #--- Properties: Marker to indicate that this has the extended properties 
                $srxServer | Set-SRxCustomProperty "_hasSRx" $true
            }

            $results.add($srxServer) | Out-Null
        }

    }
    END {
		if ($results.Count -gt 1) {
			return $results
		} else {
			return $results[0]
		}
    }
}

function Get-SRxServerSpecs {
<#
.SYNOPSIS
	Internal helper for retrieving OS/Server level specs from a server
                
.DESCRIPTION

.NOTES
	Based on Get-Uptime.ps1 by Olaf

#>
[CmdletBinding()]
param ( [parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]$Server = $ENV:ComputerName )

	BEGIN { 				
		#== Create the result set (e.g. for handling pipelined input)
		$results = New-Object System.Collections.ArrayList
	} 

	#if this cmdlet receives an array of servers pipelined in, such as:  $xSSA._Servers | Get-SRxServerSpecs
	# then this PROCESS block will handle a single SRxServer ...one by one
	PROCESS {	
		$Server = New-SRxServer $Server
		$serverName = $Server.Name
		if ([String]::IsNullOrEmpty($serverName)) {
			Write-SRx WARNING $("~~~[Get-SRxServerSpecs] `$serverName is `$null or empty string... skipping server")
		} else {
            Write-SRx INFO $(" * [Get-SRxServerSpecs (") -ForegroundColor DarkCyan -NoNewline
            Write-SRx INFO $serverName -ForegroundColor Yellow -NoNewline
            Write-SRx INFO ")] " -ForegroundColor DarkCyan -NoNewline
            
            $sinceMidnight = $( New-TimeSpan $(Get-Date -Hour 0 -Minute 00 -Second 00) (Get-Date)).TotalSeconds
            try {
                $cachedSpecs = Get-SRxRecentCachedFile $sinceMidnight "specs" $serverName
            } catch {
                Write-SRx VERBOSE (" --> Caught exception retrieving from cache ...skipping")
            }

            if ($cachedSpecs -ne $null) { 
                Write-SRx INFO ("Using cached server specs ") -NoNewline
                Write-SRx INFO ("(valid until " + $(Get-Date -Hour 0 -Minute 00 -Second 00).AddDays(1).ToShortDateString() + ")") -ForegroundColor Cyan
				$osInfo = $cachedSpecs.osInfo
				$csInfo = $cachedSpecs.csInfo
				$cpuInfo = $cachedSpecs.cpuInfo
				$powerPlan = $cachedSpecs.powerPlan
				$biosInfo = $cachedSpecs.biosInfo
				$driveInfo = $cachedSpecs.driveInfo
            } elseif (-not $Server.canPing()) {
                Write-SRx INFO ("Failed to ping this server ...skipping") -ForegroundColor Yellow 
            } else {
                Write-SRx INFO ("Retrieving Server Specs...")
				
				try {
					$osInfo = Get-WmiObject -class Win32_OperatingSystem -computer $serverName -ErrorAction SilentlyContinue
					$csInfo = Get-WmiObject -class Win32_ComputerSystem -computer $serverName -ErrorAction SilentlyContinue
					$cpuInfo = Get-WmiObject -class Win32_Processor -computer $serverName -ErrorAction SilentlyContinue
					$powerPlan = Get-WmiObject -Class Win32_PowerPlan -Namespace root\cimv2\power -computer $serverName -ErrorAction SilentlyContinue | Where {$_.IsActive -eq $true}
					$biosInfo = Get-WmiObject -class Win32_BIOS -computer $serverName -ErrorAction SilentlyContinue
					$driveInfo = Get-WmiObject -class win32_volume -Computer $serverName -ErrorAction SilentlyContinue | Where {$_.DriveLetter -ne $null}
                    $createCache = $true
                } catch {
					Write-SRx WARNING $("~~~[Get-SRxServerSpecs (" + $serverName + ")] Failure occurred when attempting to retrieve the system information")
				}
            }
					                 
			if ($osInfo -eq $null) {
				$Server |  Set-SRxCustomProperty "BootTime" 'unknown'
			} else { 
				$Server | Set-SRxCustomProperty "BootTime"	$(if ($osInfo.Lastbootuptime -ne $null) {$osInfo.ConvertToDateTime($osInfo.Lastbootuptime)} else {$osInfo.BootTime})
				$Server | Set-SRxCustomProperty "OSversion"	$(if ($osInfo.Version -ne $null) {$osInfo.Version} else {$osInfo.OSversion})
			}

			if ($csInfo -eq $null) {
				$Server | Set-SRxCustomProperty "CPUs" 'unknown'
			} else {
				$Server | Set-SRxCustomProperty "Model"	$csInfo.Model
				$Server | Set-SRxCustomProperty "RAM"	$(if ($csInfo.TotalPhysicalMemory -ne $null) {$csInfo.TotalPhysicalMemory} else {$csInfo.RAM})
				$Server | Set-SRxCustomProperty "CPUs"	$(if ($csInfo.NumberOfProcessors -ne $null) {$csInfo.NumberOfProcessors} else {$csInfo.CPUs})
			}

			if ($cpuInfo -eq $null) {
				$Server | Set-SRxCustomProperty "CPU"	'unknown'
				$Server | Set-SRxCustomProperty "Cores"	'unknown'
			} else {
				$Server | Set-SRxCustomProperty "CPU"			$(if ($cpuInfo.Name -ne $null) {$cpuInfo.Name} else {$cpuInfo.CPU})
				$Server | Set-SRxCustomProperty "Clock"			$(if ($cpuInfo.CurrentClockSpeed -ne $null) {$cpuInfo.CurrentClockSpeed} else {$cpuInfo.Clock})
				$Server | Set-SRxCustomProperty "MaxClock"		$(if ($cpuInfo.MaxClockSpeed -ne $null) {$cpuInfo.MaxClockSpeed} else {$cpuInfo.MaxClock})
				$Server | Set-SRxCustomProperty "Cores"			$(if ($cpuInfo.NumberOfCores -ne $null) {$cpuInfo.NumberOfCores} else {$cpuInfo.Cores})
				$Server | Set-SRxCustomProperty "LogicalCores"	$(if ($cpuInfo.NumberOfLogicalProcessors -ne $null) {$cpuInfo.NumberOfLogicalProcessors} else {$cpuInfo.LogicalCores})
			}

			if ($powerPlan -eq $null) {
				$Server | Set-SRxCustomProperty "PowerPlan" 'unknown'
			} else {
				$Server | Set-SRxCustomProperty "PowerPlan" $(if ($powerPlan.ElementName -ne $null) {$powerPlan.ElementName} else {$powerPlan.PowerPlan})
			}

			if ($biosInfo -eq $null) {
				$Server | Set-SRxCustomProperty "BIOS" 'unknown'
			} else {
				$Server | Set-SRxCustomProperty "BIOS" $(if ($biosInfo.SMBIOSBIOSVersion -ne $null) {$biosInfo.SMBIOSBIOSVersion} else {$biosInfo.BIOS})
			}

			$Server | Set-SRxCustomProperty "Drives" @()
			if ($driveInfo -ne $null) {
				foreach ($drive in @( $driveInfo )) {
					$Server.Drives += New-Object PSObject -Property @{
												"DriveLetter" = $drive.DriveLetter;
												"DriveType" = $drive.DriveType;
												"SystemVolume" = $drive.SystemVolume;
												"FileSystem" = $drive.FileSystem;
												"BlockSize" = $drive.BlockSize;
												"Compressed" = $drive.Compressed;
												"IndexingEnabled" = $drive.IndexingEnabled;
												"FreeSpace" = $drive.FreeSpace;
												"Capacity" = $drive.Capacity;
										    }
				}
			}
            $results.add($Server) | Out-Null
            if ($createCache) { 
                $data = New-Object PSObject -Property @{
                    		"osInfo" = $($Server | SELECT BootTime, OSversion);
				            "csInfo" = $($Server | SELECT Model, RAM, CPUs);
				            "cpuInfo" = $($Server | SELECT CPU, Clock, MaxClock, Cores, LogicalCores);
				            "powerPlan" = $($Server | SELECT PowerPlan);
				            "biosInfo" = $($Server | SELECT BIOS);
				            "driveInfo" = $($Server | SELECT -ExpandProperty Drives)
			    }
                New-SRxCacheFile -object $data -action "specs" -category $serverName
            }
		}
	}
	
	END {
		if ($results.Count -gt 1) {
			return $results
		} else {
			return $results[0]
		}
	}
}

function Test-SRxURLConnection {
<#
.SYNOPSIS
	Tests a connection to a URL (or collection of URLs)
                
.DESCRIPTION

#>
[CmdletBinding()]
param ( [parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]$target )
    BEGIN {
        if ($global:___SRxCache.URL -isNot [hashtable]) { 
	        $global:___SRxCache.URL = @{} 
        }

        if (-not $(Get-Module WebAdministration)) {
		    Import-Module WebAdministration -ErrorAction SilentlyContinue
	    }

        $results = New-Object PSObject -Property @{ Status = $false; Details = $(New-Object System.Collections.ArrayList); }
    }

    PROCESS {
        if ($target -is [String]) { $target = @( [Uri]$target ) }
        elseif ($target -is [Uri]) { $target = @( $target ) }
        #else ...assume that this is an array
    
        foreach ($uri in $target) {
            $url = ([Uri]$uri).AbsoluteUri
            $usingCache = $false
            if ($global:___SRxCache.URL[$url] -ne $null) {
		        Write-SRx DEBUG $(" --> [Test-SRxURLConnection " + $url + "] Found in cache...")
		        $timeOfLastReport = $($global:___SRxCache.URL[$url].Keys)[0]
		        $reportAge = $( New-TimeSpan $timeOfLastReport $(Get-Date) ).TotalSeconds
		        if ($reportAge -lt 1200) {
			        Write-SRx DEBUG $(" --> [Test-SRxURLConnection] Using cached response until " + $(Get-Date).AddSeconds(1200 - $reportAge)) -ForegroundColor Cyan
	    		    $request = $global:___SRxCache.URL[$url][$timeOfLastReport]  #Get-WebUrl -url $url.AbsoluteUri
                    $usingCache = $true
		        } 
	        } 

            if (-not $usingCache) {
                try { 
                    Write-SRx VERBOSE $(" --> [Test-SRxURLConnection " + $url + "] Requesting...")
                    $request = Get-WebUrl -url $url 
                    Write-SRx DEBUG $(" --> [Test-SRxURLConnection " + $url + "] Received response")
                } catch {
                    Write-SRx DEBUG (" ~~> [Test-SRxURLConnection " + $url + "] Unable to load the 'WebAdministration' module")
                }   
                $global:___SRxCache.URL[$url] = @{ $(Get-Date) = $request }
            }

		    if ($request -eq $null) {
			    $results.details.Add( $(New-Object PSObject -Property @{ "Host" = $_.DnsSafeHost; "Url" = $url; "Result" = 'unknown' }) ) | Out-Null
		    } elseif ($request.status -ine "OK") {
                $results.details.Add( $(New-Object PSObject -Property @{ "Host" = $_.DnsSafeHost; "Url" = $url; "Result" = $request }) ) | Out-Null
            }
	    }
    }

    END {
        if (($target -ne $null) -and ($target.Count -gt 0)) {
			if ($results.details.count -eq 0) { $results.status = $true } 
		} else { $results.details.Add("unknownEndPoints") | Out-Null }
        
        return $results
    }
}

function New-SRxCacheFile {
<#
.SYNOPSIS
	Internal helper
	
.DESCRIPTION

#>
[CmdletBinding()]
param ($object, $action = "_unspecified", $category = $null, $objDepth = 3)
    if ([string]::isNullOrEmpty($object)) { 
        Write-SRx DEBUG ("This `$object is null ...skipping cache request")
    } else {
        $cacheFilePath = Join-Path $global:SRxEnv.Paths.Tmp "_cache"
	    if ($category -ne $null) { $cacheFilePath = Join-Path $cacheFilePath $category }
        $cacheFilePath = Join-Path $cacheFilePath $action

        if (-not (Test-Path $cacheFilePath)) {
            Write-SRx VERBOSE ("Creating temp folder: " + $cacheFilePath)
            New-Item -path $cacheFilePath -ItemType Directory | Out-Null
        }
        $cacheFilePath = Join-Path -Path $cacheFilePath $("_p" + $pid + "-" + $(Get-Date -Format "yyyyMMddHHmmss") + ".json")
        
        try {
            $jsonConfig = ConvertTo-Json $object -Depth $objDepth -Compress
		} catch {
            Write-Error $(" --> Caught exception converting `$object to JSON for caching - skipping: " + $action + $(if($category -ne $null) {" (" + $category +")"}))
        }
        
        try {
            Write-SRx VERBOSE $("<--Creating-Cache-File-- " + $cacheFilePath) -ForegroundColor Yellow
            $jsonConfig | Set-Content $cacheFilePath -ErrorAction Stop
        } catch {
            Write-SRx Warning $("~~~ Unable to persist file to " + $cacheFilePath + " - skipping")
        }
    }
}

function Get-SRxRecentCachedFile {
<#
.SYNOPSIS
	Internal helper
	
.DESCRIPTION

#>
[CmdletBinding()]
param ($ttl = 0, $action, $category = $null)
	$cacheHit = $null
	$cachePath = Join-Path $global:SRxEnv.Paths.Tmp "_cache"
	if ($category -ne $null) { $cachePath = Join-Path $cachePath $category }
	if ($action -ne $null) { 
        $cachePath = Join-Path $cachePath $action 
	    if (Test-Path $cachePath) {
            #if the path doesn't exist, then we clearly do not have a cached copy (so no need to go down this path)
            $found = gci $cachePath -file | sort LastWriteTime -Descend 
		    if ($found.Count -gt 0) {
		        $candidate = $found | SELECT -first 1
                $reportAge = $( New-TimeSpan $candidate.LastWriteTime $(Get-Date) ).TotalSeconds
			    Write-SRx DEBUG (" --> [Candidate file: " + $candidate.FullName)
			    Write-SRx DEBUG (" --> [Existing LastWriteTime: " + $candidate.LastWriteTime)
			    Write-SRx DEBUG (" --> [Age of cached item (sec): " + $reportAge)
			    if ($reportAge -lt $ttl) {
		  		    $currentFile = $candidate.FullName
                    try {
                        if (-not [string]::isNullOrEmpty($currentFile)) { 
                            $jsonObject = Get-Content $currentFile -Raw -ErrorAction Stop
                            if ([string]::isNullOrEmpty($jsonObject)) {
                                Write-SRx VERBOSE (" --> The cache file " + $currentFile + " exists, but is empty ...skipping")
                            } else { 
		    	                $cacheHit = ConvertFrom-Json $jsonObject
                                Write-SRx VERBOSE (" --> [Re-hydrated object from cache: " + $action + $(if($category -ne $null) {" (" + $category +")" } ))
                            }
                        }
                    } catch {
                        Write-SRx VERBOSE (" --> Caught exception retrieving from cache ...skipping")
                    }
                }
				#Clean up old logs
				if ($found.Count -gt 1) {
					Write-SRx VERBOSE (" --> [Removing old log files from this `$temp path...")
					$found | Where { $_.LastWriteTime -lt $candidate.LastWriteTime } | Remove-Item -Force
				}
		    }
	    } else {
            Write-SRx VERBOSE ("Creating temp folder: " + $cachePath)
            New-Item -path $cachePath -ItemType Directory | Out-Null
	    }
    } else {
        Write-SRx DEBUG ("Skipping cache check... (no specific action path supplied as an argument)")
    }

    return $cacheHit
}

function Compare-SRxVersionHash {
<#
.SYNOPSIS
	Internal helper
	
.DESCRIPTION

#>
    [CmdletBinding()]
    param ( 
    )
	DynamicParam 
	{
		# Set the dynamic parameters' name
		$ParamHashFile1 = 'HashFile1'
		$ParamHashFile2 = 'HashFile2'
		
		# Create the dictionary 
		$RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

		# Create the collection of attributes
		$AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
		
		# Create and set the parameters' attributes
		$ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
		$ParameterAttribute.Mandatory = $true

		# Add the attributes to the attributes collection
		$AttributeCollection.Add($ParameterAttribute)

		# Generate and set the ValidateSet 
		$arrSet = Get-ChildItem -Path $global:SRxEnv.Paths.Log -File "Version.*.hash" | Select-Object -ExpandProperty Name | Sort-Object -Descending
		$ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)

		# Add the ValidateSet to the attributes collection
		$AttributeCollection.Add($ValidateSetAttribute)

		# Create and return the dynamic parameter
		$RuntimeParameter1 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParamHashFile1, [string], $AttributeCollection)
		$RuntimeParameterDictionary.Add($ParamHashFile1, $RuntimeParameter1)
		$RuntimeParameter2 = New-Object System.Management.Automation.RuntimeDefinedParameter($ParamHashFile2, [string], $AttributeCollection)
		$RuntimeParameterDictionary.Add($ParamHashFile2, $RuntimeParameter2)
		return $RuntimeParameterDictionary
	}
    begin 
    {
        $HashFile1 = $PsBoundParameters[$ParamHashFile1]
        $HashFile2 = $PsBoundParameters[$ParamHashFile2]
        Write-SRx INFO "Comparing $HashFile1 to $HashFile2"
    }
    process 
    {
        $difffile  = Join-Path $global:SRxEnv.Paths.Log "Version.$(Get-Date -f 'yyyyMMddHHmmss').diff"
        $o1 = Get-Content -Path $(Join-Path $global:SRxEnv.Paths.Log $HashFile1)
        $o2 = Get-Content -Path $(Join-Path $global:SRxEnv.Paths.Log $HashFile2)

        $diff = Compare-Object $o1 $o2
    
        if($diff -eq $null)
        {
            Write-SRx INFO "SRx Version hash files match." -ForegroundColor DarkCyan
        }
        else
        {
            $diff | Add-Content $difffile
            Write-SRx INFO "SRx Version hash files do not match." -ForegroundColor yellow
            Write-SRx INFO "Wrote compare output to $difffile" -ForegroundColor yellow
        }
    }
}

function New-SRxVersionHash {
[CmdletBinding()]
param ( [parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
        $hashpath= $global:SRxEnv.Paths.Log,
        [parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
        $SRXRootDir= $global:SRxEnv.Paths.SRxRoot)
<#
.SYNOPSIS
	Internal helper
	
.DESCRIPTION

#>
    Write-SRx INFO "Calculating SRx version hash..."
    $hashfile  = Join-Path $hashpath "Version.$(Get-Date -f 'yyyyMMddHHmmss').hash"
    $exclusionList = @("*\Example\*", "*\InDev\*", "*\Output\*", "*\var\*", "*\Dashboard\WebPartContent\ScriptEditor1.js", "*\SRx.pssproj*")
    $files = Get-ChildItem -Path $SRXRootDir -Recurse 
    foreach($file in $files) {
        # ignore folders
        if($file.PSIsContainer) {
            continue
        }
        # ignore items in exclude list
        $skip = $false
        foreach($exclusion in $exclusionList) {
            if($file.FullName -like $exclusion) {
                $skip = $true
                break
            }
        }
        if($skip) {
            continue
        }
        # build the hashes
        $hashObj = Get-FileHash -Path $file.FullName
        "$($file.Name)`t$($hashObj.Hash)" | Add-Content -Path $hashfile 
    }

    $hashObj = Get-FileHash -Path $hashfile
    Write-SRx INFO "Wrote version hash info to $hashfile"
    Write-SRx INFO "SRx version $($hashObj.Algorithm) hash = $($hashObj.Hash)" -Foreground Cyan
    return $($hashObj.Hash)
}

Function Test-SRxRecursiveACLs{
Param(
    [String]$Path=$(Throw "You must specify a path"),
    [String]$IdentityToCheck="WSS_WPG",
    [String]$RightToCheck="FullControl"
)
    $passtest = $true
    $Output = GCI $Path -Recurse -Directory|%{
        $PathName=$_.FullName
        # make sure each directory and subdirectory has WSS_WPG and FullControl
        $wsscheck = $false
        $rightcheck = $false
        $_.GetAccessControl().Access|%{
            if($_.IdentityReference.Value.Contains($IdentityToCheck)) {
                if($_.FileSystemRights.ToString().Contains($RightToCheck)) {
                    $rightcheck = $true
                }
                $wsscheck = $true
            }

        }
        if(-not $wsscheck) {
            $passtest = $false
			Write-SRx WARNING ("Identity $IdentityToCheck was not granted rights on this directory: $PathName")
            
        }
        if(-not $rightcheck) {
            $passtest = $false
			Write-SRx WARNING ("File System Right $RightToCheck does not exist for $IdentityToCheck on this directory: $PathName")
        }
    }
	return $passtest
}


#=====================================
#== MSOL / Azure AD Related Methods ==
#=====================================

function Connect-SRxToMsolService {
<#
.SYNOPSIS
	Verifies if existing MsolConnection established, otherwise prompts the user to connect
#>
[CmdletBinding()]
param ( [parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]$credential ) #$credential = $( do something here or default to $null) #toDo: Determine if we can use the OS Credential Manager to store a credential ...and then retrieve it here
    $isConnected = $( if ($global:SRxEnv.MsolServiceConnection -is [bool]) { $global:SRxEnv.MsolServiceConnection } else { $false } )
    #if not connected to MSOL and "Connect-MsolService" is a command in the current shell...
    if ((-not $isConnected) -and $(Get-Command "Connect-MsolService" -ErrorAction SilentlyContinue) -ne $null) { 
        $isConnected = ((Get-MsolAccountSku -ErrorAction SilentlyContinue) -ne $null)
        if (-not $isConnected) {
            try {
                if ($credential) {
                    Connect-MsolService -Credential $Credential
                } else {
                    Write-SRx INFO (" > Please provide your credentials to connect to the MSOL Service") -ForegroundColor Yellow
                    Connect-MsolService
                }
                $isConnected = ((Get-MsolAccountSku -ErrorAction SilentlyContinue) -ne $null)
            } catch { 
                $isConnected = $false
            }
        }
    }
    $global:SRxEnv.SetCustomProperty("MsolServiceConnection", $isConnected)
    return $isConnected
}

#======================================
#== Extensions to the $SRxEnv object ==
#======================================
if ($global:SRxEnv.Exists) {
	$global:SRxEnv | Set-SRxCustomProperty "h" $(New-Object PSObject)
	$global:SRxEnv.h | Set-SRxCustomProperty "description" "Utility Helper Methods"
	$global:SRxEnv.h | Add-Member -Force ScriptMethod -Name isNumeric -Value { 
		param ( $value ) 
		return $value -match "^[\d\.]+$"
	}
	$global:SRxEnv.h | Add-Member -Force ScriptMethod -Name isUnknownOrNull -Value { 
		param ( $value ) 
		return ( [string]::IsNullOrEmpty($value) -or ( ($value -is [string]) -and ($value -eq 'unknown') ) )
	}
	$global:SRxEnv.h | Add-Member -Force ScriptMethod -Name isUnknownOrZero -Value { 
		param ( $value ) 
		return (
            ([string]::IsNullOrEmpty($value)) -or ($value -eq 0) -or ( 
               ($value -is [string]) -and (($value -eq "0") -or ($value -eq 'unknown'))
            ))
	}
	$global:SRxEnv.h | Add-Member -Force ScriptMethod -Name isUnknown -Value { 
		param ( $value ) 
		return ( ($value -is [string]) -and ($value -eq 'unknown') )
	}
	$global:SRxEnv.h | Add-Member -Force ScriptMethod -Name GetDiscreteTime -Value { 
		param ( [datetime]$t, $interval = 15 )
		$midPoint =  [math]::Round($interval/2)
		
		#Rounds a datetime to a discrete point in time (e.g. useful for charting points in time)
		return $t.AddMinutes( 
					$($x = $t.Minute % $interval; if ($x -lt $midPoint) {(-1)*$x } else {$interval-$x}) 
				).AddSeconds( (-1)*($t.Second) )
	}
    $global:SRxEnv.h | Add-Member -Force ScriptMethod -Name BuildHandleMappings -Value { 
		param ( [bool]$invalidatePreviousMappings = $false )
        
        $map = @()
        foreach ($name in $global:___SRxCache.SSASummaryList.Name) {
            $handle = "" #the assumed value
            if (-not $invalidateSiblingMappings) {
                if (($name -eq $global:SRxEnv.SSA) -and ($global:SRxEnv.Dashboard.Handle -ne $null))  { 
                    $handle = $global:SRxEnv.Dashboard.Handle
                } else {
                    $mappedHandle = $($global:SRxEnv.HandleMap | Where {$_.Name -eq $name}).Handle
                    if ($mappedHandle.count -gt 1) {
                        #this path should not happen *(implies multiple SSAs with the same name)
                        Write-SRx WARNING $("[`$SRxEnv.h.BuildHandleMappings] Invalid HandleMap: Multiple SSAs map to '" + $SSA + "' ...ignoring map")
                        $mappedHandle = ""
                    }
                    if (-not [string]::isNullOrEmpty($mappedHandle)) {
                        $handle = $mappedHandle
                    }
                }
            }
            Write-SRx VERBOSE $(" --> Mapping SSA '" + $name + "', to Handle: '" + $handle + "'")
            $map += $( New-Object PSObject -Property @{ "Name" = $name; "Handle" = $handle } )
        }
        $global:SRxEnv.PersistCustomProperty("HandleMap", $map)
    }
}

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAsSeheZUd69oiF
# TGbFsx245rFCuL7eBweIChfN7vNUf6CCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIJ11kJP5FPajUkRzNfJgyIQBVEQviOwsukhJZhoLk5QtMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBABVB/UA+VHpPbVeCvyeMwZOT
# E+8VpK/y0yB4Dc5aWCN2lopLGGw8zh3pYYOTy/FEHSzpFw1RNXlbyhC6JHr4Gk8D
# pxt1fsVm3ZC9F74TxBsJLokss7G/1o7KczjQjrMo8xCC4POkvlD7R+UUsjYubKXc
# yQVpOKi4MN3nh9G7rnQUolYrJ2RJaJInfCs8GmmCxyTRXbHvmngjoCvbYZUyGTDh
# af66Wfe1M2NyZN47L2H8HpSq4d5fty1kz4LfZnJJjFA9yod1dk5EEXL7lNa36KVY
# a8QgOJvAmQdzqGma9AuYQROpoeM5Gb1VipdqBZ8bDmcI988+m27IQ4i3wEpHS0eh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgdpAR26MVP9e+Gp1HbUhH
# kSqQkbzhOrH9OzItP3KrDdICBljVOtTJeRgTMjAxNzA0MjYyMzU0MDAuODAyWjAH
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
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIDGoyy7fArQHU4rF
# kjoK97PmlnbTgqSNzur14YuDCnn0MIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUvf/FlWOQ8ROcYNYZwK/puJ4eIB0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAALI1BWg3IhwNpwAAAAAAsjAWBBSRrnb7XKTtB5IW
# rfee9hkzrTNhXzANBgkqhkiG9w0BAQsFAASCAQA7c4F9bDYne15ZKm4J+ACBo7GE
# V8a0Y80Wt2Cqp71qCPJMNI7Hh08QSO3qoGu3rXc3U+HgxGDnuGo4ukitKtu3slKk
# 1bG9K02VNeO0Y8k/zgG1wPhk43LRz31f0FSloVeWn+N9kZ36PbH/Z+R6seHc4eDk
# JIec/OBHGdDHRXSiOTEonpJrmBzOcHFQEQBpf14kS4iDmRL7w2Dx/1j3/zqY/H+h
# bJjfnWsrEPU4mmykp1cwlXJyOpQI2G1aEURrKFgs6n1walv3bgbARPVHjcVTNSje
# G4Sxm4rvdADGWM+y+utRIidjRXcfT2bk6NEUwhlotIfXPxRiXaXjoWW9FYz1
# SIG # End signature block
