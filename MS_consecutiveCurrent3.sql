set nocount on

declare @prevEOM date

set @prevEOM = Investor_Reporting.dbo.fGetLastDateForPriorMonth(GETDATE())

CREATE TABLE #PaymentString 
(           accountNumber int,
	        consecutiveCurrentCount int,
	        runDate date)

declare @reportDate date
set @reportDate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(Getdate())

declare @reportStart date
set @reportStart = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-7,@reportDate))
--set @reportStart =  '1/31/2016'

--start report date loop

while @reportDate >= @reportStart
begin

Insert into #PaymentString (accountNumber,consecutiveCurrentCount,runDate)
	select a.[acct number],1,a.[run date]
	from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a
	inner join Loanlevel_Database.dbo.[Deal Names] DN on DN.[Investor Number]=a.[eff inv cd]
		and DN.INVESTOR_CODE_CATEGORY not in ('DEFICIENCY','CHARGE-OFF')
	where a.[close code] in (1,6,9)
	and dn.deal_level_name in ('MS_S1','MS_Prime')
	and dn.[Investor Number] not in (1510,1534)
	and [run date]=@reportDate
	and a.[mba payments due] < 1

		--start 12 month payment string loop
		declare @monthLookback int = 11 
		declare @dateLoop datetime
		declare @loopCount int

		set @dateLoop = Investor_Reporting.dbo.fGetLastDateForPriorMonth(@reportDate)
		set @loopCount = 1

		while @dateLoop >= Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-@monthLookback,@reportDate))
		begin
			
			update #PaymentString 
					set consecutiveCurrentCount = case when @loopCount <= consecutiveCurrentCount  then consecutiveCurrentCount + l.previousCurrent 
														else consecutiveCurrentCount end 
					from (
						  select
						  l.[acct number]
						  ,case when l.[mba payments due] < 1 then 1 else 0 end as previousCurrent
						  from Loanlevel_Database.dbo.Loanlevel_EOM_13Months l with(nolock)
						  where l.[run date] = @dateLoop
						  and l.[close code] in (1,6,9)
						) l
					where #PaymentString.accountNumber = l.[acct number] and #PaymentString.runDate = @reportDate

			set @dateLoop = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-1,@dateLoop))	
			set @loopCount = @loopCount + 1
		end

set @reportDate = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-1,@reportDate)) 		
end


select
convert(smalldatetime,p.runDate) as runDate
,COUNT(*) as begCount
,p.consecutiveCurrentCount
,sum(case when a.[mba payments due] < 1 then 1 else 0 end ) as rollCount
,SUM(case when a2.[mba payments due] < 1 then 1 else 0 end) as currMonthRollCount
from #PaymentString p
left join Loanlevel_Database.dbo.Loanlevel_EOM_13Months a with(nolock) on a.[acct number] = p.accountNumber
			and DATEDIFF(m,p.runDate,a.[run date]) = 1
left join Loanlevel_Database.dbo.Loanlevel_Current a2 with(nolock) on a2.[acct number] = p.accountNumber
			and p.runDate = @prevEOM
group by
p.runDate
,p.consecutiveCurrentCount

drop table #PaymentString



