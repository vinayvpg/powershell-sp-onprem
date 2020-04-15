[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="UNC path of entity extraction csv file")]
    [string] $entityExtractDictPath = "\\AZUSPEWEB01\Scripts\Infrastructure\DCTMLegacyFolderPathWordPartExtractDictionary1.csv"
)

$ErrorActionPreference = "Stop"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

#------------------ main script --------------------------------------------------
write-host "Start - $(Get-Date)`n" -ForegroundColor Yellow

if([string]::IsNullOrWhiteSpace($entityExtractDictPath))
{
    do {
        $entityExtractDictPath = Read-Host "Specify the full UNC path to the custom entity extraction CSV file"
    }
    until (![string]::IsNullOrWhiteSpace($entityExtractDictPath))
}

Write-Host "Custom entity extraction dictionary path $entityExtractDictPath..."

try {
    [ValidateSet('Word','WordPart','ExactWord','ExactWordPart')] $dictTypeResponse = Read-Host "What type of dictionary is this? [Word|WordPart|ExactWord|ExactWordPart]"
}
catch {}

if(($dictTypeResponse -eq 'Word') -or ($dictTypeResponse -eq 'WordPart') -or ($dictTypeResponse -eq 'ExactWord') -or ($dictTypeResponse -eq 'ExactWordPart')) {
    $dictionaryName = [string]::Empty
    if(($dictTypeResponse -eq 'Word') -or ($dictTypeResponse -eq 'WordPart')){
        try {
            [ValidateSet('1','2','3','4','5')] $dictNameOrderResponse = Read-Host "Specify dictionary name order. Any existing dictionary at that order will be replaced.? [1|2|3|4|5]"
            $dictionaryName = "Microsoft.UserDictionaries.EntityExtraction.Custom." + $dictTypeResponse + "." + $dictNameOrderResponse
        }
        catch {}
    }
    elseif(($dictTypeResponse -eq 'ExactWord') -or ($dictTypeResponse -eq 'ExactWordPart')) {
        $dictionaryName = "Microsoft.UserDictionaries.EntityExtraction.Custom." + $dictTypeResponse + ".1"
    }

    if(![string]::IsNullOrEmpty($dictionaryName)) {
        Write-Host "Getting default search service application..." -NoNewline
        
        $ssa = Get-SPEnterpriseSearchServiceApplication

        Write-Host "Name: '$($ssa.Name)' Id: $($ssa.Id)..." -NoNewline

        Write-Host "Done" -BackgroundColor Green

        Write-Host "Importing..." -NoNewline

        Import-SPEnterpriseSearchCustomExtractionDictionary -SearchApplication $ssa -FileName $entityExtractDictPath -DictionaryName $dictionaryName

        Write-Host "Done" -BackgroundColor Green
    }
}
else {
    Write-Warning "Invalid dictionary type. Dictionary was not imported"
}

Write-host "`nDone - $(Get-Date)" -ForegroundColor Yellow