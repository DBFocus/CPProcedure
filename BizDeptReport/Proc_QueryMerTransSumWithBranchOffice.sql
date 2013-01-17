--[Modified] at 2012-07-13 by ������  Description:Add Financial Dept Configuration Data
--[Modified] at 2012-12-13 by ������  Description:Add Branch Office Fund Trans Data
if OBJECT_ID(N'Proc_QueryMerTransSumWithBranchOffice',N'P') is not null
begin
	drop procedure Proc_QueryMerTransSumWithBranchOffice;
end
go

Create Procedure Proc_QueryMerTransSumWithBranchOffice
	@StartDate datetime = '2012-11-01',
	@PeriodUnit nChar(4) = N'�Զ���',
	@EndDate datetime = '2012-11-29',
	@BranchOfficeName nChar(15) = N'���������������޹�˾'
as 
begin

--1. Check Input
if (@StartDate is null or ISNULL(@PeriodUnit,N'') = N'' or ISNULL(@BranchOfficeName,N'') = N'')
begin
	raiserror(N'Input params cannot be empty in Proc_QueryMerTransSumWithBranchOffice',16,1);
end


--2. Prepare StartDate and EndDate
declare @CurrStartDate datetime;
declare @CurrEndDate datetime;

if(@PeriodUnit = N'��')
begin
	set @CurrStartDate = left(CONVERT(char,@StartDate,120),7) + '-01';
	set @CurrEndDate = DATEADD(MONTH,1,@CurrStartDate);
end
else if(@PeriodUnit = N'����')
begin
	set @CurrStartDate = left(CONVERT(char,@StartDate,120),7) + '-01';
	set @CurrEndDate = DATEADD(QUARTER,1,@CurrStartDate);
end
else if(@PeriodUnit = N'����')
begin
	set @CurrStartDate = left(CONVERT(char,@StartDate,120),7) + '-01';
	set @CurrEndDate = DATEADD(QUARTER,2,@CurrStartDate);
end
else if(@PeriodUnit = N'�Զ���')
begin
	set @CurrStartDate = @StartDate;
	set @CurrEndDate = DATEADD(DAY,1,@EndDate);
end


--3.Get SpecifiedTimePeriod Data
select
	MerchantNo,
	(select MerchantName from Table_OraMerchants where MerchantNo = Table_OraTransSum.MerchantNo) MerchantName,
	sum(TransCount) TransCount,
	sum(TransAmount) TransAmount
into
	#OraTransSum
from
	Table_OraTransSum
where
	CPDate >= @CurrStartDate
	and
	CPDate < @CurrEndDate
group by
	MerchantNo;
	
select 
	MerchantNo,
	(select MerchantName from Table_MerInfo where MerchantNo = FactDailyTrans.MerchantNo) MerchantName,
	sum(SucceedTransCount) SucceedTransCount,
	sum(SucceedTransAmount) SucceedTransAmount
into
	#FactDailyTrans
from
	FactDailyTrans
where
	DailyTransDate >= @CurrStartDate
	and
	DailyTransDate < @CurrEndDate
group by
	MerchantNo;
	
select 
	EmallTransSum.MerchantNo,
	EmallTransSum.MerchantName,
	sum(EmallTransSum.SucceedTransCount) TransCount,
	sum(EmallTransSum.SucceedTransAmount) TransAmount
into 
	#EmallTransSum
from	
	Table_EmallTransSum EmallTransSum
	inner join
	Table_BranchOfficeNameRule BranchOfficeNameRule
	on
		EmallTransSum.BranchOffice = BranchOfficeNameRule.UnnormalBranchOfficeName
where 
	EmallTransSum.TransDate >= @CurrStartDate
	and
	EmallTransSum.TransDate < @CurrEndDate
	and
	BranchOfficeNameRule.UmsSpec = @BranchOfficeName
group by
	EmallTransSum.MerchantNo,
	EmallTransSum.MerchantName;

--Add Branch Office Fund Trans Data
select 
	N'' as MerchantNo,
	N'����' as MerchantName,
	SUM(Branch.B2BPurchaseCnt+Branch.B2BRedemptoryCnt+Branch.B2CPurchaseCnt+Branch.B2CRedemptoryCnt) TransCount,
	SUM(Branch.B2BPurchaseAmt+Branch.B2BRedemptoryAmt+Branch.B2CPurchaseAmt+Branch.B2CRedemptoryAmt) TransAmount
into
	#BranchFundTrans
from 
	Table_UMSBranchFundTrans Branch
	inner join
	Table_BranchOfficeNameRule BranchOfficeNameRule
	on
		Branch.BranchOfficeName = BranchOfficeNameRule.UnnormalBranchOfficeName
where	
	Branch.TransDate >= @CurrStartDate
	and
	Branch.TransDate <  @CurrEndDate
	and
	BranchOfficeNameRule.NormalBranchOfficeName = @BranchOfficeName;

--4. Get table MerWithBranchOffice
select
	SalesDeptConfiguration.MerchantNo
into
	#MerWithBranchOffice
from
	Table_BranchOfficeNameRule BranchOfficeNameRule 
	inner join
	Table_SalesDeptConfiguration SalesDeptConfiguration
	on
		BranchOfficeNameRule.UnnormalBranchOfficeName = SalesDeptConfiguration.BranchOffice
where 
	BranchOfficeNameRule.UmsSpec = @BranchOfficeName
union 
select
	Finance.MerchantNo
from
	Table_BranchOfficeNameRule BranchOfficeNameRule 
	inner join
	Table_FinancialDeptConfiguration Finance
	on
		BranchOfficeNameRule.UnnormalBranchOfficeName = Finance.BranchOffice
where	BranchOfficeNameRule.UmsSpec = @BranchOfficeName;


--5. Get TransDetail respectively
select
	OraTransSum.MerchantName,
	OraTransSum.MerchantNo,
	OraTransSum.TransCount,
	OraTransSum.TransAmount
into
	#OraTransWithBO
from
	#OraTransSum OraTransSum
	inner join
	#MerWithBranchOffice MerWithBranchOffice
	on
		OraTransSum.MerchantNo = MerWithBranchOffice.MerchantNo;

select
	FactDailyTrans.MerchantName,
	FactDailyTrans.MerchantNo,
	FactDailyTrans.SucceedTransCount as TransCount,
	FactDailyTrans.SucceedTransAmount as TransAmount
into
	#FactDailyTransWithBO
from
	#FactDailyTrans FactDailyTrans
	inner join
	#MerWithBranchOffice MerWithBranchOffice
	on
		FactDailyTrans.MerchantNo = MerWithBranchOffice.MerchantNo;

	
--6. Union all Trans
select
	MerchantName,
	MerchantNo,
	ISNULL(TransCount,0) TransCount,
	convert(decimal, ISNULL(TransAmount,0))/100.0 TransAmount
into
	#AllTransSum
from
	(select
		MerchantName,
		MerchantNo,
		TransCount,
		TransAmount
	from
		#OraTransWithBO	
	union all
	select 
		MerchantName,
		MerchantNo,
		TransCount,
		TransAmount
	from
		#FactDailyTransWithBO	
	union all
	select
		MerchantName,
		MerchantNo,
		TransCount,
		TransAmount
	from
		#EmallTransSum
	union all 
	select
		MerchantName,
		MerchantNo,
		TransCount,
		TransAmount
	from
		#BranchFundTrans) Mer; 
	
	
--7. Get Special MerchantNo
select 
	SalesDeptConfiguration.MerchantNo
into
	#SpecMerchantNo
from
	Table_SalesDeptConfiguration SalesDeptConfiguration
	inner join
	Table_BranchOfficeNameRule BranchOfficeNameRule
	on
		SalesDeptConfiguration.BranchOffice = BranchOfficeNameRule.UnnormalBranchOfficeName
where
	BranchOfficeNameRule.UmsSpecMark = 1
union
select
	Finance.MerchantNo
from
	Table_FinancialDeptConfiguration Finance
	inner join
	Table_BranchOfficeNameRule BranchOfficeNameRule
	on
		Finance.BranchOffice = BranchOfficeNameRule.UnnormalBranchOfficeName
where
	BranchOfficeNameRule.UmsSpecMark = 1;
	

--8. Get Result	
update
	AllTransSum
set
	AllTransSum.MerchantName = ('*'+AllTransSum.MerchantName)
from
	#AllTransSum AllTransSum
	inner join
	#SpecMerchantNo SpecMerchantNo
	on
		AllTransSum.MerchantNo = SpecMerchantNo.MerchantNo;

select
	MerchantName,
	MerchantNo,
	TransCount,
	TransAmount
from	
	#AllTransSum;


--9. drop temp table
drop table #OraTransSum;
drop table #FactDailyTrans;
drop table #EmallTransSum;
drop table #MerWithBranchOffice;
drop table #OraTransWithBO;
drop table #FactDailyTransWithBO;
drop table #AllTransSum;
drop table #SpecMerchantNo;
drop table #BranchFundTrans;

end

