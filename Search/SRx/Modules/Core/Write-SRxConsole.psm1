function ColorByLevel
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
[CmdletBinding()]
param ( 
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
		$line,
        [switch]$IncludeDetails
)
	BEGIN 
    {
		[System.ConsoleColor]$defaultColor = (Get-Host).UI.RawUI.ForegroundColor
        if($defaultColor -lt 0) {$defaultColor = [System.ConsoleColor]::White}
        
        $incomingResultRow = 0 
        $headlineOffset = 0
 	}
	PROCESS
	{
		if([string]::IsNullOrEmpty($line)){return}
		$words = $line.Split()

        if ($incomingResultRow -eq 0) 
        {
            $headlineOffset = $line.indexOf("Headline")
            #Write-Host $("-" * $line.length) -foregroundColor Cyan
            #Write-Host $line -foregroundColor Cyan
            #Write-Host $("-" * $line.length) -foregroundColor Cyan
        }
        
		$count = 0
		foreach($word in $words[1..$words.Length])
		{
			if([string]::IsNullOrWhiteSpace($word))
			{
				$count++
				continue
			}

			$level = $word
			break
		}

		switch($level)
		{
			"INFO" {
				Write-Host $words[0..$count] -NoNewline
				Write-Host " Info " -NoNewline
				Write-Host $words[($count+2)..$words.Length] -ForegroundColor $defaultColor 
			}
			"Normal" {
				Write-Host $words[0..$count] -NoNewline
				Write-Host " $level " -ForegroundColor Green -NoNewline
				Write-Host $words[($count+2)..$words.Length] -ForegroundColor $defaultColor 
			}
			"Warning" {
				Write-Host $words[0..$count] -NoNewline
				Write-Host " $level " -ForegroundColor Yellow -NoNewline
				Write-Host $words[($count+2)..$words.Length] -ForegroundColor $defaultColor
			}
			"Error" {
				Write-Host $words[0..$count] -NoNewline
				Write-Host " $level " -ForegroundColor Red -NoNewline
				Write-Host $words[($count+2)..$words.Length] -ForegroundColor $defaultColor
			}
			"Exception" {
				Write-Host $words[0..$count] -NoNewline
				Write-Host " $level " -ForegroundColor Magenta -NoNewline
				Write-Host $words[($count+2)..$words.Length] -ForegroundColor $defaultColor
			}
			default {Write-Host $line}
		}

        if ($IncludeDetails -and ($incomingResultRow -gt 1) -and ($dataList[$incomingResultRow-2].Details -ne $null)) {
            if ($dataList[$incomingResultRow-2].Details -is [String]) {
                $details = $dataList[$incomingResultRow-2].Details.split("`n").trimEnd()
            } else {
                $detailStrings = $dataList[$incomingResultRow-2].Details | foreach { $_ | Out-String -stream }
                $details = $detailStrings | foreach { $_.trimEnd() }
            }

            $lineInDetails = 0
            foreach ($d in $details) {
                if ($d.length -gt $($Host.UI.RawUI.WindowSize.Width - $headlineOffset - 1)) {
                    $d = $d.Substring(0, $($Host.UI.RawUI.WindowSize.Width - $headlineOffset -3)) + "..."
                }
                if (($lineInDetails -eq 0) -or ($details[$lineInDetails-1] -ne $details[$lineInDetails] -ne "")) {
                    Write-Host $(" " * $headlineOffset) -NoNewline
                    Write-Host $d
                }
                $lineInDetails++
            }
        }
        $incomingResultRow++
	}
	END
	{}
}

function Write-SRxConsole 
{ 
[CmdletBinding()]
param ( 
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
		[object[]]$data,
        [switch]$Details
		)

	BEGIN 
    {
		[System.Collections.ArrayList]$dataList = @()
	}
	PROCESS
	{
		foreach($d in $data)
		{
			$dataList.Add($d) | Out-Null
			Write-SRx DEBUG "PROCESS[$d]"
		}
	}
	END
	{
		Write-SRx DEBUG " --> [formatting data for output"
		if ($global:SRxEnv.Log.Level -eq "Debug")
        {
            $dataList | Format-List | Out-String -Stream
        } 
        else 
        {
            $dataList | Format-Table -AutoSize  @{l='Test'; e={$_.Name.Substring(5)}}, Level, Headline | Out-String -Stream | ColorByLevel -IncludeDetails:$Details
        }
	}
}

Export-ModuleMember Write-SRxConsole 

# SIG # Begin signature block
# MIIkuAYJKoZIhvcNAQcCoIIkqTCCJKUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD/qX55jAn+vJXY
# SqNu0X3sHnhCuueXc1hwfB3Qi72O9aCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIJkcWCQTJopBnWH42hThxyOzFAVeMPg8aD2SvOE7uuagMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAJtmfPzYKFXnrHqw95abHNWJ
# NZExI9DIw2prvcoWvN/dlnCXppZ9NktoAMaml5X1nrLbDx/IsQ4mpcN48jMK7mXL
# p67qgk63n+q0U164uQ8Zcpuhd39Az4nloW/CqrVghSE0qQLRBIbprNM9FoUW4lON
# gADWU29TaqdX91uKOja8SbSAS0VAe1JNhaCD1aaRAiY03PQqLN7p8CXPlmF//Odd
# 6L9wcGPntVdZDq6l0LRY2bK/griXWA7ltRdQQWRSqx5r3ozCn3J9zssk6JiSMAur
# mehsKt+BjUz6sMCl2Skc5UBeTrr+r8QMEHx++zzhECuB3r255J8j9pKPevpItV2h
# ghNJMIITRQYKKwYBBAGCNwMDATGCEzUwghMxBgkqhkiG9w0BBwKgghMiMIITHgIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPAYLKoZIhvcNAQkQAQSgggErBIIBJzCCASMC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQg/qhm6GGrorWvK/wcO2Zl
# bgkM9PVNk6EVH1m35yP3dTkCBljVRUm9tRgSMjAxNzA0MjYyMzUzNTkuNThaMAcC
# AQGAAgH0oIG5pIG2MIGzMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046QzBG
# NC0zMDg2LURFRjgxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
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
# DaBQNdrvCScc1bN+NR4Iuto229Nfj950iEkSMIIE2jCCA8KgAwIBAgITMwAAAKPv
# HyIggWPcpQAAAAAAozANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDAeFw0xNjA5MDcxNzU2NDlaFw0xODA5MDcxNzU2NDlaMIGzMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BS
# MScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046QzBGNC0zMDg2LURFRjgxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCp0R6XxxNp+Dg7FRfmSA75X4KsVJ0wGq0QXdDyBfc/
# aIY3WtAAU+acbRxo8inH1v8xmFJNEbr1wWSGOjkJJ1ZJXp+hIRkpG8xaFuPzfQFV
# Fyzp4ayW+8eZryhwAHUi+i5ylFRfutHFrDLU5dYeefCBowq+Y754aWfij4XRyb7I
# f5CL5Lh+mK5vvipkCBpItzkhyGr0JEtgENRygHIIOOlu+TtT7VnbJNRNYchb02lj
# ADK9zLFRPetAuH+4vrtyHcE4bN4Jjm4tmTpsRQjes09bbW2Akdkjm0iZTB7lEX+z
# F552kb3iJhYfEQAcOt+Z6Cz/7HUsWClwpxctKO6PtKNfAgMBAAGjggEbMIIBFzAd
# BgNVHQ4EFgQU+oW6ZmboRpnacJ+6ISVA2+DosXAwHwYDVR0jBBgwFoAU1WM6XIox
# kPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNy
# b3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDct
# MDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5j
# cnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0B
# AQsFAAOCAQEAHdFFulu0v4rmho1FzjWIJhJGsDODamExyBZz+OYkemrBwBU3PI3H
# KQ1Iy3SXpbKH4QZ41UOMUzrw4lEOeLbT/ByNJeVTGhXZPnq8x7vBTmZYURgPZSVh
# IaG+5pHDYI75CbQ+iMKmcoE7HPIQHNUFrohdNFVSqEOGjPANVL5L5EvuF5W2m7wC
# axbNsi1s9avfNeEGg7RZQeceAfNoTffY3iQsRktCwI0Xc0RQK43eds1/dF3f5mTM
# MriewM9lUhEIBnqXtoNlo2LYw4O6OY5HuFOqw2YaHL1JTvTc1Aes0rjRZPngd8ns
# doDEqxcr6yODtZaJ8dhLlpLdb6nCO9bznKGCA3YwggJeAgEBMIHjoYG5pIG2MIGz
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRN
# T1BSMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046QzBGNC0zMDg2LURFRjgxJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiJQoBATAJBgUrDgMC
# GgUAAxUANeSj+04//yYNcfVtXhJ7kZY4po2ggcIwgb+kgbwwgbkxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIxJzAlBgNV
# BAsTHm5DaXBoZXIgTlRTIEVTTjo1N0Y2LUMxRTAtNTU0QzErMCkGA1UEAxMiTWlj
# cm9zb2Z0IFRpbWUgU291cmNlIE1hc3RlciBDbG9jazANBgkqhkiG9w0BAQUFAAIF
# ANyrUBEwIhgPMjAxNzA0MjYxNjU3NTNaGA8yMDE3MDQyNzE2NTc1M1owdDA6Bgor
# BgEEAYRZCgQBMSwwKjAKAgUA3KtQEQIBADAHAgEAAgInZzAHAgEAAgIYjjAKAgUA
# 3KyhkQIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMBoAowCAIBAAID
# FuNgoQowCAIBAAIDB6EgMA0GCSqGSIb3DQEBBQUAA4IBAQBAl734NwI7HODHif+U
# 7t73v+u7h0IQRpuooVZgNFMBV573IR6wYZcWScS6Z+XP3Tu2WVKUVsMCV6cOwjfS
# ZQBOhGom4lovEyL5FiH4kA6OLRPcJJmd2c0j56eIfZiaK708xwIQYyENfWS1a2Dx
# /yqezUJljClmNGYY6wFePxuap573RJlMxXyIm8E4/tyLD44g8k3lM5wq+nXLngHh
# TgIF7LjZlwZtB274BedNra6XagbrxD+XoEnvS9ncj+TFLckd2HIar3nx16jLXwOc
# h/bw4W9h0iHUz+5ZefehA2xNDLUdeCL0bJZcGNiSZg1tAt7iiLvyk8BRQRpR+qu3
# HY7MMYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAACj7x8iIIFj3KUAAAAAAKMwDQYJYIZIAWUDBAIBBQCgggEyMBoGCSqGSIb3
# DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgHS2fEdjfFtate4ZX
# 2mHYad+fch7EktFIOBIIUI7tjrUwgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGx
# BBQ15KP7Tj//Jg1x9W1eEnuRljimjTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAAAo+8fIiCBY9ylAAAAAACjMBYEFHvz0TVluF+EB/9/
# 3eKKATkyNv9qMA0GCSqGSIb3DQEBCwUABIIBAKa+ZxdXXA/SjbIvQBIlvQj7AirX
# 4ONc8kaoA8EqeP/OcUreZ2/H+E1V4BwQJ0RFOBgFDOWNNtrb7sAgOIRQRtCPp4LN
# ZpMnwM9mWgto++DIYllTv5sYZWzLUXIfLfy867qETrHjxvtsegMSCkLIV14oOCRO
# ymIQu6OZmWH3g0TDxq4fqmLJqKI52PwJ4UIV8pL/2CL2fyAX2gGx0kKZvkCoqdtW
# nx4rw8hBbUvoaSamV12LdS5dfhuO76BeerP6Iem1UKuHFmPlG3GG+z1ie8r2MTtl
# M1hy91u5dF01fJS3jJ2Pe2w+nZ6qmW81A8min8nAIotvqPU+IxN5lA6ZeOQ=
# SIG # End signature block
