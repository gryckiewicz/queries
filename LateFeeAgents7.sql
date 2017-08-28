set nocount on 


Declare @startDate date
Declare @endDate date

Set @endDate = Investor_Reporting.dbo.fGetPriorBusinessDate(GETDATE())
--Set @endDate = Investor_Reporting.dbo.fGetLastBusinessDateForPriorMonth(GETDATE())
Set @startDate = Investor_Reporting.dbo.fGetPriorBusinessDate(Investor_Reporting.dbo.fGetLastDateforPriorMonth(dateadd(m,-2,@endDate)))


-- Subquery for Call Data
IF OBJECT_ID('tempdb..#calls') IS NOT NULL DROP TABLE #calls
select
t.callStartDateWithTimestamp as callDate,
Investor_Reporting.dbo.fGetLastDateForCurrentMonth(t.callStartDateWithTimestamp) as callMonth,
t.accountNumber as acctNum,
t.agentId as agentID,
t.callDescription
into #calls
from Performance_Books.dbo.T_CALL_DATA t with(nolock)
where t.[callStartDate] between @startDate and @endDate
and t.rightPartyContact = 1
and t.callDescription in ('PROMISE_TO_PAY','SPEEDPAY_TAKEN','PROMISE_PAY_ACH','SpeedPay with IPA','Speedpay with IPA and Promise')
and t.accountNumber != 0



-- Subquery for Employees
IF OBJECT_ID('tempdb..#employees') IS NOT NULL DROP TABLE #employees
select
e.EMPLOYEE_ID as employeeID,
e.EMPLOYEE_FULL_NAME as employeeName,
e.FISERV_TELLER_ID as fiservID,
e.EMPLOYEE_NETWORK_ID as employeeNetworkID,
e.EMPLOYEE_POSITION_DEPARTMENT_NAME as employeeDepartment
into #employees
from sqlprd62.datamartanalytics.dbo.V_Rpt_Employee e

-- Subquery for late fees collected
IF OBJECT_ID('tempdb..#collected') IS NOT NULL DROP TABLE #collected
select
c.[Loan Number] as acctNumber
,dateadd(HH,23,dateadd(MI,59,c.[Report Date])) as paymentDate
,Investor_Reporting.dbo.fGetLastDateForCurrentMonth(c.[Report Date]) as paymentMonth
,sum(isnull(c.[Int Activity],0) + isnull(c.[Prin Activity],0)) as totalPIChange
,sum(c.[Late Chg Activity]) as lateChargesCollected
into #collected
from Analytic_Reporting_Database.dbo.[62-01_COMBINED] c with(nolock)
--inner join #calls c2 on c2.acctNum = c.[Loan Number]
where c.[Report Date] between @startDate and @endDate
and (isnull(c.[Int Activity],0) + isnull(c.[Prin Activity],0) > 0 or
		c.[Late Chg Activity] > 0)
and c.[Tran Code] not in ('PF','SPO','FC','RCA','SDI')
group by 
c.[Loan Number]
,c.[Report Date]


-- Subquery for LLA
IF OBJECT_ID('tempdb..#lla') IS NOT NULL DROP TABLE #lla
select
a.[acct number] as acctNum
,a.[run date] as runDate
,a.[uncoll late fee] as uncollLateFee
into #lla
from Loanlevel_Database.dbo.Loanlevel_Archive a with(nolock)
inner join Loanlevel_Database.dbo.[Deal Names] DN on DN.[Investor Number]= a.[eff inv cd]
	and DN.INVESTOR_CODE_CATEGORY not in ('DEFICIENCY','CHARGE-OFF')
where a.[close code] in (1,6)
and a.[run date] between @startDate and @endDate
and a.[uncoll late fee] > 0 


-- loanlevel detail with calls
IF OBJECT_ID('tempdb..#loanLevel') IS NOT NULL DROP TABLE #loanLevel
select
c.acctNum
,c.callDescription
,rank() over (partition by c.acctNum,c.callMonth order by c.callDate ASC) as callRank
,c.callDate
,c.callMonth
,e.employeeName
,e.employeeDepartment
,l.uncollLateFee
into #loanLevel
from #calls c
left join #employees e on e.employeeNetworkID = c.agentID
inner join #lla l on l.acctNum = c.acctNum
	and l.runDate = Investor_Reporting.dbo.fGetPriorBusinessDate(c.callDate)
where e.employeeDepartment not in ('Charge-Off Recovery','Cashiering')


-- calls matched up with collections
IF OBJECT_ID('tempdb..#matchup') IS NOT NULL DROP TABLE #matchup
select
c.acctNumber
,l.callDate
,l.employeeName
,l.employeeDepartment
,l.uncollLateFee
,c.paymentDate
,c.totalPIChange
,c.lateChargesCollected
into #matchup
from #collected c
left join #loanlevel l on l.acctNum = c.acctNumber
	and c.paymentDate >= l.callDate
inner join (select
			l.acctNum
			,c.paymentdate
			,l.callMonth
			,max(l.callrank) as callRank
			from #collected c
			left join #loanlevel l on l.acctNum = c.acctNumber
				and c.paymentDate between l.callDate and l.callMonth
			group by l.acctNum, c.paymentdate, l.callMonth
			) c2 on c2.callrank = l.callrank
				and c2.paymentDate = c.paymentDate
				and c2.acctNum = c.acctNumber
				and c2.callMonth = l.callMonth

-- we group up the payments and pick the earliest payment date following the call. this is to remove duplicates. we'd get duplicate call entries when there was 1 call followed by 2-3 payments before the next call occurred.
IF OBJECT_ID('tempdb..#matchup2') IS NOT NULL DROP TABLE #matchup2
select
m.acctNumber
,m.callDate
,m.employeeName
,m.employeeDepartment
--,m.uncollLateFee
,MIN(m.paymentDate) as paymentDate
,SUM(m.totalPIChange) as totalPIChange
,SUM(m.lateChargesCollected) as lateChargesCollected
into #matchup2
from #matchup m
--where acctNumber = 1000111466
group by
m.acctNumber
,m.callDate
,m.employeeName
,m.employeeDepartment
--,m.uncollLateFee

select
l.*
,case when m.acctNumber is null or m.lateChargesCollected = 0 then 0
		else 1 end as lateFeeConverted
,case when m.acctNumber is not null then 'Y' else 'N' end as paymentOpportunity
,CONVERT(date,m.paymentDate) as paymentDate2
,m.lateChargesCollected
,1 as lateFeeOpportunity
from #loanlevel l
left join #matchup2 m on m.acctNumber = l.acctNum
			and m.callDate = l.callDate
--where l.acctNum = 1011385252