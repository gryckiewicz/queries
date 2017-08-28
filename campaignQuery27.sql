set nocount on

declare @endReportDate date

set @endReportDate = Investor_Reporting.dbo.fGetPriorBusinessDate(getdate())


--/**** Start of Forbearance Query Received from Reif(BI) *****/
/*
SET NOCOUNT ON

DECLARE @startdate date SET @startdate = (SELECT DATEADD(dd,-7,DATEADD(mm,-2,FirstDate)) FROM dbo.f_GetFirstAndLastDayOfPriorMonth(GETDATE()))
DECLARE @enddate date SET @enddate = (SELECT LastDate FROM dbo.f_GetFirstAndLastDayOfPriorMonth(GETDATE()))

--SELECT @startdate, @enddate

SELECT
INSTITUTION_CODE
,INVESTOR_CODE
,INVESTOR_ENTITY_ID
,INVESTOR_CODE_NAME
,INVESTOR_ENTITY_NAME
INTO #cteinvestor
FROM
V_Rpt_Investor WITH(NOLOCK)
WHERE
INVESTOR_ENTITY_ID = 19
AND INVESTOR_CODE IN
(129
,156,157
,184,185
,217
,218
,219,220
,315
,316,317
,224,225,326,327,328,329,330,331
,332
,419
)

----Payment Dates

SELECT
vrl.INSTITUTION_CODE
,vrl.ACCOUNT_NUMBER
,pay.BEGIN_EFFECTIVE_DATE as PaymentDate
,pay.END_EFFECTIVE_DATE
,CAST(DATEADD(mm,DATEDIFF(mm,0,pay.BEGIN_EFFECTIVE_DATE),0) AS date) AS 'PaymentMonth'
,DATEADD(mm,DATEDIFF(mm,0,pay.BEGIN_EFFECTIVE_DATE)+1,0) AS 'PaymentMonthNext'
,DATENAME(mm,pay.BEGIN_EFFECTIVE_DATE) AS 'PaymentMonthName'
INTO #ctepayment
FROM
dbo.V_Rpt_Loan vrl WITH (NOLOCK)
INNER JOIN #cteinvestor ic ON vrl.INSTITUTION_CODE = ic.INSTITUTION_CODE
      AND vrl.INVESTOR_CODE = ic.INVESTOR_CODE
INNER JOIN dbo.T_Rpt_BI_Dim_Loan_Payment pay WITH (NOLOCK) ON vrl.INSTITUTION_CODE = pay.INSTITUTION_CODE
      AND vrl.ACCOUNT_NUMBER = pay.ACCOUNT_NUMBER
INNER JOIN dbo.T_Rpt_BI_Dim_Loan_Payment pay0 WITH (NOLOCK) ON pay.INSTITUTION_CODE = pay0.INSTITUTION_CODE
      AND pay.ACCOUNT_NUMBER = pay0.ACCOUNT_NUMBER
      AND pay.BEGIN_EFFECTIVE_DATE = pay0.END_EFFECTIVE_DATE
      AND pay.PAYMENT_DUE_DATE_NEXT <> pay0.PAYMENT_DUE_DATE_NEXT
WHERE
pay.BEGIN_EFFECTIVE_DATE BETWEEN @startdate AND @enddate
--AND pay.ACCOUNT_NUMBER IN (1000877001,1010672445)

--SELECT * FROM #ctepayment

----C and D Loans to be excluded

;WITH CeaseDesist AS
(
SELECT CIT.[ACCOUNT_NUMBER]
     ,MAX([TASK_DATE_COMPLETE]) MaxTASK_DATE_COMPLETE
      ,MAX([TASK_DATE_CREATED])MaxTASK_DATE_CREATED
      ,[TASK_DESCRIPTION]
      ,[TASK_NUMBER]
  FROM [dbo].[V_Rpt_Loan_CIT] CIT WITH(NOLOCK)
  WHERE TASK_NUMBER = 623
  GROUP BY CIT.[ACCOUNT_NUMBER]
      ,[TASK_DESCRIPTION]
    ,[TASK_NUMBER]
)

----Payments with adjusted dates

,cteadjpayments1 AS

(

SELECT
cp.INSTITUTION_CODE
,cp.ACCOUNT_NUMBER
,cp.PaymentDate
,cp.PaymentMonth
,cp.PaymentMonthNext
,CASE WHEN DATEDIFF(dd,cp.PaymentDate,cp.PaymentMonthNext) <= 7 AND cpp.PaymentDate IS NOT NULL THEN DATEADD(mm,1,cp.PaymentMonth)
      ELSE cp.PaymentMonth END AS 'PaymentMonthAdjusted'
,CASE WHEN DATEDIFF(dd,cp.PaymentDate,cp.PaymentMonthNext) <= 7 AND cpp.PaymentDate IS NOT NULL THEN DATEDIFF(mm,DATEADD(mm,1,cp.PaymentMonth),GETDATE())
      ELSE DATEDIFF(mm,cp.PaymentMonth,GETDATE()) END AS 'PaymentNumber'


FROM #ctepayment cp
OUTER APPLY
      (SELECT MAX(PaymentDate) AS PaymentDate
            FROM #ctepayment cp2
            WHERE cp2.ACCOUNT_NUMBER = cp.ACCOUNT_NUMBER
            AND cp2.PaymentDate >= DATEADD(dd,-7,DATEADD(mm,DATEDIFF(mm,0,cp.PaymentDate),0))
            AND cp2.PaymentDate < cp.PaymentDate) cpp
WHERE cp.PaymentDate >= @startdate

)

----SELECT * FROM cteadjpayments1

----Payment Months

,RecentPayments AS

(

SELECT *
FROM (
            SELECT cap.INSTITUTION_CODE
                  ,cap.ACCOUNT_NUMBER
                  ,cap.PaymentMonthAdjusted
                  ,'Payment Month ' + CAST(cap.PaymentNumber AS varchar(1)) AS PaymentNumber
            FROM cteadjpayments1 cap
            ) S
PIVOT (MAX(PaymentMonthAdjusted)
            FOR PaymentNumber IN ([Payment Month 1],[Payment Month 2],[Payment Month 3])) PV

)

--SELECT * FROM RecentPayments

----Payment Made Dates

,RecentPaymentDate AS

(

SELECT *
FROM (
            SELECT cap.ACCOUNT_NUMBER
                  ,'Payment Date ' + CAST(cap.PaymentNumber AS varchar(1)) AS PaymentNumber
                  ,CAST (cap.PaymentDate AS date) AS PaymentDate
            FROM cteadjpayments1 cap
            ) S
PIVOT (MAX(PaymentDate)
            FOR PaymentNumber IN ([Payment Date 1],[Payment Date 2],[Payment Date 3])) PV

)
--SELECT * FROM RecentPaymentDate

SELECT 
      RL.ACCOUNT_NUMBER
      ,inv.INVESTOR_ENTITY_NAME
      ,RL.DELQ_DAYS_FROM_DUE
      ,RL.PAYMENT_DUE_DATE_NEXT
      ,RL.PAYMENT_PI_AMOUNT_CURRENT
      ,RL.PAYMENT_TI_AMOUNT_CURRENT
      ,ISNULL(RL.PAYMENT_PI_AMOUNT_CURRENT,0) + ISNULL(RL.PAYMENT_TI_AMOUNT_CURRENT,0) AS PAYMENT_PITI_AMOUNT
      ,RL.LOAN_CLOSE_CODE
      ,RL.LOAN_WARNING_CODE
      ,RL.LOAN_WARNING_CODE_DESC
      ,RL.SERVICE_TRANSFER_DATE
      ,BK.BK_LAST_RECORD_FLAG 
      ,BK.BK_ACTIVE_FLAG 
      ,FCL.FCL_ACTIVE_FLAG
      ,FCL.FCL_LAST_RECORD_FLAG
      ,RL.LITIGATION_TYPE_CODE
      ,RL.LITIGATION_TYPE_CODE_DESC
      ,RL.LITIGATION_START_DATE
      ,rp.[Payment Month 1] AS 'Payment 1 Month'
      ,rpd.[Payment Date 1]
      ,rp.[Payment Month 2] AS 'Payment 2 Month'
      ,rpd.[Payment Date 2]
      ,rp.[Payment Month 3] AS 'Payment 3 Month'
      ,rpd.[Payment Date 3]

FROM dbo.V_Rpt_Loan RL WITH(NOLOCK) 
      INNER JOIN #cteinvestor inv WITH(NOLOCK)
            ON inv.INVESTOR_CODE = RL.INVESTOR_CODE
      INNER JOIN RecentPayments RP
            ON RL.INSTITUTION_CODE = RP.INSTITUTION_CODE 
            AND RL.ACCOUNT_NUMBER = RP.ACCOUNT_NUMBER
      INNER JOIN RecentPaymentDate RPD
            ON RPD.ACCOUNT_NUMBER = RL.ACCOUNT_NUMBER
      INNER JOIN cteadjpayments1 cap WITH (NOLOCK) ON RL.INSTITUTION_CODE = cap.INSTITUTION_CODE
            AND RL.ACCOUNT_NUMBER = cap.ACCOUNT_NUMBER
            AND cap.PaymentDate = (SELECT MAX(PaymentDate) FROM cteadjpayments1 WITH (NOLOCK) WHERE INSTITUTION_CODE = RL.INSTITUTION_CODE AND ACCOUNT_NUMBER = RL.ACCOUNT_NUMBER)
      LEFT JOIN CeaseDesist CD
            ON CD.ACCOUNT_NUMBER = RL.ACCOUNT_NUMBER
      LEFT JOIN V_Rpt_Loan_Bankruptcy BK WITH(NOLOCK)
            ON BK.ACCOUNT_NUMBER = RL.ACCOUNT_NUMBER
            AND BK.BK_LAST_RECORD_FLAG = 'Y'
            AND BK.BK_ACTIVE_FLAG = 'Y'
      LEFT JOIN V_Rpt_Loan_Foreclosure FCL WITH(NOLOCK)
            ON FCL.ACCOUNT_NUMBER = RL.ACCOUNT_NUMBER
            AND FCL.FCL_LAST_RECORD_FLAG = 'Y'
            AND FCL.FCL_ACTIVE_FLAG = 'Y'
      LEFT JOIN V_Rpt_Loan_Escrow ESC WITH (NOLOCK) ON rl.INSTITUTION_CODE = ESC.INSTITUTION_CODE
            AND rl.ACCOUNT_NUMBER = ESC.ACCOUNT_NUMBER
            AND ESC.ESCROW_TYPE_CODE IN (40,50)
            AND ESC.ESCROW_PAYER_CODE = 5
      LEFT JOIN V_Rpt_Loan_Activity_Fee fee WITH (NOLOCK) ON RL.INSTITUTION_CODE = fee.INSTITUTION_CODE
            AND RL.ACCOUNT_NUMBER = fee.ACCOUNT_NUMBER
            AND fee.TRAN_DESC = 'NSF FEE'
            AND fee.TRAN_DATE >= cap.PaymentDate
WHERE
RL.LOAN_OTS_OVERALL_STATUS NOT IN ('Bankruptcy','Bankruptcy, FCL on Hold','Foreclosure','Paid in Full','REO','Service Release')
      AND RL.DELQ_DAYS_FROM_DUE BETWEEN 31 AND 119
      AND CD.ACCOUNT_NUMBER IS NULL 
      AND BK.ACCOUNT_NUMBER IS NULL
      AND FCL.ACCOUNT_NUMBER IS NULL
      AND RL.LITIGATION_TYPE_CODE = 0
      AND ESC.ACCOUNT_NUMBER IS NULL
      AND fee.ACCOUNT_NUMBER IS NULL      
      AND rp.[Payment Month 1] IS NOT NULL
      AND rp.[Payment Month 2] IS NOT NULL
      AND rp.[Payment Month 3] IS NOT NULL
      
DROP TABLE #cteinvestor
DROP TABLE #ctepayment
*/

--/**** End of Forbearance Query Received from Clay *****/


/**** Start of Loss Mit denial reason query from Kostya ****/


declare @rundate date
declare @priorbusdate date
set @rundate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(getdate())
set @priorbusdate = Investor_Reporting.dbo.fGetPriorBusinessDate(getdate())

---------------------------------------------------------------------------------
--Get All Active MABS Loans, and exclude REOs, Current, and BKs
---------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#initloanlist') IS NOT NULL DROP TABLE #initloanlist
select distinct
lla.[acct number]
,lla.[run date]
,lla.[eff inv cd]
,lla.[close code]
,lla.[overall OTS]
,lla.[prin bal]
,g.[prop state]
,g.[prop county]
,g.[prop zip code]
,lla.[lien position]
,lla.[next due]
,datediff(D,lla.[next due],@rundate) as 'Days Past Due'
,lla.[pi constant]
,lla.[stop code1]
,lla.[warn code]
,lla.[serv begin date]
,lla.[note rate]
into #initloanlist
from Loanlevel_Database.dbo.Loanlevel_Archive lla with(nolock)
left join Loanlevel_Database.dbo.GeneralTable g on lla.[acct number] = g.[acct number]
where lla.[eff inv cd] in (129,130,156,157,184,185,217,218,220,315,316,317,224,225,326,327,328,329,330,331,332,419)
and lla.[close code] in (1,6)
and lla.[run date] = @rundate

--Denied for Loss Mit
IF OBJECT_ID('tempdb..#lossmitdenial') IS NOT NULL DROP TABLE #lossmitdenial
select distinct
      i.[acct number]
      ,mapp.[Most Recent Loss Mit App]
      ,max(dpp.DECISION_PACKAGE_PROCESS_STATUS_DATE) as DECISION_PACKAGE_PROCESS_STATUS_DATE
      ,max(dp.DEAL_ID) as DealID
into #lossmitdenial
from #initloanlist i
inner join (select
                  map.ACCOUNT_NUMBER
                  ,max(map.LOSS_MIT_APPLICATION_ID) as 'Most Recent Loss Mit App'
                  from MortgageServ_Reports.dbo.T_Rpt_Milestone_Application_Process map with(nolock)
                  where map.APPLICATION_ACTIVATION_DATE <= @rundate
                  group by map.ACCOUNT_NUMBER) mapp on i.[acct number] = mapp.ACCOUNT_NUMBER
left join MortgageServ_Reports.dbo.T_Rpt_Milestone_Decision_Package_Process dpp on mapp.[Most Recent Loss Mit App] = dpp.LOSS_MIT_APPLICATION_ID
left join MortgageServ_Reports.dbo.T_Rpt_Milestone_Decision_Process dp on mapp.[Most Recent Loss Mit App] = dp.LOSS_MIT_APPLICATION_ID
where dpp.DECISION_PACKAGE_STATUS_DESC = 'Sent'
and dpp.DECISION_PACKAGE_FINAL_RESULT = 'Denied'
group by i.[acct number]
,mapp.[Most Recent Loss Mit App]

 

--Denial Reason
IF OBJECT_ID('tempdb..#denialreason62') IS NOT NULL DROP TABLE #denialreason62
create table #denialreason62 (
      ACCOUNT_NUMBER bigint
      ,DEAL_ID int
      ,DENIAL_ID int
      ,DENIAL_REASON varchar (200)
);
create nonclustered index ixAcc on #denialreason62 (DEAL_ID);

insert into #denialreason62
select
*
from openquery (sqlprd62, 'select d.ACCOUNT_NUMBER 
                                    ,d.DEAL_ID
                              ,d.DENIAL_ID
                              ,d.DENIAL_REASON from datamartanalytics.dbo.V_Rpt_CRW_Denial d
                              inner join datamartanalytics.dbo.V_Rpt_Loan L on L.ACCOUNT_NUMBER=d.ACCOUNT_NUMBER
                              where L.INVESTOR_CODE  in (129,130,156,157,184,185,217,218,220,315,316,317,224,225,326,327,328,329,330,331,332,419)') 

IF OBJECT_ID('tempdb..#denialreason') IS NOT NULL DROP TABLE #denialreason
select
d.[acct number]
,d.[Most Recent Loss Mit App]
,d.DealID
,crdd.denialID    
,isnull(dr.DENIAL_REASON,'Unknown') as 'DENIAL REASON'
,dp.DECISION_DEAL_NAME
,d.DECISION_PACKAGE_PROCESS_STATUS_DATE as 'DENIAL DATE'
into #denialreason
from #lossmitdenial d
left join (select
                  crd.DEAL_ID
                  ,max(crd.DENIAL_ID) as denialID
                  from #denialreason62 crd 
                  group by crd.DEAL_ID) crdd on d.DealID = crdd.DEAL_ID
left join #denialreason62 dr on crdd.denialID = dr.DENIAL_ID
left join MortgageServ_Reports.dbo.T_Rpt_Milestone_Decision_Process dp on d.DealID = dp.deal_id


/*** End of Loss Mit denial reason query from Kostya ***/

IF OBJECT_ID('tempdb..#forbear') IS NOT NULL DROP TABLE #forbear
select 
c.[acct number] as acctNumber
into #forbear
from Loanlevel_Database.dbo.Loanlevel_Current c with(nolock)
where c.[acct number] in
(1000804618,
1000838998,
1000864098,
1000865385,
1000877001,
1000882601,
1001983499,
1004992830,
1004997628,
1004997644,
1005010847,
1005020688,
1005042080,
1005158987,
1005254263,
1005273215,
1006879935,
1006933130,
1006977183,
1006995754,
1007000965,
1007011077,
1007013868,
1007029661,
1007037433,
1007116231,
1007120560,
1007134064,
1000875155,
1002036552,
1002082629,
1005016919,
1005045032,
1006882919,
1006918113,
1006943434,
1006988457,
1007009380,
1007016001,
1007030320,
1007158422,
1007160177,
1007170154,
1007181635,
1007188188,
1007227829,
1007274610,
1007277316,
1007277581,
1007538165,
1010668394,
1010673321,
1010677000,
1010677835,
1010677903,
1010679121,
1000943294,
1002222609,
1002732982,
1002754258,
1005001241,
1005013116,
1005015295,
1005016113,
1005044059,
1005114992,
1005132042,
1005252168,
1005257736,
1006884742,
1006906620,
1006973336,
1006987092,
1007003836,
1007047397,
1007047656,
1007058713,
1007066501,
1007227557,
1010670175,
1010674087,
1010679260,
1010680916,
1010683120,
1000873814,
1002159604,
1002271401,
1004992607,
1005073363,
1005121736,
1006936276,
1006940631,
1006978292,
1006988279,
1007015837,
1007043838,
1007086840,
1007180380,
1007196633,
1007199973,
1007205498,
1007219277,
1007231802,
1007276524,
1010668679,
1010670133,
1010671064,
1010672241,
1010672623,
1010673350,
1010673525,
1010674197,
1010687171,
1010675374,
1010682244,
1010683405,
1010683421,
1010685018,
1010686347,
1010687935,
1010689137,
1010692470,
1007278810,
1010668666,
1010672445,
1010674016,
1010674317,
1010676454,
1010680835,
1010683926,
1010685982,
1010687401,
1010689658,
1010691549,
1010691950,
1010692250,
1010679273,
1010680709,
1010681562,
1010682697,
1010682749,
1010687362,
1010688044,
1010688264,
1010692357,
1010692726)

----Forbearance Loans
--IF OBJECT_ID('tempdb..#forbear') IS NOT NULL DROP TABLE #forbear
--select distinct
--ACCOUNT_NUMBER as acctNumber
--into #forbear
--from #forbearOG

--PAMODs (to be excluded)
IF OBJECT_ID('tempdb..#PAMODCES') IS NOT NULL DROP TABLE #PAMODCES
select
a.ACCOUNT_NUMBER as accountNumber
into #PAMODCES
from SQLPRD62.DatamartAnalytics.[dbo].[V_Rpt_Borrower_Correspondence] a with(nolock)
where a.GV_DOCUMENT_DESCRIPTION = 'Assured_PreApproved_CES_Modification'




-- main loan list (which loans are NOT pre-evaluated for a PAMOD)

IF OBJECT_ID('tempdb..#loanlist') IS NOT NULL DROP TABLE #loanlist
select
c.[acct number]
,c.[run date]
,dn.[Investor Number]
,dn.[Deal Name]
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
left join Loanlevel_Database.dbo.[Deal Names] dn with(nolock) on dn.[Investor Number] = c.[eff inv cd]            
left join #PAMODCES p on p.accountNumber = c.[acct number]            
left join Loanlevel_Database.dbo.GeneralTable g with(nolock) on g.[acct number] = c.[acct number]
where 
p.accountNumber is null
and c.[eff inv cd] in (129,130,156,157,184,185,217,218,220,224,225,315,316,317,326,327,328,329,330,331,332,419)
and [overall OTS] != 'ZERO BAL'
and c.[close code] in (1,6)
and c.[lien position] = 1


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
ce.accountNumber
into #lossMit
from Loanlevel_Database.dbo.T_CallCenterExceptions ce with(nolock)
inner join #loanlist l on l.[acct number] = ce.accountNumber
where ce.runDate = @endReportDate
and ce.lossMitFlag_CRW = 'Y'


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
                  when c.loan_stop_code_1 in (2,3,4,6,8,9) then 'Stop Code 1 = ' + CONVERT(varchar,c.loan_stop_code_1)
                  when c.SPECIAL_HANDLING_CODE between 1 and 99 or c.SPECIAL_HANDLING_CODE between 104 and 200 or c.SPECIAL_HANDLING_CODE in (202,203,205) then 'Special Handling Code = ' + CONVERT(varchar,c.SPECIAL_HANDLING_CODE)
                  when c.LOAN_LOCKOUT_CODE between 1 and 8 then 'Lockout Code = ' + CONVERT(varchar,c.LOAN_LOCKOUT_CODE)
                  when C.LOAN_WARNING_CODE in (2,3,4,7,9) then 'Warning Code = ' + CONVERT(varchar,c.LOAN_WARNING_CODE)
                  when uf.UF040_BK_CHAPTER7_DISCHARGE in ('MR','D7') then 'Userfield 40 - ' + CONVERT(varchar,UF.UF040_BK_CHAPTER7_DISCHARGE)
                  when c.LOAN_STOP_CODE_3 = 8 then 'Stop Code 3 = 8'
                  when uf.UF044_ATTNY_REP_AND_CD_CODE not in ('PN','') then 'Userfield 44 - Attorney - ' + CONVERT(varchar,uf.UF044_ATTNY_REP_AND_CD_CODE)
                  when l.[overall OTS] = 'BANKRUPTCY' then 'Bankruptcy'
            end
into #uncontrollables
from [sqlprd62].DatamartAnalytics.dbo.V_RPT_LOAN c with(nolock)
left join [sqlprd62].DatamartAnalytics.dbo.v_rpt_loan_user_field uf with(nolock) on c.ACCOUNT_NUMBER = uf.ACCOUNT_NUMBER
inner join #loanlist l on l.[acct number] = c.ACCOUNT_NUMBER
AND C.loan_close_code IN (1,6)

--identify high risk
IF OBJECT_ID('tempdb..#highRisk') IS NOT NULL DROP TABLE #highRisk
select
u.ACCOUNT_NUMBER
,u.UF005_HIGH_RISK
into #highRisk
from sqlprd62.DatamartAnalytics.DBO.V_RPT_LOAN_USER_FIELD u with(nolock)
where u.UF005_HIGH_RISK in ('H','R','Z')


--prior campaigns raw(except for HAFA, since they sometimes are simultaneous and it messes stuff up)
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
and UF051_CAMPAIGN_LETTER_CODE not like '%HAFA%'
and UF051_CAMPAIGN_LETTER_CODE not like '%HAMP%'
and UF051_CAMPAIGN_LETTER_CODE not like '%PAMOD%'
and UF051_CAMPAIGN_LETTER_CODE not like '%PAIO%'
and UF051_CAMPAIGN_LETTER_CODE not like '%PENDING%' -- test to ensure anything in PAMOD program is not included
and isnull(UF181_CALL_CAMPAIGN_EXPIRATION_DATE,'')<>''
and isnull(UF181_CALL_CAMPAIGN_EXPIRATION_DATE,'')<>'00/00/00'


--prior campaigns raw(for HAFA only)
IF OBJECT_ID('tempdb..#campHAFA') IS NOT NULL DROP TABLE #campHAFA
select distinct 
ACCOUNT_NUMBER as accountNumber
,SUBSTRING(UF051_CAMPAIGN_LETTER_CODE,5,LEN(UF051_CAMPAIGN_LETTER_CODE)) as campaignCode
,max(convert(date,UF181_CALL_CAMPAIGN_EXPIRATION_DATE)) as expirationDate
--,UF051_CAMPAIGN_LETTER_CODE as campaignCode2
--,UF181_CALL_CAMPAIGN_EXPIRATION_DATE as expirationDate2
into #campHAFA
from sqlprd62.DatamartAnalytics.DBO.V_RPT_LOAN_USER_FIELD_HISTORY with(nolock)
inner join #loanlist l on l.[acct number] = ACCOUNT_NUMBER
where UF051_CAMPAIGN_LETTER_CODE like '%HAFA%'
and isnull(UF181_CALL_CAMPAIGN_EXPIRATION_DATE,'')<>''
and isnull(UF181_CALL_CAMPAIGN_EXPIRATION_DATE,'')<>'00/00/00'
group by
ACCOUNT_NUMBER
,SUBSTRING(UF051_CAMPAIGN_LETTER_CODE,5,LEN(UF051_CAMPAIGN_LETTER_CODE))


--campaign aggregation(except for HAFA) - this is so we can join the history only once below
IF OBJECT_ID('tempdb..#campaignHistory') IS NOT NULL DROP TABLE #campaignHistory
select 
c.accountNumber
,max(case when (c.campaignCode like '%3TIER%' and c.campaignCode like '%MERCH%') or c.campaignCode like '%MERCH%' then isnull(c.expirationDate,'1/1/1901') else '1/1/1901' end) as 'Merch_Date'
,max(case when c.campaignCode like '%3TIER%' and c.campaignCode not like '%MERCH%' then isnull(c.expirationDate,'1/1/1901') else '1/1/1901' end) as 'Tier_Date'
,max(case when c.campaignCode like '%DK%' then isnull(c.expirationDate,'1/1/1901') else '1/1/1901' end) as 'Door_Knock_Date'
,max(case when c.campaignCode like '%FORB%' or c.campaignCode like '%EXT%' then isnull(c.expirationDate,'1/1/1901') else '1/1/1901' end) as 'Forbearance_Date'
,max(case when c.campaignCode like '%STREAMLINE%' then isnull(c.expirationDate,'1/1/1901') 
		when c.campaignCode like '%STL%' then isnull(c.expirationDate,'1/1/1901')
		when c.campaignCode like '%STLINE%' then isnull(c.expirationDate,'1/1/1901')
		else '1/1/1901' end) as 'Streamline_Date'
,max(case when c.campaignCode like '%SETT%' or c.campaignCode like '%NCP%' then isnull(c.expirationDate,'1/1/1901') else '1/1/1901' end) as 'Settlement_Date'
,max(case when c.campaignCode like '%GLM%' and c.campaignCode not like '%GLM_DK%' then isnull(c.expirationDate,'1/1/1901') else '1/1/1901' end) as 'GLM_Date'
into #campaignHistory
from #camp as c
group by c.accountNumber


--unpivot the campaign history to get a list of the last campaigns of each type for each loan
IF OBJECT_ID('tempdb..#pivot') IS NOT NULL DROP TABLE #pivot
select accountNumber, CampaignName, CampaignDate
into #pivot
from
	(select c.accountNumber, c.Tier_Date, c.Merch_Date,c.Door_Knock_Date,c.Forbearance_Date,c.GLM_Date,c.Settlement_Date,c.Streamline_Date
	from #campaignHistory c) c
UNPIVOT
	(CampaignDate for CampaignName IN
		(Tier_Date,Merch_Date,Door_Knock_Date,Forbearance_Date,GLM_Date,Settlement_Date,Streamline_Date)
) as unpvt;



--a list of the last campaign for each account number
IF OBJECT_ID('tempdb..#campLast') IS NOT NULL DROP TABLE #campLast
select
p.accountNumber
,p.CampaignName
,p.CampaignDate as LastCampaignDate
into #campLast
from #pivot p
inner join (select p.accountNumber, MAX(p.CampaignDate) as lastCampaignDate
			from #pivot p
			group by p.accountNumber) p2 on p2.accountNumber = p.accountNumber and p2.lastCampaignDate = p.CampaignDate
where lastCampaignDate <> '1901-01-01'

	


--a look back to find the number of consecutive payments made
IF OBJECT_ID('tempdb..#PaymentString') IS NOT NULL DROP TABLE #PaymentString
CREATE TABLE #PaymentString 
(           accountNumber int,
	        consecutiveCurrentCount int,
	        otsPaymentsDue int,
	        runDate date)

declare @reportDate date
set @reportDate = Investor_Reporting.dbo.fGetLastDateForPriorMonth(Getdate())

--start report date loop

Insert into #PaymentString (accountNumber,consecutiveCurrentCount,otsPaymentsDue,runDate)
	select a.[acct number]
	,case when a2.[ots payments due] >= a.[ots payments due] then 1 else 0 end 
	,a2.[ots payments due]
	,a.[run date]
	from Loanlevel_Database.dbo.Loanlevel_EOM_13Months a
	left join Loanlevel_Database.dbo.Loanlevel_EOM_13Months a2 on a2.[acct number] = a.[acct number]
		and DATEDIFF(m,a2.[run date],a.[run date]) = 1
	inner join #loanlist l on l.[acct number] = a.[acct number]
	where a.[close code] in (1,6)
	and a.[run date]=@reportDate

		--start 12 month payment string loop
		declare @monthLookback int = 12 
		declare @dateLoop datetime
		declare @loopCount int

		set @dateLoop = Investor_Reporting.dbo.fGetLastDateForPriorMonth(dateadd(m,-1,@reportDate))
		set @loopCount = 1

		while @dateLoop >= Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-@monthLookback,@reportDate))
		begin
			
			update #PaymentString 
					set consecutiveCurrentCount = case when @loopCount <= consecutiveCurrentCount  then consecutiveCurrentCount + l.previousCurrent 
														else consecutiveCurrentCount end 
						,otsPaymentsDue = l.otsPaymentsDue
					from (
						  select
						  l.[acct number]
						  ,case when l.[ots payments due] >= p.otsPaymentsDue then 1 else 0 end as previousCurrent
						  ,l.[ots payments due] as otsPaymentsDue
						  from Loanlevel_Database.dbo.Loanlevel_EOM_13Months l with(nolock)
						  left join #PaymentString p on p.accountNumber = l.[acct number] 
						  where l.[run date] = @dateLoop
						  and l.[close code] in (1,6)
						) l
					where #PaymentString.accountNumber = l.[acct number] and #PaymentString.runDate = @reportDate

			set @dateLoop = Investor_Reporting.dbo.fGetLastDateForCurrentMonth(dateadd(m,-1,@dateLoop))	
			set @loopCount = @loopCount + 1
		end
		
		

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
,case when f.[acct number] is not null then 'Y'
		when p.accountNumber is not null then 'Y'
		when lm.accountNumber is not null then 'Y'
		when u.uncontrollableReason is not null then 'Y'
		when DATEDIFF(D,cd.lastRPCDate,@endReportDate) <= 30 and fb.acctNumber is null then 'Y'
		when l.[overall OTS] = 'BANKRUPTCY' then 'Y'
		when l.[overall OTS] = 'REO' then 'Y'
		when l.daysPastDue < 30 then 'Y'
		when c.Tier_Date >= @endReportDate then 'Y'
		when c.Merch_Date >= @endReportDate then 'Y'
		when c.Door_Knock_Date >= @endReportDate then 'Y'
		when c.Forbearance_Date >= @endReportDate then 'Y'
		when c.GLM_Date >= @endReportDate then 'Y'
		when ch.expirationDate >= @endReportDate then 'Y'
		when c.Settlement_Date >= @endReportDate then 'Y'
		when c.Streamline_Date >= @endReportDate then 'Y'
		when h.ACCOUNT_NUMBER IS NOT NULL then 'Y'
		else 'N' end as excluded
,case when f.[acct number] is not null then 'Foreclosure Sale Date'
		when p.accountNumber is not null then 'Active Payment Plan'
		when lm.accountNumber is not null then 'Active Loss Mitigation Application'
		when u.uncontrollableReason is not null then u.uncontrollableReason
		when DATEDIFF(D,cd.lastRPCDate,@endReportDate) <= 30 and fb.acctNumber is null then 'RPC within the last 30 Days'
		when l.[overall OTS] = 'BANKRUPTCY' then 'Warning Code = 4'
		when l.[overall OTS] = 'REO' then 'REO'
		when l.daysPastDue < 30 then 'OTS <30 Days'
		when c.Tier_Date >= @endReportDate then 'Currently in Active Campaign'
		when c.Merch_Date >= @endReportDate then 'Currently in Active Campaign'
		when c.Door_Knock_Date >= @endReportDate then 'Currently in Active Campaign'
		when c.Forbearance_Date >= @endReportDate then 'Currently in Active Campaign'
		when c.GLM_Date >= @endReportDate then 'Currently in Active Campaign'
		when ch.expirationDate >= @endReportDate then 'Currently in Active Campaign'
		when c.Settlement_Date >= @endReportDate then 'Currently in Active Campaign'
		when c.Streamline_Date >= @endReportDate then 'Currently in Active Campaign'
		when h.ACCOUNT_NUMBER IS NOT NULL then 'High Risk'
		else 'Not Excluded' end as exclusionReason
,case 
		when c.Tier_Date >= @endReportDate then '3 Tier'
		when c.Merch_Date >= @endReportDate then '3 Tier with Merchandise'
		when c.Door_Knock_Date >= @endReportDate then 'Door Knock'
		when c.Forbearance_Date >= @endReportDate then 'Forbearance'
		when c.GLM_Date >= @endReportDate then 'GLM'
		when ch.expirationDate >= @endReportDate then 'HAFA'
		when c.Settlement_Date >= @endReportDate then 'Settlement'
		when c.Streamline_Date >= @endReportDate then 'Streamline'
		else 'N/A'
		end as activeCampaign
,case  
		when c.Tier_Date >= @endReportDate then c.Tier_Date
		when c.Merch_Date >= @endReportDate then c.Merch_Date
		when c.Door_Knock_Date >= @endReportDate then c.Door_Knock_Date
		when c.Forbearance_Date >= @endReportDate then c.Forbearance_Date
		when c.GLM_Date >= @endReportDate then c.GLM_Date
		when ch.expirationDate >= @endReportDate then ch.expirationDate
		when c.Settlement_Date >= @endReportDate then c.Settlement_Date
		when c.Streamline_Date >= @endReportDate then c.Streamline_Date
		else NULL
		end as activeCampaignEndDate
,case 
		when cl.CampaignName = 'Tier_Date' then '3 Tier'
		when cl.CampaignName = 'Merch_Date' then '3 Tier with Merchandise'
		when cl.CampaignName = 'Door_Knock_Date' then 'Door Knock'
		when cl.CampaignName = 'Forbearance_Date' then 'Forbearance'
		when cl.CampaignName = 'GLM_Date' then 'GLM'
		when cl.CampaignName = 'Settlement_Date' then 'Settlement'
		when cl.CampaignName = 'Streamline_Date' then 'Streamline'
		when ch.accountNumber is not null then 'HAFA'
		else 'N/A'
		end as lastCampaign
,case when cl.LastCampaignDate = '1/1/1901' then null 
	when cl.LastCampaignDate <> '1/1/1901' then cl.LastCampaignDate 
	when ch.expirationDate <> '1/1/1901' then ch.expirationDate
	else NULL end as lastCampaignEndDate
,case when c.Tier_Date = '1/1/1901' then null else c.Tier_Date end as last3TierCampaign
,case when c.Merch_Date = '1/1/1901' then null else c.Merch_Date end as last3TierMerchCampaign
,case when c.Door_Knock_Date = '1/1/1901' then null else c.Door_Knock_Date end as lastDoorKnock
,case when c.Forbearance_Date = '1/1/1901' then null else c.Forbearance_Date end as lastForbearance
,case when c.GLM_Date = '1/1/1901' then null else c.GLM_Date end as lastGLM
,case when ch.expirationDate = '1/1/1901' then null else ch.expirationDate end as lastHAFA
,case when c.Settlement_Date = '1/1/1901' then null else c.Settlement_Date end as lastSettlement
,case when c.Streamline_Date = '1/1/1901' then null else c.Streamline_Date end as lastStreamline
,case
		when fb.acctNumber is not null then 'Y'
		else 'N'
		end as forbearanceCandidate
,d.[DENIAL REASON]
,d.[DENIAL DATE]
,case when ps.consecutiveCurrentCount >= 12 then '12+'
		else convert(varchar(2),ps.consecutiveCurrentCount) 
		end as consecutivePayments
into #main
from #loanlist l
left join #fclSales f on f.[acct number] = l.[acct number]
left join #lossMit lm on lm.accountNumber = l.[acct number]
left join #callData cd on cd.accountNumber = l.[acct number]
left join #plan p on p.accountNumber = l.[acct number]
left join #uncontrollables u on u.acctNumber = l.[acct number]
left join #forbear fb on fb.acctNumber = l.[acct number]
left join #campaignHistory c on c.accountNumber = l.[acct number]
left join #campLast cl on cl.accountNumber = l.[acct number]
left join #campHAFA ch on ch.accountNumber = l.[acct number]
left join #denialreason d on d.[acct number] = l.[acct number]
left join #PaymentString ps on ps.accountNumber = l.[acct number]
left join #highRisk h on h.ACCOUNT_NUMBER = l.[acct number]



-- Do the loans qualify for the campaigns available?
IF OBJECT_ID('tempdb..#eligibility') IS NOT NULL DROP TABLE #eligibility
select
m.[acct number]
,case when (DATEDIFF(m,m.lastGLM,@endReportDate) > 3 or m.lastGLM is null) then 'Y' else 'N' end as 'GLM Eligible'
,case when DATEDIFF(m,m.lastGLM,@endReportDate) <= 3 then 'GLM campaign within the last three months' else NULL end as 'GLM Non-eligible Reason'
,case when (DATEDIFF(d,m.lastRPCDate,@endReportDate) > 60 or m.lastRPCDate is null)
			and (DATEDIFF(m,m.last3TierCampaign,@endReportDate) > 6 or m.last3TierCampaign is null) 
			and (d.[acct number] is null) then 'Y' else 'N' end as '3Tier Eligible'
,case when DATEDIFF(d,m.lastRPCDate,@endReportDate) <= 60 then 'RPC within the last 60 days'
		when DATEDIFF(m,m.last3TierCampaign,@endReportDate) <= 6 then '3 Tier campaign within the last six months'
		when d.[acct number] is not null then 'Loss mitigation previously denied'
		else NULL end as '3 Tier Non-eligible Reason'
,case when (DATEDIFF(m,m.last3TierMerchCampaign,@endReportDate) > 6 or m.last3TierMerchCampaign is null)
			and (DATEDIFF(d,m.lastRPCDate,@endReportDate) > 60 or m.lastRPCDate is null) then 'Y' else 'N' end as 'Merch_3Tier Eligible'
,case when DATEDIFF(m,m.last3TierMerchCampaign,@endReportDate) <= 6 then 'Merch 3 Tier campaign within the last six months'
		when DATEDIFF(d,m.lastRPCDate,@endReportDate) <= 60 then 'RPC within the last 60 days'
		else NULL end as 'Merch_3Tier Non-eligible Reason'
,case when (DATEDIFF(m,m.lastDoorKnock,@endReportDate) > 6 or m.lastDoorKnock is null) 
			and m.[prin bal] > 50000 
			and DATEDIFF(m,m.last3TierMerchCampaign,@endReportDate) <= 6
			then 'Y' else 'N' end as 'Door Knock Eligible'
,case when DATEDIFF(m,m.lastDoorKnock,@endReportDate) <= 6 then 'Door knock within the last six months'
		when m.[prin bal] <= 50000 then 'UPB is less than $50,000'
		when (DATEDIFF(m,m.last3TierMerchCampaign,@endReportDate) > 6 or m.last3TierMerchCampaign is null) then 'Merch campaign not within last six months'
		else NULL end as 'Door knock Non-eligible Reason'
,d.[DENIAL REASON]
into #eligibility
from #main m
left join #denialreason d on d.[acct number] = m.[acct number]
	and d.[DENIAL REASON] not in ('Documents not returned','Mod Docs Not Returned')
where m.excluded = 'N'



-- final result set
select
m.[acct number] as 'Loan Number'
,case when m.excluded = 'Y' then 'Y'
		when m.lastCampaign = '3 Tier with Merchandise' and e.[Door Knock Eligible] = 'N' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then 'Y'
		when m.lastCampaign = '3 Tier' and e.[Merch_3Tier Eligible] = 'N' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then 'Y'
		when m.lastCampaign = 'GLM'	and e.[3Tier Eligible] = 'N' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then 'Y'
		when (m.lastCampaign = NULL or m.lastCampaign = 'Door Knock') and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then 'Y'
		when m.lastCampaign = 'Streamline' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then 'Y'
		else m.excluded
		end as 'Excluded'
,case when m.exclusionReason != 'Not Excluded' then m.exclusionReason
		when m.lastCampaign = '3 Tier with Merchandise' and e.[Door Knock Eligible] = 'N' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then e.[Door knock Non-eligible Reason]
		when m.lastCampaign = '3 Tier' and e.[Merch_3Tier Eligible] = 'N' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then e.[Merch_3Tier Non-eligible Reason]
		when m.lastCampaign = 'GLM'	and e.[3Tier Eligible] = 'N' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then e.[3 Tier Non-eligible Reason]
		when (m.lastCampaign = NULL or m.lastCampaign = 'Door Knock') and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then e.[GLM Non-eligible Reason]
		when m.lastCampaign = 'Streamline' and e.[GLM Eligible] = 'N' and m.forbearanceCandidate = 'N' then e.[GLM Non-eligible Reason]
		else m.exclusionReason
		end as 'Exclusion Reason'
,m.[overall OTS] as 'Overall OTS'
,case when m.excluded = 'Y' then 'No Campaign'
		when m.forbearanceCandidate = 'Y' and m.excluded = 'N' 
			and (DATEDIFF(M,m.lastForbearance,@endReportDate) > 3 or m.lastForbearance is null) then 'Forbearance Campaign'
		when m.lastCampaign = '3 Tier with Merchandise' and e.[Door Knock Eligible] = 'N' and e.[GLM Eligible] = 'N' then 'No Campaign'
		when m.lastCampaign = '3 Tier' and e.[Merch_3Tier Eligible] = 'N' and e.[GLM Eligible] = 'N' then 'No Campaign'
		when m.lastCampaign = 'GLM'	and e.[3Tier Eligible] = 'N' and e.[GLM Eligible] = 'N' then 'No Campaign'
		when (m.lastCampaign = NULL or m.lastCampaign = 'Door Knock') and e.[GLM Eligible] = 'N' then 'No Campaign'
		when m.lastCampaign = '3 Tier with Merchandise'
			and e.[Door Knock Eligible] = 'Y' then 'DoorKnock Campaign'
		when m.lastCampaign = '3 Tier' 
			and e.[Merch_3Tier Eligible] = 'Y' then 'Merchandise Campaign with 3 Tier Gift Card Offer'
		when m.lastCampaign = 'GLM'
			and e.[3Tier Eligible] = 'Y'
			then '3 Tier Gift Card Offer'
		when m.excluded = 'N' 
			and e.[GLM Eligible] = 'Y' then 'GLM Campaign'
		else 'No Campaign' 
		end as 'New Campaign Recommendation'
,m.activeCampaign as 'Active Campaign'
,m.activeCampaignEndDate as 'Active Campaign End Date'		
,m.lastRPCDate as 'Last RPC Date'
,DATEDIFF(D,m.lastRPCDate,@endReportDate) as 'Days Since Last RPC'
,m.lastCampaign as 'Last Campaign'
,m.lastCampaignEndDate as 'Last Campaign End Date'
,m.last3TierCampaign as 'Last 3 Tier Campaign'
,m.last3TierMerchCampaign as 'Last 3 Tier Merch Campaign'
,m.lastDoorKnock as 'Last Door Knock'
,m.lastForbearance as 'Last Forbearance'
,m.lastGLM as 'Last GLM'
,m.lastHAFA as 'Last HAFA'
,m.lastStreamline as 'Last Streamline'
,m.lastSettlement as 'Last Settlement'
,m.foreclosureSaleScheduled as 'Foreclosure Sale Scheduled'
,m.[DENIAL DATE] as 'Loss Mit Denial Date'
,m.[DENIAL REASON] as 'Loss Mit Denial Reason'
,m.consecutivePayments as 'Months of Consecutive Payments'
,m.[Deal Name] as 'Deal Name'
,m.[Investor Number] as 'Investor Code'
,m.[lien position] as 'Lien Position'
,m.[prin bal] as 'UPB'
,m.nextDueDate as 'Next Due Date'
,m.daysPastDue as 'Days Past Due'
,m.[pi constant] as 'PI Constant'
,m.[note rate] as 'Interest Rate'
,m.[prop state] as 'Property State'
,m.[prop county] as 'Property County'
,m.[prop zip code] as 'Property Zip'
,m.runDate as 'File Run Date'
from #main m
left join #eligibility e on e.[acct number] = m.[acct number]	