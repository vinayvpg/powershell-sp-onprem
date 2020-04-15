SELECT
  CrawlId,
  SUM (SuccessCount) as Successes,
  SUM (ErrorCount) as Errors,
  SUM (DeleteCount) as Deletes,
  SUM (NotModifiedCount) as NotModified,
  SUM (SecurityOnlyCount) as SecurityOnly,
  SUM (WarningCount) as Warnings,
  SUM (RetryCount) as Retries
FROM [**SEARCHADMIN**].[dbo].[MSSCrawlComponentsStatistics]
**WHERE**
GROUP By CrawlId
ORDER BY CrawlId DESC