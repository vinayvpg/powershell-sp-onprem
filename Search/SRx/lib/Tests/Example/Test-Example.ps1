<#
.SYNOPSIS 
	Example Test
	
.DESCRIPTION 
	This is an example of a test, which simply evaluates whether or not the SSA is online
		
.NOTES
	=========================================
	Project		: Search Health Reports (SRx)
	-----------------------------------------
	File Name 	: Test-Example.ps1

	Requires	: 
		PowerShell Version 3.0, Search Health Reports (SRx), Microsoft.SharePoint.PowerShell, 
        Patterns and Practices v15 PowerShell
        -----
        Test files must follow the naming convention: Test-[whateverYouWant].ps1

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
    No input required

.EXAMPLE
	$t = Test-SRx -Name Example

#>

#-- Pre-reqs (and eject if they are not met)
    # Ensure the the $xSSA has been instantiated and "throw" exception otherwise (here, the message level defaults to "Exception")
    if (-not $xSSA._hasSRx) {
        throw [System.NullReferenceException] "This test requires a valid `$xSSA"
    }

    # Or, you can also just return with a friendly string (here, the message level defaults to "Info")
    if ($global:arbitraryTest) {
        return "This rule only applies when `$arbitraryTest is not true"
    }

# $xSSA will be in scope
$ruleObject = New-Object PSObject
#$ruleObject | Add-Member Name "Test-Example"           #...the name property is optional if your test script is named "test-nameOfYourTest"
$ruleObject | Add-Member ExpectedValue "Online"         # - optional property
$ruleObject | Add-Member Category @("example","sample") # - Add any categories you want as a string
$ruleObject | Add-Member ActualValue $($xSSA.Status)    # - optional property
$ruleObject | Add-Member Success $($ruleObject.ActualValue -eq $ruleObject.ExpectedValue)
$ruleObject | Add-Member Message $(                     # - the value must be a hashtable with level and headline (and optionally, details and data)
    if($ruleObject.Success){ 
        @{ 
		    level = "Normal";    # - levels that we use: Normal, Error, Warning, Info, Exception
		    headline = "'" + $xSSA.Name + "' is "  + $ruleObject.ExpectedValue;
            details = "[optional] This is the detailed output for you test";
            data = $(Get-Host);  # - optional message property
	    } 
    } else { 
        @{
			level = "Error";
			headline = "Expected SSA to have status " + $ruleObject.ExpectedValue + ", found status: " + $ruleObject.ActualValue;
		} 
    } 
) 

#And then just return the object as the last step�
$ruleObject

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAk3HsvDF7oR91y
# RxrAyxkqB34rimU1sCGfnpXOtS85daCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEINYXJLrlCSNdVPDJpDO47qi6g9fCnZ/qkLBHbOJ80wAMMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAG6o2XwVwygko0HdV/QnuKxm
# qlV2nejQ/QboydTuGosncgqr5GvRk8ZcqtXM+y1+nUBy9mMHFnu1zwiehP6YIHxr
# +o2ZmuYcRpLClyueCLEnws5VTMW3s8JtmpDdsgeBns3AZvtbhI4ZUPn/as5X+yb4
# 1GEAQM55H8loj7XBA1E1B77ecTGSr3t/8cLaowAz36yuWIqVaS8nNweoLYZLSgAQ
# VpXoQ7lCr2rIe6h3Dzv4XPRgKXBdbWEajMeMcTRePTN1fX0q7hhFDIlf6AL68MUD
# d19wABPy+FWr1AWJzKb9Qex7yozQAa16+jR2vEubmgeUTttSIRxche2jsRySmjCh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgjZtSCFX8BIBLFEtNbyr2
# pg+Nf26nQHjmk6ZQi7Y84DoCBljVRUm9ARgTMjAxNzA0MjYyMzUzNTQuNzI3WjAH
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
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIPxEEEPYqps7wCnX
# YGc/UHGPdU6VzYNNihAcp/EHib49MIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUNeSj+04//yYNcfVtXhJ7kZY4po0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAKPvHyIggWPcpQAAAAAAozAWBBR789E1ZbhfhAf/
# f93iigE5Mjb/ajANBgkqhkiG9w0BAQsFAASCAQAwqkqCtsJhF430BN9S/ofZW87P
# 4KSiybu4iHQ56u4o8PXkduTMwq1sx9BOtbRZ+XbXkeJ++INW3mCp8sySi7v6BuIC
# 1tpIVmJX+XHiyl4PrVAdGxJrCfQcOn39oI6ZuCQlajNy1Ol+sQcoc+qle7ulVGm5
# wrlAuzWU84mr1PgcUi4o6dH9wDxkiQwZ65wEQvNauYme06u3FUeZfqtLZP+oRXi2
# UZ1gpFRlnCDwKGmF3PkuHwA838XOURfFIUDLi2tBKLkI67FlaZi05Img/duKPBW2
# /agyheylcVGAHByHHWmgdLZjXOl1Y+k02WfKJmQzmfLvnysBEmjGGeGMwju2
# SIG # End signature block
