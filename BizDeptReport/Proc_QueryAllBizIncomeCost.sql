
if OBJECT_ID(N'Proc_QueryAllBizIncomeCost',N'P') is not null
begin
	drop procedure Proc_QueryAllBizIncomeCost
end
go

create procedure Proc_QueryAllBizIncomeCost
	@StartDate date,
	@EndDate date
as
begin
--1. Check input date param
if (@StartDate is null or @EndDate is null)
begin
	raiserror(N'Input date parameters cannot be empty.', 16, 1);    
end

set @EndDate = DATEADD(day, 1, @EndDate);

--2. ���� #WestUnion
select
	CPDate as TransDate,
	MerchantNo,
	'' as Gate,
	SUM(DestTransAmount) as TransAmt,
	COUNT(1) as TransCnt,
	0 as FeeAmt,
	0.0 as CostAmt,
	N'Table_WUTransLog' as Plat,
	N'�������' as Category,
	140 as Rn
into
	#WestUnion
from 
	Table_WUTransLog
where
	CPDate >= @StartDate
	and
	CPDate < @EndDate
group by
	CPDate,
	MerchantNo;

--3. �´��ո�ƽ̨ #TraScreenSum
create table #TraCost
(
	MerchantNo char(15),
	ChannelNo char(6),
	TransType varchar(20),
	CPDate date,
	TotalCnt int,
	TotalAmt decimal(15, 2),
	SucceedCnt int,
	SucceedAmt decimal(15,2),
	CalFeeCnt int,
	CalFeeAmt decimal(15,2),
	CalCostCnt int,
	CalCostAmt decimal(15,2),
	FeeAmt decimal(15,2),
	CostAmt decimal(15,2)
);

insert into #TraCost
(
	MerchantNo,
	ChannelNo,
	TransType,
	CPDate,
	TotalCnt,
	TotalAmt,
	SucceedCnt,
	SucceedAmt,
	CalFeeCnt,
	CalFeeAmt,
	CalCostCnt,
	CalCostAmt,
	FeeAmt,
	CostAmt
)
exec Proc_CalTraCost
	@StartDate,
	@EndDate;

select
	CPDate as TransDate,
	MerchantNo,
	ChannelNo as Gate,
	CalFeeAmt as TransAmt,
	CalFeeCnt as TransCnt,
	FeeAmt,
	CostAmt,
	N'Table_TraScreenSum' as Plat,
	case when
		TransType in ('100002', '100005')
	then
		N'�������'
	when
		TransType in ('100001', '100004')
	then
		N'����'
	else
		N'��ȷ��'	
	end as Category,
	case when
		TransType in ('100002', '100005')
	then
		160
	when
		TransType in ('100001', '100004')
	then
		180
	else
		-1	
	end as Rn
into
	#TraScreenSum
from
	#TraCost;

--4. �ϴ��� #OraTransSum
create table #OraCost
(
	BankSettingID char(8),    
	MerchantNo char(20),    
	CPDate date,  
	TransCnt int,  
	TransAmt bigint,  
	CostAmt decimal(20,2)  
);

insert into #OraCost
(
	BankSettingID,    
	MerchantNo,    
	CPDate,  
	TransCnt,  
	TransAmt,  
	CostAmt
)
exec Proc_CalOraCost 
	@StartDate, 
	@EndDate, 
	null;

select
	OraCost.BankSettingID as Gate,    
	OraCost.MerchantNo,    
	OraCost.CPDate as TransDate,  
	OraCost.TransCnt,  
	OraCost.TransAmt,
	isnull(OraCost.TransCnt * Additional.FeeValue, OraFee.FeeAmount) as FeeAmt,
	OraCost.CostAmt,
	N'Table_OraTransSum' as Plat,
	case when
		OraCost.MerchantNo in ('606060290000015','606060290000016','606060290000017')
	then
		N'��ҵ����'
	else
		N'�������'		
	end as Category,
	case when
		OraCost.MerchantNo in ('606060290000015','606060290000016','606060290000017')
	then
		170
	else
		160		
	end as Rn
into
	#OraTransSum
from
	#OraCost OraCost
	inner join
	Table_OraTransSum OraFee
	on
		OraCost.BankSettingID = OraFee.BankSettingID
		and
		OraCost.CPDate = OraFee.CPDate
		and
		OraCost.MerchantNo = OraFee.MerchantNo
	left join
	Table_OraAdditionalFeeRule Additional
	on
		OraCost.MerchantNo = Additional.MerchantNo;

--5. Upopֱ�� #UpopliqFeeLiqResult
create table #UpopDirect
(
	GateNo char(4),
	MerchantNo char(20),
	TransDate date,
	CdFlag char(2),
	TransAmt bigint,
	TransCnt int,
	FeeAmt bigint,
	CostAmt decimal(20,2)
);

insert into #UpopDirect
(
	GateNo,
	MerchantNo,
	TransDate,
	CdFlag,
	TransAmt,
	TransCnt,
	FeeAmt,
	CostAmt
)
exec Proc_CalUpopCost @StartDate, @EndDate;

select
	u.TransDate,
	u.GateNo as Gate,
	u.MerchantNo,
	u.TransCnt,
	u.TransAmt,
	u.FeeAmt,
	u.CostAmt,
	N'Table_UpopliqFeeLiqResult' as Plat,
	case when 
		u.MerchantNo = '802080290000015'
	then
		N'������'
	when
		r.CpMerNo in (select MerchantNo from Table_InstuMerInfo where InstuNo = '999920130320153')
	then
		N'UPOP-�ֻ�֧��'
	else
		N'UPOP-ֱ��'
	end as Category,
	case when 
		u.MerchantNo = '802080290000015'
	then
		90
	when
		r.CpMerNo in (select MerchantNo from Table_InstuMerInfo where InstuNo = '999920130320153')
	then
		80
	else
		70
	end as Rn
into
	#UpopliqFeeLiqResult
from
	#UpopDirect u
	left join
	Table_CpUpopRelation r
	on
		u.MerchantNo = r.UpopMerNo;
		
--6. ֧����̨ #FeeCalcResult
--6.1 FeeCalcResult������
create table #FeeCalcResult
(
	GateNo char(4),
	MerchantNo Char(20),
	FeeEndDate date,
	TransCnt int,
	TransAmt decimal(20,2),
	CostAmt decimal(20,2),
	FeeAmt decimal(20,2),
	InstuFeeAmt decimal(20,2),
	Plat varchar(40) default('Table_FeeCalcResult'),
	Category nvarchar(40) default(N''),
	Rn int default(-3)
);

insert into #FeeCalcResult
(
	GateNo,
	MerchantNo,
	FeeEndDate,
	TransCnt,
	TransAmt,
	CostAmt,
	FeeAmt,
	InstuFeeAmt
)
exec Proc_CalPaymentCost @StartDate,@EndDate,null,'on'

--6.2 ����Category ����
update
	f
set
	f.Category = N'����',
	f.Rn = 180
from
	#FeeCalcResult f
where
	f.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'����')
	and
	f.Category = N'';

--6.3 ����Category ����������
update
	fcr
set
	fcr.Category = N'����������',
	fcr.Rn = 120
from
	#FeeCalcResult fcr
where
	fcr.GateNo in ('5901','5902')
	and
	fcr.Category = N'';

--6.4 ����Category B2B
update
	fcr
set
	fcr.Category = N'B2B',
	fcr.Rn = 110
from
	#FeeCalcResult fcr
where
	fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'B2B')
	and
	fcr.Category = N'';

--6.5 ����Category Epos
update
	fcr
set
	fcr.Category = N'������',
	fcr.Rn = 100
from
	#FeeCalcResult fcr
where
	fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'EPOS')
	and
	fcr.Category = N'';

--6.6 ����Category UPOP����
update
	fcr
set
	fcr.Category = N'UPOP-����',
	fcr.Rn = 60
from
	#FeeCalcResult fcr
where
	fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'UPOP')
	and
	fcr.Category = N'';

--6.7 ����Category ����֧��
update
	fcr
set
	fcr.Category = N'����֧��',
	fcr.Rn = 50
from
	#FeeCalcResult fcr
where
	fcr.GateNo in ('5601','5602','5603')
	and
	fcr.Category = N'';
	

--6.7 ����Category Ԥ��Ȩ
update
	fcr
set
	fcr.Category = N'Ԥ��Ȩ',
	fcr.Rn = 40
from
	#FeeCalcResult fcr
where
	fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'MOTO')
	and
	fcr.Category = N'';
	
--6.8 ����Category B2C-�ֻ�֧��
update
	fcr
set
	fcr.Category = N'B2C-�ֻ�֧��',
	fcr.Rn = 30
from
	#FeeCalcResult fcr
where
	fcr.GateNo in ('7607')
	and
	fcr.MerchantNo in (select MerchantNo from Table_InstuMerInfo where InstuNo = '999920130320153')
	and
	fcr.Category = N'';	

--6.9 ����Category B2C-����
update
	fcr
set
	fcr.Category = N'B2C-����',
	fcr.Rn = 20
from
	#FeeCalcResult fcr
where
	fcr.MerchantNo in (select MerchantNo from Table_MerInfoExt)
	and
	fcr.Category = N'';

--6.10 ����Category B2C-����
update
	fcr
set
	fcr.Category = N'B2C-����',
	fcr.Rn = 10
from
	#FeeCalcResult fcr
where
	fcr.Category = N'';

--declare @StartDate date;
--declare @EndDate date;
--set @StartDate = '2013-09-01';
--set @EndDate = '2013-10-01';
	
--7 B2C������ת�� #TrfTransLog
With Fund_Trf as
(
	select
		case when 
			TransType in ('2070')
		then
			N'ת��'
		else
			N'����B2C'
		end as Category,
		case when 
			TransType in ('2070')
		then
			220
		else
			200
		end as Rn,
		TransAmt,
		TransType
	from   
		Table_TrfTransLog  
	where
		TransType in ('2070', '3010','3020','3030','3040','3050')
		and
		TransDate >= @StartDate
		and
		TransDate < @EndDate
)
select
	null as TransDate,
	'' as MerchantNo,
	'' as Gate,
	case Category
		when N'ת��' then SUM(TransAmt)
		when N'����B2C' then SUM(case when TransType = '3020' then -1*TransAmt else TransAmt end)
	end as TransAmt,
	case Category
		when N'ת��' then COUNT(TransAmt)
		when N'����B2C' then SUM(case when TransType = '3020' then -1 else 1 end)
	end as TransCnt,	
	0.0 FeeAmt,
	0.0 CostAmt,
	N'TrfTransLog' as Plat,
	Category,
	Rn
into
	#TrfTransLog
from
	Fund_Trf
group by
	Category,
	Rn;
	
--8 FinalResult
With AllTrans as
(
	select
		TransDate,
		MerchantNo,
		Gate,
		TransAmt,
		TransCnt,
		FeeAmt,
		CostAmt,
		Plat,
		Category,
		Rn
	from
		#WestUnion
	union all
	select
		TransDate,
		MerchantNo,
		Gate,
		TransAmt,
		TransCnt,
		FeeAmt,
		CostAmt,
		Plat,
		Category,
		Rn
	from
		#TraScreenSum
	union all
	select
		TransDate,
		MerchantNo,
		Gate,
		TransAmt,
		TransCnt,
		FeeAmt,
		CostAmt,
		Plat,
		Category,
		Rn
	from	
		#OraTransSum
	union all
	select
		TransDate,
		MerchantNo,
		Gate,
		TransAmt,
		TransCnt,
		FeeAmt,
		CostAmt,
		Plat,
		Category,
		Rn
	from
		#UpopliqFeeLiqResult
	union all
	select
		FeeEndDate as TransDate,
		MerchantNo,
		GateNo as Gate,
		TransAmt,
		TransCnt,
		FeeAmt,
		CostAmt,
		Plat,
		Category,
		Rn
	from
		#FeeCalcResult
	union all
	select
		TransDate,
		MerchantNo,
		Gate,
		TransAmt,
		TransCnt,
		FeeAmt,
		CostAmt,
		Plat,
		Category,
		Rn	
	from
		#TrfTransLog
)
select
	Category,
	SUM(TransAmt)/10000000000.0 as TransAmt,
	SUM(TransCnt)/10000.0 as TransCnt,
	SUM(FeeAmt)/1000000.0 as FeeAmt,
	SUM(CostAmt)/1000000.0 as CostAmt
into
	#AllBiz
from
	AllTrans
group by
	Category;
	
create table #FullCategory
(
	Rn int,
	Category1 nvarchar(40),
	Category2 nvarchar(40),
	Category3 nvarchar(40)
);

insert into 
	#FullCategory
	(
		Rn,
		Category1,
		Category2,
		Category3
	)
values
	(10, N'һ������֧��ҵ��',N'B2C',N'B2C-����'),
	(20, N'һ������֧��ҵ��',N'B2C',N'B2C-����'),
	(30, N'һ������֧��ҵ��',N'B2C',N'B2C-�ֻ�֧��'),
	(40, N'һ������֧��ҵ��',N'B2C',N'Ԥ��Ȩ'),
	(50, N'һ������֧��ҵ��',N'B2C',N'����֧��'),
	(60, N'һ������֧��ҵ��',N'UPOP',N'UPOP-����'),
	(70, N'һ������֧��ҵ��',N'UPOP',N'UPOP-ֱ��'),
	(80, N'һ������֧��ҵ��',N'UPOP',N'UPOP-�ֻ�֧��'),
	(90, N'һ������֧��ҵ��',N'UPOP',N'������'),
	(100, N'һ������֧��ҵ��',N'֧������',N'������'),
	(110, N'һ������֧��ҵ��',N'֧������',N'B2B'),
	(120, N'һ������֧��ҵ��',N'֧������',N'����������'),
	(130, N'һ������֧��ҵ��',N'֧������',N'����ѧ��'),
	(140, N'һ������֧��ҵ��',N'֧������',N'�������'),
	(150, N'һ������֧��ҵ��',N'֧������',N'�ն˽���'),
	
	(160, N'���ո�ҵ��',N'����',N'�������'),
	(170, N'���ո�ҵ��',N'����',N'��ҵ����'),
	(180, N'���ո�ҵ��',N'���ո�����',N'����'),
	(190, N'���ո�ҵ��',N'���ո�����',N'����ʵ��֧��'),
	
	(200, N'���ҵ��',N'����',N'����B2C'),
	(210, N'���ҵ��',N'����',N'����B2B'),
	(220, N'���ҵ��',N'ת��',N'ת��'),
	(230, N'���ҵ��',N'ת��',N'���ÿ�'),
	(240, N'���ҵ��',N'�������',N'�����'),
	(250, N'���ҵ��',N'�������',N'���ƽ̨'),
	(260, N'���ҵ��',N'�������',N'����ƽ̨');

	
select
	f.Rn,
	f.Category1,
	f.Category2,
	f.Category3,
	isnull(a.TransAmt, 0) as TransAmt,
	isnull(a.TransCnt, 0) as TransCnt,
	isnull(a.FeeAmt, 0) as FeeAmt,
	isnull(a.CostAmt, 0) as CostAmt,
	isnull(a.FeeAmt,0) - isnull(a.CostAmt,0) as ProfitAmt
from
	#FullCategory f
	left join
	#AllBiz a
	on
		f.Category3 = a.Category
order by
	f.Rn
	

--8 Clear temp tables
--drop table #DateRange;
drop table #WestUnion;
drop table #TraScreenSum;
drop table #OraCost;
drop table #OraTransSum;
drop table #UpopDirect;
drop table #UpopliqFeeLiqResult;
drop table #FeeCalcResult;
drop table #TraCost;
drop table #TrfTransLog;
drop table #AllBiz;
drop table #FullCategory;

end