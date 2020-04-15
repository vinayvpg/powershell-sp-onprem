<#  
.Description  
    Download from on-prem SP, specific files requested during audit. This powershell uses webRequest and webClient to connect with SP and download files.
    It can be run from ANY machine without needing access to SP client or server libraries.
    It uses the credentials of the logged in user so whether or not files are found depends on whether or not the user has access to them.
         
.Parameter - auditInfoCSVPath 
    Path to csv file containing invoice numbers and file class. The header columns in the csv should be 'InvoiceNumber' and 'Class'.
.Parameter - downloadPath 
    Path where files will be downloaded
.Parameter - invoiceNum 
    Invoice Number is attempting to find and download individual file.
.Parameter - class 
    Document class is attempting to find and download individual file (ATT, APS etc.)
.Parameter - download 
    Flag to actually download the file or run discovery without downloading.
.Usage 
    Download files specified in csv
     
    PS >  Download-SPFilesForAudit.ps1 -auditInfoCSVPath "c:/temp/invoices.csv" -download
.Usage 
    Download individual file
     
    PS >  Download-SPFilesForAudit.ps1 -invoiceNum 'abcdef' -class 'APS' -download
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Full path to csv containing vendor or invoice numbers for audit")]
    [string] $auditInfoCSVPath="C:\Users\prabhvx\OneDrive - Murphy Oil\Desktop\SP Management Scripts\Grp5_Original_03102020.csv",
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Path to folder where files will be downloaded")]
    [string] $downloadPath,

    [Parameter(Mandatory=$false, Position=2, HelpMessage="Invoice number to look for")]
    [string] $invoiceNum,#="0011609IN"

    [Parameter(Mandatory=$false, Position=3, HelpMessage="Vendor number to look for")]
    [string] $vendorNum,

    [Parameter(Mandatory=$false, Position=4, HelpMessage="Vendor name to look for")]
    [string] $vendorName="SPITZER INDUSTRIES INC",

    [Parameter(Mandatory=$false, Position=5, HelpMessage="Document class - ATT, APS etc. This affects the search query that will be formulated.")]
    [string] $class ="APS",

    [Parameter(Mandatory=$false, Position=6, HelpMessage="Specify the properties to select")]
    [string] $selectProps ="Title,Path,Write,FileExtension,DCTMLegacyChronicleIDOWSTEXT",

    [Parameter(Mandatory=$false, Position=7, HelpMessage="Start date to search by")]
    [string] $modifiedStartDate,

    [Parameter(Mandatory=$false, Position=8, HelpMessage="End date to search by")]
    [string] $modifiedEndDate,

    [Parameter(Mandatory=$false, Position=9, HelpMessage="Download?")]
    [switch] $download=$true,

    [Parameter(Mandatory=$false, Position=10, HelpMessage="Get attachments from dm_document?")]
    [switch] $getAttachments=$true,

    [Parameter(Mandatory=$false, Position=11, HelpMessage="Download attachments from dm_document?")]
    [switch] $downloadAttachments=$true,

    [Parameter(Mandatory=$false, Position=12, HelpMessage="VoucherId to look for")]
    [string] $voucherId="1469882",

    [Parameter(Mandatory=$false, Position=13, HelpMessage="Invoice total to look for")]
    [double] $invoiceTotal=557225,

    [Parameter(Mandatory=$false, Position=14, HelpMessage="PONumber to look for")]
    [double] $poNumber
)

cls

$ErrorActionPreference = "Continue"

function GetDocument([PSCustomObject] $row)
{
    $targetSite = "http://search.murphyoilcorp.com"

    $endpoint = [string]::Empty

    $invoiceNum = $($row.InvoiceNumber.Trim())

    $vendorNum = $($row.VendorNumber.Trim())
    # vendorNum = 0 indicates spurious data
    if($vendorNum -eq "0") {
        $vendorNum = [string]::Empty
    }

    $modifiedStartDate = $($row.ModifiedStartDate.Trim()) -replace "\/","%2f"
    $modifiedEndDate = $($row.ModifiedEndDate.Trim()) -replace "\/","%2f"

    $vendorName = $($row.VendorName.Trim())
    # url encode special characters in vendor name
    $vendorName = $vendorName -replace "\&", "%26" -replace "\$", "%24" -replace "\#", "%23" -replace "\/","%2f"

    $voucherId = $($row.VoucherId.Trim())
    # single digit voucher ids are probably useless
    if($voucherId.length -eq 1) {
        $voucherId = [string]::Empty
    }

    $poNumber = $($row.PONumber.Trim())

    $invoiceTotal = [double] $($row.InvoiceTotal)

    $class = $($row.Class.Trim())
    
    $mainDocFileFound = [string]::Empty
    $mainDocFileNames = [string]::Empty
    $attachmentFileNames = [string]::Empty

    switch($class)
    {
        'ATT' {                    
            $endpoint = $targetSite + "/_api/search/query?querytext=%27SPSiteUrl%3Adocs*%20$invoiceNum*%27" + "&selectproperties=%27$selectProps%27"
        }
        'APS' {
            if(![string]::IsNullOrEmpty($invoiceNum)) {
                if([string]::IsNullOrEmpty($vendorNum) -and [string]::IsNullOrEmpty($vendorName) -and [string]::IsNullOrEmpty($voucherId)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%27" + "&selectproperties=%27$selectProps%27"
                }
                
                if([string]::IsNullOrEmpty($vendorNum) -and [string]::IsNullOrEmpty($vendorName) -and ![string]::IsNullOrEmpty($voucherId)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%20DCTMVoucherIdOWSTEXT%3A*$voucherId*%27" + "&selectproperties=%27$selectProps%27"
                }

                if (![string]::IsNullOrEmpty($vendorNum) -and ![string]::IsNullOrEmpty($voucherId) -and [string]::IsNullOrEmpty($vendorName)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%20DCTMVendorNumberOWSTEXT%3A$vendorNum*%20DCTMVoucherIdOWSTEXT%3A*$voucherId*%27" + "&selectproperties=%27$selectProps%27"
                }

                if(![string]::IsNullOrEmpty($vendorName) -and [string]::IsNullOrEmpty($vendorNum) -and ![string]::IsNullOrEmpty($voucherId)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%20DCTMVendorNameOWSTEXT%3A$vendorName*%20DCTMVoucherIdOWSTEXT%3A*$voucherId*%27" + "&selectproperties=%27$selectProps%27"
                }
            }
            else {
                if(![string]::IsNullOrEmpty($vendorNum) -and ![string]::IsNullOrEmpty($voucherId)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMVendorNumberOWSTEXT%3A*$vendorNum*%20AND%20DCTMVoucherIdOWSTEXT%3A*$voucherId*%27" + "&selectproperties=%27$selectProps%27"
                }
                elseif(![string]::IsNullOrEmpty($vendorName) -and ![string]::IsNullOrEmpty($poNumber)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMVendorNameOWSTEXT%3A$vendorName*%20AND%20DCTMPONumberAllOWSTEXT%3A$poNumber%27" + "&selectproperties=%27$selectProps%27"
                }
                elseif(![string]::IsNullOrEmpty($vendorName) -and ![string]::IsNullOrEmpty($invoiceTotal)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMVendorNameOWSTEXT%3A$vendorName*%20AND%20DCTMInvoiceTotalOWSNMBR%3A$invoiceTotal%27" + "&selectproperties=%27$selectProps%27"
                }
                elseif (![string]::IsNullOrEmpty($vendorNum) -and [string]::IsNullOrEmpty($voucherId) -and [string]::IsNullOrEmpty($vendorName)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMVendorNumberOWSTEXT%3A*$vendorNum*%20AND%20Write>%3D$modifiedStartDate%20AND%20Write<%3D$modifiedEndDate%27" + "&selectproperties=%27$selectProps%27"
                }
                elseif(![string]::IsNullOrEmpty($vendorName) -and [string]::IsNullOrEmpty($vendorNum) -and [string]::IsNullOrEmpty($voucherId)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMVendorNameOWSTEXT%3A$vendorName*%20AND%20Write>%3D$modifiedStartDate%20AND%20Write<%3D$modifiedEndDate%27" + "&selectproperties=%27$selectProps%27"
                }
                elseif(![string]::IsNullOrEmpty($voucherId) -and [string]::IsNullOrEmpty($vendorName) -and [string]::IsNullOrEmpty($vendorNum)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMVoucherIdOWSTEXT%3A*$voucherId*%27" + "&selectproperties=%27$selectProps%27"
                }
                elseif(![string]::IsNullOrEmpty($voucherId) -and ![string]::IsNullOrEmpty($vendorName) -and [string]::IsNullOrEmpty($vendorNum)) {
                    $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMVoucherIdOWSTEXT%3A*$voucherId*%20AND%20DCTMVendorNameOWSTEXT%3A$vendorName*%27" + "&selectproperties=%27$selectProps%27"
                }
            }
        }
        default {
            if([string]::IsNullOrEmpty($vendorNum)) {
                $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%27" + "&selectproperties=%27$selectProps%27"
            }
            else {
                $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%20DCTMVendorNumberOWSTEXT%3A$vendorNum*%27" + "&selectproperties=%27$selectProps%27"
            }

            if([string]::IsNullOrEmpty($vendorName)) {
                $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%27" + "&selectproperties=%27$selectProps%27"
            }
            else {
                $endpoint = $targetSite + "/_api/search/query?querytext=%27(ContentType%3A%22DCTM%20aps_core%22%20AND%20SPSiteUrl%3Alegacydocs*)%20DCTMInvoiceNumberOWSTEXT%3A$invoiceNum*%20DCTMVendorNameOWSTEXT%3A$vendorName*%27" + "&selectproperties=%27$selectProps%27"
            }
        }
    }

    Write-Host "-----------------------------------------------------------------------------------------------"

    Write-Host "Searching for document with invoice number:'$invoiceNum', vendor name:'$vendorName', vendor number:'$vendorNum', voucherId: '$voucherId', PO Number: '$poNumber', Invoice Total: '$invoiceTotal' and class:'$class'..." -BackgroundColor Magenta
    Write-Host "`nQuery: $endpoint"

    if(![string]::IsNullOrWhiteSpace($endPoint)) {
        $req = [System.Net.WebRequest]::Create($endpoint)
        $req.UseDefaultCredentials = $true
        $req.Accept = "application/json;odata=verbose"
        $req.Method = "GET"

        if($req -ne $null) {
            [System.Net.WebResponse] $resp = $req.GetResponse()
            [System.IO.Stream] $respStream = $resp.GetResponseStream()

            $readStream = New-Object System.IO.StreamReader $respStream
            
            $ret = $readStream.ReadToEnd() | ConvertFrom-Json

            if($ret -ne $null) {
                if($ret.d.query.PrimaryQueryResult.RelevantResults.TotalRows -ne 0) {
                    $mainDocFileFound = "Yes"
                    $count = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results.length

                    if($count -gt 0) {
                        Write-Host "`n$count files found for these search criteria. " -BackgroundColor DarkYellow -ForegroundColor Black
                    }

                    if($count -gt 1) {
                        Write-Host "Downloaded file name will be modified to include a counter..." -BackgroundColor DarkYellow -ForegroundColor Black
                    }

                    for($i=0; $i -lt $count; $i++) {
                        $sourceFilePath = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results[$i].Cells.results[3].Value
                        $sourceFileName = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results[$i].Cells.results[2].Value -replace "\\", "_"
                        $sourceFileExtension = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results[$i].Cells.results[5].Value
                        $sourceFileLegacyChronicleId = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results[$i].Cells.results[6].Value

                        #$sourceFilePath = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results[$i].Cells.results[6].Value
                        #$sourceFileName = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results[$i].Cells.results[3].Value -replace "\\", "_"
                        #$sourceFileExtension = $ret.d.query.PrimaryQueryResult.RelevantResults.Table.Rows.results[$i].Cells.results[31].Value

                        Write-Host "`nFile found at '$sourceFilePath'..." -NoNewline

                        $mainDocFileNames = $sourceFileName + "." + $sourceFileExtension

                        if(![string]::IsNullOrEmpty($vendorNum)) {
                            $mainDocFileNames = $vendorNum + "_" + $mainDocFileNames
                        }
                        
                        # special filename consideration for voucher id
                        if(![string]::IsNullOrEmpty($voucherId)) {
                            $mainDocFileNames = $voucherId +  "_" + $mainDocFileNames
                        }

                        # special filename consideration for po number
                        if(![string]::IsNullOrEmpty($poNumber)) {
                            $mainDocFileNames = $poNumber +  "_" + $mainDocFileNames
                        }

                        if($global:download) {
                            $modifier = [string]::Empty
                            if($count -gt 1) {
                                $modifier = "_$i"
                            }

                            if(![string]::IsNullOrEmpty($vendorNum)) {
                                $sourceFileName = $vendorNum + "_" + $modifiedStartDate + "_" + $sourceFileName
                            }

                            # special filename consideration for voucher id
                            if(![string]::IsNullOrEmpty($voucherId)) {
                                $sourceFileName = $voucherId + "_" + $sourceFileName
                            }

                            $destinationFilePath = $global:downloadPath + $sourceFileName + $modifier + "." + $sourceFileExtension

                            Write-Host "Downloading to '$destinationFilePath'..." -NoNewline

                            $webClient = New-Object System.Net.WebClient
                            $webClient.UseDefaultCredentials = $true
                            $webClient.DownloadFile($sourceFilePath, $destinationFilePath)

                            Write-Host "Done" -BackgroundColor Green
                        }
                        else {
                            Write-Host "Not downloaded" -BackgroundColor Red
                        }

                        # get attachments from dm_document if requested

                        if($global:getAttachments) {
                            Write-Host "`n---> Getting attachments from dm_document"

                            if(![string]::IsNullOrEmpty($invoiceNum)) {
                                $endpointAttachment = "http://legacydocs.murphyoilcorp.com/documentum/_api/web/Lists/GetByTitle(%27DCTM%20dm_document%27)/items?" + '$select=EncodedAbsUrl,FieldValuesAsText/FileLeafRef&$expand=FieldValuesAsText&$filter=DCTM_x0020_LegacyRelation eq %27' + $invoiceNum + "_aps_document_" + $sourceFileLegacyChronicleId + "%27"
                            }
                            else {
                                $endpointAttachment = "http://legacydocs.murphyoilcorp.com/documentum/_api/web/Lists/GetByTitle(%27DCTM%20dm_document%27)/items?" + '$select=EncodedAbsUrl,FieldValuesAsText/FileLeafRef&$expand=FieldValuesAsText&$filter=substringof(%27' + "_aps_document_" + $sourceFileLegacyChronicleId + "%27,DCTM_x0020_LegacyRelation)"
                            }

                            Write-Host "Query: $endpointAttachment"

                            $reqAttachment = [System.Net.WebRequest]::Create($endpointAttachment)
                            $reqAttachment.UseDefaultCredentials = $true
                            $reqAttachment.Accept = "application/json;odata=verbose"
                            $reqAttachment.Method = "GET"
                            
                            if($reqAttachment -ne $null) {
                                [System.Net.WebResponse] $respAttachment = $reqAttachment.GetResponse()
                                [System.IO.Stream] $respStreamAttachment = $respAttachment.GetResponseStream()

                                $readStreamAttachment = New-Object System.IO.StreamReader $respStreamAttachment
            
                                $retAttachment = $readStreamAttachment.ReadToEnd() | ConvertFrom-Json

                                if($retAttachment -ne $null) {

                                    $countAttachment = $retAttachment.d.results.length

                                    Write-Host "`n$countAttachment attachments found for this. Downloaded file name will be modified to be prepended with invoice number..." -BackgroundColor DarkYellow -ForegroundColor Black
                                    
                                    if($countAttachment -gt 0) {    
                                        $attachmentFileNames = [string]::Empty
                                                    
                                        for($j=0; $j -lt $countAttachment; $j++) {
                                            #$sourceAttachmentPath = $($retAttachment.d.results[$j].File.__deferred.uri) + '/$value'
                                            $sourceAttachmentPath = $($retAttachment.d.results[$j].EncodedAbsUrl)
                                            $attachmentFileName = $($retAttachment.d.results[$j].FieldValuesAsText.FileLeafRef)

                                            $destinationFilePathAttachment = $global:downloadPath + $invoiceNum + "_" + $attachmentFileName
                                            
                                            # special download path consideration for voucher id
                                            if(![string]::IsNullOrEmpty($voucherId)) {
                                                $destinationFilePathAttachment = $global:downloadPath + $voucherId + "_" + $attachmentFileName
                                            }

                                            # special download path consideration for PO Number
                                            if(![string]::IsNullOrEmpty($poNumber)) {
                                                $destinationFilePathAttachment = $global:downloadPath + $poNumber + "_" + $attachmentFileName
                                            }

                                            $attachmentFileNames = $attachmentFileNames + $invoiceNum + "_" + $attachmentFileName + ", "

                                            # special filename consideration for voucher id
                                            if(![string]::IsNullOrEmpty($voucherId)) {
                                                $attachmentFileNames = $attachmentFileNames + $voucherId + "_" + $attachmentFileName + ", "
                                            }

                                            # special filename consideration for PO Number
                                            if(![string]::IsNullOrEmpty($poNumber)) {
                                                $attachmentFileNames = $attachmentFileNames + $poNumber + "_" + $attachmentFileName + ", "
                                            }

                                            # download attachments if requested
                                            if($global:downloadAttachments) {
                                                Write-Host "`n------> Downloading attachment to '$destinationFilePathAttachment'..." -NoNewline

                                                $webClientAttachment = New-Object System.Net.WebClient
                                                $webClientAttachment.UseDefaultCredentials = $true
                                                $webClientAttachment.DownloadFile($sourceAttachmentPath, $destinationFilePathAttachment)

                                                Write-Host "Done" -BackgroundColor Green
                                            }
                                        }
                                    }                                   
                                }

                                # populate log
                                "$invoiceNum `t $vendorName `t $class `t $vendorNum `t $voucherId `t $poNumber `t $invoiceTotal `t $mainDocFileFound `t $mainDocFileNames `t $countAttachment `t $attachmentFileNames" | out-file $global:logCSVPath -Append 
                            }
                        }
                        else {
                                # populate log
                                "$invoiceNum `t $vendorName `t $class `t $vendorNum `t $voucherId `t $poNumber `t $invoiceTotal `t $mainDocFileFound `t $mainDocFileNames `t 'n/a' `t 'n/a'" | out-file $global:logCSVPath -Append 
                        }
                    }
                }
                else {
                    $mainDocFileFound = "No"

                    Write-Host "$class file with invoice '$invoiceNum' NOT found" -BackgroundColor Red

                    "$invoiceNum `t $vendorName `t $class `t $vendorNum `t $voucherId `t $poNumber `t $invoiceTotal `t $mainDocFileFound `t $mainDocFileNames `t 0 `t $attachmentFileNames" | out-file $global:logCSVPath -Append 
                }
            }
        }
    }
}

function ProcessCSV([string] $csvPath)
{
    if(![string]::IsNullOrEmpty($csvPath))
    {
        write-host "`nProcessing csv file $csvPath..." -ForegroundColor Green
        $global:csv = Import-Csv -Path $csvPath
    }

    if($global:csv -ne $null)
    {
        $global:csv | % {
            GetDocument $_ | out-null
        }
    }
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

$global:download = $download
$global:getAttachments = $getAttachments
$global:downloadAttachments = $downloadAttachments

$timestamp = Get-Date -Format s | % { $_ -replace ":", "-" }

if([string]::IsNullOrWhiteSpace($downloadPath))
{
    $currentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $downloadPath = $currentDir + "\downloads\" + $timestamp + "\"

    Write-Host "You did not specify a path for downloading files or logging. The log as well as and downloaded files will be available at '$downloadPath'" -ForegroundColor Cyan

    if(-not (Test-Path $downloadPath -PathType Container)) {
        Write-Host "Creating download folder '$downloadPath'..." -NoNewline
        md -Path $downloadPath | out-null
        Write-Host "Done" -ForegroundColor White -BackgroundColor Green
    }
}

$global:downloadPath = $downloadPath
$global:logCSVPath = $global:downloadPath + "FullLog.csv"

#log csv
"InvoiceNumber `t VendorName `t Class `t VendorNumber `t VoucherId `t PONumber `t InvoiceTotal `t DocFound? `t DocFileName(s) `t AttachmentCount `t AttachmentFileName(s)" | out-file $global:logCSVPath

if(![string]::IsNullOrWhiteSpace($auditInfoCSVPath))
{
    ProcessCSV $auditInfoCSVPath
}
else 
{
    Write-Host "`nYou did not specify a csv file containing audit data...." -ForegroundColor Cyan

    $csvPathEntryReponse = Read-Host "Would you like to enter the full path of the csv file? [y|n]"
    if($csvPathEntryReponse -eq 'y') {
        do {
            $path = Read-Host "Enter full path to the csv file containing audit data."
        }
        until (![string]::IsNullOrWhiteSpace($path))

        ProcessCSV $path
    }
    else {
        Write-Host "`nSearching for individual document(s)..." -BackgroundColor White -ForegroundColor Black

        if([string]::IsNullOrWhiteSpace($class))
        {
            do {
                $class = Read-Host "Specify the class of document e.g. ATT, APS etc."
            }
            until (![string]::IsNullOrWhiteSpace($class))
        }

        $row = @{InvoiceNumber=$invoiceNum;Class=$class;VendorNumber=$vendorNum;VendorName=$vendorName;ModifiedStartDate=$modifiedStartDate;ModifiedEndDate=$modifiedEndDate;VoucherId=$voucherId;InvoiceTotal=$invoiceTotal;PONumber=$poNumber}

        Write-Host "`nYou are looking for invoice number '$invoiceNum' & vendor number '$vendorNum' & vendor name '$vendorName' & document of class '$class'..." -BackgroundColor White -ForegroundColor Black
    
        GetDocument $row | Out-Null
    }
}

Write-Host "`nDone - $(Get-Date)" -ForegroundColor Yellow
