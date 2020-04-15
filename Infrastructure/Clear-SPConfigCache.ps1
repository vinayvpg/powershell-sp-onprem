# Clear the SharePoint Config Cache

# Output program information
Write-Host -foregroundcolor White ""
Write-Host -foregroundcolor White "Clear SharePoint Timer Cache"

#**************************************************************************************
# Constants
#**************************************************************************************
Set-Variable timerServiceName -option Constant -value "SPTimerV4"
Set-Variable timerServiceInstanceName -option Constant -value "Microsoft SharePoint Foundation Timer"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

#**************************************************************************************
# Functions
#**************************************************************************************

#<summary>
# Stops the SharePoint Timer Service on each server in the SharePoint Farm.
#</summary>
#<param name="$farm">The SharePoint farm object.</param>
function StopSharePointTimerServicesInFarm($farm)
{
    # Iterate through each server in the farm, and each service in each server
    foreach($server in $farm)
    {
        foreach($instance in $server.ServiceInstances)
        {
            # If the server has the timer service then stop the service
            if($instance.TypeName -eq $timerServiceInstanceName)
            {
                [string]$serverName = $server.Name

                Write-Host -foregroundcolor DarkGray -NoNewline "Stop '$timerServiceName' service on server: "
                Write-Host -foregroundcolor Gray $serverName

                $service = Get-WmiObject -ComputerName $serverName Win32_Service -Filter "Name='$timerServiceName'"
                sc.exe \\$serverName stop $timerServiceName > $null

                # Wait until this service has actually stopped
                WaitForServiceState $serverName $timerServiceName "Stopped"

                break;
            }
        }
    }
}

#<summary>
# Waits for the service on the server to reach the required service state.
#</summary>
#<param name="$serverName">The name of the server with the service to monitor.</param>
#<param name="$serviceName">The name of the service to monitor.</param>
#<param name="$serviceState">The service state to wait for, e.g. Stopped, or Running.</param>
function WaitForServiceState([string]$serverName, [string]$serviceName, [string]$serviceState)
{
    Write-Host -foregroundcolor DarkGray -NoNewLine "Waiting for service '$serviceName' to change state to $serviceState on server $serverName"

    do
    {
        Start-Sleep 1
        Write-Host -foregroundcolor DarkGray -NoNewLine "."
        $service = Get-WmiObject -ComputerName $serverName Win32_Service -Filter "Name='$serviceName'"
    }
    while ($service.State -ne $serviceState)

    Write-Host -foregroundcolor DarkGray -NoNewLine " Service is "
    Write-Host -foregroundcolor Gray $serviceState
}

#<summary>
# Starts the SharePoint Timer Service on each server in the SharePoint Farm.
#</summary>
#<param name="$farm">The SharePoint farm object.</param>
function StartSharePointTimerServicesInFarm($farm)
{
    # Iterate through each server in the farm, and each service in each server
    foreach($server in $farm)
    {
        foreach($instance in $server.ServiceInstances)
        {
            # If the server has the timer service then start the service
            if($instance.TypeName -eq $timerServiceInstanceName)
            {
                [string]$serverName = $server.Name

                Write-Host -foregroundcolor DarkGray -NoNewline "Start '$timerServiceName' service on server: "
                Write-Host -foregroundcolor Gray $serverName

                $service = Get-WmiObject -ComputerName $serverName Win32_Service -Filter "Name='$timerServiceName'"
                sc.exe \\$serverName start $timerServiceName > $null

                WaitForServiceState $serverName $timerServiceName "Running"

                break;
            }
        }
    }
}

#<summary>
# Removes all xml files recursive on a UNC path
#</summary>
#<param name="$farm">The SharePoint farm object.</param>
function DeleteXmlFilesFromConfigCache($farm)
{
    Write-Host -foregroundcolor DarkGray "Delete xml files"

    [string] $path = ""

    # Iterate through each server in the farm, and each service in each server
    foreach($server in $farm)
    {
        foreach($instance in $server.ServiceInstances)
        {
            # If the server has the timer service delete the XML files from the config cache
            if($instance.TypeName -eq $timerServiceInstanceName)
            {
                [string]$serverName = $server.Name

                Write-Host -foregroundcolor DarkGray -NoNewline "Deleting xml files from config cache on server: "
                Write-Host -foregroundcolor Gray $serverName

                # Remove all xml files recursive on an UNC path
                $path = "\\" + $serverName + "\c$\ProgramData\Microsoft\SharePoint\Config\*-*\*.xml"
                Remove-Item -path $path -Force

                break
            }
        }
    }
}

#<summary>
# Clears the SharePoint cache on an UNC path
#</summary>
#<param name="$farm">The SharePoint farm object.</param>
function ClearTimerCache($farm)
{
    Write-Host -foregroundcolor DarkGray "Clear the cache"

    [string] $path = ""

    # Iterate through each server in the farm, and each service in each server
    foreach($server in $farm)
    {
        foreach($instance in $server.ServiceInstances)
        {
            # If the server has the timer service then force the cache settings to be refreshed
            if($instance.TypeName -eq $timerServiceInstanceName)
            {
                [string]$serverName = $server.Name

                Write-Host -foregroundcolor DarkGray -NoNewline "Clearing timer cache on server: "
                Write-Host -foregroundcolor Gray $serverName

                # Clear the cache on an UNC path
                # 1 = refresh all cache settings
                $path = "\\" + $serverName + "\c$\ProgramData\Microsoft\SharePoint\Config\*-*\cache.ini"
                Set-Content -path $path -Value "1"

                break
            }
        }
    }
}

#**************************************************************************************
# Main script block
#**************************************************************************************
Write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

# Get the local farm instance
$farm = Get-SPServer | where {$_.Role -match "Application"}

# Stop the SharePoint Timer Service on each server in the farm
StopSharePointTimerServicesInFarm $farm

# Delete all xml files from cache config folder on each server in the farm
DeleteXmlFilesFromConfigCache $farm

# Clear the timer cache on each server in the farm
ClearTimerCache $farm

# Start the SharePoint Timer Service on each server in the farm
StartSharePointTimerServicesInFarm $farm

Write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow