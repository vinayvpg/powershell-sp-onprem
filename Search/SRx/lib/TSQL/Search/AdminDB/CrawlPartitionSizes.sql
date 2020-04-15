SELECT [PartitionID]
      ,[MasterPartitionID]
      ,[MasterPartitionName]
      ,[CrawlStoreID]
      ,[CrawlStoreName]
      ,[HostName]
      ,[DocumentCount]
  FROM [**SEARCHADMIN**].[dbo].[MSSCrawlPartitionSizes] WITH (nolock)