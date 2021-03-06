<#
.SYNOPSIS 
	
.DESCRIPTION 
	
.NOTES
	=========================================
	Project		: 
	-----------------------------------------
	File Name 	 : Deploy-SearchTopology.ps1
    Author		 : Brian Pendergrass
    Contributors : Brent Groom, Eric Dixon, Jon Waite 
	Requires	 : PowerShell Version 3.0, Microsoft.SharePoint.PowerShell
	Date		 : September 25, 2016
	
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

.OUTPUTS

.EXAMPLE
)
#>
[CmdletBinding()]
param (
		[parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)]
			[string]$DeploymentConfigFile, 		 #== For more advanced deployments, specify the file path 
												 #   to a deployConfig.json that contains the config options 
	    [parameter(Mandatory=$false)][string]	 $SSAName,							#== The Search Service Application Name (e.g. "SSA")
		[parameter(Mandatory=$false)][string]	 $SearchServiceAccount,				#== The Search Service Account
		[parameter(Mandatory=$false)][string]	 $CrawlAccount,						#== The Search "Crawl Account" 
		[parameter(Mandatory=$false)][switch] 	 $CloudIndex,						#== Provision as a Cloud SSA (e.g. to crawl on premises content and push to the SharePoint Online Index)
        																			#    - If false, provision a (classic) on premises SSA
	    [parameter(Mandatory=$false)][string]	 $DatabaseSQLInstance,				#== Database Server Instance for hosting ALL of the Search databases
		[parameter(Mandatory=$false)][switch] 	 $SingleServerConfig,				#== Simple everything-on-this-server config 
																					#   with this current user as the service account
        [parameter(Mandatory=$false)][string]    $IndexPathStub = ":\Index\I.R.",   #== The menus below ask for the drive letter and partition # to create a full path such as i:\Index\I.R.0
        [parameter(Mandatory=$false)][switch]    $GenerateSampleConfig
)

#=========================================================
#== Global environment variables and ensure requirements
#=========================================================

#== Temporary internal variables 
$domainUserPattern = '^[a-zA-Z][a-zA-Z0-9-]{1,50}(\.[a-zA-Z]{3,})*\\[a-zA-Z0-9-\.\$_]{2,}$'
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$isBuiltinAdmin = $([Security.Principal.WindowsPrincipal] $CurrentUser).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$truthyResponses = @("y", "yes", "1", "t", "true", "`$true")
$falsyResponses = @("n", "no", "0", "f", "false", "`$false")
$passedChecks = $true

#== Set the console I/O to be UTF8 friendly to accomodate non-English languages
if ($Host.Name -eq "ConsoleHost") {
	[system.console]::InputEncoding=[System.Text.Encoding]::UTF8
	[system.console]::OutputEncoding=[System.Text.Encoding]::UTF8
}

#-- Ensure minimum width and height for this shell window
if ($Host -and $Host.UI -and $Host.UI.RawUI) {
	$rawUI = $Host.UI.RawUI
	$oldSize = $rawUI.BufferSize
    $newWidth = 125
    $newHeight = 5000
	if ($oldSize.Width -gt $newWidth) {
		$newWidth = $oldSize.Width
	}
	if ($oldSize.Height -gt $newHeight) {
		$newHeight = $oldSize.Height
	}
	$typeName = $oldSize.GetType().FullName
	$newSize = New-Object $typeName ($newWidth, $newHeight)
	$rawUI.BufferSize = $newSize
}

if ($GenerateSampleConfig) {
    @{  "SSAName" = "SampleSSA";
        "CloudIndex" = $false;
        "AppPoolName" = "SampleSSA_AppPool";
        "SearchServiceAccount" =  "CHOTCHKIES\searchSvc";
        "CrawlAccount" =  "CHOTCHKIES\searchSvc";
        "Servers" =  @{
            "WAITER1" =    @{ "components" =  @( "Admin", "CC" ) }; "WAITER2" =    @{ "components" =  @( "Admin", "CC" ) };
            "LINECOOK1" =  @{ "components" =  @( "CPC", "APC" ) };  "LINECOOK2" =  @{ "components" =  @( "CPC", "APC" ) };
            "LINECOOK3" =  @{ "components" =  @( "CPC", "APC" ) };  "LINECOOK4" =  @{ "components" =  @( "CPC", "APC" ) };
            "TABLE41" =    @{ "components" =  @( "QPC", "Idx" );
                "replicaConfig" =  @( @{ "Partition" = 0; "Path" = "x:\Index\I.R.0" }; @{ "Partition" = 1; "Path" = "y:\Index\I.R.1" } ) };
            "TABLE42" =    @{ "components" =  @( "QPC", "Idx" );
                "replicaConfig" =  @( @{ "Partition" = 0; "Path" = "x:\Index\I.R.0" }; @{ "Partition" = 1; "Path" = "y:\Index\I.R.1" } ) };
        };
        "Databases" =  @{
            "dbNamePrefix" = "SSA";
            "SearchAdmin" = @{ "SQLInstance" =  "THEKITCHEN" };
            "CrawlStore" = @( @{ "SQLInstance" = "THEFRIDGE"; "DBCount" =  1 }; @{ "SQLInstance" = "THEPANTRY"; "DBCount" =  1 } );
            "LinksStore" = @( @{ "SQLInstance" = "THEKITCHEN"; "DBCount" =  1 } );
            "AnalyticsReportingStore" =  @( @{ "SQLInstance" = "THEKITCHEN"; "DBCount" =  2 } )
        };
        "SSAHandle" =  "SampleSSA" 
    } | ConvertTo-JSON -Depth 4 | Out-File .\sampleConfigToo.json
    Write-Host $(" -- Saved to: ") -ForegroundColor DarkCyan -NoNewline
    Write-Host (".\sampleConfig.json")
    exit
}

if (-not $isBuiltinAdmin) {
    Write-Warning $("Deploying a new SSA requires a local administrator")
    $passedChecks = $false   #-- Set this flag as false (which will prevent attempts to deploy the SSA)
}

#== Load the SharePoint PowerShell Snap-in
if ((Get-PSSnapin "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) {
	Write-Host $(" -- Adding the SharePoint PowerShell Snapin") -ForegroundColor DarkCyan
	Add-PSSnapin "Microsoft.SharePoint.PowerShell"
	if ((Get-PSSnapin "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) {
		Write-Warning $("Unable to load the Microsoft.SharePoint.PowerShell PsSnapin")
	    $passedChecks = $false   #-- Set this flag as false (which will prevent attempts to deploy the SSA)
    } 
}
if (-not $passedChecks) {
	Write-Warning ("One or more checks above failed... <terminating script>") 
	start-sleep 2
	exit
}

#== Temporary run-time variables 
$farmMajorBuildVersion = (Get-SPFarm).BuildVersion.Major
$existingSSACount = (Get-SPEnterpriseSearchServiceApplication).Count

#=============================================================
#== Define the configuration to be deployed by this script...
#=============================================================
Write-Host $("===========================================================") -BackgroundColor DarkCyan -ForegroundColor Black
Write-Host $("-- SharePoint Server Search | Topology Deployment Script --") -BackgroundColor DarkCyan 
Write-Host $("===========================================================") -BackgroundColor DarkCyan -ForegroundColor Black

#== If $DeploymentConfigFile is not supplied as a command line parameter...
if ([string]::isNullOrWhitespace($DeploymentConfigFile) -and (Test-Path $(Join-Path $PWD.Path "deployConfig.json"))) {
    do {
        $DeploymentConfigFile = $(Join-Path $PWD.Path "deployConfig.json")
        Write-Host $(" > Do you want to re-use ") -ForegroundColor Yellow -NoNewline
        Write-Host $DeploymentConfigFile -NoNewline
        Write-Host $(" for config [y/n]? ") -ForegroundColor Yellow -NoNewline
        $userResponse = Read-Host
        if ([string]::isNullOrWhitespace($userResponse)) {
            $userResponse = 'y'
        }
    } while ([string]::isNullOrWhitespace($userResponse))
    if ($truthyResponses.Contains($userResponse)) {
        Write-Host $("    -- Defaulting to " + $DeploymentConfigFile) -ForegroundColor DarkCyan
    } else {
        $DeploymentConfigFile = $null
    }
} 

#== Verify that the $DeploymentConfigFile specifies a file name ending in .json and exists... 
if (($DeploymentConfigFile -is [string]) -and ($DeploymentConfigFile.toLower().EndsWith(".json"))) {
	if ($DeploymentConfigFile.StartsWith(".\")) { 
		#strip off the ".\" and append current path
		$DeploymentConfigFile = $( Join-Path $PWD.Path $DeploymentConfigFile.SubString(2) )
	}
	
    #-- If the configuration file exists...
	if (Test-Path $DeploymentConfigFile) { 	
		Write-Host $("`nLoading configuration from: ") -ForegroundColor Cyan -NoNewline
		Write-Host $DeploymentConfigFile

		#-- Convert the json file to the hashtable configuration object named $ssaConfig
		try {
            $rawConfig = Get-Content $DeploymentConfigFile -Raw -ErrorAction Stop
			$global:ssaConfig = ConvertFrom-Json $rawConfig
        } catch { 
            Write-Error $(" --> Caught exception converting " + $DeploymentConfigFile + " to object. Check file for syntax errors.")
            $_

            Write-Host ("Do you want to specify a new configuration instead [y/n]? ") -ForegroundColor Yellow -NoNewline
            $userResponse = Read-Host
            if ($truthyResponses.Contains($userResponse)) {
                Write-Host $("  -- Ignoring: " + $DeploymentConfigFile)
            } else {
                $passedChecks = $false
            }
        }
	}
} elseif ([Environment]::UserInteractive) {
    #-- The information can be populated with user interaction
	Write-Host $("`nPlease answer the following questions to configure a new Search Service Application: ") -ForegroundColor Cyan
	Write-Host $(" * Note: Answer ") -ForegroundColor DarkCyan -NoNewLine
    Write-Host $("? ") -ForegroundColor Yellow -NoNewLine
    Write-Host $("for further details or press ") -ForegroundColor DarkCyan -NoNewLine
    Write-Host $("<ENTER> ") -NoNewLine
    Write-Host $("to accept any ") -ForegroundColor DarkCyan -NoNewLine
    Write-Host $("default value") -ForegroundColor Cyan
    Write-Host
} elseif ((-not $SingleServerConfig) -or ([string]::isNullOrWhitespace($SSAName))) {
    #-- If this is not a user interactive session and either (this was not designated as a single server deployment or an SSA Name was not specified)
    #     - then this needs to terminate because the script needs additional info from the user but has no way to prompt the user
    Write-Warning ("Insufficient configuration options are specified") 
    $passedChecks = $false
}

if (-not $passedChecks) {
	Write-Warning ("One or more checks above failed... <terminating script>") 
	start-sleep 2
	exit
}

#== Create a global $ssaConfig object if it does not exist (or not defined as a hashtable objhect)
if (($global:ssaConfig -eq $null) -or ($global:ssaConfig -isNot [hashtable])) { $global:ssaConfig = @{ } }

#== And then populate each part of this $ssaConfig...   
#   **Note: command line options will take precedence

#-- $SSAName : Specify the name for Search Service Application (e.g. "SSA")
if (-not [string]::isNullOrWhitespace($SSAName)) { 
    $ssaConfig.SSAName = $SSAName;
} elseif ([string]::isNullOrWhitespace($ssaConfig.SSAName)) {
    #-- Prompt the user 
    do {
		Write-Host $(" > SSA Name (such as SSA or CloudSSA): ") -ForegroundColor Yellow -NoNewline
        $userResponse = Read-Host
        if ($userResponse -eq "?") { 
            Write-Host $("    -- Please specify a name for this new Search Service Application ") -ForegroundColor DarkCyan
            $userResponse = $null
        } elseif ($userResponse.Length -gt 75) { 
            Write-Host $("    -- ") -ForegroundColor DarkCyan -NoNewline
            Write-Host $("Hint") -ForegroundColor Yellow -NoNewline
            Write-Host $(": Long SSA names can make administrative tasks more difficult") -ForegroundColor DarkCyan
        } elseif (
            ($existingSSACount -gt 0) -and                                         #If there are existing SSA(s)
            (-not [string]::isNullOrWhitespace($userResponse)) -and                #And the user response isn't null
            ($(Get-SPEnterpriseSearchServiceApplication $userResponse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue) -ne $null)) #And this doesn't already exist
        {
            Write-Warning $("-- An SSA with the name `"" + $userResponse + "`" already exists in this farm")
            $userResponse = $null
        }
    } while ([string]::isNullOrWhitespace($userResponse))
    $ssaConfig.SSAName = $userResponse
}

#Optional custom property useful for naming conventions (e.g. App Pools, DB Prefix, etc)
if ([string]::isNullOrWhitespace($ssaConfig.SSAHandle)) {
    if (($ssaConfig.SSAName.Length -gt 0) -and ($ssaConfig.SSAName.Length -le 30)) { 
        $ssaConfig.SSAHandle = $ssaConfig.SSAName.Replace(" ","")
    } elseif ($existingSSACount -gt 0) {
        $ssaConfig.SSAHandle = "SSA" + $($existingSSACount + 1) 
    } else {
        $ssaConfig.SSAHandle = "SSA"
    }
} 

#-- $SearchServiceAccount : The Search Service Account (e.g. the "Search Service Instance" account)
if ($existingSSACount -gt 0) { 
    #Only allow this change if there is no other existing SSA which would be impacted by making this change
    $ssaConfig.SearchServiceAccount = (Get-SPEnterpriseSearchService).ProcessIdentity
    Write-Warning $("-- An existing SSA exists")
    Write-Host $("    -- Deferring to the current Search Service Account: " + $ssaConfig.SearchServiceAccount) -ForegroundColor DarkCyan
} else {
    if ((-not [string]::isNullOrWhitespace($SearchServiceAccount)) -and ($SearchServiceAccount -match $domainUserPattern)) { 
	    $ssaConfig.SearchServiceAccount = $SearchServiceAccount;
    } elseif (([string]::isNullOrWhitespace($ssaConfig.SearchServiceAccount)) -or (-not ($ssaConfig.SearchServiceAccount -match $domainUserPattern))) {
	    #-- Prompt the user 
        $currentSearchSvcIdentity = (Get-SPEnterpriseSearchService).ProcessIdentity
        do {
		    Write-Host $(" > Search Service Account (") -ForegroundColor Yellow -NoNewline
            if ($currentSearchSvcIdentity -match "LocalService") {
                Write-Host $("e.g. domain\user") -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host $("currently ") -ForegroundColor Yellow -NoNewline
                Write-Host $($currentSearchSvcIdentity) -ForegroundColor Cyan -NoNewline
            }
		    Write-Host $("): ") -ForegroundColor Yellow -NoNewline
            $userResponse = Read-Host

            #ensure the $userResponse matches a pattern such as domain\user, domain.com\user, domain.com\$_username
            if ($userResponse -eq "?") { 
                Write-Host $("    -- Please specify an account in the form of ") -ForegroundColor DarkCyan -NoNewline
                Write-Host $("domain\user") -NoNewLine
                Write-Host $(" or press ") -ForegroundColor DarkCyan -NoNewLine
                Write-Host $("<ENTER> ") -NoNewLine
                Write-Host $("to accept ") -ForegroundColor DarkCyan -NoNewLine
                Write-Host $($currentSearchSvcIdentity) -ForegroundColor Cyan
                $userResponse = $null
            } elseif ([string]::isNullOrWhitespace($userResponse)) { 
                $userResponse = $currentSearchSvcIdentity
                if ($userResponse -match "LocalService") { 
                    $userResponse = $null 
                } else { 
                    Write-Host $("    -- Deferring to the existing Search Service Account: ") -ForegroundColor DarkCyan -NoNewline
                    Write-Host $($userResponse) 
                }
            } elseif ($userResponse -notMatch $domainUserPattern) { 
		        Write-Host $("    - `"") -ForegroundColor Yellow -NoNewline
		        Write-Host $($userResponse) -ForegroundColor Cyan -NoNewline
		        Write-Host $("`" does not match the 'domain\user' pattern") -ForegroundColor Yellow
                $userResponse = $null
            }
        } while ([string]::isNullOrWhitespace($userResponse))
        $ssaConfig.SearchServiceAccount = $userResponse
    }
}

#-- $CrawlAccount : The Crawl Account (e.g. the default content access account)
if (($CrawlAccount -ne $null) -and ($CrawlAccount -match $domainUserPattern)) { 
	$ssaConfig.CrawlAccount = $CrawlAccount
} elseif (([string]::isNullOrWhitespace($ssaConfig.CrawlAccount)) -or (-not ($ssaConfig.CrawlAccount -match $domainUserPattern))) {
	#-- Prompt the user
    do {
        Write-Host $(" > Default Content Access `"Crawl`" Account (e.g. ") -ForegroundColor Yellow -NoNewline
        Write-Host $($ssaConfig.SearchServiceAccount) -ForegroundColor Cyan -NoNewline
        Write-Host $("): ") -ForegroundColor Yellow -NoNewline
        $userResponse = Read-Host
        if ($userResponse -eq "?") {
            Write-Host $("    -- By default, this will be the Search Service Account ") -ForegroundColor DarkCyan -NoNewline
            Write-Host $($ssaConfig.SearchServiceAccount)
            $userResponse = $null
        } elseif ([string]::isNullOrWhitespace($userResponse)) {
            Write-Host $("    -- Defaulting to the Search Service Account ") -ForegroundColor DarkCyan
            $userResponse = $ssaConfig.SearchServiceAccount
        } elseif ($userResponse -notMatch $domainUserPattern) { 
		    Write-Host $("    - `"") -ForegroundColor Yellow -NoNewline
		    Write-Host $($userResponse) -ForegroundColor Cyan -NoNewline
		    Write-Host $("`" does not match the 'domain\user' pattern") -ForegroundColor Yellow -NoNewline
            $userResponse = $null
        }
    } while ([string]::isNullOrWhitespace($userResponse))
    $ssaConfig.CrawlAccount = $userResponse
}

#-- The SP Application Pool for the Search Query and Site Settings
if ([string]::isNullOrWhitespace($ssaConfig.AppPoolName)) {
	#-- Prompt the user 
    do {
        Write-Host $(" > Search Web Service App Pool Name (e.g. ") -ForegroundColor Yellow -NoNewline
        Write-Host $($ssaConfig.SSAHandle + "_AppPool") -ForegroundColor Cyan -NoNewline
        Write-Host $("): ") -ForegroundColor Yellow -NoNewline
        $userResponse = Read-Host
        if ($userResponse -eq "?") { 
            Write-Host $("    -- This App Pool is used for the SearchAdmin.svc and SearchService.svc WCF endpoints ") -ForegroundColor DarkCyan
            $userResponse = $null
        } elseif ([string]::isNullOrWhitespace($userResponse)) {
            Write-Host $("    -- Defaulting to: ") -ForegroundColor DarkCyan -NoNewline
            Write-Host $($ssaConfig.SSAHandle + "_AppPool")
            $userResponse = $ssaConfig.SSAHandle + "_AppPool"
        }
    } while ([string]::isNullOrWhitespace($userResponse))
    $ssaConfig.AppPoolName = $userResponse
}

#-- $CloudIndex : If true, provision a Cloud Hybrid SSA (instead of a classic on-premises SSA)
if ($CloudIndex) {
    $ssaConfig.CloudIndex = $CloudIndex
} elseif ($ssaConfig.CloudIndex -isNot [bool]) {
    if ($truthyResponses.Contains($ssaConfig.CloudIndex)) {
        $ssaConfig.CloudIndex = $true
    } elseif ($falsyResponses.Contains($ssaConfig.CloudIndex)) {
        $ssaConfig.CloudIndex = $false
    } else {
        #if a true/false value is not explicitly specified, then prompt the user to choose
        do {
            Write-Host $(" > Use Cloud Index [y/n]? ") -ForegroundColor Yellow -NoNewline
            $userResponse = Read-Host
            if ($userResponse -eq "?") { 
                Write-Host $("    -- Enter `"y`" to configure a Cloud SSA (e.g. to crawl on premises content and push to the SharePoint Online Index)") -ForegroundColor DarkCyan
                Write-Host $("    -- Enter `"n`" to configure a (classic) on premises SSA with a locally managed Search Index") -ForegroundColor DarkCyan
                $userResponse = $null
            }
        } while ([string]::isNullOrWhitespace($userResponse))
        $ssaConfig.CloudIndex = $truthyResponses.Contains($userResponse.toString().trim().toLower())
    }
}

#-- Prevent a user from specifying a server not in this farm (or for SP2016, that does not have Search role)
if ($farmMajorBuildVersion -ge 16) {
    $candidateServers = $(Get-SPServer | Where {($_.Role -eq "Search") -or ($_.Role -eq "Custom") -or ($_.Role -eq "SingleServerFarm")}).Name
} else {
    $candidateServers = $(Get-SPServer | Where {$_.Role -eq "Application"}).Name
}

if ($candidateServers.count -gt 0) { 
    $candidateServers = $candidateServers.ToUpper()
} else {
    $passedChecks = $false   #-- Set this flag as false (which will prevent attempts to deploy the SSA)
    Write-Warning ("Found no servers available to deploy a Search component... <terminating script>") 
    start-sleep 2
    exit
}

#-- Server configuration (e.g. mapping the components to a particular server)
if (([string]::isNullOrWhitespace($ssaConfig.Servers)) -or (($ssaConfig.Servers -isNot [hashtable]))) { 
    Write-Host $("`n -- Component-to-Server Configuration ----- ") -ForegroundColor DarkGray
	$serverMapping = @{}
    
    if ($ssaConfig.CloudIndex) {
        do {
            Write-Host $(" > Deploy all components to ") -ForegroundColor Yellow -NoNewline
    		Write-Host $(($ENV:ComputerName).ToUpper()) -ForegroundColor Cyan -NoNewline
	    	Write-Host $(" as a single server SSA [y/n]? ") -ForegroundColor Yellow -NoNewline
            $userResponse = Read-Host
            if ($userResponse -eq "?") { 
                Write-Host $("    -- Enter `"y`" to deploy one of each component to the specified server") -ForegroundColor DarkCyan
                Write-Host $("    -- Enter `"n`" to specify a scaled out SSA across multiple servers") -ForegroundColor DarkCyan
                $userResponse = $null
            }
        } while ([string]::isNullOrWhitespace($userResponse))

		#prompt the user - Do you want to deploy all the components to this local server? (if 'no', then you plan to scale out this SSA across multiple servers)
        $SingleServerConfig = $truthyResponses.Contains($userResponse.toString().trim().toLower())
    }

    if ($SingleServerConfig) {
        if ($candidateServers.Contains($($ENV:ComputerName).ToUpper())) {
            $serverMapping = @{ $($ENV:ComputerName).ToUpper() = @{ components = [System.Collections.ArrayList]("Admin", "CC", "CPC", "APC", "Idx", "QPC") } };
        } else {
            #prompt the user... please run this on one of the $candidateServers (*where you want to deploy)
			Write-Warning $("--- This local server $(($ENV:ComputerName).ToUpper()) is not capable of running search")
			if ($farmMajorBuildVersion -ge 16) {
				Write-Host $("            (please ensure the server is enabled to run the 'Search' minrole)") -ForegroundColor Yellow
			}
			$passedChecks = $false
        }
    } else {

		#===========================================================
        #== Internal functions for mapping servers to components...
        #===========================================================

        #toDo: add a function to pretty print Servers in the farm...

		function addToServerList { 
			param ($rawServerList = "", $componentType = "N/A", $attributes = $null)

			#-- Count the number of successful mappings
			$mappedCount = 0
			
            if ((-not [string]::isNullOrWhitespace($rawServerList)) -and ($componentType -ne "N/A")) {
			    #-- Normalize the raw user input to an array of server names (split on space, tab, comma, or semi-colon)
			    $normalizedList = @( $rawServerList.replace("(","").replace(")","").replace("`"","").replace("'","").toUpper() -split '[ \t,;]+' ) | ? {-not [string]::IsNullOrWhitespace($_)}
			
			    foreach ($targetServer in $normalizedList) {
				    $mapped = $false

                    #-- Verify that each server is in the list of candidate servers
				    if ($candidateServers.Contains($targetServer)) {
					
					    #-- If this is a new server reference, create the stub for this server with an empty "components" array
					    if ($serverMapping[$targetServer].components -eq $null) { 
						    $serverMapping[$targetServer] = @{ "components" = New-Object System.Collections.ArrayList }
					    }
					    
					    if (-not $serverMapping[$targetServer].components.Contains($componentType)) {
						    $serverMapping[$targetServer].components.Add([string]$componentType) | Out-Null
						    #-- Flag as mapped --> successfully mapped a component to a valid server
						    $mapped = $true
					    }
					
					    if (($componentType -eq "Idx") -and ($attributes -ne $null)) {
						    if ($serverMapping[$targetServer].replicaConfig -eq $null) {
							    $serverMapping[$targetServer].replicaConfig = New-Object System.Collections.ArrayList 
						    }

                            if ($serverMapping[$targetServer].replicaConfig.Partition -contains $attributes.Partition) {
                                #we have a duplicate.... should I update? or warn? or both?
                            } else {
                                $serverMapping[$targetServer].replicaConfig.Add($attributes) | Out-Null
                                #-- Flag as mapped --> successfully set replicaConfig for this indexer
                                $mapped = $true
                            }
					    }

				    } else {
                        Write-Host $("       - `"") -ForegroundColor Yellow -NoNewline
		                Write-Host $($targetServer) -ForegroundColor Cyan -NoNewline
            		    Write-Host $("`"  is not in this farm or not capable of running Search components ") -ForegroundColor Yellow -NoNewline
                        Write-Host $("...IGNORING THIS SERVER") -ForegroundColor Magenta
					    if ($farmMajorBuildVersion -ge 16) {
						    Write-Host $("         (please ensure the specified server is enabled to run the 'Search' minrole)")
					    }
				    }

                    if ($mapped) { $mappedCount++ }
			    }
            }
			return $mappedCount
		}

		#=================================================
        #== Iterate through each Search Component type...
        #=================================================
		
        #---------------------
        # Component Type Key:
        #---------------------
          #   Admin: Admin Component
          #   CC:    Crawl Component
          #   CPC:   Content Processing Component
          #   APC:   Analytics Processing Component
          #   Idx:   Index Component
          #   QPC:   Query Processing Component

		Write-Host $("    * For each component type, list the server(s) where it should be provisioned") -ForegroundColor Cyan
        Write-Host $("      Note: To specify multiple server names, use a comma delimited list such as:") -ForegroundColor DarkCyan
        Write-Host $("            server1, server2, server3 `n")
		@( 
			@{"Admin" = "Admin Component"}, 
			@{"QPC"	  = "Query Processing Component"}, 
			@{"CC"	  = "Crawl Component"} 
		) | foreach { 
			do {
				Write-Host $("    > " + $_.Values[0] + "(s): ") -ForegroundColor Yellow -NoNewline
				$userResponse = Read-Host
                if ($userResponse -eq "?") {
                    Write-Host $("       -- List the server(s) where this component type should be provisioned") -ForegroundColor DarkCyan
                    $userResponse = $null
                }
		 	} while ( $(addToServerList $userResponse $_.Keys[0]) -eq 0 ) #ensure that this component is mapped to at least one server... and repeat if not
		}

		if ($ssaConfig.CloudIndex) {
			#-- With the Cloud SSA, these remaining components are only logically deployed
			if ($candidateServers.Contains($($ENV:ComputerName).ToUpper())) {
				#Default to the local server (*if it's a candidate for Search)
				$targetForLogicalComponents = $($ENV:ComputerName).ToUpper()
			} else {
				#Otherwise, just pick the first one we find using the previously mappedssssss components
				$targetForLogicalComponents = $serverMapping.Keys[0]			
			}
			
			@( "CPC", "APC", "Idx" ) | foreach { addToServerList $targetForLogicalComponents $_ | Out-Null }
		
		} else {
			#-- Configure the remaining components for the (legacy) on-premises SSA
			@( 
				@{"CPC"	  = "Content Processing Component"},
				@{"APC"	  = "Analytics Processing Component"}
			) | foreach { 
				do {
					Write-Host $("    > " + $_.Values[0] + "(s): ") -ForegroundColor Yellow -NoNewline
					$userResponse = Read-Host
			 	} while ( $(addToServerList $userResponse $_.Keys[0]) -eq 0 ) #ensure that this component is mapped to at least one server... and repeat if not
			}
					
			#-- And then for the Index...
            Write-Host $("`n    -- Index Configuration ----- ") -ForegroundColor DarkGray
			do {
				Write-Host $("    > How many Index Partitions [1-25]? ") -ForegroundColor Yellow -NoNewline
				$userResponse = Read-Host
				try { $partitionCount = [int]$userResponse } catch { $partitionCount = -1 }
		    } while (($partitionCount -lt 1) -or ($partitionCount -gt 25))
			
            do {
                Write-Host $("    > Use custom RootDirectory for Index storage [y/n]? ") -ForegroundColor Yellow -NoNewline
			    $userResponse = Read-Host
                if ($userResponse -eq "?") { 
                    Write-Host $("    -- Enter `"y`" to specify a custom path for the Index storage") -ForegroundColor DarkCyan
                    Write-Host $("    -- Enter `"n`" to default to the DataDirectory path defined at install") -ForegroundColor DarkCyan
                    $userResponse = $null
                } elseif ($userResponse.contains(":")) {  #did someone specify a drive path here?
                    $userResponse = $null
                }
            } while ([string]::isNullOrWhitespace($userResponse))
			$useRootDirectory = $truthyResponses.Contains($userResponse.toString().trim().toLower())
			
			for ($i = 0; $i -lt $partitionCount; $i++) {
				if ($partitionCount -gt 1) {
					Write-Host $("`n       == Index Partition [") -ForegroundColor DarkGray -NoNewline
					Write-Host $i -ForegroundColor Cyan -NoNewline
					Write-Host $("] == ") -ForegroundColor DarkGray
					$indent = "       "
				} else {
					$indent = "    "
				}
				$replicaConfig = @{ "Partition"=$i; };   
				if ($useRootDirectory) {
					do {
						Write-Host $($indent + "> Specify a drive letter for the Index storage: ") -ForegroundColor Yellow -NoNewline
						$userResponse = Read-Host
                        if ($userResponse -eq "?") {
                            Write-Host $($indent + "   -- For the specified drive letter (e.g. i:\ ), this script will create a path such as: ") -ForegroundColor DarkCyan -NoNewline
                            Write-Host $("i:\Index\I.R.0")
                            $userResponse = $null
                        } 
					} while ([string]::IsNullOrWhiteSpace($userResponse) -or (-not ($userResponse.trim() -match '^[a-zA-Z][:(:\\)]*$')))
					$replicaConfig["Path"] = ($userResponse.trim())[0] + $IndexPathStub + $i  #Path = Drive letter + $IndexPathStub + partition# (e.g. i:\Index\I.R.0)
				}
				
				do {
					Write-Host $($indent + "> Server(s) where Index Replicas should be provisioned: ") -ForegroundColor Yellow -NoNewline
					$userResponse = Read-Host
			 	} while ( $(addToServerList $userResponse "Idx" $replicaConfig) -eq 0 ) #ensure that this replica is mapped to at least one server... and repeat if not
			}
        }
    }
	$ssaConfig.Servers = $serverMapping
}

#toDo: 
#Verify values passed in by config.json (e.g. if $ssaConfig.Servers was defined)
#  - Do we have at least one of each type of component in this mapping?
#  - Do the servers in the mapping exist in the farm ...and for [SP2016] do these servers have the Search role

#-- Database configuration (e.g. the naming convention and SQL Instances where DBs are created)
if (([string]::isNullOrWhitespace($ssaConfig.Databases)) -or (($ssaConfig.Databases -isNot [hashtable]))) { 
    Write-Host $("`n -- Database Configuration ----- ") -ForegroundColor DarkGray
    $databaseConfig = @{ }
    do {
	    Write-Host $(" > Search Database Name Prefix (e.g. ") -ForegroundColor Yellow -NoNewline
        Write-Host $($ssaConfig.SSAHandle) -ForegroundColor Cyan -NoNewline
        Write-Host $("): ") -ForegroundColor Yellow -NoNewline
	    $userResponse = Read-Host
        if ($userResponse -eq "?") {
            Write-Host $("    -- A prefix for naming the Search Databases. For example, setting the prefix to `"SSA`" would result") -ForegroundColor DarkCyan
            Write-Host $("       in Search Databases named such as: ") -ForegroundColor DarkCyan -NoNewline
            Write-Host $("SSA, SSA_CrawlStore, SSA_LinksStore, SSA_AnalyticsReportingStore")
            $userResponse = $null
        } elseif ([string]::isNullOrWhitespace($userResponse)) {
            Write-Host $("    -- Defaulting to the Search DB prefix: ") -ForegroundColor DarkCyan -NoNewline
            Write-Host $($ssaConfig.SSAHandle)
            $userResponse = $ssaConfig.SSAHandle
        }
    } while ([string]::isNullOrWhitespace($userResponse))
    $databaseConfig.dbNamePrefix = $userResponse

    if (-not [string]::isNullOrWhitespace($DatabaseServerName)) {
	    $defaultSQLInstance = $DatabaseServerName;
        $useDefaultSQLInstance = $true
    } elseif ([string]::isNullOrWhitespace($ssaConfig.dbServer)) {
   	    $locationOfConfigDB = (Get-SPDatabase | where {$_.TypeName -eq "Configuration Database"})[0].Server.Address

        #if we get a value and it isn't a SQL Named Instance (e.g. contains the "\")
        if (-not (([string]::isNullOrWhitespace($locationOfConfigDB)) -or ($locationOfConfigDB.contains("\")))) {
            $defaultSQLInstance = $locationOfConfigDB.toUpper()
            do {
                Write-Host $(" > Create the Search DBs (one of each) on the SQL Server Instance ") -ForegroundColor Yellow -NoNewline
		        Write-Host $($defaultSQLInstance) -ForegroundColor Cyan -NoNewline
		        Write-Host $(" [y/n]? ") -ForegroundColor Yellow -NoNewline
		        $userResponse = Read-Host
                if ($userResponse -eq "?") {
                    Write-Host $("    -- Enter `"y`" to create all Search DBs on the SQL Server Instance ") -ForegroundColor DarkCyan -NoNewline
                    Write-Host $($defaultSQLInstance)
                    Write-Host $("    -- Enter `"n`" if you want to specify a different SQL Server Instance(s) for the Search DBs") -ForegroundColor DarkCyan
                    $userResponse = $null
                } elseif ([string]::isNullOrWhitespace($userResponse)) {
                    Write-Host $("    -- Defaulting to the SQL Server Instance  ") -ForegroundColor DarkCyan -NoNewline
                    Write-Host $($defaultSQLInstance)
                    $userResponse = 'y'
                }
            } while ([string]::isNullOrWhitespace($userResponse))
            $useDefaultSQLInstance = $truthyResponses.Contains($userResponse.toString().trim().toLower())    
        }
    }

    @("SearchAdmin", "CrawlStore", "LinksStore", "AnalyticsReportingStore") | foreach { 
		$dbType = $_
        $canScaleOut = ($dbType -ne "SearchAdmin")
        if ($useDefaultSQLInstance) { 
            if (-not $canScaleOut) {
                $databaseConfig[$dbType] = @{ "SQLInstance" = $defaultSQLInstance };
            } else {
                $databaseConfig[$dbType] = New-Object System.Collections.ArrayList 
                $databaseConfig[$dbType].Add( @{ "SQLInstance" = $defaultSQLInstance; "DBCount" = 1; } ) | Out-Null
            }
        } else {
            Write-Host $("`n    -- " + $dbType + " Database (e.g. ") -ForegroundColor DarkGray -NoNewline
			Write-Host $($databaseConfig.dbNamePrefix + $(if ($canScaleOut) {"_" + $dbType})) -ForegroundColor DarkGray -NoNewline
			Write-Host $(") -- ") -ForegroundColor DarkGray
            do {
                if ($canScaleOut) {
                    Write-Host $("    > List the SQL Server Instance(s): ") -ForegroundColor Yellow -NoNewline
                } else {
                    Write-Host $("    > SQL Server Instance (e.g. ") -ForegroundColor Yellow -NoNewline
                    Write-Host $($defaultSQLInstance) -ForegroundColor Cyan -NoNewline
                    Write-Host $("): ") -ForegroundColor Yellow -NoNewline
                }
                $userResponse = Read-Host
                
                if ([string]::isNullOrWhitespace($userResponse)) {
                    Write-Host $("       -- Defaulting to the SQL Instance: ") -ForegroundColor DarkCyan -NoNewline
                    Write-Host $($defaultSQLInstance)
                    $normalizedListOfSQL = @( $defaultSQLInstance.toUpper() )
                } elseif ($userResponse.contains("\")) {
                    Write-Host $("        -- ") -ForegroundColor DarkCyan -NoNewline
                    Write-Host $("Hint") -ForegroundColor Yellow -NoNewline
                    Write-Host $(": Configure a SQL Server alias rather than using a SQL Named Instance with SharePoint") -ForegroundColor DarkCyan
                    Write-Host $("           Example steps: ") -ForegroundColor DarkCyan -NoNewline
                    Write-Host $("Configuring SQL Server alias with SharePoint Server 2013") -ForegroundColor Cyan
                    Write-Host $("           https://blogs.technet.microsoft.com/gabn/2014/04/14/configuring-sql-server-alias-with-sharepoint-server-2013")
                    $normalizedListOfSQL = @()
                } else {
                    $normalizedListOfSQL = @( $userResponse.replace("(","").replace(")","").replace("`"","").replace("'","").toUpper() -split '[ \t,;]+' ) | ? {-not [string]::IsNullOrWhitespace($_)}
                    if ((-not $canScaleOut) -and ($normalizedListOfSQL.count -gt 1)) {
                        Write-Host $("     - The ") -ForegroundColor Yellow -NoNewline
                        Write-Host $($dbType + " Database ") -ForegroundColor Cyan -NoNewline
                        Write-Host $("cannot be scaled out. Please specify a single SQL Server Instance...") -ForegroundColor Yellow
                        $normalizedListOfSQL = @()
                    }
                }
                $normalizedListOfSQL = @( $normalizedListOfSQL )
            } while ($normalizedListOfSQL.count -eq 0)

            #And now we start building out the configuration object
            if (-not $canScaleOut) {
                $databaseConfig[$dbType] = @{ "SQLInstance" = $normalizedListOfSQL[0] };
            } else {
                $databaseConfig[$dbType] = New-Object System.Collections.ArrayList 
                for ($i = 0; $i -lt $normalizedListOfSQL.count; $i++) { 
                    Write-Host $("`n       == SQL Server [ ") -ForegroundColor DarkGray -NoNewline
			        Write-Host $($normalizedListOfSQL[$i]) -ForegroundColor Cyan -NoNewline
			        Write-Host $(" ] == ") -ForegroundColor DarkGray                    
                    if ($canScaleOut) {
                        $partitionFactor = $( if ($farmMajorBuildVersion -ge 16) {2} else {1} )
                        switch ($dbType) {
                            "CrawlStore" {
                                $suggestedCount = $( if ($partitionCount -gt 1) { [math]::Ceiling( (0.5 * $partitionFactor * $partitionCount) / $normalizedListOfSQL.count ) } else { 1 } )
                                $helpMessage = "The recommendation is 1 CrawlStore for every 20M items (or every " + (2 / $partitionFactor) + " Index Partitions)"
                            }
                            "LinksStore" {
                                $p = $( if ($farmMajorBuildVersion -ge 16) {1} else {2} )
                                $suggestedCount = $( if ($partitionCount -gt 1) { [math]::Ceiling( (0.1 * $partitionFactor * $partitionCount) / $normalizedListOfSQL.count ) } else { 1 } )
                                $helpMessage = "The recommendation is 1 LinksStore for every 100M items (or every " + (10 / $partitionFactor) + " Index Partitions)"
                            }
                            "AnalyticsReportingStore" {
                                $suggestedCount = $( if ($partitionCount -gt 1) { [math]::Ceiling( (0.5 * $partitionFactor * $partitionCount) / $normalizedListOfSQL.count ) } else { 1 } )
                                $helpMessage = "The recommendation is 1 CrawlStore for every 20M items (or every " + (2 / $partitionFactor) + " Index Partitions)"
                            }
                            default { 1 }
                        }

                        do {
                            Write-Host $("       > How many " + $dbType + " DBs on this SQL Instance (suggested: ") -ForegroundColor Yellow -NoNewline
                            Write-Host $($suggestedCount) -ForegroundColor Cyan -NoNewline
                            Write-Host $(")? ") -ForegroundColor Yellow -NoNewline
                            
                            $userResponse = Read-Host
                            if ($userResponse -eq "?") {
                                Write-Host $("          -- " + $helpMessage) -ForegroundColor DarkCyan
                                Write-Host $("          -- The SSA is currently configured for ") -ForegroundColor DarkCyan -NoNewline
                                Write-Host $($partitionCount.ToString() + " Index Partitions ") -NoNewline
                                Write-Host $("and") -ForegroundColor DarkCyan -NoNewline
                                Write-Host $(($normalizedListOfSQL.count).ToString()  + " SQL Instances") -NoNewline
                                $userResponse = 0
                            } elseif ([string]::isNullOrWhitespace($userResponse)) {
                                Write-Host $("          -- Defaulting to the suggested count: ") -ForegroundColor DarkCyan -NoNewline
                                Write-Host $($suggestedCount)
                                $userResponse = $suggestedCount
                            }
                            try { $dbCount = [int]$userResponse } catch { $dbCount = -1 }
		                } while (($dbCount -lt 1) -or ($dbCount -gt 16))
                    }
                    $databaseConfig[$dbType].Add( @{ "SQLInstance" = $normalizedListOfSQL[$i]; "DBCount" = $dbCount; } ) | Out-Null
                } 
            }
	    }
    }
    $ssaConfig.Databases = $databaseConfig
}

if (-not $passedChecks) {
	Write-Warning ("One or more checks above failed with Database configuration... <terminating script>") 
	start-sleep 2
	exit
}

Write-Host ("`n`n")
Write-Host ("------------------------------------") -ForegroundColor DarkCyan
Write-Host ("--- ") -ForegroundColor DarkCyan -NoNewline
Write-Host ("Configuration to be deployed ") -ForegroundColor Yellow -NoNewline
Write-Host ("---") -ForegroundColor DarkCyan
Write-Host ("------------------------------------`n") -ForegroundColor DarkCyan
Write-Host ("Service Application Name : ") -ForegroundColor Cyan -NoNewline
Write-Host ($ssaConfig.SSAName)
Write-Host ("Search Service Account   : ") -ForegroundColor Cyan -NoNewline
Write-Host ($ssaConfig.SearchServiceAccount)
if ([string]::isNullOrWhitespace($ssaConfig.CrawlAccount)) { 
    Write-Host ("Default Content Access   : ") -ForegroundColor Cyan -NoNewline
    if ($ssaConfig.CrawlAccount -eq $ssaConfig.SearchServiceAccount) {
        Write-Host ("<Search Service Account>")
    } else {
        Write-Host ($ssaConfig.CrawlAccount)
    }
}
Write-Host ("Web Service App Pool     : ") -ForegroundColor Cyan -NoNewline
Write-Host ($ssaConfig.AppPoolName)
if ([string]::isNullOrWhitespace($ssaConfig.AppPoolAccount)) { 
    Write-Host ("App Pool Service Account : ") -ForegroundColor Cyan -NoNewline
    Write-Host ($ssaConfig.AppPoolName) 
}
Write-Host ("Database Name Prefix     : ") -ForegroundColor Cyan -NoNewline
Write-Host ($ssaConfig.Databases.dbNamePrefix)

#SQL Instances...
$allSQLInstances = @( $ssaConfig.Databases.SearchAdmin.SQLInstance )
$totalCrawlStoreCount = 0
$totalLinksStoreCount = 0
$totalReportingStoreCount = 0
foreach ($config in $ssaConfig.Databases.CrawlStore) { 
    $allSQLInstances += $config.SQLInstance 
    $hasCrawlStoreDBScaleOut = ($hasCrawlStoreDBScaleOut -or ($config.DBCount -gt 1) -or ($config.SQLInstance -ne $ssaConfig.Databases.SearchAdmin.SQLInstance))
    $totalCrawlStoreCount += $config.DBCount
}
foreach ($config in $ssaConfig.Databases.LinksStore) {
    $allSQLInstances += $config.SQLInstance 
    $hasLinksStoreDBScaleOut = ($hasLinksStoreDBScaleOut -or ($config.DBCount -gt 1) -or ($config.SQLInstance -ne $ssaConfig.Databases.SearchAdmin.SQLInstance))
    $totalLinksStoreCount += $config.DBCount
}
foreach ($config in $ssaConfig.Databases.AnalyticsReportingStore) { 
    $allSQLInstances += $config.SQLInstance 
    $hasReportingStoreDBScaleOut = ($hasReportingStoreDBScaleOut -or ($config.DBCount -gt 1) -or ($config.SQLInstance -ne $ssaConfig.Databases.SearchAdmin.SQLInstance))
    $totalReportingStoreCount += $config.DBCount
}
$hasDBScaleOut = ($hasCrawlStoreDBScaleOut -or $hasLinksStoreDBScaleOut -or $hasReportingStoreDBScaleOut)

#DB allocation per SQL Instance...
$allSQLInstances = @( $allSQLInstances | SELECT -Unique )
if ($allSQLInstances.count -eq 1) {
    Write-Host ("SQL Server Instance     : ") -ForegroundColor Cyan -NoNewline
    Write-Host ($ssaConfig.Databases.SearchAdmin.SQLInstance)
    Write-Host ("  * Search Admin        : ") -ForegroundColor Cyan -NoNewline
    Write-Host ("1")
    Write-Host ("  * Crawl Store         : ") -ForegroundColor Cyan -NoNewline
    Write-Host ($totalCrawlStoreCount)
    Write-Host ("  * Links Store         : ") -ForegroundColor Cyan -NoNewline
    Write-Host ($totalLinksStoreCount)
    Write-Host ("  * Analytics Reporting : ") -ForegroundColor Cyan -NoNewline
    Write-Host ($totalReportingStoreCount)
} else {
    $hasDBScaleOut = $true
    Write-Host ("Search Databases") -ForegroundColor Cyan
    Write-Host ("  * Search Admin        : ") -ForegroundColor Cyan -NoNewline
    Write-Host ("1") -NoNewline
    Write-Host (" [ ") -ForegroundColor Yellow -NoNewline
    Write-Host ($ssaConfig.Databases.SearchAdmin.SQLInstance) -NoNewline
    Write-Host (" ]") -ForegroundColor Yellow

    Write-Host ("  * Crawl Stores        : ") -ForegroundColor Cyan -NoNewline
    Write-Host ($totalCrawlStoreCount) -NoNewline
    Write-Host (" [ ") -ForegroundColor Yellow -NoNewline
    $delim = ""
    foreach ($sql in $ssaConfig.Databases.CrawlStore.SQLInstance) { 
        Write-Host ($delim) -ForegroundColor Yellow -NoNewline
        Write-Host ($sql) -NoNewline
        $delim = ", "
    }
    Write-Host (" ]") -ForegroundColor Yellow

    Write-Host ("  * Links Stores        : ") -ForegroundColor Cyan -NoNewline
    Write-Host ($totalLinksStoreCount) -NoNewline
    Write-Host (" [ ") -ForegroundColor Yellow -NoNewline
    $delim = ""
    foreach ($sql in $ssaConfig.Databases.LinksStore.SQLInstance) { 
        Write-Host ($delim) -ForegroundColor Yellow -NoNewline
        Write-Host ($sql) -NoNewline
        $delim = ", "
    }
    Write-Host (" ]") -ForegroundColor Yellow

    Write-Host ("  * Analytics Reporting : ") -ForegroundColor Cyan -NoNewline

    Write-Host ($totalReportingStoreCount) -NoNewline
    Write-Host (" [ ") -ForegroundColor Yellow -NoNewline
    $delim = ""
    foreach ($sql in $ssaConfig.Databases.AnalyticsReportingStore.SQLInstance) { 
        Write-Host ($delim) -ForegroundColor Yellow -NoNewline
        Write-Host ($sql) -NoNewline
        $delim = ", "
    }
    Write-Host (" ]") -ForegroundColor Yellow
}
#-- Advanced properties that can be defined in the $DeploymentConfigFile
#	(optional)AdminPoolName = "SearchWebAdminAppPool";
#	(optional)AppPoolAccount = "CHOTCHKIES\searchSvc";	   #typically these use the same identity  
#	(optional)AdminPoolAccount = "CHOTCHKIES\searchSvc";   #as the Search Service Instance account

foreach ($netbios in $ssaConfig.Servers.keys) {	
	Write-Host ("`n[ ") -ForegroundColor Yellow -NoNewline
    Write-Host ($netbios) -NoNewline
    Write-Host (" ]") -ForegroundColor Yellow
	Write-Host ("  * Components: ") -ForegroundColor Cyan -NoNewline
    $delim = ""
    foreach ($comp in $ssaConfig.Servers[$netbios].Components) { 
        Write-Host ($delim) -ForegroundColor Yellow -NoNewline
        Write-Host ($comp) -NoNewline
        $delim = ", "
    }
    Write-Host
	$componentsToDeploy += $ssaConfig.Servers[$netbios].Components

	#-- Start the Search Instances (if not already online) on the relevant servers
    if ((Get-SPServer $netbios -ErrorVariable err -ErrorAction SilentlyContinue) -eq $null) {
        Write-Warning ("The server" + $netbios + "is not found in this farm...")
        $passedChecks = $false
    } else {
        if ((Get-SPEnterpriseSearchServiceInstance -identity $netbios).status -ne "Online") {
            if ($ssaConfig.StartServiceInstances -isNot [bool]) {
                do {
                    Write-Host $("     > Would you like this script to start SP Search Service Instances [y/n]? ") -ForegroundColor Yellow -NoNewline
			        $userResponse = Read-Host
                    if ($userResponse -eq "?") { 
                        Write-Host $("       -- Enter `"y`" to start this required service instance on all Search Servers ") -ForegroundColor DarkCyan
                        Write-Host $("       -- Enter `"n`" to make no changes to the environment") -ForegroundColor DarkCyan
                        $userResponse = $null
                    }
                } while ([string]::isNullOrWhitespace($userResponse))
                $ssaConfig.StartServiceInstances = $truthyResponses.Contains($userResponse.toString().trim().toLower())
	        }

            if ($ssaConfig.StartServiceInstances) {
			    Write-Host ("     -- Starting ") -NoNewline
                Write-Host ("`"SharePoint Server Search`" ") -ForegroundColor Magenta -NoNewline
                Write-Host ("Service Instance...")
			    Start-SPEnterpriseSearchServiceInstance -identity $netbios
            } else {
                Write-Warning ("The `"SharePoint Server Search`" Service Instance is required, but not started" )
                $passedChecks = $false
            }
        } 
    }
    #$ssaConfig.Servers[$netbios].instance = Get-SPEnterpriseSearchServiceInstance -identity $netbios

	#-- Validate the "RootDirectory" path if this is an Indexer server
	$idxConfig = $ssaConfig.Servers[$netbios].replicaConfig
    $createIndexRootDir = $null
	if ($idxConfig -ne $null) {
		if ($idxConfig -is [Hashtable]) {
			$ssaConfig.Servers[$netbios].replicaConfig = @( $idxConfig )
			$idxConfig = $ssaConfig.Servers[$netbios].replicaConfig 
		}
		if ($idxConfig.Count -gt 4) {
			Write-Warning ("More than 4 Index Replicas on a single server is not supported")
			$passedChecks = $false
		} else {
			foreach ($replica in $idxConfig) {
				Write-Host ("  * Index Replica") -ForegroundColor Cyan
				if ($replica.Partition -ne $null) {
					Write-Host ("     - Partition (#): ") -ForegroundColor Cyan -NoNewline
                    Write-Host ($replica.Partition)
				}
				if ($replica.Path -ne $null) {
					Write-Host ("     - RootDirectory: ") -ForegroundColor Cyan -NoNewline
                    Write-Host ($replica.Path)
					if ($netbios -ine $ENV:COMPUTERNAME) {
						$rootDirectory = "\\" + $netbios + "\" + $replica.Path.Replace(":\","$\")
					} else {
						$rootDirectory = $replica.Path
					}
					
					if (Test-Path $rootDirectory) {
						$contents = $rootDirectory | gci
						if ($contents.Count -gt 0) {
							Write-Warning ("The following RootDirectory is not empty as suggested: " + $replica.path)
						}
					} else {
                        if ($createIndexRootDir -isNot [bool]) {
                            do {
                                Write-Host $("        > Would you like this script to create this path for you [y/n]? ") -ForegroundColor Yellow -NoNewline
			                    $userResponse = Read-Host
                                if ($userResponse -eq "?") { 
                                    Write-Host $("        > Would you like this script to create this path for you [y/n]? ") -ForegroundColor Yellow -NoNewline
                                    Write-Host $("           -- Enter `"y`" to create this path on applicable Index Server ") -ForegroundColor DarkCyan
                                    Write-Host $("           -- Enter `"n`" to make no changes to the environment") -ForegroundColor DarkCyan
                                    $userResponse = $null
                                }
                            } while ([string]::isNullOrWhitespace($userResponse))
                            $createIndexRootDir = $truthyResponses.Contains($userResponse.toString().trim().toLower())
	                    }

						if ($createIndexRootDir) {
			                Write-Host ("        -- Creating RootDirectory: ") -NoNewline
                            Write-Host ($rootDirectory) -ForegroundColor Magenta
							New-Item -path $rootDirectory -ItemType Directory | Out-Null
						}
						$passedChecks = $passedChecks -and $(Test-Path $rootDirectory)
					}
				}
			}
		}
	}
}

Write-Host
#-- Check that each of the component types are being added to at least one server...
$referenceComponents = ("Admin", "CC", "CPC", "Idx", "APC", "QPC")
$delta = Compare-Object $referenceComponents $($componentsToDeploy | SELECT -Unique)
if ($delta.Count -gt 0) {
	#if ($ssaConfig.CloudIndex) {
	#	$cloudComponents = ("Admin", "CC", "QP")
	#	$delta = Compare-Object $referenceComponents $($componentsToDeploy | SELECT -Unique)
	#} else {
	Write-Warning ("This requested topology is missing at least one of the following components:")
	Write-Host $( $delta | ForEach {$_.InputObject} )
	$passedChecks = $false
}

if (-not $passedChecks) {
	Write-Warning ("One or more checks above failed... <terminating script>") 
	start-sleep 2
	exit
}

if ([Environment]::UserInteractive) {
    do {
        Write-Host $("Would you like to save this configuration? [y/n] ") -ForegroundColor Yellow -NoNewline
		$userResponse = Read-Host
        if ($userResponse -eq "?") { 
            Write-Host $("    -- Enter `"y`" to save this `$ssaConfig to .\deployConfig.json file for later reuse") -ForegroundColor DarkCyan
            Write-Host $("    -- Enter `"n`" to continue without saving this configuration") -ForegroundColor DarkCyan
            $userResponse = $null
        }
    } while ([string]::isNullOrWhitespace($userResponse))
    if ($truthyResponses.Contains($userResponse.toString().trim().toLower())) {
        $DeploymentConfigFile = $(Join-Path $PWD.Path "deployConfig.json")
        try {
            $ssaConfig | ConvertTo-JSON -Depth 4 | Out-File $DeploymentConfigFile
            Write-Host $(" -- Saved to: ") -ForegroundColor DarkCyan -NoNewline
            Write-Host ($DeploymentConfigFile)
        } catch {
            Write-Warning ("A failure occurred when writing the output to: " + $DeploymentConfigFile)
        }
    }

    do {
        Write-Host $("Would you like the script to deploy this SSA now? [y/n] ") -ForegroundColor Yellow -NoNewline
		$userResponse = Read-Host
        if ($userResponse -eq "?") { 
            Write-Host $("    -- Enter `"y`" to continue with the steps to deploy the new SSA") -ForegroundColor DarkCyan
            Write-Host $("    -- Enter `"n`" to quit this script without deploying the SSA") -ForegroundColor DarkCyan
            $userResponse = $null
        }
    } while ([string]::isNullOrWhitespace($userResponse))
    
    if ( -not $truthyResponses.Contains($userResponse.toString().trim().toLower())) { 
        Write-Host $("...now closing this script without deploying the SSA")
        exit
    } 
}

#================================================
#== And now, deploy the defined configuration...
#================================================

$err = $null
#-----------------------------
# Create the Service Accounts
#-----------------------------

function SetSPServiceAccount {
	param ($serviceAccountName)
	# Create managed account if it does not exist
	if ((Get-SPManagedAccount $serviceAccountName -ErrorVariable err -ErrorAction SilentlyContinue) -eq $null) {
	  Write-Host ("****************************************************** ")
	  Write-Host -ForegroundColor DarkCyan ("* Create managed account for " + $serviceAccountName)
	  Write-Host ("****************************************************** ")
	  $credential = Get-Credential
	  if ($credential -eq $null) { Write-Error ("[The `$credential value is `$null] Terminating script..."); start-sleep -s 3; exit; }
	  New-SPManagedAccount -Credential $credential 
	}	
}

if ($ssaConfig.SearchServiceAccount -ne $null) {
	SetSPServiceAccount $ssaConfig.SearchServiceAccount
} else {
	$ssaConfig.SearchServiceAccount = $(Get-SPEnterpriseSEarchService).ProcessIdentity
}

if ($ssaConfig.AppPoolAccount -ne $null) {
	SetSPServiceAccount $ssaConfig.AppPoolAccount
} else {
	$ssaConfig.AppPoolAccount = $ssaConfig.SearchServiceAccount
}

if ($ssaConfig.AdminPoolAccount -ne $null) {
	SetSPServiceAccount $ssaConfig.AdminPoolAccount
} else {
	$ssaConfig.AdminPoolAccount = $ssaConfig.AppPoolAccount
}

#-----------------------------------------
# Set the Search Service Instance account
#-----------------------------------------
if ($ssaConfig.SearchServiceAccount -ne $(Get-SPEnterpriseSEarchService).ProcessIdentity) {
	if ($existingSSACount -gt 0) {
		Write-Warning ("The existing Search Service Account is: " + $(Get-SPEnterpriseSEarchService).ProcessIdentity)
		Write-Warning ("And this script specifies: " + $ssaConfig.SearchServiceAccount)
		Write-Warning ("---")
		Write-Warning ("Making this change will impact the other existing SSA(s):")
		foreach	($searchServiceApp in Get-SPEnterpriseSearchServiceApplication) {
			Write-Warning (" - " + $searchServiceApp.Name)
		}
        
        do {
		    Write-Warning ("Are you sure you want to proceed with this service account change [y/n]?")
            $userResponse = Read-Host
        } while ([string]::isNullOrWhitespace($userResponse))
        if ($truthyResponses.Contains($userResponse.toString().trim().toLower())) {
			Write-Host ("Terminating script..."); start-sleep 1; exit; 
		}
	}
	$pwd_secure_string = read-host -assecurestring ("Enter the password for " + $ssaConfig.SearchServiceAccount + " ")
	Set-SPEnterpriseSearchService -IgnoreSSLWarnings $true -ServiceAccount $ssaConfig.SearchServiceAccount -ServicePassword $pwd_secure_string
	Write-Host ("...sleeping for 60 seconds for change to propagate")
	start-sleep 60
}

#-----------------------
# Create the App Pool(s)
#-----------------------
$sqssPool = Get-SPServiceApplicationPool | where {$_.Name -eq $ssaConfig.AppPoolName }
if ($sqssPool -ne $null) { 
    Write-Verbose ("-- Search App Pool [" + $ssaConfig.AppPoolName + "] already exists... <skipping>")
} else { 
	$sqssPool = New-SPServiceApplicationPool -name $ssaConfig.AppPoolName -account $ssaConfig.AppPoolAccount
}

if ($ssaConfig.AdminPoolName -ne $null) {
    $adminPool = Get-SPServiceApplicationPool | where {$_.Name -eq $ssaConfig.AdminPoolName }
    if ($adminPool -ne $null) { 
        Write-Verbose ("-- Search Admin App Pool [" + $ssaConfig.AdminPoolName + "] already exists... <skipping>")
    } else { $adminPool = New-SPServiceApplicationPool -name $ssaConfig.AdminPoolName -account $ssaConfig.AdminPoolAccount }
} else {
    $adminPool = $sqssPool;
}

$ssaConfig["sqssPool"] = $sqssPool
$ssaConfig["adminPool"] = $adminPool

#------------------------------------------------------------------------------------------------
# Create the new SSA (which will take a while (~15min) to run...
#   - And it will also report a failure b/c the index path is null... currently this is expected
#------------------------------------------------------------------------------------------------
Write-Host ("`n`n")
Write-Host ("------------------------------------") -ForegroundColor DarkCyan
Write-Host ("--- ") -ForegroundColor DarkCyan -NoNewline
Write-Host ("Deploying this configuration ") -ForegroundColor Yellow -NoNewline
Write-Host ("---") -ForegroundColor DarkCyan
Write-Host ("------------------------------------`n") -ForegroundColor DarkCyan

$startTime = Get-Date
Write-Host (" * Creating a new SSA (this may take several minutes)...") -ForegroundColor DarkCyan 
Write-Host ("    - Starting at: ") -ForegroundColor Cyan -NoNewline
Write-Host ($startTime)

if ($ssaConfig.Databases.dbNamePrefix -ne $null) { 
    $dbPrefix = $ssaConfig.Databases.dbNamePrefix 
} elseif ($ssaConfig.SSAHandle -ne $null) { 
    $dbPrefix = $ssaConfig.SSAHandle 
} else {
    $dbPrefix = $ssaConfig.SSAName
}

$newSSA = New-SPEnterpriseSearchServiceApplication -name $ssaConfig.SSAName -ApplicationPool $ssaConfig.sqssPool -AdminApplicationPool $ssaConfig.adminPool -DatabaseServer $ssaConfig.Databases.SearchAdmin.SQLInstance -DatabaseName $dbPrefix -CloudIndex $ssaConfig.CloudIndex
Write-Host ("    - Time span for initial creation: ") -ForegroundColor Cyan -NoNewline
Write-Host (New-TimeSpan $startTime (Get-Date))
Write-Host

if (-not $newSSA.AdminComponent.Initialized) {
	Write-Output "Waiting for the Legacy Admin Component to be initialized..." 
	$startTime = Get-Date
	$timeoutTime=($startTime).AddMinutes(20) 
	do {Write-Output .;Start-Sleep 10;} while ((-not $newSSA.AdminComponent.Initialized) -and ($timeoutTime -ge (Get-Date))) 
	if (-not $newSSA.AdminComponent.Initialized) { throw 'Legacy Admin Component (`$SSA.AdminComponent) could not be initialized!'}
	Write-Host ("   - Time span for Legacy Admin Component to be initialized: ") -ForegroundColor Cyan -NoNewline
    Write-Host (New-TimeSpan (Get-Date) $startTime)
	Write-Host
}

#Creating new topology..."
$global:newTopo = $newSSA | New-SPEnterpriseSearchTopology 

#------------------------------------------
# Create the new components on each server
#------------------------------------------
Write-Host (" * Mapping Components to specified server" + $(if ($ssaconfig.servers.count -gt 1) {"s"}) + "...`n ") -ForegroundColor DarkCyan 
foreach ($netbios in $ssaConfig.Servers.keys) {
	foreach ($type in $ssaConfig.Servers[$netbios].components) {
        Write-Host ("[ ") -ForegroundColor Yellow -NoNewline
        Write-Host ($netbios) -NoNewline
        Write-Host (" ]") -ForegroundColor Yellow -NoNewline
        Write-Host (" --> ") -ForegroundColor DarkCyan -NoNewline
        Write-Host ($type) -ForegroundColor Cyan

        switch ($type) {
		    "Admin" {
    			New-SPEnterpriseSearchAdminComponent -SearchTopology $newTopo -SearchServiceInstance $netbios
                $newSSA | Get-SPEnterpriseSearchAdministrationComponent | Set-SPEnterpriseSearchAdministrationComponent -SearchServiceInstance $netbios
			    $newSSA | Get-SPEnterpriseSearchAdministrationComponent
		    }
	    	"CC" { New-SPEnterpriseSearchCrawlComponent -SearchTopology $newTopo -SearchServiceInstance $netbios }
	    	"CPC" { New-SPEnterpriseSearchContentProcessingComponent -SearchTopology $newTopo -SearchServiceInstance $netbios }
	    	"APC" { New-SPEnterpriseSearchAnalyticsProcessingComponent -SearchTopology $newTopo -SearchServiceInstance $netbios }
			"QPC" { New-SPEnterpriseSearchQueryProcessingComponent -SearchTopology $newTopo -SearchServiceInstance $netbios }
			"Idx" { 
				$idxConfig = $ssaConfig.Servers[$netbios].replicaConfig
				if ($idxConfig -ne $null) {
					foreach ($replica in $idxConfig) {
						if ($replica.Partition -eq $null) { $partition = 0 }
						else { $partition = $replica.Partition }
						
						$idxComp = (New-Object Microsoft.Office.Server.Search.Administration.Topology.IndexComponent $netbios, $partition);
						if ($replica.Path -ne $null) {
							$idxComp.RootDirectory = $replica.Path
						}
						$newTopo.AddComponent($idxComp)
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
$startTime = Get-Date
Write-Host (" * Activating (e.g. provisioning) the topology (which will run for several minutes)...") -ForegroundColor DarkCyan 
Write-Host ("    - Starting at: ") -ForegroundColor Cyan -NoNewline
Write-Host ($startTime)
$newTopo.Activate()
Write-Host ("    - Time span for activation: ") -ForegroundColor Cyan -NoNewline
Write-Host (New-TimeSpan $startTime (Get-Date))
Write-Host

Write-Host  " * Cleaning up the inactive topology" -ForegroundColor DarkCyan
while ($newTopo.State -ne "Active") { "."; start-sleep 10; } 
$newSSA | Get-SPEnterpriseSearchTopology | Where {$_.State -eq "Inactive" } | Remove-SPEnterpriseSearchTopology -Confirm:$false

Write-Host  " * Creating an SSA Proxy" -ForegroundColor DarkCyan
$ssaProxy = New-SPEnterpriseSearchServiceApplicationProxy -name $ssaConfig.SSAName -SearchApplication $newSSA

#---------------------------------------
# Set the Default content access account
#---------------------------------------
if (($ssaConfig.CrawlAccount -ne $null) -and ($ssaConfig.CrawlAccount -ne $ssaConfig.SearchServiceAccount)) {
  $pwd_secure_string = read-host -assecurestring ("Enter the password for the Default Crawl Account [" + $ssaConfig.CrawlAccount + "] ")
  Set-SPEnterpriseSearchServiceApplication -DefaultContentAccessAccountName $ssaConfig.CrawlAccount -DefaultContentAccessAccountPassword $pwd_secure_string -Identity $newSSA
}

#--------------------------------------
# Scale out Search DBs (if applicable)
#--------------------------------------
if ($hasDBScaleOut) {
    Write-Host ("`n`n")
    Write-Host ("------------------------------------") -ForegroundColor DarkCyan
    Write-Host ("--- ") -ForegroundColor DarkCyan -NoNewline
    Write-Host ("Scaling out Search Databases ") -ForegroundColor Yellow -NoNewline
    Write-Host ("---") -ForegroundColor DarkCyan
    Write-Host ("------------------------------------`n") -ForegroundColor DarkCyan

    Write-Host (" * Pausing ") -ForegroundColor DarkCyan -NoNewline
    Write-Host ($newSSA.name) -ForegroundColor Cyan -NoNewline
    Write-Host ("for database scale out") -ForegroundColor DarkCyan
	$bigBucket = $newSSA.Pause()

	#---------------------
	# Create crawl stores
	#---------------------
    if ($hasCrawlStoreDBScaleOut) {
        Write-Host (" * Processing Crawl Stores:") -ForegroundColor DarkCyan	
	    $oldCrawlStore = Get-SPEnterpriseSearchCrawlDatabase –SearchApplication $newSSA 

        $totalOffset = 1
        foreach ($csConfig in $ssaConfig.Databases.CrawlStore) { 
            Write-Host $("   == SQL Server [ ") -ForegroundColor DarkGray -NoNewline
			Write-Host $($csConfig.SQLInstance) -ForegroundColor Cyan -NoNewline
			Write-Host $(" ] == ") -ForegroundColor DarkGray
            $upperBound = $csConfig.DBCount + $totalOffset
            for($i = $totalOffset; $i -lt $upperBound; $i++) {
    		    $dbName = $ssaConfig.Databases.dbNamePrefix + "_CrawlStore-" + [string]$i
		        Write-Host ("       - Creating database: ") -NoNewline
                Write-Host ($dbName) -ForegroundColor Magenta
                $params = @{ SearchApplication = $newSSA;
					         DatabaseName = $dbName;
					         DatabaseServer = $csConfig.SQLInstance }
		        if (-not ([string]::IsNullOrWhiteSpace($csConfig.FailoverDatabaseServer))) {
			        $params['FailoverDatabaseServer'] = $csConfig.FailoverDatabaseServer
		        }
                New-SPEnterpriseSearchCrawlDatabase @params | Out-Null
                $totalOffset++;
            }
        }
    } 

	#---------------------
	# Create links stores
	#---------------------
    if ($hasLinksStoreDBScaleOut) {
        Write-Host ("`n * Processing Links Stores...") -ForegroundColor DarkCyan	
	    $oldLinksStore = Get-SPEnterpriseSearchLinksDatabase –SearchApplication $newSSA 

        $totalOffset = 1
        foreach ($csConfig in $ssaConfig.Databases.LinksStore) { 
            Write-Host $("   == SQL Server [ ") -ForegroundColor DarkGray -NoNewline
			Write-Host $($csConfig.SQLInstance) -ForegroundColor Cyan -NoNewline
			Write-Host $(" ] == ") -ForegroundColor DarkGray
            $upperBound = $csConfig.DBCount + $totalOffset
            for($i = $totalOffset; $i -lt $upperBound; $i++) {
    		    $dbName = $ssaConfig.Databases.dbNamePrefix + "_LinksStore-" + [string]$i
		        Write-Host ("       - Creating database: ") -NoNewline
                Write-Host ($dbName) -ForegroundColor Magenta
                $params = @{ SearchApplication = $newSSA;
					         DatabaseName = $dbName;
					         DatabaseServer = $csConfig.SQLInstance }
		        if (-not ([string]::IsNullOrWhiteSpace($csConfig.FailoverDatabaseServer))) {
			        $params['FailoverDatabaseServer'] = $csConfig.FailoverDatabaseServer
		        }
                $placeholder =  New-SPEnterpriseSearchLinksDatabase @params | Out-Null
                $totalOffset++;
            }
        }
        $newLinksDBs = $newSSA | Get-SPEnterpriseSearchLinksDatabase | where {$_.Id -ne $oldLinksStore.Id}
    } 
  
    #--------------------------------
	# Create analytics reporting dbs
	#--------------------------------
    if ($hasReportingStoreDBScaleOut) {
        Write-Host (" * Processing Analytics Reporting Databases") -ForegroundColor DarkCyan	
	    $oldARStore = Get-SPServerScaleOutDatabase -ServiceApplication $newSSA 

        $totalOffset = 1
        foreach ($csConfig in $ssaConfig.Databases.AnalyticsReportingStore) { 
            Write-Host $("   == SQL Server [ ") -ForegroundColor DarkGray -NoNewline
			Write-Host $($csConfig.SQLInstance) -ForegroundColor Cyan -NoNewline
			Write-Host $(" ] == ") -ForegroundColor DarkGray
            $upperBound = $csConfig.DBCount + $totalOffset
            for($i = $totalOffset; $i -lt $upperBound; $i++) {
    		    $dbName = $ssaConfig.Databases.dbNamePrefix + "_AnalyticsReportingStore-" + [string]$i
		        Write-Host ("       - Creating database: ") -NoNewline
                Write-Host ($dbName) -ForegroundColor Magenta
                $params = @{ ServiceApplication = $newSSA;
                             DatabaseName = $dbName;
                             DatabaseServer = $csConfig.SQLInstance;            
                }
		        if (-not ([string]::IsNullOrWhiteSpace($csConfig.FailoverDatabaseServer))) {
			        $params['DatabaseFailoverServer'] = $csConfig.FailoverDatabaseServer
		        }
                $bitBucket = Add-SPServerScaleOutDatabase @params | Out-Null
                $totalOffset++
            }
        }
    } 

	Write-Host ("`n * Resuming ") -ForegroundColor DarkCyan -NoNewline
    Write-Host ($newSSA.name) -ForegroundColor Cyan
    $bitBucket =$newSSA.Resume()

    Write-Host (" * Removing default databases:") -ForegroundColor DarkCyan
    if ($hasCrawlStoreDBScaleOut) {
        Write-Host ("    > Removing: ") -ForegroundColor Yellow -NoNewline
        Write-Host ($oldCrawlStore.name)
	    $bitBucket = $oldCrawlStore | Remove-SPEnterpriseSearchCrawlDatabase -Confirm:$false | Out-Null
    }
    if ($hasLinksStoreDBScaleOut) {
        Write-Host ("    > Removing: ") -ForegroundColor Yellow -NoNewline
        Write-Host ($oldLinksStore.name)
        $bitBucket = $newSSA | Move-SPEnterpriseSearchLinksDatabases -TargetStores $newLinksDBs | Out-Null
	    $bitBucket = $oldLinksStore | Remove-SPEnterpriseSearchLinksDatabase -Confirm:$false | Out-Null
    }
    #if ($hasReportingStoreDBScaleOut) {
    #    Write-Host ("    > Removing: ") -ForegroundColor Yellow -NoNewline
    #    Write-Host ($oldARStore.name)
    #    $bitBucket = $oldARStore | Remove-SPServerScaleOutDatabase -ServiceApplication $SSA -Confirm:$false | Out-Null
    #}
}

Write-Host ("`n`n-----------------------------------------------------------------") -ForegroundColor DarkGray
Write-Host ("--> ") -ForegroundColor DarkGray -NoNewline
Write-Host (" Successfully Completed SSA Deployment: ") -ForegroundColor Green -NoNewline
Write-Host (Get-Date)


#if the SRx is in the same path... offer to launch it now...
if (([Environment]::UserInteractive) -and (Test-Path (Join-Path $PsScriptRoot "..\..\initSRx.ps1"))) { 
    Write-Host ("`n`nWould you want to validate this deployment with the ") -ForegroundColor Yellow -NoNewline
    Write-Host ("`Search Health Reports (SRx) ") -ForegroundColor DarkCyan -NoNewline
    Write-Host ("now [y/n]? ") -ForegroundColor Yellow -NoNewline
    $userResponse = Read-Host
    if ($truthyResponses.Contains($userResponse)) {
        $SRxInitScript = (Join-Path ($PsScriptRoot.toLower().replace('\lib\scripts', "")) "initSRx.ps1")
        Write-Host ("  -- Running: ") -ForegroundColor DarkCyan -NoNewline
        Write-Host ($SRxInitScript + "`n")
        . $SRxInitScript -SSA $newSSA  #run the SRx initialization script in local scope
        if ($global:SRxEnv.exists) {
            New-SRxReport -RunAllTests
        } else {
            Write-Warning ("--- A failure occurred initializing the Search Health Reports (SRx) script for diagnostics")
        }
    }
}


# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCif0hCLUxpGqNK
# ZANvPeJSQPFSi1R2fgq0hjL5IZWx8KCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIC31auHN3qsDyqdsmDIwzv5J5JVBBi9PyuBvgLhhGS7rMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBALjNkxsoDSjtGxPmeK/bzC7F
# 7vHnGjqx5j6TG7xq2Gdg7hHi6u5eGkKLMSWBOsEwJThCpsJGilBN2yC3+AJeP38K
# XPzOksdI35sf8TCZ7ODUFk1JNhMUpME+mdsNC4u7CNbh1yTRypux8hqBJ6VVslwd
# DcKzD3BIqv2X1Cip5C5u1c2PVfd8UZ4HAFs3wqxpbVfBOZm3PErLO5lmVARLp7N+
# 38ZgE2fMxhpmenyJQVXO7gYUsyebL8nRavpcDFZSMgHp/cwzO07j0l+f7lPJsj9D
# Fb9ScEJDtbxyWoxNv0yRZ22wruPJn7C/KJ7N9wDJXislok2YS2pNwAHtoMx4IMih
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQg7oo55OonRsKwkyzvsgm2
# eBhi6fodLNNLoKaromw8f4UCBljVRqE86xgTMjAxNzA0MjYyMzUzNDUuODk1WjAH
# AgEBgAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkY1
# MjgtMzc3Ny04QTc2MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
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
# 7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNowggPCoAMCAQICEzMAAACw
# humSIApd6vgAAAAAALAwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU2WhcNMTgwOTA3MTc1NjU2WjCBszEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkY1MjgtMzc3Ny04QTc2MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEA8OXwjZRZqZrXbAkHdxQhWV23PXi4Na31MDH/zuH/
# 1ukayYOYI/uQEMGS7Dq8UGyQvVzxa61MovVhpYfhKayjPBLff8QAgs69tApfy7nb
# mrcZLVrtBwCtVP0zrPb4EiRKJGdX2rhLoawPgPk5vSANtafELEvxoVbm8i8nuSbB
# MyXZKwwwclCEa5JqlYzy+ghNuC4k1UPT3OvzdGqIs8m0YNzJZa1fCeURahQ0weRX
# BhJG5qC9hFokQkP2vPQsVZlajbOIpqoSlCK+hrVKiYyqR7CgxR8bj5zwYm1UnTLT
# qcSbU+m5cju/F56vWFydxitQIbvYlsw2742mc9mtu0NwFQIDAQABo4IBGzCCARcw
# HQYDVR0OBBYEFPyoB1LZ7yn+mEM8FVx0Xrd/c+CvMB8GA1UdIwQYMBaAFNVjOlyK
# MZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3
# LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEu
# Y3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcN
# AQELBQADggEBAJL9gPd1vWWQPhfN1RWDxY4CkTusTn1g7485BpOQ4w+qRT2JPwL9
# 7G+4UJAJbITSNyGZscGGdh3kDcaO/xjgovpGtYV3dG5ODERF0LzStgR+cEsP1qsH
# aVZKdmTo+apHo6OG3PTPRLhJEFtnj9Haea463YdTBuiPavx/1+SjhkUVDZFiIjqQ
# SuPYaAFJyS0Oa3hsEQL0j00RYHOoAyENl+MPcnW7/egOuOv8IEGdjpP9xTNzPjl6
# vWo0HjlHYhG1HO9X9HODcZ+oFGW+5AOOTW3EATMbflfsofMcl6k4p/SoOjn5iTX8
# XaMirgq9jQyrMRJu6b1hFuz0GTokhWJfqbKhggN2MIICXgIBATCB46GBuaSBtjCB
# szELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxME
# TU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkY1MjgtMzc3Ny04QTc2MSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4D
# AhoFAAMVALyE+51bEtrHNoU7iGaeoxYY1cwcoIHCMIG/pIG8MIG5MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYD
# VQQLEx5uQ2lwaGVyIE5UUyBFU046NTdGNi1DMUUwLTU1NEMxKzApBgNVBAMTIk1p
# Y3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQAC
# BQDcq1AaMCIYDzIwMTcwNDI2MTY1ODAyWhgPMjAxNzA0MjcxNjU4MDJaMHQwOgYK
# KwYBBAGEWQoEATEsMCowCgIFANyrUBoCAQAwBwIBAAICJkwwBwIBAAICGFIwCgIF
# ANysoZoCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQAC
# AxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEAXtsbEjhFAICab6RG
# 4wdOJddf4XAMLeJhY+Fh36EzfNgX3hfWZnhbMBYHnOtPc9EM2aaaa07/fjYb3S+F
# T3lDepqaax03QCnFJ0fy/iZom7nkbn+obOaXi9UxbmDcYDuS/fcCSaTxZ95bR8ib
# ZYsDQQ29jjFBpWh7BuqBZ0c00e8UFCArCDaVKmfh/f2nBd4sHAsS+yz4hQhOqpYM
# 0b7mUuTic4rn6Ph9A1aBeAe9pjNq0YyAKya93w81CtuzBIrIFsnKUHMYR6SNOH4K
# ef7gQEyjRY7mgFC8rrrJbkKRv3EyLokxm7ef6vc7g86R3quyY1EMjCQBFIGLi3XN
# sWTYdjGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAAsIbpkiAKXer4AAAAAACwMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIFl+IW8vKf+L2Pw9
# 1BHYkhHzX462N0p5epU/vuYzN19pMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUvIT7nVsS2sc2hTuIZp6jFhjVzBwwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAALCG6ZIgCl3q+AAAAAAAsDAWBBRnsOQFab38m9PY
# MldGBT0kLsOaSTANBgkqhkiG9w0BAQsFAASCAQCHVE6bhognyjUPFyg1Cr4R5lWe
# SwJPvD4B8tHTCF90QNcrhBW6igKGTtZnaY6qwLiizMN/atSVKU6+aY0X243is9Vw
# dCRev2xOW6hW1SYaMCSMIk+9euTww68yFKyOpB4wWk6jptlG/POjlQ09Eh66nW+/
# wEwiQk10gXRRDSL4hhayPhHFLhhzLKE7CSbkVWb4YyJRPgCGLSZWRall/eOwVeyf
# 1doqL6dc90zpeX1DNS4/3nUs1uqx9kz5R9gj5LdGDRsylNxQUZbz79BrbK2zw7PL
# /9IL9cIsycNsrv8ZP6oy1Xv5k18/g0SnBBuV2Lene3wPDJrJW0lUjsFFHx0s
# SIG # End signature block
