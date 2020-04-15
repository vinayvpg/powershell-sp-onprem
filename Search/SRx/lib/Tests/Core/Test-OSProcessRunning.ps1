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
# make sure the the $xSSA has been instantiated
if(-not $xSSA._hasSRx) {
    throw [System.NullReferenceException] "This test requires a valid `$xSSA"
}

# $xSSA will be in scope
$ruleObject = New-Object PSObject
$ruleObject | Add-Member Name "Test-OSProcessRunning"  
$ruleObject | Add-Member ExpectedValue 0
$ruleObject | Add-Member Category @("topology");  
$ruleObject | Add-Member ActualValue $(
	$components = $xSSA.ActiveTopology.GetComponents() | Sort ServerName | SELECT ServerName, Name
	$notRunning = $(New-Object System.Collections.ArrayList)
	$unreachableHosts = $(New-Object System.Collections.ArrayList)
	$unableToVerify = $(New-Object System.Collections.ArrayList)

	foreach ($srxServer in $xSSA._Servers) {
		if ($srxServer.canPing()) {
			try {
                $processes = $srxServer.GetProcesses();
			    #Write-Host ("Processes Count: " + $processes.count)
			    if ($processes.Count -eq 0) { $unreachableHosts.Add( $(New-Object PSObject -Property @{ "ServerName" = $srxServer.Name; "Components" = $srxServer.Components; }) ) | Out-Null }
			
		        $crawler = $components | Where {($_.Servername -eq $srxServer.Name) -and ($_.Name -match "Crawl")}
			    if ($crawler) {
		            if (-not $($processes | Where {($_.MachineName -match $srxServer.Name) -and ($_.Name -match "mssearch")})) {
					    $notRunning.Add( $(New-Object PSObject -Property @{ "ServerName" = $srxServer.Name; "Component" = $crawler.Name }) ) | Out-Null
				    }
			    }

		        $junoComponents = $components | Where {($_.Servername -eq $srxServer.Name) -and ($_.Name -notMatch "Crawl") }     
		        $noderunners = $processes | Where {($_.MachineName -match $srxServer.Name) -and ($_.Name -match "noderunner")}

		        foreach ($component in $junoComponents) {
				    #redundant variable, so consolidating: $serverNodes = $($noderunners | Where {$_.MachineName -match $srxServer.Name})
				
				    if ($noderunners.count -eq 0) {
					    #if this component has no proceses matching this $srxServer.Name, then we know it is not running
					    $notRunning.Add( $(New-Object PSObject -Property @{ "ServerName" = $srxServer.Name; "Component" = $component.Name; }) ) | Out-Null
				    } else {
					    #if all of the noderunner processes on this server have a null _ProcessCommandLine, then we most likely could not get this value from Get-Process
					    $hasMissingCmdlineProperty = $noderunners._ProcessCommandLine | Where { [string]::IsNullOrEmpty($_)}
					    if (($hasMissingCmdlineProperty.count -gt 0) -and ($hasMissingCmdlineProperty.count -ne $junoComponents.count)) {
						    #in this scenario, we cannot fully verify that there is a corresponding process for each component, but the counts match
						    $unableToVerify.Add( $(New-Object PSObject -Property @{ "ServerName" = $srxServer.Name; "Component" = $component.Name }) ) | Out-Null
					    } elseif ($($noderunners | Where {$_._ProcessCommandLine -ilike $("*\" + $component.Name + "\*")}).count -ne 1) {
						    #if the nonerunner(s) on this server have the commandline property... but they don't match this component 
						    $notRunning.Add( $(New-Object PSObject -Property @{ "ServerName" = $srxServer.Name; "Component" = $component.Name }) ) | Out-Null
					    }
				    } 
			    }
            } catch {
                $unreachableHosts.Add( $(New-Object PSObject -Property @{ "ServerName" = $srxServer.Name; "Components" = $srxServer.Components; }) ) | Out-Null 
            }
		} else { $unreachableHosts.Add( $(New-Object PSObject -Property @{ "ServerName" = $srxServer.Name; "Components" = $srxServer.Components; }) ) | Out-Null }
	}

	if ($xSSA._Servers.Count -gt 0) {
		if (($notRunning.count -eq 0) -and ($unreachableHosts.count -eq 0) -and ($unableToVerify.count -eq 0)) {0}
		else { $(New-Object PSObject -Property @{ "NotRunning" = $notRunning; "NotVerified" = $unableToVerify; "UnreachableHosts" = $unreachableHosts; }) } 
	} else { 'unknown' } #something else is wrong if no servers are reported
)
$ruleObject | Add-Member Success $($ruleObject.ActualValue -eq $ruleObject.ExpectedValue)
$ruleObject | Add-Member Message $(if($ruleObject.Success){ 
	@{
        level = "Normal";
        headline = "All applicable Component related processes are running";
	} 
} else {
	@{
        level = $(
			if ($ruleObject.ActualValue -ieq 'unknown') { "Exception" }
			elseif ($ruleObject.ActualValue -is [PSCustomObject]) {
				$resultObj = $ruleObject.ActualValue
				if (($resultObj.NotRunning.Count -eq 0) -and ($resultObj.UnreachableHosts.Count -eq 0)) { "Warning" }
				else { "Error" }
			} else { "Error" }	
		);
        headline = $(
			if ($ruleObject.ActualValue -ieq 'unknown') { 
				"Unexpected : No servers could be identified relating to this SSA"
			} else { 
				if ($ruleObject.ActualValue -is [PSCustomObject]) {
					$resultObj = $ruleObject.ActualValue
					$impacted = @()

					if (($resultObj.NotRunning.Count -eq 0) -and ($resultObj.UnreachableHosts.Count -eq 0)) { 
						$outString = "Unable to verify ('commandline' property is null): "
						$impacted += $resultObj.NotVerified.ServerName
					} 
					
					if ($resultObj.UnreachableHosts.Count -gt 0) {
						$outString = "Unable to verify (Servers cannot be pinged): " 
						$impacted += $resultObj.UnreachableHosts.ServerName
					}

					if ($resultObj.NotRunning.Count -gt 0) {
						$outString = "Servers with OS Processes not running: " #take precedence
						$impacted += $($resultObj.NotRunning.ServerName | SELECT -Unique | Sort ServerName)
					}
					
					$delim = ""
					$impacted | SELECT -Unique | foreach { $outString += $delim + $_; $delim = ", " }
					if ([string]::IsNullOrEmpty($outString)) { 
						#we should never hit this case...
						$outString = "Unexpected: Unable to verify because this test produced ambiguous results"
					}
					$outString
				}
			}
		);
        details = $(
			if (($ruleObject.ActualValue -ine 'unknown') -and 
				($ruleObject.ActualValue -is [PSCustomObject])) {
					$resultObj = $ruleObject.ActualValue
					$outString = ""
					if (($resultObj.NotRunning.Count -eq 0) -and ($resultObj.UnreachableHosts.Count -eq 0)) { 
						$outString = ""
						foreach ($failure in $resultObj.NotVerified) { $outString += "  [" + $failure.ServerName + "] " + $failure.Component + "`n" }
					} else {
						$previousServerWithFailure = ">dummy-servername<"
						if ($resultObj.NotRunning.Count -gt 0) { 
							foreach ($failure in $($resultObj.NotRunning | Sort ServerName)) { 
								#render this server header if it does not match the previous server
								if ($failure.ServerName -ne $previousServerWithFailure) { 
									$outString += "  [" + $failure.ServerName + "]`n"
									$previousServerWithFailure = $failure.ServerName
								}
								$outString += "    " + $failure.Component + "`n" 
							}
							$lineFormatting = "`n  "
						}
						
						if ($resultObj.UnreachableHosts.Count -gt 0) {
							#if we have more than 1 unreachable ...or only 1 that is not already reported as NotRunning then we can append this section
							if (($resultObj.UnreachableHosts.Count -gt 1) -or ($resultObj.NotRunning.ServerName -NotContains $resultObj.UnreachableHosts[0].ServerName)) {
								if ($resultObj.NotRunning.Count -gt 0) {  }
								$outString += $lineFormatting + "The following servers cannot be reached (unable to verify the state of processes):`n"
								foreach ($failure in $resultObj.UnreachableHosts) { 
									if ($resultObj.NotRunning.ServerName -NotContains $failure.ServerName) { 
										$outString += "  [" + $failure.ServerName + "]" 
										if ($failure.Components.count -eq 1) { $outString += "  " + $failure.Components[0] + "`n" }
										else {
											$outString += "`n"
											$failure.Components | foreach { $outString += "    " + $_ + "`n" }
										}
									}
								}
							}
						}
						
						if ($resultObj.NotVerified.count -gt 0) {
							$outString += "`n  And the following Components have no 'commandline' property to verify a corresponding process:`n"
							foreach ($failure in $resultObj.NotVerified) { $outString += "  [" + $failure.ServerName + "] " + $failure.Component + "`n" }									
						}
					}
					if (($resultObj.NotVerified.ServerName -contains $ENV:ComputerName) -and (-not $global:SRxEnv.isBuiltinAdmin)) {
						$outString += "`n  *(To access the 'commandline' property, start PowerShell with 'Run as Admin' and try again)`n" 
					}
					$outString
			}
		);
		data = $(
			if ($ruleObject.ActualValue -ine 'unknown') { $ruleObject.ActualValue }
		)
	}		
})

#And then just return the object as the last step…
$ruleObject

# SIG # Begin signature block
# MIIktQYJKoZIhvcNAQcCoIIkpjCCJKICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDlpMtdS0018xc+
# Hrwq+DfCehqPCMJKUjH/BPYJp7ThJKCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIA8nl6uXh52rCeADwRm4/TFpLwphvIBN4LoKvdZ/qwLPMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAMLXaRZwxshSlAza9HBnYhQO
# zr5FLN1zbn6e/K5+EeyCWxBVhonoJNGToRiOzumIOljRk9vYMEgKMNDqfHaLjWs2
# HeyRN2GaeN1IFdTvEovJUwOJfkhmoIYOQZwaaf3y65bfpce2oKRuaIPu96fjK1Y/
# nzHcQg6TowsRfeAL7mennCpaj+LXIDg1vTWWSpjm0Y2tSN/6PbpSHPB8OxGj1uwj
# aXvHwdhgq1tI29/MQZMch96D2tTmPO0e0ZYUMcFnISns31Kw3JkPKDm/vl/4DJWP
# w9UnRQu3jCOmJGNHQJebyFARTzX1MmTxQ15hCM5YsJ/BHF7FPU8My99LMAceg9uh
# ghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG9w0BBwKgghMfMIITGwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBOgYLKoZIhvcNAQkQAQSgggEpBIIBJTCCASEC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgNJ0tmRzZj6C7azcvwWHn
# GvrCWDr84+ghZyQFvFfitYgCBljwlST+FxgTMjAxNzA0MjYyMzUzNDUuNzczWjAE
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
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgZ62VLK0uZit7TBVWYZz+
# UEWDJHRpDVjGk+WDbBmr0oYwgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGxBBQH
# wJWXri5ObsnTdfbZiVGYiyBtOjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAAAtEM6HP62ulKJAAAAAAC0MBYEFD0IHYltP9HRvAmIbEZV
# 8WGBDMOvMA0GCSqGSIb3DQEBCwUABIIBAImlRGcBnZwpim01NzRgHxWIQgCI9RMG
# a3ziq9b5O9ZmXGbIiimjv6bOPkmiPbKLYaWHKSbFXtyDBUR8fO88NMZ0qH5lbjL4
# c1rbrWUcZF3MLD6dNY9GNvoi/ApS9uOpZF5Ig9hDfZhFi2LUYBU5gy+as8679oB6
# YuQglA2ooefaFJ08Lbi7mo/9ay45/Duj1Alzd7r6btm/zNf08mB+iq3eAeyMd8rB
# 5kEvBB/Bqo6l4vESohm+0130Ei3wUG2p7jIjQfPfaEL54bjx24ap1Bm21HXMrmKY
# DHgIGMU+bRWXJsxLx3ranOT+vODduWPq8kZ/LJvq+d4dWKlJMgDkto0=
# SIG # End signature block
