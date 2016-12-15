set nocount on

declare @startDate date
declare @endDate date
--declare @testDate date

set @startDate = '1/1/2011'
--set @endDate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(getdate())
set @endDate = '11/30/2016'
--set @testDate = '12/31/2016'

create table #invCodes (invCode int)

insert into #invCodes 
values (69),(913),(914),(930),(940),(941),(942),(945),(946),(947),(948),(950),(951),(952),(953),(954),(955),(956),(960),(961),(962),(963),(964),(965),(966),(967),(968),(969),(970),(971),(972),(973),(974),(975),(976),(978),(980),(981),(983),(990),(991),(992),(993),(2096),(2097)



--badInvCodes
select distinct
a.[acct number]
into #badCodes
from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a
where a.[run date] >=@startDate
and a.[eff inv cd] in (934,932)

--chargeOffData
select distinct
a.[acct number] as accountNumber
,a.[prin bal] as currentUPB
,a.[run date] as currentRunDate
,ISNULL(Investor_Reporting.dbo.fGetLastDateForCurrentMonth(v.loan_charge_off_date),'12/31/2028') as chargeOffMonth
,a2.[prin bal] as chargeOffUPB
,case when s.delq_route_code between 1 and 10 then '10'
	else s.delq_route_code 
	end as routeCode 
,case when a.[lien position] in (1,2) then 'Secured'
	when a.[lien position] >= 3 then 'Unsecured'
	else 'error' end as loanType
,case when DATEDIFF(d,a.[serv begin date],a2.[run date]) <= 30 then 'acquired Charge-Off'
		when DATEDIFF(d,a.[serv begin date],a2.[run date]) > 30 then 'organic Charge-Off'
		else 'no data' end as chargeOffSource 
into #currentRecovery
from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a with(nolock)
inner join #invCodes i on i.invCode = a.[eff inv cd]
left join [sqlprd62].DATAMARTANalytics.dbo.v_rpt_loan v with(nolock) on a.[acct number] = v.account_number
left join Loanlevel_Database.dbo.Loanlevel_Archive a2 with(nolock) on a2.[acct number] = v.account_number
		and a2.[run date] = v.loan_charge_off_date
left join #badCodes b on b.[acct number] = a.[acct number]
left join [sqlprd62].[DataMartAnalytics].[dbo].[V_Rpt_Snapshot_MonthEnd_Loan] s with(nolock) on s.account_number = a.[acct number]
			and s.data_as_of_date = a.[run date] 
where a.[run date] = @endDate
and a.[close code] in (1,6)
and b.[acct number] is null


--data from payments on loan list
select 
v.Account_Number as accountNumber
,Investor_Reporting.dbo.fGetLastDateForCurrentMonth(v.Tran_Date) as paymentEOMDate
,sum(v.Tran_Amount_Interest) as interestPayments
,sum(v.Tran_Amount_Principal) as principalPayments
,SUM(v.Tran_Amount_Principal + v.Tran_Amount_Interest) as totalPayments
into #payments
from sqlprd62.datamartanalytics.dbo.V_Rpt_Loan_Activity_Financial v with(nolock)
inner join #currentRecovery c on c.accountNumber = v.Account_Number
where v.TRAN_DATE between '1/1/2007' and @endDate
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



--details on loan data
select
c.chargeOffSource
,c.loanType
,c.routeCode
,DATEDIFF(m,c.chargeOffMonth,c.currentRunDate) as currentMonthsSinceCharge
,SUM(isnull(c.chargeOffUPB,0)) as chargeOffUPB
,sum(isnull(c.currentUPB,0)) as currentUPB
--,SUM(isnull(p.totalPayments,0)) as totalPayments
,sum(case when p.paymentEOMDate = @endDate then isnull(p.totalPayments,0) else 0 end) as lastMonthPayment
from #currentRecovery c with(nolock) 
left join #payments p with(nolock) on p.accountNumber = c.accountNumber
			and p.paymentEOMDate = @endDate
group by 
c.chargeOffSource
,c.loanType
,c.routeCode
,DATEDIFF(m,c.chargeOffMonth,c.currentRunDate)


drop table #currentRecovery
drop table #payments
drop table #invCodes
drop table #badCodes