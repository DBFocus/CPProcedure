
--Created by chen.wu on 2014.1.13

if OBJECT_ID(N'Proc_MerBizRank',N'P') is not null
begin
	drop procedure Proc_MerBizRank
end
go

create procedure Proc_MerBizRank
	@MerchantType nvarchar(10),
	@StartDate date,
	@EndDate date	
as
begin

--1. Check input params
if (ISNULL(@MerchantType, N'') = N''
	or @StartDate is null
	or @EndDate is null)
begin
	raiserror(N'Input parameters cannot be empty.', 16, 1);  
end

--2. Adjust end date
set @EndDate = DATEADD(day, 1, @EndDate);

--3. Get open account merchants
select
	MerchantNo,
	MerchantName,
	MerchantType
into
	#OpenAccountMers
from
	Table_MerOpenAccountInfo
where
	MerchantType = @MerchantType;

--4. FactDailyTrans
select
	MerchantNo,
	SUM(SucceedTransCount) as SucceedTransCnt,
	SUM(SucceedTransAmount) as SucceedTransAmt
into
	#FactDailyTrans
from
	FactDailyTrans
where
	DailyTransDate >= @StartDate
	and
	DailyTransDate < @EndDate
	and
	MerchantNo in (select MerchantNo from #OpenAccountMers)
group by
	MerchantNo;
	
--4.1 update foreign merchant currency
with CuryFullRate as
(
	select
		CuryCode,
		AVG(CuryRate) as CuryRate
	from
		Table_CuryFullRate
	where
		CuryDate >= @StartDate
		and
		CuryDate < @EndDate
	group by
		CuryCode
)
update
	trans
set
	trans.SucceedTransAmt = trans.SucceedTransAmt * rate.CuryRate
from
	#FactDailyTrans trans
	inner join
	Table_MerInfoExt ext
	on
		trans.MerchantNo = ext.MerchantNo
	inner join
	CuryFullRate rate
	on
		ext.CuryCode = rate.CuryCode;

--5. TraScreenSum
select
	MerchantNo,
	SUM(SucceedCnt) as SucceedTransCnt,
	SUM(SucceedAmt) as SucceedTransAmt
into
	#TraScreenSum
from
	Table_TraScreenSum
where
	CPDate >= @StartDate
	and
	CPDate < @EndDate
	and
	MerchantNo in (select MerchantNo from #OpenAccountMers)
group by
	MerchantNo;

--6. OraTransSum
select
	MerchantNo,
	SUM(TransCount) as SucceedTransCnt,
	SUM(TransAmount) as SucceedTransAmt
into
	#OraTransSum
from
	Table_OraTransSum
where
	CPDate >= @StartDate
	and
	CPDate < @EndDate
	and
	MerchantNo in (select MerchantNo from #OpenAccountMers)	
group by
	MerchantNo;
	
--7. UpopliqFeeLiqResult
select
	relation.CpMerNo as MerchantNo,
	SUM(upop.PurCnt) as SucceedTransCnt,
	SUM(upop.PurAmt) as SucceedTransAmt
into
	#UpopliqFeeLiqResult
from
	Table_UpopliqFeeLiqResult upop
	inner join
	Table_CpUpopRelation relation
	on
		upop.MerchantNo = relation.UpopMerNo
where
	upop.TransDate >= @StartDate
	and
	upop.TransDate < @EndDate
	and
	relation.CpMerNo in (select MerchantNo from #OpenAccountMers)
group by
	relation.CpMerNo;

--8. All Data
With AllData as
(
select
	MerchantNo,
	SucceedTransCnt,
	SucceedTransAmt
from
	#FactDailyTrans
union all
select
	MerchantNo,
	SucceedTransCnt,
	SucceedTransAmt
from
	#TraScreenSum
union all
select
	MerchantNo,
	SucceedTransCnt,
	SucceedTransAmt
from
	#OraTransSum
union all
select
	MerchantNo,
	SucceedTransCnt,
	SucceedTransAmt
from
	#UpopliqFeeLiqResult
)
select
	MerchantNo,
	SUM(SucceedTransCnt) as SucceedTransCnt,
	SUM(SucceedTransAmt) as SucceedTransAmt
into
	#AllData
from
	AllData
group by
	MerchantNo;

--9. Final Result
With MerScore as (
	select top(100)
		MerchantNo,
		(101 - ROW_NUMBER() over(order by SucceedTransCnt desc)) + (101 - ROW_NUMBER() over(order by SucceedTransAmt desc)) as Score
	from
		#AllData
	order by
		Score desc
)
select
	ms.MerchantNo,
	mers.MerchantName,
	ms.Score	
from
	MerScore ms
	inner join
	#OpenAccountMers mers
	on
		ms.MerchantNo = mers.MerchantNo
order by
	ms.Score desc;
		

--10. Clear temp tables
drop table #OpenAccountMers;
drop table #FactDailyTrans;
drop table #TraScreenSum;
drop table #OraTransSum;
drop table #UpopliqFeeLiqResult;
drop table #AllData;

end