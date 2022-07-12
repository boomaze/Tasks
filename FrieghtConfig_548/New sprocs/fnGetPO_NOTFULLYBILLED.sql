USE [TMS]
GO

/****** Object:  UserDefinedFunction [dbo].[fnGetPO_NOTFULLYBILLED]    Script Date: 7/11/2022 12:50:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* =================================================================
 Author:	  Johana Aleman
 Create date: 03/07/2016
 Description: Returns a dataset with the PO_NUMBER, LO_PURCHASE_ORDER_ID  
			  AND LO_LOAD_NUMBER that has not been Fully Billed
 Modification Log:
  10/26/2018  JAleman  Change the logic to make the function dynamic
					   if the Load Carrier <> Bill POs Carrier then
					   the Load/PO is not fully Billed.

  10/4/2019	  		   Modified Where clause to filter out shuttle
                       carries by CARRIER_ID.

  12/11/2019		   Modified Where clause to filter out any PO 
					   that is on a load where the Carrier has 
					   CR_CARRIERS.SHUTTLE_CARRIER = 1. 
					   
  12/30/2019		   Modified Where clause to filter out the carriers
					   who are shuttle carriers 
					   CR_CARRIERS.SHUTTLE_CARRIER <> 1. 
					   CR_CARRIERS.SHUTTLE_CARRIER = 1 was limiting the
					   recordset to only shuttle carriers not filtering
					   them out.					   	
  7/11/2022	  CM       added source system filter
			   	
 =================================================================*/
ALTER FUNCTION [dbo].[fnGetPO_NOTFULLYBILLED]
(
	@StartDate DATE
,	@EndDate DATE
,   @FilterBySourceSystem BIT --SET to apply filter, if false filter is ignored
,   @SourceSystem VARCHAR(50)
) RETURNS TABLE
AS
RETURN
(
	SELECT POS.PO_NUMBER,
		POS.LO_PURCHASE_ORDER_ID,
		LPOS.LO_LOAD_NUMBER
	FROM LO_PURCHASE_ORDERS POS 
		INNER JOIN LO_PO_LOADS LPOS 
			ON POS.LO_PURCHASE_ORDER_ID = LPOS.LO_PURCHASE_ORDER_ID
				AND (LPOS.IS_DELETED IS NULL OR LPOS.IS_DELETED = 0)
		INNER JOIN LO_LOADS LDS 
			ON LPOS.LO_LOAD_NUMBER = LDS.LO_LOAD_NUMBER
				AND LDS.TMS_STATUS_ID NOT IN (32)
		LEFT JOIN (SELECT BPOS.LO_PURCHASE_ORDER_ID, bb.BL_BILLING_ID
						, BPOS.LO_LOAD_NUMBER, bb.CR_CARRIER_ID
					FROM BL_BILL_POS BPOS 
						INNER JOIN BL_BILLING bb 
							ON BPOS.BL_BILLING_ID = bb.BL_BILLING_ID
								AND (BPOS.IS_DELETED IS NULL OR BPOS.IS_DELETED = 0)
					WHERE bb.INVOICE_AMOUNT > 0) VALIDBILLS
			ON POS.LO_PURCHASE_ORDER_ID = VALIDBILLS.LO_PURCHASE_ORDER_ID
				AND LPOS.LO_LOAD_NUMBER = VALIDBILLS.LO_LOAD_NUMBER
				AND LDS.CR_CARRIER_ID = VALIDBILLS.CR_CARRIER_ID
		INNER JOIN dbo.CR_CARRIERS AS CR
		    ON LDS.CR_CARRIER_ID = CR.CR_CARRIER_ID
	WHERE POS.TMS_STATUS_ID = 9
		AND POS.SOURCE_SYSTEM =
		CASE WHEN @FilterBySourceSystem = 1 
			THEN
			 @SourceSystem
			ELSE
			 POS.SOURCE_SYSTEM
		END
		AND VALIDBILLS.BL_BILLING_ID IS NULL
		AND LDS.CR_CARRIER_ID NOT IN (78, 1680, 2496, 1704)
		AND (CAST(POS.REC_DATE AS DATE) BETWEEN @StartDate AND @EndDate)		
		--AND LDS.CR_CARRIER_ID NOT IN (2116,4103,4569,4601,4917,5140,5144,5307,7135,7449,7518)-- Separating bc this will be replace during LCS project with CR_CARRIERS.SHUTTLE_CARRIER logic
		AND CR.SHUTTLE_CARRIER <> 1
)
GO


