set nocount on

declare @endReportDate date

set @endReportDate = Investor_Reporting.dbo.fGetPriorBusinessDate(getdate())

-- main loan list (which loans are pre-evaluated for a PAMOD)

IF OBJECT_ID('tempdb..#loanlist') IS NOT NULL DROP TABLE #loanlist
select
c.[acct number]
,c.[run date]
,b.[Investor Number]
,b.[Deal Name]
,c.[overall OTS]
,c.[prin bal]
,c.[lien position]
,c.[next due]
,g.[prop state]
,g.[prop county]
,g.[prop zip code]
,c.[pi constant]
,g.[note rate]
,DATEDIFF(D,c.[next due],@endReportDate) as daysPastDue
into #loanlist
from Loanlevel_Database.dbo.Loanlevel_Current c with(nolock)
inner join (            
      select            
      *           
      from Loanlevel_Database.dbo.[Deal Names] dn with(nolock)
      where dn.Deal_Group = 'FSA'
) b               
on c.[eff inv cd] = b.[Investor Number]
left join (             
      select            
            c.investorNumber
      from Campaign_Reporting.dbo.T_CAMPAIGN_GROUPS c with(nolock)
      inner join (      
            select      
                  c.campaignName
                  ,versionNumber = max(c.versionNumber)
            from Campaign_Reporting.dbo.T_CAMPAIGN_GROUPS c with(nolock)
            where c.campaignName = 'Monarch.IndyMac.TemporaryModProgram'
            group by c.campaignName
      ) b         
      on c.campaignName = b.campaignName AND c.versionNumber = b.versionNumber
) r               
on c.[eff inv cd] = r.investorNumber
left join Loanlevel_Database.dbo.GeneralTable g with(nolock) on g.[acct number] = c.[acct number]
where r.investorNumber is null
and c.[eff inv cd] in (129,130,156,157,184,185,217,218,219,220,315,316,317,224,225,326,327,328,329,330,331,332,419)
--and DATEDIFF(d,c.[next due],@endReportDate) >= 30
and [overall OTS] != 'REO'
and [overall OTS] != 'ZERO BAL'
and c.[close code] in (1,6)


--Forbearance Loans
IF OBJECT_ID('tempdb..#forbear') IS NOT NULL DROP TABLE #forbear
create table #forbear (acctNumber numeric(10,0))

insert into #forbear 
values
(1010687207),
(1006929102),
(1010680916),
(1010681915),
(1005036643),
(1010674197),
(1005158958),
(1010675442),
(1007829942),
(1006928653),
(1007205498),
(1004997327),
(1005031473),
(1005045760)





-- Foreclosure Sales
IF OBJECT_ID('tempdb..#fclSales') IS NOT NULL DROP TABLE #fclSales
select
fcl.[acct number]
,fcl.DATE_FCL_SALE_SCHEDULED
into #fclSales
from Default_Database.dbo.ttFCLDailyCrossTab fcl with(nolock)
inner join #loanlist l on l.[acct number] = fcl.[acct number]
where DATEDIFF(D,@endReportDate,fcl.DATE_FCL_SALE_SCHEDULED) < 60



-- active LM apps
IF OBJECT_ID('tempdb..#lossMit') IS NOT NULL DROP TABLE #lossMit
select 
p.accountNumber
into #lossMit
from Dev_Modification.dbo.T_Loss_Mitigation_Pipeline p with(nolock)
inner join #loanlist l on l.[acct number] = p.accountNumber
where p.pipelineDate = (select MAX(p.pipelineDate)
						from Dev_Modification.dbo.T_Loss_Mitigation_Pipeline p with(nolock)) 
and p.activeFlag_app = 'Y'


--payment plans
IF OBJECT_ID('tempdb..#plan') IS NOT NULL DROP TABLE #plan
select
lpp.account_Number as accountNumber
into #plan
from [sqlprd62].datamartanalytics.dbo.v_rpt_loan_payment_plan lpp
inner join #loanlist l on l.[acct number] = lpp.account_Number
where plan_status_code_desc = 'Active'


--exceptions, dials and RPCs
IF OBJECT_ID('tempdb..#callData') IS NOT NULL DROP TABLE #callData
select 
ce.accountNumber
,lastRPCDate = ce.lastRightPartyContact
,ce.runDate
into #callData
from Loanlevel_Database.dbo.T_CallCenterExceptions ce with(nolock)
inner join #loanlist l on l.[acct number] = ce.accountNumber
where ce.runDate = @endReportDate

-- uncontrollable reasons
IF OBJECT_ID('tempdb..#uncontrollables') IS NOT NULL DROP TABLE #uncontrollables
select
      c.ACCOUNT_NUMBER as acctNumber
      ,uncontrollableReason = 
            case
                  when c.loan_stop_code_3 in (2,3,4,6,8,9) then 'Stop Code 1 = ' + CONVERT(varchar,c.loan_stop_code_3)
                  when c.SPECIAL_HANDLING_CODE between 1 and 99 or c.SPECIAL_HANDLING_CODE between 104 and 200 or c.SPECIAL_HANDLING_CODE in (202,203,205) then 'Special Handling Code = ' + CONVERT(varchar,c.SPECIAL_HANDLING_CODE)
                  when c.LOAN_LOCKOUT_CODE between 1 and 8 then 'Lockout Code = ' + CONVERT(varchar,c.LOAN_LOCKOUT_CODE)
                  when C.LOAN_WARNING_CODE in (2,3,4,7,9) then 'Warning Code = ' + CONVERT(varchar,c.LOAN_WARNING_CODE)
                  when uf.UF040_BK_CHAPTER7_DISCHARGE in ('MR','D7') then 'Userfield 40 - ' + CONVERT(varchar,UF.UF040_BK_CHAPTER7_DISCHARGE)
                  when c.LOAN_STOP_CODE_3 = 8 then 'Stop Code 3 = 8'
                  when uf.UF044_ATTNY_REP_AND_CD_CODE not in ('PN','') then 'Userfield 44 - Attorney - ' + CONVERT(varchar,uf.UF044_ATTNY_REP_AND_CD_CODE)
                  when c.DELQ_OVERALL_STATUS_MBA = 'BANKRUPTCY' then 'Bankruptcy'
            end
into #uncontrollables
from [sqlprd62].DatamartAnalytics.dbo.V_RPT_LOAN c with(nolock)
left join [sqlprd62].DatamartAnalytics.dbo.v_rpt_loan_user_field uf with(nolock) on c.ACCOUNT_NUMBER = uf.ACCOUNT_NUMBER
inner join #loanlist l on l.[acct number] = c.ACCOUNT_NUMBER
AND C.loan_close_code IN (1,6)

--prior campaigns raw
IF OBJECT_ID('tempdb..#camp') IS NOT NULL DROP TABLE #camp
select distinct 
ACCOUNT_NUMBER as accountNumber
,SUBSTRING(UF051_CAMPAIGN_LETTER_CODE,5,LEN(UF051_CAMPAIGN_LETTER_CODE)) as campaignCode
,convert(date,UF181_CALL_CAMPAIGN_EXPIRATION_DATE) as expirationDate
into #camp
from sqlprd62.DatamartAnalytics.DBO.V_RPT_LOAN_USER_FIELD_HISTORY with(nolock)
inner join #loanlist l on l.[acct number] = ACCOUNT_NUMBER
where UF051_CAMPAIGN_LETTER_CODE not in ('','.','SLS-RETRACTION-SENT')
and UF051_CAMPAIGN_LETTER_CODE not like '%***%'
--and UF051_CAMPAIGN_LETTER_CODE not like '%STREAM%'
--and UF051_CAMPAIGN_LETTER_CODE not like '%STL%'
--and UF051_CAMPAIGN_LETTER_CODE not like '%HAFA%'
and UF051_CAMPAIGN_LETTER_CODE not like '%HAMP%'
and isnull(UF181_CALL_CAMPAIGN_EXPIRATION_DATE,'')<>''

--prior campaign combined
IF OBJECT_ID('tempdb..#campaignHistory') IS NOT NULL DROP TABLE #campaignHistory
select 
c.accountNumber
,case when c.campaignCode like '%3TIER%' then 'Y' else 'N' end as '3Tier'
,case when c.campaignCode like '%3TIER%' then c.expirationDate else NULL end as '3_Tier_Date'
,case when c.campaignCode like '%DK%' then 'Y' else 'N' end as 'Door_Knock'
,case when c.campaignCode like '%DK%' then c.expirationDate else NULL end as 'Door_Knock_Date'
,case when c.campaignCode like '%MERCH%' then 'Y' else 'N' end as 'Merchandise'
,case when c.campaignCode like '%MERCH%' then c.expirationDate else NULL end as 'Merchandise_Date'
,case when c.campaignCode like '%STREAMLINE%' then 'Y' 
		when c.campaignCode like '%STL%' then 'Y'
		else 'N' end as 'Streamline'
,case when c.campaignCode like '%STREAMLINE%' then c.expirationDate 
		when c.campaignCode like '%STL%' then c.expirationDate
		else NULL end as 'Streamline_Date'
,case when c.campaignCode like '%HAFA%' then 'Y' else 'N' end as 'HAFA'
,case when c.campaignCode like '%HAFA%' then c.expirationDate else NULL end as 'HAFA_Date'
into #campaignHistory
from #camp c
order by 1



-- main query
IF OBJECT_ID('tempdb..#main') IS NOT NULL DROP TABLE #main
select 
l.[acct number]
,convert(date,l.[run date]) as runDate
,l.[Investor Number]
,l.[Deal Name]
,l.[overall OTS]
,l.[prin bal]
,l.[lien position]
,l.[prop state]
,l.[prop county]
,l.[prop zip code]
,convert(date,l.[next due]) as nextDueDate
,l.daysPastDue
,l.[pi constant]
,l.[note rate]
,cd.lastRPCDate
,convert(date,f.DATE_FCL_SALE_SCHEDULED) as foreclosureSaleScheduled
,case when p.accountNumber is not null then 'Y' else 'N' end as activePaymentPlan
,case when lm.accountNumber is not null then 'Y' else 'N' end as activeLossMitApp
,case when l.[overall OTS] = 'BANKRUPTCY' then 'Warning Code = 4'
		else u.uncontrollableReason end as uncontrollableReason
,case when f.[acct number] is not null then 'Y'
		when p.accountNumber is not null then 'Y'
		when lm.accountNumber is not null then 'Y'
		when u.uncontrollableReason is not null then 'Y'
		when DATEDIFF(D,cd.lastRPCDate,@endReportDate) <= 30 and fb.acctNumber is null then 'Y'
		when l.[overall OTS] = 'BANKRUPTCY' then 'Y'
		when l.daysPastDue < 30 then 'Y'
		when c1.campaignDate >= @endReportDate then 'Y'
		when c2.campaignDate >= @endReportDate then 'Y'
		when c3.campaignDate >= @endReportDate then 'Y'
		when c4.campaignDate >= @endReportDate then 'Y'
		when c5.campaignDate >= @endReportDate then 'Y'
		else 'N' end as excluded
,case when f.[acct number] is not null then 'foreclosureSalein60days'
		when p.accountNumber is not null then 'activePaymentPlan'
		when lm.accountNumber is not null then 'activeLossMitApp'
		when u.uncontrollableReason is not null then 'uncontrollableReason'
		when DATEDIFF(D,cd.lastRPCDate,@endReportDate) <= 30 and fb.acctNumber is null then 'RPCWithin30Days'
		when l.[overall OTS] = 'BANKRUPTCY' then 'uncontrollableReason'
		when l.daysPastDue < 30 then '<30 days past due'
		when c1.campaignDate >= @endReportDate then 'activeCampaign'
		when c2.campaignDate >= @endReportDate then 'activeCampaign'
		when c3.campaignDate >= @endReportDate then 'activeCampaign'
		when c4.campaignDate >= @endReportDate then 'activeCampaign'
		when c5.campaignDate >= @endReportDate then 'activeCampaign'
		else 'N/A' end as exclusionReason
,case 
		when c1.campaignDate >= @endReportDate then '3Tier'
		when c2.campaignDate >= @endReportDate then 'DoorKnock'
		when c3.campaignDate >= @endReportDate then 'Merchandise'
		when c4.campaignDate >= @endReportDate then 'Streamline'
		when c5.campaignDate >= @endReportDate then 'HAFA'
		else 'N/A'
		end as activeCampaign
,case   
		when c1.campaignDate >= @endReportDate then c1.campaignDate
		when c2.campaignDate >= @endReportDate then c2.campaignDate
		when c3.campaignDate >= @endReportDate then c3.campaignDate
		when c4.campaignDate >= @endReportDate then c4.campaignDate
		when c5.campaignDate >= @endReportDate then c5.campaignDate
		else NULL
		end as activeCampaignEndDate
,case 
		when c1.campaignDate < @endReportDate then '3Tier'
		when c2.campaignDate < @endReportDate then 'DoorKnock'
		when c3.campaignDate < @endReportDate then 'Merchandise'
		when c4.campaignDate < @endReportDate then 'Streamline'
		when c5.campaignDate < @endReportDate then 'HAFA'
		else 'N/A'
		end as previousCampaign
,case 
		when c1.campaignDate < @endReportDate then c1.campaignDate
		when c2.campaignDate < @endReportDate then c2.campaignDate
		when c3.campaignDate < @endReportDate then c3.campaignDate
		when c4.campaignDate < @endReportDate then c4.campaignDate
		when c5.campaignDate < @endReportDate then c5.campaignDate
		else NULL
		end as previousCampaignDate
,case   
		when c1.campaignDate < @endReportDate then c1.campaignDate
		else NULL
		end as last3TierCampaign
,case   
		when c2.campaignDate < @endReportDate then c2.campaignDate
		else NULL
		end as lastDoorKnockCampaign
,case   
		when c3.campaignDate < @endReportDate then c3.campaignDate
		else NULL
		end as lastMerchandiseCampaign
,case   
		when c4.campaignDate < @endReportDate then c4.campaignDate
		else NULL
		end as lastStreamlineCampaign
,case   
		when c5.campaignDate < @endReportDate then c5.campaignDate
		else NULL
		end as lastHAFACampaign
,case
		when fb.acctNumber is not null then 'Y'
		else 'N'
		end as forbearanceCandidate
into #main
from #loanlist l
left join #fclSales f on f.[acct number] = l.[acct number]
left join #lossMit lm on lm.accountNumber = l.[acct number]
left join #callData cd on cd.accountNumber = l.[acct number]
left join #plan p on p.accountNumber = l.[acct number]
left join #uncontrollables u on u.acctNumber = l.[acct number]
left join #forbear fb on fb.acctNumber = l.[acct number]
left join (select accountNumber, MAX(c.[3_Tier_Date]) as campaignDate
			from #campaignHistory c 
			where c.[3Tier] = 'Y'
			group by accountNumber) c1 on c1.accountNumber = l.[acct number]
left join (select accountNumber, MAX(c.Door_Knock_Date) as campaignDate
			from #campaignHistory c 
			where c.Door_Knock = 'Y'
			group by accountNumber) c2 on c2.accountNumber = l.[acct number]
left join (select accountNumber, MAX(c.Merchandise_Date) as campaignDate
			from #campaignHistory c 
			where c.Merchandise = 'Y'
			group by accountNumber) c3 on c3.accountNumber = l.[acct number]
left join (select accountNumber, MAX(c.Streamline_Date) as campaignDate
			from #campaignHistory c 
			where c.Streamline = 'Y'
			group by accountNumber) c4 on c4.accountNumber = l.[acct number]
left join (select accountNumber, MAX(c.HAFA_Date) as campaignDate
			from #campaignHistory c 
			where c.HAFA = 'Y'
			group by accountNumber) c5 on c5.accountNumber = l.[acct number]



select
m.[acct number]
,m.runDate
,m.[Investor Number]
,m.[Deal Name]
,m.[overall OTS]
,m.[prin bal]
,m.[lien position]
,m.[prop state]
,m.[prop county]
,m.[prop zip code]
,m.nextDueDate
,m.daysPastDue
,m.[pi constant]
,m.[note rate]
,m.lastRPCDate
,DATEDIFF(D,m.lastRPCDate,@endReportDate) as daysSinceLastRPC
,m.excluded
,m.exclusionReason
,case when m.excluded = 'Y' then 'No Campaign'  
		when m.forbearanceCandidate = 'Y' and m.excluded = 'N' then 'Forbearance'
		when m.previousCampaign = '3Tier' then 'Merchandise Campaign with 3 tier gift card offer'
		when m.previousCampaign = 'Merchandise' then 'Door Knock Campaign'
		when m.previousCampaign = 'DoorKnock' then 'Liquidation Campaign'
		when m.excluded = 'N' then 'GLM Campaign'
		else 'No Campaign'
		end as newCampaignRecommendation
,m.uncontrollableReason
,m.activeCampaign
,m.activeCampaignEndDate
,m.previousCampaign
,m.previousCampaignDate
,m.foreclosureSaleScheduled
from #main m



		
	