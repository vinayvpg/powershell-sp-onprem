param
(
    [switch]$AddEntry,
    [switch]$RemoveEntry
)
[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
try
{
    $newMod = New-Object Microsoft.SharePoint.Administration.SPWebConfigModification
    $newMod.Name = "LegacyWorkflowAuthorizedType_Sept2018"
    $newMod.Owner = "SharePoint"
    $newMod.Path = "configuration/System.Workflow.ComponentModel.WorkflowCompiler/authorizedTypes/targetFx"
    $newmod.Value = "<!-- Added to address changes introduced in September .Net security updates (CVE-2018-8421) --><authorizedType Assembly=`"System, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089`" NameSpace=`"System.CodeDom`" TypeName=`"*`" Authorized=`"True`" />"
    $newmod.Type = [Microsoft.SharePoint.Administration.SPWebConfigModification+SPWebConfigModificationType]::EnsureChildNode

    $contentSvc = [Microsoft.SharePoint.Administration.SPWebService]::ContentService
    if(!$AddEntry -and !$RemoveEntry)
    {
        $Title = "FixSPLegacyWOrkflowWebConfig"
        $Info = "Specify whether you would like to add or remove the System.CodeDom authorized type web.config modification"
        $options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Add Entry", "&Remove Entry", "&Quit")
        $defaultchoice = 0
        $opt = $host.UI.PromptForChoice($Title , $Info , $Options,$defaultchoice)
        switch($opt)
        {
            0{$AddEntry = $true}
            1{$RemoveEntry = $true}
            2{return}
        }
    }    
    if($AddEntry)
    {
        if(!$contentSvc.WebConfigModifications.Contains($webConfigMod))
        {
            #$proceed = Read-Host "Do you want to deploy this change to the web.configs now?`r`nNOTE: this will cause the application pools to recycle.`r`n"
            $title = "FixSPLegacyWOrkflowWebConfig"
            $info = "Do you want to deploy this change to the web.configs now?`r`nNOTE: this will cause the application pools to recycle."
            $options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No")
            $defaultchoice = 0
            $opt = $host.UI.PromptForChoice($Title , $Info , $Options,$defaultchoice)
            switch($opt)
            {
                0{continue}
                1{return}
            }
            Write-Host "Adding web config modification" -ForegroundColor Cyan
            $contentSvc.WebConfigModifications.Add($newMod)
            $contentSvc.Update()
            $contentSvc.ApplyWebConfigModifications()
        }
        else
        {
            #$proceed = Read-Host "The modification is already defined, did you want to re-deploy it to the web applications?`r`nNOTE: this will cause the application pools to recycle.`r`n"
            $title = "FixSPLegacyWOrkflowWebConfig"
            $info = "The modification is already defined, did you want to re-deploy it to the web applications?`r`nNOTE: this will cause the application pools to recycle."
            $options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No")
            $defaultchoice = 0
            $opt = $host.UI.PromptForChoice($Title , $Info , $Options,$defaultchoice)
            switch($opt)
            {
                0{continue}
                1{return}
            }
            Write-Host "Deploying web.config modifications" -ForegroundColor Cyan
            $contentSvc.ApplyWebConfigModifications()
            return
        }
    }
    elseif($RemoveEntry)
    {
        if($contentSvc.WebConfigModifications.Contains($newMod))
        {
            #$proceed = Read-Host "Do you want to remove this change from the web.configs now?`r`nNOTE: this will cause the application pools to recycle.`r`n"
            $title = "FixSPLegacyWOrkflowWebConfig"
            $info = "Do you want to remove this change from the web.configs now?`r`nNOTE: this will cause the application pools to recycle."
            $options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No")
            $defaultchoice = 0
            $opt = $host.UI.PromptForChoice($Title , $Info , $Options,$defaultchoice)
            switch($opt)
            {
                0{continue}
                1{return}
            }
            Write-Host "Removing web config modification" -ForegroundColor Cyan
            $contentSvc.WebConfigModifications.Remove($newMod)
            $contentSvc.Update()
            $contentSvc.ApplyWebConfigModifications()
        }
    }
}
catch
{
    throw $Error
}