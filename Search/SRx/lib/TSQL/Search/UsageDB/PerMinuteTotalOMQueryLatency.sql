/****** Get Query Performance Counters from Usage DB ******/
SELECT 
	Top 100000
	LogTime, MachineName, ApplicationType, ResultPageUrl, ImsFlow, CustomTags, NumQueries, TotalQueryTimeMs, IMSProxyTimeMs, QPTimeMs
  FROM [**USAGEDB**].[dbo].[Search_PerMinuteTotalOMQueryLatency]
  WHERE LogTime >= DATEADD(minute, **MINUTES**, **UTCENDTIME**)
    AND LogTime < **UTCENDTIME**
    **FILTER**
  ORDER BY LogTime