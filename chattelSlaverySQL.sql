set nocount on


IF OBJECT_ID('tempdb..#PaymentString') IS NOT NULL DROP TABLE #PaymentString
CREATE TABLE #PaymentString 
(           accountNumber int,
	        consecutiveCurrentCount int,
	        runDate date,
	        lienPosition int,
	        startMBAPaymentsDue int,
	        waterfallFlag varchar(100))



declare @prevEOM date

set @prevEOM = Investor_Reporting.dbo.fGetLastDateForPriorMonth(GETDATE())


--start report date loop

declare @reportDate date
set @reportDate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(dateadd(m,-1,GETDATE()))

declare @reportStart date
set @reportStart = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-14,@reportDate))

--declare @startAnalDate date
declare @callStart date

--set @startAnalDate = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-35,@reportDate))
set @callStart = Investor_Reporting.dbo.fGetFirstDateOfMonth(@reportStart)



while @reportDate > @reportStart
begin


Insert into #PaymentString (accountNumber,consecutiveCurrentCount,runDate,lienPosition,startMBAPaymentsDue,waterfallFlag)
	select a.[acct number]
	,case when a.[mba payments due] < 1 then 1 else 0 end
	,a.[run date]
	,a.[lien position]
	,a.[mba payments due]
	,case when DN.[Investor Number] in (1894,1895) then 'Waterfall'
		else 'Non-Waterfall'
		end as waterfallFlag
	from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a
	inner join Loanlevel_Database.dbo.[Deal Names] DN on DN.[Investor Number]=a.[eff inv cd]
		and DN.INVESTOR_CODE_CATEGORY not in ('DEFICIENCY','CHARGE-OFF')
	where a.[close code] in (1,6)
	and [run date]=@reportDate
	and datediff(m,a.[serv begin date],a.[run date])>2
	and a.[overall MBA] not in ('REO','Foreclosure')

		--start 36 month payment string loop
		declare @monthLookback int = 35 
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
						  and l.[close code] in (1,6)
						) l
					where #PaymentString.accountNumber = l.[acct number] and #PaymentString.runDate = @reportDate

			set @dateLoop = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-1,@dateLoop))	
			set @loopCount = @loopCount + 1
		end

set @reportDate = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-1,@reportDate)) 		
end

-- Subquery for loanLevel
IF OBJECT_ID('tempdb..#loanLevel') IS NOT NULL DROP TABLE #loanLevel
select 
p.accountNumber
,p.consecutiveCurrentCount
,p.waterfallFlag
,p.runDate
,p.startMBAPaymentsDue
,p.lienPosition
into #loanLevel
from #PaymentString p


create nonclustered index ixAccRunDate on #loanLevel (accountNumber,runDate);

-- Subquery for Call Data
IF OBJECT_ID('tempdb..#calls') IS NOT NULL DROP TABLE #calls
select 
callMonth = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(t.[callStartDate]),
accountNumber = t.accountNumber,
dials = SUM(t.[attempt]),
uniquedials = case when SUM(t.[attempt]) > 0 then 1 else 0 end,
outboundRPC = SUM(case when t.[rightpartycontact] = 1 and t.typeofCall = 'outgoing' then 1 else 0 end),
uniqueRPC = case when SUM(case when t.[rightpartycontact] = 1 and t.typeofCall = 'outgoing' then 1 else 0 end) > 0 then 1 else 0 end,
inboundCalls = sum(t.[offered])
into #calls
from Performance_Books.dbo.T_CALL_DATA t with(nolock)
where t.[callStartDate] between @callStart and @prevEOM
group by 
Investor_Reporting.dbo.fGetLastDateForCurrentMonth(t.[callStartDate]),
t.accountNumber

create nonclustered index ixAccCallDate on #calls (accountNumber,callMonth);


-- dates subquery because the data sucks
IF OBJECT_ID('tempdb..#dates') IS NOT NULL DROP TABLE #dates
select distinct
l.runDate
,Investor_Reporting.dbo.fGetLastBusinessDateForCurrentMonth(l.runDate) as lastBusinessDate
into #dates
from #loanLevel l


-- Subquery for Call Exceptions
IF OBJECT_ID('tempdb..#callExceptions') IS NOT NULL DROP TABLE #callExceptions
select
a.accountNumber
,a.runDate as reportDate
,d.runDate
,case when achStartDate <= l.runDate then 'Y' else 'N' end as 'ACH_Setup'
,case when a.uncontrollableReason = 'Y' or a.badPhoneNumber = 'Y' or a.highRiskFlag = 'Y' then 'Nondialable'
		else 'Dialable'
		end as callExceptions
into #callExceptions
from Loanlevel_Database.dbo.T_CallCenterExceptions a with(nolock)
inner join #dates d on d.lastBusinessDate = a.runDate
inner join #loanLevel l on l.accountNumber = a.accountNumber and l.runDate = d.runDate
where 
a.lossMitFlag_CRW = 'N'
and a.lossMitFlag_Fiserv = 'N'

-- final
select
l.runDate
,l.consecutiveCurrentCount
,l.waterfallFlag
,ce.ACH_Setup
,ce.callExceptions
,case when l.startMBAPaymentsDue >= 3 then '90+ Days DQ'
	when l.startMBAPaymentsDue = 2 then '60 Days DQ'
	when l.startMBAPaymentsDue = 1 then '30 Days DQ'
	when l.consecutiveCurrentCount between 1 and 2 then 'Current'
	when l.consecutiveCurrentCount between 3 and 5 then '3+ Months Clean'
	when l.consecutiveCurrentCount between 6 and 11 then '6+ Months Clean'
	when l.consecutiveCurrentCount between 12 and 23 then '12+ Months Clean'
	when l.consecutiveCurrentCount between 24 and 35 then '24+ Months Clean'
	when l.consecutiveCurrentCount = 36 then '36 Months Clean'
	end as payStringHistory
,case when l.lienPosition = 1 then '1st Liens'
	when l.lienPosition >= 2 then '2nd Liens'
	end as lienPosition
,count(*) as loanCount
,sum(c.dials) as dials
,sum(c.uniquedials) as uniquedials
,sum(c.inboundCalls) as inboundCalls
,sum(c.outboundRPC) as outboundRPC
,sum(c.uniqueRPC) as uniqueRPC
from #loanLevel l
left join #calls c on c.accountNumber = l.accountNumber
		and DATEDIFF(M,l.runDate,c.callMonth) = 1
inner join #callExceptions ce on ce.accountNumber = l.accountNumber
		and ce.runDate = l.runDate
group by
l.runDate
,l.consecutiveCurrentCount
,l.waterfallFlag
,ce.ACH_Setup
,ce.callExceptions
,case when l.startMBAPaymentsDue >= 3 then '90+ Days DQ'
	when l.startMBAPaymentsDue = 2 then '60 Days DQ'
	when l.startMBAPaymentsDue = 1 then '30 Days DQ'
	when l.consecutiveCurrentCount between 1 and 2 then 'Current'
	when l.consecutiveCurrentCount between 3 and 5 then '3+ Months Clean'
	when l.consecutiveCurrentCount between 6 and 11 then '6+ Months Clean'
	when l.consecutiveCurrentCount between 12 and 23 then '12+ Months Clean'
	when l.consecutiveCurrentCount between 24 and 35 then '24+ Months Clean'
	when l.consecutiveCurrentCount = 36 then '36 Months Clean'
	end
,case when l.lienPosition = 1 then '1st Liens'
	when l.lienPosition >= 2 then '2nd Liens'
	end