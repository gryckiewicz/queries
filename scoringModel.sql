set nocount on

declare @scoringDate date
declare @marketDate date
declare @LTVDate date

set @scoringDate = Investor_Reporting.dbo.fGetPriorBusinessDate(getdate())

set @marketDate = (select max(reportDate)
						from dev_analytical_modeling.dbo.T_freddieMarketRates)

set @LTVDate = (select MAX(runDate)
					from Loanlevel_Database.dbo.T_LoanToValue)	
						

-- currentMarketRates
IF OBJECT_ID('tempdb..#marketRates') IS NOT NULL DROP TABLE #marketRates
select *
into #marketRates
from dev_analytical_modeling.dbo.T_freddieMarketRates f
where f.reportDate = @marketDate			



					
-- Population for Analysis
IF OBJECT_ID('tempdb..#loanLevel') IS NOT NULL DROP TABLE #loanLevel
select 
a.[acct number] as accountNumber
,a.fico
,a.[note rate] as currentRate
,a.[prin bal] as UPB
,CONVERT(int,a.[prin bal] * .015) as closingCosts
,g.[close date] as closingDate
,g.[prop state] as propertyState
,CONVERT(int,g.term/12) as originalTerm
,case when CONVERT(int,g.term/12) between 1 and 20 then 15
	when CONVERT(int,g.term/12) >= 21 then 30
	end as proposedTerm
,g.[maturity date] as maturityDate
,a.[pi constant] as currentPayment
,case when v.CONTRACT_NUMBER = 0 or v.CONTRACT_NUMBER is null then 'Fixed'
		when v.LOAN_ALTERNATIVE_FREEZE_CODE = 'M' and v.CONTRACT_NUMBER != 0 and v.CONTRACT_NUMBER is not null then 'Fixed'
		else 'ARM'
		end as 'interestType'
,1.11 as proposedRate
,1.11 as proposedPoints
,1 as proposedRefiTotal
,convert(numeric(8,2),1) as impliedPayment
,m.rate30Year
,m.feesPoints30Year
,m.rate15Year
,m.feesPoints15Year
,m.rate5to1ARM
,m.feesPoints5to1ARM
,ltv.mostRecentValuation
,ltv.loanToValue
,ltv.mostRecentValuationSource
into #loanLevel
from Loanlevel_Database.dbo.Loanlevel_Archive a with(nolock)
inner join Loanlevel_Database.dbo.[Deal Names] d with(nolock) on d.[Investor Number] = a.[eff inv cd]
	and d.INVESTOR_CODE_CATEGORY not in ('DEFICIENCY','CHARGE-OFF')
left join Loanlevel_Database.dbo.GeneralTable g with(nolock) on g.[acct number] = a.[acct number]
left join SQLPRD62.DatamartAnalytics.dbo.V_RPT_LOAN v with(nolock) on v.ACCOUNT_NUMBER = a.[acct number]
left join Loanlevel_Database.dbo.T_LoanToValue ltv with(nolock) on ltv.accountNumber = a.[acct number]
	and ltv.runDate = @LTVDate
left join #marketRates m on m.reportDate = @marketDate
where a.[close code] in (1,6)
and a.[lien position] = 1
and a.[run date] = @scoringDate
and a.[overall MBA] not in ('REO','Foreclosure','Bankruptcy')
and g.[maturity date] > @scoringDate
and a.fico >= 650
and g.[prop state] in ('NY','CA')



-- Getting Payment History
IF OBJECT_ID('tempdb..#PaymentString') IS NOT NULL DROP TABLE #PaymentString
CREATE TABLE #PaymentString 
(           accountNumber int,
	        consecutiveCurrentCount int,
	        numberMonthsOver90DQ int,
	        runDate date,
	        startMBAPaymentsDue int)
	        
declare @reportDate date
set @reportDate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(@scoringDate)

Insert into #PaymentString (accountNumber,consecutiveCurrentCount,numberMonthsOver90DQ,runDate,startMBAPaymentsDue)
	select a.[acct number]
	,case when a.[mba payments due] < 1 then 1 else 0 end
	,case when a.[mba payments due] >= 3 then 1 else 0 end
	,a.[run date]
	,a.[mba payments due]
	from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a
	inner join #loanLevel l on l.accountNumber = a.[acct number]
	where a.[run date] = @reportDate

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
														else consecutiveCurrentCount end,
						numberMonthsOver90DQ = numberMonthsOver90DQ + l.DQ90Again
					 
					from (
						  select
						  l.[acct number]
						  ,case when l.[mba payments due] < 1 then 1 else 0 end as previousCurrent
						  ,case when l.[mba payments due] >= 3 then 1 else 0 end as DQ90Again
						  from Loanlevel_Database.dbo.Loanlevel_EOM_13Months l with(nolock)
						  where l.[run date] = @dateLoop
						  and l.[close code] in (1,6)
						) l
					where #PaymentString.accountNumber = l.[acct number] and #PaymentString.runDate = @reportDate

			set @dateLoop = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-1,@dateLoop))	
			set @loopCount = @loopCount + 1
		end


-- Updating Loan Level for Proposed Rate and Fees
UPDATE #loanLevel 
set proposedRate = l.rate5to1ARM
from #loanLevel l
where l.interestType = 'ARM'

UPDATE #loanLevel 
set proposedRate = l.rate30Year
from #loanLevel l
where l.interestType = 'FIXED' and l.proposedTerm = 30

UPDATE #loanLevel 
set proposedRate = l.rate15Year
from #loanLevel l
where l.interestType = 'FIXED' and l.proposedTerm = 15

UPDATE #loanLevel 
set proposedPoints = l.feesPoints5to1ARM
from #loanLevel l
where l.interestType = 'ARM'

UPDATE #loanLevel 
set proposedPoints = l.feesPoints30Year
from #loanLevel l
where l.interestType = 'FIXED' and l.proposedTerm = 30

UPDATE #loanLevel 
set proposedPoints = l.feesPoints15Year
from #loanLevel l
where l.interestType = 'FIXED' and l.proposedTerm = 15

--update loan level to get proposed total finance amount
UPDATE #loanLevel
set proposedRefiTotal = convert(int,l.UPB) + convert(int,l.closingCosts) + convert(int,(l.UPB * (l.proposedPoints/100)))
from #loanLevel l

--update loan level to get implied payment
UPDATE #loanLevel
set impliedPayment = dev_analytical_modeling.dbo.f_getPaymentAmount(l.proposedRate,l.proposedTerm,l.proposedRefiTotal)
from #loanLevel l


select 
l.accountNumber
,l.UPB
,l.closingCosts
,l.closingDate
,l.maturityDate
,l.currentPayment
,l.currentRate
,l.originalTerm
,l.proposedTerm
,l.proposedRate
,l.proposedPoints
,l.proposedRefiTotal
,l.impliedPayment
,l.impliedPayment - l.currentPayment as paymentAdjustment
,l.fico
,l.propertyState
,l.interestType
,l.loanToValue
,l.mostRecentValuation
,l.mostRecentValuationSource
,p.consecutiveCurrentCount
,p.numberMonthsOver90DQ
--,dev_analytical_modeling.dbo.f_getPaymentAmount(l.proposedRate,l.proposedTerm,l.proposedRefiTotal) as impliedPayment
from #loanLevel l
inner join #PaymentString p on p.accountNumber = l.accountNumber
where l.impliedPayment < l.currentPayment
and p.consecutiveCurrentCount > 0
order by 2 desc

