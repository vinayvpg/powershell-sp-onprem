[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Web application url")]
    [string] $webAppUrl='http://portal.murphyoilcorp.com',

    [Parameter(Mandatory=$false, Position=1, HelpMessage="Email address to send site access requests to")]
    [string] $siteAccessRequestAdminEmail='sharepoint_support@murphyoilcorp.com',

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Create report or apply change")]
    [switch] $apply = $false
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

if([string]::IsNullOrWhiteSpace($webAppUrl))
{
    do {
        $webAppUrl = Read-Host "Specify the url of target web application"
    }
    until (![string]::IsNullOrWhiteSpace($webAppUrl))
}

if([string]::IsNullOrWhiteSpace($siteAccessRequestAdminEmail))
{
    do {
        $siteAccessRequestAdminEmail = Read-Host "Specify the email address to send access request emails to"
    }
    until (![string]::IsNullOrWhiteSpace($siteAccessRequestAdminEmail))
}

$webApp = Get-SPWebApplication -Identity $webAppUrl

if($webApp -ne $null) 
{ 
    foreach($siteColl in $webApp.Sites) 
    {
        Write-Host "`n------------------------------------------------------------------------------------------------"

        Write-Host "Processing site collection $($siteColl.url)...."
        
        if($($siteColl.url).ToUpper() -like "*MY.MURPHYOILCORP.COM*") {
            Write-Host "---> Personal site collection...Skipped" -BackgroundColor Magenta
        }
        else {
            foreach($web in $siteColl.AllWebs) 
            { 
                # If site inherits permissions then inherit access request settings as well
                if (!$web.HasUniquePerm)
                {
                    if($apply) {
                        Write-Host "---> Web:$($web.Name) @ Url:$($web.Url) inherits access request settings from its parent '$($web.ParentWeb.Name)' @ Url: $($web.ParentWeb.url)..." -NoNewline
                        Write-Host "Skipping" -BackgroundColor Magenta
                    }
                    else {
                        Write-Host "---> Web:$($web.Name) @ Url:$($web.Url) inherits access request settings from its parent '$($web.ParentWeb.Name)' @ Url: $($web.ParentWeb.url)..."
                    }
                }
                else {
                    if($web.RequestAccessEnabled)
                    {
                        if($apply) {
                            Write-Host "---> Web:$($web.Name) @ Url:$($web.Url) has unique permissions. Setting access request email to '$siteAccessRequestAdminEmail'..." -NoNewline 
                            $web.RequestAccessEmail = $siteAccessRequestAdminEmail
                            $web.Update()  
                            Write-Host "Done" -BackgroundColor Green
                        }
                        else {
                            Write-Host "---> Web:$($web.Name) @ Url:$($web.Url) access request email will be set from '$($web.RequestAccessEmail)' to '$siteAccessRequestAdminEmail'" -BackgroundColor Green
                        }       
                    }
                    else {
                        if($apply) {                    
                            Write-Host "---> Web:$($web.Name) @ Url:$($web.Url) has unique permissions but access requests are NOT enabled" -BackgroundColor Yellow -NoNewline
                            Write-Host "Skipping" -BackgroundColor Red
                        }
                        else {
                            Write-Host "---> Web:$($web.Name) @ Url:$($web.Url) access requests are NOT enabled" -BackgroundColor Yellow

                        }
                    }
                }
            }
        }
    } 
} 

write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow