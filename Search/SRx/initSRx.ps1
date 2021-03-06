<#
.SYNOPSIS 
	The Search Health Reports (SRx) Initialization Wrapper

.DESCRIPTION 
	This helper script sets up the SRx environment by loading applicable SharePoint PowerShell SnapIns and loading all SRx modules prior to launching the core Get-SRxSSA module (which creates the extended $xSSA)

.NOTES
	=========================================
	Project		: Search Health Reports (SRx)
	-----------------------------------------
	File Name 	: initSRx.ps1
    Author		: Brian Pendergrass
    Contributors: Nicolas Uthurriague, Eric Dixon	
	Requires	: PowerShell Version 3.0, Microsoft.SharePoint.PowerShell
	
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
			  any claims or lawsuits, including attorneysâ€™ fees, that arise or result from 
			  the use or distribution of the Sample Code.

	========================================================================================
	
.INPUTS
	N/A

.OUTPUTS
	$SRxEnv : Contains properties about the environment (e.g. Paths) and run-time configuration 
	$xSSA : An extended Search Service Application object

.EXAMPLE
	.\initSRx.ps1
	Default invocation of the SRx. Assumes SharePoint 2013 as the target Product environment

.EXAMPLE
	.\initSRx.ps1 -SSA "Search Service Appplication 1"
	Default invocation of the SRx targeting a specific Search Service Application

.EXAMPLE
	.\initSRx.ps1 -SRxConfig "custom.config.json"
	Starts the SRx using "custom.config.json" for any custom configuration
	
	.\initSRx.ps1 -SRxConfig @{ "Product" = "customFoo"; "Paths" = @{ "Log" = $ENV:TEMP } } 
	Starts the SRx using a hashtable object (e.g. @{} ) supplied as a command line argument

.EXAMPLE
	.\initSRx.ps1 -SRxConfig @{ "ProductInitScript" = "c:\custom\lib\scripts\productInit.ps1"} } 
	Starts the SRx, but also triggers productInit.ps1 to run BEFORE loading any of the SRx modules

.EXAMPLE
	.\initSRx.ps1 -SRxConfig @{ "PostInitScript" = "c:\custom\lib\scripts\runAfterInit.ps1"} } 
	Starts the SRx and then triggers runAfterInit.ps1 to run as the last step in initSRx.ps1

.EXAMPLE
	Not Yet Implemented
	#.\initSRx.ps1 -SilentMode
	#Starts the SRx in script mode (supresses all messages sent to the screen)
#>
[CmdletBinding()]
param (
		[parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
			[alias("SearchServiceApplication","Handle")]$SSA,  #== Target a Search Service Application ($SSA) by name or by object
		[parameter(Mandatory=$false,ValueFromPipeline=$false)]
			$SRxConfig,   #== Specify a custom.config.json or hashtable with config options
		
        #== Run test(s) after the environment loads...
        [parameter(Mandatory=$false,ValueFromPipeline=$false)]
			$ControlFile,   #== Run tests using a specific control file
        [parameter(Mandatory=$false,ValueFromPipeline=$false)]
			$Test,          #== Run a specific test
		
		#== Implementation flags...
        [switch]$CoreEnv,                #== Use this to only load core SRxEnv (e.g. for version and hash checking)
        [switch]$SPO,                    #== Use this to only load a minimal environment that is SPO-centric
		[alias("DashboardInstallOnly")]
        [switch]$ContentFarm,	         #== If this is run on a Content Farm, then skip any Search related configuration (e.g. farm only)
		[switch]$Extended,	             #== Implement any extended configuration (e.g. build out extended properties and methods)
        [alias("ScheduledTask")]
        [switch]$UseReadOnlyConfig,      #== Set the Custom Config File to ReadOnly

		#== Development/Debug flags...
		[switch]$TrackDebugTimings,      #== Creates an additional structure for tracking timings within modules (where applicable)
		[switch]$RebuildSRx,		     #== Removes the modules before loading them (ensures newest source is being loaded)
		
		#== To set $SRxEnv.Log.Level (e.g. logging verbosity)
		[alias("INFO")][switch]$INFOLogLevel,
		[alias("SILENT")][switch]$SILENTLogLevel
		#The -VERBOSE and -DEBUG flags are also supported
	  )

#=========================================================
#== Global environment variables and ensure requirements
#=========================================================

#== Global type def for logging level (SRxLogLevel)
Add-Type -ErrorAction SilentlyContinue -TypeDefinition @"
public enum SRxLogLevel { SILENT, ERROR, WARNING, INFO, VERBOSE, DEBUG } 
"@

$SRxLogLevel = $( 
    if($PSBoundParameters['Debug']) { [SRxLogLevel]::Debug }				#ex: .\initSRx.ps1 -debug
    elseif($PSBoundParameters['Verbose']) {	                                #ex: .\initSRx.ps1 -verbose
        [SRxLogLevel]::Verbose 
        $VerbosePreference = "SilentlyContinue"
    }		
    elseif ($INFOLogLevel) { [SRxLogLevel]::INFO }							#ex: .\initSRx.ps1 -info
    elseif ($SILENTLogLevel) { [SRxLogLevel]::SILENT }						#ex: .\initSRx.ps1 -silent
    elseif($global:SRxEnv.Log.Level) { [SRxLogLevel]::$($global:SRxEnv.Log.Level) }  #ex: assumes rebuild of env
    else { [SRxLogLevel]::INFO }											#defaults to INFO level
)

#== Temporary internal variables (e.g. set as global so external scripts can set this at run time)
    $SRxConfigPath = "\etc\SRxMgmt\"  #sub-path to the .json config files
    #-- Run-time properties
    $SRxCurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $isBuiltinAdmin = $([Security.Principal.WindowsPrincipal] $SRxCurrentUser).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

	#-- Trigger automatic rebuild for the following scenarios
    $RebuildSRx = $($RebuildSRx -or $global:__SRxHasInitFailure -or ($SSA -and $xSSA._hasSRx -and ($xSSA.Name -ne $SSA)))

#== Global variables that external scripts can trigger/set/read
    #-- Flag for tracking initialization failures
    $global:__SRxHasInitFailure = $false   

	#-- Get paths for any modules we need to load up...
	$global:__SRxModulesPathsToLoad = New-Object System.Collections.ArrayList

	#-- List of command strings to be invoked at the end of this init script...
	$global:__SRxInvocationList = New-Object System.Collections.ArrayList

#== Check PowerShell Version Pre-Reqs
if ($Host.Version.Major -lt 3) {
	Write-Warning "[initSRx] SRx requires PowerShell 3.0 or higher! ...exiting script"
	$global:__SRxHasInitFailure = $true
    exit 
}
$ServerVersion = [System.Environment]::OSVersion.Version
if ($ServerVersion.Major -eq 6 -and $ServerVersion.Minor -lt 2) {
	Write-Warning "[initSRx] This server is running a server version prior to Windows 2012."
	Write-Warning "[initSRx] SRx has not been thoroughly tested on older server versions."
	Write-Warning "[initSRx] Some tests may not run successfully."
}


#== Verify that this script is running as administrator
if ((-not $isBuiltinAdmin) -and (-not $CoreEnv) -and (-not $SPO) -and ([Environment]::UserInteractive)) { 
    Write-Warning "The current PowerShell window is not running with the 'Administrator' role (e.g. 'Run as Administrator')"

  	$title = "" 
	$message = "Do you want to proceed without the 'Administrator' role (which may prevent some tests from running successfully)? "    	
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Continue with 'Administrator'"
	$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Stop this initialization script (initSRx.ps1)"
	$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

	$result = $host.ui.PromptForChoice($title, $message, $options, 1)
	switch ($result) 
	{
		0 { Write-Host "...continuing without the 'Administrator' role `n" -ForegroundColor Magenta }
		1 { Write-Host "`n...you may now close this PowerShell window and then open a new with 'Run as Administrator'" -ForegroundColor Cyan; $global:__SRxHasInitFailure = $true; exit }
	}
}

#==============================================
#== Starting initialization and loading SRxEnv
#==============================================
if ($TrackDebugTimings) { $srxInitStart = @{ $(Get-Date) = "Starting initSRx.ps1..." } }

if ($global:SRxEnv.Exists -and (-not $RebuildSRx)) {
    #================================================================
	#== Environment already loaded, so reuse the $SRxEnv hashtable ==
	#================================================================
	$global:SRxEnv.SetCustomProperty("Log.Level", $SRxLogLevel)
    
    if (($global:SRxEnv.paths.SRxRoot -ne $null) -and ($PsScriptRoot -ne $null) -and ($global:SRxEnv.paths.SRxRoot -ne $PsScriptRoot)) {
        Write-Warning $("~~~[initSRx] Ambiguous Request: Attempting to re-initialize with a different initSRx.ps1")
        $global:__SRxHasInitFailure = $true; 
        exit  
    } 

	Write-SRx INFO "======= Reusing `$SRxEnv ======="
} else {
	#==================================================================
	#== Set the global configuration in the $global:SRxEnv hashtable ==
	#==================================================================

    #-- Set the console I/O to be UTF8 friendly to accomodate non-english languages
	if ($Host.Name -eq "ConsoleHost") {
		[system.console]::InputEncoding=[System.Text.Encoding]::UTF8
		[system.console]::OutputEncoding=[System.Text.Encoding]::UTF8
	}

	#-- intended for *internal use only by the SRx (only create if it does not exist or on rebuild)
	if ($global:___SRxCache -isNot [hashtable]) {$global:___SRxCache = @{} }

    #-- Set the list on known SSAs to null
    $global:___SRxCache.SSASummaryList = @()

    #-- set the path to the core config file ("core.config.json")
	if (-not ([String]::IsNullOrEmpty($global:__SRxRootPath))) {
        Write-Host $("Using `$global:__SRxRootPath to set the SRx Root path") -ForegroundColor Magenta
		$SRxRootPath = $global:__SRxRootPath
    } elseif (($global:SRxEnv.paths.SRxRoot -ne $null) -and ($global:SRxEnv.paths.SRxRoot -ne $PsScriptRoot)) {
        Write-Warning $("~~~[initSRx] Ambiguous Request: Attempting to re-initialize with a different initSRx.ps1")
        $global:__SRxHasInitFailure = $true; 
        exit         
	} elseif (-not ([String]::IsNullOrEmpty($PsScriptRoot))) {
		$SRxRootPath = $PsScriptRoot
	} elseif (Test-Path $(Join-Path $PWD.Path "initSRx.ps1")) {
		$SRxRootPath = $PWD.Path
	} else {
		Write-Warning "[initSRx] Unable to find the root path for the SRx! ...exiting script"
        $global:__SRxHasInitFailure = $true
		exit 
	}
	#$SRxRootPath is the folder path where this script exists (which may be different than the current path)
	$configPath = Join-Path $(Join-Path $SRxRootPath $SRxConfigPath) "core.config.json"
	
	#== if exists, load configuration from the core.config.json file
	if (Test-Path $configPath) {
		$readlockRetries = 40
        $config = $null
        do {
		    try {
			    $config = Get-Content $configPath -Raw -ErrorAction Stop
                if ([string]::isNullOrEmpty($config)) {
                    $global:__SRxHasInitFailure = $true
                    $initFailureMessage = " --> The config file $configPath exists, but is empty."
                    $initException = New-Object NullReferenceException("Empty configuration file: $configPath")
                } else { 
                    try {
			            $global:SRxEnv = ConvertFrom-Json $config
		            } catch { 
                        $global:__SRxHasInitFailure = $true
                        $initFailureMessage = " --> Caught exception converting $configPath to object. Check file for syntax errors."
                        $initException = $_
                    }
                }
            } catch [System.IO.IOException] {
                if ($readlockRetries -eq 40) { Write-Host " --> Unable to read $configPath - Retrying up to 10s" -NoNewline -ForegroundColor Yellow }
                elseif ($($readlockRetries % 4) -eq 0) {  Write-Host "." -NoNewline }
                Start-Sleep -Milliseconds 250
                $readlockRetries--
                $initException = $_
            } catch {
                $global:__SRxHasInitFailure = $true
                $initFailureMessage = " --> Caught exception reading $configPath from disk"
                $initException = $_
            }
        } while (($readlockRetries -gt 0) -and ([string]::isNullOrEmpty($config)) -and (-not $global:__SRxHasInitFailure))
	} else { 
        $initFailureMessage = " --> The config file $configPath is inaccessible or does not exist"
        $initException = New-Object NullReferenceException("Configuration file does not exist: $configPath")
    }
 
    if ([string]::isNullOrEmpty($config) -or $global:__SRxHasInitFailure) {
        $tmpErrorLog = Join-Path $SRxRootPath "var\log\error.log"
        $("-" * 50) | out-file $tmpErrorLog -append
        "--[ initialization failure: " + $(get-date) + " ]" | out-file $tmpErrorLog -append
        $("-" * 50) | out-file $tmpErrorLog -append
        $initFailureMessage | out-file $tmpErrorLog -append
        $initException | out-file $tmpErrorLog -append
        $("`n ...exiting. `n") | out-file $tmpErrorLog -append
        if ($initException) { 
            throw ($initException)
        }
        exit
    }

   	#== Create utility methods for the $SRxEnv object
	$global:SRxEnv | Add-Member -Force -MemberType ScriptMethod -Name UpdateShellTitle	-Value {
		param([string]$trailingText = "")
		if ($global:SRxEnv.isBuiltinAdmin) { $adminPrefix = "Administrator: " }
		if ([String]::IsNullOrEmpty($trailingText) -and ($global:SRxEnv.SRxVersion -ne "__REPLACE_WITH_VERSION_NUMBER_NAME__")) { 
			$trailingText = " - " + $global:SRxEnv.SRxVersion 
		}
		(Get-Host).UI.RawUI.WindowTitle = $($adminPrefix + $global:SRxEnv.SRxTitle + " " + $trailingText)
	}
	#-- Set the title for this shell window
	$global:SRxEnv.UpdateShellTitle("(Initializing...)")

	$global:SRxEnv | Add-Member -Force -MemberType ScriptMethod -Name ResolvePath	-Value {
		param([string]$pathStub = "")

		if (-not [String]::IsNullOrEmpty($pathStub)) { 
			if ($pathStub.StartsWith(".\")) { return Join-Path $global:SRxEnv.Paths.SRxRoot $pathStub.SubString(2) } #strip off the ".\"
			elseif ($pathStub.StartsWith($global:SRxEnv.Paths.SRxRoot)) { return $pathStub }
			elseif (($pathStub.StartsWith("`"$")) -or ($global:SRxEnv.Paths.$pathStub.StartsWith("$"))) {
				try {
					return $(Invoke-Expression $global:SRxEnv.Paths.$pathStub)
				} catch { }
			} 
			elseif (Test-Path $pathStub) { return $pathStub }
		}
		
		#if we're still here, then throw a warning
		Write-SRx WARNING $("~~[`$SRxEnv.ResolvePath(`$path)] Unable to resolve path: " + $pathStub)
	}

	$global:SRxEnv | Add-Member -Force -MemberType ScriptMethod -Name CreateFileWithReadPermissions -Value { 
		param ($filePath)
		
		if (-not [string]::IsNullOrEmpty($filePath)) {
			if (-not $(Test-Path $filePath)) { 
				$file = New-Item -Path $filePath -ItemType File

				# set permissions for user group so any user can open/write (if Admin is the first, other non-Admin users would get locked out)
				$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(".\Users","FullControl","Allow")
				$acl = Get-Acl $file.FullName
				$acl.SetAccessRule($rule)
				Set-Acl $file.Fullname $acl 
			}
		}
	}
	
	$global:SRxEnv | Add-Member -Force -MemberType ScriptMethod -Name SetCustomProperty -Value { 
		param ([String]$propertyName, $propertyValue)
		
		if (($propertyName.Contains(".")) -and ($(Get-Command "Set-SRxCustomProperty" -ErrorAction SilentlyContinue) -ne $null)) {
			$this | Set-SRxCustomProperty $propertyName $propertyValue
		} else {
			if ( $( $this | Get-Member -Name $propertyName) -ne $null ) { 
		        #if the property already exists, just set it
				$this.$propertyName = $propertyValue
			} else {
				#add the new member property and set it
				$this | Add-Member -Force -MemberType "NoteProperty" -Name $propertyName -Value $propertyValue 
			}
		}
	}
		
    $global:SRxEnv | Add-Member -Force -MemberType ScriptMethod -Name PersistCustomProperty -Value { 
		param ([String]$propertyName, $propertyValue, [bool]$persistToFile = $true)
		
        $this.SetCustomProperty($propertyName, $propertyValue)
		if ($persistToFile) {		
			if ($global:SRxEnv.CustomConfigIsReadOnly) {
                Write-SRx Warning $("~~~ The property '" + $propertyName + "' cannot be persisted (the custom config file is read only or inaccessible) - skipping...")
            } else { 
                # -- add propert info to $SRxEnv.CustomConfig (e.g. custom.config.json)
                $readlockRetries = 40
                $persistFailure = $false
                $config = $null
                do {
                    try {
                        Write-SRx VERBOSE $("<-Persisting- '" + $propertyName + "' to " + $global:SRxEnv.CustomConfig) -ForegroundColor Yellow
			            $config = Get-Content $($global:SRxEnv.CustomConfig) -Raw -ErrorAction Stop
                        if ([string]::isNullOrEmpty($config)) {
                            $persistFailure = $true
                            Write-SRx Warning $("~~~ The property '" + $propertyName + "' cannot be persisted (the custom config file is null or empty) - skipping...")
                        } else {                        
                            try {
			                    $tmpSRxEnv = ConvertFrom-Json $config -ErrorAction SilentlyContinue
			                    if ($(Get-Command "Set-SRxCustomProperty" -ErrorAction SilentlyContinue) -ne $null) {
				                    $tmpSRxEnv | Set-SRxCustomProperty $propertyName $propertyValue
			                    } else {
				                    $tmpSRxEnv | Add-Member -Force -MemberType "NoteProperty" -Name $propertyName -Value $propertyValue
			                    }
                                $jsonConfig = ConvertTo-Json $tmpSRxEnv -Depth 12
                            } catch { 
                                $persistFailure = $true
                                Write-Error $(" --> Caught exception converting `$global:SRxEnv.CustomConfig to object/JSON. Check for syntax errors - skipping: " + $propertyName)
                            } 
                        }
                    } catch [System.IO.IOException] {
                        if ($readlockRetries -eq 40) { Write-SRx INFO " --> Unable to read $configPath - Retrying up to 10s" -NoNewline -ForegroundColor Yellow }
                        elseif ($($readlockRetries % 4) -eq 0) {  Write-SRx INFO "." -NoNewline }
                        Start-Sleep -Milliseconds 250
                        $readlockRetries--
                    } catch {
                        $persistFailure = $true
                        Write-Error $(" --> Caught exception reading `$global:SRxEnv.CustomConfig when persisting a change - skipping: " + $propertyName)
                    }
                } while (($readlockRetries -gt 0) -and ([string]::isNullOrEmpty($jsonConfig)) -and (-not $persistFailure))
			
                if ([string]::isNullOrEmpty($jsonConfig) -and ($readlockRetries -lt 1)) {
                    Write-SRx Warning $("~~~ Timed out waiting for a read/write lock on `$global:SRxEnv.CustomConfig - skipping: " + $propertyName)
                } elseif (-not [string]::isNullOrEmpty($jsonConfig)) {
                    try {
                        $jsonConfig | Set-Content $($global:SRxEnv.CustomConfig) -ErrorAction Stop
                    } catch {
                        Write-SRx Warning $("~~~ Unable to obtain a read/write lock on `$global:SRxEnv.CustomConfig - skipping: " + $propertyName)
                    }
                }
            }
		}
	}
 
  	#-- Ensure the $SRxEnv.Paths object is defined
	if ($global:SRxEnv.Paths -isNot [PSCustomObject]) { $global:SRxEnv.SetCustomProperty("Paths", $(New-Object PSObject)) }
	
	if (-not $global:SRxEnv.Paths.SRxRoot) { 
		$global:SRxEnv.Paths | Add-Member -Force "SRxRoot" $SRxRootPath 
	} else { 
		$global:SRxEnv.Paths.SRxRoot = $SRxRootPath 
	}
	
	if (-not $global:SRxEnv.Paths.Mgmt) { 
		$global:SRxEnv.Paths | Add-Member -Force "Mgmt" $(Join-Path $SRxRootPath $SRxConfigPath) 
	} else { 
		$global:SRxEnv.Paths.Mgmt = $global:SRxEnv.ResolvePath($global:SRxEnv.Paths.Mgmt) 
	}

	if ($TrackDebugTimings) {
		Write-Host "Adding `$SRxEnv.DebugTimings" -ForegroundColor Magenta 
		$global:SRxEnv.SetCustomProperty("DebugTimings", @{})
		$global:SRxEnv.DebugTimings["[initSRx]"] = $(New-Object System.Collections.ArrayList)
		$global:SRxEnv.DebugTimings["[initSRx]"].Add( $srxInitStart ) | Out-Null
		$global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Loaded core methods..." } ) | Out-Null
	}
 	
	#== Configure SRx Logging
  	#-- Ensure the $SRxEnv.Log object is defined
	if ($global:SRxEnv.Log -isNot [PSCustomObject]) { 
        $logObj = New-Object PSObject -Property @{
            "Level" = "INFO";
            "ToFile" = $true;
            "RetentionBytes" = 600MB;
            "RetentionDays" = 90;
        }
        $global:SRxEnv.SetCustomProperty("Log", $logObj)
    }

    #-- Set the verbosity of logging...
	if ([string]::IsNullOrWhiteSpace($global:SRxEnv.Log.Level)) { 
		$global:SRxEnv.Log | Add-Member -Force "Level" $SRxLogLevel 
	} else { 
		$global:SRxEnv.Log.Level = $SRxLogLevel 
	}

	#-- enable/disable logging to a file
	if ($global:SRxEnv.Log.ToFile -is [bool]) { 
        $actualLogToFileSetting = $global:SRxEnv.Log.ToFile 
    } else { 
        $actualLogToFileSetting = $false
        $global:SRxEnv.Log | Add-Member -Force "ToFile" $true
    }
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Configured SRx logging settings..." } ) | Out-Null }

	#-- if the SRx log folder/file is not already configured or it does not exist...
	if ([String]::IsNullOrEmpty($global:SRxEnv.LogFile) -or (-not (Test-Path $global:SRxEnv.LogFile))) {
		#...then temporarily disable file logging ($EnableLogToFile = $false) until further into the initialization
        $global:SRxEnv.Log.ToFile = $false
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Tested path for SRx LogFile, disabled Log.ToFile..." } ) | Out-Null }
	} else { 
        $global:SRxEnv.Log.ToFile = $actualLogToFileSetting
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Tested path for SRx LogFile, enabled Log.ToFile..." } ) | Out-Null }
	}

	#-- Load the SRx Logging module
	$loggingModule = $(Join-Path $global:SRxEnv.Paths.SRxRoot "Modules\Core\Write-SRx.psm1")
	try {
	    if ([SRxLogLevel]::$($global:SRxEnv.Log.Level) -ge [SRxLogLevel]::INFO) { 
			Write-Host "[initSRx] Loading SRx logging module..."
		}
	    if($RebuildSRx) { 
			Remove-Module "Write-SRx" -ErrorAction SilentlyContinue 
			if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Removed SRx logging module..." } ) | Out-Null }
		}
	    Import-Module $loggingModule
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Loaded SRx logging module..." } ) | Out-Null }
	}
	catch {
		if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Failed loading SRx logging module..." } ) | Out-Null }
	    Write-Error "[initSRx] Unable to load the SRx logging module.  Path = $loggingModule"
	    Write-Error $_
	    exit
	}

 	#== Apply any overrides supplied in custom.config.json (if it exists)
	if ($SRxConfig -is [String]) {
		if ($SRxConfig.EndsWith(".config.json")) {
			$customConfigPath = $global:SRxEnv.ResolvePath($SRxConfig)
			Write-SRx INFO $("[initSRx] Custom config specified: ") -ForegroundColor Cyan -NoNewline
			Write-SRx INFO $customConfigPath
            if (-not (Test-Path $customConfigPath)) {
                Write-SRx WARNING $("...ignoring custom config file specified with the -SRxConfig param (file does not exist)")
                $customConfigPath = $null
            }
		} else {
			Write-SRx WARNING $("[initSRx] Invalid custom config file specified with the -SRxConfig param (specified file does not end with *.config.json)")
            $customConfigPath = $null
		}
	} 
    
    if ([string]::isNullOrEmpty($customConfigPath)) {
		$customConfigPath = Join-Path $global:SRxEnv.Paths.Mgmt "custom.config.json"
		Write-SRx INFO $("[initSRx] Custom config (default): ") -ForegroundColor Cyan -NoNewline
		Write-SRx INFO $customConfigPath
	}

	#-- Set this property in case any other modules want to persist any custom configuration (even if the path does not exist)
	$global:SRxEnv.SetCustomProperty("CustomConfig", $customConfigPath)
    $global:SRxEnv.SetCustomProperty("CustomConfigIsReadOnly", $UseReadOnlyConfig)
	
	if ((-not [string]::isNullOrEmpty($global:SRxEnv.CustomConfig)) -and (Test-Path $global:SRxEnv.CustomConfig)) {
		Write-SRx VERBOSE $("--Loading--> " + $global:SRxEnv.CustomConfig)

        try {
			$config = Get-Content $global:SRxEnv.CustomConfig -Raw
			$customConfig = ConvertFrom-Json $config
		} catch { 
			Write-SRx ERROR ("!!! Exception occurred getting content from " + $global:SRxEnv.CustomConfig)
            Write-SRx ERROR ($_.Exception.Message) 
		    Write-SRx VERBOSE ($_.Exception) 
            Write-SRx WARNING $("[initSRx] Unable to load the custom config file; Will block any attempts to persist options here.")
		    $global:SRxEnv.SetCustomProperty("CustomConfigIsReadOnly", $true)
        }

        #temporary helper function
        #function OverlaySubProperties () {
	       # #For $customConfig.$propName, extract each child property and append/overwrite as applicable...
	       # $options = $($customConfig.$propName | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Name
	       # foreach ($configName in $options) {
		      #  Write-SRx VERBOSE $("Custom Config -> $propName." + $configName + " = " + [string]($customConfig.$propName.$configName)) -ForegroundColor Yellow
		      #  if ( $( $global:SRxEnv.$propName | Get-Member -Name $configName) -ne $null ) { 
			     #   #if the property already exists, just set it
			     #   $global:SRxEnv.$propName.$configName = $customConfig.$propName.$configName
		      #  } else {
			     #   #add the new member property and set it
			     #   $global:SRxEnv.$propName | Add-Member -Force -MemberType "NoteProperty" -Name $configName -Value $customConfig.$propName.$configName 
		      #  }					
	       # }
        #}

		$propertyBag = $customConfig | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue
		foreach ($propName in $propertyBag.Name) {
			Write-SRx VERBOSE $("Custom Config: " + $propName) -ForegroundColor Yellow
			switch ($propName) {
				"Paths" {
                    #OverlaySubProperties
					
                    #For Paths, extract each child path name and append/overwrite as applicable...
					$pathNames = $($customConfig.Paths | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Name
					foreach ($pathName in $pathNames) {
						Write-SRx VERBOSE $("Custom Config -> Path : `$pathName = " + $pathName + " [" + $customConfig.Paths.$pathName + "]") -ForegroundColor Yellow
						if ( $( $global:SRxEnv.Paths | Get-Member -Name $pathName) -ne $null ) { 
					        #if the property already exists, just set it
							$global:SRxEnv.Paths.$pathName = $customConfig.Paths.$pathName
						} else {
							#add the new member property and set it
							$global:SRxEnv.Paths | Add-Member -Force -MemberType "NoteProperty" -Name $pathName -Value $customConfig.Paths.$pathName 
						}					
					}
					break
				}
                "Override" {
                    #Create base object if it does not exist...
					if ($global:SRxEnv.Override -eq $null) { $global:SRxEnv.SetCustomProperty("Override", (New-Object PSObject)) }
                    #OverlaySubProperties

                    #For Override options, extract each child config and append/overwrite as applicable...
					$options = $($customConfig.Override | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Name
                    foreach ($configName in $options) {
						Write-SRx VERBOSE $("Custom Config -> Override." + $configName + " = " + [string]($customConfig.Override.$configName)) -ForegroundColor Yellow
						if ( $( $global:SRxEnv.Override | Get-Member -Name $configName) -ne $null ) { 
					        #if the property already exists, just set it
							$global:SRxEnv.Override.$configName = $customConfig.Override.$configName
						} else {
							#add the new member property and set it
							$global:SRxEnv.Override | Add-Member -Force -MemberType "NoteProperty" -Name $configName -Value $customConfig.Override.$configName 
						}					
					}
					break
                }
                #"Servers" {
                    # -- future location for next generation server objects --
                #}
                "Log" {
                    #For Log options, extract each child config and append/overwrite as applicable...
					$options = $($customConfig.Log | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Name
					if ($global:SRxEnv.Log -eq $null) { $global:SRxEnv.SetCustomProperty("Log", (New-Object PSObject)) }
                    foreach ($configName in $options) {
						Write-SRx VERBOSE $("Custom Config -> Log." + $configName + " = " + [string]($customConfig.Log.$configName)) -ForegroundColor Yellow
                        switch ($configName) {
                            "ToFile" { 
					            $actualLogToFileSetting = $customConfig.Log.ToFile 
					            break
				            }
                            "Level" {
                                if ([SRxLogLevel]::$($customConfig.Log.Level) -gt [SRxLogLevel]::$($SRxLogLevel)) { 
	                                $global:SRxEnv.Log.Level = [SRxLogLevel]::$($customConfig.Log.Level)
                                }
                                break
                            }
                            default {
						        if ( $( $global:SRxEnv.Log | Get-Member -Name $configName) -ne $null ) { 
					                #if the property already exists, just set it
							        $global:SRxEnv.Log.$configName = $customConfig.Log.$configName
						        } else {
							        #add the new member property and set it
							        $global:SRxEnv.Log | Add-Member -Force -MemberType "NoteProperty" -Name $configName -Value $customConfig.Log.$configName  
						        }
                            }
                        }	
					}
                    $logObj = $null 
					break
                }
                "HandleMap" {
                    if ($customConfig.HandleMap -is [Hashtable]) {
                        $global:SRxEnv.SetCustomProperty("HandleMap", @($($customConfig.$propName)))
                    } else {
                        $global:SRxEnv.SetCustomProperty("HandleMap", $($customConfig.$propName))
                    }
                    break
                }
				default { $global:SRxEnv.SetCustomProperty($propName, $($customConfig.$propName)) }
			}
		}

        if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Loaded custom.config.json..." } ) | Out-Null }
	
    } elseif (-not [string]::isNullOrEmpty($global:SRxEnv.CustomConfig)) {
        Write-SRx VERBOSE $("--Creating--> " + $global:SRxEnv.CustomConfig)
        $global:SRxEnv.CreateFileWithReadPermissions( $($global:SRxEnv.CustomConfig) )
		try {
		    New-Object PSObject -Property @{ 
			    "Paths" = @{ "Log" = ".\var\log" };
                "RequiredModules" = @();
                "Log" = @{
                    "Level" = "INFO";
                    "ToFile" = $true
                    "RetentionBytes" = 629145600;
                    "RetentionDays" = 90;
                };
                "Tmp" = @{
                    "RetentionBytes" = 629145600;
                    "RetentionDays" = 7;
                };
                "Override" = @{ 
                    "CrawlVisualizationQueryLimit" = 100;
                };
		    } | ConvertTo-Json | Set-Content $global:SRxEnv.CustomConfig -ErrorAction Stop
            $logObj = $null
        } catch {
            Write-SRx Error $("~~~ Unable to obtain a read/write lock when creating `$global:SRxEnv.CustomConfig - skipping its creation...")
            $global:SRxEnv.SetCustomProperty("CustomConfigIsReadOnly", $true)
        }
        if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Created custom.config.json..." } ) | Out-Null }
	} else {
        Write-SRx WARNING $("[initSRx] `$SRxEnv.CustomConfig is null; Will block any attempts to persist options here.")
		$global:SRxEnv.SetCustomProperty("CustomConfigIsReadOnly", $true)
    }
    
 	#== Configure SRx Logging
	if ($logObj -ne $null) { $global:SRxEnv.PersistCustomProperty("Log", $logObj) }

    #-- set the logging path
    if (-not $global:SRxEnv.Paths.Log) { 
		$global:SRxEnv.Paths | Add-Member -Force "Log" $(Join-Path $($global:SRxEnv.Paths.SRxRoot) "\var\log") 
	} else {
		#-- Ensure $SRxEnv.Paths.Log is resolved to a full path (e.g. not a relative path such as .\var\log)
		$global:SRxEnv.Paths.Log = $global:SRxEnv.ResolvePath($global:SRxEnv.Paths.Log)		
	}
	
	#-- if the SRx log folder/file is not already configured or it does not exist...
	if ((-not $global:SRxEnv.LogFile) -or (-not (Test-Path $global:SRxEnv.LogFile))) {
		$logFolder = Join-Path $global:SRxEnv.Paths.Log "Session"
		if (-not (Test-Path $logFolder)) { 
			New-Item -path $logFolder -ItemType Directory | Out-Null
		}
		$currentLogFile = Join-Path -Path $logFolder $("SRx-" + $(Get-Date -Format "yyyyMMddHHmmss") + "-" + $pid + ".log")
	} else {
		$currentLogFile = $global:SRxEnv.ResolvePath($global:SRxEnv.LogFile)
	}
	$global:SRxEnv.SetCustomProperty("LogFile", $currentLogFile)
	$global:SRxEnv.Log.ToFile = $actualLogToFileSetting
	if ($global:SRxEnv.Log.ToFile) {
		Write-SRx INFO $("[initSRx] Current log file: ") -ForegroundColor Cyan -NoNewline
		Write-SRx INFO ($global:SRxEnv.LogFile)
	}
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Configured SRx log file..." } ) | Out-Null }
	
	#== Set the run-time properties
	$global:SRxEnv.SetCustomProperty("CurrentUser", $SRxCurrentUser)
	$global:SRxEnv.SetCustomProperty("isBuiltinAdmin",	$isBuiltinAdmin)

	#== Update the properties for this PowerShell window (e.g. the UI) ===
	if (-not $global:SRxEnv.UI) { $global:SRxEnv.SetCustomProperty("UI", $( New-Object PSObject -Property @{ "MinWidth" = 125; "MinHeight" = 5000; })) } 
	if ((-not $global:SRxEnv.UI.MinWidth) -or ($global:SRxEnv.UI.MinWidth -lt 125)) { $global:SRxEnv.UI | Add-Member -Force -MemberType "NoteProperty" -Name "MinWidth" -Value 125 } 
	if ((-not $global:SRxEnv.UI.MinHeight) -or ($global:SRxEnv.UI.MinHeight -lt 5000)) { $global:SRxEnv.UI | Add-Member -Force -MemberType "NoteProperty" -Name "MinHeight" -Value 5000 } 

	#-- Ensure minimum width and height for this shell window
	if ($Host -and $Host.UI -and $Host.UI.RawUI) {
		$rawUI = $Host.UI.RawUI
		$oldSize = $rawUI.BufferSize
	    if ($oldSize.Width -gt $global:SRxEnv.UI.MinWidth) {
			$global:SRxEnv.UI.MinWidth = $oldSize.Width
		}
		if ($oldSize.Height -gt $global:SRxEnv.UI.MinHeight) {
			$global:SRxEnv.UI.MinHeight = $oldSize.Height
		}
	    $typeName = $oldSize.GetType().FullName
	    $newSize = New-Object $typeName ($global:SRxEnv.UI.MinWidth, $global:SRxEnv.UI.MinHeight)
	    $rawUI.BufferSize = $newSize
	}
	
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Configured run-time properties..." } ) | Out-Null }
}

#== Apply any overrides supplied on the command line
if (($SRxConfig -ne $null) -and ($SRxConfig -is [Hashtable])) {
	foreach ($property in $SRxConfig.Keys) {
		switch ($property) {
			"Paths" {
				if ($SRxConfig.Paths -is [Hashtable]) {
					foreach ($pathName in $SRxConfig.Paths.Keys) {
						if ( $( $global:SRxEnv.Paths | Get-Member -Name $pathName) -ne $null ) { 
					        #if the property already exists, just set it
							$global:SRxEnv.Paths.$pathName = $SRxConfig.Paths[$pathName]
						} else {
							#add the new member property and set it
							$global:SRxEnv.Paths | Add-Member -Force -MemberType "NoteProperty" -Name $pathName -Value $SRxConfig.Paths[$pathName] 
						}
					}
				}
				break
			}
			"RequiredModules" {
                #-- Configurable list of modules that are required to sucessfully load the SRx
                if (($global:SRxEnv.RequiredModules -is [String]) -and (-not ([String]::isNullOrEmpty($global:SRxEnv.RequiredModules)))) {
		            $global:SRxEnv.SetCustomProperty("RequiredModules", @( $global:SRxEnv.RequiredModules ) ) 
	            } elseif ($global:SRxEnv.RequiredModules -isNot [Array]) { 
		            $global:SRxEnv.SetCustomProperty("RequiredModules", @()) 
	            }

                #-- Ensure the incoming $SRxConfig.RequiredModules is an array structure
				if (($SRxConfig.RequiredModules -is [String]) -and (-not ([String]::isNullOrEmpty($SRxConfig.RequiredModules)))) {
                    $modules = @( $SRxConfig.RequiredModules )
                } elseif (($SRxConfig.RequiredModules -is [Array]) -or ($SRxConfig.RequiredModules -is [System.Collections.ArrayList])) { 
				    $modules = $SRxConfig.RequiredModules
                } else {
                    $modules = @()
                }	
					
                #-- Add each module if it doesn't already exist (e.g. ignore duplicates)
				foreach ($module in $modules) {
					if (-not ($global:SRxEnv.RequiredModules -contains $module)) {
						$global:SRxEnv.RequiredModules += $module
					}
				}
				break
			}
			default { $global:SRxEnv.SetCustomProperty($property, $SRxConfig[$property]) }
		}
	}
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Processed `$SRxConfig overrides..." } ) | Out-Null }
}

#== Resolve any relative or variable valued paths ..and validate existance
foreach ($pathName in $($global:SRxEnv.Paths | Get-Member | Where {$_.MemberType -eq "NoteProperty"}).Name) {
	#Ensure this path is resolved to a full path (e.g. not a relative path such as ./somePathName or $PWD/somePathName)
	$global:SRxEnv.Paths.$pathName = $global:SRxEnv.ResolvePath($global:SRxEnv.Paths.$pathName)
	
	switch ($pathName) {
		"Modules" {
			#== "Modules" path for "Search" specific modules, "Core" helper modules (e.g. utility functionality), and any product specific modules (e.g. "SP2013", "SP2016", etc)
			#-- x:\<SRxProjectPath>\Modules
			if (-not (Test-Path $global:SRxEnv.Paths.Modules)) {	
				Write-SRx WARNING $("[initSRx] Invalid path specified for Modules: " + $global:SRxEnv.Paths.Modules)
				$global:__SRxHasInitFailure = $true
			}
			break
		}
		"Log" { 
			#== "Log" path for results and user output
			#-- x:\<current-path>\var\log
			if (-not (Test-Path $global:SRxEnv.Paths.Log)) {	
				New-Item $global:SRxEnv.Paths.Log -Type Directory -ErrorAction SilentlyContinue| Out-Null
				#Verify that it did get created...
				if (-not (Test-Path $global:SRxEnv.Paths.Log)) {	
					Write-SRx WARNING $("[initSRx] Unable to create the Log path: " + $global:SRxEnv.Paths.Log)
					$global:__SRxHasInitFailure = $true
				} else {
				Write-SRx INFO $("[initSRx] Results and Logging Path: " + $global:SRxEnv.Paths.Log) 
			}
			}
			break
		}
		"Scripts" {
			#== "Scripts" path (e.g. useful for custom scripts)
			#-- x:\<SRxProjectPath>\Scripts
			if (-not (Test-Path $global:SRxEnv.Paths.Scripts)) {
				Write-SRx WARNING $("[initSRx] Invalid path specified for Scripts: " + $global:SRxEnv.Paths.Scripts)
			} else {
				if (-not ($Env:Path).ToLower().Contains($global:SRxEnv.Paths.Scripts.ToLower())) {
					#Append to the $ENV:Path (if it doesn't already exist)
					$ENV:Path += ";" + $global:SRxEnv.Paths.Scripts
					Write-SRx INFO $("[initSRx] Appending the Scripts folder (" + $global:SRxEnv.Paths.Scripts + ") to `$ENV:Path")
				}
			}
			break
		}
		"Tools" {
			#== "Tools" path (e.g. for ULSViewer)
			#-- x:\<SRxProjectPath>\Tools
			if (-not (Test-Path $global:SRxEnv.Paths.Tools)) {
                if ($global:SRxEnv.Paths.Tools.toLower().startsWith($global:SRxEnv.Paths.SRxRoot.toLower())) {
				    Write-SRx VERBOSE $("[initSRx] Removing `$SRxEnv.Paths.Tools because the specified path does not exist")
				    $global:SRxEnv.Paths.PSObject.Properties.Remove("Tools")
                } else {
                    Write-SRx WARNING $("[initSRx] Invalid path specified for Tools: " + $global:SRxEnv.Paths.Tools)
                }
			} else {
                if (-not ($Env:Path).ToLower().Contains($global:SRxEnv.Paths.Tools.ToLower())) {
					#Append to the $ENV:Path (if it doesn't already exist)
					$ENV:Path += ";" + $global:SRxEnv.Paths.Tools
					Write-SRx INFO $("[initSRx] Appending the Tools folder (" + $global:SRxEnv.Paths.Tools + ") to `$ENV:Path")
			}
			}
			break
		}
        "Tmp" { 
			#== ".\var\tmp" path for temporary system storage
			#-- x:\<current-path>\var\tmp
			if (-not (Test-Path $global:SRxEnv.Paths.Tmp)) {	
				New-Item $global:SRxEnv.Paths.Tmp -Type Directory -ErrorAction SilentlyContinue| Out-Null
				#Verify that it did get created...
				if (-not (Test-Path $global:SRxEnv.Paths.Tmp)) {	
					Write-SRx WARNING $("[initSRx] Unable to create the output path: " + $global:SRxEnv.Paths.Tmp)
					$global:__SRxHasInitFailure = $true
				} else {
				Write-SRx INFO $("[initSRx] Temporary SRx Storage: " + $global:SRxEnv.Paths.Tmp) 
			}
			}
			break
		}
		default {  
			if (-not (Test-Path $global:SRxEnv.Paths.$pathName)) {	
				Write-SRx WARNING $("[initSRx] Invalid path specified for " + $pathName + ": " + $global:SRxEnv.Paths.$pathName)
			}
		}
	}	
}
if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Resolved all paths in `$SRxEnv.Paths..." } ) | Out-Null }


if ((-not $global:__SRxHasInitFailure) -and (-not $CoreEnv)) {
    #=============================================================================================
    #== Perform any Product-specific intialization (e.g. ensure applicable snap-ins are Loaded) ==
    #=============================================================================================
    if ($SPO) { 
        Write-SRx VERBOSE "Configuring for SharePoint Online"
		while (-not $global:SRxEnv.SPOTenantUrl) {
            $tenantUrl = Read-Host "Please enter your SPO Tenant URL (e.g. https://contoso.sharepoint.com/)"
            if (-not $tenantUrl.StartsWith("https://")) { $tenantUrl = "https://" + $tenantUrl }
			if (-not $tenantUrl.EndsWith("/")) { $tenantUrl += "/" }
			#casting $tenantUrl to [URI] and using the AbsoluteUri property ensures this a valid URL structure ...otherwise it's $null
			$tenantUrl = ([URI]$tenantUrl).AbsoluteUri
			$global:SRxEnv.PersistCustomProperty("SPOTenantUrl", $tenantUrl)
        }
		if ($global:SRxEnv.Product -eq $null) {
			$global:SRxEnv.PersistCustomProperty("Product", "SPO") 
        }
    }
	$SPO = ($global:SRxEnv.Product -eq "SPO")

    if (-not $global:SRxEnv.ProductInitScript) { 
		$initScript = $(Join-Path $global:SRxEnv.Paths.Scripts $("load" + $(if ($SPO) {"SPO"}) + "PreReqs.ps1"))
        $global:SRxEnv.SetCustomProperty("ProductInitScript", $initScript) 
    }

    $resolvedProductInitScript = $global:SRxEnv.ResolvePath($global:SRxEnv.ProductInitScript)
    if ($resolvedProductInitScript -and (Test-Path $resolvedProductInitScript)) {
	    #run a custom product initialization script here
	    $global:SRxEnv.UpdateShellTitle("(Running ProductInitScript...)")
	    . $resolvedProductInitScript  #run this script in local scope
	
	    if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Ran `$SRxEnv.ProductInitScript..." } ) | Out-Null }
    }

	if ((-not $SPO) -and ($global:SRxEnv.Product -eq $null)) {
		try { 
            #the Get-SPFarm may potentially not be loaded... so wrapping this in try/catch
			$global:SRxEnv.PersistCustomProperty("Product", $( 
				switch ((Get-SPFarm).BuildVersion.Major) {
		        	14 { "SP2010" } 15 { "SP2013" } 16 { "SP2016" }
		    	}))
		} catch {
    	    Write-SRx WARNING $("[initSRx] Caught exception while getting product version from Get-SPFarm")
			$global:SRxEnv.SetCustomProperty("Product", $null)
		}
    }

    #HINT: if you need to prevent this initSRx.ps1 script from continuing,
    #      have the custom script set $global:__SRxHasInitFailure = $true
    if ($global:__SRxHasInitFailure) { 
	    Write-SRx WARNING $("[initSRx] Product Init Script set `$__SRxHasInitFailure!  ...exiting script")
        exit
    } 
} else {
	$global:SRxEnv.SetCustomProperty("CoreEnv", $true)
}

#The final marker to signal the core SRx stood up... 
if ((-not $global:__SRxHasInitFailure) -and (-not $global:SRxEnv.Exists)) { $global:SRxEnv.SetCustomProperty("Exists", $true) }

#==================
#== Load Modules ==
#==================
if (-not $global:__SRxHasInitFailure) {
    #-- Set the title for this shell window
    $global:SRxEnv.UpdateShellTitle("(Loading...)")

    #-- Configurable list of modules that are required to sucessfully load the SRx
    if (($global:SRxEnv.RequiredModules -is [String]) -and (-not ([String]::isNullOrEmpty($global:SRxEnv.RequiredModules)))) {
	    $global:SRxEnv.RequiredModules = @( $global:SRxEnv.RequiredModules )
    } elseif ($global:SRxEnv.RequiredModules -isNot [Array]) { 
	    $global:SRxEnv.SetCustomProperty("RequiredModules", @()) 
    }

    #-- Add to $__SRxModulesPathsToLoad if path exists: x:\<SRxProjectPath>\Modules\Core
    $_coreModules = Join-Path $global:SRxEnv.Paths.Modules "Core"
    if (Test-Path $_coreModules) { $global:__SRxModulesPathsToLoad.Add($_coreModules) | Out-Null }

    #-- [Optional] Load "product" modules ...but skip if just loading up the Core SRx (e.g. for version/hash checking)
    if ((-not $CoreEnv) -and ($global:SRxEnv.Product -ne $null)) {
	    #-- Add to $__SRxModulesPathsToLoad if path exists: x:\<SRxProjectPath>\Modules\SP2013
	    $_productModules = Join-Path $global:SRxEnv.Paths.Modules $global:SRxEnv.Product
	    if (Test-Path $_productModules) { $global:__SRxModulesPathsToLoad.Add($_productModules) | Out-Null }

        #-- For different products, use a different set of required modules and configuration...
        if (($global:SRxEnv.Product -eq "SP2013") -or ($global:SRxEnv.Product -eq "SP2016")) { 
            if (-not ($global:SRxEnv.RequiredModules -contains "Get-SRxFarm")) {
                $global:SRxEnv.RequiredModules += "Get-SRxFarm"
		    }
        } 

	    #-- [Optional] Load "Search" modules ...but skip if just running on a Content Farm (e.g. non-Search farm)
	    if ((-not $ContentFarm) -and (-not $SPO)) {
	        #if SP2010, load "LegacySearch" modules ...otherwise, use the "Search" modules: x:\<SRxProjectPath>\Modules\Search
	        $_searchModules = Join-Path $global:SRxEnv.Paths.Modules $(if ($global:SRxEnv.Product -eq "SP2010") { "Legacy" } else { "Search" } )
	        if (Test-Path $_searchModules) { $global:__SRxModulesPathsToLoad.Add($_searchModules) | Out-Null }
                #If we don't have a cached list of SSA[s] in the farm, build it...
                if ($global:___SRxCache.SSASummaryList.count -eq 0) {
                    try { 
                        #$global:___SRxCache.SSANameList = @( $(Get-SPEnterpriseSearchServiceApplication -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Name ) 
                        $global:___SRxCache.SSASummaryList = @( $(Get-SPEnterpriseSearchServiceApplication -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | % { 
                                                                if (-not [string]::isNullOrWhitespace($_.name)) { $(New-Object PSCustomObject -Property @{ "Name" = $_.Name; "CloudIndex" = $_.CloudIndex}) } 
                                                             }))
                    }
                    catch { $global:__SRxHasInitFailure = $true }
                }

                #Test the number of SSAs in this farm (*Multiple SSAs is less than ideal, but we'll do our best effort to handle it)
                if ($global:___SRxCache.SSASummaryList.count -eq 0) { 
                    $ContentFarm = $true

                    Write-SRx WARNING $("~~~[initSRx] Failed to load an SSA object from: Get-SPEnterpriseSearchServiceApplication ...exiting script")
                } elseif (($global:___SRxCache.SSASummaryList.count -gt 1) -and ([string]::isNullOrEmpty($SSA))) {
                    #if we have multiple SSAs in the and one was not explicitly specified on init... 
                    # - then start falling back to plan b (defined in config or $xSSA when not doing a rebuild)
                    $warnForMultiSSA = ([string]::isNullOrEmpty($global:SRxEnv.SSA)) -or ((-not $RebuildSRx) -and (-not $xSSA._hasSRx))
                
                    if ($warnForMultiSSA) {
                        #we'll try to handle multiple SSAs... 
                        Write-SRx WARNING $("~~~[initSRx] Multiple SSAs Detected: Please initialize the SRx with a specific SSA as the target...")
                        if ([Environment]::UserInteractive) {
                            foreach ($name in $global:___SRxCache.SSASummaryList.Name) {
                                Write-SRx INFO $("   *Hint: ") -ForegroundColor Magenta -NoNewline
                                Write-SRx INFO $(".\initSRx.ps1 -SSA `"" + $name  + "`"") -ForegroundColor Cyan
                            }
                    
                            #[Optional] toDo for multi-SSA: 
                            #  - Insert code here to prompt user to choose which SSA
                            #  - And if using dashboard, you can also prompt for an SSA handle here too (or punt and let post init handle that)
                            #...but for now, consider this a failed init state and exit the script here
                            $global:__SRxHasInitFailure = $true
                        } else {    
                            #but can only handle multiple SSAs if the user explicity specifies one *(and here they did not)
                            $global:__SRxHasInitFailure = $true
                        }
                    }
                }
                if ($global:__SRxHasInitFailure) { exit }
        
            $searchModules = @("Get-SRxSSA", "Enable-SRxCrawlDiag", "Enable-SRxQueryDiag")
            if (($global:___SRxCache.SSASummaryList.CloudIndex | ? {($_ -is [bool]) -and (-not $_)}).count -gt 0) { 
                $searchModules += "Enable-SRxIndexDiag"
            }

            if (($global:___SRxCache.SSASummaryList.CloudIndex | ? {$_}).count -gt 0) { 
                $searchModules += "Enable-SRxCloudDiag"
            }

            foreach ($module in $searchModules) {
                if (-not ($global:SRxEnv.RequiredModules -contains $module)) {
                    $global:SRxEnv.RequiredModules += $module
		        }
            }
	    }

        if (-not $SPO) {
	        #-- Add to $__SRxModulesPathsToLoad if path exists: x:\<SRxProjectPath>\Modules\Premier
	        $_premierModules = Join-Path $global:SRxEnv.Paths.Modules "Premier"
	        if (Test-Path $_premierModules) { 
		        $global:__SRxModulesPathsToLoad.Add($_premierModules) | Out-Null 
	        } else {
		        $_premierModules = $false
	        }
        }

	    #-- Add to $__SRxModulesPathsToLoad if path exists: x:\<SRxProjectPath>\Modules\Dashboard
	    $_dashboardModules = Join-Path $global:SRxEnv.Paths.Modules "Dashboard"
	    if (Test-Path $_dashboardModules) { 
		    $global:__SRxModulesPathsToLoad.Add($_dashboardModules) | Out-Null 
	    } else {
		    $_dashboardModules = $false
	    }
    } elseif(-not $CoreEnv) {
        Write-SRx WARNING $("[initSRx] Skipped product modules because `$SRxEnv.Product is not set")
    }

    #-- Enables user to load up modules from any custom path 
    #   --- in the configuration, set $global:SRxEnv.CustomModules to a target directory
    #   --- Add to $modulesToLoad if test path x:\<cust$omModulesPath>
    if (-not [String]::IsNullOrEmpty($global:SRxEnv.CustomModules)) {
        if (Test-Path $global:SRxEnv.CustomModules) { $global:__SRxModulesPathsToLoad.Add($global:SRxEnv.CustomModules) | Out-Null }
    }
    if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Mapped all modules to be loaded..." } ) | Out-Null }

    #-- Load all modules from each module path, if not already loaded (e.g. files ending in .psm1 file extension)
    foreach ($root in $global:__SRxModulesPathsToLoad) {
        $modulesInPath = Get-ChildItem -Path "$root\*.psm1"
        Write-SRx INFO $("[initSRx] Checking Modules in $root") -ForegroundColor DarkCyan

        foreach ($module in $modulesInPath) {
	        #when $RebuildSRx is true, the module will get removed before being added (e.g. to refresh code changes)
	        if ($RebuildSRx -and ($module.Basename -ne "Write-SRx")) { 
			    #we intentionally skip the removal of "Write-SRx" because it blows up normal processing/logging when missing
		        Remove-Module $($module.BaseName) -ErrorAction SilentlyContinue 
	        }
		
	        if (-not (Get-Module $($module.BaseName))) {
		        Write-SRx INFO $(" > Loading: " + $($module.Basename))
		        Import-Module $module.Fullname
	        }
        }
    }
    if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Loaded all modules..." } ) | Out-Null }
}

if ((-not $global:__SRxHasInitFailure) -and (-not $CoreEnv)) {
    #== If this is an Internal Build, we need to overwrite the SRxVersion property
    if (($global:SRxEnv.SRxVersion -eq "__REPLACE_WITH_VERSION_NUMBER_NAME__") -or ($global:SRxEnv.SRxVersion.Contains("Internal Build"))) {
        $latestModifiedTestOrModule = "Internal Build " + 
		    $(GCI -Path $global:SRxEnv.Paths.SRxRoot -File "*.ps*" -Recurse | Where {
			    ($_.fullname -notLike "*\Custom\*") -and ($_.fullname -notLike "*\Example\*") 
		    } | Sort LastWriteTime -Descending | SELECT -First 1).LastWriteTime.ToShortDateString()
        if ($global:SRxEnv.SRxVersion -ne $latestModifiedTestOrModule) {
	        $global:SRxEnv.PersistCustomProperty("SRxVersion", $latestModifiedTestOrModule)
        }
    }

    #=========================================
    #== Validate Core Modules Were Loaded ==
    #=========================================
    foreach ($moduleName in $global:SRxEnv.RequiredModules) {
	    if (-not (Get-Module $moduleName)) {
		    Write-SRx WARNING $("[initSRx] Unable to load module: " + $moduleName)
		    $global:__SRxHasInitFailure = $true
	    }
    }
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Validated required modules are loaded..." } ) | Out-Null }

    #========================================================================================
    #== If applicable, build the command strings to invoke the $xFarm and/or $xSSA objects ==
    #========================================================================================
    if ((-not $global:__SRxHasInitFailure) -and ($global:SRxEnv.RequiredModules.Count -gt 0)) {
	    if ($global:SRxEnv.RequiredModules -contains "Get-SRxFarm") {
		    $cmdString = "`$global:xFarm = Get-SRxFarm"	
		    $global:__SRxInvocationList.add($cmdString) | Out-Null
	    }
	
	    if ((-not $ContentFarm) -and ($global:SRxEnv.RequiredModules -contains "Get-SRxSSA")) {
		    $cmdString = "`$global:xSSA = Get-SRxSSA"
		
            #-- Specify a particular SSA name... (this piece is optional unless there are multiple SSAs in this farm)                   
            if ($SSA -is [Microsoft.Office.Server.Search.Administration.SearchServiceApplication]) { 
                $cmdString += " -SSA `$SSA"                                          #If an SSA object was explicitly specified, use it
            } elseif (-not [string]::isNullOrEmpty($SSA)) {                          #Else, if an SSA name was explicitly specified
                #-- Check if the value is the SSA is an actual name or a "handle"
                $mappedName = $( $global:SRxEnv.HandleMap | Where { ($_.Name -eq $SSA) -or ($_.Handle -eq $SSA) }).Name

                if ($mappedName.count -gt 1) {
                    Write-SRx WARNING $("[initSRx] Invalid HandleMap: Multiple SSAs map to '" + $SSA + "' ...ignoring map")
                    $mappedName = ""
                }

                if (-not [string]::isNullOrEmpty($mappedName)) {
                    $cmdString += " -SSA `"" + $mappedName +  "`""                        #-- if so, use the SSA name mapped to this handle
                } else {
                    $cmdString += " -SSA `"" + $SSA +  "`""                               #-- Or, use the specified name as is (which may or may not be valid)
                }
            } elseif ($xSSA._hasSRx) {
                $cmdString += " -SSA `$xSSA"                                         #Else, if we already have an $xSSA, re-use the same $xSSA
            } elseif (-not [string]::isNullOrEmpty($global:SRxEnv.SSA)) { 
                $cmdString += " -SSA `"" + $global:SRxEnv.SSA +  "`""                #Else, if an SSA name is defined in the custom.config.json, use that
            } 

            #-- And continue adding the other parameters to the cmd string (where applicable)
		    if ($Extended) {$cmdString += " -Extended" }
		    if ($RebuildSRx) { $cmdString += " -RebuildSRxSSA" }
	
            #-- if a specific SSA is specified, break this out as a separate action... 
            if ($cmdString.Contains(" -SSA ")) {
                $global:__SRxInvocationList.add($cmdString) | Out-Null
                #And the action of extending the $xSSA as another action
                $cmdString = "`$global:xSSA = `$xSSA"
            }

            $searchDiagModules = @("Enable-SRxCrawlDiag", "Enable-SRxQueryDiag", "Enable-SRxIndexDiag", "Enable-SRxCloudDiag")
		    foreach ($diagMod in $searchDiagModules) {            
                if ($global:SRxEnv.RequiredModules -contains $diagMod) {
			        $cmdString += " | " + $diagMod
			        if ($Extended) {$cmdString += " -Extended" }
		        } 
            }
        
            #-- if this second command string is more than just the string "`$global:xSSA = `$xSSA", then add it as an action
            if ($cmdString.length -gt 20) {	
		        $global:__SRxInvocationList.add($cmdString) | Out-Null
            }
	    }
    }
} 

#========================================================
#== Invoke each cmd string in the $__SRxInvocationList ==
#========================================================
if (-not $global:__SRxHasInitFailure) {
    if ($global:__SRxInvocationList.Count -gt 0) { 
	    $global:SRxEnv.UpdateShellTitle("(Invoking...)")
    }

    #-- Invoke each cmdString in this list
    foreach ($cmdString in $global:__SRxInvocationList) {
	    if ($global:__SRxHasInitFailure) {
            Write-SRx INFO $("~~~ Skipping: ") -NoNewLine -ForegroundColor Yellow
            Write-SRx Info $cmdString -ForegroundColor Gray
        } else {
            if (-not [String]::IsNullOrEmpty($cmdString)) {
                Write-SRx 
		        Write-SRx INFO "Running: " -NoNewline
		        Write-SRx INFO $($cmdString) -ForegroundColor Yellow
		        try {
			        Invoke-Expression ($cmdString)
		        } catch {
			        $global:__SRxHasInitFailure = $true
                    Write-SRx INFO $("~~~ Invocation failed: ") -NoNewLine -ForegroundColor Yellow
                    Write-SRx Info $cmdString -ForegroundColor Gray
                    Write-SRx ERROR "$_"
		        }
            }
        }
    }
    Write-SRx INFO
	if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Ran items in invocation list..." } ) | Out-Null }
}

#======================================================
#== (Optional) Validate and Dashboard related config ==
#======================================================

#-- Dashboard is N/A to the publicly available core
if ($CoreEnv -or $SPO -or $global:__SRxHasInitFailure) {
	if ($global:SRxEnv.Dashboard -ne $null) { $global:SRxEnv.Dashboard = $null }
} else {
	$farmId = $(if ($xFarm -ne $null) { $xFarm.id } else { (Get-SPFarm).id })
	
	if ($farmId -ne $null) {
	    if ($global:SRxEnv.FarmId -eq $null) {
		    $global:SRxEnv.PersistCustomProperty("FarmId", $farmId)
	    } elseif ($global:SRxEnv.FarmId -ne $farmId) {
		    #validate if the local farm id matches the id in the custom.config.json (e.g. was this copied over from another farm?)
		    Write-SRx WARNING $("[initSRx] `$SRxEnv.FarmId does not match the local farm id (this config was likely copied from another farm)")
		    $userMsg = "   - Updating `$SRxEnv.FarmId"
		
		    if ($global:SRxEnv.Dashboard -ne $null) {
			    $global:SRxEnv.Dashboard.Initialized = $false
			    $global:SRxEnv.PersistCustomProperty("Dashboard", $( $global:SRxEnv.Dashboard ))
			    $global:SRxEnv.Dashboard | Set-SRxCustomProperty "UpdateHandle" $true
			    $userMsg += " and the SRx Dashboard configuration"
		    }
		    Write-SRx INFO $($userMsg + " in the custom.config.json")
		    $global:SRxEnv.PersistCustomProperty("FarmId", $farmId)
	    }
    }

    # If there are no SSAs then this must be a content farm
    $existingSSAs = $(Get-SPEnterpriseSearchServiceApplication).Count
    if ($existingSSAs -eq 0) {
        $ContentFarm = $true
    }

    #-- If applicable (e.g. not running core), create a "Dashboard" config object if it does not already exist
	if ($_dashboardModules -and ($global:SRxEnv.Dashboard -eq $null) -and ((Get-Module "Enable-SRxDashboard") -ne $null)) {
        $dashboardConfig = New-Object PSObject -Property @{ 
			"Initialized" = $false;   	#Are Dashboard modules in place and is this configured for a deployed SRx site?
			"Site" = $null; 	    	#The site collection URL where the SRx Dashboard site has been deployed
			"Handle" = $null;	    	#A short name to describe *this SSA (e.g. "Prod", "QA", or "Dev")                
			"ThirdParty" = $null;   	#Use a CDN or locally downloaded copies for any third party libraries (e.g. AngularJS)?
			"LicenseAccepted" = $false;	#Has the license been accepted?
            "DashboardOnly" = $ContentFarm.IsPresent; #Only creating the Dashboard site, don't run Test tasks
		}
		$global:SRxEnv.PersistCustomProperty("Dashboard", $dashboardConfig)
	}

    # make sure the license agreement has been accepted.
   	if ($_dashboardModules -and ((Get-Module "Enable-SRxDashboard") -ne $null) -and ($global:SRxEnv.Dashboard.Initialized)) {
        $result = Confirm-SRxLicenseAgreement
    }
}

#=============================================================
#== (Optional) Trigger a custom startup script as last step ==
#=============================================================
$resolvedPostInitScript = $global:SRxEnv.ResolvePath($global:SRxEnv.PostInitScript)
if ($resolvedPostInitScript -and (Test-Path $resolvedPostInitScript)) {
    $global:SRxEnv.UpdateShellTitle("(Running PostInitScript...)")
    #if exists, run a custom post init script here
    . $resolvedPostInitScript  #run this script in local scope
}

if (-not $CoreEnv) {
	$boilerPlateScript = Join-Path $global:SRxEnv.paths.Scripts "writeBoilerPlate.ps1"
	#if exists, run the boiler plate script here...
	if (Test-Path $boilerPlateScript) {
		. $boilerPlateScript  #run this script in local scope
	}
}

$global:SRxEnv.UpdateShellTitle()
if ($TrackDebugTimings) { $global:SRxEnv.DebugTimings["[initSRx]"].Add( @{ $(Get-Date) = "Ended InitSRx.ps1" } ) | Out-Null }

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA0zjMaC/uAhKj6
# Ptn9Bb+/uV4FFwmPHdA/VyDKXyPT06CCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIN6poR3KsP48w9POsm9VYVhkqlN8gnYmDPm38uenhcsdMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAGfvOkaMtaev/DS/8jq5OUYW
# LUWNNAg8k8OmuAIcz6PqEiwZVs3uYmRzInpfmdFU3TAqFKM5R5T2P+oJpGUL3+HQ
# EF8Re9gil3VNhzguaSg5DadZGv7fODs29WJSnnghHvZ1GDdM2pEQzrbMHpfAyDIj
# nO7DVOin9aemJ0/iEG9GmeRD6QGoOEpTf+ri4KKZvq15JeFRpyglD0Ulf2v9SvJQ
# C727kyg+FUJX0uz3eepf8B3V8Ii45UhgeoSsvYey7PCTMHrZ+cPJs1rFY3pcOam8
# Vb9DKLspG20vu11R+31RnygPksKwrMWgs1tOcGFnje3owlFqcvMWmKU+fNGZ11Oh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgxmc4IcmOnnKziC+0Y9Pz
# o8Z9MO74ii6LyzRS3M29u8ICBljVRUm+IxgTMjAxNzA0MjYyMzU0MDcuNTk2WjAH
# AgEBgAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkMw
# RjQtMzA4Ni1ERUY4MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
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
# 7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNowggPCoAMCAQICEzMAAACj
# 7x8iIIFj3KUAAAAAAKMwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjQ5WhcNMTgwOTA3MTc1NjQ5WjCBszEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkMwRjQtMzA4Ni1ERUY4MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAqdEel8cTafg4OxUX5kgO+V+CrFSdMBqtEF3Q8gX3
# P2iGN1rQAFPmnG0caPIpx9b/MZhSTRG69cFkhjo5CSdWSV6foSEZKRvMWhbj830B
# VRcs6eGslvvHma8ocAB1IvoucpRUX7rRxawy1OXWHnnwgaMKvmO+eGln4o+F0cm+
# yH+Qi+S4fpiub74qZAgaSLc5Ichq9CRLYBDUcoByCDjpbvk7U+1Z2yTUTWHIW9Np
# YwAyvcyxUT3rQLh/uL67ch3BOGzeCY5uLZk6bEUI3rNPW21tgJHZI5tImUwe5RF/
# sxeedpG94iYWHxEAHDrfmegs/+x1LFgpcKcXLSjuj7SjXwIDAQABo4IBGzCCARcw
# HQYDVR0OBBYEFPqFumZm6EaZ2nCfuiElQNvg6LFwMB8GA1UdIwQYMBaAFNVjOlyK
# MZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3
# LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEu
# Y3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcN
# AQELBQADggEBAB3RRbpbtL+K5oaNRc41iCYSRrAzg2phMcgWc/jmJHpqwcAVNzyN
# xykNSMt0l6Wyh+EGeNVDjFM68OJRDni20/wcjSXlUxoV2T56vMe7wU5mWFEYD2Ul
# YSGhvuaRw2CO+Qm0PojCpnKBOxzyEBzVBa6IXTRVUqhDhozwDVS+S+RL7heVtpu8
# AmsWzbItbPWr3zXhBoO0WUHnHgHzaE332N4kLEZLQsCNF3NEUCuN3nbNf3Rd3+Zk
# zDK4nsDPZVIRCAZ6l7aDZaNi2MODujmOR7hTqsNmGhy9SU703NQHrNK40WT54HfJ
# 7HaAxKsXK+sjg7WWifHYS5aS3W+pwjvW85yhggN2MIICXgIBATCB46GBuaSBtjCB
# szELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxME
# TU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkMwRjQtMzA4Ni1ERUY4MSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4D
# AhoFAAMVADXko/tOP/8mDXH1bV4Se5GWOKaNoIHCMIG/pIG8MIG5MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYD
# VQQLEx5uQ2lwaGVyIE5UUyBFU046NTdGNi1DMUUwLTU1NEMxKzApBgNVBAMTIk1p
# Y3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQAC
# BQDcq1ARMCIYDzIwMTcwNDI2MTY1NzUzWhgPMjAxNzA0MjcxNjU3NTNaMHQwOgYK
# KwYBBAGEWQoEATEsMCowCgIFANyrUBECAQAwBwIBAAICJ2cwBwIBAAICGI4wCgIF
# ANysoZECAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQAC
# AxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEAQJe9+DcCOxzgx4n/
# lO7e97/ru4dCEEabqKFWYDRTAVee9yEesGGXFknEumflz907tllSlFbDAlenDsI3
# 0mUAToRqJuJaLxMi+RYh+JAOji0T3CSZndnNI+eniH2Ymiu9PMcCEGMhDX1ktWtg
# 8f8qns1CZYwpZjRmGOsBXj8bmqee90SZTMV8iJvBOP7ciw+OIPJN5TOcKvp1y54B
# 4U4CBey42ZcGbQdu+AXnTa2ul2oG68Q/l6BJ70vZ3I/kxS3JHdhyGq958deoy18D
# nIf28OFvYdIh1M/uWXn3oQNsTQy1HXgi9GyWXBjYkmYNbQLe4oi78pPAUUEaUfqr
# tx2OzDGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAAo+8fIiCBY9ylAAAAAACjMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEILhEP4Wc9ZrZNApT
# UkTenZOa03Wgfch1gEPRx6qgOIWAMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUNeSj+04//yYNcfVtXhJ7kZY4po0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAKPvHyIggWPcpQAAAAAAozAWBBR789E1ZbhfhAf/
# f93iigE5Mjb/ajANBgkqhkiG9w0BAQsFAASCAQCRjri3oAW4hfexsu1I9ie6kHJk
# wYNa2whxJvfgWlklsVR63l2UUwfXE2DP1M076PWMKFs1sjzOD3Ysq8AzE+pb4leV
# 9l64uutwfvGNns0KJhyo8Jh3b4ClrPDEwHezb6RfVROUQ+Sawq1ViNzwJaC1x29V
# PuD6V/xA6NY9f75JCSK8zgpTVKG1+w0XVN/YIq9xfyCxfjgSOwTQx7prLPJah7vR
# O9PTL29oRWyYdqBsFjTHz+8hTBu6Uy+fzTZ+q0PNw+AfaWWTrep9yal67baKuVBX
# ada3R741hDxJe+D5R03Hf6BjmO+I8EhmiwtNlXT2IgyOqM+TlqCwPALiBpKJ
# SIG # End signature block
