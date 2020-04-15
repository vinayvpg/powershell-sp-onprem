<#  
.Description  
    Updates the password for a managed sharepoint account (farm, admin, pool etc.). Run the script on web front end or application server hosting CA (preferred)
         
.Parameter - managedAccountIdentity  
    Identity of the managed account whose password needs to be updated
.Parameter - newPwd 
    New password for the account
.Usage 
    Update application pool account password
     
    PS >  Update-ManagedAccountPwd.ps1 -managedAccountIdentity "moc_w2k\svc_prdsp_pool" -newPwd 'xyz"sdfjsd'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Managed account identity in domain\loginname format")]
    [string] $managedAccountIdentity = "domain\svc_account",

    [Parameter(Mandatory=$true, Position=1, HelpMessage="New password for the managed account")]
    [string] $newPwd = 'newpwdescaped'
)

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

$managedAccountPwd = ConvertTo-SecureString -String $newPwd -AsPlainText -Force

Set-SPManagedAccount -Identity $managedAccountIdentity -ExistingPassword $managedAccountPwd -UseExistingPassword:$true