USE [TMS]
GO

/****** Object:  UserDefinedFunction [dbo].[fnGetPOSWithCalculatePalletsFPA]    Script Date: 7/11/2022 12:52:13 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/******************************************************************************************
Created By  : Johana Aleman
Date	    : 12/06/2018
Description : Get all the POs that have RCV status(TMS_STATUS_ID = 9) between the Start 
			  and End Dates and Calculate Pallets base on FPA Calculation. 

Note: The FPA calculation will apply to only Backhaul Loads but at this point we calculated
      for all POs
	  
7/11/2022		CM       added source system filter
****************************************************************************************/
ALTER FUNCTION [dbo].[fnGetPOSWithCalculatePalletsFPA]
(
	@StartDate DATE
,	@EndDate DATE
,   @FilterBySourceSystem BIT --SET to apply filter, if false filter is ignored
,   @SourceSystem VARCHAR(50)
)
RETURNS TABLE 
AS
/**************************************************************************************************************
– For Backhaul Pricing types, the Freight Tool will need to calculate pallets based on the FPA calculation
•	Determine if Calculate the PO Weight per Pallet falls within the range of 250 – 1200
•	Determine if PO Cube per Pallet falls within the range of 25 – 100
•	If neither PO Weight per Pallet and PO Cube per Pallet fall within their respective ranges,  calculate pallets by assigning 1 pallet for every 50 cube and get Min (total cubes/50, pallets)
•	Check If the result of the Previous pallets are less than 26 pallets then use previous Min otherwise use 26
***************************************************************************************************************/
RETURN 
(
	SELECT LO_PURCHASE_ORDER_ID
		--, IIF(CASE WHEN IS_BETWEEN_PO_WEIGHT_PALLET = 0 AND IS_BETWEEN_PO_CUBE_PALLET = 0 THEN CAST(CEILING(TOTAL_CUBES / 50.0) AS DECIMAL(10,3)) END < TOTAL_PALLETS, CAST(CEILING(TOTAL_CUBES / 50.0) AS DECIMAL(10,3)),TOTAL_PALLETS) AS RESIZE_PALLETS
		,CASE WHEN IIF(CASE WHEN IS_BETWEEN_PO_WEIGHT_PALLET = 0 AND IS_BETWEEN_PO_CUBE_PALLET = 0 THEN CAST(CEILING(TOTAL_CUBES / 50.0) AS DECIMAL(10,3)) END < TOTAL_PALLETS, CAST(CEILING(TOTAL_CUBES / 50.0) AS DECIMAL(10,3)),TOTAL_PALLETS) > 26.0 THEN 26.0 ELSE IIF(CASE WHEN IS_BETWEEN_PO_WEIGHT_PALLET = 0 AND IS_BETWEEN_PO_CUBE_PALLET = 0 THEN CAST(CEILING(TOTAL_CUBES / 50.0) AS DECIMAL(10,3)) END < TOTAL_PALLETS, CAST(CEILING(TOTAL_CUBES / 50.0) AS DECIMAL(10,3)),TOTAL_PALLETS) END AS MAX_26PALLETS_FINAL_CALC
	FROM (
			SELECT lpo.LO_PURCHASE_ORDER_ID
				, lpo.TOTAL_CUBES
				, CEILING(lpo.TOTAL_PALLETS) AS TOTAL_PALLETS
				, CASE WHEN lpo.TOTAL_WEIGHT / NULLIF(CEILING(lpo.TOTAL_PALLETS),0) BETWEEN 250 AND 1200 THEN 1 ELSE 0 END AS IS_BETWEEN_PO_WEIGHT_PALLET
				, CASE WHEN lpo.TOTAL_CUBES / NULLIF(CEILING(lpo.TOTAL_PALLETS),0) BETWEEN 25 AND 100 THEN 1 ELSE 0 END AS IS_BETWEEN_PO_CUBE_PALLET
			FROM LO_PURCHASE_ORDERS lpo
			WHERE lpo.TMS_STATUS_ID = 9
			AND lpo.SOURCE_SYSTEM =
			CASE WHEN @FilterBySourceSystem = 1 
				THEN
				 @SourceSystem
				ELSE
				 lpo.SOURCE_SYSTEM
			END
			AND CAST(REC_DATE AS DATE) BETWEEN @StartDate AND @EndDate
	)t
)
GO


