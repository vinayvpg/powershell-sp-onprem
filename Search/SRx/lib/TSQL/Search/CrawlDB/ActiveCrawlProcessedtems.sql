/****** Count all items that this Crawl has processed on this CRAWLSTORE ******/
SELECT MSSCrawlHistory.CrawlId,Count(MSSCrawlUrl.DocID) AS AllItemsProcessed
FROM [**SEARCHADMIN**].[dbo].[MSSCrawlHistory] WITH (nolock)
INNER JOIN [**CRAWLSTORE**].[dbo].[MSSCrawlUrl]
ON MSSCrawlHistory.CrawlId = MSSCrawlUrl.CommitCrawlId
WHERE MSSCrawlHistory.Status Not In (5,11,12)
GROUP By MSSCrawlHistory.CrawlId
