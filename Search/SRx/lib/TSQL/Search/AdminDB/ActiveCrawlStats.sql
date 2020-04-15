SELECT **TOP** 
MSSCrawlHistory.CrawlId,
SUM(MSSCrawlComponentsStatistics.SuccessCount) AS Successes,
SUM(MSSCrawlComponentsStatistics.ErrorCount) AS Errors,
SUM(MSSCrawlComponentsStatistics.WarningCount) AS Warnings,
SUM(MSSCrawlComponentsStatistics.RetryCount) AS RetryCount
FROM [**SEARCHADMIN**].[dbo].[MSSCrawlHistory] WITH (nolock)
INNER JOIN [**SEARCHADMIN**].[dbo].[MSSCrawlComponentsStatistics]
ON MSSCrawlHistory.CrawlId = MSSCrawlComponentsStatistics.CrawlId
WHERE MSSCrawlHistory.Status Not In (5,11,12)
GROUP By MSSCrawlHistory.CrawlId
ORDER BY MSSCrawlHistory.CrawlId DESC