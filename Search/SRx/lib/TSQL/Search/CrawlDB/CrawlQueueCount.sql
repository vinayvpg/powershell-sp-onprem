/****** Count all items in the Crawl Queue ******/
SELECT MSSCrawlHistory.CrawlId,Count(MSSCrawlQueue.DocID) AS ItemsInQueue
FROM [**SEARCHADMIN**].[dbo].[MSSCrawlHistory] WITH (nolock)
INNER JOIN [**CRAWLSTORE**].[dbo].[MSSCrawlQueue]
ON MSSCrawlHistory.CrawlId = MSSCrawlQueue.CrawlId
GROUP By MSSCrawlHistory.CrawlId
