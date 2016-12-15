set nocount on

declare @startDate date
declare @endDate date

set @startDate = '1/1/2011'
set @endDate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(getdate())

create table #invCodes (invCode int)

insert into #invCodes 
values (69),(913),(914),(930),(940),(941),(942),(945),(946),(947),(948),(950),(951),(952),(953),(954),(955),(956),(960),(961),(962),(963),(964),(965),(966),(967),(968),(969),(970),(971),(972),(973),(974),(975),(976),(978),(980),(981),(983),(990),(991),(992),(993),(2096),(2097)


--badInvCodes
select distinct
a.[acct number]
into #badCodes
from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a with(nolock)
where a.[run date] >=@startDate
and a.[eff inv cd] in (934,932)

--chargeOffData
select 
a.[acct number] as accountNumber
,a.[run date] as chargeOffDate
,a.[prin bal] as chargeOffUPB
,case when a.[lien position] in (1,2) then 'Secured'
	when a.[lien position] >= 3 then 'Unsecured'
	else 'error' end as loanType
,case when DATEDIFF(d,a.[serv begin date],a.[run date]) <= 30 then 'acquired Charge-Off'
		when DATEDIFF(d,a.[serv begin date],a.[run date]) > 30 then 'organic Charge-Off'
		else 'no data' end as chargeOffSource 
into #chargeOffPop
from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a with(nolock)
inner join #invCodes i on i.invCode = a.[eff inv cd]
left join (select a.[acct number] as accountNumber, [run date] as runDate
			 from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a
			 inner join #invCodes i on i.invCode = a.[eff inv cd]
			 where a.[close code] in (1,6)
			 and a.[run date] >= '12/30/2010') a2 on a2.accountNumber = a.[acct number]
														and DATEDIFF(m,a2.runDate,a.[run date]) = 1	
left join #badCodes b on b.[acct number] = a.[acct number]
where a.[run date] >= @startDate
and a.[close code] in (1,6)
and a2.accountNumber is null
and b.[acct number] is null

-- Subquery for Liquidations
select
	a.accountNumber
	,liqDate = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(c.[Date of Liquidation])
	,TypeOfLiq = c.TypeOfLiq
	,liqUPB = c.PrinBal
into #liq
from (
	select
		accountNumber = c.[Loan Number]
		,maxRecordId = max(c.RECORD_ID)
	from Liquidations_Database.dbo.T_LIQUIDATIONS_CERTS c with(nolock)
	inner join #chargeOffPop c2 on c2.accountNumber = c.[Loan Number]
	where c.[Date of Liquidation] between @startDate and @endDate
	and c.TypeOfLiq not in ('Loss Correction','Loss Corrections','Charge Off')
	group by c.[Loan Number]
	) a
inner join Liquidations_Database.dbo.T_LIQUIDATIONS_CERTS c with(nolock) on a.maxRecordId = c.RECORD_ID


--loan UPB history
select 
a.[run date] as runDate
,a.[acct number] as accountNumber
,a.[prin bal] as availableUPB
into #loanHistory
from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a with(nolock)
inner join #chargeOffPop c on c.accountNumber = a.[acct number] and a.[run date] >= c.chargeOffDate
where a.[run date] >= '12/31/2010'

create nonclustered index ixAccRunDate on #loanHistory (accountNumber,runDate);



--payments
select 
v.Account_Number as accountNumber
,Investor_Reporting.dbo.fGetLastDateForCurrentMonth(v.Tran_Date) as paymentEOMDate
,sum(v.Tran_Amount_Interest) as interestPayments
,sum(v.Tran_Amount_Principal) as principalPayments
,SUM(v.Tran_Amount_Principal + v.Tran_Amount_Interest) as totalPayments
into #payments
from sqlprd62.datamartanalytics.dbo.V_Rpt_Loan_Activity_Financial v with(nolock)
inner join #chargeOffPop c on c.accountNumber = v.Account_Number
where v.TRAN_DATE >= @startDate
and (v.tran_Amount_principal <> 0 or v.tran_Amount_interest <>0)
and v.tran_type_Code in ('ADR','AP','BAP','CT','CTA','CTB','CTR','CTT','CWA','CWP','E01','E10','E20','E21','E90','EI','EIP',
'EIS','FC','FE','FEA','FP','FWA','FWC','FWP','L00','M01','M20','M70','M90','PA','PF','PR','PR0','PR2',
'PR9','PRA','PRB','PRC','PRD','PRH','PRI','PRJ','PRN','PRO','PT','R01','R02','R05','R10','R11','R12','R16','R20',
'R21','R22','R23','R25','R40','R56','R80','R82','R90','R91','R92','R93','R96','R97','RCA','REJ','RP',
'RT','RT0','RT1','RT2','RT4','RT9','RTC','SDI','SP','SPO','SR','SRA','SWA','SWP','SR0','SR7')
group by 
v.Account_Number
,Investor_Reporting.dbo.fGetLastDateForCurrentMonth(v.Tran_Date)

create nonclustered index ixAccPayDate on #payments (accountNumber,paymentEOMDate);

select
h.runDate
,c.chargeOffDate
,c.chargeOffSource
,c.loanType
,p.paymentEOMDate
,l.liqDate
,l.TypeOfLiq
,case when s.delq_route_code between 1 and 10 then '10'
	else s.delq_route_code 
	end as routeCode --attempt to add route code
,DATEDIFF(m,c.chargeOffDate,h.runDate) as monthsFromChargeOff
,SUM(l.liqUPB) as liquidationUPB
,sum(c.chargeOffUPB) as chargeOffUPB
,sum(h2.availableUPB) as availableUPB
,sum(p.principalPayments) as principalPayments
,sum(p.interestPayments) as interestPayments
,sum(p.totalPayments) as totalPayments
,COUNT(*) as loanCount
from #chargeOffPop c
left join #loanHistory h on c.accountNumber = h.accountNumber
			and h.runDate >= c.chargeOffDate
left join #loanHistory h2 on h2.accountNumber = h.accountNumber
			and DATEDIFF(m,h2.runDate,h.runDate) = 1
left join #payments p on p.accountNumber = h.accountNumber
		and DATEDIFF(m,p.paymentEOMDate,h.runDate) = 0
		and p.paymentEOMDate >= c.chargeOffDate
left join #liq l on l.accountNumber = c.accountNumber
		and l.liqDate = h.runDate
left join [sqlprd62].[DataMartAnalytics].[dbo].[V_Rpt_Snapshot_MonthEnd_Loan] s with(nolock) on s.account_number = h.accountNumber
			and s.data_as_of_date = h.runDate --attempt to add route code

group by
h.runDate
,c.chargeOffDate
,c.chargeOffSource
,c.loanType
,p.paymentEOMDate
,l.liqDate
,l.TypeOfLiq
,case when s.delq_route_code between 1 and 10 then '10'
	else s.delq_route_code 
	end --attempt to add route code

drop table #invCodes
drop table #payments
drop table #chargeOffPop
drop table #loanHistory
drop table #liq
drop table #badCodes


--select *
--from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a
--where a.[run date] between '2/28/2011' and '3/31/2011'
--and a.[acct number] = 1004071913