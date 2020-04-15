$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

Function GetUserAccessReport($WebAppURL, $FileUrl)
{
 #Get All Site Collections of the WebApp
 $SiteCollections = Get-SPSite -WebApplication $WebAppURL -Limit All

#Write CSV- TAB Separated File) Header
"URL `t Scope `t Title `t PermissionType `t Permissions `t LoginName `t DisplayName `t SID" | out-file $FileUrl


	#Check Web Application Policies
	$WebApp= Get-SPWebApplication $WebAppURL

	foreach ($Policy in $WebApp.Policies) 
  	{
	 	#Check if the search users is member of the group
		#if($Policy.UserName -eq $SearchUser)
		  #	{
				#Write-Host $Policy.UserName
	 			$PolicyRoles=@()
		 		foreach($Role in $Policy.PolicyRoleBindings)
				{
					$PolicyRoles+= $Role.Name +";"
				}
				#Write-Host "Permissions: " $PolicyRoles
				
				"$($AdminWebApp.URL) `t Web Application `t $($AdminSite.Title)`t  Web Application Policy `t $($PolicyRoles) `t $($Policy.UserName) `t $($Policy.DisplayName) `t $($Policy.SID)" | Out-File $FileUrl -Append
			#}
 	 }
  
  #Loop through all site collections
   foreach($Site in $SiteCollections) 
    {
	  #Check Whether the Search User is a Site Collection Administrator
	  foreach($SiteCollAdmin in $Site.RootWeb.SiteAdministrators)
      	{
			"$($Site.RootWeb.Url) `t Site `t $($Site.RootWeb.Title) `t Site Collection Administrator `t Site Collection Administrator `t $($SiteCollAdmin.LoginName) `t $($SiteCollAdmin.Name) `t $($SiteCollAdmin.SID)" | Out-File $FileUrl -Append
		}
  
	   #Loop throuh all Sub Sites
       foreach($Web in $Site.AllWebs) 
       {	
			if($Web.HasUniqueRoleAssignments -eq $True)
            	{
		        #Get all the users granted permissions to the web
	            foreach($WebRoleAssignment in $Web.RoleAssignments ) 
	            { 
	                #Is it a User Account?
					if($WebRoleAssignment.Member.userlogin)    
						{
							#Get the Permissions assigned to user
							$WebUserPermissions=@()
							foreach ($RoleDefinition in $WebRoleAssignment.RoleDefinitionBindings)
							{
                                if($RoleDefinition.Name -ne "Limited Access") {
				                    $WebUserPermissions += $RoleDefinition.Name +";"
                                }
				            }
							#write-host "with these permissions: " $WebUserPermissions
							#Send the Data to Log 
                            if(![string]::IsNullOrEmpty($WebUserPermissions)) {
							    "$($Web.Url) `t Web `t $($Web.Title) `t Direct Permission `t $($WebUserPermissions) `t $($WebRoleAssignment.Member.LoginName) `t $($WebRoleAssignment.Member.Name) `t $($WebRoleAssignment.Member.SID)" | Out-File $FileUrl -Append
                            }
						}
					#Its a SharePoint Group, So search inside the group and check if the user is member of that group
					else  
						{
                        foreach($user in $WebRoleAssignment.member.users)
                            {
								    #Get the Group's Permissions on site
									$WebGroupPermissions=@()
							    	foreach ($RoleDefinition  in $WebRoleAssignment.RoleDefinitionBindings)
							   		{
                                        if($RoleDefinition.Name -ne "Limited Access") {
		                    	  		    $WebGroupPermissions += $RoleDefinition.Name +";"
                                        }
		                       		}
									#write-host "Group has these permissions: " $WebGroupPermissions
									
									if(![string]::IsNullOrEmpty($WebGroupPermissions)) {
									    "$($Web.Url) `t Web `t $($Web.Title) `t Member of '$($WebRoleAssignment.Member.Name)' Group `t $($WebGroupPermissions) `t $($user.LoginName) `t $($user.Name) `t $($user.SID)" | Out-File $FileUrl -Append
                                    }
							}
						}
               	    }
				}
				
				#********  Check Lists with Unique Permissions ********/
		            foreach($List in $Web.lists)
		            {
		                if($List.HasUniqueRoleAssignments -eq $True -and ($List.Hidden -eq $false))
		                {
		                   #Get all the users granted permissions to the list
				            foreach($ListRoleAssignment in $List.RoleAssignments ) 
				                { 
				                  #Is it a User Account?
									if($ListRoleAssignment.Member.userlogin)    
										{
										   
											#Get the Permissions assigned to user
											$ListUserPermissions=@()
											foreach ($RoleDefinition  in $ListRoleAssignment.RoleDefinitionBindings)
											{
                                                if($RoleDefinition.Name -ne "Limited Access") {
							                        $ListUserPermissions += $RoleDefinition.Name +";"
                                                }
							                }
											#write-host "with these permissions: " $ListUserPermissions
													
											if(![string]::IsNullOrEmpty($ListUserPermissions)) {
											    "$($List.ParentWeb.Url)/$($List.RootFolder.Url) `t List `t $($List.Title) `t Direct Permission `t $($ListUserPermissions) `t $($ListRoleAssignment.Member.LoginName) `t $($ListRoleAssignment.Member.Name) `t $($ListRoleAssignment.Member.SID)" | Out-File $FileUrl -Append
                                            }
										}
										#Its a SharePoint Group, So search inside the group and check if the user is member of that group
									else  
										{
					                        foreach($user in $ListRoleAssignment.member.users)
					                            {
													    #Get the Group's Permissions on site
														$ListGroupPermissions=@()
												    	foreach ($RoleDefinition  in $ListRoleAssignment.RoleDefinitionBindings)
												   		{
                                                            if($RoleDefinition.Name -ne "Limited Access") {
							                    	  		    $ListGroupPermissions += $RoleDefinition.Name +";"
                                                            }
							                       		}
														#write-host "Group has these permissions: " $ListGroupPermissions
														
														if(![string]::IsNullOrEmpty($ListGroupPermissions)) {
														    "$($List.ParentWeb.Url)/$($List.RootFolder.Url) `t List `t $($List.Title) `t Member of '$($ListRoleAssignment.Member.Name)' Group `t $($ListGroupPermissions) `t $($user.LoginName) `t $($user.Name) `t $($user.SID)" | Out-File $FileUrl -Append
                                                        }
												}
									}	
			               	    }
				            }
		            }
				}	
			}
	Write-Host "Report generated at $FileUrl"	
}

$webAppUrl = Read-Host "Enter Url of the web application"
$reportPath = Read-Host "Enter path of folder where report should be created"

GetUserAccessReport $webAppUrl "$reportPath\user_Permission_Report.csv"