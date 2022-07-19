USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_JOB_FILL_FP_WEEKLY_SUPPLIER_WHS_MARGIN_LOSS]    Script Date: 7/7/2022 9:45:01 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ==================================================================================================================
 Author:		Johana Aleman
 Create date:   04/25/2019
 Description:	Creation of a Margin Loss Notification that will run on a weekly basis
			    The Supplier Margin Loss job will run on a weekly basis and will calculate the following metrics for 
				PO’s rolled up to the Vendor WHS level that are Received and fully billed. The job will use Margin Loss 
				Months Back from the configurations screens that will determine how many months the job will look back 
				and store the data historically in the FP_WEEKLY_SUPPLIER_WHS_Margin_Loss

++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Log Update:
	11/05/19	JAleman		Added @Report_Date parameter so in case the job failed the sp can be executed with a date
    05/26/20	JAleman		Use the [dbo].[PALLET_HANDLING_RATE] table to get the direct PO =[BACKHAUL_RATE]
							and Crossdock = [CROSS_DOCK_RATE]
	04/08/21	JAleman		exclude Side Stream POs from this job as part of the SS freight pricing project
	07/12/2022  CM				Filter on SOURCE_SYSTEM, wrap in try/catch
 ================================================================================================================================*/
ALTER PROCEDURE [dbo].[SP_FP_JOB_FILL_FP_WEEKLY_SUPPLIER_WHS_MARGIN_LOSS]
(
	@Report_Date as DATE = NULL
)
AS
BEGIN
	SET NOCOUNT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
/**********************************************************************
Example 1:	
		EXEC dbo.SP_FP_JOB_FILL_FP_WEEKLY_SUPPLIER_WHS_MARGIN_LOSS
***********************************************************************/
--Variable declarations
	DECLARE	@MARGIN_LOSS_REPORT_MONTHS_BACK INT
		,	@StartDate DATE
		,	@EndDate DATE
		,	@Today DATE
		,   @system VARCHAR(50)

	--Set @today base on the Parameter
	IF (@Report_Date IS NULL )
	BEGIN
		SET @Today = GETDATE()
	END
	ELSE 
	BEGIN
		SET @Today = @Report_Date
	END
	
BEGIN TRY  
		
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

	--if there is an entry for the same day, we delete those records and process again
	IF EXISTS (SELECT TOP 1 1 FROM FP_WEEKLY_SUPPLIER_WHS_MARGIN_LOSS WHERE REPORT_DATE = @Today)
		DELETE FROM FP_WEEKLY_SUPPLIER_WHS_MARGIN_LOSS
		WHERE REPORT_DATE = @Today


	DECLARE @source_system VARCHAR(50)  -- cursor through all source systems

	DECLARE source_systems_cursor CURSOR FOR    
	SELECT DISTINCT SOURCE_SYSTEM 
	FROM LO_PURCHASE_ORDERS 
	OPEN source_systems_cursor  
	FETCH NEXT FROM source_systems_cursor INTO @source_system 

		WHILE @@FETCH_STATUS = 0  
		BEGIN  
			--Get the value of the number of months that job will go back from the config default table
			SET @MARGIN_LOSS_REPORT_MONTHS_BACK = COALESCE ( (SELECT MARGIN_LOSS_REPORT_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = @source_system) , 
															(SELECT MARGIN_LOSS_REPORT_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = 'DEFAULT')	)
				
			SET @StartDate =  DATEADD(MONTH,-@MARGIN_LOSS_REPORT_MONTHS_BACK, @Today) 
			SET @EndDate = @Today
			SET @system = @source_system

			PRINT @StartDate
			PRINT @EndDate
			
			--To get the POs that are NOT full Billed 
			INSERT 
			INTO #NOTFULLYBILLED 
			SELECT *
			FROM dbo.fnGetPO_NOTFULLYBILLED(@StartDate, @EndDate, 1, @system)

			FETCH NEXT FROM source_systems_cursor INTO @source_system  
		END 

	CLOSE source_systems_cursor  
	DEALLOCATE source_systems_cursor 

	
	CREATE CLUSTERED INDEX #NFBIDX ON #NOTFULLYBILLED (LO_PURCHASE_ORDER_ID)	
	
	
	DECLARE source_systems_cursor CURSOR FOR    
	SELECT DISTINCT SOURCE_SYSTEM 
	FROM LO_PURCHASE_ORDERS 
	OPEN source_systems_cursor  
	FETCH NEXT FROM source_systems_cursor INTO @source_system 
		WHILE @@FETCH_STATUS = 0  
		BEGIN  
		
			SET @MARGIN_LOSS_REPORT_MONTHS_BACK = COALESCE ( (SELECT MARGIN_LOSS_REPORT_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = @source_system) , 
															(SELECT MARGIN_LOSS_REPORT_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = 'DEFAULT')	)
				
			SET @StartDate =  DATEADD(MONTH,-@MARGIN_LOSS_REPORT_MONTHS_BACK, @Today) 
			SET @EndDate = @Today
			SET @system = @source_system
			--Get all the RCV POs with FPA calculation even when this calculation apply only to Backhaul
			--that are fully billed
			INSERT
			INTO #PO_LIST
			SELECT * 
			FROM [dbo].[fnGetPOSWithCalculatePalletsFPA](@StartDate, @EndDate, 1, @system)
			WHERE LO_PURCHASE_ORDER_ID NOT IN (SELECT LO_PURCHASE_ORDER_ID FROM #NOTFULLYBILLED) --Lead out POs that are not fully billed
	
			FETCH NEXT FROM source_systems_cursor INTO @source_system  
		END 

	CLOSE source_systems_cursor  
	DEALLOCATE source_systems_cursor 

	CREATE CLUSTERED INDEX #IDX_PO_LIST ON #PO_LIST(LO_PURCHASE_ORDER_ID)
	
	
	DECLARE source_systems_cursor CURSOR FOR    
	SELECT DISTINCT SOURCE_SYSTEM 
	FROM LO_PURCHASE_ORDERS 
	OPEN source_systems_cursor  
	FETCH NEXT FROM source_systems_cursor INTO @source_system 
		WHILE @@FETCH_STATUS = 0  
		BEGIN  
		
			SET @MARGIN_LOSS_REPORT_MONTHS_BACK = COALESCE ( (SELECT MARGIN_LOSS_REPORT_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = @source_system) , 
															(SELECT MARGIN_LOSS_REPORT_MONTHS_BACK FROM FP_DEFAULT_CONFIG WHERE SOURCE_SYSTEM = 'DEFAULT')	)
				
			SET @StartDate =  DATEADD(MONTH,-@MARGIN_LOSS_REPORT_MONTHS_BACK, @Today) 
			SET @EndDate = @Today
			SET @system = @source_system

			--To get the Suppliers PO expenses for all the RCV POs
			INSERT
			INTO #PO_FREIGHT
			SELECT LO_PURCHASE_ORDER_ID, SUM(cast(ISNULL(FREIGHT_PAID_PO,0) as decimal(10,3))) AS FREIGHT_PAID_PO
			FROM  dbo.fnGetSuppliersPOExpenses(@StartDate, @EndDate, 1, @system)
			WHERE LO_PURCHASE_ORDER_ID IN (SELECT LO_PURCHASE_ORDER_ID FROM #PO_LIST) 
			GROUP BY LO_PURCHASE_ORDER_ID
			
			FETCH NEXT FROM source_systems_cursor INTO @source_system  
		END 

	CLOSE source_systems_cursor  
	DEALLOCATE source_systems_cursor 

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
	,   ISNULL(lpo.PO_Dollar_Value,0) AS PO_Dollar_Value
	,	CAST(lpo.REC_DATE AS DATE) AS REC_DATE
	,	lpo.SOURCE_SYSTEM
	INTO #POS
	FROM #PO_LIST PO
		INNER JOIN LO_PURCHASE_ORDERS lpo
			ON PO.LO_PURCHASE_ORDER_ID = lpo.LO_PURCHASE_ORDER_ID
				AND (lpo.ORDER_TYPE_ID IS NULL OR lpo.ORDER_TYPE_ID <> 1)
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
										THEN MAX_26PALLETS_FINAL_CALC * phr.[BACKHAUL_RATE]
										ELSE MAX_26PALLETS_FINAL_CALC * phr.[CROSS_DOCK_RATE]									 
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
	
	INSERT INTO FP_WEEKLY_SUPPLIER_WHS_MARGIN_LOSS
	SELECT TMS_VENDOR_ID
		, COUNT(DISTINCT LO_PURCHASE_ORDER_ID) as PO_COUNT
		, CAST(SUM(TOTAL_UNITS) as decimal(18,3)) AS TOTAL_UNITS
		, CAST(SUM(TOTAL_WEIGHT) as decimal(18,3)) AS TOTAL_WEIGHT
		, CAST(SUM(TOTAL_CUBES) as decimal(18,3)) AS TOTAL_CUBES
		, CAST(SUM(TOTAL_PALLETS) as decimal(18,3)) AS TOTAL_PALLETS
		, CAST(SUM(PO_Dollar_Value) as decimal(18,3)) AS  TOTAL_PO_DOLLAR_VALUE
		, CAST(SUM(TOTAL_EXPENSE) as decimal(18,3)) AS TOTAL_EXPENSE	
		, CAST(SUM(REVENUE) as decimal(18,3)) AS TOTAL_REVENUE
		, CAST(SUM(REVENUE) - SUM(TOTAL_EXPENSE) as decimal(18,3)) AS TOTAL_MARGIN
		, CAST(SUM(PROD_FRT) as decimal(18,3)) AS TOTAL_FREIGHT
		, CAST(SUM(ALLOWANCE) as decimal(18,3)) AS TOTAL_ALLOWANCE
		, CAST(AVG(TOTAL_EXPENSE)/NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_EXPENSE_PER_LB
		, CAST(AVG(REVENUE) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_REVENUE_PER_LB
		, CAST(AVG(PROD_FRT) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_FREIGHT_PER_LB
		, CAST(AVG(ALLOWANCE) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_ALLOWANCE_PER_LB
		, CAST((AVG(REVENUE) - AVG(TOTAL_EXPENSE)) / NULLIF(AVG(TOTAL_WEIGHT),0) as decimal(18,6)) AS AVG_MARGIN_PER_LB
		, @MARGIN_LOSS_REPORT_MONTHS_BACK AS MARGIN_LOSS_REPORT_MONTHS_BACK
		, @Today as REPORT_DATE
	FROM #POS
	GROUP BY TMS_VENDOR_ID

	DROP TABLE #POS
	DROP TABLE #PO_LIST
	DROP TABLE #NOTFULLYBILLED
	DROP TABLE #PO_FREIGHT
	
END TRY      
BEGIN CATCH      
INSERT INTO [dbo].[DB_Errors]      
 VALUES (NEWID(), SUSER_SNAME(), ERROR_NUMBER(), ERROR_STATE(), ERROR_SEVERITY(), ERROR_LINE(), ERROR_PROCEDURE(), ERROR_MESSAGE(), GETDATE());      
END CATCH

END


GO


