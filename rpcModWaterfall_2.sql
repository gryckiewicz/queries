set nocount on

declare @reportDate date
declare @monthStartDate date
declare @thisLastBusinessDate date

set @reportDate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(getdate())
set @monthStartDate = Investor_Reporting.dbo.fGetFirstDateOfMonth(@reportDate)
set @thisLastBusinessDate = Investor_Reporting.dbo.fGetLastBusinessDateForCurrentMonth(@reportDate)

--loanlist
select 
la.[acct number],
clientName = Case
					when dn.[Investor Number] between 5000 and 5999 then 'BANA'
					when dn.[Investor Number] between 7000 and 7999 then 'Chase'
					when dn.[Investor Number] in (1450,1452) and LA.[serv begin date] between '2/1/2015' and '3/31/2015' then 'Etrade PNC'
					when dn.[Investor Number] in (1450,1452) and LA.[serv begin date] between '4/1/2015' and '4/30/2015' then 'Etrade Ocwen'
					when dn.[Investor Number] in (1450,1452) and LA.[serv begin date] between '11/1/2015' and '11/30/2015' then 'Etrade Nationstar'
					when dn.[Investor Number] in (1450,1452) and LA.[serv begin date] < '2/1/2015' then 'Etrade Legacy'
					when dn.[Investor Number] in (325,326,327,328,329,330,331,224,225) then 'Assured CWHEQ'
					when dn.[Investor Number] = 419 then 'Assured MABS'
					when dn.Deal_Group = 'FSA' then 'Assured Other'
					when dn.Deal_Group = 'AMBAC' then 'AMBAC'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') and la.[eff inv blk] = 32 then 'MS Whole Bayview'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') and la.[eff inv blk] = 27 then 'MS Whole Hudson'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') and la.[eff inv blk] = 34 then 'MS Whole Marathon'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') and la.[eff inv blk] = 33 and la.[serv begin date] between '7/1/2016' and '7/31/2016' then 'MS Whole Neuberger Fay'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') and la.[eff inv blk] = 33 and la.[serv begin date] between '4/1/2014' and '12/31/2015' then 'MS Whole Neuberger SLS'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') and la.[eff inv blk] = 15 then 'MS Whole PNC'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') then 'MS Whole Loan Other'
					when dn.Deal_Level_Name = 'MS_HELOC Non-Securitized' then 'MS HELOC Non-Securitized'
					when dn.Deal_Level_Name = 'MS_HELOC Securitized' then 'MS HELOC Securitized'
					when dn.Deal_Level_Name = 'MS_Non-HELOC Securitized' then 'MS Non-HELOC Securitized'
					when dn.[Investor Number] = 560 then 'Freddie Mac VPC'
					when dn.[Investor Number] between 500 and 599 then 'Freddie Mac'
					when dn.[Investor Number] between 700 and 799 then 'Fannie Mae'
					when dn.[Group] = 'Black Diamond' then 'Black Diamond'
					when dn.[Group] = 'Black Diamond 2' then 'Black Diamond 2'
					else 'Other'
					End,
la.[overall MBA],
la.[run date]
into #loanlist
from Loanlevel_Database.dbo.Loanlevel_EOM_13Months la with (nolock)
inner join Loanlevel_Database.dbo.[Deal Names] dn with(nolock) on dn.[Investor Number] = la.[eff inv cd]
		and dn.INVESTOR_CODE_CATEGORY not in ('DEFICIENCY','CHARGE-OFF')
where la.[run date] = @reportDate
and la.[close code] in (1,6)
and la.[overall MBA] != 'REO'


--exceptions, dials and RPCs
select 
ce.accountNumber,
dialable = case
			when ce.uncontrollableReason = 'Y' OR ce.highRiskFlag = 'Y' OR ce.badPhoneNumber = 'Y' then 'N'
			else 'Y'
			end,
lastDialDate = ce.lastAttemptDate,
lastRPCDate = ce.lastRightPartyContact,
ce.runDate
into #callData
from Loanlevel_Database.dbo.T_CallCenterExceptions ce with(nolock)
inner join #loanlist l on l.[acct number] = ce.accountNumber
where ce.runDate = @thisLastBusinessDate

-- Subquery for Payments
select
accountNumber = c.[Loan Number]
,count(*) as loanCount
into #payments
from Analytic_Reporting_Database.dbo.[62-01_COMBINED] c with(nolock)
inner join #loanlist l on l.[acct number] = c.[Loan Number]
inner join (select accountNumber = c.[Loan Number], MAX(c.[Report Date]) as reportDate
			from Analytic_Reporting_Database.dbo.[62-01_COMBINED] c with(nolock)
			where c.[Report Date] between @monthStartDate and @reportDate
			and ISNULL(c.[Int Activity],0) > 0
			and c.[Tran Code] in ('AP','GP','PA','PR','PT','RP','RRN','SR','SRA','SRL','SWA','SWP','CWA','CWP')
			group by c.[Loan Number]
			) c2 on c2.accountNumber = c.[Loan Number] and c2.reportDate = c.[Report Date]
where c.[Report Date] between @monthStartDate and @reportDate
and ISNULL(c.[Int Activity],0) > 0
and c.[Tran Code] in ('AP','GP','PA','PR','PT','RP','RRN','SR','SRA','SRL','SWA','SWP','CWA','CWP')
group by c.[Loan Number]

-- Loss Mit Events
select 
p.accountNumber
,p.archiveStartDate_App
into #lossMit
from Dev_Modification.dbo.T_Loss_Mitigation_Pipeline p with(nolock)
inner join #loanlist l on l.[acct number] = p.accountNumber
where p.pipelineDate = @thisLastBusinessDate
and p.activeFlag_app = 'Y'


select
l.clientName
,l.[overall MBA]
,l.[run date]
,case when c2.dialable = 'N' then 'nondialable'
		when c2.dialable = 'Y' then 'dialable'
		else 'nondialable'
		end as 'dialableNondialable'
,case when c2.lastDialDate between @monthStartDate and @reportDate then 'dialedThisMonth'
		else 'noDialThisMonth' end as 'borrowerDialed'
,case when c2.lastRPCDate between @monthStartDate and @reportDate then 'RPCThisMonth'
		else 'noRPCThisMonth' end as 'borrowerRPC'
,case when p.accountNumber is not null then 'paymentMade'
		when p.accountNumber is null then 'noPaymentMade'
		end as 'payment'
,case when m.archiveStartDate_App between @monthStartDate and @reportDate then 'newLossMitApp'
		when m.archiveStartDate_App <= @monthStartDate then 'priorActiveLossMitApp'
		else 'noLossMitApp'
		end as 'lossMit'
,COUNT(*) as loanCount
from #loanlist l
left join #callData c2 on c2.accountNumber = l.[acct number]
	and c2.runDate = @thisLastBusinessDate
left join #lossMit m on m.accountNumber = l.[acct number]
left join #payments p on p.accountNumber = l.[acct number]
group by
l.clientName
,l.[overall MBA]
,l.[run date]
,case when c2.dialable = 'N' then 'nondialable'
		when c2.dialable = 'Y' then 'dialable'
		else 'nondialable'
		end
,case when c2.lastDialDate between @monthStartDate and @reportDate then 'dialedThisMonth'
		else 'noDialThisMonth' end
,case when c2.lastRPCDate between @monthStartDate and @reportDate then 'RPCThisMonth'
		else 'noRPCThisMonth' end
,case when p.accountNumber is not null then 'paymentMade'
		when p.accountNumber is null then 'noPaymentMade'
		end 
,case when m.archiveStartDate_App between @monthStartDate and @reportDate then 'newLossMitApp'
		when m.archiveStartDate_App <= @monthStartDate then 'priorActiveLossMitApp'
		else 'noLossMitApp'
		end 


drop table #lossMit
drop table #payments
drop table #callData
drop table #loanlist


