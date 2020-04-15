<#
.Description  
    AppFabric 1.1 aka SharePoint Distributed Cache service is patched independently from SharePoint itself
    
    This script identifies patch level (CU) and launches the patch process.
    It needs to be run individually on EACH farm server running the distributed cache service instance.         
.Parameter - patchFilePath 
    Full path to the AppFabric patch executable
.Usage 
    Apply patch identified by path
     
    PS >  Patch-AppFabric.ps1 -patchFilePath "c:\patch.exe"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Full path to the patch file exe")]
    [string] $patchFilePath = "E:\Builds\AppFabric 1.1\AppFabric-KB3092423-x64-ENU.exe"
)

$ErrorActionPreference = "Continue"

cls

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

if([string]::IsNullOrWhiteSpace($patchFilePath))
{
    do {
        $patchFilePath = Read-Host "Specify the full path to the patch file executable"
    }
    until (![string]::IsNullOrWhiteSpace($patchFilePath))
}

$patchfile = Get-Item -LiteralPath $patchFilePath
if($patchfile -eq $null) { 
    Write-Host "Unable to retrieve the patch file. Exiting." -ForegroundColor Red 
    Return 
}

# Set context for cache cluster to be patched
Use-CacheCluster

# Verify existing patch level and decide if update is warranted
Write-Host "`nAppFabric 1.1 CU versions"

Write-Host "`nCU1     1.0.4639.0
CU2     1.0.4644.0
CU3     1.0.4652.2
CU4     1.0.4653.2
CU5     1.0.4655.2
CU6     1.0.4656.2
CU7     1.0.4657.2"

Write-Host "`nCU version for AppFabric 1.1 service on $($env:COMPUTERNAME)..." -NoNewline

Write-Host "$(((Get-ItemProperty "C:\Program Files\AppFabric 1.1 for Windows Server\PowershellModules\DistributedCacheConfiguration\Microsoft.ApplicationServer.Caching.Configuration.dll").VersionInfo).ProductVersion)" -ForegroundColor Green

Write-Host "`nVerify the installed AppFabric 1.1 CU from " -NoNewLine
Write-Host "Control Panel/Add-Remove Programs/Installed Updates..." -ForegroundColor Green

$confirm = Read-Host "`nProceed with patching? [y | n]"

if($confirm -eq 'y') {
    $timer = New-TimeSpan -Seconds 120
    
    # Step 1: Gracefully stop the dc service. This will distribute the cache items to other servers in the cache cluster
    $dcServiceInstance = Get-SPServiceInstance | ? { $_.TypeName -eq "Distributed Cache" -and $_.Server.Name -eq $env:COMPUTERNAME}
    if($dcServiceInstance -ne $null) {
        Write-Host "`nFound distributed cache service instance on $($env:COMPUTERNAME)..." -ForegroundColor White
        $dcServiceInstance
        if($dcServiceInstance.Status -eq "Online") {
            Write-Host "`nStopping distributed cache service instance on $($env:COMPUTERNAME)..." -ForegroundColor White -NoNewline
            Stop-SPDistributedCacheServiceInstance -Graceful
            
            # takes upto 2 minutes to properly redistribute the cache to other servers in the cluster
            # no visibility as to what's happening until then, so we'll just sleep 2 minutes
            $stopWait = [System.Diagnostics.Stopwatch]::StartNew()
            while ($stopWait.Elapsed -lt $timer) {
                Write-Host "." -ForegroundColor White -NoNewline
                Start-Sleep -Seconds 5
            }

            Write-Host "Done!" -BackgroundColor Green 
        }
        else {
            Write-Host "`nDistributed cache service instance on $($env:COMPUTERNAME) is already stopped..." -ForegroundColor White
        }
    }
    
    # Step 2: Launch patch process

    Write-Host "`nPatching using file $patchFilePath. Keep this window open......" -ForegroundColor Magenta -NoNewline  

    Start-Process $patchfile 

    Start-Sleep -seconds 10

    $proc = Get-Process $patchfile.BaseName
    $proc.WaitForExit() 

    Write-Host "Done!" -BackgroundColor Green
    
    # Step 3: Restart the dc instance

    Write-Host "`nStarting distributed cache service instance on $($env:COMPUTERNAME)..." -ForegroundColor White -NoNewline

    $dcServiceInstanceNew = Get-SPServiceInstance | ? { $_.TypeName -eq "Distributed Cache" -and $_.Server.Name -eq $env:COMPUTERNAME}
    if($dcServiceInstanceNew -ne $null) {
        $dcServiceInstanceNew.Provision()

        # wait 2 minutes
        $startWait = [System.Diagnostics.Stopwatch]::StartNew()
        while ($startWait.Elapsed -lt $timer) {
            Write-Host "." -ForegroundColor White -NoNewline
            Start-Sleep -Seconds 5
        }

        Write-Host "Done!" -BackgroundColor Green 
    }
}

# Verify existing distributed cache cluster configuration for the farm
Write-Host "`nDisplaying existing Distributed Cache Cluster configuration for the farm..." -ForegroundColor Magenta

Get-CacheHost
