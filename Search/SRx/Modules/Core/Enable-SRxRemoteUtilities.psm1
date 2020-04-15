#=============================================
# Project		: Search Health Reports (SRx)
#---------------------------------------------
# File Name 	: Enable-SRxRemoteUtilities.psm1
# Author		: Eric Dixon, Brian Pendergrass
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

function Enable-SRxRemoteTool 
{
<#
.SYNOPSIS

.DESCRIPTION

.INPUTS
	
.NOTES

#>
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true,ValueFromPipeline=$true)]
    $TargetServer,
    [parameter(Mandatory=$true)]
    $ToolName,
    $ToolExe,
    [Object[]]$ToolSupportFiles=@()
)

BEGIN {
    if(-not $global:SRxEnv.RemoteUtilities) {
        $global:SRxEnv.PersistCustomProperty("RemoteUtilities", $(New-Object PSOBject))
    }

    $global:OldDriveLetter = $null
    if(AddRemoteTool -ToolName $ToolName) {
        $TargetDrive = GetToolDriveLetter -ToolName $ToolName
	    $status = $true
    } else {
		$status = $false
		return $status
	}

    # add tool to handle map
    if(-not $global:SRxEnv.RemoteUtilities.$ToolName) {
        $o = New-Object PSObject -Property @{
            Initialized=$false;
            Exe=$ToolExe;
            SupportFiles=$ToolSupportFiles;
            Drive=$TargetDrive;
            Servers=@();
        }
        $global:SRxEnv.PersistCustomProperty("RemoteUtilities.$ToolName", $o)
    }

    $serversToAdd = New-Object System.Collections.ArrayList
}

PROCESS {
	if($status -eq $false) {
		return
	}
    # todo: create function member on object
    Write-SRx INFO ("Enabling Remote Utility $ToolName on $($TargetServer.Name)...") -ForegroundColor Cyan 

    $serversToAdd.Add($TargetServer.name) | Out-Null

    try {
        # create folders on target server
        $ScriptBlock = { 
            param([string]$newToolPath)
            New-Item -Path (Join-Path $newToolPath "bin") -type directory -Force | Out-Null
            New-Item -Path (Join-Path $newToolPath "var") -type directory -Force | Out-Null
        }

        $toolPath = GetToolPath -ToolName $ToolName
        Write-SRx INFO ("Copying $ToolName executables to '$toolPath' on $($TargetServer.Name)...") -ForegroundColor Cyan 
        if($env:COMPUTERNAME -eq $TargetServer.Name){
            Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList(,$toolPath)
        } else {
            try{
                Invoke-Command -ComputerName $TargetServer.Name -ScriptBlock $ScriptBlock -ArgumentList(,$toolPath) -ErrorAction Stop
            }catch{
                # connect to the computer from client using kerberos as the current user:
                Invoke-Command -ComputerName $TargetServer.Name -ScriptBlock $ScriptBlock -ArgumentList(,$toolPath) -Authentication NegotiateWithImplicitCredential  
            }
        }

        $toolPath = (GetToolPath -ToolName $ToolName).Replace(":","$")
        $toolPathBin = (Join-Path $toolPath "bin") 
        $destPath = Join-Path "\\$($TargetServer.Name)" $toolPathBin

        # copy files to target server
        Copy-Item (Join-Path $global:SRxEnv.Paths.Tools  $global:SRxEnv.RemoteUtilities.$ToolName.Exe) $destPath -Force -Recurse
        foreach($supportFile in $global:SRxEnv.RemoteUtilities.$ToolName.SupportFiles){
            Copy-Item (Join-Path $global:SRxEnv.Paths.Tools $supportFile) $destPath -Force -Recurse
        }
        $global:SRxEnv.PersistCustomProperty("RemoteUtilities.$ToolName.Initialized", $true)
    } catch {
        Write-SRx ERROR "Failed to create folders and copy files for $ToolName on $($TargetServer.Name)"
        Write-SRx DEBUG "Caught Exception"
        Write-SRx DEBUG "$_"
        $global:SRxEnv.PersistCustomProperty("RemoteUtilities.$ToolName.Initialized", $false)
        $status = $false
    }
}

END {
	if($status) {
        Write-SRx INFO ("Completed enabling $ToolName.") -ForegroundColor Cyan 

        $servers = $global:SRxEnv.RemoteUtilities.$ToolName.Servers
        $newServers = New-Object System.Collections.ArrayList

        foreach($s in $serversToAdd){
            if(-not ($servers -contains $s)) {
                $newServers.Add($s) | Out-Null
            }
        }
        $newServers.AddRange($servers) | Out-Null
        $global:SRxEnv.PersistCustomProperty("RemoteUtilities.$ToolName.Servers", $newServers)
	}

    return $status
}
}



function AddRemoteTool 
{
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true)]
    $ToolName
)

	if($global:SRxEnv.RemoteUtilities.$ToolName.Initialized)
	{
        Write-SRx VERBOSE "$ToolName is initialized."
	}
    else
    {
		$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Copy $ToolName to servers."
		$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Do not copy $ToolName."
		$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        Write-Host "The SRx Dashboard can run utilites on remote servers." -BackgroundColor DarkCyan -ForegroundColor White
        Write-Host "Enabling $ToolName implies you accept the EULA for this tool." -BackgroundColor DarkCyan -ForegroundColor White
		$title = "" 
		$message = "Do you want to enable $ToolName for SRx Dashboard?"
		$result = $host.ui.PromptForChoice($title, $message, $options, 1)
		switch ($result) 
		{
			0 { Write-Host "Yes";}
			1 { Write-Host "No"; return $false }
		}

		$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Copy $ToolName to servers."
		$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Do not copy $ToolName."
		$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        Write-Host "The $ToolName utility needs to be copied to each server in the search farm." -BackgroundColor DarkCyan -ForegroundColor White
		$title = "" 
		$message = "Do you want to copy the $ToolName utility to each server in the farm?"
		$result = $host.ui.PromptForChoice($title, $message, $options, 1)
		switch ($result) 
		{
			0 { Write-Host "Yes";}
			1 { Write-Host "No"; return $false }
		}

    }

    return $true
}



function GetToolDriveLetter
{
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true)]
    $ToolName
)
    $done = $false
    while(-not $done)
    {
	    Write-Host "Please specify a drive letter that exists on all search servers in the farm" -BackgroundColor DarkCyan -ForegroundColor White
	    Write-Host "where SRx will do all remote utilite file operations for $ToolName." -BackgroundColor DarkCyan -ForegroundColor White
	    while(-not ($driveLetter -match '^[a-zA-Z][:(:\\)]*$'))
	    {
		    Write-Host "Specify an existing drive." -BackgroundColor DarkCyan -ForegroundColor White
		    $driveLetter = Read-Host ">> Drive letter"
	    }
        $driveLetter = ($driveLetter.trim().ToUpper())[0]

	    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Accept"
	    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Re-enter"
	    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
	    $title = "" 
	    $message = "You have entered '$driveLetter'. Is this correct?"
	    $result = $host.ui.PromptForChoice($title, $message, $options, 0)
	    switch ($result) 
	    {
		    0 { Write-Host "Yes"; return $driveLetter}
		    1 { Write-Host "No"; $driveLetter = "";$done = $false }
	    }
    }
}


function GetToolPath
{
    param([string]$ToolName)
    return "$($global:SRxEnv.RemoteUtilities.$ToolName.Drive):\SRx\RemoteUtilities\$ToolName"
}

function IsEnabledRemoteTool {
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true)]
    $ToolName,
    [parameter(Mandatory=$true)]
    $TargetServer
)
    if($global:SRxEnv.RemoteUtilities.$ToolName.Initialized) {
        $servers = $global:SRxEnv.RemoteUtilities.$ToolName.Servers
        # check for .exe, .dll files and bin, var dirs
        $utilitiesFolder = Join-Path $("\\" + $TargetServer.Name) (GetToolPath -ToolName $ToolName)
        $utilitiesFolder = $utilitiesFolder.Replace(':','$')
        $binFolder = Join-Path $utilitiesFolder "bin"
        $varFolder = Join-Path $utilitiesFolder "var"

        $enable = $false
        if(-not ($servers -contains $TargetServer.Name)) {
            Write-SRx Verbose ("[IsEnabledRemoteTool] Server Not Initialized " + $TargetServer.Name) -ForegroundColor Magenta
            $enable = $true
        } elseif(-not (Test-Path (Join-Path $binFolder ($global:SRxEnv.RemoteUtilities.$ToolName.Exe)))) {
            Write-SRx Verbose ("[IsEnabledRemoteTool] " + $global:SRxEnv.RemoteUtilities.$ToolName.Exe + " not found on " + $TargetServer.Name) -ForegroundColor Magenta
            $enable = $true    
        } elseif(-not (Test-Path $varFolder)) {
            Write-SRx Verbose ("[IsEnabledRemoteTool] var folder not found on " + $TargetServer.Name) -ForegroundColor Magenta
            $enable = $true    
        } else {
            $supportFiles = $global:SRxEnv.RemoteUtilities.$ToolName.SupportFiles
            foreach($f in $supportFiles){
                if(-not (Test-Path (Join-Path $binFolder $f))) {
                    Write-SRx Verbose ("[IsEnabledRemoteTool] Support file " + $f + " not found on " + $TargetServer.Name) -ForegroundColor Magenta
                    $enable = $true
                    break
                }
            }
        }

        if($enable){
			Write-SRx Verbose "[IsEnabledRemoteTool] Enabling $ToolName on $($TargetServer.Name)..."-ForegroundColor Magenta
            $TargetServer | Enable-SRxRemoteTool -ToolName $ToolName
        }

        return $true
    }

    return $false
}

function Invoke-SRxRemoteTool 
{
<#
.SYNOPSIS

.DESCRIPTION

.INPUTS
	
.NOTES

#>
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
    $TargetServer,
    [parameter(Mandatory=$true)]
    $ToolName,
    [parameter(Mandatory=$true)]
    [Scriptblock]$CmdBlock,
    [parameter(Mandatory=$true)]
	[Hashtable]$InputParams=@{},
    [parameter(Mandatory=$false)]
	[Object[]]$OutputParams
)
    BEGIN {
        if(-not $SRxEnv.RemoteUtilities.$ToolName){
            throw [System.NullReferenceException] "RemoteUtilities configuration for '$ToolName' not found in `$SRxEnv"
        }

        # to be tricky like Brian
        $HasDebugFlag = ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent -or $global:SRxEnv.Log.Level -eq "Debug")

        $startTime = Get-Date

        # job list
        $jobList = New-Object System.Collections.ArrayList

        # if utf 8 is enabled, it will put a BOM on the script block input for Start-Job and break it
        # this is not a problem with the ISE, check our host name
	    if ($Host.Name -eq "ConsoleHost") {
            if([system.console]::InputEncoding -is [Text.UTF8Encoding]){
		        [system.console]::InputEncoding= New-Object Text.UTF8Encoding $false
            }
        }
        $jobGUID = [guid]::NewGuid()
        $destPath = New-Item -Path (Join-Path $global:SRxEnv.Paths.Tmp $jobGUID) -type directory -Force
        Write-SRx INFO "[Invoke-SRxRemoteTool][$ToolName] Invoking command with JobId: $($jobGUID)" -ForegroundColor Cyan

        $ToolPath = GetToolPath -ToolName $ToolName
    }
    PROCESS{
        if (-not $TargetServer.canPing()) {
            Write-SRx ERROR "[Invoke-SRxRemoteTool][$ToolName] Unable to ping $($TargetServer.Name)"
        } elseif (IsEnabledRemoteTool -Tool $ToolName -TargetServer $TargetServer) {
            $jobBlock = {
                param([string]$ToolName,[string]$ToolPath,[string]$TargetServerName,[string]$ToolNameExe,[string]$jobGUID,[string]$destPath,[string]$cmdBlock,[Hashtable]$inParams,[Object[]]$outParams,[bool]$HasDebugFlag)

                $logfile = Join-Path $destPath "job-$TargetServerName-debug.log"
			    if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Entered Job block." | Add-Content -Path $logfile }

                $cmdBlock2 = {
                    param([string]$varpath,[string]$guid,[bool]$debug)
                    $zipfile = Join-Path $varpath "$($env:COMPUTERNAME)-$guid.zip"
                    $outpath = Join-Path $varpath $guid
                    if($debug) {
                        $logfile = Join-Path $varPath "$guid.log"
        			    "Creating zip file $zipfile from $outpath" | Add-Content -Path $logfile
                    }
                    Add-Type -Assembly System.IO.Compression.FileSystem
                    $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
                    [System.IO.Compression.ZipFile]::CreateFromDirectory($outpath, $zipfile, $compressionLevel, $false)
                }

                $cmdBlock3 = {
                    param([string]$varpath,[string]$guid,[bool]$debug)
                    $zipfile = Join-Path $varpath "$($env:COMPUTERNAME)-$guid.zip"
                    if (-not $debug) {
                        $outpath = Join-Path $varpath $guid
                        Remove-Item $outpath -Recurse -Confirm:$false -Force
                        Remove-Item $zipfile -Confirm:$false -Force
                    } 
                }


                try{
                    $binPath = Join-Path $ToolPath "bin"
                    $exefile = Join-Path $binPath $ToolNameExe
                    $varPath = Join-Path $ToolPath "var"
                    $outpath = Join-Path $varpath $jobGUID
                    $zipfile = Join-Path $varpath "$($TargetServerName)-$jobGUID.zip"
                    $zipPath = (Join-Path "\\$($TargetServerName)" $zipfile).Replace(':','$')

					if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Invoking command on $($TargetServerName)..." | Add-Content -Path $logfile }
					if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Invoking command block: $cmdBlock" | Add-Content -Path $logfile }
                    $cmdBlock1 = [Scriptblock]::Create($cmdBlock)

                    if ($TargetServerName -eq $ENV:ComputerName) {
                        $job1Obj = Invoke-Command -ScriptBlock $cmdBlock1 -ArgumentList($TargetServerName,$ToolName,$exefile,$varpath,$jobGUID,$inParams,$outParams,$HasDebugFlag) 
                        
					    if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Compressing files on $($TargetServerName)..." | Add-Content -Path $logfile }
                        $job2Obj = Invoke-Command -ScriptBlock $cmdBlock2 -ArgumentList($varPath,$jobGUID,$HasDebugFlag) 

					    if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Copying files from $($TargetServerName)..." | Add-Content -Path $logfile }
                        Copy-Item -Path $zipPath -Destination $destPath

					    if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Done copying files from $($TargetServerName)." | Add-Content -Path $logfile }
                        if(-not $HasDebugFlag) {
                            #clean up files on remote servers
                            $job3Obj = Invoke-Command -ScriptBlock $cmdBlock3 -ArgumentList($varPath,$jobGUID,$HasDebugFlag) 
                        }
                    } else {
                        try{
                            $job1Obj = Invoke-Command -ComputerName $TargetServerName -ScriptBlock $cmdBlock1 -ArgumentList($TargetServerName,$ToolName,$exefile,$varpath,$jobGUID,$inParams,$outParams,$HasDebugFlag)  -ErrorAction Stop
                            
					        if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Compressing files on $($TargetServerName)..." | Add-Content -Path $logfile }
                            $job2Obj = Invoke-Command -ComputerName $TargetServerName -ScriptBlock $cmdBlock2 -ArgumentList($varPath,$jobGUID,$HasDebugFlag) 

					        if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Copying files from $($TargetServerName)..." | Add-Content -Path $logfile }
                            Copy-Item -Path $zipPath -Destination $destPath

                            if(-not $HasDebugFlag) {
                                $job3Obj = Invoke-Command -ComputerName $TargetServerName -ScriptBlock $cmdBlock3 -ArgumentList($varPath,$jobGUID,$HasDebugFlag)
                            } else {
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Did not clean up working files on $($TargetServerName)" | Add-Content -Path $logfile }
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Files:" | Add-Content -Path $logfile }
						        $tPath = Join-Path "\\$($TargetServerName)" (Join-Path $varpath $jobGUID)
						        $tPath = $tPath.Replace(":","$")
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool]    $tPath"  | Add-Content -Path $logfile }
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool]    $zipPath" | Add-Content -Path $logfile }
                            }
					        if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Done copying files from $($TargetServerName)." | Add-Content -Path $logfile }
                        } catch {
                            if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Caught exception.  Attemption command with Kerberos authentication..." | Add-Content -Path $logfile }

                            # connect to the computer from client using kerberos as the current user:
                            $job1Obj = Invoke-Command -ComputerName $TargetServerName -ScriptBlock $cmdBlock1 -ArgumentList($TargetServerName,$ToolName,$exefile,$varpath,$jobGUID,$inParams,$outParams,$HasDebugFlag) -Authentication NegotiateWithImplicitCredential

					        if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Compressing files on $($TargetServerName)..." | Add-Content -Path $logfile }
                            $job2Obj = Invoke-Command -ComputerName $TargetServerName -ScriptBlock $cmdBlock2 -ArgumentList($varPath,$jobGUID,$HasDebugFlag) -Authentication NegotiateWithImplicitCredential

					        if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Copying files from $($TargetServerName)..." | Add-Content -Path $logfile }
                            Copy-Item -Path $zipPath -Destination $destPath

                            if(-not $HasDebugFlag) {
                                $job3Obj = Invoke-Command -ComputerName $TargetServerName -ScriptBlock $cmdBlock3 -ArgumentList($varPath,$jobGUID,$HasDebugFlag) -Authentication NegotiateWithImplicitCredential
                            } else {
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Did not clean up working files on $($TargetServerName)" | Add-Content -Path $logfile }
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Files:" | Add-Content -Path $logfile }
						        $tPath = Join-Path "\\$($TargetServerName)" (Join-Path $varpath $jobGUID)
						        $tPath = $tPath.Replace(":","$")
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool]    $tPath"  | Add-Content -Path $logfile }
                                if($HasDebugFlag){ "[Invoke-SRxRemoteTool]    $zipPath" | Add-Content -Path $logfile }
                            }
					        if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Done copying files from $($TargetServerName)." | Add-Content -Path $logfile }

                        }
                    }

                    if($HasDebugFlag){ "[Invoke-SRxRemoteTool] Completed invoked $ToolName command on $($TargetServerName) with job id $($jobGUID)." | Add-Content -Path $logfile }

                } catch {
                    $errorfile = Join-Path $destPath "error.log"
                    "[Invoke-SRxRemoteTool] Caught exception while invoking $ToolName command on $($TargetServer.Name)" | Add-Content -Path $errorfile
                    "Exception:" | Add-Content -Path $errorfile 
                    "$_" | Add-Content -Path $errorfile 
                }
            }

            Write-SRx INFO "[Invoke-SRxRemoteTool][$ToolName] Invoking tool on $($TargetServer.Name)."
            if($HasDebugFlag) {Write-Host "Creating debug file in $destPath"}
            try {
                    $job = Start-Job -Name $TargetServer.Name -ScriptBlock $jobBlock -ArgumentList $($ToolName,$ToolPath,$TargetServer.Name,$global:SRxEnv.RemoteUtilities.$ToolName.Exe,$jobGUID,$destPath,$CmdBlock.ToString(),$InputParams,$OutputParams,$HasDebugFlag)
#                    $job = Start-Job -Name $TargetServer.Name -ScriptBlock $jobBlock -ArgumentList $($jobGUID,$destPath,$InputParams,$HasDebugFlag)
                    $jobList.Add($job) | Out-Null
            } catch {
                Write-SRx ERROR "[Invoke-SRxRemoteTool][$ToolName] Caught exception when starting job."
                Write-SRx ERROR "$job"
                Write-SRx ERROR "[Invoke-SRxRemoteTool][$ToolName] Exception:"
                Write-SRx ERROR "$_"
            }
        } else {
            Write-SRx ERROR "[Invoke-SRxRemoteTool][$ToolName] Unable to invoke tool. The Remote Utility '$ToolName' is not enabled."
        }
    }
    END {
        WaitForJobs -Jobs $jobList

        Write-SRx VERBOSE "[Invoke-SRxRemoteTool][$ToolName] Done collecting data. Extracting..." 
        Add-Type -Assembly System.IO.Compression.FileSystem
        $zipfiles = Get-ChildItem $destPath -Filter "*.zip"
        foreach($f in $zipfiles) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($f.FullName, $destPath)
            if(-not $HasDebugFlag) {
                $f.Delete()
            }
        }

#        $files = Get-ChildItem $destPath -Filter "$ToolName-*.log"
        $files = Get-ChildItem $destPath 
        $sum = $files | Measure-Object -Property Length -Sum
        $t = $(Get-Date) - $startTime
        if($sum.Sum -gt 1GB) {
            $size = "$("{0:N2}" -f ($sum.Sum/1GB)) GB"
        } elseif($sum.Sum -gt 1MB) { 
            $size = "$("{0:N2}" -f ($sum.Sum/1MB)) MB"
        } else{ 
            $size = "$("{0:N2}" -f ($sum.Sum/1KB)) KB"
        }
        Write-SRx INFO "[Invoke-SRxRemoteTool][$ToolName] Collected $($files.Count) files totaling $size in $("{0:N2}" -f $t.TotalMinutes) minutes." -ForegroundColor DarkGray


        # if this is a console (not ISE) reset input encoding back to utf8
        # if utf 8 is enabled, it will put a BOM on the script block input for Start-Job and break it
	    if ($Host.Name -eq "ConsoleHost") {
            if([system.console]::InputEncoding -isnot [Text.UTF8Encoding]) {
                [system.console]::InputEncoding=[System.Text.Encoding]::UTF8
            }
        }

        return $files
    }
}

Function WaitForJobs
{
    param(
        [parameter(Mandatory=$true)]
	    [Object[]]$Jobs,
        [switch]$DoNotRemoveJobs
    )

    if($Jobs.Count -eq 0) {
        Write-SRx VERBOSE "[Invoke-SRxRemoteTool][$ToolName] No Jobs found." 
        return
    } else {
        Write-SRx VERBOSE "[Invoke-SRxRemoteTool][$ToolName] Waiting for Jobs..." 
    }

    Write-SRx INFO "[Invoke-SRxRemoteTool][$ToolName] Created $($jobs.Count) Jobs to collect data. Waiting..." -ForegroundColor Cyan 

    $done = $false
    while(-not $done)
    {
        $completed = $jobs | ? { $_.State -eq "Completed" -or $_.State -eq "Failed" } 
        $count = $completed.Count
        $p = [System.Convert]::ToInt32(($count/$($jobs.Count) * 100))
        Write-Progress -Id 2 -Activity "Waiting for remote jobs..." -Status "[$ToolName] - $count of $($jobs.Count) jobs complete"  -PercentComplete $p
        Start-Sleep -Seconds 1
        if($count -ge $jobs.Count){$done = $true}
    }
    Write-Progress -Id 2 -Activity "Waiting for remote jobs..." -Completed

    $failedJobs = $jobs | ? { $_.State -eq "Failed" } 
    $failedJobs | % { Write-SRx WARNING "[Invoke-SRxRemoteTool][$ToolName] Job failed on server $($_.Name)"; if($HasDebugFlag){Write-SRx ERROR "$(Receive-Job $_)" }}
    if($failedJobs.Count -eq 0) {
        Write-SRx INFO "[Invoke-SRxRemoteTool][$ToolName] All Jobs completed successfully." -ForegroundColor Green
    }
    if(-not $DoNotRemoveJobs){
        Write-SRx INFO " * [Invoke-SRxRemoteTool][$ToolName] Keeping jobs." -ForegroundColor DarkGray
        $jobs | Remove-Job
    }
}


function Remove-SRxRemoteTool 
{
<#
.SYNOPSIS

.DESCRIPTION

.INPUTS
	
.NOTES

#>
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true,ValueFromPipeline=$true)]
    $TargetServer,
    [parameter(Mandatory=$true)]
    $ToolName
)
}

function Invoke-SRxRemotePowerShellJobs
{
    [CmdletBinding()]
    param ( 
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        $TargetServer,
        [parameter(Mandatory=$true)]
        $Cmdlet
    )
    BEGIN {
        # to be tricky like Brian
        $HasDebugFlag = ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent -or $global:SRxEnv.Log.Level -eq "Debug")

        $ToolName = $Cmdlet
        Write-SRx INFO "[Invoke-SRxRemotePowerShellJobs][$ToolName] Invoking commands" -ForegroundColor Cyan

        $startTime = Get-Date

        # job list
        $jobList = New-Object System.Collections.ArrayList

        # if utf 8 is enabled, it will put a BOM on the script block input for Start-Job and break it
        # this is not a problem with the ISE, check our host name
	    if ($Host.Name -eq "ConsoleHost") {
            if([system.console]::InputEncoding -is [Text.UTF8Encoding]){
		        [system.console]::InputEncoding= New-Object Text.UTF8Encoding $false
            }
        }
    }
    PROCESS {
        if (-not $TargetServer.canPing()) {
            Write-SRx ERROR "[Invoke-SRxRemotePowerShellJobs][$ToolName] Unable to ping $($TargetServer.Name)"
        } else {
            Write-SRx INFO "[Invoke-SRxRemotePowerShellJobs][$ToolName] Invoking command on $($TargetServer.Name)."
            if($TargetServer.Name -eq $env:COMPUTERNAME){
                $job = Start-Job -ScriptBlock {param($cmd); . $cmd} -ArgumentList ($Cmdlet) -Name $TargetServer.Name;
                $jobList.Add($job) | Out-Null
            } else {
                $job = Invoke-Command -ComputerName $TargetServer.Name -ScriptBlock {param($cmd);. $cmd} -ArgumentList ($Cmdlet) -AsJob -JobName $TargetServer.Name
                $jobList.Add($job) | Out-Null
            }
        }
    }
    END {
        WaitForJobs -Jobs $jobList -DoNotRemoveJobs

        $jobData = $jobList | % { New-Object PSObject -Property @{
            Name = $_.Name;
            Data = Receive-Job -Job $_ ;
        } }
        $jobList | Remove-Job | Out-Null

        $t = $(Get-Date) - $startTime
        Write-SRx INFO "[Invoke-SRxRemotePowerShellJobs][$ToolName] Ran commands on $($jobList.Count) servers in $("{0:N2}" -f $t.TotalMinutes) minutes." -ForegroundColor DarkGray

        # if this is a console (not ISE) reset input encoding back to utf8
        # if utf 8 is enabled, it will put a BOM on the script block input for Start-Job and break it
	    if ($Host.Name -eq "ConsoleHost") {
            if([system.console]::InputEncoding -isnot [Text.UTF8Encoding]) {
                [system.console]::InputEncoding=[System.Text.Encoding]::UTF8
            }
        }

        return $jobData
    }
}


Export-ModuleMember Invoke-SRxRemoteTool
Export-ModuleMember Enable-SRxRemoteTool
Export-ModuleMember Remove-SRxRemoteTool
Export-ModuleMember Invoke-SRxRemotePowerShellJobs

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAAn0YkzW21Jn7F
# M6T2qWWtnVH9wD9XNPFDh0Iw+byJOqCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEINdA0+wlAhWHktDblHCkmcKBGypnYpI8owunroxa5QWoMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAJe+x7yF3SREbp2CIQSaIzAV
# j0raEJVDP3wN8/EGbOyC03O4VvhSkZYzFFI7+/T8K8saaPDIpEuKL5WKS9oGp5Ch
# 5wTOqo3lb2gYZ4dhI09ruwb8N3RU7WriAsyn+2lYVH9MZ68h37EUVsEK7bNnbZW5
# SCcHxwzgsyBCAYURw60dUMGzFHYTuQoUhH1t0MAKzW1oUpC5qGaDCTWJ2FIKRx0e
# YQJCdF1YFbM0r59WEy5EKyG+piRk2gKtbNuDaPIb0RA156Xkb+3XI1avBVQaVFQt
# Ll534iFEIpnP2w24xxvepaYYm2d9nRH8JqJls659qPBOAjPrZh/xZ28uyaS5jxOh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgg2FpO0NwDx9HMMWgeseN
# +QKRy0VpIni0PFODDQ9MKRMCBljVRUm9hhgTMjAxNzA0MjYyMzUzNTguMTk2WjAH
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
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEILO4Owhp5vxrB6b6
# 9TaqqHu5OyGJh+shaGGbCSC3OL9iMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUNeSj+04//yYNcfVtXhJ7kZY4po0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAKPvHyIggWPcpQAAAAAAozAWBBR789E1ZbhfhAf/
# f93iigE5Mjb/ajANBgkqhkiG9w0BAQsFAASCAQBHzLEbOCyPWK9F6CBv8vm+XJ3l
# oUrjONguc4wtHKxipKKi2HhQvh8xjx0BXWv8Xw3sGmAtkm7vVLy6AxNiEWKSXTcs
# HRZCrpANx6MWfMO0pRulwvTjKv++VNULaUMOEjg1loXlnr6UQLrHWH9TpKprL7B6
# +LnMfG0RjeMKLNF6dJetlgo76BIl90QR7Rt2jKMHu/PQjN5sMmAyQP7sjc73RWOs
# SgmDi/xqX1ZDGzsQy3pkS0cuLGQv52uUAXk6syUNX+onexSfd+DspJ2NksaPZZnw
# BlCrybYRbXoEKo6HX4rBa3duxSJ2KhhK1ejwo53ub5AX9gBqZ0WwZ7Ycq26M
# SIG # End signature block
