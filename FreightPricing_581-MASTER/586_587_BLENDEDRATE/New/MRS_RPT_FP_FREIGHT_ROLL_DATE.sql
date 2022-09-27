USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[MRS_RPT_FP_FREIGHT_ROLL_DATE]    Script Date: 9/27/2022 10:48:50 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ====================================================================================================
 Author:		Johana Aleman
 Create date:	05/21/2019
 Description:	FREIGHT PRICING RELEASE II – Freight Pricing Roll Date Report
 Update Log:
	062619	Johana Aleman	fix the Pickup_date base on the function used in the front-end application
	091019  Johana Aleman	Added Surce System Parameter to the report since for each source system will  
						    have an effective.
	102819  Johana Aleman   Need to add the following columns to the Freight Pricing Roll Date Report:
							- Submitted Allowance Type   (from the FORM table)
							- Submitted Allowance Rate (if its off invoice, it should be a % else its $$.$$$)   
							  (from the Form Vendor table, OFFERED_PICKUP_ALLOWANCE) IN:2428
-- ====================================================================================================*/
ALTER PROCEDURE [dbo].[MRS_RPT_FP_FREIGHT_ROLL_DATE]
(
	 @StartDate DATE
	, @EndDate DATE
	, @SOURCE_SYSTEM VARCHAR(8000)
)
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/***************************************************************************************************************
Execution Example:
	EXECUTE MRS_RPT_FP_FREIGHT_ROLL_DATE '01/01/2018', '07/27/2019', NULL
****************************************************************************************************************/

		SELECT DISTINCT fff.FP_FREIGHT_FORM_ID, tv.VENDOR_NUMBER as SUPPLIER_NUMBER
			, COALESCE(fff.SUPPLIER_NAME, tv.NAME) as SUPPLIER_NAME
			, WHS.NAME as WAREHOUSE
			, CASE WHEN fff.TMS_STATUS_ID = 66 THEN fff.SUBMIT_DATE END SUBMIT_DATE_COMPLETED_STATUS
			, CASE WHEN WHS.SOURCE_SYSTEM = 'UBS' THEN CAST(fff.EAST_BLENDED_FREIGHT_RATE AS DECIMAL(18,3)) 
					WHEN WHS.TMS_WHS_ID IN (1, 114) THEN CAST(fff.GILROC_BLENDED_FREIGHT_RATE AS DECIMAL(18,3))
			   ELSE 
					 CAST(fffV.PROPOSED_FREIGHT_PER_LB AS DECIMAL(18,3)) 
			 END AS SUBMITTED_RATE_PER_LB
			, fffv.EFFECTIVE_DATE as ROLL_DATE
			, loc.D_RTE
			, CASE loc.PICKUP_DAY WHEN 0 THEN 'Monday'
								  WHEN 1 THEN 'Tuesday'
								  WHEN 2 THEN 'Wednesday'
								  WHEN 3 THEN 'Thursday'
								  WHEN 4 THEN 'Friday'
								  WHEN 5 THEN 'Saturday'
								  WHEN 6 THEN 'Sunday' END AS PICKUP_DAY
			, ffat.FP_FF_ALLOWANCE_TYPE_ID			
			, ffat.DESCRIPTION
			, fffv.OFFERED_PICKUP_ALLOWANCE
		FROM FP_FREIGHT_FORM fff
			LEFT JOIN FP_FREIGHT_FORM_VENDOR fffv
				ON fff.FP_FREIGHT_FORM_ID = fffv.FP_FREIGHT_FORM_ID
					AND (FFFV.IS_DELETED = 0 OR FFFV.IS_DELETED IS NULL)
			LEFT JOIN TMS_WHS WHS
				ON WHS.TMS_WHS_ID = fffv.TMS_WHS_ID
			LEFT JOIN TMS_VENDOR tv
				ON tv.TMS_VENDOR_ID = fffv.TMS_VENDOR_ID
					AND (tv.IS_DELETED IS NULL OR tv.IS_DELETED = 0)
			LEFT JOIN dbo.FP_FF_PICKUP_LOCATIONS loc
				ON fffv.FP_FF_PICKUP_LOCATIONS_ID = loc.FP_FF_PICKUP_LOCATIONS_ID
					AND fffv.FP_FREIGHT_FORM_ID = loc.FP_FREIGHT_FORM_ID
					AND (loc.IS_DELETED = 0 OR loc.IS_DELETED IS NULL)
			LEFT JOIN FP_FF_ALLOWANCE_TYPE ffat
				ON fff.FP_FF_ALLOWANCE_TYPE_ID = ffat.FP_FF_ALLOWANCE_TYPE_ID 
					AND (ffat.IS_DELETED = 0 OR ffat.IS_DELETED IS NULL)
		WHERE CAST(fffv.EFFECTIVE_DATE AS DATE) BETWEEN @StartDate AND @EndDate
			AND (@SOURCE_SYSTEM IS NULL OR (WHS.SOURCE_SYSTEM IN (SELECT c FROM dbo.fnParseStack(@SOURCE_SYSTEM,'c'))))

END
GO


