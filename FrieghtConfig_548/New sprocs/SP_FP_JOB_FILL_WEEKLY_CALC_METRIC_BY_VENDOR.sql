USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_JOB_FILL_WEEKLY_CALC_METRIC_BY_VENDOR]    Script Date: 7/7/2022 9:40:51 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ==================================================================================================================
 Author:		Johana Aleman
 Create date:   12/11/2018
 Description:	The Freight Pricing Engine should calculate the following
				metrics and refresh them on a weekly basis at the Supplier 
				Warehouse level for “X” months back, “X” being configurable 
				?	Average PO Units
				?	Average PO Weight
				?	Average PO Cube
				?	Average PO Pallets
				?	PO Count
				?	Average Expense per pound
				?	Average Revenue
					•	Average Freight per pound
					•	Average Freight Allowance per pound
				?	Average Margin
				?	Total Expense
				?	Total Revenue
					•	Total Freight
					•	Total Freight Allowance
				?	Total Margin
				Get the number of months that the job is going back in the past from 
				the Default config table
Log Update:
	04032019	Johana Aleman	Fixed issue with crossdock POs values were sum up as the number of loads(Spiral#1813) Freight pricingI
	04252019	Johana Aleman	Round avg po wiehgt,units, pallets and cubes to return the closest integer value
	05262020	Johana Aleman	Use the [dbo].[PALLET_HANDLING_RATE] table to get the direct PO =[BACKHAUL_RATE]
								and Crossdock = [CROSS_DOCK_RATE]
 ==================================================================================================================*/
ALTER PROCEDURE [dbo].[SP_FP_JOB_FILL_WEEKLY_CALC_METRIC_BY_VENDOR]
AS
BEGIN
	SET NOCOUNT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
/**********************************************************************
Example 1:	
		EXEC dbo.SP_FP_JOB_FILL_WEEKLY_CALC_METRIC_BY_VENDOR 
***********************************************************************/
--Variable declarations
	DECLARE	@SUPPLIER_SCREEN_MONTHS_BACK INT
		,	@StartDate DATE
		,	@EndDate DATE
		,	@Today DATE
		,   @system VARCHAR(50)

	SET @Today = GETDATE()
	
	----Clean up the table
	DELETE FROM FP_WEEKLY_CALC_METRIC_BY_VENDOR
	
	
	----CREATE the temp tables
	CREATE TABLE #NOTFULLYBILLED (
		PO_NUMBER VARCHAR(100),
		LO_PURCHASE_ORDER_ID BIGINT,
		LO_LOAD_NUMBER BIGINT
	)

	CREATE TABLE #PO_LIST (
		LO_PURCHASE_ORDER_ID BIGINT,
		MAX_26PALLETS_FINAL_CALC DECIMAL(10,3)
	)

	CREATE TABLE #PO_FREIGHT (
		LO_PURCHASE_ORDER_ID BIGINT,
		FREIGHT_PAID_PO DECIMAL
	)
	
	----

	DECLARE @source_system VARCHAR(50) 

	DECLARE db_cursor CURSOR FOR 
	SELECT DISTINCT SOURCE_SYSTEM 
	FROM LO_PURCHASE_ORDERS 

	OPEN db_cursor  
	FETCH NEXT FROM db_cursor INTO @source_system 

	WHILE @@FETCH_STATUS = 0  
	BEGIN  

	--Get the value of the number of months that job will go back from the config default table
	SET @SUPPLIER_SCREEN_MONTHS_BACK = COALESCE ( (SELECT SUPPLIER_SCREEN_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = @source_system) , 
													(SELECT SUPPLIER_SCREEN_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = 'DEFAULT')	)
		
	--(SELECT TOP 1 SUPPLIER_SCREEN_MONTHS_BACK FROM dbo.FP_DEFAULT_CONFIG)
	SET @StartDate =  '1/2/2020'-- DATEADD(MONTH,-@SUPPLIER_SCREEN_MONTHS_BACK, @Today) 
	SET @EndDate = '1/3/2020' --@Today
	SET @system = @source_system

	--To get the POs that are NOT full Billed 
	INSERT 
	INTO #NOTFULLYBILLED 
	SELECT *
	FROM dbo.fnGetPO_NOTFULLYBILLED(@StartDate, @EndDate, @system)

	PRINT @source_system
	PRINT @SUPPLIER_SCREEN_MONTHS_BACK
	FETCH NEXT FROM db_cursor INTO @source_system  
	END 

	CLOSE db_cursor  

	DEALLOCATE db_cursor 

	--END CURSOR
	
	CREATE CLUSTERED INDEX #NFBIDX ON #NOTFULLYBILLED (LO_PURCHASE_ORDER_ID)	


	DECLARE db_cursor CURSOR FOR 
	SELECT DISTINCT SOURCE_SYSTEM 
	FROM LO_PURCHASE_ORDERS 

	OPEN db_cursor  
	FETCH NEXT FROM db_cursor INTO @source_system 

	WHILE @@FETCH_STATUS = 0  
	BEGIN  

	--Get the value of the number of months that job will go back from the config default table
	SET @SUPPLIER_SCREEN_MONTHS_BACK = 1--(SELECT TOP 1 SUPPLIER_SCREEN_MONTHS_BACK FROM dbo.FP_DEFAULT_CONFIG)
	SET @StartDate =  '1/2/2020'-- DATEADD(MONTH,-@SUPPLIER_SCREEN_MONTHS_BACK, @Today) 
	SET @EndDate = '1/3/2020' --@Today
	SET @system = @source_system




	--Get all the RCV POs with FPA calculation even when this calculation apply only to Backhaul
	--that are fully billed
	INSERT
	INTO #PO_LIST
	SELECT * 
	FROM [dbo].[fnGetPOSWithCalculatePalletsFPA](@StartDate, @EndDate, @system)
	WHERE LO_PURCHASE_ORDER_ID NOT IN (SELECT LO_PURCHASE_ORDER_ID FROM #NOTFULLYBILLED) --Lead out POs that are not fully billed


	PRINT @source_system
	FETCH NEXT FROM db_cursor INTO @source_system  
	END 

	CLOSE db_cursor  

	DEALLOCATE db_cursor 

	--END CURSOR

	CREATE CLUSTERED INDEX #IDX_PO_LIST ON #PO_LIST(LO_PURCHASE_ORDER_ID)


	DECLARE db_cursor CURSOR FOR 
	SELECT DISTINCT SOURCE_SYSTEM 
	FROM LO_PURCHASE_ORDERS 

	OPEN db_cursor  
	FETCH NEXT FROM db_cursor INTO @source_system 

	WHILE @@FETCH_STATUS = 0  
	BEGIN  

	--Get the value of the number of months that job will go back from the config default table
	SET @SUPPLIER_SCREEN_MONTHS_BACK = 1--(SELECT TOP 1 SUPPLIER_SCREEN_MONTHS_BACK FROM dbo.FP_DEFAULT_CONFIG)
	SET @StartDate =  '1/2/2020'-- DATEADD(MONTH,-@SUPPLIER_SCREEN_MONTHS_BACK, @Today) 
	SET @EndDate = '1/3/2020' --@Today
	SET @system = @source_system


	--To get the Suppliers PO expenses for all the RCV POs
	INSERT
	INTO #PO_FREIGHT
	SELECT LO_PURCHASE_ORDER_ID, SUM(cast(ISNULL(FREIGHT_PAID_PO,0) as decimal(10,3))) AS FREIGHT_PAID_PO
	FROM  dbo.fnGetSuppliersPOExpenses(@StartDate, @EndDate, @system) 
	WHERE LO_PURCHASE_ORDER_ID IN (SELECT LO_PURCHASE_ORDER_ID FROM #PO_LIST) 
	GROUP BY LO_PURCHASE_ORDER_ID

	PRINT @source_system
	FETCH NEXT FROM db_cursor INTO @source_system  
	END 

	CLOSE db_cursor  

	DEALLOCATE db_cursor 

	CREATE CLUSTERED INDEX #IDXPO_Freight ON #PO_Freight (LO_PURCHASE_ORDER_ID)

	SELECT tv.TMS_VENDOR_ID
	,	lpo.TOTAL_UNITS
	,	lpo.TOTAL_WEIGHT
	,	lpo.TOTAL_CUBES	
	,	CEILING(ISNULL(lpo.TOTAL_PALLETS,0)) AS TOTAL_PALLETS
	,	PO.MAX_26PALLETS_FINAL_CALC
	,	lpo.LO_PURCHASE_ORDER_ID
	,	ISNULL(lpo.PROD_FRT,0) AS PROD_FRT
	,   ABS(lpo.ALLOWANCE) AS ALLOWANCE
	,	ISNULL(lpo.PROD_FRT,0) +  ABS(ISNULL(lpo.ALLOWANCE,0)) AS REVENUE
	,	ISNULL(Freight.FREIGHT_PAID_PO,0) AS PO_EXPENSE
	,   ISNULL(CAST(NULL AS DECIMAL(10,3)),0) AS BACKHAUL_EXPENSE_PO
	,   ISNULL(CAST(NULL AS DECIMAL(10,3)),0) AS TOTAL_EXPENSE
	,   lpo.DIS_WHS_ID
	,	CAST(lpo.REC_DATE AS DATE) as REC_DATE
	,	lpo.SOURCE_SYSTEM
	INTO #POS
	FROM #PO_LIST PO
		INNER JOIN LO_PURCHASE_ORDERS lpo
			ON PO.LO_PURCHASE_ORDER_ID = lpo.LO_PURCHASE_ORDER_ID
		INNER JOIN dbo.TMS_VENDOR tv 
				ON lpo.TMS_VENDOR_ID = tv.TMS_VENDOR_ID
		LEFT JOIN #PO_FREIGHT Freight  
			ON PO.LO_PURCHASE_ORDER_ID = Freight.LO_PURCHASE_ORDER_ID		

	CREATE CLUSTERED INDEX #IX_LPO ON #POS (LO_PURCHASE_ORDER_ID)

	/*Update Pallets(if load is backhaul then use MAX_26PALLETS_FINAL_CALC as Total Pallets otherwise use Total Pallets from PO table.
	 Backhaul Expenses base on the Carrier id and source whs (backhaul load)*/	
	UPDATE #POS
	SET TOTAL_PALLETS = ISNULL(lpo.MAX_26PALLETS_FINAL_CALC,0) 
	,	BACKHAUL_EXPENSE_PO = ISNULL(CASE WHEN lpo.DIS_WHS_ID = ll.DESTINATION_WHS_ID 
										THEN MAX_26PALLETS_FINAL_CALC * phr.BACKHAUL_RATE
										ELSE MAX_26PALLETS_FINAL_CALC * phr.CROSS_DOCK_RATE									 
									 END,0)
	FROM #POS lpo
		INNER JOIN LO_PO_LOADS lpl 
			ON lpo.LO_PURCHASE_ORDER_ID = lpl.LO_PURCHASE_ORDER_ID 
				AND (lpl.IS_DELETED IS NULL OR lpl.IS_DELETED = 0)
		INNER JOIN LO_LOADS ll 
			ON lpl.LO_LOAD_NUMBER = ll.LO_LOAD_NUMBER
				AND ll.CR_CARRIER_ID = 78 
				AND ll.SOURCE_WHS_ID IS NULL 
		LEFT JOIN dbo.tblUNFIfiscalCalendar uc
			ON REC_DATE BETWEEN uc.WeekStart AND uc.WeekEnd
		LEFT JOIN dbo.PALLET_HANDLING_RATE phr
			ON	uc.FiscalYear = phr.[FISCAL_YEAR]
				AND lpo.SOURCE_SYSTEM = phr.SOURCE_SYSTEM	
	 

	----Update POs Expense
	UPDATE #POS
	SET TOTAL_EXPENSE = PO_EXPENSE + BACKHAUL_EXPENSE_PO 

	
	INSERT INTO FP_WEEKLY_CALC_METRIC_BY_VENDOR
	SELECT TMS_VENDOR_ID
		, CAST(CEILING(AVG(TOTAL_UNITS)) as decimal(18,3)) AS AVG_UNITS
		, CAST(CEILING(AVG(TOTAL_WEIGHT)) as decimal(18,3)) AS AVG_WEIGHT
		, CAST(CEILING(AVG(TOTAL_CUBES)) as decimal(18,3)) AS AVG_CUBES
		, CAST(CEILING(AVG(TOTAL_PALLETS)) as decimal(18,3)) AS AVG_PALLETS
		, COUNT(DISTINCT LO_PURCHASE_ORDER_ID) as PO_COUNT
		, CAST(AVG(REVENUE) as decimal(18,3)) AS AVG_REVENUE
		, CAST(AVG(PROD_FRT) as decimal(18,3)) AS AVG_FREIGHT
		, CAST(AVG(ALLOWANCE) as decimal(18,3)) AS AVG_ALLOWANCE
		, CAST(AVG(TOTAL_EXPENSE) as decimal(18,3)) AS AVG_TOTAL_EXPENSE
		, CAST(AVG(REVENUE) - AVG(TOTAL_EXPENSE) as decimal(18,3)) AS AVG_MARGIN
		, CAST(SUM(REVENUE) as decimal(18,3)) AS TOTAL_REVENUE
		, CAST(SUM(PROD_FRT) as decimal(18,3)) AS TOTAL_FREIGHT
		, CAST(SUM(ALLOWANCE) as decimal(18,3)) AS TOTAL_ALLOWANCE
		, CAST(SUM(TOTAL_EXPENSE) as decimal(18,3)) AS TOTAL_EXPENSE
		, CAST(SUM(REVENUE) - SUM(TOTAL_EXPENSE) as decimal(18,3)) AS TOTAL_MARGIN
		, CAST(AVG(REVENUE) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_REVENUE_PER_LB
		, CAST(AVG(PROD_FRT) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_FREIGHT_PER_LB
		, CAST(AVG(ALLOWANCE) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_ALLOWANCE_PER_LB
		, CAST(AVG(TOTAL_EXPENSE)/NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_EXPENSE_PER_LB
		, CAST((AVG(REVENUE) - AVG(TOTAL_EXPENSE)) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_MARGIN_PER_LB
	FROM #POS
	GROUP BY TMS_VENDOR_ID
	
	
	DROP TABLE #NOTFULLYBILLED
	DROP TABLE #PO_LIST
	DROP TABLE #PO_FREIGHT

	DROP TABLE #POS


END


GO


