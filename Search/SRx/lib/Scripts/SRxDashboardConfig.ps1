<#
.SYNOPSIS 
    SRx Dashboard Configuration Script
    	
.DESCRIPTION 
	Internal script for bootstrapping the Dashboard configuration
		
.NOTES
	=========================================
	Project		: Search Health Reports (SRx)
	-----------------------------------------
	Requires	: 
		PowerShell Version 3.0, Search Health Reports (SRx), Microsoft.SharePoint.PowerShell,
        SharePoint Search Health (SRx) Dashboard license

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
	
.INPUTS
    input1

.EXAMPLE
	Module-Name

#>
if($global:SRxEnv.Exists) 
{
    Write-SRx VERBOSE $("[Post Init Script] Dashboard Config") -ForegroundColor DarkCyan
    $previousState = ($global:SRxEnv.Dashboard.Initialized)
	$global:SRxEnv.Dashboard.Initialized = $((-not $global:SRxEnv.Dashboard.UpdateHandle) -and 
											($global:SRxEnv.Dashboard.Site -ne $null) -and 
											($global:SRxEnv.Dashboard.Handle -ne $null))

    if (($global:SRxEnv.Dashboard.UpdateHandle -ne $null) -and ($global:SRxEnv.Dashboard.UpdateHandle -is [bool])) 
	{
        $global:SRxEnv.Dashboard.PSObject.Properties.Remove("UpdateHandle")
    }

    $isNowBusted = $( ($previousState) -and ($previousState -ne $global:SRxEnv.Dashboard.Initialized) ) 
    $isNowInitialized = $( ($global:SRxEnv.Dashboard.Initialized) -and ($global:SRxEnv.Dashboard.Initialized -ne $previousState) ) 

    #-- If now busted, persist the Dashboard config to file (assuming the config file is not inaccessible) ---            
	if ($isNowBusted -or $isNowInitialized) 
    { 
		Write-SRx VERBOSE $(" --> Updating the 'initialized' state for the Dashboard")
        $global:SRxEnv.PersistCustomProperty("Dashboard", $( $global:SRxEnv.Dashboard ))
	}
			
    if ($xSSA._hasSRx) 
    {
        if ([string]::isNullOrEmpty($global:SRxEnv.SSA)) 
        {
            Write-SRx VERBOSE $(" --> Setting Default SSA: " + $xSSA.Name) -ForegroundColor Cyan
            $global:SRxEnv.PersistCustomProperty("SSA", $xSSA.Name)
        }
                
        $configuredHandleCount = $( if ($global:SRxEnv.HandleMap -is [Hashtable]) { 1 } 
                                    elseif($global:SRxEnv.HandleMap -is [PSCustomObject]) { 1 } 
                                    else {$global:SRxEnv.HandleMap.count} 
                                    )
        if ($global:___SRxCache.SSASummaryList.count -ne $configuredHandleCount)
        {
            Write-SRx VERBOSE $(" --> " + $(if ($configuredHandleCount -eq 0) {"B"} else {"Reb"}) + " uilding the `$SRxEnv.HandleMap")
            $SRxEnv.h.BuildHandleMappings()
        }

        if ($xSSA.name -ne $global:SRxEnv.SSA) 
        {    
            Write-SRx VERBOSE $(" --> Setting new Default SSA: " + $xSSA.Name + "  (replacing '" + $global:SRxEnv.SSA + "')") -ForegroundColor Cyan
            $global:SRxEnv.SetCustomProperty("SSA", $xSSA.name)
        }

        $mappedHandle = $($global:SRxEnv.HandleMap | Where { $_.Name -eq $xSSA.name }).Handle
        if ($mappedHandle.count -gt 1) {
            Write-SRx WARNING $(" --> Multiple SSAs map to '" + $xSSA.name + "' ...ignoring map")
            $mappedHandle = ""
        }
                    
        if ([string]::isNullOrEmpty($mappedHandle)) {
            #This will trigger an Enable-SRxDashboard below
            Write-SRx VERBOSE $(" --> No handle configured, triggering Enable-SRxDashboard")
            $global:SRxEnv.SetCustomProperty("Dashboard.Initialized", $false)
        } else {
            #Just logically update the $SRxEnv.Dashboard (but this will not persist to custom.config.json)
            Write-SRx VERBOSE $(" --> Updating `$SRxEnv.Dashboard.Handle with " + $mappedHandle)
            $global:SRxEnv.SetCustomProperty("Dashboard.Handle", $mappedHandle)
        }
    }

	if ($global:SRxEnv.Dashboard.Initialized) 
	{
        Write-SRx Info "SRx Search Dashboard Site: " -ForegroundColor DarkCyan -NoNewline
		Write-SRx Info $global:SRxEnv.Dashboard.Site
        Write-SRx Info "SRx Search Dashboard Handle: " -ForegroundColor DarkCyan -NoNewline
		Write-SRx Info $global:SRxEnv.Dashboard.Handle

		Write-SRx Verbose "Run the command 'Enable-SRxDashboard' to change the Dashboard settings."
        if ($SRxEnv.SilentLicenseAccepted)
        {
            Write-SRx INFO $("-" * 32) -ForegroundColor DarkCyan
			Write-SRx INFO $("-- Initializing SRx Dashboard --") -ForegroundColor DarkCyan
			Write-SRx INFO $("-" * 32) -ForegroundColor DarkCyan
			Write-SRx INFO
					
            Enable-SRxSilentInstall -Site $SRxEnv.SilentSite -Handle "$($SRxEnv.SilentHandle)" -SSA "$($SRxEnv.SilentSSA)" -ThirdPartyLibrariesAccepted:$SRxEnv.SilentThirdPartyLibrariesAccepted -LicenseAccepted:$SRxEnv.SilentLicenseAccepted -ScheduledTasksPassword $SRxEnv.SilentScheduledTasksPassword -ScheduledTasksUser $SRxEnv.SilentScheduledTasksUser -IsHybrid $SRxEnv.SilentIsHybrid
        }
	}
	elseif ((Get-Module "Enable-SRxDashboard") -ne $null) 
	{
        if ($global:SRxEnv.CustomConfigIsReadOnly) 
        {
			Write-SRx Warning $("~~~ The custom config file is currently inaccessible; skipping Dashboard initialization...")
        }
        elseif ($SRxEnv.SilentLicenseAccepted)
        {
            Write-SRx INFO $("-" * 32) -ForegroundColor DarkCyan
			Write-SRx INFO $("-- Initializing SRx Dashboard --") -ForegroundColor DarkCyan
			Write-SRx INFO $("-" * 32) -ForegroundColor DarkCyan
			Write-SRx INFO
					
            Enable-SRxSilentInstall -Site $SRxEnv.SilentSite -Handle "$($SRxEnv.SilentHandle)" -SSA "$($SRxEnv.SilentSSA)" -ThirdPartyLibrariesAccepted:$SRxEnv.SilentThirdPartyLibrariesAccepted -LicenseAccepted:$SRxEnv.SilentLicenseAccepted -ScheduledTasksPassword $SRxEnv.SilentScheduledTasksPassword -ScheduledTasksUser $SRxEnv.SilentScheduledTasksUser -IsHybrid $SRxEnv.SilentIsHybrid
        }
        elseif ([Environment]::UserInteractive)
        {
            Write-SRx INFO $("-" * 32) -ForegroundColor DarkCyan
			Write-SRx INFO $("-- Initializing SRx Dashboard --") -ForegroundColor DarkCyan
			Write-SRx INFO $("-" * 32) -ForegroundColor DarkCyan
			Write-SRx INFO
					
			Enable-SRxDashboard
        }
	}  
	else
	{			    
		Write-SRx INFO $(" -- Contact SearchEngineers@microsoft.com to enable Dashboard, Alerts, and Monitoring features") -ForegroundColor White -BackgroundColor DarkMagenta 
	}
}
# SIG # Begin signature block
# MIIktQYJKoZIhvcNAQcCoIIkpjCCJKICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCUQwxE2KC2yaUA
# M/O4gMD38l8gQrdga7XIH6hnmSjObqCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIEyFpVNvyIoJOgkvANqfcUdOCl45/iTGRcgHCnjNHrEGMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAE7Fp9CVhCLPh1IYiSazsY69
# d71BXB+TAphuAqwXBzJNka/iVN2kI/OkBFfzsS3J00gUr7WzT+0xhYIy30Lxvgnn
# NK1q8zsiixDRHqWoN4OZ7878luSSYlfaBXoomke9ZjE97e7zaSmNoS96Z9VoEfGd
# AnYevOhQfZ9CTUQckCamJM896rDZ8VDjB2DgE9So1kWKIEEouaZrbhKqHiOQlGww
# IlmwLAi64FQa4OLx+EwsSCY+RlPnlJkTSNLJInHR2gnC3go1xeTx/64aadmvYuoU
# gzU1NXJuBoteLFUEB3ZAX5ZWmXyftWOMuSGi9loLFCJTF0lDUzNKfrlmv/o6osqh
# ghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG9w0BBwKgghMfMIITGwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBOgYLKoZIhvcNAQkQAQSgggEpBIIBJTCCASEC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgqK9gGqmpP9+JikigXXRn
# cbmjv5mkDgYGnczGNeDYK3sCBljwlST+bhgTMjAxNzA0MjYyMzUzNDcuODUzWjAE
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
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg2FM03PlK3G+oz7qQBPAA
# veKzg/YQq4ZKeBboQ8hAJzwwgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGxBBQH
# wJWXri5ObsnTdfbZiVGYiyBtOjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAAAtEM6HP62ulKJAAAAAAC0MBYEFD0IHYltP9HRvAmIbEZV
# 8WGBDMOvMA0GCSqGSIb3DQEBCwUABIIBAEg0loHK/wbQ57mXSJUcdk68418ao5mn
# Der4b6YMPIuqKzb9uppdSkvTUD54gc/kuIubiasYg+MV1HSptMU9d2Whffbjrkmq
# qxysO1azuyVZfgXFI/J802SisuPsdbR0M0zhwxetXdSrBtIxu6I/ZsDKor8+ENcG
# LgG4xgB1p9O4bEMV7+Pt1k9IGw1F7IkppfoHqFNW7Fm2pi4MLJr2CMyKuXE4XdJD
# EUfKExMdEXjMCcH/ZBUZgxO/Cdbjo3gXQ1jBb/xtT41lIWPDZ5+kQs0gleDn0fCt
# iAzYiBLmv7ZPabtUU4VAFCuAqQXE4hENedV3fvZUPWr0Z/WQH1fdoes=
# SIG # End signature block
