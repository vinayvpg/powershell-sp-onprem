        if ((Get-PSSnapin -Name "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) {
            Add-PSSnapin -Name "Microsoft.SharePoint.PowerShell"
        } 

cls

#Connect to the O365 Tenant
Write-Host "Please Conenct to the Microsoft Online tenant you wish to validate this on premises farm with" -ForegroundColor Yellow
Connect-MsolService 

#Validate Certificate is not expired - checks all Msol Principals not just current farm
Write-Host "Validating MSOL Principals still within valid date range" -ForegroundColor Yellow
Write-Host
Write-Host "Collecting All MSOL Principals" -ForegroundColor Yellow
$MsolSPC = Get-MsolServicePrincipalCredential -AppPrincipalId "00000003-0000-0ff1-ce00-000000000000" -ReturnKeyValues:$false|ft startdate,enddate ,keyid -autosize 
Write-Host
# Validate that the local STS Signing Certificate matches a valid Microsoft Online Service Principal
Write-Host "Validating that the local STS Signing Certificate matches a valid Microsoft Online Service Principal" -ForegroundColor Yellow

$StsThumbprint = (Get-SPSecurityTokenServiceConfig).LocalLoginProvider.SigningCertificate.thumbprint
#Changed to /sharepoint
$StsCertificate = get-item -Path CERT:\localmachine\SharePoint\$StsThumbprint
$StsCertificateBin = $StsCertificate.GetRawCertData()
$StsCredentialValue = [System.Convert]::ToBase64String($StsCertificateBin)
$MsolServicePrincipalCredential = Get-MsolServicePrincipalCredential -AppPrincipalId "00000003-0000-0ff1-ce00-000000000000" -ReturnKeyValues $true | Where-Object {$_.Value -eq $StsCredentialValue}

if($MsolServicePrincipalCredential){
    
    # Check for valid date 
    if($MsolServicePrincipalCredential.EndDate -gt (get-date) -and $MsolServicePrincipalCredential.StartDate -le (get-date)){
       	Write-Host
       	write-host "Msol Service Principal is found and is Valid until :"$MsolServicePrincipalCredential.EndDate -ForegroundColor Green
    } else {
      	Write-Host
       	write-host "Msol Service Principal is found but expired on " + $MsolServicePrincipalCredential.EndDate + " You should update the ACS trust certificates for hybrid workloads to function"  -ForegroundColor Yellow
    }
	
} else {
    Write-Host
    Write-host "No matching Msol Service Principal found for the local farm. Hybrid workloads will not function correctly on this farm" -foregroundcolor Red
}

   
#Validate SPNs setup properly in WAAD
Write-Host
Write-Host "Validating that the Microsoft online Service Principal Names are correct" -ForegroundColor Yellow
$apps = (Get-MsolServicePrincipal -AppPrincipalId "00000003-0000-0ff1-ce00-000000000000").serviceprincipalnames
#$apps
$webapps = Get-SPWebApplication
$foundmatch = $false
Foreach($WebApp in $WebApps){

	$webappurl = (($WebApp.url).split(":")).split("//")
	Write-Host $("`$WebApp.Url: " + $WebApp.url)
	
	Foreach($app in $apps){

		$spn = ((($app).split("/")) -replace "\*.", "")
		#Write-Host $("spn: " + $spn)
		
		Write-Host $("`$webappurl[3]: " + $webappurl[3]) -foregroundcolor Cyan
		Write-Host $("`$spn[1]      : " + $spn[1]) -foregroundcolor Cyan
		
		if(($webappurl[3] -match $spn[1]) -and ($spn[1] -ne $null )){
		    Write-Host
		    write-host "It seems the local farm has a matching SPN and URL combination " $webappurl[3] " matched with " $spn[1] " on this farm" -ForegroundColor Green
		    write-host "This is required for hybrid scenarios requiring outbound OAuthN" -ForegroundColor Green
		    $foundmatch=$true
		} else {
			Write-Host "No match" -ForegroundColor Yellow
		}
    }
}
if($foundmatch -eq $false){   #bspender: replaced "=" with "-eq"
    Write-Host
    write-host "No matching SPN and URL combinations found on this farm" -ForegroundColor Red
}

# Validate Directory Synchronization
Write-Host "Checking Directory Synchronization is Operational" -ForegroundColor Yellow
$msolcompany = Get-MsolCompanyInformation
$IsDirSyncEnabled = $msolcompany.DirectorySynchronizationEnabled
if ($IsDirSyncEnabled) {
	Write-Host "Directory Sync -> Enabled: " $IsDirSyncEnabled -ForegroundColor Green
	Write-Host
	$LastDirsynctime = $msolcompany.LastDirSyncTime
	Write-Host "Last Directory Sync Time" $LastDirsynctime -ForegroundColor Green
	Write-Host
} else {
	Write-Host "Directory Sync is not currently enabled!" -ForegroundColor Red
}

Write-Host "Checking license state of users" -ForegroundColor Yellow
#$licensed = Get-MsolUser | ?{$_.IsLicensed -eq $true}
$licensed = Get-MsolUser -All | ?{$_.IsLicensed -eq $true}

#$unlicensed = Get-MsolUser | ?{$_.IsLicensed -eq $false}
$unlicensed = Get-MsolUser -UnlicensedUsersOnly -All  #is this equivalent?

#$licenses = (MSOnline\Get-MsolSubscription).TotalLicenses
$licenses = (Get-MsolSubscription).TotalLicenses

Write-Host "Total number of licensed users is " $licensed.count -ForegroundColor Green
Write-Host "Total number of unlicensed users is " $unlicensed.count -ForegroundColor Green
Write-Host "Total number of purchased licenses is " $licenses -ForegroundColor Green
Write-Host

#Validate Service Applications
Write-Host "Checking On Premises Services" -ForegroundColor Yellow
$upa=Get-SPServiceApplication | where-object {$_.TypeName -match "User profile Service Application"} 
if ($upa -ne $null -and $upa.Status -eq "online") {
Write-Host ("User Profile Service Application is available with status ") $upa.status -ForegroundColor Green
}
elseif ($upa -ne $null -and $upa.Status -ne "online"){
Write-Host ("User Profile Service Application is availble but status is ") $upa.status -ForegroundColor Red
}
else{
Write-Host ("User Profile Service Application is not available. ") $upa.status -ForegroundColor Red
}
Write-Host
$app=Get-SPServiceApplication | where-object {$_.TypeName -match "App Management Service Application"} 

if ($app -ne $null -and $app.Status -eq "online") {
Write-Host ("App Management Service Application is available with status ") $app.status -ForegroundColor Green
}
elseif ($app -ne $null -and $app.Status -ne "online"){
Write-Host ("App Management  Service Application is available but status is ") $app.status -ForegroundColor Red
}
else{
Write-Host ("App Management  Service Application is not available. ") $app.status -ForegroundColor Red
}
Write-Host
Write-Host "Checking On Proxies" -ForegroundColor Yellow

#Validate ACS Proxy

$proxy =Get-SPServiceApplicationProxy | ? {$_.TypeName -eq "Azure Access Control Service Application Proxy"}
if ($proxy -ne $null -and $proxy.Status -eq "online") {
Write-Host ("ACS proxy is available with status ") $proxy.status -ForegroundColor Green
}
elseif ($proxy -ne $null -and $proxy.Status -ne "online"){
Write-Host ("ACS proxy is available but status is ") $proxy.status -ForegroundColor Red
}
else{
Write-Host ("ACS proxy is  not available. ") -ForegroundColor Red
}

Write-Host
# Validate SPO proxy
$spoProxy = Get-SPServiceApplicationProxy | ? {$_.TypeName -eq "SharePoint Online Application Principal Management Service Application Proxy"}
if ($spoproxy -ne $null -and $spoproxy.Status -eq "online") {
Write-Host ("SPO proxy is available with status ") $spoProxy.status -ForegroundColor Green
}
elseif ($spoproxy -ne $null -and $spoproxy.Status -ne "online"){
Write-Host ("SPO proxy is available but status is ") $spoProxy.status -ForegroundColor Red
}
else{
Write-Host ("SPO proxy is  not available. ") -ForegroundColor Red
}


# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBotV5STGYpmhfR
# t4pBCHzungS7QNvPbP3V337t0kKCCqCCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIKEmBNJN37UHIo57E4Yj7tM/+Ch4T0LR1ebbeCkFAkaKMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBALbxsOwJISjROu0B0oyio/7m
# 5ZSDp8vfcdwRn2Ve+VIPNrjOk4InXqEjhnaVXLnq4tCx9g9ATkxfI4rZ5rqodwA9
# u31hLEhgfxz+wYlYhO3iEtV9lU3rGIAkqr1LI0ph0sJnVd7tGjh13AAW7KQEdXYZ
# oWL5GrniZBPY4TPmkqywlLW2GqQ/PDvYRH4/ZJMIiXMvqIQblA4jDgQ2SH6kNmcp
# wLNaLhthC8NtOwu9WYKigUQhL55JgCfg/X3u6wrNhhBV/j9tyi2hhdbH08WEJaOl
# 25wzZkUpOKQY5qNys49sT0ljCn/YdfS/LZyM6idJ7b4hZuzJ+zVB2S377boqlKOh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgDbVyxuohJ53hRs7zEDWQ
# gqjPGbHuiSpCpdWix0qClHsCBljVOtTHsxgTMjAxNzA0MjYyMzUzNDQuODQ3WjAH
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
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIPKVza4YYqYCSVqC
# mwYDojLMOChHDfuP0yuhBqGew90uMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUvf/FlWOQ8ROcYNYZwK/puJ4eIB0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAALI1BWg3IhwNpwAAAAAAsjAWBBSRrnb7XKTtB5IW
# rfee9hkzrTNhXzANBgkqhkiG9w0BAQsFAASCAQCSNG0ZesHqHP5xyhVygjptiN2m
# U6XTCsLitfFiPZ3ckoAljLZEyCRpliRmDOnZ9Y69QDfrdmCv4LWt3HARbVMJS02Z
# 395NikZgPOWG6x3dtV4qHtTpzRs+jYmsneGHTjW0QKIWOcj8eiR/N3AJGd6cd9Vj
# KnRuSQ134L79qjIptnMnMzvfbCdA/HG7knS93AYAKZkKqLbiXYEtYL/zmQmsqu/d
# 2HbiHBS5vdwbclHepmRcSABcDIXoByJRmYXLQ6qEy9pYpdFaC1KmRqVY8q0+vgwU
# sFUggNrTF8Ug3WsT+dY8HXtZzXL0XTVg1ykXSOXqzDYcKSdiKxHklvqGtPCj
# SIG # End signature block
