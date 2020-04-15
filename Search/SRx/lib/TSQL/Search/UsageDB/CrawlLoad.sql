/****** Get Crawl Load Performance Counters from Usage DB ******/
SELECT 
	Top 100000 
	LogTime, MachineName, CrawlComponentId, CrawlId, GathererDelayed, GathererTransactionsStarted, GathererTransactionsBeingFiltered, GathererInProgress, GathererCompleteTransactions, CTSSubmitted, WaitingInContentPlugin, SubmittedToSPO, WaitingInAzurePlugin, WaitingInAzurePluginThrottling
  FROM [**USAGEDB**].[dbo].[Search_CrawlLoad]
  WHERE LogTime >= DATEADD(minute, **MINUTES**, **UTCENDTIME**) 
    AND LogTime < **UTCENDTIME**
    **FILTER**
  ORDER BY LogTime