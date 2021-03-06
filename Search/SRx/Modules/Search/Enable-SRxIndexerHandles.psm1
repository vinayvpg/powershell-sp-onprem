function Enable-SRxIndexerHandles
{ 
<#
.SYNOPSIS 
	synopsis
	
.DESCRIPTION 
	description
		
.NOTES
	=========================================
	Project		: Search Health Reports (SRx)
	-----------------------------------------
	File Name 	: Module-Name.psm1

	Requires	: 
		PowerShell Version 3.0, Search Health Reports (SRx), Microsoft.SharePoint.PowerShell, 
        Patterns and Practices v15 PowerShell

        /*************************************************************
        *                                                            *
        *   Copyright (C) Microsoft Corporation. All rights reserved.*
        *                                                            *
        *************************************************************/	
	
.INPUTS
    input1

.EXAMPLE
	Module-Name

#>

	[CmdletBinding()]
	param ( 
	)

    $ServerVersion = [System.Environment]::OSVersion.Version
    if ($ServerVersion.Major -eq 6 -and $ServerVersion.Minor -lt 2) {
	    Write-Warning "[initSRx] This server is running a server version prior to Windows 2012."
	    Write-Warning "[initSRx] SRxIndexerHandles may not install correctly on older server versions without manual intervention."
    }

	if($global:SRxEnv.RemoteUtilities.Handle.Initialized)
	{
        Write-SRx WARNING "Handle.exe has already been initialized."

		$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Reinitialize."
		$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Do not reinitialize."
		$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        Write-Host "The Handle.exe tool has already been initialized." -BackgroundColor DarkCyan -ForegroundColor White
		$title = "" 
		$message = "Do you want to reinitialize the tool?"
		$result = $host.ui.PromptForChoice($title, $message, $options, 1)
		switch ($result) 
		{
			0 { Write-Host "Yes";}
			1 { Write-Host "No"; return }
		}
        $global:SRxEnv.PersistCustomProperty("RemoteUtilities.Handle", $null)
    }
    # download utility
    if(GetHandleExe) 
    {
        # copy utility to servers
        # todo: enable for custom objects
        $results = $xSSA._Servers | Enable-SRxRemoteTool -ToolName "Handle" -ToolExe "handle.exe" -ToolSupportFiles @() 
    }
}
Export-ModuleMember Enable-SRxIndexerHandles

function GetHandleExe
{
    $downloadScript = Join-Path ($SRxEnv.Paths.Scripts) "downloadRemoteUtilities.ps1"
    $resolvedDownloadScript = $global:SRxEnv.ResolvePath($downloadScript)
    if ($resolvedDownloadScript -and (Test-Path $resolvedDownloadScript)) 
    {
        $global:SRxEnv.UpdateShellTitle("(Running downloadRemoteUtilities.ps1 script...)")
        #if exists, run a custom post init script here
        $destFolder = $global:SRxEnv.Paths.Tools
        #.\downloadRemoteUtilities.ps1 -Tool LogParser -DestinationFolder ..\Tools
        $result = . $resolvedDownloadScript -Tool Handle -DestinationFolder $destFolder #run this script in local scope
        if($result)
        {
            Write-SRx INFO "Success" -ForegroundColor Green
        }
        else
        {
            Write-SRx ERROR "Unable to download Handle.zip."
            Write-SRx ERROR "If this server does not have internet access, try running '$resolvedDownloadScript' from your desktop."
        }
        $global:SRxEnv.UpdateShellTitle()
        return $result
    }
    else
    {
         Write-SRx ERROR "Unable to resolve path to '$downloadScript'."
         Write-SRx ERROR "Unable to download Handle.zip."
    }
    return $false
}


function Invoke-SRxIndexerHandles
{
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
    $TargetServer,
	[int]$MaxRunTimeSecs=60,
    $DataDir=$null
)
BEGIN {
    $TargetServers = New-Object Collections.ArrayList
    $HasDebugFlag = ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent -or $global:SRxEnv.Log.Level -eq "Debug")
    if(([string]::IsNullOrEmpty($DataDir)) -and (-not $xSSA._hasSRxIndexDiskReport)){
        Write-SRx INFO "Need to build SRx Index Disk Report.  Running _BuildDiskReportData() for each Indexer..."
        $xSSA._GetIndexServerReport() | Out-Null
    }

    # exclude processes
    $excludes = @("Nthandle" `
                ,"Handle" `
                ,"Copyright" `
                ,"Sysinternals" `
                ,"System" `
                ,"noderunner.exe" `
                ,"hostcontrollerservice.exe" `
        )          
    $excludes = New-Object Collections.ArrayList(,$excludes)

    $excludesFilePath = $(Join-Path $($global:SRxEnv.Paths.Config) "FileHandleExcludeFilter.csv")
    if(Test-Path($excludesFilePath))
    {
        $excludeFilter = Import-Csv $excludesFilePath
        foreach($e in $excludeFilter)
        {
            $excludes.Add($e.ProcessName) | Out-Null
        }
    }
}
PROCESS{
    if($TargetServer.hasIndexer){
        $TargetServers.Add($TargetServer) | Out-Null
    }
}
END{
    $cmdBlock = {
        param([string]$servername,[string]$toolname,[string]$exefile,[string]$varpath,[string]$guid,[Hashtable]$inParams,[Object[]]$outParams,[bool]$debug)
		if($debug){
			$logfile = Join-Path $varPath "$guid.log"
            "Entered SRxIndexerHandles cmdBlock." | Add-Content -Path $logfile
            "servername=$servername`n toolname=$toolname`n exefile=$exefile`n varpath=$varpath`n guid=$guid`n debug=$debug`n " | Add-Content -Path $logfile
        }
        $outpath = Join-Path $varpath $guid
        if(-not(Test-Path $outpath)){New-Item $outpath -ItemType Directory | Out-Null}
        $outfileTmpl = Join-Path $outpath "IndexerHandles.{0}.{1}.out"

		if($debug){
			$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
			"Current user: $($currentUser.Name)" | Add-Content -Path $logfile
			$isBuiltinAdmin = $([Security.Principal.WindowsPrincipal] $currentUser).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
			"Is Admin = $isBuiltinAdmin" | Add-Content -Path $logfile
            "Writing to file template '$outfileTmpl'" | Add-Content -Path $logfile
            "Will run no more than $($inParams.TTL_Secs) seconds" | Add-Content -Path $logfile
		}

        foreach($path in $inParams.Paths){
            if(-not $inParams.$path.Contains($servername)){
		        if($debug){
                    "Skipping path='$path' for server $servername" | Add-Content -Path $logfile
		        }
                continue
            }
            $outfile = $outfileTmpl -f ($servername,$path.Replace([System.IO.Path]::DirectorySeparatorChar,"_").Replace(" ","_").Replace(":","_"))
		    if($debug){
                "Gather handles from '$path'" | Add-Content -Path $logfile
                "Write output to '$outfile'" | Add-Content -Path $logfile
                "Run command '. $exefile -nobanner -accepteula $path'" | Add-Content -Path $logfile
		    }
            $startTime = Get-Date
            # while we have not exceeded the max time handle.exe will run
            $count = 0
            do {
                $count+=1
                $output = . $exefile -nobanner -accepteula $path
                $output | Add-Content -Path $outfile
    		    $lifespan = New-TimeSpan $startTime (Get-Date)
		    } while ($lifespan.totalSeconds -le $inParams.TTL_Secs) 

		    if($debug){
			    "Handles ran $count times in $($lifespan.totalSeconds) secs for '$path'" | Add-Content -Path $logfile
		    }
        }
	}

    [Object[]]$OutputParams = @()
    $InputParams = @{
        TTL_Secs = $MaxRunTimeSecs;
        Paths = New-Object Collections.ArrayList
    }

    $TargetServers | %{$sn=$_.Name;$_.Components | ? {$_ -Match "Index"} | % { $xSSA._GetIndexer($_) | % { 
        # DataDir may be passed on cmd line
        if([string]::IsNullOrEmpty($DataDir)) {
            if($global:SRxEnv.h.isUnknownOrNull($_._CellPath)){
                Write-SRx ERROR "Cell path for $($_.Name) on $($_.ServerName) is unknown."
            } else {
                $path = Split-Path $_._CellPath
            }
        } else {
            $path = $DataDir
        }
        if(-not $global:SRxEnv.h.isUnknownOrNull($path)){
            if(-not $InputParams.ContainsKey($path)) {
                $InputParams.Paths.Add($path) | Out-Null
                $InputParams.$($path) = New-Object Collections.ArrayList
            } 
            $InputParams.$($path).Add($sn) | Out-Null
        }
    } } }
    
    if($HasDebugFlag) {
        $files = $TargetServers | Invoke-SRxRemoteTool -ToolName Handle -CmdBlock $cmdBlock -InputParams $InputParams -Debug
    } else {
        $files = $TargetServers | Invoke-SRxRemoteTool -ToolName Handle -CmdBlock $cmdBlock -InputParams $InputParams 
    }

    $processTable = @{}
    foreach($f in ($files | ?{$_.Name -match "IndexerHandles.*.out"})){
        $filename = $f.Name.Split(".")
        $server = $filename[1]
        $lines = Get-Content $f.FullName
        foreach($l in $lines){
            if([string]::IsNullOrEmpty($l)) {
                   continue
            }
            if($l -eq "No matching handles found."){
                if([string]::IsNullOrEmpty($DataDir)){
                    $s = $TargetServers | ? {$_.Name -eq $server} 
                    $path = $s._CellPath
                } else {
                    $path = $DataDir
                }
                Write-SRx Warning ("Did NOT find ANY processes accessing path '{0}' on server {1}. " -f ($path, $server))
                Write-SRx Warning ("Please verify the path is correct and the Index Components are running.")
                break
            }
            $process = $l.Split()
            if($process[0] -in $excludes){
                continue
            }
            else {
                $InputParams.Paths | % {
                    $i = $l.IndexOf("$_")
                    if($i -gt -1) {
                        $path = $l.Substring($i,$l.Length-$i)
                    }
                }
                #Write-SRx ERROR ("Found process {0} on {1} accessing '{2}'. " -f ($process[0],$server,$path))
                if(-not $processTable.ContainsKey($server)){
                    $processTable.$server = @{}
                }
                if(-not $processTable.$server.ContainsKey($process[0])) {
                    $processTable.$server.$($process[0]) = @{}
                }
                if(-not $processTable.$server.ContainsKey($process[0]).$path) {
                    $processTable.$server.$($process[0]).$path = 0
                }

                $processTable.$server.$($process[0]).$path += 1
            }
        }
    }

    foreach($server in $processTable.Keys){
        Write-SRx ERROR ("Found processes accessing the data index directory on server {0}. " -f ($server))
        foreach($process in $processTable.$server.Keys){
            Write-SRx ERROR (">> Found process '{0}' accessing {1} files and folders. " -f ($process,$processTable.$server.$process.Keys.Count))
        }
    }

    if($processTable.Count -gt 0) {
        return $processTable
    } else {
        return $null
    }
}
}
Export-ModuleMember Invoke-SRxIndexerHandles



# SIG # Begin signature block
# MIIkuAYJKoZIhvcNAQcCoIIkqTCCJKUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCHFsjSVDKVnzy4
# Y6HE7AxB7Y4QcSXm5/wqpfI6Tk89R6CCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# ezCCFncCAQEwgZUwfjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAA
# AI6HkaRXGl/KPgAAAAAAjjANBglghkgBZQMEAgEFAKCCAWkwGQYJKoZIhvcNAQkD
# MQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJ
# KoZIhvcNAQkEMSIEIJ3MlZIIFeOIHrtBcVE1tGl8H11UiS4zymGKz5855cGKMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAEAdVPM9vySnl7/zsIy03aL3
# eaMPTlO3807jAF+CmDDWqILU+Qr2Yi4OCUhTCYJfk2VqDkw+QtmoMe1RTNLI5Dge
# y+Nhw++TCHxStCHZCj3OVLl1koctrQv85a3MesnlR5XO3dLs0UjrNm92DjyNZd8m
# ICueeaxwZm8bqft3uhSE8eR10D1x+eCB0bdFKfi1VlsS0dHqpZmDszeUNfVP5h3y
# LOOR9rNoO4mmhMFPjnh79P4gsqsww8ftKWpN8ZSobtSnl4lISfFUKGwkEDAzoy3E
# bGqMB61tIowBXHsE5h1LYCOQFv6AoO0gclEDpSrPtWrbGDE4h+Ikj/xLcnSodiih
# ghNJMIITRQYKKwYBBAGCNwMDATGCEzUwghMxBgkqhkiG9w0BBwKgghMiMIITHgIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPAYLKoZIhvcNAQkQAQSgggErBIIBJzCCASMC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgFy97rVg1L9KTktvSfOAs
# R5KLFjdGgvqXSGx9NvIT6bkCBljVRnmbahgSMjAxNzA0MjYyMzU0MDQuMjZaMAcC
# AQGAAgH0oIG5pIG2MIGzMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046QjhF
# Qy0zMEE0LTcxNDQxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2Wggg7NMIIGcTCCBFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCB
# iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAw
# NzAxMjEzNjU1WhcNMjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6
# IOz8E5f1+n9plGt0VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsa
# lR3OCROOfGEwWbEwRA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8k
# YDJYYEbyWEeGMoQedGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRn
# EnIaIYqvS2SJUGKxXf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWa
# yrGo8noqCjHw2k4GkbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURd
# XhacAQVPIk0CAwEAAaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQW
# BBTVYzpcijGQ80N7fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDCBoAYDVR0gAQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUH
# AgEWMWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVs
# dC5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkA
# XwBTAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN
# 4sbgmD+BcQM9naOhIW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj
# +bzta1RXCCtRgkQS+7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/
# xn/yN31aPxzymXlKkVIArzgPF/UveYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaP
# WSm8tv0E4XCfMkon/VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jns
# GUpxY517IW3DnKOiPPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWA
# myI4ILUl5WTs9/S/fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99
# g/DhO3EJ3110mCIIYdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mB
# y6cJrDm77MbL2IK0cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4S
# KfXAL1QnIffIrE7aKLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYov
# G8chr1m1rtxEPJdQcdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7v
# DaBQNdrvCScc1bN+NR4Iuto229Nfj950iEkSMIIE2jCCA8KgAwIBAgITMwAAAJ9n
# 8rWoIwZbewAAAAAAnzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDAeFw0xNjA5MDcxNzU2NDdaFw0xODA5MDcxNzU2NDdaMIGzMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BS
# MScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046QjhFQy0zMEE0LTcxNDQxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQC5CPEjnN3EAi8ChaGjJ5dk+QOcElQ/U4JauD7rfW4Y
# xXLBJ9VwKQzwlkvWj4THFjlinvuxDSOEouMw99J1UAvT2dDQ7vqSvV1fNzn4xnIR
# ZCszgUXXToabEJMRYDBd0Xy0zVwBKn35zWkXl8LVVJIhhCb1uipgAYscz9GnlFZi
# ejB5yZ5qPkymXaFZe3IOk2OiwqM3vxeq4Tl5ovz91/yt4x7ZgGsS/Trud44w4DuU
# Y8bemRGpnRLBhdklmesB+g5oPRuomT8YMPpozg8EXi+o8Iex9l4bL86BTK0hETMy
# CH9niRgDPQtBkdAWR8kbYte0Ki+U2grlj4zMUyl1+A5ZAgMBAAGjggEbMIIBFzAd
# BgNVHQ4EFgQU/YsbIsN9I0d2ph7f4GbUUum2+aAwHwYDVR0jBBgwFoAU1WM6XIox
# kPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNy
# b3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDct
# MDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5j
# cnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0B
# AQsFAAOCAQEAZRDBbGvPFR6vD0g2698tC7wAAOaRZhpQlmW5MQ9ljKnxdMvH55b4
# G/O+M/LM/EGcwcgpmNYx8h03PfGXpM+y9mOUgDVCGvI8lN+nOuApOX2Oj3vYVANU
# Rv9cz/nqtPNHIVDwhds3s4X8Ls/Tm9KGzuuAcFtBmYGGM9YY7KvgwZEggUVefa8h
# ac4CkcIVhfKrl7Rw6YpoicfnbNlWUsBFZP0EWO6S7lL3nTfD+Qzbi2mkcN6CXLNl
# sYdo1kuU/GNyXr1KNyt1U7Rz4tiAViEpBBu0zpzRFHFFwzBkjnmdu5LjxcypA1W7
# c78BFXqZBq7GdVvtcbg2D0NW9wTBvAu/R6GCA3YwggJeAgEBMIHjoYG5pIG2MIGz
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRN
# T1BSMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046QjhFQy0zMEE0LTcxNDQxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiJQoBATAJBgUrDgMC
# GgUAAxUAbNMnCPL52ajL+RnekktKrdsZo8GggcIwgb+kgbwwgbkxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIxJzAlBgNV
# BAsTHm5DaXBoZXIgTlRTIEVTTjo1N0Y2LUMxRTAtNTU0QzErMCkGA1UEAxMiTWlj
# cm9zb2Z0IFRpbWUgU291cmNlIE1hc3RlciBDbG9jazANBgkqhkiG9w0BAQUFAAIF
# ANyrUCQwIhgPMjAxNzA0MjYxNjU4MTJaGA8yMDE3MDQyNzE2NTgxMlowdDA6Bgor
# BgEEAYRZCgQBMSwwKjAKAgUA3KtQJAIBADAHAgEAAgIiQjAHAgEAAgIYhjAKAgUA
# 3KyhpAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMBoAowCAIBAAID
# FuNgoQowCAIBAAIDB6EgMA0GCSqGSIb3DQEBBQUAA4IBAQAXoskePwjz1ZbFRCdi
# 492S182sqP2YBJAg1IHbfhwVYJF2WAPK8RJKSHgX6ecWSiPLcOUpNoaJYKoNrCJh
# WZi7PLAmbLS6NJoV55ik9ddmInoJpA/CQV+Q1NVsyI8g1FPTZuItxm/zvRE5Cevv
# UEaxFtsYvaQJAtaB1SaA0KVnwDwrSVXl4IwB62C52jeZHRISjAH8n47EN3cXeK8a
# MOHwprIS7zFKXQOicviuXRU2JTUQJ8MctYZmffZtpmaIhAkfyDsDN78EwrbBRS6q
# TC98WmyhV+Q3BnqIGTg6q74jB2+DwdvOSUbVu49mEE3UFcZO6K6lNrIRYN95GFnK
# zERsMYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAACfZ/K1qCMGW3sAAAAAAJ8wDQYJYIZIAWUDBAIBBQCgggEyMBoGCSqGSIb3
# DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgzdwrt+53dphHCA51
# loH+7CwdQPV12mDxiueYkZF9e2EwgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGx
# BBRs0ycI8vnZqMv5Gd6SS0qt2xmjwTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAAAn2fytagjBlt7AAAAAACfMBYEFACV5s7yCUpCjwlK
# Op0J7ZGDwJj/MA0GCSqGSIb3DQEBCwUABIIBAKMXRh660U3MSsFU/Li9KxtgVLSq
# fEM5r+dXAB6/JLqGHWtdSJJFf6fdJfwhxFWRWHOU1qxHNq/mcGpewj5wtU2tHFC+
# G4TczMe3CuKpkaqcRX8sWZLQHK8CQwlTrSNNk4ut8nfgn00oOpxRhPyf0YcxbsuZ
# h6ZJe/SvNn7Q1P2mSOwCFnQxFwieTaCUesxdbvR6Y2tLkY3xTPmdO6vOgPR6feRs
# nB8YGwA223miocCDmj488ZlkFjbwFcPPJbQY6QN1fnGX+rypY4Zq1VtVpwKNc1XJ
# 7Ak8L8tk1wHbPOallyuf2PIsN7lzGwAq7Y2LSP60/CCR13HkK+aOdwQRV3Y=
# SIG # End signature block
