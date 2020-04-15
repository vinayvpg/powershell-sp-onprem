/****** Get Crawl Load Performance Counters from Usage DB ******/
SELECT 
	Top 100000 
	LogTime, MachineName, CPUUsage, MemoryUsage, MssearchCPU, MssearchMemory, TimerCPU, TimerMemory, NoderunnerCPU, NoderunnerMemory, MssdmnCPU, MssdmnMemory
  FROM [**USAGEDB**].[dbo].[Search_SystemMetrics]
  WHERE LogTime >= DATEADD(minute, **MINUTES**, **UTCENDTIME**) 
    AND LogTime < **UTCENDTIME**
    **FILTER**
  ORDER BY LogTime


  