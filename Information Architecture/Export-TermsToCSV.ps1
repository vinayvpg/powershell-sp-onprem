<#  
.Description  
    Exports term sets for a managed metadata service into csv files
         
.Parameter - siteUrl 
    Url of site associated with term store
.Parameter - outputDir 
    Directory to output csvs to
.Usage 
    Exports entire term store into individual csv files
     
    PS >  Export-TermsToCSV.ps1 -siteUrl "http://my.site.url" -outputDir "c:\temp\termsets"
#>
[CmdletBinding()]
param(    
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Url of a site collection in the farm associated with the target managed metadata service")]
    [string] $siteUrl="http://teams.murphyoilcorp.com",
    
    [Parameter(Mandatory=$false, Position=1, HelpMessage="Directory to create termset csv")]
    [string] $outputDir="E:\Scripts\Information Architecture\TermSets\1"
)

$ErrorActionPreference = "Continue"

if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell *> $null
}

cls
 
  function Get-TermSetsCSV() {
     param($SiteUrl, $CSVOutput)
  
    $empty = ""
 
    Write-Host "`nConnecting to site '$siteUrl'...." -NoNewline

    $taxonomySite = Get-SPSite -Identity $SiteUrl

    Write-Host "Done" -BackgroundColor Green

    Write-Host "`nConnecting to managed metadata service associated with site...." -NoNewline
    
     #Connect to Term Store in the Managed Metadata Service Application
    $taxonomySession = Get-SPTaxonomySession -site $taxonomySite

    Write-Host "Done" -BackgroundColor Green

    Write-Host "`nGetting default term store in managed metadata service associated with site...." -NoNewline 

    $taxonomyTermStore =  $taxonomySession.TermStores | Select Name
    $termStore = $taxonomySession.TermStores[$taxonomyTermStore.Name]
 
    Write-Host "Term store: $($termStore.Name)..." -NoNewline 
    Write-Host "Done" -BackgroundColor Green
 
    Write-Host "`n"
   
    # identify term groups that should not be exported (they are farm specific)
    $skipGroup = @('People', 'System', 'Search Dictionaries')

   foreach ($group in $termStore.Groups)
   {
       Write-Host "Exporting group: $($group.Name)..." -NoNewline

       if($skipGroup -contains $group.Name) {
            Write-Host "Skipping" -BackgroundColor Cyan
       }
       else {
              foreach($termSet in $group.TermSets)
         {
            $terms = @()
 
              #The path and file name, in this case I did C:\TermSet\TermSetName.csv
             $CSVFile = $CSVOutput + '\' + $group.Name + '_' + $termSet.Name + '.csv'
  
           #From TechNet: The first line of the file must contain 12 items separated by commas
             $firstLine = New-TermLine -TermSetName $termSet.Name -TermSetDescription $empty -LCID $empty -AvailableForTagging "TRUE" -TermDescription $empty -Level1 $empty -Level2 $empty -Level3 $empty -Level4 $empty -Level5 $empty -Level6 $empty -Level7 $empty
            $terms+=$firstLine
             #Now we start to add a line in the file for each term in the term set
             foreach ($term in $termSet.GetAllTerms())
            {
 
                 $tempTerm = $term
                $counter = 0
                 $tempTerms = @("","","","","","","")
 
               #this while loop makes sure you are using the root term then counts how many child terms there are 
                while (!$tempTerm.IsRoot)
                 {
                    $tempTerm = $tempTerm.Parent
                     $counter = $counter + 1
                 }
 
                 $start = $counter
  
                #this makes sure that any columns that would need to be empty are empty
                #i.e. if the current term is 3 levels deep, then the 4th, 5th, and 6th level will be empty
                while ($counter -le 6)
                {
                     $tempTerms[$counter] = $empty
                       $counter = $counter + 1
              }

                  #start with the current term
                 $tempTerm = $term
 
                #fill in the parent terms of the current term (there should never be children of the current term--the child term will have its own line in the CSV)
             while ($start -ge 0)
                  {
                     $tempTerms[$start] = $tempTerm.Name
                      $tempTerm = $tempTerm.Parent
                      $start = $start - 1
               }
  
                #create a new line in the CSV file
                 $CSVLine = New-TermLine -TermSetName $empty -TermSetDescription $empty -LCID $empty -AvailableForTagging "TRUE" -TermDescription $empty -Level1 $tempTerms[0] -Level2 $tempTerms[1] -Level3 $tempTerms[2] -Level4 $tempTerms[3] -Level5 $tempTerms[4] -Level6 $tempTerms[5] -Level7 $tempTerms[6]
 
                 #add the new line
               $terms+=$CSVLine
             }

             #export all of the terms to a CSV file
            $terms | Export-Csv $CSVFile -notype
         }
         
         Write-Host "Done" -BackgroundColor Green
       }

   }
    
    $taxonomySite.dispose()
 }
 
 #constructor
 function New-TermLine() {
      param($TermSetName, $TermSetDescription, $LCID, $AvailableForTagging, $TermDescription, $Level1, $Level2, $Level3, $Level4, $Level5, $Level6, $Level7)
 
      $term = New-Object PSObject
 
     $term | Add-Member -Name "TermSetName" -MemberType NoteProperty -Value $TermSetName
     $term | Add-Member -Name "TermSetDescription" -MemberType NoteProperty -Value $TermSetDescription
    $term | Add-Member -Name "LCID" -MemberType NoteProperty -Value $LCID
     $term | Add-Member -Name "AvailableForTagging" -MemberType NoteProperty -Value $AvailableForTagging
     $term | Add-Member -Name "TermDescription" -MemberType NoteProperty -Value $TermDescription
     $term | Add-Member -Name "Level1" -MemberType NoteProperty -Value $Level1
       $term | Add-Member -Name "Level2" -MemberType NoteProperty -Value $Level2
      $term | Add-Member -Name "Level3" -MemberType NoteProperty -Value $Level3
    $term | Add-Member -Name "Level4" -MemberType NoteProperty -Value $Level4
    $term | Add-Member -Name "Level5" -MemberType NoteProperty -Value $Level5
     $term | Add-Member -Name "Level6" -MemberType NoteProperty -Value $Level6
     $term | Add-Member -Name "Level7" -MemberType NoteProperty -Value $Level7
 
     return $term
  }
 
 Get-TermSetsCSV -SiteUrl $siteUrl -CSVOutput $outputDir