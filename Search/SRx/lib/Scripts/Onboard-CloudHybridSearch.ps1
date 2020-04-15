<#
.SYNOPSIS
    When you run this script you onboard your SharePoint Online (SPO) tenant and your SharePoint server cloud SSA to cloud hybrid search.
    This includes setting up server to server authentication between SharePoint Online and SharePoint Server
.PARAMETER PortalUrl
    SharePoint Online portal URL, for example 'https://contoso.sharepoint.com'.
.PARAMETER CloudSsaId
    Name or id (Guid) of the cloud Search service application, created with the CreateCloudSSA script.
.PARAMETER Credential
    Logon credential for tenant admin. Will prompt for credential if not specified.

.NOTES
    TODO
    - Check that SCS URLs are accessible
        need to invoke as service account
    	*.search.msit.us.trafficmanager.net
		*.search.production.us.trafficmanager.net
		*.search.production.emea.trafficmanager.net
		*.search.production.apac.trafficmanager.net
        https://usfrontendexternal.search.production.us.trafficmanager.net/
#>
Param(
    [Parameter(Mandatory=$true, HelpMessage="SharePoint Online portal URL, for example 'https://contoso.sharepoint.com'.")]
    [ValidateNotNullOrEmpty()]
    [string] $PortalUrl,

    [Parameter(Mandatory=$false, HelpMessage="Name or id (Guid) of the cloud Search service application, created with the CreateCloudSSA script.")]
    [ValidateNotNullOrEmpty()]
    [string] $CloudSsaId,
    
    [Parameter(Mandatory=$false, HelpMessage="Logon credential for tenant admin. Will be prompted if not specified.")]
    [PSCredential] $Credential
)

if ($ACS_APPPRINCIPALID -eq $null) {
    New-Variable -Option Constant -Name ACS_APPPRINCIPALID -Value '00000001-0000-0000-c000-000000000000'
    New-Variable -Option Constant -Name ACS_HOST -Value "accounts.accesscontrol.windows.net"
    New-Variable -Option Constant -Name PROVISIONINGAPI_WEBSERVICEURL -Value "https://provisioningapi.microsoftonline.com/provisioningwebservice.svc"
    New-Variable -Option Constant -Name SCS_AUTHORITIES -Value @(
        "*.search.msit.us.trafficmanager.net",
        "*.search.production.us.trafficmanager.net",
        "*.search.production.emea.trafficmanager.net",
        "*.search.production.apac.trafficmanager.net"
    )
}

New-Variable -Option Constant -Name SCS_APPPRINCIPALID -Value '8f0dc9ad-0d19-4fec-a421-6d0279080014'
New-Variable -Option Constant -Name SCS_APPPRINCIPALDISPLAYNAME -Value 'Search Content Service'
New-Variable -Option Constant -Name SP_APPPRINCIPALID -Value '00000003-0000-0ff1-ce00-000000000000'
New-Variable -Option Constant -Name SPO_MANAGEMENT_APPPROXY_NAME -Value 'SPO App Management Proxy'
New-Variable -Option Constant -Name ACS_APPPROXY_NAME -Value 'ACS'
New-Variable -Option Constant -Name ACS_STS_NAME -Value 'ACS-STS'
New-Variable -Option Constant -Name AAD_METADATAEP_FSTRING -Value 'https://{0}/{1}/metadata/json/1'

$SP_VERSION = "15"
$regKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office Server\15.0\Search" -ErrorAction SilentlyContinue
if ($regKey -eq $null) {
    $regKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office Server\16.0\Search" -ErrorAction SilentlyContinue
    if ($regKey -eq $null) {
        throw "Unable to detect SharePoint installation."
    }
    $SP_VERSION = "16"
}

Write-Host "Configuring for SharePoint Server version $SP_VERSION."

function Configure-LocalSharePointFarm
{
    Param(
        [Parameter(Mandatory=$true)][string] $Realm
    )

    # Set up to authenticate as AAD realm
    Set-SPAuthenticationRealm -Realm $Realm

    $acsMetadataEndpoint = $AAD_METADATAEP_FSTRING -f $ACS_HOST,$Realm
    $acsMetadataEndpointUri = [System.Uri] $acsMetadataEndpoint
    $acsMetadataEndpointUriSlash = [System.Uri] "$($acsMetadataEndpoint)/"
    Write-Host "ACS metatada endpoint: $acsMetadataEndpoint"

    # ACS Proxy
    $acsProxy = Get-SPServiceApplicationProxy | ? {
        $_.TypeName -eq "Azure Access Control Service Application Proxy" -and
        (($_.MetadataEndpointUri -eq $acsMetadataEndpointUri) -or ($_.MetadataEndpointUri -eq $acsMetadataEndpointUriSlash))
    }
    if ($acsProxy -eq $null) {
        Write-Host "Setting up ACS proxy..." -Foreground Yellow
        $acsProxy = Get-SPServiceApplicationProxy | ? {$_.DisplayName -eq $ACS_APPPROXY_NAME}
        if ($acsProxy -ne $null) {
            throw "There is already a service application proxy registered with name '$($acsProxy.DisplayName)'. Remove manually and retry."
        }
        $acsProxy = New-SPAzureAccessControlServiceApplicationProxy -Name $ACS_APPPROXY_NAME -MetadataServiceEndpointUri $acsMetadataEndpointUri -DefaultProxyGroup
    } elseif ($acsProxy.Count > 1) {
        throw "Found multiple existing ACS proxies for this metadata endpoint."
    } else {
        Write-Host "Found existing ACS proxy '$($acsProxy.DisplayName)'." -Foreground Green
    }

    # The proxy must be in default group and set as default for authentication to work
    if (((Get-SPServiceApplicationProxyGroup -Default).DefaultProxies | select Id).Id -notcontains $acsProxy.Id) {
        throw "ACS proxy '$($acsProxy.DisplayName)' is not set as the default. Configure manually through Service Application Associations admin UI and retry."
    }

    # Register ACS token issuer
    $acsTokenIssuer = Get-SPTrustedSecurityTokenIssuer | ? {
        (($_.MetadataEndPoint -eq $acsMetadataEndpointUri) -or ($_.MetadataEndPoint -eq $acsMetadataEndpointUriSlash))
    }
    if ($acsTokenIssuer -eq $null) {
        Write-Host "Registering ACS as trusted token issuer..." -Foreground Yellow
        $acsTokenIssuer = Get-SPTrustedSecurityTokenIssuer | ? {$_.DisplayName -eq $ACS_STS_NAME}
        if ($acsTokenIssuer -ne $null) {
            throw "There is already a token issuer registered with name '$($acsTokenIssuer.DisplayName)'. Remove manually and retry."
        }
        try {
            $acsTokenIssuer = New-SPTrustedSecurityTokenIssuer -Name $ACS_STS_NAME -IsTrustBroker -MetadataEndPoint $acsMetadataEndpointUri -ErrorAction Stop
        } catch [System.ArgumentException] {
            Write-Warning "$($_)"
        }
    } elseif ($acsTokenIssuer.Count > 1) {
        throw "Found multiple existing token issuers for this metadata endpoint."
    } else {
        if ($acsTokenIssuer.IsSelfIssuer -eq $true) {
            Write-Warning "Existing trusted token issuer '$($acsTokenIssuer.DisplayName)' is configured as SelfIssuer."
        } else {
            Write-Host "Found existing token issuer '$($acsTokenIssuer.DisplayName)'." -Foreground Green
        }
    }

    # SPO proxy
    $spoProxy = Get-SPServiceApplicationProxy | ? {$_.TypeName -eq "SharePoint Online Application Principal Management Service Application Proxy" -and $_.OnlineTenantUri -eq [System.Uri] $PortalUrl}
    if ($spoProxy -eq $null) {
        Write-Host "Setting up SPO Proxy..." -Foreground Yellow
        $spoProxy = Get-SPServiceApplicationProxy | ? {$_.DisplayName -eq $SPO_MANAGEMENT_APPPROXY_NAME}
        if ($spoProxy -ne $null) {
            throw "There is already a service application proxy registered with name '$($spoProxy.DisplayName)'. Remove manually and retry."
        }
        $spoProxy = New-SPOnlineApplicationPrincipalManagementServiceApplicationProxy -Name $SPO_MANAGEMENT_APPPROXY_NAME -OnlineTenantUri $PortalUrl -DefaultProxyGroup
    } elseif ($spoProxy.Count > 1) {
        throw "Found multiple existing SPO proxies for this tenant URI."
    } else {
        Write-Host "Found existing SPO proxy '$($spoProxy.DisplayName)'." -Foreground Green
    }

    # The proxy should be in default group and set to default
    if (((Get-SPServiceApplicationProxyGroup -Default).DefaultProxies | select Id).Id -notcontains $spoProxy.Id) {
        throw "SPO proxy '$($spoProxy.DisplayName)' is not set as the default. Configure manually through Service Application Associations admin UI and retry."
    }

    return (Get-SPSecurityTokenServiceConfig).LocalLoginProvider.SigningCertificate
}

function Upload-SigningCredentialToSharePointPrincipal
{
    Param(
        [Parameter(Mandatory=$true)][System.Security.Cryptography.X509Certificates.X509Certificate2] $Cert
    )

    $exported = $Cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $certValue = [System.Convert]::ToBase64String($exported)

    $principal = Get-MsolServicePrincipal -AppPrincipalId $SP_APPPRINCIPALID
    $keys = Get-MsolServicePrincipalCredential -ObjectId $principal.ObjectId -ReturnKeyValues $true | ? Value -eq $certValue
    if ($keys -eq $null) {
        New-MsolServicePrincipalCredential -AppPrincipalId $SP_APPPRINCIPALID -Type Asymmetric -Value $certValue -Usage Verify
    } else {
        Write-Host "Signing credential already exists in SharePoint principal."
    }
}

function Add-ScsServicePrincipal
{
    $spns = $SCS_AUTHORITIES | foreach { "$SCS_APPPRINCIPALID/$_" }
    $principal = Get-MsolServicePrincipal -AppPrincipalId $SCS_APPPRINCIPALID -ErrorAction SilentlyContinue

    if ($principal -eq $null) {
        Write-Host "Creating new service principal for $SCS_APPPRINCIPALDISPLAYNAME with the following SPNs:"
        $spns | foreach { Write-Host $_ }
        $scspn = New-MsolServicePrincipal -AppPrincipalId $SCS_APPPRINCIPALID -DisplayName $SCS_APPPRINCIPALDISPLAYNAME -ServicePrincipalNames $spns
    } else {
        $update = $false
        $spns | foreach {
            if ($principal.ServicePrincipalNames -notcontains $_) {
                $principal.ServicePrincipalNames.Add($_)
                Write-Host "Adding new SPN to existing service principal: $_."
                $update = $true
            }
        }
        if ($update -eq $true) {
            Set-MsolServicePrincipal -AppPrincipalId $principal.AppPrincipalId -ServicePrincipalNames $principal.ServicePrincipalNames
        } else {
            Write-Host "Service Principal already registered, containing the correct SPNs."
        }
    }
}

function Prepare-Environment
{
    $MSOIdCRLRegKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\MSOIdentityCRL" -ErrorAction SilentlyContinue
    if ($MSOIdCRLRegKey -eq $null) {
        Write-Host "Online Services Sign-In Assistant required, install from http://www.microsoft.com/en-us/download/details.aspx?id=39267." -Foreground Red
    } else {
        Write-Host "Found Online Services Sign-In Assistant!" -Foreground Green
    }

    $MSOLPSRegKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\MSOnlinePowershell" -ErrorAction SilentlyContinue
    if ($MSOLPSRegKey -eq $null) {
        Write-Host "AAD PowerShell required, install from http://go.microsoft.com/fwlink/p/?linkid=236297." -Foreground Red
    } else {
        Write-Host "Found AAD PowerShell!" -Foreground Green
    }

    if ($MSOIdCRLRegKey -eq $null -or $MSOLPSRegKey -eq $null) {
        throw "Manual installation of prerequisites required."
    }

    Write-Host "Configuring Azure AD settings..." -Foreground Yellow

    $regkey = "HKLM:\SOFTWARE\Microsoft\MSOnlinePowerShell\Path"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\MSOIdentityCRL" -Name "ServiceEnvironment" -Value "Production"
    Set-ItemProperty -Path $regkey -Name "WebServiceUrl" -Value $PROVISIONINGAPI_WEBSERVICEURL
    Set-ItemProperty -Path $regkey -Name "FederationProviderIdentifier" -Value "microsoftonline.com"

    Write-Host "Restarting MSO IDCRL Service..." -Foreground Yellow

    # Service takes time to get provisioned, retry restart.
    for ($i = 1; $i -le 10; $i++) {
        try {
            Stop-Service -Name msoidsvc -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $svc = Get-Service msoidsvc
            $svc.WaitForStatus("Stopped")
            Start-Service -Name msoidsvc
        } catch {
            Write-Host "Failed to start msoidsvc service, retrying..."
            Start-Sleep -seconds 2
            continue
        }
        Write-Host "Service Restarted!" -Foreground Green
        break
    }
}

function Get-CloudSsa
{
    $ssa = $null

    if (-not $CloudSsaId) {
        $ssa = Get-SPEnterpriseSearchServiceApplication
        if ($ssa.Count -ne 1) {
            throw "Multiple SSAs found, specify which cloud SSA to on-board."
        }
    } else {
        $ssa = Get-SPEnterpriseSearchServiceApplication -Identity $CloudSsaId
    }

    if ($ssa -eq $null) {
        throw "Cloud SSA not found."
    }

    # Make sure SSA is created with CreateCloudSSA.ps1
    if ($ssa.CloudIndex -ne $true) {
        throw "The provided SSA is not set up for cloud hybrid search, please create a cloud SSA before proceeding with onboarding."
    }

    Write-Host "Using SSA with id $($ssa.Id)."
    $ssa.SetProperty("IsHybrid", 1)
    $ssa.Update()

    return $ssa
}

$code = @"
using System;
using System.Net;
using System.Security;
using Microsoft.SharePoint;
using Microsoft.SharePoint.Administration;
using Microsoft.SharePoint.Client;
using Microsoft.SharePoint.IdentityModel;
using Microsoft.SharePoint.IdentityModel.OAuth2;

static public class ClientContextHelper
{
    public static ClientContext GetAppClientContext(string siteUrl)
    {
        SPServiceContext serviceContext = SPServiceContext.GetContext(SPServiceApplicationProxyGroup.Default, SPSiteSubscriptionIdentifier.Default);
        using (SPServiceContextScope serviceContextScope = new SPServiceContextScope(serviceContext))
        {
            ClientContext clientContext = new ClientContext(siteUrl);
            ICredentials credentials = null;
            clientContext.ExecutingWebRequest += (sndr, request) =>
            {
                    request.WebRequestExecutor.RequestHeaders.Add(HttpRequestHeader.Authorization, "Bearer");
                    request.WebRequestExecutor.WebRequest.PreAuthenticate = true;
            };

            // Run elevated to get app credentials
            SPSecurity.RunWithElevatedPrivileges(delegate()
            {
               credentials = SPOAuth2BearerCredentials.Create();
            });

            clientContext.Credentials = credentials;

            return clientContext;
        }
    }
}
"@

$assemblies = @(
"System.Core.dll",
"System.Web.dll",
"Microsoft.SharePoint, Version=$SP_VERSION.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c",
"Microsoft.SharePoint.Client, Version=$SP_VERSION.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c",
"Microsoft.SharePoint.Client.Runtime, Version=$SP_VERSION.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c"
)

Add-Type -AssemblyName ("Microsoft.SharePoint.Client, Version=$SP_VERSION.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c")
Add-Type -AssemblyName ("Microsoft.SharePoint.Client.Search, Version=$SP_VERSION.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c")
Add-Type -AssemblyName ("Microsoft.SharePoint.Client.Runtime, Version=$SP_VERSION.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c")
Add-Type -TypeDefinition $code -ReferencedAssemblies $assemblies

Add-PSSnapin Microsoft.SharePoint.PowerShell

try
{
    Write-Host "Accessing Cloud SSA..." -Foreground Yellow
    $ssa = Get-CloudSsa

    Write-Host "Preparing environment..." -Foreground Yellow
    Prepare-Environment

    Import-Module MSOnline
    Import-Module MSOnlineExtended -force

    Write-Host "Connecting to O365..." -Foreground Yellow
    if ($Credential -eq $null) {
        $Credential = Get-Credential -Message "Tenant Admin credential"
    }
    Connect-MsolService -Credential $Credential -ErrorAction Stop
    $tenantInfo = Get-MsolCompanyInformation
    $AADRealm = $tenantInfo.ObjectId.Guid

    Write-Host "AAD tenant realm is $AADRealm."

    Write-Host "Configuring on-prem SharePoint farm..." -Foreground Yellow
    $signingCert = Configure-LocalSharePointFarm -Realm $AADRealm
    
    Write-Host "Adding local signing credential to SharePoint principal..." -Foreground Yellow
    Upload-SigningCredentialToSharePointPrincipal -Cert $signingCert

    Write-Host "Configuring service principal for the cloud search service..." -Foreground Yellow
    Add-ScsServicePrincipal

    Write-Host "Connecting to content farm in SPO..." -foreground Yellow
    $cctx = [ClientContextHelper]::GetAppClientContext($PortalUrl)
    $pushTenantManager = new-object Microsoft.SharePoint.Client.Search.ContentPush.PushTenantManager $cctx

    # Retry up to 4 minutes, mitigate 401 Unauthorized from CSOM
    Write-Host "Preparing tenant for cloud hybrid search (this can take a couple of minutes)..." -foreground Yellow
    for ($i = 1; $i -le 12; $i++) {
        try {
            $pushTenantManager.PreparePushTenant()
            $cctx.ExecuteQuery()
            Write-Host "PreparePushTenant was successfully invoked!" -Foreground Green
            break
        } catch {
            if ($i -ge 12) {
                throw "Failed to call PreparePushTenant, error was $($_.Exception.Message)"
            }
            Start-Sleep -seconds 20
        }
    }

    Write-Host "Getting service info..." -foreground Yellow
    $info = $pushTenantManager.GetPushServiceInfo()
    $info.Retrieve("EndpointAddress")
    $info.Retrieve("TenantId")
    $info.Retrieve("AuthenticationRealm")
    $info.Retrieve("ValidContentEncryptionCertificates")
    $cctx.ExecuteQuery()

    Write-Host "Registered cloud hybrid search configuration:"
    $info | select TenantId,AuthenticationRealm,EndpointAddress | format-list

    if ([string]::IsNullOrEmpty($info.EndpointAddress)) {
        throw "No indexing service endpoint found!"
    }

    if ($info.ValidContentEncryptionCertificates -eq $null) {
        Write-Warning "No valid encryption certificate found."
    }

    if ($AADRealm -ne $info.AuthenticationRealm) {
        throw "Unexpected mismatch between realm ids read from Get-MsolCompanyInformation ($AADRealm) and GetPushServiceInfo ($($info.AuthenticationRealm))."
    }

    Write-Host "Configuring Cloud SSA..." -foreground Yellow
    $ssa.SetProperty("CertServerURL", $PortalUrl)
    $ssa.SetProperty("HybridTenantID", $info.TenantId)
    $ssa.SetProperty("AuthRealm", $info.AuthenticationRealm)
    $ssa.Update()

    Write-Host "Restarting SharePoint Timer Service..." -foreground Yellow
    Stop-Service SPTimerV4
    Write-Host "Restarting SharePoint Server Search..." -foreground Yellow
    if ($SP_VERSION -eq "15") {
        Restart-Service OSearch15
    } else {
        Restart-Service OSearch16
    }
    Start-Service SPTimerV4

    Write-Host "All done!" -foreground Green
}
catch
{
    Write-Error -ErrorRecord $_
    Write-Host "It is safe to re-run onboarding if you believe this error is transient." -Foreground Yellow
    return
}

# SIG # Begin signature block
# MIIkuQYJKoZIhvcNAQcCoIIkqjCCJKYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAQUlMbu/E/C+ZX
# e+HCh8TNhhw7u51NvArv33Ob8KpI76CCDZMwggYRMIID+aADAgECAhMzAAAAjoeR
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
# KoZIhvcNAQkEMSIEIABgkJhKZRoN7ReOgjB+XMlRrbI4j4mt+5L/unUI7nfpMIH8
# BgorBgEEAYI3AgEMMYHtMIHqoFaAVABTAGgAYQByAGUAUABvAGkAbgB0ACAAUwBl
# AGEAcgBjAGgAIABIAGUAYQBsAHQAaAAgAFIAZQBwAG8AcgB0AHMAIABEAGEAcwBo
# AGIAbwBhAHIAZKGBj4CBjGh0dHBzOi8vYmxvZ3MubXNkbi5taWNyb3NvZnQuY29t
# L3NoYXJlcG9pbnRfc3RyYXRlZ2VyeS8yMDE2LzAyLzAxL2Fubm91bmNpbmctdGhl
# LXNlYXJjaC1oZWFsdGgtcmVwb3J0cy1zcngtZm9yLXNoYXJlcG9pbnQtc2VhcmNo
# LWRpYWdub3N0aWNzMA0GCSqGSIb3DQEBAQUABIIBAG/bKNyHWGN1EjSk7qEBlnUs
# /IkeK6WVzmhIjAT3ABN+K5Ud9GIMZumXEEf6oXteHYX+Oi+WRVdth+i3jIxhsLwM
# ipavlCV3P5zKpAGuV/47jLytA+vteRYarahMFVCtCxc6t63jHOtx3O25lgEOeGoK
# Ig3xmlBbPPYt7t9j4PmB3Mwo2VHvTIfxorUGlfxUK85qRRjEG7DJDduzd1WL+TK+
# 5yDykzAknIAMItvIGJ6do26ce0FMXU2ON2Q6cyNqh+YNqZ2TVKRUufl6DogiiAkl
# z98wGAS2xhVbxO0UgqEsnZ5ay4UoKufcUQI7bovznKdGEWCcImDMUqQ27tkrTeOh
# ghNKMIITRgYKKwYBBAGCNwMDATGCEzYwghMyBgkqhkiG9w0BBwKgghMjMIITHwIB
# AzEPMA0GCWCGSAFlAwQCAQUAMIIBPQYLKoZIhvcNAQkQAQSgggEsBIIBKDCCASQC
# AQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgpaMlHgnVN3wTit4Ji0M/
# pA0rXui6tDJGOArk0Ed1Oy4CBljVRnmaARgTMjAxNzA0MjYyMzUzNDguNDYzWjAH
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
# 9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIJUdZ0XMAxdrjy5f
# rcPGXlTi4CEvKnCzpjqd5/5abk+iMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCB
# sQQUbNMnCPL52ajL+RnekktKrdsZo8EwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAJ9n8rWoIwZbewAAAAAAnzAWBBQAlebO8glKQo8J
# SjqdCe2Rg8CY/zANBgkqhkiG9w0BAQsFAASCAQChQ7N6nwsHEKeLXGeplvF4cdYc
# dzBW6SUuxYbCTUG7A14yTV9hAt5xZEOMQaxQivRtuYXDw8ak6Yrb/VCXq8F9uzBi
# XxNA9rNRTe1DzAeP5iN3pE5YLHecD2AnbEluAbcIyB0coNYQtypt54dyLhNngx6T
# qw5P9SwuO8tfWL+oKAYMb1N7PzcJPB+YWfkIAxwFoMTFe5MZNpy38vXdW7CaqERp
# Xs+ot72dJJnAuUn0jb/kFWUbRNll1g2YpyK4CzCPSOD7+y0Ie6UMBymbrrguZXjm
# hr0D/vthgmFAvmtElTB3nZgFfrYH7Pg8g52LxW0OLurfQ80U36f5S1vJMbFJ
# SIG # End signature block
