function Enable-SRxULSLogParser
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
	if($global:SRxEnv.RemoteUtilities.LogParser.Initialized)
	{
        Write-SRx WARNING "Log Parser has already been initialized."

		$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Reinitialize."
		$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Do not reinitialize."
		$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        Write-Host "The Log Parser tool has already been initialized." -BackgroundColor DarkCyan -ForegroundColor White
		$title = "" 
		$message = "Do you want to reinitialize the tool?"
		$result = $host.ui.PromptForChoice($title, $message, $options, 1)
		switch ($result) 
		{
			0 { Write-Host "Yes";}
			1 { Write-Host "No"; return }
		}
        $global:SRxEnv.PersistCustomProperty("RemoteUtilities.LogParser", $null)
    }

    if(GetLogParser) 
    {
        # copy log parser to servers
        # todo: enable for custom objects
        $results = $xSSA._Servers | Enable-SRxRemoteTool -ToolName "LogParser" -ToolExe "LogParser.exe" -ToolSupportFiles @("LogParser.dll","ULS-Headers.tsv") 
    }
}
Export-ModuleMember Enable-SRxULSLogParser

function GetLogParser
{
    $downloadScript = Join-Path ($SRxEnv.Paths.Scripts) "downloadRemoteUtilities.ps1"
    $resolvedDownloadScript = $global:SRxEnv.ResolvePath($downloadScript)
    if ($resolvedDownloadScript -and (Test-Path $resolvedDownloadScript)) 
    {
        $global:SRxEnv.UpdateShellTitle("(Running downloadRemoteUtilities.ps1 script...)")
        #if exists, run a custom post init script here
        $destFolder = $global:SRxEnv.Paths.Tools
        #.\downloadRemoteUtilities.ps1 -Tool LogParser -DestinationFolder ..\Tools
        $result = . $resolvedDownloadScript -Tool LogParser -DestinationFolder $destFolder #run this script in local scope
        if($result)
        {
            Write-SRx INFO "Success" -ForegroundColor Green
        }
        else
        {
            Write-SRx ERROR "Unable to download LogParser.msi."
            Write-SRx ERROR "If this server does not have internet access, try running '$resolvedDownloadScript' from your desktop"
            Write-SRx ERROR "and copying LogParser.msi to the '$destFolder'."
        }
        $global:SRxEnv.UpdateShellTitle()
        return $result
    }
    else
    {
         Write-SRx ERROR "Unable to resolve path to '$downloadScript'."
         Write-SRx ERROR "Unable to download LogParser.msi."
    }
    return $false
}



function Invoke-SRxULSLogParser
{
[CmdletBinding()]
param ( 
    [parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
    $TargetServer,
    [parameter(Mandatory=$true)]
	[Object[]]$OutputParams,
    [parameter(Mandatory=$true)]
	$Filter,
    [parameter(Mandatory=$true)]
	[int]$HoursBack,
	$EndTime
)
BEGIN {
    $TargetServers = New-Object Collections.ArrayList
    if([string]::IsNullOrEmpty($EndTime)) {
        $EndTime = Get-Date
    } elseif($EndTime -is [string]) {
        $EndTime = Get-Date $EndTime
    } 
    $HasDebugFlag = ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent -or $global:SRxEnv.Log.Level -eq "Debug")

}
PROCESS{
    $TargetServers.Add($TargetServer) | Out-Null
}
END{

    $cmdBlock = {
        param([string]$servername,[string]$toolname,[string]$exefile,[string]$varpath,[string]$guid,[Hashtable]$inParams,[Object[]]$outParams,[bool]$debug)

		$headerFile = Join-Path (Split-Path -Path $exefile) "ULS-Headers.tsv"
        $outpath = Join-Path $varpath $guid
        if(-not(Test-Path $outpath)){New-Item $outpath -ItemType Directory | Out-Null}
        $outfile = Join-Path $outpath $toolname-$($env:COMPUTERNAME).log
        $files = Get-ChildItem $inParams.ulsPath -Filter "$($env:COMPUTERNAME)*.log" | ? {$_.LastWriteTime -gt ($inParams.Endtime).AddHours(-$inParams.Hoursback) -and $_.LastWriteTime -le $inParams.Endtime}

        #$select = "SELECT $($outParams -join ',') INTO $outfile FROM $($files.FullName -join ",") WHERE $($inParams.filter)"
        $select = "SELECT $($outParams -join ',') INTO $outfile FROM " + $($($files | % {"'$($_.FullName)'"}) -join ",") + " WHERE $($inParams.filter)"
        

		if($debug){
			$logfile = Join-Path $varPath "$guid.log"
			$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
			$currentUser.Name | Add-Content -Path $logfile
			$isBuiltinAdmin = $([Security.Principal.WindowsPrincipal] $currentUser).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
			"Is Admin = $isBuiltinAdmin" | Add-Content -Path $logfile
            "Header file = $headerFile" | Add-Content -Path $logfile
            "File filter = `$_.LastWriteTime -gt $(($inParams.Endtime).AddHours(-$inParams.Hoursback)) -and `$_.LastWriteTime -le $($inParams.Endtime)" | Add-Content -Path $logfile
            "Select statement: $select" | Add-Content -Path $logfile
            "Found $($files.Count) files" | Add-Content -Path $logfile
		}

        $output = .$exefile $select -i:tsv -o:tsv -oCodepage:-1 -iCodepage:65001 -fixedSep:ON -iHeaderFile:"$headerFile" -headerRow:ON -nSkipLines:1 
            
		if($debug){
            "Output:" | Add-Content -Path $logfile
            "$output" | Add-Content -Path $logfile
		}
	}

    $inputParams = @{
        HoursBack = $hoursBack;
        EndTime = $EndTime;
        Filter = $Filter;
        UlsPath = [Environment]::ExpandEnvironmentVariables((Get-SPDiagnosticConfig).LogLocation)
    }

    $OutputParams = @("Timestamp","Message") 

    if($HasDebugFlag) {
        $files = $TargetServers | Invoke-SRxRemoteTool -ToolName LogParser -CmdBlock $cmdBlock -InputParams $InputParams -OutputParams $OutputParams -Debug
    } else {
        $files = $TargetServers | Invoke-SRxRemoteTool -ToolName LogParser -CmdBlock $cmdBlock -InputParams $InputParams -OutputParams $OutputParams
    }
    return $files
}
}
Export-ModuleMember Invoke-SRxULSLogParser



# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAae6jLcke/gDE7
# mst6fGbMWsSczJv7oc0dpWrQdYtVoaCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIClMXA7+LwF5tlM1UGqCGun8vlBLfAJdU9gnvGmfxlzcMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAH3NmtUyQ7Tz9r43P4HWBjtq
# Cing/jwAg2rCiqborul7jvJdCk3uUjN4qV3xDswsQjAQSJ+YDASJvGMNtGWyJylC
# Opyz9lZvaKcZg5nfcFPvzbUnGbIfBunCbRN/9nlHCFos3jxcM2jhOzWANu/ym1W/
# KPcQadpxqsQkVF/3jEOe9HwrY/r9I6iekdiZdnDWf3e0pZWFqZWLf/rkTusVltQ7
# s0gZMxDJAPjCM+r43E9B/hHva+xip+GX0afE0hR7uK89KGJSbQnGLTzl/F0BqHc2
# wQeHmXafX+6z29bMhjKHQlxnSzF2krlWDZx4gI444sCBks0NJXQoZ1bBf9hNXo+h
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgk3PkPfRneWX5/pR3dddm
# r0Lqk1GD3zCah4z7FD6cUScCBljVRqE9hRgTMjAxNzA0MjYyMzUzNTguMDU4WjAH
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
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIJRKfFmVVT9KtPxi
# EfAcxHeiLeGLPsuFfRwj3/lxIG3PMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUvIT7nVsS2sc2hTuIZp6jFhjVzBwwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAALCG6ZIgCl3q+AAAAAAAsDAWBBRnsOQFab38m9PY
# MldGBT0kLsOaSTANBgkqhkiG9w0BAQsFAASCAQDbR0JkYxTjSpMXyUJAlIR/eu07
# OYaavoWakpF/ALkIpUsQy+zdI0oWurrPqQ2gXgboaQDVMom1fR4SbuChjN0G4cr9
# swk479tl65HClEIpRDH2POe5RsmcUgJTFaHAQMWQiCL7gDSIZdF8Fuw2ihU634KL
# HjiDkaop1e6HEO6kxKg6tcfh0Cn4G3nuDffUZWizGzHA6+JCEpQLSWdA/hLgwJxd
# +fNPzlH/MHucHzpdhojvPTmdBmrnucZOFuw9d7e2yg+gmJK+j10P43laxpWF+v5G
# IQc2F5gwYqO3xMDzAsvSqcB9Eq33nm7fARyoizj/akC+L0bqZag5kSlIU7SV
# SIG # End signature block
