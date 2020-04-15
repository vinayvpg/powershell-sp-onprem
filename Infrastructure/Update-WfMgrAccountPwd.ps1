<#  
.Description  
    Updates the password for workflow manager related accounts (workflow manager setup, run as account etc.). Run the script on every server in workflow manager farm.
         
.Parameter - newRunasAccountPwd 
    New password for the account
.Usage 
    Update 'run as' account password
     
    PS >  Update-WfMgrAccountPwd.ps1 -newRunasAccountPwd 'xyz"sdfjsd'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="New password for the run as account")]
    [string] $newRunasAccountPwd = 'newpwdescaped'
)

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

Import-Module ServiceBus
Import-Module WorkflowManager

$password = ConvertTo-SecureString $newRunasAccountPwd -AsPlainText -Force

Stop-SBFarm

Update-SBHost -RunAsPassword $password
Update-WFHost -RunAsPassword $password

Start-SBFarm