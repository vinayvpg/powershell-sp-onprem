function New-SRxReport {
<#
.SYNOPSIS 
	Invokes a test(s) and handles where the output event(s) get written 
	
.DESCRIPTION 
	This cmdlet wraps the invocation chain of Test-SRx followed by:
		-> Export-SRxToSearchDashboard | Export-SRxToAlertsList
		-> and/or Write-SRxConsole
	
.NOTES
	=========================================
	Project		: Search Health Reports (SRx)
	-----------------------------------------
	File Name 	: New-SRxReport.psm1
    Author		: Eric Dixon
	Requires	: 
		PowerShell Version 3.0, Search Health Reports (SRx), Microsoft.SharePoint.PowerShell
	
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
	Control file (e.g. TestControl.csv)

.OUTPUTS
	[ $SRxEvent(s) ]

.EXAMPLE

#>

	[CmdletBinding()]
	param ( 
			[alias("All")][switch]$RunAllTests,
			[alias("OutNull")][switch]$NoWriteToConsole,
            [switch]$PassThrough,
            [alias("EventLog")][switch]$WriteErrorsToEventLog,
            [switch]$Details
	)

	DynamicParam 
	{
		# Set the dynamic parameters' name
		$ParameterControlFile = 'ControlFile'
		$ParameterTest = 'Test'
		
		# Create the dictionary 
		$RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

		# Create the collection of attributes
		$AttributeCollectionControlFile = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
		$AttributeCollectionTest = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
		
		# Create and set the parameters' attributes
		$ParameterAttributeControlFile = New-Object System.Management.Automation.ParameterAttribute
		$ParameterAttributeControlFile.Mandatory = $false
		$ParameterAttributeControlFile.Position = 1

		$ParameterAttributeTest = New-Object System.Management.Automation.ParameterAttribute
		$ParameterAttributeTest.Mandatory = $false
		$ParameterAttributeTest.Position = 1

		# Add the attributes to the attributes collection
		$AttributeCollectionControlFile.Add($ParameterAttributeControlFile)

		$AttributeCollectionTest.Add($ParameterAttributeTest)

		# Generate and set the ValidateSet 
		$rulesControlFolder = Join-Path $global:SRxEnv.Paths.Config "TestControls"
		#$arrSet = Get-ChildItem -Path $rulesControlFolder -File "*.csv" -Recurse | Select-Object -ExpandProperty Name
   		$arrSet = Get-ChildItem -Path $rulesControlFolder -File "*.csv" -Recurse `
            | Select-Object -ExpandProperty Name `
            | % {if($_.EndsWith(".csv","CurrentCultureIgnoreCase")){$_.Substring(0,$_.Length-4)}} 

		$ValidateSetAttributeControlFile = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)

		$rulesDefinitions = $global:SRxEnv.Paths.Tests
		#$arrSet2 = Get-ChildItem -Path $rulesDefinitions -File "Test-*.ps1" -Recurse | Select-Object -ExpandProperty Name
        $arrSet2 = Get-ChildItem -Path $rulesDefinitions -File "Test-*.ps1" -Recurse `
            | Select-Object -ExpandProperty Name `
            | % {if($_.StartsWith("Test-","CurrentCultureIgnoreCase")){$_.Substring(5)}} `
            | % {if($_.EndsWith(".ps1","CurrentCultureIgnoreCase")){$_.Substring(0,$_.Length-4)}} 
		$ValidateSetAttributeTest = New-Object System.Management.Automation.ValidateSetAttribute($arrSet2)

		# Add the ValidateSet to the attributes collection
		$AttributeCollectionControlFile.Add($ValidateSetAttributeControlFile)

		$AttributeCollectionTest.Add($ValidateSetAttributeTest)

		# Create and return the dynamic parameter
		$RuntimeParameterControlFile = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterControlFile, [string], $AttributeCollectionControlFile)
		$RuntimeParameterDictionary.Add($ParameterControlFile, $RuntimeParameterControlFile)
		$RuntimeParameterTest = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterTest, [string], $AttributeCollectionTest)
		$RuntimeParameterDictionary.Add($ParameterTest, $RuntimeParameterTest)
		return $RuntimeParameterDictionary
	}

	BEGIN 
    {
		Write-SRx DEBUG "BEGIN"
		$ControlFile = $PsBoundParameters[$ParameterControlFile]
		$Test = $PsBoundParameters[$ParameterTest]
	}
	PROCESS
	{
		Write-SRx DEBUG "PROCESS"

		if($RunAllTests)
		{
			$output = Test-SRx -RunAllTests 
		}
		elseif($Test)
		{
            if($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent) {
    			$output = Test-SRx -Name $Test -Debug
            } else {
    			$output = Test-SRx -Name $Test 
            }
		}
		elseif($ControlFile)
		{
			$output = Test-SRx -ControlFile $ControlFile 
		}
        else
        {
            Write-SRx ERROR "You must supply command line parameter -Test <test name>, -ControlFile <control file name>, or -RunAllTests"
            return
        }

        if($global:SRxEnv.Dashboard.Initialized)
        {
			$output | Export-SRxToSearchDashboard | Export-SRxToAlertsList | Out-Null
        }

		if(-not $NoWriteToConsole -and $output -ne $null)
		{
			$output | Write-SRxConsole -Details:$Details
		}

        if($WriteErrorsToEventLog)
        {
            foreach($o in $output)
            {
                $message = $null
                if($o.Level -eq "Warning") 
                {
                    $message = $o.Name +":"+ $o.Headline +"("+ $o.RunId +")"
                    $eventId = 21121
                    $eventType = [System.Diagnostics.EventLogEntryType]::Warning
                }
                if($o.Level -eq "Error") 
                {
                    $message = $o.Name +":"+ $o.Headline +"("+ $o.RunId +")"
                    $eventId = 21122
                    $eventType = [System.Diagnostics.EventLogEntryType]::Error
                }
                if($output.Level -eq "Exception") 
                {
                    $message = $o.Name +":"+ $o.Headline +"("+ $o.RunId +")"
                    $eventType = [System.Diagnostics.EventLogEntryType]::Error
                    $eventId = 21123
                }
                if(-not [string]::IsNullOrEmpty($message))
                {
                    try
                    {
                        Write-EventLog -Source "SharePoint Search Health Reports Dashboard" -LogName Application -EntryType $eventType -Message $message -EventId $eventId
                        Write-SRx INFO "Wrote test output to event log."
                    }
                    catch
                    {
                        Write-SRx ERROR "Failed writing test result to Event Log"
                    }
                }
            }
        }

        if($PassThrough)
        {
            $output
        }
	}
	END
	{
		Write-SRx DEBUG "END"
	}
}

Export-ModuleMember New-SRxReport

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCP3JTtrAiddX/L
# fogxk3dhPg9ODlflvoI+3VvhWARdq6CCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEICuk+ii9lGgIA3Zb6TvOYs2w5onC1VhaKvLd4vJCqv4JMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAE+Hb14wiBk8ePAGEKdtngSJ
# eMdfaHWcw7P2/Ase/O3pQbDGGzKdzF56tfEYfhzKv0r6YDDiRDutZhD5JvGaiwsi
# g/3BPolTGRAB77VA4nfjjhptFn/JvOiE+BLlOazp+DdzTzI+ow523T+zWPa8S61w
# vyZ0yzKAVz8VparJnI3Yd0A8lfQ63S63Who9TAMNVX7Kch7Pt6GXLy+iDdVqnV+0
# 8SyiCyL8UpPo/xMcFmvlroIwLaQ4QPEvTQ0jSaUUNYYcmtYHf84WpGaLHa4Tnin+
# kOZgof+MAUMGd2griiIuF0QyNJDHXissqspg+9UUrOJgLF8EoBAgNbFwzjcQlPqh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgDJzHLV0C/HLA0cGsAhVt
# jvmUvo0/rc2yZE8lQMTwn7sCBljVRnmbVhgTMjAxNzA0MjYyMzUzNTguNzY1WjAH
# AgEBgAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkI4
# RUMtMzBBNC03MTQ0MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
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
# 7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNowggPCoAMCAQICEzMAAACf
# Z/K1qCMGW3sAAAAAAJ8wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjQ3WhcNMTgwOTA3MTc1NjQ3WjCBszEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkI4RUMtMzBBNC03MTQ0MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAuQjxI5zdxAIvAoWhoyeXZPkDnBJUP1OCWrg+631u
# GMVywSfVcCkM8JZL1o+ExxY5Yp77sQ0jhKLjMPfSdVAL09nQ0O76kr1dXzc5+MZy
# EWQrM4FF106GmxCTEWAwXdF8tM1cASp9+c1pF5fC1VSSIYQm9boqYAGLHM/Rp5RW
# Ynowecmeaj5Mpl2hWXtyDpNjosKjN78XquE5eaL8/df8reMe2YBrEv067neOMOA7
# lGPG3pkRqZ0SwYXZJZnrAfoOaD0bqJk/GDD6aM4PBF4vqPCHsfZeGy/OgUytIREz
# Mgh/Z4kYAz0LQZHQFkfJG2LXtCovlNoK5Y+MzFMpdfgOWQIDAQABo4IBGzCCARcw
# HQYDVR0OBBYEFP2LGyLDfSNHdqYe3+Bm1FLptvmgMB8GA1UdIwQYMBaAFNVjOlyK
# MZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3
# LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEu
# Y3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcN
# AQELBQADggEBAGUQwWxrzxUerw9INuvfLQu8AADmkWYaUJZluTEPZYyp8XTLx+eW
# +BvzvjPyzPxBnMHIKZjWMfIdNz3xl6TPsvZjlIA1QhryPJTfpzrgKTl9jo972FQD
# VEb/XM/56rTzRyFQ8IXbN7OF/C7P05vShs7rgHBbQZmBhjPWGOyr4MGRIIFFXn2v
# IWnOApHCFYXyq5e0cOmKaInH52zZVlLARWT9BFjuku5S9503w/kM24tppHDeglyz
# ZbGHaNZLlPxjcl69SjcrdVO0c+LYgFYhKQQbtM6c0RRxRcMwZI55nbuS48XMqQNV
# u3O/ARV6mQauxnVb7XG4Ng9DVvcEwbwLv0ehggN2MIICXgIBATCB46GBuaSBtjCB
# szELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxME
# TU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkI4RUMtMzBBNC03MTQ0MSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4D
# AhoFAAMVAGzTJwjy+dmoy/kZ3pJLSq3bGaPBoIHCMIG/pIG8MIG5MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYD
# VQQLEx5uQ2lwaGVyIE5UUyBFU046NTdGNi1DMUUwLTU1NEMxKzApBgNVBAMTIk1p
# Y3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQAC
# BQDcq1AkMCIYDzIwMTcwNDI2MTY1ODEyWhgPMjAxNzA0MjcxNjU4MTJaMHQwOgYK
# KwYBBAGEWQoEATEsMCowCgIFANyrUCQCAQAwBwIBAAICIkIwBwIBAAICGIYwCgIF
# ANysoaQCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQAC
# AxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEAF6LJHj8I89WWxUQn
# YuPdktfNrKj9mASQINSB234cFWCRdlgDyvESSkh4F+nnFkojy3DlKTaGiWCqDawi
# YVmYuzywJmy0ujSaFeeYpPXXZiJ6CaQPwkFfkNTVbMiPINRT02biLcZv870ROQnr
# 71BGsRbbGL2kCQLWgdUmgNClZ8A8K0lV5eCMAetgudo3mR0SEowB/J+OxDd3F3iv
# GjDh8KayEu8xSl0DonL4rl0VNiU1ECfDHLWGZn32baZmiIQJH8g7Aze/BMK2wUUu
# qkwvfFpsoVfkNwZ6iBk4Oqu+Iwdvg8HbzklG1buPZhBN1BXGTuiupTayEWDfeRhZ
# ysxEbDGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAAn2fytagjBlt7AAAAAACfMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIPvHIHsDr3cU+RIG
# /8/kfzWtxUML9F4xedVXeVyQGw/OMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUbNMnCPL52ajL+RnekktKrdsZo8EwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAJ9n8rWoIwZbewAAAAAAnzAWBBQAlebO8glKQo8J
# SjqdCe2Rg8CY/zANBgkqhkiG9w0BAQsFAASCAQCTd2yu2IlIqMXCHowZwQbUS07d
# tjOyYFTBOLolwxq2NtTYwums4Hbb7BTM4QiAnnxDqVbGytsTiZ8utoCDEjXKIQyn
# IPTCdBUAFo6hfMwTPeve6p2lWgSyY443DlkITx5/+6AlKwOhCDcPjPjNp3guVtp6
# EbE40IVlDcjaoWv/3rLiQIS+WP9quKlHgXkcrt2PMhW5wykwbRaYWVPsrMG/I3++
# AiT23ajGAqxUkffYtYj5JR6ySm7svx5vC4IBnhGoRrCYrmWeiTgVYyx6mKcs9KUj
# yIqdym0VK7Sx2mM4sDdPsScMIj6yPjwoKrEIqDlVByGSJJEXCOfc4n7ggRHk
# SIG # End signature block
