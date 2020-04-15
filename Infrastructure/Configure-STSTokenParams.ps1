<#
    Script to configure parameters related to security token service that influence token caching
#>
if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

# Configure settings for Content Service
$cs = [Microsoft.SharePoint.Administration.SPWebService]::ContentService

if($cs -ne $null) {
    # Token Timeout indicates how frequently UPSS syncs group membership changes from AD into SP. Default is once every 24 hrs.
    Write-Host "`nSetting TokenTimeout (affects UPPS sync frequency with AD)..."
    Write-Host "Current value: $($cs.TokenTimeout)" -ForegroundColor Magenta

    $cs.TokenTimeout = (New-TimeSpan -minutes 15)
    $cs.Update()

    Write-Host "New value: $($cs.TokenTimeout)" -ForegroundColor Green
    Write-Host "Done!" -BackgroundColor Green
}

# Configure settings for SharePoint STS (Security Token Service) - responsible for issuing logon token to authenticating user that is cached in distributed cache.
# Every SP request during a session retrieves the token from the cache before the request is served. If it is valid then it is used. If expired then user is prompted to authenticate.
$sts = Get-SPSecurityTokenServiceConfig

if($sts -ne $null) {
    # Windows Token Lifetime indicates the duration for which a logon token granted to a user authenticating to SP with NTLM/Kerberos is valid.
    # Default is 10 hrs.
    Write-Host "`nSetting WindowsTokenLifetime (lifetime of logon token for NTLM/kerberos authentication)..."
    Write-Host "Current value: $($sts.WindowsTokenLifetime)" -ForegroundColor Magenta

    $sts.WindowsTokenLifetime = (New-TimeSpan -minutes 30)

    # Forms Token Lifetime indicates the duration for which a logon token granted to a user authenticating to SP with Forms based authentication is valid.
    # Default is 10 hrs.
    Write-Host "`nSetting FormsTokenLifetime (lifetime of logon token for Forms based authentication)..."
    Write-Host "Current value: $($sts.FormsTokenLifetime)" -ForegroundColor Magenta

    $sts.FormsTokenLifetime = (New-TimeSpan -minutes 30)

    # use in memory session cookie so closing browser window expires session
    Write-Host "`nSetting use of in memory cookies for session management..."

    $sts.UseSessionCookies = $true

    # Logon Token Cache Expiration Window is the minimum lifetime of a token returned from logon token cache. If the token is valid for equal to or less than this duration then it is considered expired. 
    # So the actual valid lifetime of a token is calculated by subtracting this value from token lifetime values above...on a sliding basis. So this value should NEVER be more than the token lifetime values above.
    # Default is 10 mins.
    # So default lifetime of a freshly issued logon token is 9 hr 50 mins. (10 hr - 10 mins)
    Write-Host "`nSetting LogonTokenCacheExpirationWindow (minimum lifetime of logon token before it is considered expired)..."
    Write-Host "Current value: $($sts.LogonTokenCacheExpirationWindow)" -ForegroundColor Magenta

    $sts.LogonTokenCacheExpirationWindow = (New-TimeSpan -minutes 5)

    $sts.Update()

    Write-Host "`n"
    Write-Host "New value WindowsTokenLifetime: $($sts.WindowsTokenLifetime)" -ForegroundColor Green
    Write-Host "New value FormsTokenLifetime: $($sts.FormsTokenLifetime)..." -ForegroundColor Green
    Write-Host "New value LogonTokenExpirationWindow: $($sts.LogonTokenCacheExpirationWindow)..." -ForegroundColor Green

    Write-Host "`nDone!" -BackgroundColor Green
}

Write-Host "`nPerforming IISRESET..."

IISReset

Write-Host "`nDone!" -BackgroundColor Green