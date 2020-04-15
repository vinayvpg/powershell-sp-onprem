<#  
.SYNOPSIS  
    Microsoft Corporation
    This script installs the Microsoft Operations Manager solution file for SharePoint.
.DESCRIPTION  
    Use this script to install the Operations Manager solution.
.NOTES  
    File Name  : install-OperationsManager-DashboardViewer.ps1
    Requires   : PowerShell Version 2.0  
.PARAMETER solutionPath  
    The directory for the Microsoft.EnterpriseManagement.SharePointIntegration.wsp.
.PARAMETER url
    An optional specifier for installing to a specific portal address or website.
    If not specified, the solution will be deployed to all web sites for the portal.
.EXAMPLE  
    Install to all sites and web applications for the farm.
    install-OperationsManager-DashboardViewer.ps1 "c:\Program Files\System Center Operations Manager 2012\" [ENTER]
    
    Install to a specific site or web application in the farm.
    install-OperationsManager-DashboardViewer.ps1 "c:\Program Files\System Center Operations Manager 2012\" http://localhost:4096 [ENTER]
    
#>      
param([string]$solutionPath, [string]$url)

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

# Finds an assembly in the Global Assembly Cache
function FindGACFile($fileName)
{
  $files = Get-ChildItem -Recurse $env:windir\Assembly $fileName
  if ($files -ne $null){
    return $True;
  }
  else
  {
    return $False;
  }
}

# write out our banner
Write-Host ""
Write-Host -f Green "Microsoft Operations Manager - SharePoint Integration Solution Deployment Script v1.0"
Write-Host ""

$snapin="Microsoft.SharePoint.PowerShell"
if (get-pssnapin $snapin -ea "silentlycontinue") {
    write-host -f Green "PSsnapin $snapin is loaded"
}
elseif (get-pssnapin $snapin -registered -ea "silentlycontinue") {
    write-host -f Green "PSsnapin $snapin is registered"
    Add-PSSnapin $snapin
    write-host -f Green "PSsnapin $snapin is loaded"
}
else {
    write-host -f orange "PSSnapin $snapin not found" -foregroundcolor Red
}

# Check for Already Installed 
#$file = Get-ChildItem $solution
#$solutionID = $file.Name;
$solutionID = "Microsoft.EnterpriseManagement.SharePointIntegration.wsp";
$farm = Get-SPFarm
$sol = $farm.Solutions[$solutionID]
if ($sol)
{
  Write-Host "";
  Write-Host -f Red "ERROR: The solution $solutionID is already installed.  You can not install the solution when it is already deployed.";
  Write-Host "";
  return;
}

Write-Host -f Green "Install-Deploy.";
# Prompt for the $solutionPath
if ( $solutionPath -eq "" ) {
    Write-Host "";
    Write-Host -f White  "Type the name of the folder that contains the Microsoft.EnterpriseManagement.SharePointIntegration.wsp solution file: "
    Write-Host -f Yellow "     CTRL-C to cancel:"
	  $solutionPath = Read-Host 
}
if ( $solutionPath -eq "")
{
    Write-Host -f Red "No solution path specified, must specify the folder that contains the Microsoft.EnterpriseManagement.SharePointIntegration.wsp file";
    return;
}

# fetch the path
$temp = AddPathChar($solutionPath);

# set the solution name
$solution = [string]::Concat( $temp, "Microsoft.EnterpriseManagement.SharePointIntegration.wsp");
$sleeptime = 2

# Make sure SharePoint Admin service is started
$SPAdminSvc = Get-Service | where {$_.Name -eq "SPAdminV4"}
if ( $SPAdminSvc.Status -eq "Stopped" )
{
   Start-Service -Name $SPAdminSvc.Name
}
# Make sure SharePoint Timer service is started
$SPTimerSvc = Get-Service | where {$_.Name -eq "SPTimerV4"}
if ( $SPTimerSvc.Status -eq "Stopped" )
{
   Start-Service -Name $SPTimerSvc.Name
}

# Prompt for the Host
if ( $url -eq $null -OR $url -eq "" ) {
    Write-Host "";
    Write-Host -f White "Type the SharePoint Portal Siteurl: ";
    Write-Host -f Yellow "[ENTER] to install for all Sites. CTRL-C to Cancel.";
	  $url = Read-Host 
}

if ( $url -eq $null -OR $url -eq "" ) {
  Write-Host ""
  Write-Host -f Green "Operation applies to all sites."
  Write-Host ""
}
else
{
  Write-Host ""
  Write-Host -f Green "Portal Site is at: $url"
  Write-Host ""
}


Write-Host -f Yellow "Scanning for previous installation remnants...please wait`n";


$fileErrorMessage = "";
# Test for an existing WebPart assembly file in the GAC
if ( FindGACFile("Microsoft.EnterpriseManagement.SharePointIntegration.dll"))
{
  $fileErrorMessage = "Microsoft.EnterpriseManagement.SharePointIntegration.DLL";
}
# Test for the Crypto DLL in the GAC 
if ( FindGACFile("Microsoft.EnterpriseManagement.Presentation.Security.Cryptography.dll"))
{
  $fileErrorMessage = [string]::Concat( $fileErrorMessage, "`nMicrosoft.EnterpriseManagement.Presentation.Security.Cryptography.dll");
}

if ( $fileErrorMessage -ne $null -AND $fileErrorMessage -ne "")
{
    Write-Host -f Red "ERROR: Remnant files exist in the GAC, please remove and re-run the installation script."
    Write-Host -f Red "";
    Write-Host -f Yellow "The un-installation script (uninstall-OperationsManager-DashboardViewer.ps1) of the Dashboard Viewer can leave remnants in the Global Assembly Cache.";
    Write-Host -f Yellow "The files listed below can become locked or placed into Temp folders under the GAC.";
    Write-Host -f Yellow "To remove these files it is necessary to quit out of the Powershell.";
    Write-Host -f Yellow "Stop (SharePoint 2010 Timer) service (net stop SPTimerv4).";
    Write-Host -f Yellow "Stop (Internet Information Services) (net stop w3svc).";
    Write-Host -f Yellow "Then manually delete the files listed from: $env:windir\Assembly.";
    Write-Host -f Yellow "Then manually restart the (Sharepoint 2010 Timer) service (net start SPTimerv4).";
    Write-Host -f Yellow "Then manually restart the (Internet Information Services) (net start w3svc or IISReset).";
    Write-Host -f Yellow "Remnant files found...";
    Write-Host $fileErrorMessage;
    return;
}

Write-Host -f Green "SUCCESS: No remnant files found.`n";


Write-Host ""
Write-Host -f Green "Going to Add new version of $solutionID"
Write-Host ""

Add-SPSolution $solution

Write-Host ""

if ( $url -eq $null -OR $url -eq "" ) {
    Write-Host -f Green "Going to Deploy $solutionID"
    Write-Host ""
    Install-SPSolution -Identity $solutionID -GacDeployment -CasPolicies -AllWebApplications -Force
}
else {
    Write-Host -f Green "Going to Deploy $solutionID to $url"
    Write-Host ""
    Install-SPSolution -Identity $solutionID -GacDeployment -CasPolicies -Force -Webapplication $url
}

Write-Host ""

$sol = $farm.Solutions[$solutionID]

while( $sol.JobExists ) {
    write-host -f yellow " waiting for deployment."
    sleep $sleeptime
}

Write-Host ""
Write-Host -f Green $solutionID deployed $sol.Deployed
Write-Host ""

# ENABLE the feature for all web sites
Write-Host ""
Write-Host -f Green Enabling Features for $solutionID
Write-Host ""
$webApp = Get-SPWebApplication
$webApp | Get-SPSite -limit all | ForEach-Object {Enable-SPFeature -Identity "a228ed17-bc22-4966-bb80-0acf59d99e1e" -Url $_.Url -Force -Confirm:0; Write-Host $_.Url}

Write-Host ""
Write-Host -f Green Features enabled for $solutionID
Write-Host ""




# SIG # Begin signature block
# MIIa5AYJKoZIhvcNAQcCoIIa1TCCGtECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQURFg7tsdcbOS2mcYLerqF5FSA
# Xd6gghWCMIIEwzCCA6ugAwIBAgITMwAAACs5MkjBsslI8wAAAAAAKzANBgkqhkiG
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
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFA5x
# PNN8vK2uW1SanrSMApJBhY0oMIGEBgorBgEEAYI3AgEMMXYwdKBWgFQAUwB5AHMA
# dABlAG0AIABDAGUAbgB0AGUAcgAgADIAMAAxADIAIABSADIAIAAtACAATwBwAGUA
# cgBhAHQAaQBvAG4AcwAgAE0AYQBuAGEAZwBlAHKhGoAYaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAIPHAGG+IaLOrXHhqG8nZ1XKNrop
# akU6zvjM//lAOv1WiOKDpQ9z/0DWWExIqaqDdve1NpZSaeL22MTjKIcfrw2PT2Eo
# 8shj3T619AQu7Xuz5s5zQDD4uLXr1VJvTXWPeuUmTdv+lo5uxWsHfGvHb73Fov13
# BsGJRccNCe10tp5Lz+oPMmAznZdqxswvUXAMaMwMnAhbFyw8waRP9GCdm2lyWXYX
# dhsWal4xznPYXvoW5k9T4M2fnEFpvr2/okBk97OkbKRqdAgtEVE5MAObpvFHwRd1
# xaENCuWznlTZ7O5rMmJ8K+q1Z64DwCSowoWwSws8kyrQV7SpC8IW5qNSUOqhggIo
# MIICJAYJKoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBAhMzAAAAKzkySMGyyUjzAAAAAAArMAkGBSsOAwIaBQCgXTAYBgkqhkiG
# 9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xMzA5MDYyMzE5MDVa
# MCMGCSqGSIb3DQEJBDEWBBT5sWVpaAgnm7u2YfUQJJMhrYd4EjANBgkqhkiG9w0B
# AQUFAASCAQB+BqXnMC+Y7dKslk3vSW/dEtS3zwJxegV07jAZLQ1en08qor7MuUNZ
# gydRqgJS+f4f+4vgqXg2PvsNdgP2rllwmTl/bwW3VFEq0FGGR+WlNUqry0BqMBWo
# Z89RkRt4etRjmOAaYJPs6sPqzhk54aDxQw5jv6vfRz6q0kET1LxkTX8fHQf4fUH4
# kO0n65XISw2PZy3SKyU6ypJ7o0ElvRZp2TNE74alXuIrhDB27oaRs9t2PRRIQjkp
# fqijXXVW47vR5ApG+2dHixe374wYGm6yVINRct01uxZlkCLd0p7LTG+iIBt3dl7h
# OGLfof0ISQh0txjYUt32jp0TiROJxJiF
# SIG # End signature block
