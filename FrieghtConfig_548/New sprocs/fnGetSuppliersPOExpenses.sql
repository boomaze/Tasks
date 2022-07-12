USE [TMS]
GO

/****** Object:  UserDefinedFunction [dbo].[fnGetSuppliersPOExpenses]    Script Date: 7/11/2022 12:55:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<Johana Aleman>
-- Create date: <04/03/2016>
-- Description:	<Returns a table with all the PO calculation expenses between the start and end date (LO_PURCHASE_ORDERS.REC_DATE) >

--  7/11/2022	CM	       added source system filter
-- =============================================
ALTER FUNCTION [dbo].[fnGetSuppliersPOExpenses] 
(	
	@StartDate DATE
,	@EndDate DATE
,   @FilterBySourceSystem BIT --SET to apply filter, if false filter is ignored
,   @SourceSystem VARCHAR(50)
)
RETURNS TABLE 
AS
RETURN 
(
		SELECT DISTINCT
		CASE
			WHEN SUM(lpo.TOTAL_WEIGHT) OVER (PARTITION BY bb.BL_BILLING_ID) > 0
			THEN (lpo.TOTAL_WEIGHT / SUM(lpo.TOTAL_WEIGHT) OVER (PARTITION BY bb.BL_BILLING_ID)) * bb.INVOICE_AMOUNT
			ELSE NULL
		END AS FREIGHT_PAID_PO
	,	lpo.LO_PURCHASE_ORDER_ID
	,	bbp.LO_LOAD_NUMBER
	,	bb.BL_BILLING_ID
	,	lpo.PO_NUMBER
	FROM LO_PURCHASE_ORDERS lpo WITH(NOLOCK)
		
		INNER JOIN dbo.BL_BILL_POS bbp WITH(NOLOCK)
				ON bbp.LO_PURCHASE_ORDER_ID = lpo.LO_PURCHASE_ORDER_ID
					AND ISNULL(bbp.IS_DELETED, 0) = 0
		INNER JOIN dbo.BL_BILLING bb WITH(NOLOCK)
				ON bb.BL_BILLING_ID = bbp.BL_BILLING_ID
				AND bb.CR_CARRIER_ID NOT IN (78, 1680, 2629, 69, 2616, 3122)
	WHERE
		bb.BL_BILLING_ID IN (SELECT bbp.BL_BILLING_ID
			FROM LO_PURCHASE_ORDERS lpo WITH(NOLOCK)
				INNER JOIN BL_BILL_POS bbp WITH(NOLOCK)
						ON lpo.LO_PURCHASE_ORDER_ID = bbp.LO_PURCHASE_ORDER_ID
							AND ISNULL(bbp.IS_DELETED, 0) = 0
			WHERE CAST(lpo.REC_DATE AS DATE) BETWEEN @StartDate AND @EndDate)
			AND lpo.TMS_STATUS_ID != 8
			AND lpo.SOURCE_SYSTEM =
			CASE WHEN @FilterBySourceSystem = 1 
				THEN
				 @SourceSystem
				ELSE
				 lpo.SOURCE_SYSTEM
			END
)
GO


