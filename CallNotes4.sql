/************Query to get the list of loans needed for call messages**************/
;
Declare @ReportDate date, @Start date, @End date
Set @ReportDate='1/31/2016'
Set @Start='2/1/2016'
Set @End='2/29/2016'

If OBJECT_ID('tempdb..#accounts') IS NOT NULL
	DROP TABLE #accounts;
	
If OBJECT_ID('tempdb..#payments') IS NOT NULL
	DROP TABLE #payments;
	
If OBJECT_ID('tempdb..#calls') IS NOT NULL
	DROP TABLE #calls;
	
If OBJECT_ID('tempdb..#finallist') IS NOT NULL
	DROP TABLE #finallist;

If OBJECT_ID('tempdb..#acctsForProcess') IS NOT NULL
	DROP TABLE #acctsForProcess;

--calls--
select 
t.accountNumber
,call_bucket=case when sum(t.contact)=0 and Sum(t.attempt)>=1 then  'outbound dial_no contact'
      when sum(t.contact)>=1 and sum(t.attempt)>=1 and SUM(t.rightPartyContact)>=1 then 'outbound dial_contact_rpc'
      when sum(t.contact)>=1 and sum(t.attempt)>=1 and SUM(t.rightPartyContact)=0 then 'outbound dial_contact_norpc'
      when sum(t.offered)>=0 and Sum(t.attempt)=0 then  'made no outbound dial_recieved inbound'
      else 'None' end

into #calls

from [sqlprd13].Performance_Books.dbo.T_CALL_DATA t
where t.callStartDate between @Start and @End
and t.accountNumber<>0
group by t.accountNumber


--loans--

Select
a.[acct number]
,monthly_payment=round(a.[pi constant],2) 
into #accounts

from [sqlprd13].Loanlevel_Database.dbo.Loanlevel_Archive a with(nolock)
left join  sqlprd13.[Loanlevel_Database].[dbo].[Deal Names] d on a.[eff inv cd]=d.[Investor Number]
where a.[run date]=@ReportDate
and a.[close code] in (1,6,9)
and d.INVESTOR_CODE_CATEGORY not in ('CHARGE-OFF','DEFICIENCY')   
and a.[overall MBA]='30 - 59 DAYS'
and a.[lien position]=1



--payment--
select
c.[Loan Number]
,round(isnull(SUM(c.[Activity Total]),0),2) Total_Payment_Activity
into #payments

from sqlprd13.Analytic_Reporting_Database.dbo.[62-01_COMBINED] c with(nolock)
where c.[Report Date] between @Start and @End
and isnull(c.[Int Activity],0) > 0
group by c.[Loan Number]


select
a.[acct number]
,payment_bucket= case when round(p.Total_Payment_Activity,2)< round(a.monthly_payment,2)  then 'made partial Payment <1 payment'
      when round(p.Total_Payment_Activity,2) >= round(a.monthly_payment,2)  and round(p.Total_Payment_Activity,2) <round((a.monthly_payment*2),2) then 'made 1+ payment'
      when round(p.Total_Payment_Activity,2)  >=round((a.monthly_payment*2),2) then 'made 2+ payment'
      else 'made no payment' end     
,call_bucket=case when call_bucket IS NULL then 'no call' else call_bucket end 
into #finallist

from #accounts a
left join #payments p on a.[acct number]=p.[Loan Number]
left join #calls c on a.[acct number]=c.accountNumber

Select f.[acct number] 
into #acctsForProcess
from #finallist f
where f.payment_bucket='made no payment'
and f.call_bucket='outbound dial_contact_rpc';
Go





use DataMart;

If OBJECT_ID('tempdb..#AcctNumsAndDates') IS NOT NULL
	DROP TABLE #AcctNumsAndDates;
	
If OBJECT_ID('tempdb..#finalMessage') IS NOT NULL
	DROP TABLE #finalMessage;
Go
	
Create Table #AcctNumsAndDates (
RecordID int Primary Key Identity
,AcctNum bigint NOT NULL
,CallDate date 
,CallTime varchar(5)
,Comments varchar(max) DEFAULT NULL
);
Create Table #finalMessage (
RecordID int Primary Key Identity
,AcctNum bigint NOT NULL
,CallDate date NOT NULL
,CallTime varchar(5) DEFAULT 0
,Comments varchar(max)
);
Go

INSERT INTO #AcctNumsAndDates 
Select a.[acct number] as AcctNum, m.TRAN_DATE as CallDate, m2.TRAN_TIME as CallTime, Comments = NULL
from sqlprd13.tempdb.#acctsForProcess a
left join 
		(select distinct m.ACCOUNT_NUMBER, m.TRAN_DATE
		 from [DataMart].[dbo].[V_Rpt_Loan_Activity_Message] M) M
		 on M.ACCOUNT_NUMBER = a.[acct number]
left join 
		(select distinct m.ACCOUNT_NUMBER, m.TRAN_TIME
		 from [DataMart].[dbo].[V_Rpt_Loan_Activity_Message] M) M2
		 on M2.ACCOUNT_NUMBER = a.[acct number]
Go




/******Cursor To Concatenate comments starts here******/
Declare Table_Cursor CURSOR	
	Local Static Forward_ONLY

For 
	Select AcctNum, CallDate, CallTime
	From #AcctNumsAndDates;

Declare @AcctVar varchar(10), @DateVar varchar(10), @TimeVar varchar(5), @ExecVar varchar(max);

Open Table_Cursor;
Fetch Next From Table_Cursor INTO
	@AcctVar, @DateVar, @TimeVar;
While @@FETCH_STATUS = 0
Begin
	Set @ExecVar = '
	WITH CTE_Concatenated AS
    (
    SELECT  M.ACCOUNT_NUMBER,
			M.TRAN_DATE,
			M.TRAN_TIME,
			M.TRAN_BATCH_SEQUENCE_NUMBER,
            RTRIM(Convert(Varchar(Max),M.TRAN_MESSAGE)) as Tran_Message
    FROM    [DataMart].[dbo].[V_Rpt_Loan_Activity_Message] M
    WHERE   M.ACCOUNT_NUMBER = ';
    Set @ExecVar = @ExecVar + '''' + @AcctVar + '''' 
		+ ' and M.TRAN_DATE = ' + '''' + @DateVar + '''' 
		+ ' and M.TRAN_TIME = ' + '''' + @TimeVar + '''';
    Set @ExecVar = @ExecVar + ' and M.TRAN_BATCH_SEQUENCE_NUMBER = 1
    UNION ALL
    SELECT  M.ACCOUNT_NUMBER,
			M.TRAN_DATE,
			M.TRAN_TIME,
			M.TRAN_BATCH_SEQUENCE_NUMBER,
			CTE_Concatenated.TRAN_MESSAGE + RTRIM(Convert(Varchar(Max),M.TRAN_MESSAGE))
    FROM    CTE_Concatenated
    JOIN    [DataMart].[dbo].[V_Rpt_Loan_Activity_Message] M
    ON      M.TRAN_BATCH_SEQUENCE_NUMBER = CTE_Concatenated.TRAN_BATCH_SEQUENCE_NUMBER + 1
				and M.ACCOUNT_NUMBER = CTE_Concatenated.ACCOUNT_NUMBER
				and M.TRAN_DATE = CTE_Concatenated.TRAN_DATE
				and M.TRAN_TIME = CTE_Concatenated.TRAN_TIME
    )
    INSERT INTO #finalMessage
    Select ACCOUNT_NUMBER, TRAN_DATE, TRAN_TIME, TRAN_MESSAGE
    from CTE_Concatenated
	WHERE   TRAN_BATCH_SEQUENCE_NUMBER = (SELECT MAX(TRAN_BATCH_SEQUENCE_NUMBER) 
										FROM [DataMart].[dbo].[V_Rpt_Loan_Activity_Message] M
										Where M.ACCOUNT_NUMBER = ';
										Set @ExecVar = @ExecVar + '''' + @AcctVar + '''' 
										+ ' and M.TRAN_DATE = ' + '''' + @DateVar + '''' 
										+ ' and M.TRAN_TIME = ' + '''' + @TimeVar + ''''
										+  ');'
	EXEC (@ExecVar);
	FETCH NEXT FROM Table_Cursor INTO @AcctVar, @DateVar, @TimeVar;
End;
CLOSE Table_Cursor;
DEALLOCATE Table_Cursor;
Go

Select *
from #finalMessage;
