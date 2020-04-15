SELECT
hist.CrawlId, hist.CrawlType, hist.ContentSourceId, hist.StartTime, hist.Status, hist.SubStatus,
ccState.ComponentID, ccState.Status as ccStatus, ccState.SuspendedCount
FROM [**SEARCHADMIN**].[dbo].[MSSCrawlHistory] AS hist WITH (nolock)
INNER JOIN
[**SEARCHADMIN**].[dbo].[MSSCrawlComponentsState] AS ccState
ON hist.CrawlId=ccState.CrawlId
WHERE hist.Status Not In (5,11,12)
AND hist.CrawlId > 2
**WHERE**
ORDER BY hist.CrawlId DESC