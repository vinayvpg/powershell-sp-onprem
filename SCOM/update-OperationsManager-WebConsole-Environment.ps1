<#  
.SYNOPSIS  
    Microsoft Corporation
    This script Updates an existing OperationsManager Web Console Environment in the OperationsManager Web Console Environments List in the SharePoint Admin farm root.
.DESCRIPTION  
    Use this script to Update an existing OperationsManager Web Console Environment to the OperationsManager Web Console Environments List.
.NOTES  
    File Name  : Update-OperationsManager-WebConsole-Environment.ps1
    Requires   : PowerShell Version 2.0  
.PARAMETER webconsoleUnc
    The optional UNC to the Operations Manager Web Console installation folder.
.PARAMETER title
    An optional specifier for the friendly name of the Environment. 
    If not specified, and the webconsoleUnc parameter is, the Title is the machine name that the web.config file was read from.
.PARAMETER hostUri
    An optional specifier for the host name that will provide the Dashboard to the SharePoint page.
    If not specified, the hostUri is http://machinename/OperationsManager where the machine name matches the machine that the web.config file was read from.
.PARAMETER targetApplicationID
    An optional specifier for specifying the targetApplicationID in the SharePoint Secure Store.
    This value creates a link between the targetApplicationID and the SharePoint Secure Store for using a single set of credentials to Authenticate against Operations Manager.
 .PARAMETER hostErrorTimeout
    An optional integer in milliseconds. 
    This is the amount of time for the Web Part to connect to the Web Console, before showing an error.
    The range of valid values is 1000 ms. to 60000 ms.
.PARAMETER encryptionKey
    An optional specifier for specifying the Override Encryption Key.
    Cannot be used when -webconsoleUnc is specified. Values are read from web.config instead.
.PARAMETER encryptionAlgorithm
    An optional specifier for specifying the Algorithm for the Override Encryption Key.
    The value used for this must be a valid algorithm.
    Cannot be used when -webconsoleUnc is specified. Values are read from web.config instead.
.PARAMETER encryptionValidationKey
    An optional specifier for specifying the Override Encryption Validation Key.
    Cannot be used when -webconsoleUnc is specified. Values are read from web.config instead.
.PARAMETER encryptionValidationAlgorithm
    An optional specifier for specifying the Validation Algorithm used Override Encryption Key.
    The value used for this must be a valid algorithm.
    Cannot be used when -webconsoleUnc is specified. Values are read from web.config instead.
.EXAMPLE  
    Update an existing OperationsManager Web Console Environment to the SharePoint server using a UNC to the source Operations Manager Web Console.
    Update-OperationsManager-WebConsole-Environment "\\machineName\c$\Program Files\System Center Operations Manager 2012\WebConsole\WebHost" [ENTER]
    
    Update an existing OperationsManager Web Console Environment to the SharePoint server using a UNC to the source Operations Manager Web Console and give it a friendly name.
    Update-OperationsManager-WebConsole-Environment -webconsoleUnc "\\machineName\c$\Program Files\System Center Operations Manager 2012\WebConsole\WebHost" -title "Operations Manager Web Console" [ENTER]
#>      
param(
 [Parameter(Position=0, Mandatory=$false, HelpMessage="A UNC path to the Operations Manager Web Console installation folder.")]
 [string]$webconsoleUnc,
 [Parameter(Position=1, Mandatory=$false, HelpMessage="The Title/Name for the Operations Manager Environment.")]
 [string]$title, 
 [ValidatePattern("(http|https)://([\w-]+\.)*[\w-]+(/[\w- ./?%&=]*)?")]
 [Parameter(Position=2, Mandatory=$false, HelpMessage="The URL to the Operations Manager Web Server Environment")]
 [string]$hostUri, 
 [Parameter(Position=3, Mandatory=$false, HelpMessage="The targetApplicationID in the SharePoint Secure Store for Shared Credentials")]
 [string]$targetApplicationID,
 [ValidateRange(1000, 60000)]
 [Parameter(Position=4, Mandatory=$false, HelpMessage="The host error timeout value in milliseconds.  This is the amount of time the Web Part will wait to connect to the Web Console. Valid Range 1000-60000")]
 [int]$hostErrorTimeout,
 [Parameter(Position=5, Mandatory=$false, HelpMessage="The Encryption key for Shared Credentials")]
 [string]$encryptionKey, 
 [Parameter(Position=6, Mandatory=$false, HelpMessage="The Encryption algorithm for Shared Credentials")]
 [string]$encryptionAlgorithm, 
 [Parameter(Position=7, Mandatory=$false, HelpMessage="The Encryption validation key for Shared Credentials")]
 [string]$encryptionValidationKey, 
 [Parameter(Position=8, Mandatory=$false, HelpMessage="The Encryption validation algorithm for Shared Credentials")]
 [string]$encryptionValidationAlgorithm
 )

# Adds the Path Char to the Solution File
function AddPathChar()
{
  param([string]$source)
  if (  $source.EndsWith("\") )
  {
  }
  else
  {
    $source = $source + "\";
  }
  return $source;
}

# Gets the Machine Name from the UNC
function GetMachineNameFromUnc()
{
   param([string]$webconsoleUnc)
   
   [int]$index = $webconsoleUnc.IndexOf("\\")
   if ( $index -ne -1 )
   {
     [string]$temp = $webconsoleUnc.Substring(2)
     $index = $temp.IndexOf("\")
     if ( $index -ne -1 )
     {
        $temp = $temp.Substring(0,$index)
        return $temp
     }
  }
  else
  {
      Write-Host -f Red "ERROR: Invalid UNC specified"
  }
  return ""
}

# Validates the CryptoAlgorithm
function ValidateCryptoAlgorithm()
{
  param([string]$algorithm)
  try
  {
    $config = [System.Security.Cryptography.CryptoConfig]::CreateFromName($algorithm)
    if ( !$config )
    {
       return $false
    }
    else
    {
      return $true
    }
  }
  catch
  {
     return $false
  }
}

#if no webconfig unc is specified, we must have title
if ( !$webconsoleUnc )
{
    if ( !$title )
    {
       Write-Host -f Red "ERROR: title when not specifying a webconsoleUnc"
       return;
    }
    # validate the encryption settings
    if ( $encryptionAlgorithm )
    {
      $valid = ValidateCryptoAlgorithm($encryptionAlgorithm)
      if ( !$valid )
      {
          Write-Host -f Red ERROR: The encryptionAlgorithm [$encryptionAlgorithm] is invalid.
          return;
      }
    }
    if ( $encryptionValidationAlgorithm )
    {
      $valid = ValidateCryptoAlgorithm($encryptionValidationAlgorithm)
      if ( !$valid )
      {
          Write-Host -f Red ERROR: The encryptionValidationAlgorithm [$encryptionValidationAlgorithm] is invalid.
          return;
      }
    }
}
else
{
  $webconsoleUnc = AddPathChar($webconsoleUnc)
  [string] $machineName = ""
  $machineName = GetMachineNameFromUnc($webconsoleUnc)
  if ($title -eq "" )
  {
    $title = $machineName
  }
  # Never execute without a valid Title
  if ( !$title)
  {
     Write-Host -f Red "ERROR: title was not set from the machineName derived from the webconsoleUnc"
     return
  }
  # validate that no encryption settings are specified
  if ( $encryptionKey -or $encryptionValidationKey -or $encryptionAlgorithm -or $encryptionValidationAlgorithm )
  {
      Write-Host ""
      Write-Host -f Red "ERROR: Can not use the encryption overrides when specifying -webconsoleUnc. The keys will be read from web.config.";
      return;
  }
}

#rem Set the Host Uri if Not Specified
if ( $webconsoleUnc -AND !$hostUri)
{
   $hostUri = "http://" + $machineName + "/OperationsManager/"
}

Write-Host ""

#if no encryption key was found
if ( $webconsoleUnc -AND !$encryptionKey )
{
  #Read the Xml File
  [string]$fileName = $webconsoleUnc + "web.config"
  $fileExists = test-path $fileName
  if ( $fileExists-ne "True" )
  {
    Write-Host -f Red ERROR: Cannot locate Web Console files in $filename
    return
  }
  # Read in the Xml File
  $xmldata = [xml](Get-Content -path $fileName)
  # Read the keys from the file.
  try
  {
    $overrideEncryptionKey = $xmldata.SelectSingleNode("//configuration/enterpriseManagement/encryption/keys/key[@name='OverrideTicketEncryptionKey']").GetAttribute("value")
    $overrideEncryptionAlg = $xmldata.SelectSingleNode("//configuration/enterpriseManagement/encryption/keys/key[@name='OverrideTicketEncryptionKey']").GetAttribute("algorithm")
    $overrideEncryptionValidationKey = $xmldata.SelectSingleNode("//configuration/enterpriseManagement/encryption/keys/key[@name='OverrideTicketEncryptionKey']/validation").GetAttribute("value")
    $overrideEncryptionValidationAlg = $xmldata.SelectSingleNode("//configuration/enterpriseManagement/encryption/keys/key[@name='OverrideTicketEncryptionKey']/validation").GetAttribute("algorithm")    
    $encryptionKey = $overrideEncryptionKey
    $encryptionAlgorithm = $overrideEncryptionAlg    
    $encryptionValidationKey = $overrideEncryptionValidationKey
    $encryptionValidationAlgorithm = $overrideEncryptionValidationAlg    
    Write-Host Got keys from $fileName
    Write-Host ""
  }
  catch
  {
      Write-Host -f Red Cannot locate Operations Manager Web Console information in $filename.
      Write-Host ""
      return;
  }
}

# Validate that we have inputs 
if ( !$hostUri -AND !$targetApplicationID -AND $hostErrorTimeout -eq 0 -AND !$encryptionKey -AND !$encryptionValidationKey -AND !$encryptionAlgorithm -AND !$encryptionValidationAlgorithm)
{
    Write-Host ""
    Write-Host -f Red "ERROR: No values specified. You must specify one of the values for an Update to occur."
    return;
}

#find the SharePoint Admin Site on this machine
[system.reflection.assembly]::LoadWithPartialName("Microsoft.SharePoint") > $null
$ca = [Microsoft.SharePoint.Administration.SPAdministrationWebApplication]::Local
$spWeb = $ca.Sites[0].OpenWeb()
Write-Host Connecting to Admin Site at: $spWeb.Url
Write-Host ""
try
{
  $spList = $spWeb.GetList("/Lists/Operations Manager Web Console Environments") 
  #build up our query
  $caml = "<Where><Eq><FieldRef Name='Title' /><Value Type='Text'>" + $title + "</Value></Eq></Where>"
  $query=new-object Microsoft.SharePoint.SPQuery
  $query.Query=$caml
  $queriedItems = $spList.GetItems($query)
  if ( $queriedItems.Count -gt 0 )
  {
    $spListItem = $queriedItems[0]
    # Set the values supplied 
    if ( $hostUri )
    {
      $spListItem["HostUri"] = $hostUri
    }
    if ( $targetApplicationID )
    {
      $spListItem["TargetApplicationID"] = $targetApplicationID
    }
    if ( $hostErrorTimeout -ne 0 )
    {
      $spListItem["HostErrorTimeout"] = $hostErrorTimeout
    }
    if ( $encryptionKey  )
    {
      $spListItem["EncryptionAlgorithmKey"] = $encryptionKey
    }
    if ( $encryptionAlgorithm)
    {
      $spListItem["EncryptionAlgorithm"] = $encryptionAlgorithm
    }
    if ( $encryptionValidationKey )
    {
      $spListItem["EncryptionValidationAlgorithmKey"] = $encryptionValidationKey
    }
    if ( $encryptionValidationAlgorithm )
    {
      $spListItem["EncryptionValidationAlgorithm"] = $encryptionValidationAlgorithm
    }
    $spListItem.Update() 
    Write-Host ""
    Write-Host -f Green SUCCESS: Updated the Operations Manager Web Console Environment named [$title] with values: 
    if ( $hostUri ) 
    {
      Write-Host -f Yellow HostUri=$hosturi
    }
    if ( $targetApplicationID )
    {
      Write-Host -f Yellow TargetApplicationID=$targetApplicationID
    }
    if ( $hostErrorTimeout -ne 0 )
    {
      Write-Host -f Yellow HostErrorTimeout=$hostErrorTimeout
    }
    if ( $encryptionKey )
    {
      Write-Host -f Yellow EncryptionAlgorithmKey=$encryptionKey
    }
    if ( $encryptionAlgorithm )
    {
      Write-Host -f Yellow EncryptionAlgorithm=$encryptionAlgorithm
    }
    if ( $encryptionValidationKey )
    {
      Write-Host -f Yellow EncryptionValidationAlgorithmKey=$encryptionValidationKey
    }
    if ( $encryptionValidationAlgorithm )
    {
      Write-Host -f Yellow EncryptionValidationAlgorithm=$encryptionValidationAlgorithm
    }
  }
  else
  {
    Write-Host -f Red ERROR: Could not locate the environment $title 
   }
}
catch
{
  Write-Host -f Red $_
  return;
}



# SIG # Begin signature block
# MIIa5AYJKoZIhvcNAQcCoIIa1TCCGtECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUinZouq+eZZ8V2jCu3gU8XM3P
# iiygghWCMIIEwzCCA6ugAwIBAgITMwAAACs5MkjBsslI8wAAAAAAKzANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTIwOTA0MjExMjM0
# WhcNMTMxMjA0MjExMjM0WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OkMwRjQtMzA4Ni1ERUY4MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAprYwDgNlrlBa
# hmuFn0ihHsnA7l5JB4XgcJZ8vrlfYl8GJtOLObsYIqUukq3YS4g6Gq+bg67IXjmM
# wjJ7FnjtNzg68WL7aIICaOzru0CKsf6hLDZiYHA5YGIO+8YYOG+wktZADYCmDXiL
# NmuGiiYXGP+w6026uykT5lxIjnBGNib+NDWrNOH32thc6pl9MbdNH1frfNaVDWYM
# Hg4yFz4s1YChzuv3mJEC3MFf/TiA+Dl/XWTKN1w7UVtdhV/OHhz7NL5f5ShVcFSc
# uOx8AFVGWyiYKFZM4fG6CRmWgUgqMMj3MyBs52nDs9TDTs8wHjfUmFLUqSNFsq5c
# QUlPtGJokwIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFKUYM1M/lWChQxbvjsav0iu6
# nljQMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAH7MsHvlL77nVrXPc9uqUtEWOca0zfrX/h5ltedI85tGiAVm
# aiaGXv6HWNzGY444gPQIRnwrc7EOv0Gqy8eqlKQ38GQ54cXV+c4HzqvkJfBprtRG
# 4v5mMjzXl8UyIfruGiWgXgxCLBEzOoKD/e0ds77OkaSRJXG5q3Kwnq/kzwBiiXCp
# uEpQjO4vImSlqOZNa5UsHHnsp6Mx2pBgkKRu/pMCDT8sJA3GaiaBUYNKELt1Y0Sq
# aQjGA+vizwvtVjrs73KnCgz0ANMiuK8icrPnxJwLKKCAyuPh1zlmMOdGFxjn+oL6
# WQt6vKgN/hz/A4tjsk0SAiNPLbOFhDvioUfozxUwggTsMIID1KADAgECAhMzAAAA
# sBGvCovQO5/dAAEAAACwMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTEzMDEyNDIyMzMzOVoXDTE0MDQyNDIyMzMzOVowgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAOivXKIgDfgofLwFe3+t7ut2rChTPzrbQH2zjjPmVz+l
# URU0VKXPtIupP6g34S1Q7TUWTu9NetsTdoiwLPBZXKnr4dcpdeQbhSeb8/gtnkE2
# KwtA+747urlcdZMWUkvKM8U3sPPrfqj1QRVcCGUdITfwLLoiCxCxEJ13IoWEfE+5
# G5Cw9aP+i/QMmk6g9ckKIeKq4wE2R/0vgmqBA/WpNdyUV537S9QOgts4jxL+49Z6
# dIhk4WLEJS4qrp0YHw4etsKvJLQOULzeHJNcSaZ5tbbbzvlweygBhLgqKc+/qQUF
# 4eAPcU39rVwjgynrx8VKyOgnhNN+xkMLlQAFsU9lccUCAwEAAaOCAWAwggFcMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBRZcaZaM03amAeA/4Qevof5cjJB
# 8jBRBgNVHREESjBIpEYwRDENMAsGA1UECxMETU9QUjEzMDEGA1UEBRMqMzE1OTUr
# NGZhZjBiNzEtYWQzNy00YWEzLWE2NzEtNzZiYzA1MjM0NGFkMB8GA1UdIwQYMBaA
# FMsR6MrStBZYAck3LjMWFrlMmgofMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY0NvZFNpZ1BDQV8w
# OC0zMS0yMDEwLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljQ29kU2lnUENBXzA4LTMx
# LTIwMTAuY3J0MA0GCSqGSIb3DQEBBQUAA4IBAQAx124qElczgdWdxuv5OtRETQie
# 7l7falu3ec8CnLx2aJ6QoZwLw3+ijPFNupU5+w3g4Zv0XSQPG42IFTp8263Os8ls
# ujksRX0kEVQmMA0N/0fqAwfl5GZdLHudHakQ+hywdPJPaWueqSSE2u2WoN9zpO9q
# GqxLYp7xfMAUf0jNTbJE+fA8k21C2Oh85hegm2hoCSj5ApfvEQO6Z1Ktwemzc6bS
# Y81K4j7k8079/6HguwITO10g3lU/o66QQDE4dSheBKlGbeb1enlAvR/N6EXVruJd
# PvV1x+ZmY2DM1ZqEh40kMPfvNNBjHbFCZ0oOS786Du+2lTqnOOQlkgimiGaCMIIF
# vDCCA6SgAwIBAgIKYTMmGgAAAAAAMTANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZIm
# iZPyLGQBGRYDY29tMRkwFwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQD
# EyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMTAwODMx
# MjIxOTMyWhcNMjAwODMxMjIyOTMyWjB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJyWVwZMGS/HZpgICBC
# mXZTbD4b1m/My/Hqa/6XFhDg3zp0gxq3L6Ay7P/ewkJOI9VyANs1VwqJyq4gSfTw
# aKxNS42lvXlLcZtHB9r9Jd+ddYjPqnNEf9eB2/O98jakyVxF3K+tPeAoaJcap6Vy
# c1bxF5Tk/TWUcqDWdl8ed0WDhTgW0HNbBbpnUo2lsmkv2hkL/pJ0KeJ2L1TdFDBZ
# +NKNYv3LyV9GMVC5JxPkQDDPcikQKCLHN049oDI9kM2hOAaFXE5WgigqBTK3S9dP
# Y+fSLWLxRT3nrAgA9kahntFbjCZT6HqqSvJGzzc8OJ60d1ylF56NyxGPVjzBrAlf
# A9MCAwEAAaOCAV4wggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMsR6MrS
# tBZYAck3LjMWFrlMmgofMAsGA1UdDwQEAwIBhjASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBT90TFO0yaKleGYYDuoMW+mPLzYLTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTAfBgNVHSMEGDAWgBQOrIJgQFYnl+UlE/wq4QpTlVnk
# pDBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEE
# SDBGMEQGCCsGAQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY3Jvc29mdFJvb3RDZXJ0LmNydDANBgkqhkiG9w0BAQUFAAOCAgEAWTk+
# fyZGr+tvQLEytWrrDi9uqEn361917Uw7LddDrQv+y+ktMaMjzHxQmIAhXaw9L0y6
# oqhWnONwu7i0+Hm1SXL3PupBf8rhDBdpy6WcIC36C1DEVs0t40rSvHDnqA2iA6VW
# 4LiKS1fylUKc8fPv7uOGHzQ8uFaa8FMjhSqkghyT4pQHHfLiTviMocroE6WRTsgb
# 0o9ylSpxbZsa+BzwU9ZnzCL/XB3Nooy9J7J5Y1ZEolHN+emjWFbdmwJFRC9f9Nqu
# 1IIybvyklRPk62nnqaIsvsgrEA5ljpnb9aL6EiYJZTiU8XofSrvR4Vbo0HiWGFzJ
# NRZf3ZMdSY4tvq00RBzuEBUaAF3dNVshzpjHCe6FDoxPbQ4TTj18KUicctHzbMrB
# 7HCjV5JXfZSNoBtIA1r3z6NnCnSlNu0tLxfI5nI3EvRvsTxngvlSso0zFmUeDord
# EN5k9G/ORtTTF+l5xAS00/ss3x+KnqwK+xMnQK3k+eGpf0a7B2BHZWBATrBC7E7t
# s3Z52Ao0CW0cgDEf4g5U3eWh++VHEK1kmP9QFi58vwUheuKVQSdpw5OPlcmN2Jsh
# rg1cnPCiroZogwxqLbt2awAdlq3yFnv2FoMkuYjPaqhHMS+a3ONxPdcAfmJH0c6I
# ybgY+g5yjcGjPa8CQGr/aZuW4hCoELQ3UAjWwz0wggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TGCBMwwggTI
# AgEBMIGQMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xIzAh
# BgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBAhMzAAAAsBGvCovQO5/d
# AAEAAACwMAkGBSsOAwIaBQCggeUwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHv/
# sASXuguhpmv2sgpoK2XTSgPOMIGEBgorBgEEAYI3AgEMMXYwdKBWgFQAUwB5AHMA
# dABlAG0AIABDAGUAbgB0AGUAcgAgADIAMAAxADIAIABSADIAIAAtACAATwBwAGUA
# cgBhAHQAaQBvAG4AcwAgAE0AYQBuAGEAZwBlAHKhGoAYaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAOLX665cWwYfklLK4Aw2/zGQPmLn
# NcDz0nC2JxGbKPZbEjxkUoSBJsra5Qh8vtsHve+YUDVK26B6Y0erQPkpylF6yytR
# +3JnL/Rq7mmy/09hMUwjJIP09aOU6j1CxVRN1XR7gqSP5EaDNJs/+XrCkRQUBnen
# P41Vk1AlnP/iDbk9DEEJ1jpdLGrthzweEO05fwWJ+i2I1fe/ero675LGvwTp6bv/
# KNjREzNXHk/H5Xl8mz8r9VBtIs5xZahnhCQcF6Mo0Bne9EwGRCR9v13JLlaNboI4
# 2NhsXzeDTqpUdLsyR5FtjNawHL8GQBLpX95H5mQo5dQvcRZ8dYoWMLULJlehggIo
# MIICJAYJKoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBAhMzAAAAKzkySMGyyUjzAAAAAAArMAkGBSsOAwIaBQCgXTAYBgkqhkiG
# 9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xMzA5MDYyMzE5MDVa
# MCMGCSqGSIb3DQEJBDEWBBRZd3mT9TmPWhaB5b/oSj4F4afAhzANBgkqhkiG9w0B
# AQUFAASCAQCAvXMA7ozKtMfHaV7uFtAMt4V7xJnVchybsAZ+NyVbEZl1FtNn6qLk
# 7NWDoiosVZ7Ur8PPGdiH1ZuphVZ2f7jHwDMzkqC7NyWu8J4n1v80U7h0JbUM9dhb
# gVuB3FdtKkO3R5IyI4mHQL7j6j7vE9/ICX1pE/AecgVLAGjsdyOtco5N4EDsfvXJ
# sUmYrSmvlcOyGMz5V4AekDz2uMqjtQ/d3Gyn09068mAyAT3a3Q055+klKD9Bnebz
# ozDLh44C6MW+MgFged3egZSkAkCAg31P+xwTItD3fk1gr7/rY1TKOYFiyHPwz0rg
# XWMHZ0EP7F6zgmfK9ja8EEF22041gg0B
# SIG # End signature block
