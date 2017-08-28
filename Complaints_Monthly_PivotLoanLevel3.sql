set nocount on 


Declare @startDate date
Declare @endDate date

Set @endDate = Investor_Reporting.dbo.fGetLastBusinessDateForCurrentMonth(GETDATE())
Set @startDate = Investor_Reporting.dbo.fGetFirstDateForPriorMonth(dateadd(mm,-14,@endDate))


IF OBJECT_ID('tempdb..#complaintsRaw') IS NOT NULL DROP TABLE #complaintsRaw
SELECT
Investor_Reporting.dbo.fGetLastDateForCurrentMonth(t.DeptReceivedDate) as receivedMonth
,convert(smalldatetime,t.DeptReceivedDate) as DeptReceivedDate
,Investor_Reporting.dbo.fGetLastDateForCurrentMonth(t.ImportActualCompletionDate) as resolvedMonth
,convert(smalldatetime,t.ImportActualCompletionDate) as resolvedDate
,t.ACCOUNT_NUMBER
,t.IMPORT_FORM_ID
,case when t.PrimaryReason = 'Bankruptcy' then 'Bankruptcy' -- Bankruptcy
		when t.PrimaryReason = 'Credit' then 'Credit' -- Credit
		when t.PrimaryReason in ('Default/Loss Mitigation','CR - Liquidation') and t.SecondaryReason in ('Change in Circumstance Review',
																				'Deed in Lieu','Foreclosure Dispute','Short Sale Dispute') then 'Liquidation' -- Liquidation
		when t.PrimaryReason in ('In Flight Loss Mitigation','Loan Mod Issue','CR - Retention') then 'Retention' -- Retention
		when t.PrimaryReason in ('Escrow','Insurance') then 'Escrow' -- Escrow
		when t.PrimaryReason = 'Foreclosure' or
			(t.PrimaryReason = 'Default/Loss Mitigation' and t.SecondaryReason = 'Property Preservation') then 'Foreclosure' -- Foreclosure		
		when t.PrimaryReason in ('Debt Related','General Request','HELOC','Other') then 'Other' -- Other
		when t.PrimaryReason = 'Loan Terms' then 'Special Loans' -- Special Loans
		when t.PrimaryReason = 'Payment' then 'Cashiering' -- Cashiering
		when t.PrimaryReason = 'Payoff' and t.SecondaryReason in ('Lien Release Issue','Lien Release') then 'Lien Release' -- Lien Release		
		when t.PrimaryReason = 'Payoff' then 'Payoff' -- Payoff
		when (t.PrimaryReason = 'Default/Loss Mitigation' and t.SecondaryReason = 'Recovery Dispute')
			or t.PrimaryReason = 'Recovery' then 'Recovery' -- Recovery
		else 'Uncategorized'
		end as Department
,case when t.Complaint_Type = 'QWR' and t.PrimaryReason = 'Request for Info' then 'RFI'
	when t.Complaint_Type = 'QWR' and t.PrimaryReason = 'General Request' and t.SecondaryReason = 'Note Holder Info Request' then 'RFI'
	when t.Complaint_Type = 'QWR' and t.PrimaryReason = 'General Request' and t.SecondaryReason = 'Request for Info' then 'RFI'
	when t.Complaint_Type = 'QWR' and t.PrimaryReason = 'Debt Related' and t.SecondaryReason = 'Validation of Debt' then 'RFI'
	when t.Complaint_Type = 'QWR' then 'NOE'
	else t.Complaint_Type
	end as Complaint_Type
,t.PrimaryReason
,t.SecondaryReason
,case when t.SecondaryReason = 'CBR Form Ltr.' then 'Y' else 'N' end as CBRFormLtrFlag
,case 
	when t.ComplaintValid = 'Yes' then 'Servicer Error'
	when t.ComplaintValid = 'SLS Servicing Error' then 'Servicer Error'
	when t.ComplaintValid = 'No' then 'Customer Experience'
	when t.ComplaintValid = 'Customer Experience Opportunity' then 'Customer Experience'
	else 'Customer Experience'
	End as ComplaintValid
,Investor_Reporting.dbo.fGetLastDateForCurrentMonth(c.[serv begin date]) as boardingMonth
,case when datediff(d,c.[serv begin date],t.DeptReceivedDate) <= 60 then 'yes'
		else 'no'
		end as 'receivedIn60'
,c.[fldman cd] as fieldmanCode
,c.[eff inv cd] as investorCode
,investorName = Case
					when dn.[Investor Number] between 5000 and 5999 then 'BANA'
					when dn.[Investor Number] between 7000 and 7999 then 'Chase'
					when dn.[Investor Number] in (1450,1452) and c.[serv begin date] between '2/1/2015' and '3/31/2015' then 'Etrade PNC'
					when dn.[Investor Number] in (1450,1452) and c.[serv begin date] between '4/1/2015' and '4/30/2015' then 'Etrade Ocwen'
					when dn.[Investor Number] in (1450,1452) and c.[serv begin date] between '11/1/2015' and '11/30/2015' then 'Etrade Nationstar'
					when dn.[Investor Number] in (1450,1452) and c.[serv begin date] < '2/1/2015' then 'Etrade Legacy'
					when dn.[Investor Number] in (325,326,327,328,329,330,331,224,225) then 'Assured CWHEQ'
					when dn.[Investor Number] = 419 then 'Assured MABS'
					when dn.Deal_Group = 'FSA' then 'Assured Other'
					when dn.Deal_Group = 'AMBAC' then 'AMBAC'
					when dn.Deal_Level_Name in ('MS_S1','MS_Prime') then 'MS Whole Loan'
					when dn.Deal_Level_Name = 'MS_HELOC Non-Securitized' then 'MS HELOC Non-Securitized'
					when dn.Deal_Level_Name = 'MS_HELOC Securitized' then 'MS HELOC Securitized'
					when dn.Deal_Level_Name = 'MS_Non-HELOC Securitized' then 'MS Non-HELOC Securitized'
					when dn.[Investor Number] = 560 then 'Freddie Mac VPC'
					when dn.[Investor Number] = 520 then 'Freddie Mac PRP'
					when dn.[Investor Number] between 500 and 599 then 'Freddie Mac'
					when dn.[Investor Number] between 700 and 799 then 'Fannie Mae'
					when dn.[Group] = 'Black Diamond' then 'Black Diamond'
					when dn.[Group] = 'Black Diamond 2' then 'Black Diamond 2'
					when dn.[Group] = 'Black Diamond III' then 'Black Diamond 3'
					when (dn.[Investor Number] between 1875 and 1892) and dn.[Investor Number] != 1891 then 'Waterfall Legacy'
					when dn.[Investor Number] = 1891 then 'Waterfall MS 2Lien HELOC'
					when dn.[Investor Number] in (1894,1895) then 'Waterfall Citi'
					when dn.[Investor Number] = 1896 then 'Waterfall MS 1Lien HELOC'
					when dn.Deal_Level_Name = 'BOLT BlackRock' then 'BlackRock BOLT'
					when dn.Deal_Level_Name = 'Pearl' then 'BlackRock Pearl'
					else 'Other'
					End
into #complaintsRaw
from Analytical_Modeling.dbo.T_COMPLAINT_DETAIL t with(nolock)
left join Loanlevel_Database.dbo.Loanlevel_Current c with(nolock) on t.ACCOUNT_NUMBER = c.[acct number]
left join Loanlevel_Database.dbo.[Deal Names] dn with(nolock) on dn.[Investor Number] = c.[eff inv cd]
where (t.ImportActualCompletionDate between @startDate and @endDate
and t.IMPORT_FORM_NAME != 'Complaint: 2nd Ind Rev Appeal'
and t.Complaint_Type != 'Verbal Inquiry') or
(t.DeptReceivedDate between @startDate and @endDate
and t.IMPORT_FORM_NAME != 'Complaint: 2nd Ind Rev Appeal'
and t.Complaint_Type != 'Verbal Inquiry')

--and t.Resolved_Flag = 1



select
t.receivedMonth
,t.DeptReceivedDate
,t.resolvedMonth
,t.resolvedDate
,t.ACCOUNT_NUMBER
,t.IMPORT_FORM_ID
,t.fieldmanCode
,t.investorCode
,t.investorName
,t.Department
,t.Complaint_Type
,t.PrimaryReason
,t.SecondaryReason
,t.CBRFormLtrFlag
,t.ComplaintValid
,t.boardingMonth
,t.receivedIn60
,case when count(t2.IMPORT_FORM_ID) > 0 then 30
		when count(t3.IMPORT_FORM_ID) > 0 then 60
		when count(t4.IMPORT_FORM_ID) > 0 then 90
		when count(t5.IMPORT_FORM_ID) > 0 then 180
		else 0
		end as RepeatComplaints
from #complaintsRaw t
left join (select distinct t.ACCOUNT_NUMBER, t.PrimaryReason, t.DeptReceivedDate, t.IMPORT_FORM_ID
			from Analytical_Modeling.dbo.T_COMPLAINT_DETAIL t with(nolock)
			where t.ImportActualCompletionDate between @startDate and @endDate
			and t.Complaint_Type != 'Verbal Inquiry'
			and t.IMPORT_FORM_NAME != 'Complaint: 2nd Ind Rev Appeal'
			and t.Resolved_Flag = 1
			)t2 on t2.ACCOUNT_NUMBER = t.ACCOUNT_NUMBER 
					and t.PrimaryReason = t2.PrimaryReason 
					and DATEDIFF(d,t2.DeptReceivedDate,t.DeptReceivedDate) between 1 and 30
					and t2.IMPORT_FORM_ID != t.IMPORT_FORM_ID
left join (select distinct t.ACCOUNT_NUMBER, t.PrimaryReason, t.DeptReceivedDate, t.IMPORT_FORM_ID
			from Analytical_Modeling.dbo.T_COMPLAINT_DETAIL t with(nolock)
			where t.ImportActualCompletionDate between @startDate and @endDate
			and t.Complaint_Type != 'Verbal Inquiry'
			and t.IMPORT_FORM_NAME != 'Complaint: 2nd Ind Rev Appeal'
			and t.Resolved_Flag = 1
			)t3 on t3.ACCOUNT_NUMBER = t.ACCOUNT_NUMBER 
					and t.PrimaryReason = t3.PrimaryReason 
					and DATEDIFF(d,t3.DeptReceivedDate,t.DeptReceivedDate) between 31 and 60
					and t3.IMPORT_FORM_ID != t.IMPORT_FORM_ID
left join (select distinct t.ACCOUNT_NUMBER, t.PrimaryReason, t.DeptReceivedDate, t.IMPORT_FORM_ID
			from Analytical_Modeling.dbo.T_COMPLAINT_DETAIL t with(nolock)
			where t.ImportActualCompletionDate between @startDate and @endDate
			and t.Complaint_Type != 'Verbal Inquiry'
			and t.IMPORT_FORM_NAME != 'Complaint: 2nd Ind Rev Appeal'
			and t.Resolved_Flag = 1
			)t4 on t4.ACCOUNT_NUMBER = t.ACCOUNT_NUMBER 
					and t.PrimaryReason = t4.PrimaryReason 
					and DATEDIFF(d,t4.DeptReceivedDate,t.DeptReceivedDate) between 61 and 90
					and t4.IMPORT_FORM_ID != t.IMPORT_FORM_ID
left join (select distinct t.ACCOUNT_NUMBER, t.PrimaryReason, t.DeptReceivedDate, t.IMPORT_FORM_ID
			from Analytical_Modeling.dbo.T_COMPLAINT_DETAIL t with(nolock)
			where t.ImportActualCompletionDate between @startDate and @endDate
			and t.Complaint_Type != 'Verbal Inquiry'
			and t.IMPORT_FORM_NAME != 'Complaint: 2nd Ind Rev Appeal'
			and t.Resolved_Flag = 1
			)t5 on t5.ACCOUNT_NUMBER = t.ACCOUNT_NUMBER 
					and t.PrimaryReason = t5.PrimaryReason 
					and DATEDIFF(d,t5.DeptReceivedDate,t.DeptReceivedDate) between 91 and 180
					and t5.IMPORT_FORM_ID != t.IMPORT_FORM_ID
where t.PrimaryReason != 'BBB Rebuttal'
group by
t.receivedMonth
,t.DeptReceivedDate
,t.resolvedMonth
,t.resolvedDate
,t.ACCOUNT_NUMBER
,t.IMPORT_FORM_ID
,t.fieldmanCode
,t.investorCode
,t.investorName
,t.Department
,t.Complaint_Type
,t.PrimaryReason
,t.SecondaryReason
,t.CBRFormLtrFlag
,t.ComplaintValid
,t.boardingMonth
,t.receivedIn60


