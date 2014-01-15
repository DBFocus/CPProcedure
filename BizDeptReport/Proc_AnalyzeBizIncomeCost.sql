
if OBJECT_ID(N'Proc_AnalyzeBizIncomeCost',N'P') is not null
begin
	drop procedure Proc_AnalyzeBizIncomeCost
end
go

create procedure Proc_AnalyzeBizIncomeCost
	@StartDate date,
	@EndDate date,
	@CompareMethod nvarchar(4),
	@BizCategory nvarchar(80)
as
begin
	--1. Check input params
	if (@StartDate is null
		or @EndDate is null
		or @CompareMethod not in (N'同比',N'环比')
		or ISNULL(@BizCategory, N'') = N'')
	begin
		raiserror(N'Input parameters aren''t valid.', 16, 1);
	end
	
	--2. Calculate @EndDate, @CompareStartDate, @CompareEndDate
	set @EndDate = DATEADD(day,1,@EndDate);
	declare @CompareStartDate date;
	declare @CompareEndDate date;
	if @CompareMethod = N'同比'
	begin
		set @CompareStartDate = DATEADD(year,-1,@StartDate);
		set @CompareEndDate = DATEADD(year,-1,@EndDate);
	end
	else if @CompareMethod = N'环比'
	begin
		declare @DiffCnt int;
		if DAY(@StartDate) = 1 and DAY(@EndDate) = 1
		begin
			set @DiffCnt = DATEDIFF(MONTH,@StartDate,@EndDate);
			set @CompareStartDate = DATEADD(month,-1*@DiffCnt,@StartDate);			
		end
		else
		begin
			set @DiffCnt = DATEDIFF(DAY,@StartDate,@EndDate);
			set @CompareStartDate = DATEADD(day,-1*@DiffCnt,@StartDate);
		end
		set @CompareEndDate = @StartDate;
	end

	--3. Split @BizCategory into #BizCategory
	create table #BizCategory
	(
		CategoryName nvarchar(40)
	);

	declare @sqlStr nvarchar(max);
	set @sqlStr = N'select N''' + REPLACE(@BizCategory, N',', N''' union all select N''') + N'''';
	
	insert into #BizCategory
	(
		CategoryName		
	)
	exec(@sqlStr);
	
	--3.1 Set @ApplyEndDate
	declare @ApplyEndDate date;
	set @ApplyEndDate = dateadd(day, 1, GETDATE());
	
	--4. 新代收付平台 #TraScreenSum
	create table #TraScreenSumResult
	(
		Plat varchar(80),	
		MerchantNo char(15),
		MerchantName nvarchar(50),		
		ChannelNo char(8),
		ChannelName nvarchar(50),
		ApplyDate date,
		ApplyEndDate date,
		RuleDesc nvarchar(max),
		DiffTransAmt decimal(15,2),
		DiffTransCnt int,
		DiffFeeAmt decimal(15,2),
		DiffCostAmt decimal(15,2)
	);
	
	if exists(select 1 from #BizCategory where CategoryName in (N'代收',N'常规代付'))
	begin
		--4.1 Calculate Current Period #TraScreenSum1
		create table #TraCost1
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
		
		insert into #TraCost1
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
			ChannelNo,
			SucceedAmt as TransAmt,
			SucceedCnt as TransCnt,
			FeeAmt,
			CostAmt,
			N'Table_TraScreenSum' as Plat,
			case when
				TransType in ('100002', '100005')
			then
				N'常规代付'
			when
				TransType in ('100001', '100004')
			then
				N'代收'
			else
				N'不确定'	
			end as Category
		into
			#TraScreenSum1
		from
			#TraCost1;
		
		--4.2 Calculate Compare Period #TraScreenSum2
		create table #TraCost2
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
	
		insert into #TraCost2
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
			@CompareStartDate,
			@CompareEndDate;
			
		select
			CPDate as TransDate,
			MerchantNo,
			ChannelNo,
			SucceedAmt as TransAmt,
			SucceedCnt as TransCnt,
			FeeAmt,
			CostAmt,
			N'Table_TraScreenSum' as Plat,
			case when
				TransType in ('100002', '100005')
			then
				N'常规代付'
			when
				TransType in ('100001', '100004')
			then
				N'代收'
			else
				N'不确定'	
			end as Category
		into
			#TraScreenSum2
		from
			#TraCost2;
			
		--4.3 #TraScreenSum1 and #TraScreenSum2 into #TraScreenSumResult
		With tra1 as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt,
				TransCnt,
				FeeAmt,
				CostAmt
			from
				#TraScreenSum1
			where
				Category in (select CategoryName from #BizCategory)
		),
		tra2 as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt,
				TransCnt,
				FeeAmt,
				CostAmt
			from
				#TraScreenSum2
			where
				Category in (select CategoryName from #BizCategory)
		),
		traFull as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt as DiffTransAmt,
				TransCnt as DiffTransCnt,
				FeeAmt as DiffFeeAmt,
				CostAmt as DiffCostAmt
			from
				tra1
			union all
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				-1*TransAmt,
				-1*TransCnt,
				-1*FeeAmt,
				-1*CostAmt
			from
				tra2		
		),
		traCostRule as (
			select
				rule1.ChannelNo,
				rule1.ApplyDate,
				isnull(nextrule.ApplyDate, @ApplyEndDate) as ApplyEndDate,
				case rule1.FeeType
					when 'Fixed'
					then N'每笔成本' + convert(varchar, convert(decimal(10, 3), rule1.FeeValue/100)) + N'元'
					when 'Percent'
					then N'按金额的' + convert(varchar, convert(decimal(10, 3), rule1.FeeValue * 100)) + N'%收取成本'
					else N'' 
				end as RuleDesc
			from
				Table_TraCostRuleByChannel rule1
				outer apply
				(select top(1)
					rule2.ApplyDate
				from
					Table_TraCostRuleByChannel rule2
				where
					rule2.ChannelNo = rule1.ChannelNo
					and
					rule2.ApplyDate > rule1.ApplyDate
				order by
					rule2.ApplyDate) as nextrule		
		)
		insert into #TraScreenSumResult
		(
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt		
		)
		select
			N'Table_TraScreenSum' as Plat,
			traFull.MerchantNo,
			(select MerchantName from Table_TraMerchantInfo where MerchantNo = traFull.MerchantNo) as MerchantName,
			traFull.ChannelNo,
			(select ChannelName from Table_TraChannelConfig where ChannelNo = traFull.ChannelNo) as ChannelName,
			traCostRule.ApplyDate,
			dateadd(day, -1, MIN(traCostRule.ApplyEndDate)) as ApplyEndDate,
			MIN(traCostRule.RuleDesc) as RuleDesc,
			SUM(traFull.DiffTransAmt) as DiffTransAmt,
			SUM(traFull.DiffTransCnt) as DiffTransCnt,
			SUM(traFull.DiffFeeAmt) as DiffFeeAmt,
			SUM(traFull.DiffCostAmt) as DiffCostAmt
		from
			traFull
			left join
			traCostRule
			on
				traFull.ChannelNo = traCostRule.ChannelNo
				and
				traFull.TransDate >= traCostRule.ApplyDate
				and
				traFull.TransDate < traCostRule.ApplyEndDate
		group by
			traFull.MerchantNo,
			traFull.ChannelNo,
			traCostRule.ApplyDate;
			
		--4.4 Clear temp tables
		drop table #TraCost1;
		drop table #TraScreenSum1;
		drop table #TraCost2;
		drop table #TraScreenSum2;
	end


	--5. 老代付 #OraTransSum
	create table #OraTransSumResult
	(
		Plat varchar(80),	
		MerchantNo char(15),
		MerchantName nvarchar(50),		
		ChannelNo char(8),
		ChannelName nvarchar(50),
		ApplyDate date,
		ApplyEndDate date,
		RuleDesc nvarchar(max),
		DiffTransAmt decimal(15,2),
		DiffTransCnt int,
		DiffFeeAmt decimal(15,2),
		DiffCostAmt decimal(15,2)	
	);
	
	if exists(select 1 from #BizCategory where CategoryName in (N'常规代付')) 
	begin
		--5.1 Calculate Current Period #OraTransSum1
		create table #OraCost1
		(
			BankSettingID char(8),    
			MerchantNo char(20),    
			CPDate date,  
			TransCnt int,  
			TransAmt bigint,  
			CostAmt decimal(20,2)  
		);

		insert into #OraCost1
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
			OraCost.BankSettingID as ChannelNo,    
			OraCost.MerchantNo,    
			OraCost.CPDate as TransDate,  
			OraCost.TransCnt,  
			OraCost.TransAmt,
			isnull(OraCost.TransCnt * Additional.FeeValue, OraFee.FeeAmount) as FeeAmt,
			OraCost.CostAmt,
			case when
				OraCost.MerchantNo in ('606060290000015','606060290000016','606060290000017')
			then
				N'兴业渠道'
			else
				N'常规代付'		
			end as Category
		into
			#OraTransSum1
		from
			#OraCost1 OraCost
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
		
		--5.2 Calculate Compare Period #OraTransSum2	
		create table #OraCost2
		(
			BankSettingID char(8),    
			MerchantNo char(20),    
			CPDate date,  
			TransCnt int,  
			TransAmt bigint,  
			CostAmt decimal(20,2)  
		);

		insert into #OraCost2
		(
			BankSettingID,    
			MerchantNo,    
			CPDate,  
			TransCnt,  
			TransAmt,  
			CostAmt
		)
		exec Proc_CalOraCost 
			@CompareStartDate, 
			@CompareEndDate, 
			null;

		select
			OraCost.BankSettingID as ChannelNo,    
			OraCost.MerchantNo,    
			OraCost.CPDate as TransDate,  
			OraCost.TransCnt,  
			OraCost.TransAmt,
			isnull(OraCost.TransCnt * Additional.FeeValue, OraFee.FeeAmount) as FeeAmt,
			OraCost.CostAmt,
			case when
				OraCost.MerchantNo in ('606060290000015','606060290000016','606060290000017')
			then
				N'兴业渠道'
			else
				N'常规代付'		
			end as Category
		into
			#OraTransSum2
		from
			#OraCost2 OraCost
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
				
		--5.3 #OraTransSum1 and #OraTransSum2 into #OraTransSumResult
		With ora1 as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt,
				TransCnt,
				FeeAmt,
				CostAmt
			from
				#OraTransSum1
			where
				Category in (select CategoryName from #BizCategory)
		),
		ora2 as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt,
				TransCnt,
				FeeAmt,
				CostAmt
			from
				#OraTransSum2
			where
				Category in (select CategoryName from #BizCategory)
		),
		oraFull as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt as DiffTransAmt,
				TransCnt as DiffTransCnt,
				FeeAmt as DiffFeeAmt,
				CostAmt as DiffCostAmt
			from
				ora1
			union all
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				-1*TransAmt,
				-1*TransCnt,
				-1*FeeAmt,
				-1*CostAmt
			from
				ora2		
		),
		oraCostRule as (
			select
				rule1.BankSettingID as ChannelNo,
				rule1.ApplyStartDate as ApplyDate,
				case
					when rule1.ApplyEndDate > @ApplyEndDate 
					then @ApplyEndDate
					else rule1.ApplyEndDate
				end as ApplyEndDate,
				N'每笔成本' + convert(varchar, convert(decimal(10, 3), rule1.FeeValue/100.0)) + N'元' as RuleDesc
			from
				Table_OraBankCostRule rule1
		)
		insert into #OraTransSumResult
		(
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt		
		)
		select
			N'Table_OraTransSum' as Plat,
			oraFull.MerchantNo,
			(select MerchantName from Table_OraMerchants where MerchantNo = oraFull.MerchantNo) as MerchantName,
			oraFull.ChannelNo,
			(select BankName from Table_OraBankSetting where BankSettingID = oraFull.ChannelNo) as ChannelName,
			oraCostRule.ApplyDate,
			dateadd(day, -1, MIN(oraCostRule.ApplyEndDate)) as ApplyEndDate,
			MIN(oraCostRule.RuleDesc) as RuleDesc,
			SUM(oraFull.DiffTransAmt) as DiffTransAmt,
			SUM(oraFull.DiffTransCnt) as DiffTransCnt,
			SUM(oraFull.DiffFeeAmt) as DiffFeeAmt,
			SUM(oraFull.DiffCostAmt) as DiffCostAmt
		from
			oraFull
			left join
			oraCostRule
			on
				oraFull.ChannelNo = oraCostRule.ChannelNo
				and
				oraFull.TransDate >= oraCostRule.ApplyDate
				and
				oraFull.TransDate < oraCostRule.ApplyEndDate
		group by
			oraFull.MerchantNo,
			oraFull.ChannelNo,
			oraCostRule.ApplyDate;
			
		--5.4 Clear temp tables
		drop table #OraCost1;
		drop table #OraTransSum1;
		drop table #OraCost2;
		drop table #OraTransSum2;
	end;


	--6. Upop直连 #UpopliqFeeLiqResult
	create table #UpopDirectResult
	(
		Plat varchar(80),	
		MerchantNo char(15),
		MerchantName nvarchar(50),		
		ChannelNo char(8),
		ChannelName nvarchar(50),
		ApplyDate date,
		ApplyEndDate date,
		RuleDesc nvarchar(max),
		DiffTransAmt decimal(15,2),
		DiffTransCnt int,
		DiffFeeAmt decimal(15,2),
		DiffCostAmt decimal(15,2)	
	);
	
	if exists(select 1 from #BizCategory where CategoryName in (N'UPOP-直连',N'UPOP-手机支付',N'铁道部'))
	begin
		--6.1 Calculate Current Period #UpopDirect1
		create table #UpopDirect1
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

		insert into #UpopDirect1
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
			u.GateNo as ChannelNo,
			u.MerchantNo,
			u.TransCnt,
			u.TransAmt,
			u.FeeAmt,
			u.CostAmt,
			case when 
				u.MerchantNo = '802080290000015'
			then
				N'铁道部'
			when
				r.CpMerNo in (select MerchantNo from Table_InstuMerInfo where InstuNo = '999920130320153')
			then
				N'UPOP-手机支付'
			else
				N'UPOP-直连'
			end as Category
		into
			#UpopliqFeeLiqResult1
		from
			#UpopDirect1 u
			left join
			Table_CpUpopRelation r
			on
				u.MerchantNo = r.UpopMerNo;
				
		--6.2 Calculate Compare Period #UpopDirect2
		create table #UpopDirect2
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

		insert into #UpopDirect2
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
		exec Proc_CalUpopCost @CompareStartDate, @CompareEndDate;

		select
			u.TransDate,
			u.GateNo as ChannelNo,
			u.MerchantNo,
			u.TransCnt,
			u.TransAmt,
			u.FeeAmt,
			u.CostAmt,
			case when 
				u.MerchantNo = '802080290000015'
			then
				N'铁道部'
			when
				r.CpMerNo in (select MerchantNo from Table_InstuMerInfo where InstuNo = '999920130320153')
			then
				N'UPOP-手机支付'
			else
				N'UPOP-直连'
			end as Category
		into
			#UpopliqFeeLiqResult2
		from
			#UpopDirect2 u
			left join
			Table_CpUpopRelation r
			on
				u.MerchantNo = r.UpopMerNo;
		
		--6.3 #UpopDirect1 and #UpopDirect2 into #UpopDirectResult
		With upopd1 as (
			select
				d1.TransDate,
				d1.MerchantNo,
				d1.ChannelNo,
				d1.TransAmt,
				d1.TransCnt,
				d1.FeeAmt,
				d1.CostAmt
			from
				#UpopliqFeeLiqResult1 d1
			where
				d1.Category in (select CategoryName from #BizCategory)
		),
		upopd2 as (
			select
				d2.TransDate,
				d2.MerchantNo,
				d2.ChannelNo,
				d2.TransAmt,
				d2.TransCnt,
				d2.FeeAmt,
				d2.CostAmt
			from
				#UpopliqFeeLiqResult2 d2
			where
				d2.Category in (select CategoryName from #BizCategory)
		),
		upopdFull as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt as DiffTransAmt,
				TransCnt as DiffTransCnt,
				FeeAmt as DiffFeeAmt,
				CostAmt as DiffCostAmt
			from
				upopd1
			union all
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				-1*TransAmt,
				-1*TransCnt,
				-1*FeeAmt,
				-1*CostAmt
			from
				upopd2
		),
		upopCostRule as (
			select 
				rule1.ApplyDate,
				(select 
					isnull(min(rule2.ApplyDate),@ApplyEndDate)
				from 
					Table_UpopCostRule rule2 
				where 
					rule2.ApplyDate > rule1.ApplyDate) as ApplyEndDate,
				(select stuff(
					(select
						'，' +
						case when
							ByUpop.CostRuleType = 'ByMer'
							and
							ByUpop.FeeType = 'Fixed'
						then 
							N'商户：' + ByUpop.RuleObject + N' 每笔成本' + convert(varchar, convert(decimal(10, 3), ByUpop.FeeValue/100)) + N'元'
						when
							ByUpop.CostRuleType = 'ByMer'
							and
							ByUpop.FeeType = 'Percent'
						then 
							N'商户：' + ByUpop.RuleObject + N' 按金额的' + convert(varchar, convert(decimal(10, 3), ByUpop.FeeValue * 100)) + N'%收取成本'
						when
							ByUpop.CostRuleType = 'ByMcc'
							and
							ByUpop.FeeType = 'Fixed'
						then
							N'MCC：' + ByUpop.RuleObject + N' 每笔成本' + convert(varchar, convert(decimal(10, 3), ByUpop.FeeValue/100)) + N'元'
						when
							ByUpop.CostRuleType = 'ByMcc'
							and
							ByUpop.FeeType = 'Percent'
						then 
							N'MCC：' + ByUpop.RuleObject + N' 按金额的' + convert(varchar, convert(decimal(10, 3), ByUpop.FeeValue * 100)) + N'%收取成本'
						when
							ByUpop.CostRuleType = 'ByCd'
						then
							N'借贷标记：' + ByUpop.RuleObject + N' 按金额的' + convert(varchar, convert(decimal(10, 3), ByUpop.FeeValue * 100)) + N'%收取成本'
						else
							N''
						end
					from
						Table_UpopCostRule ByUpop
					where
						ByUpop.ApplyDate <= rule1.ApplyDate
						and
						not exists(select
										1
									from
										Table_UpopCostRule ByUpop2
									where
										ByUpop2.ApplyDate <= rule1.ApplyDate
										and
										ByUpop2.RuleObject = ByUpop.RuleObject
										and
										ByUpop2.ApplyDate > ByUpop.ApplyDate)
					for xml path('')),
					1,
					1,
					'')) as RuleDesc
			from 
				Table_UpopCostRule rule1
			group by
				rule1.ApplyDate
		)
		insert into #UpopDirectResult
		(
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt		
		)
		select
			N'Table_UpopliqFeeliqResult' as Plat,
			upopdFull.MerchantNo,
			(select MerchantName from Table_UpopliqMerInfo where MerchantNo = upopdFull.MerchantNo) as MerchantName,
			upopdFull.ChannelNo,
			(select GateDesc from Table_UpopliqGateRoute where GateNo = upopdFull.ChannelNo) as ChannelName,
			upopCostRule.ApplyDate,
			dateadd(day, -1, MIN(upopCostRule.ApplyEndDate)) as ApplyEndDate,
			MIN(upopCostRule.RuleDesc) as RuleDesc,
			SUM(upopdFull.DiffTransAmt) as DiffTransAmt,
			SUM(upopdFull.DiffTransCnt) as DiffTransCnt,
			SUM(upopdFull.DiffFeeAmt) as DiffFeeAmt,
			SUM(upopdFull.DiffCostAmt) as DiffCostAmt
		from
			upopdFull
			left join
			upopCostRule
			on
				upopdFull.TransDate >= upopCostRule.ApplyDate
				and
				upopdFull.TransDate < upopCostRule.ApplyEndDate
		group by
			upopdFull.MerchantNo,
			upopdFull.ChannelNo,
			upopCostRule.ApplyDate;
			
		--6.4 Clear temp tables
		drop table #UpopDirect1;
		drop table #UpopliqFeeLiqResult1;
		drop table #UpopDirect2;
		drop table #UpopliqFeeLiqResult2;				
	end
			
	--7. 支付控台 #FeeCalcResult
	create table #FeeCalcResult
	(
		Plat varchar(80),	
		MerchantNo char(15),
		MerchantName nvarchar(50),		
		ChannelNo char(8),
		ChannelName nvarchar(50),
		ApplyDate date,
		ApplyEndDate date,
		RuleDesc nvarchar(max),
		DiffTransAmt decimal(15,2),
		DiffTransCnt int,
		DiffFeeAmt decimal(15,2),
		DiffCostAmt decimal(15,2)	
	);
	
	if exists(select 1 from #BizCategory where CategoryName in (N'B2C-境内',N'B2C-境外',N'B2C-手机支付',N'预授权',N'信用支付',N'UPOP-间连',N'互联宝',N'B2B',N'代收'))
	begin	
		--7.1 Calculate Current Period #FeeCalc1
		create table #FeeCalc1
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
			Category nvarchar(40) default(N'')
		);

		insert into #FeeCalc1
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

		--7.2 更新Category 
		--代收
		update
			f
		set
			f.Category = N'代收'
		from
			#FeeCalc1 f
		where
			f.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'代扣')
			and
			f.Category = N'';

		--其他接入类
		update
			fcr
		set
			fcr.Category = N'其他接入类'
		from
			#FeeCalc1 fcr
		where
			fcr.GateNo in ('5901','5902')
			and
			fcr.Category = N'';

		--B2B
		update
			fcr
		set
			fcr.Category = N'B2B'
		from
			#FeeCalc1 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'B2B')
			and
			fcr.Category = N'';

		--互联宝
		update
			fcr
		set
			fcr.Category = N'互联宝'
		from
			#FeeCalc1 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'EPOS')
			and
			fcr.Category = N'';

		--UPOP间连
		update
			fcr
		set
			fcr.Category = N'UPOP-间连'
		from
			#FeeCalc1 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'UPOP')
			and
			fcr.Category = N'';

		--信用支付
		update
			fcr
		set
			fcr.Category = N'信用支付'
		from
			#FeeCalc1 fcr
		where
			fcr.GateNo in ('5601','5602','5603')
			and
			fcr.Category = N'';			

		--预授权
		update
			fcr
		set
			fcr.Category = N'预授权'
		from
			#FeeCalc1 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'MOTO')
			and
			fcr.Category = N'';
			
		--B2C-手机支付
		update
			fcr
		set
			fcr.Category = N'B2C-手机支付'
		from
			#FeeCalc1 fcr
		where
			fcr.GateNo in ('7607')
			and
			fcr.MerchantNo in (select MerchantNo from Table_InstuMerInfo where InstuNo = '999920130320153')
			and
			fcr.Category = N'';	

		--B2C-境外
		update
			fcr
		set
			fcr.Category = N'B2C-境外'
		from
			#FeeCalc1 fcr
		where
			fcr.MerchantNo in (select MerchantNo from Table_MerInfoExt)
			and
			fcr.Category = N'';

		--B2C-境内
		update
			fcr
		set
			fcr.Category = N'B2C-境内'
		from
			#FeeCalc1 fcr
		where
			fcr.Category = N'';
			
		--7.3 Calculate Compare Period #FeeCalc2
		create table #FeeCalc2
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
			Category nvarchar(40) default(N'')
		);

		insert into #FeeCalc2
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
		exec Proc_CalPaymentCost @CompareStartDate,@CompareEndDate,null,'on'

		--7.4 更新Category 
		--代收
		update
			f
		set
			f.Category = N'代收'
		from
			#FeeCalc2 f
		where
			f.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'代扣')
			and
			f.Category = N'';

		--其他接入类
		update
			fcr
		set
			fcr.Category = N'其他接入类'
		from
			#FeeCalc2 fcr
		where
			fcr.GateNo in ('5901','5902')
			and
			fcr.Category = N'';

		--B2B
		update
			fcr
		set
			fcr.Category = N'B2B'
		from
			#FeeCalc2 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'B2B')
			and
			fcr.Category = N'';

		--互联宝
		update
			fcr
		set
			fcr.Category = N'互联宝'
		from
			#FeeCalc2 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'EPOS')
			and
			fcr.Category = N'';

		--UPOP间连
		update
			fcr
		set
			fcr.Category = N'UPOP-间连'
		from
			#FeeCalc2 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'UPOP')
			and
			fcr.Category = N'';

		--信用支付
		update
			fcr
		set
			fcr.Category = N'信用支付'
		from
			#FeeCalc2 fcr
		where
			fcr.GateNo in ('5601','5602','5603')
			and
			fcr.Category = N'';			

		--预授权
		update
			fcr
		set
			fcr.Category = N'预授权'
		from
			#FeeCalc2 fcr
		where
			fcr.GateNo in (select GateNo from Table_GateCategory where GateCategory1 = N'MOTO')
			and
			fcr.Category = N'';
			
		--B2C-手机支付
		update
			fcr
		set
			fcr.Category = N'B2C-手机支付'
		from
			#FeeCalc2 fcr
		where
			fcr.GateNo in ('7607')
			and
			fcr.MerchantNo in (select MerchantNo from Table_InstuMerInfo where InstuNo = '999920130320153')
			and
			fcr.Category = N'';	

		--B2C-境外
		update
			fcr
		set
			fcr.Category = N'B2C-境外'
		from
			#FeeCalc2 fcr
		where
			fcr.MerchantNo in (select MerchantNo from Table_MerInfoExt)
			and
			fcr.Category = N'';

		--B2C-境内
		update
			fcr
		set
			fcr.Category = N'B2C-境内'
		from
			#FeeCalc2 fcr
		where
			fcr.Category = N'';
		
		--7.5 Merge #FeeCalc1 and #FeeCalc2 into #FeeCalcResult
		With feeCalc1 as (
			select
				FeeEndDate as TransDate,
				MerchantNo,
				GateNo as ChannelNo,
				TransAmt,
				TransCnt,
				FeeAmt,
				CostAmt
			from
				#FeeCalc1
			where
				Category in (select CategoryName from #BizCategory)
		),
		feeCalc2 as (
			select
				FeeEndDate as TransDate,
				MerchantNo,
				GateNo as ChannelNo,
				TransAmt,
				TransCnt,
				FeeAmt,
				CostAmt
			from
				#FeeCalc2
			where
				Category in (select CategoryName from #BizCategory)
		),
		feeCalcFull as (
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				TransAmt as DiffTransAmt,
				TransCnt as DiffTransCnt,
				FeeAmt as DiffFeeAmt,
				CostAmt as DiffCostAmt
			from
				feeCalc1
			union all
			select
				TransDate,
				MerchantNo,
				ChannelNo,
				-1*TransAmt,
				-1*TransCnt,
				-1*FeeAmt,
				-1*CostAmt
			from
				feeCalc2
		),
		costRule as (
			select
				rule1.GateNo as ChannelNo,
				rule1.ApplyDate,
				isnull(rule2.ApplyDate, @ApplyEndDate) as ApplyEndDate,
				dbo.Fn_PaymentCostCalcExp(rule1.GateNo, rule1.ApplyDate) as RuleDesc
			from
				Table_GateCostRule rule1
				outer apply
				(select top(1)
					ApplyDate
				from
					Table_GateCostRule
				where
					GateNo = rule1.GateNo
					and
					ApplyDate > rule1.ApplyDate
				order by
					ApplyDate desc
				) rule2
		)
		insert into #FeeCalcResult
		(
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt		
		)
		select
			N'Table_FeeCalcResult' as Plat,
			feeCalcFull.MerchantNo,
			(select MerchantName from Table_MerInfo where MerchantNo = feeCalcFull.MerchantNo) as MerchantName,
			feeCalcFull.ChannelNo,
			(select GateAlias from Table_GateRoute where GateNo = feeCalcFull.ChannelNo) as ChannelName,
			costRule.ApplyDate,
			dateadd(day, -1, MIN(costRule.ApplyEndDate)) as ApplyEndDate,
			MIN(costRule.RuleDesc) as RuleDesc,
			SUM(feeCalcFull.DiffTransAmt) as DiffTransAmt,
			SUM(feeCalcFull.DiffTransCnt) as DiffTransCnt,
			SUM(feeCalcFull.DiffFeeAmt) as DiffFeeAmt,
			SUM(feeCalcFull.DiffCostAmt) as DiffCostAmt
		from
			feeCalcFull
			left join
			costRule
			on
				feeCalcFull.ChannelNo = costRule.ChannelNo
				and
				feeCalcFull.TransDate >= costRule.ApplyDate
				and
				feeCalcFull.TransDate < costRule.ApplyEndDate
		group by
			feeCalcFull.MerchantNo,
			feeCalcFull.ChannelNo,
			costRule.ApplyDate;
			
		--7.6 Clear temp table
		drop table #FeeCalc1;
		drop table #FeeCalc2;		
	end
	
	

	;With FinalResult as
	(
		select
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt
		from
			#TraScreenSumResult
		union all
		select
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt	
		from
			#OraTransSumResult
		union all
		select
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt	
		from
			#UpopDirectResult
		union all
		select
			Plat,	
			MerchantNo,
			MerchantName,		
			ChannelNo,
			ChannelName,
			ApplyDate,
			ApplyEndDate,
			RuleDesc,
			DiffTransAmt,
			DiffTransCnt,
			DiffFeeAmt,
			DiffCostAmt		
		from
			#FeeCalcResult
	)
	select
		Plat,	
		MerchantNo,
		MerchantName,		
		ChannelNo,
		ChannelName,
		ApplyDate,
		ApplyEndDate,
		RuleDesc,
		DiffTransAmt/100.0 as DiffTransAmt,
		DiffTransCnt,
		DiffFeeAmt/100.0 as DiffFeeAmt,
		DiffCostAmt/100.0 as DiffCostAmt,
		(DiffFeeAmt - DiffCostAmt)/100.0 as DiffProfitAmt
	from
		FinalResult;


	-- Clear temp tables
	drop table #BizCategory;
	drop table #TraScreenSumResult;
	drop table #OraTransSumResult;
	drop table #UpopDirectResult;
	drop table #FeeCalcResult;
end