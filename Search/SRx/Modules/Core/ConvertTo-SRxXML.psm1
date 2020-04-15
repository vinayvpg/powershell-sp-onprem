function ConvertTo-SRxXML 
{
<#
.SYNOPSIS
	Export/Convert any object into an XML representation. 
	
.DESCRIPTION
	This module can be widely used across SRx to generate XML out of objects (custom or not). 

.NOTES
	=========================================
	Project		: Search Health Reports (SRx)
	-----------------------------------------
	File Name 	: ConvertTo-SRxXML.psm1
    Author		: Brian Pendergrass
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
	$incomingObj : object to convert.
	$rootTagName : root tag of the XML output. 
	$itemtTag 
.EXAMPLE

	ConvertTo-SRxXML -maxDepth 8 -incomingObj $documentObj -rootTagName "documents" -itemTag "document"
#>
[CmdletBinding()]
param (
	#---Core Parameters-------
	[parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)] $incomingObj = $null,
	[string]$itemTag="",
	$elementDepth = 0,
	$maxDepth = 3,
	$rootTagName = "",
	$attributes="",
	$allowRecursion=$true,
	$blockRecursionList = (  #block furthe recursion on the properties or children of these objects
		#Too Verbose
		"DiagnosticsProviders",  "DiagnosticsService", "JobDefinitions", 
		"Claims", "UserClaims", "DeviceClaims",
		#Provides Redundant Info
		"Instances", "ServiceApplicationProxyGroup", "DefaultProxies", "WebApplication", "Sites", 
		"FeatureDefinitions", "Features", "FormTemplates", "ResourceMeasures", "UsageEntryType",
		"Visualizations", "TopAnswerVisualization", "FullVisualization",  "SummaryVisualization",
		"Databases", "ManagedAccount", "SearchApplications", "Components", "WebApplications",
		#Recursively Defined
		"Collection", "Area", "SearchServiceApplication"
	),
	$doNotRenderList = (  #completely ignore these items, which tend to be VERY heavy and/or timely
		"Parent", "Farm", "NeedsUpgradeIncludeChildren", "UpgradedPersistedProperties", "RawData",
		"ManageLink", "ProvisionLink", "UnprovisionLink", "JobHistoryEntries", "HistoryEntries" )
)
	BEGIN {
		if ($elementDepth -eq 0) {
			Write-SRx VERBOSE ("(Start Time: " + $(Get-Date) + " )")
			#$xml = "<?xml version=`"1.0`"?>`n"
			#$foo = New-Object System.Xml.XmlDocument
			if ($rootTagName.Length -gt 0) { $collectionName = $rootTagName }
			else { $collectionName = "collection" }
			$collectionTag = "<$collectionName>`n"
		} else { 
			$xml = "" 
		}
		$elements = 0
	}
	PROCESS 
	{
		try 
		{
			$indentation = $(Get-ElementTabbing $elementDepth)	
			$elements++   #Only increments for members of an array

			if (($itemTag.Length -eq 0) -and ($incomingObj -eq $null)) { $itemTag = "isNull" }
			
			# In this does not have no access to SP classes, exceptions would be thrown 
			if ((Get-PSSnapin "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -ne $null) 
			{
				if ($incomingObj -is [Microsoft.SharePoint.Administration.SPManagedAccount])
				{
					$attributes += $(Get-ElementAttribs $incomingObj)
					if ($itemTag.Length -eq 0) { $itemTag = [System.Xml.XmlConvert]::EncodeName($incomingObj.GetType().Name) }
					if (($incomingObj -ne $null) -and ($incomingObj.length -gt 0)) {
						$xml += $indentation + "<" + $itemTag + $attributes + "><![CDATA[" + $incomingObj + "]]></$itemTag>`n"
					} else { $xml += $indentation + "<" + $itemTag + $attributes + " />`n" }
					Write-SRx VERBOSE ($itemTag)
				}
				else
				{
					if ($incomingObj -is [Microsoft.Office.Server.Search.Administration.LocationConfigurationCollection])
					{
						if ($itemTag.Length -eq 0) { $itemTag = [System.Xml.XmlConvert]::EncodeName($incomingObj.GetType().Name) }
						if ($($incomingObj | Measure).Count -gt 0) { 
							$xml += $indentation + "<" + $itemTag + $attributes + ">`n"
							$i = 0
							foreach ($childItem in $incomingObj) {
								if ($childItem -ne $null) { 
									$childTag = [System.Xml.XmlConvert]::EncodeName($childItem.GetType().Name)
									Write-SRx VERBOSE ($itemTag + "[" + $i + "] : " + $childTag)
									$arrayIndex = " idx=`"" + $i + "`""
									if (($elementDepth -lt $maxDepth) -and $allowRecursion) {
										$xml += $(ConvertTo-SRxXML $childItem -itemTag $childTag -attributes $arrayIndex -elementDepth $($elementDepth + 1) -maxDepth $maxDepth)
									} else {
										$xml += $indentation + "`t"+ "<" + $childTag + $arrayIndex + $(Get-ElementAttribs $childItem) + "><![CDATA[" + $childItem + "]]></" + $childTag + ">`n"
									}
									$i++
								} else {
									$xml += $indentation + "`t"+ "<"+ $childTag + $arrayIndex + " />`n" 
								}
							}
							$xml += $indentation + "</$itemTag>`n"
						} else {
							$xml += $indentation + "<" + $itemTag + " />`n"
						}
					}
				}
			}

			if (($incomingObj -eq $null) -or 
			($incomingObj -is [string]) -or ($incomingObj -is [Uri]) -or ($incomingObj -is [GUID]) -or
			($incomingObj -is [TimeSpan]) -or ($incomingObj -is [DateTime]) -or 
			($incomingObj -is [System.Security.Principal.SecurityIdentifier]) -or
			#($incomingObj -is [Microsoft.SharePoint.Administration.SPManagedAccount]) -or
			$(($incomingObj.GetType()).IsPrimitive) -or 
			$($incomingObj.GetType().BaseType.Name -eq "Enum")) 
			{
				$attributes += $(Get-ElementAttribs $incomingObj)
				if ($itemTag.Length -eq 0) { $itemTag = [System.Xml.XmlConvert]::EncodeName($incomingObj.GetType().Name) }
				if (($incomingObj -ne $null) -and ($incomingObj.length -gt 0)) {
					$xml += $indentation + "<" + $itemTag + $attributes + "><![CDATA[" + $incomingObj + "]]></$itemTag>`n"
				} else { $xml += $indentation + "<" + $itemTag + $attributes + " />`n" }
				Write-SRx VERBOSE ($itemTag)
			} 
			else 
			{
				if ($incomingObj -is [System.Collections.IDictionary]) 
				{ 
					if ($itemTag.Length -eq 0) { $itemTag = [System.Xml.XmlConvert]::EncodeName($incomingObj.GetType().Name) }
					$xml += $indentation + "<" + $itemTag + $attributes + ">`n"
					foreach ($childName in $incomingObj.Keys) {
						$childTag = [System.Xml.XmlConvert]::EncodeName($($incomingObj[$childName]).GetType().Name)
						$keyAttrib = " key=`"" + [System.Xml.XmlConvert]::EncodeName($childName) + "`""
						Write-SRx VERBOSE ($itemTag + "[" + $childName + "]")
						if ($incomingObj[$childName] -ne $null) {
							if (($elementDepth -lt $maxDepth) -and $allowRecursion) {	
								$xml += $(ConvertTo-SRxXML $incomingObj[$childName] -itemTag $childTag -attributes $keyAttrib -elementDepth $($elementDepth + 1) -maxDepth $maxDepth)
							} else {
								$xml += $indentation + "`t"+ "<" + $childTag + $keyAttrib + "><![CDATA[" + $incomingObj[$childName] + "]]></" + $childTag + ">`n"
							}
						} else { $xml += $indentation + "`t"+ "<" + $childTag + $keyAttrib + " />`n" }
					}
					$xml += $indentation + "</$itemTag>`n"
				} 
				else 
				{
					if (($incomingObj -is [System.Collections.ICollection]) -or
					($incomingObj -is [System.Collections.IEnumerable]) -or
					($incomingObj -is [System.Collections.ArrayList]) -or
					($incomingObj -is [System.Collections.IList]) -or
					($incomingObj -is [Array]) -or 
					(($incomingObj.GetType().BaseType.Name) -like "*Array*")
					#($incomingObj -is [Microsoft.Office.Server.Search.Administration.LocationConfigurationCollection])
					) 
					{
						if ($itemTag.Length -eq 0) { $itemTag = [System.Xml.XmlConvert]::EncodeName($incomingObj.GetType().Name) }
						if ($($incomingObj | Measure).Count -gt 0) { 
							$xml += $indentation + "<" + $itemTag + $attributes + ">`n"
							$i = 0
							foreach ($childItem in $incomingObj) {
								if ($childItem -ne $null) { 
									$childTag = [System.Xml.XmlConvert]::EncodeName($childItem.GetType().Name)
									Write-SRx VERBOSE ($itemTag + "[" + $i + "] : " + $childTag)
									$arrayIndex = " idx=`"" + $i + "`""
									if (($elementDepth -lt $maxDepth) -and $allowRecursion) {
										$xml += $(ConvertTo-SRxXML $childItem -itemTag $childTag -attributes $arrayIndex -elementDepth $($elementDepth + 1) -maxDepth $maxDepth)
									} else {
										$xml += $indentation + "`t"+ "<" + $childTag + $arrayIndex + $(Get-ElementAttribs $childItem) + "><![CDATA[" + $childItem + "]]></" + $childTag + ">`n"
									}
									$i++
								} else {
									$xml += $indentation + "`t"+ "<"+ $childTag + $arrayIndex + " />`n" 
								}
							}
							$xml += $indentation + "</$itemTag>`n"
						} else {
							$xml += $indentation + "<" + $itemTag + " />`n"
						}
					} else {
						if ($incomingObj -is [Object]) {
							if ($itemTag.Length -eq 0) { $itemTag = $incomingObj.GetType().Name }
							Write-SRx VERBOSE ($itemTag)
							$attributes += $(Get-ElementAttribs $incomingObj)
							$xml += $indentation + "<" + $itemTag
							if (($elementDepth -lt $maxDepth) -and $allowRecursion) {							
								$propertyBag = $incomingObj | Get-Member -ErrorAction SilentlyContinue | Where {($_.MemberType -eq "Property") -or ($_.MemberType -eq "NoteProperty") -or ($_.MemberType -eq "ScriptProperty")}
								if ($propertyBag -ne $null) {
									$xml += ">`n"
									foreach ($objProperty in $propertyBag) {
										$propertyName = $objProperty.Name
										Write-SRx VERBOSE ($itemTag + "." + $propertyName)
										<# for debugging #>	if ($itemTag -eq "fill-in-your-tag-name") {
																$debugPoint = $true   <# for debugging #>
										<# for debugging #>	}									
										if ($doNotRenderList.Contains($propertyName)) {
											$xml += $indentation + "`t"+ "<$propertyName />  <!-- SRx: Item Skipped --> `n"
										} else {
											if ($incomingObj.$propertyName -eq $null) { 
												$xml += $indentation + "`t"+ "<$propertyName />`n"
											} else {
												if ($blockRecursionList.Contains($propertyName)) { $canRecurse = $false }
												else { $canRecurse = $true }
												switch ($propertyName) {
													"Server"	{ 
														if ($incomingObj.Server.GetType().Name -eq "SPServer") { $childObj = $incomingObj.Server.Address }
														else { 
															$childObj = $incomingObj.Server
															$canRecurse = $false
														}
													}
													"Service"	{
														if ($incomingObj.Parent.GetType().Name -eq "SPServer") { $canRecurse = $false }
													}
													default {
														if ($blockRecursionList.Contains($propertyName)) { 
															$canRecurse = $false
														} else { $canRecurse = $true }
														$childObj = $incomingObj.$propertyName
													}
												}
												if ($childObj -ne $null) {
													$xml += $(ConvertTo-SRxXML $childObj -itemTag $propertyName -elementDepth $($elementDepth + 1) -maxDepth $maxDepth -allowRecursion $canRecurse) 
												} else { $xml += $indentation + "`t"+ "<$propertyName />`n" }
											}
										}
									}
								} else {
									$indentation = ""
								}
							} else {
								if (($incomingObj.GetType().Name -like "SP*") -and
									(
										($incomingObj.GetType().Name -ne "SPFarm") -or 
										($incomingObj.GetType().Name -ne "SPServer") -or
										($incomingObj.GetType().Name -ne "SPServiceApplicationProxyGroup") -or
										($incomingObj.GetType().Name -ne "SPWebApplication") -or
										($incomingObj.GetType().Name -ne "SPSite") -or
										($incomingObj.GetType().Name -ne "SPWeb")
									)) {
									$xml += $attributes + "><![CDATA[" + $( $incomingObj | select * -First 100 ) + "]]> <!-- SRx: $incomingObj | select * -First 100 --> "
								} else { $xml += "><![CDATA[" + $incomingObj + "]]>" }
								$indentation = ""
							}
							$xml += $indentation + "</$itemTag>`n"
						}
					}
				}
			}
		} 
		catch 
		{
			#potentially unsupported type on the running host (laptop vs Content vs Search Farm)
		}
	}
	END {
		if (($elements -gt 1) -or ($rootTagName.Length -gt 0))  {
			$xml = $collectionTag + $xml + "</$collectionName>`n"
		} 
		$xml
	}
}

Export-ModuleMember *SRx*

function Get-ElementTabbing {
	param ([int]$depth=0)
	$tabbedWhiteSpace = ""
	for ($i=0; $i -lt $depth; $i++) { $tabbedWhiteSpace += "`t"}
	$tabbedWhiteSpace
}

function Get-ElementAttribs {
	param ($anObject = $null, $attribList = @("displayName","name") )
	$attribString = ""
	
	foreach ($attribName in $attribList) {
		if (($anObject.$attribName -ne $null) -and (-not [string]::IsNullOrEmpty($($anObject.$attribName).trim()))) {
			$attribString += " $attribName=`"" + [System.Web.HttpUtility]::HtmlAttributeEncode($anObject.$attribName) + "`""	
		}
	}
	$attribString
}

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBUVeK2L+5dpCPE
# gTWWWsqKkvh5qj/2mA3940DCudvOraCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIAYH2egzNZQjFQ0J5fdtHnPHv75N29jKig4kVIav4NwzMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBALpA8jRoBy2sgcKHpuEajWcA
# t1N3iV0bCBu5cGZ2iAnAh8kPN8C82QFHSXHHlHvKeSc4Y3dk9+QY1Bo9adax4mtx
# VOd8SsFOY3lj35SG1w9jZ25HF/2yR4ieRA0Ec+Ul0yty94jSCrffHL+djUSivpdc
# eSFacWlk6kUTAVhehyX4swPzuR6hpBc+1pnFxwZQl0BFGWDju6z3h7qlkVarDBqs
# voBnRiwDHy0ZXz+LuRmZzb44Sy2bp1eTceddZVyX0tB70vg11IzijXcJDWjVDq8G
# Ou3Xl3B6YpklAw1Rbi/Kdu3blPF+POu9awClUHlS2M3aR+wYrNXzkYE3gehpV7Oh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgE/10R0vhXHaDXR/4PxMs
# n2uVPZa02Eq6Ym3nq+kVcXACBljVOtTIzRgTMjAxNzA0MjYyMzUzNTYuNTQ4WjAH
# AgEBgAIB9KCBuaSBtjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjcy
# OEQtQzQ1Ri1GOUVCMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
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
# 7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNowggPCoAMCAQICEzMAAACy
# NQVoNyIcDacAAAAAALIwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU3WhcNMTgwOTA3MTc1NjU3WjCBszEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9Q
# UjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjcyOEQtQzQ1Ri1GOUVCMSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAmEoBu9FY9X90kULpoS5TXfIsIG8SLpvT15WV3J1v
# iXwOa3ApTbAuDzVW9o8CS/h8VW1QzT/HqnjyEAeoB2sDu/wr8Kolnd388WNwJGVv
# hPpLRF7Ocih9wrMfxW+GapmHrrr+zAWYvm++FYJHZbcvdcq82hB6mzsyT9odSJIO
# IuexsUJtWcJiniwqCvA1NyACCezhFOO1F+OAflTuXVEOk9maSjPJryYN6/ZrI5Uv
# P10SITdKJM+OvQ+bUz/u6e6McHvaO/VquZk8t9sBfBLLP1XO9K/WBrk6PN98J9Ry
# lM2vSgk2xiLsXXO9OuKAGh31vXdwjWNwe8DA9u6eNGmHtwIDAQABo4IBGzCCARcw
# HQYDVR0OBBYEFDNkvmdrHNz5Y0QGSOTFQ8mQ9oKVMB8GA1UdIwQYMBaAFNVjOlyK
# MZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3
# LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEu
# Y3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcN
# AQELBQADggEBAEHgsqCgyvQob8yN3f7bvSBViWwgKXZ2P9QnyV57g/vBwkc2jfZ6
# IUxEGzpxY6sjJr9ErqIZ7yfWWIa6enD6L7RL5HFIOlfStf+jEBuaCcNfHgnoMM2R
# 61RcwQtZ/vTqUi+oejVrYLaDOAmmmnbblrPXNYeoZDpcBs9MEw3GIhi3AGOMuHWx
# ReGpR1rb//y7Gh1UOdsVX+ZX5DSeeC/9tNwg39ITEKPOPXHZ4bBeZVl7jmzulbOZ
# 3/CoHGEPTE9XqtbEMfZ8DWLrbGsAoQqE0nxxKScipNgTD8B6yJ3dOjnq3icG3ARh
# jjxqhJrfTraa7bBM4fpRjYBCBaYm9oNvAeahggN2MIICXgIBATCB46GBuaSBtjCB
# szELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxME
# TU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjcyOEQtQzQ1Ri1GOUVCMSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4D
# AhoFAAMVAL3/xZVjkPETnGDWGcCv6bieHiAdoIHCMIG/pIG8MIG5MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYD
# VQQLEx5uQ2lwaGVyIE5UUyBFU046NERFOS0wQzVFLTNFMDkxKzApBgNVBAMTIk1p
# Y3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQAC
# BQDcq0/oMCIYDzIwMTcwNDI2MTY1NzEyWhgPMjAxNzA0MjcxNjU3MTJaMHQwOgYK
# KwYBBAGEWQoEATEsMCowCgIFANyrT+gCAQAwBwIBAAICHMgwBwIBAAICGegwCgIF
# ANysoWgCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQAC
# AxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEASQFtaOOEu/QY2w7k
# q/HVZ4Vk09m47nWp0s+cBKzFeMO/8j7DRsLVpNzgLe6Wz+bi2oRe0UrBpVT3gOW9
# w66oaovIX9rEYww0u/YIjXnVKCt8uDFHPFHQBKp9OcmOUaNbmD+PHvB/sKdGFHMA
# MACqYesHlT429nyq+Tozz/XWkISu8WEu6QxYjrhCDdWBtIAjKIqcZF97uceeaPGx
# 0vaXkeKYdcvs+vNrGWf0spNEAGooi0ZEKMrAMrlzrw0o8PQNLC88kkokaYql1z5B
# OvlvdXmOSif/CTe4fDC+GeEpvQ/8FIhjKm7eDK6UZZ1NitBrTdsO8/QmyB5+wBtH
# lCEcjzGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAAsjUFaDciHA2nAAAAAACyMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIEoZay857CTOh7Lp
# nSOtz7k8gyp4xOXvXsADo5nbvdTLMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUvf/FlWOQ8ROcYNYZwK/puJ4eIB0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAALI1BWg3IhwNpwAAAAAAsjAWBBSRrnb7XKTtB5IW
# rfee9hkzrTNhXzANBgkqhkiG9w0BAQsFAASCAQBgi/CQjEW32z7rvuGxDp6P8HVh
# 8oi6y1He7v8uJga0tNynWop89bs0ZJy61IuNCR/OWxz9Z2bHfPi/gs3KI0hn8Crd
# FO0CAp2Im8n5SAGwC/SCSQAMgSu6MsdzTeSFcBFCsZp0ialoirr5x/G4Q0Fz2EnE
# jMCBhrLwz9sDVh6a1mUq1ZnSdiHAQ8Pa427xkqNwrDt8IhmruO6fFGTDuYSOHj3p
# fmbFtIqS/aBmmmNMJ9aTQ9hD97Z6HK7jjL+165gZRs2KgLEw0yKWWgb9KWQKZcAR
# vpcTl2rV8Oz4Kl1/8SSyIXywpb/Ewo405pQq/3u9qJ78kj01iLTfYr5lGtQZ
# SIG # End signature block
