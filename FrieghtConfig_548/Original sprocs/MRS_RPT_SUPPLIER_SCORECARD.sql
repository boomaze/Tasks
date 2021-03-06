USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[MRS_RPT_SUPPLIER_SCORECARD]    Script Date: 7/12/2022 1:37:43 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ====================================================================================================
Author:			Johana Aleman
Create date:	03/07/2016
Description:    Develop Dashboard Report to measure Supplier Performance for UNFI complete with 
				Summary and Details tab for verification and backup data	
			
Arguments:		@StarDate DATE,
				@EndDate DATE,
				@LawsonNumber VARCHAR(MAX), --Valor by defaulf is 'ALL'
				@VendorNumber VARCHAR(MAX), --Valor by defaulf is 'ALL'
				@UNFI_DC VARCHAR(MAX) = NULL –This contains an specific TMS_WHS_ID 	
Update Log:
	20171206	Johana Aleman 	Add column to specify if PO was ver in PEND/PND status in the LO_PO_LOG TABLE
	20180521	Johana Aleman   Renamed Procedure from SP_RPT_SUPPLIER_SCORED_CARD to MRS_RPT_SUPPLIER_SCORECARD
	20190329	Johana Aleman   Fixed issue of ambiguity with LPO DRTE and Vendor DRTE (Added as part of Freight Pricing Project
	20200121					Modified logic to utilize the IS_TRANSFER_VENDOR field 
									in the [dbo].[TMS_VENDOR] table when selecting 
									Transfer Vendors.

									Old SQL Code:
												tv.NAME NOT LIKE '%TRANSFER%'

									New SQL Code:
												tv.IS_TRANSFER_VENDOR <> 1
	20200401		BK				Old SQL Code:
												tv.IS_TRANSFER_VENDOR <> 1
									New SQL Code:
												tv.IS_TRANSFER_VENDOR IS NULL OR tv.IS_TRANSFER_VENDOR = 0
	05222020		JA		Use the [dbo].[PALLET_HANDLING_RATE] table to get the Direct =[BACKHAUL_RATE]
							and MRS_RPT_SUPPLIER_SCORECARD 
# =====================================================================================================*/
ALTER PROCEDURE [dbo].[MRS_RPT_SUPPLIER_SCORECARD]
( 
	 @StartDate DATE --= '2015-12-06'
	 ,@EndDate DATE --= '2016-01-02'
	 ,@LawsonNumber VARCHAR(MAX) = 'ALL'
	 ,@VendorNumber VARCHAR(MAX) = 'ALL'
	 ,@UNFI_DC VARCHAR(2000) = NULL
	 ,@BuyerList VARCHAR(MAX) = NULL
) 
AS
BEGIN
	SET NOCOUNT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
/*************************************************************************************************
Example 1
	EXEC dbo.MRS_RPT_SUPPLIER_SCORECARD '2015-12-06', '2016-01-02', 11189,NULL,NULL
**************************************************************************************************/
		--Returns a table with all the PO that are no fully billed. 
		SELECT * INTO #NOTFULLYBILLED FROM dbo.fnGetPO_NOTFULLYBILLED(@StartDate, @EndDate)
		CREATE INDEX #NFBIDX ON #NOTFULLYBILLED (PO_NUMBER)	
		create INDEX #NFB_POIDX ON #NOTFULLYBILLED (LO_PURCHASE_ORDER_ID)
		
		SELECT LO_PURCHASE_ORDER_ID, PO_NUMBER, CAST(SUM(ISNULL(FREIGHT_PAID_PO,0)) AS DECIMAL(10,3)) AS FREIGHT_PAID_PO,  CAST(NULL AS VARCHAR(25)) AS BILL_STATUS
		INTO #TOTALS FROM [dbo].[fnGetSuppliersPOExpenses](@StartDate,@EndDate)GROUP BY LO_PURCHASE_ORDER_ID, PO_NUMBER
		CREATE INDEX #TOTALSIDX ON #TOTALS (PO_NUMBER)
		CREATE INDEX #TOTALS_POIDX ON #TOTALS (LO_PURCHASE_ORDER_ID) 


		UPDATE #TOTALS
		SET
			BILL_STATUS = 'Not Fully Billed'
		FROM 
			#TOTALS t 
			INNER JOIN #NOTFULLYBILLED nfb 
			ON nfb.LO_PURCHASE_ORDER_ID = t.LO_PURCHASE_ORDER_ID
					

		SELECT DISTINCT 
			tv.REMIT_VENDOR AS REMIT_VENDOR_NUMBER
			,CAST(NULL AS VARCHAR(255)) AS REMIT_VENDOR_NAME
			,tv.VENDOR_NUMBER 
			,tv.NAME AS VENDOR_NAME
			,lpo.DIS_WHS_ID
			,PODEST.NAME AS PO_DESTINATION
			,lpo.D_RTE AS ROUTE_CODE			
			,CASE 
				WHEN lpl.LO_PO_LOADS_ID IS NULL
					THEN 'VSP'
				ELSE 'COLLECT'
			 END AS PO_TYPE
			,lpo.ORIGINAL_ETA_DATE
			,app.APPOINTMENT_DATE
			,app.DATETIMELANDED
			,apos.APP_APPOINTMENT_ID
			,APPDEST.NAME AS APPT_DESTINATION_WHS
			,(
				CASE 
					WHEN DATEDIFF(DAY,CAST(lpo.ORIGINAL_ETA_DATE AS DATE),CAST(app.DATETIMELANDED AS DATE)) > 0
						THEN 'LATE'
					ELSE 'ON TIME'
				END) AS LANDED
			,(
				CASE 
					WHEN DATEDIFF(MINUTE,app.APPOINTMENT_DATE, app.DATETIMELANDED) <=30 OR app.DATETIMELANDED <= app.APPOINTMENT_DATE
						THEN 'ON TIME'
					ELSE 'LATE' 
			 END) AS APPOINTMENT_STATUS
			 ,
				CASE 
					WHEN DATEDIFF(DAY, CAST(COALESCE(app.CALCULATED_ETA, lpo.EXPECT_DATE) AS DATE), CAST(app.DATETIMELANDED AS DATE)) > 0 
						THEN 'LATE' 
					ELSE 'ON TIME' 
				END AS LANDED_VS_NEEDBY
			,lpo.PO_NUMBER
			,lpo.TOTAL_UNITS AS TOTAL_UNITS_RCV
			,(
				CASE
					WHEN lpo.FRZ_UNITS > 0
					THEN 'F'
					WHEN lpo.CHL_UNITS > 0
					THEN 'C'
					WHEN lpo.RPK_UNITS > 0
					THEN 'D'
					ELSE 'D'
				END) AS PROTECTION_LEVEL
			,COALESCE(tvf.ADDRESS1, tv.ADDRESS1) AS PICKUP_ADDRESS
			,COALESCE(tvf.CITY, tv.CITY) AS PICKUP_CITY
			,COALESCE(tvf.STATE, tv.STATE) AS PICKUP_STATE
			,COALESCE(tvf.ZIP, tv.ZIP) AS ZIP
			,lpo.TOTAL_WEIGHT AS TOTAL_PO_RECEIVED_LBS
			,ISNULL(lpo.PROD_FRT,0)  AS PO_REVENUE
			 ,CASE
				WHEN t.BILL_STATUS IS NULL 
					THEN t.FREIGHT_PAID_PO 
				ELSE 0.0
			 END AS PO_EXPENSE
			,lpo.SOURCE_SYSTEM
			,lpo.LO_PURCHASE_ORDER_ID
			,LPO.PO_Dollar_Value
			--,CAST(NULL AS DECIMAL(10,3)) AS TOTAL_PO_EAST
			--,CAST(NULL AS DECIMAL(10,3)) AS TOTAL_PO_NATIONAL
			,t.BILL_STATUS
			,CAST(CASE WHEN	t.BILL_STATUS IS NULL 
					THEN SUM(CASE WHEN ll.CR_CARRIER_ID = 78 AND CEILING(TOTAL_PALLETS) > 0 AND ll.SOURCE_WHS_ID IS NULL
									THEN CASE
											WHEN lpo.DIS_WHS_ID = ll.DESTINATION_WHS_ID 
												THEN CEILING(lpo.TOTAL_PALLETS) * [BACKHAUL_RATE]
										  ELSE CEILING(lpo.TOTAL_PALLETS) * [CROSS_DOCK_RATE]
									END
			  END) OVER (PARTITION BY lpo.LO_PURCHASE_ORDER_ID) 
			  END as decimal(10,3)) AS BACKHAUL_EXPENSE_PO
			,CASE WHEN COUNT(CASE WHEN ll.CR_CARRIER_ID = 78 AND ll.SOURCE_WHS_ID IS NULL THEN 1 END) OVER (PARTITION BY lpo.LO_PURCHASE_ORDER_ID) > 0 THEN 'YES'  ELSE 'NO' END  AS BACKHAUL_INDICATOR
		,CEILING(lpo.TOTAL_PALLETS) AS TOTAL_PALLETS_RCV
		,CAST(COALESCE(app.CALCULATED_ETA, lpo.EXPECT_DATE) AS DATE) as NEED_BY_DATE
		,tb.NAME AS BUYER_NAME
		,CAST(NULL AS INT ) AS HAS_BEEN_IN_PEND_STATUS
		INTO #POS
		FROM LO_PURCHASE_ORDERS lpo 
			left JOIN #TOTALS t 
				ON  t.LO_PURCHASE_ORDER_ID = lpo.LO_PURCHASE_ORDER_ID 
					AND t.PO_NUMBER = lpo.PO_NUMBER 			
			LEFT JOIN LO_PO_LOADS lpl 
				ON lpo.LO_PURCHASE_ORDER_ID = lpl.LO_PURCHASE_ORDER_ID
					and (lpl.IS_DELETED IS NULL OR lpl.IS_DELETED = 0)
			LEFT JOIN LO_LOADS ll 
				ON ll.LO_LOAD_NUMBER = lpl.LO_LOAD_NUMBER
			INNER JOIN APP_APPOINTMENT_POS apos  
				ON 	lpo.LO_PURCHASE_ORDER_ID = apos.LO_PURCHASE_ORDER_ID 
					AND (apos.IS_DELETED IS NULL or apos.IS_DELETED = 0) --
			INNER JOIN APP_APPOINTMENTS app
				ON app.APP_APPOINTMENT_ID = apos.APP_APPOINTMENT_ID
					AND app.TMS_WHS_ID = lpo.DIS_WHS_ID
					AND app.APPOINTMENT_STATUS NOT IN (14,15)
			INNER JOIN TMS_WHS APPDEST 
				ON app.TMS_WHS_ID = APPDEST.TMS_WHS_ID 
			LEFT JOIN TMS_WHS SOURCE_WHS 
				ON ll.SOURCE_WHS_ID = SOURCE_WHS.TMS_WHS_ID
			INNER JOIN TMS_WHS PODEST 
				ON lpo.DIS_WHS_ID = PODEST.TMS_WHS_ID
			LEFT JOIN TMS_VENDOR tv 
				ON tv.TMS_VENDOR_ID = lpo.TMS_VENDOR_ID
			LEFT JOIN TMS_VENDOR_FACILITY tvf 
				ON lpo.TMS_VENDOR_FACILITY_ID = tvf.TMS_VENDOR_FACILITY_ID
			LEFT JOIN TMS_BUYER tb 
				ON tb.TMS_BUYER_ID = lpo.TMS_BUYER
			LEFT JOIN tblUNFIfiscalCalendar uc
				ON CAST(lpo.REC_DATE AS DATE) BETWEEN uc.WeekStart AND uc.WeekEnd
			LEFT JOIN dbo.PALLET_HANDLING_RATE phr
				ON	uc.FiscalYear = phr.[FISCAL_YEAR]
				AND PODEST.SOURCE_SYSTEM = phr.SOURCE_SYSTEM
		WHERE (CAST(lpo.REC_DATE AS DATE) BETWEEN @StartDate AND @EndDate)
			AND lpo.TMS_STATUS_ID = 9
			AND ((@LawsonNumber IS NULL OR @LawsonNumber = 'ALL') OR tv.REMIT_VENDOR IN (SELECT I FROM dbo.fnParseStack(@LawsonNumber, 'I'))) 
			AND ((@VendorNumber IS NULL OR @VendorNumber = 'ALL') OR tv.VENDOR_NUMBER IN (SELECT C FROM dbo.fnParseStack(@VendorNumber,'C')))
			AND (@UNFI_DC IS NULL OR PODEST.TMS_WHS_ID IN (SELECT RTRIM(LTRIM(i)) FROM dbo.fnSplitStringCTE(@UNFI_DC, ',')))
			AND (@BuyerList IS NULL OR lpo.TMS_BUYER IN (SELECT i FROM dbo.fnParseStack(@BuyerList, 'I')))
			AND (tv.IS_TRANSFER_VENDOR IS NULL OR tv.IS_TRANSFER_VENDOR = 0)

			CREATE CLUSTERED INDEX #IDXLPO ON #POS(LO_PURCHASE_ORDER_ID)
			CREATE INDEX #IDX_PO ON #POS(PO_NUMBER) 
			CREATE INDEX #IDX_REMITVENDOR ON #POS(REMIT_VENDOR_NUMBER)

			UPDATE #POS
			SET HAS_BEEN_IN_PEND_STATUS = 1 
			FROM #POS p
				INNER JOIN LO_PO_LOG llog
					ON p.LO_PURCHASE_ORDER_ID = llog.LO_PURCHASE_ORDER_ID
			WHERE llog.D_RTE IN ('PEND', 'PND')


			--UPDATE #POS
			--SET TOTAL_PO_NATIONAL = POH_R_W.TOTAL
			--FROM #POS p
			--	LEFT JOIN NDM.National_Datamart.dbo.tbl_MPW_POHeader POH_R_W 
			--		ON p.PO_NUMBER = LEFT(POH_R_W.PONumber, 9)
			--			AND p.SOURCE_SYSTEM = 'WBS'
			--			AND POH_R_W.Form = 17
				

			--UPDATE #POS
			--SET TOTAL_PO_EAST = POH_R_E.POTotalAmount
			--FROM #POS p
			--LEFT JOIN EDM.East_Datamart.dbo.tblReceivedPOheader POH_R_E 
			--	ON p.PO_NUMBER = POH_R_E.PONumber
			--		AND p.SOURCE_SYSTEM = 'UBS'

			UPDATE #POS
			SET 
				REMIT_VENDOR_NAME = v.[VENDOR_VNAME]
			FROM 
				#POS p
				INNER JOIN [NDM].[Lawson_PROD].[dbo].[APVENMAST] v 
				ON p.REMIT_VENDOR_NUMBER = v.[VENDOR]
				
			
		SELECT DISTINCT
			pol.PO_NUMBER
			,pol.TOTAL_UNITS
			,pol.TOTAL_WEIGHT
			,RANK() OVER (PARTITION BY pol.PO_NUMBER ORDER BY pol.PurchaseOrderLogID DESC) AS RNK
			,RANK() OVER (PARTITION BY pol.PO_NUMBER ORDER BY  pol.PurchaseOrderLogID ) AS RNK_ORIGINAL
		INTO #LOGDATA
		FROM 
			TMS_INTEG_LOG.dbo.PurchaseOrdersLog pol 
			INNER JOIN #POS 
			ON #POS.PO_NUMBER = pol.PO_NUMBER 
		WHERE 
			ISDATE(REQUEST_DATE) = 1
			AND ISDATE(EXPECT_DATE) = 1
			AND pol.TOTAL_UNITS > 0
			AND POL.STATUS NOT IN ('RCV','DEL')

		CREATE INDEX #IDX_LOGDATA ON #LOGDATA(PO_NUMBER)
		
			
		SELECT DISTINCT 
			REMIT_VENDOR_NUMBER
			,REMIT_VENDOR_NAME
			,VENDOR_NUMBER 
			,VENDOR_NAME
			,PO_DESTINATION
			,ROUTE_CODE			
			,PO_TYPE
			,ORIGINAL_ETA_DATE
			,APPOINTMENT_DATE
			,DATETIMELANDED
			,APP_APPOINTMENT_ID
			,APPT_DESTINATION_WHS
			,LANDED
			,APPOINTMENT_STATUS
			,#POS.PO_NUMBER
			,ld.TOTAL_UNITS AS TOTAL_UNITS_ORDERED
			,ld1.TOTAL_UNITS AS TOTAL_UNITS_ORIGINAL
			,TOTAL_UNITS_RCV
			,PROTECTION_LEVEL
			,PICKUP_ADDRESS
			,PICKUP_CITY
			,PICKUP_STATE
			,ZIP
			,TOTAL_PO_RECEIVED_LBS
			,isnull(PO_REVENUE,0) as PO_REVENUE
			,PO_EXPENSE 
			,ISNULL(BACKHAUL_EXPENSE_PO,0) AS BACKHAUL_EXPENSE_PO
			,CASE WHEN BILL_STATUS IS NULL THEN PO_EXPENSE+ISNULL(BACKHAUL_EXPENSE_PO,0) END AS PO_INBOUND_EXPENSE
			,BACKHAUL_INDICATOR
			,CASE WHEN BILL_STATUS IS NULL THEN PO_REVENUE - (PO_EXPENSE+ISNULL(BACKHAUL_EXPENSE_PO,0)) ELSE 0 END AS MARGIN_PO
			,cast(CASE WHEN BILL_STATUS IS NULL 	AND PO_EXPENSE+ISNULL(BACKHAUL_EXPENSE_PO,0) <> 0				
				THEN ISNULL((PO_REVENUE - (PO_EXPENSE+ISNULL(BACKHAUL_EXPENSE_PO,0))) / NULLIF(PO_REVENUE,0),0) 
				ELSE  PO_REVENUE
			 END as decimal(20,6)) AS MARGIN_PO_PCT
			,BILL_STATUS
			,PO_Dollar_Value AS TOTAL_PO
			,TOTAL_PALLETS_RCV
			,LANDED_VS_NEEDBY
			,NEED_BY_DATE
			,BUYER_NAME
			,HAS_BEEN_IN_PEND_STATUS
		FROM #POS 
			INNER JOIN #LOGDATA ld 
				ON #POS.PO_NUMBER = ld.PO_NUMBER
					AND ld.RNK = 1
			INNER JOIN #LOGDATA ld1 
				ON #POS.PO_NUMBER = ld1.PO_NUMBER
					AND ld1.RNK_ORIGINAL = 1 	
					AND #POS.REMIT_VENDOR_NUMBER IS NOT NULL AND LEN(LTRIM(RTRIM(#POS.REMIT_VENDOR_NUMBER))) > 0 AND #POS.REMIT_VENDOR_NUMBER > 0
		

	DECLARE @d_sql NVARCHAR(MAX)
    	
	SET @d_sql = ''

	SELECT @d_sql = @d_sql + 'DROP TABLE ' + QUOTENAME(name) + ';'
    FROM tempdb..sysobjects 
    WHERE name like '#[^#]%'
		AND OBJECT_ID('tempdb..'+QUOTENAME(name)) IS NOT NULL
        
    IF @d_sql <> ''
    BEGIN
	    EXEC( @d_sql )
    END	

END

GO


