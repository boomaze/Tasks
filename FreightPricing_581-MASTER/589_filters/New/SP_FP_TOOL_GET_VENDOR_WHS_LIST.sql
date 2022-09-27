USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_TOOL_GET_VENDOR_WHS_LIST]    Script Date: 8/22/2022 6:16:20 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		TIM LEWIS
-- Create date: 01/03/2019
-- Description:	GET FORM VENDOR WHS LIST FOR THE FRIEGHT PRICING TOOL

--Modification list
--
--04/30/2019 - TWL - Rename PICKUP_ALLOWANCE to OFFERED_PICKUP_ALLOWANCE
--09/09/2019 - TWL - SUBMIT PARTIAL FORM CHANGE
--08/23/2022 - CEM - Fixed WHS name search
-- =============================================
ALTER PROCEDURE [dbo].[SP_FP_TOOL_GET_VENDOR_WHS_LIST]
	@FORM_ID BIGINT = NULL,
	@PICKUP_LOCATION_NAME VARCHAR(250) = NULL,
	@DESTINATION_WHS_NAME VARCHAR(250) = NULL,
	@CROSSDOCK_NAME AS VARCHAR(250) = NULL,
	@METHOD VARCHAR(250) = NULL,
	@Sort_Direction VARCHAR(250) = 'ASC',
	@Sort_Expression VARCHAR(250) = 'WHS_NUMBER'

AS
BEGIN

	DECLARE @QUERY AS nvarchar(MAX) = ''
	
	SET @QUERY=@QUERY+ '
		select *
		from (
		select FRM.FP_FREIGHT_FORM_ID,
					FRM_VEN.FP_FREIGHT_FORM_VENDOR_ID,
					METHOD.FP_FF_METHOD_ID,
					METHOD.DESCRIPTION AS METHOD,
					VEN.TMS_VENDOR_ID,
					VEN.NAME AS VENDOR_NAME,
					PICKUP.FP_FF_PICKUP_LOCATIONS_ID,
					PICKUP.PICKUP_NAME,
					PICKUP.ADDRESS AS ORIGIN_ADDRESS,
					PICKUP.CITY AS ORIGIN_CITY,
					PICKUP.ZIP AS ORIGIN_ZIP,
					CROSSDOCK_WHS.TMS_WHS_ID AS CROSSDOCK_WHS_ID,
					CROSSDOCK_WHS.ADDRESS1 AS CROSSDOCK_ADDRESS,
					CROSSDOCK_WHS.CITY AS CROSSDOCK_CITY,
					CROSSDOCK_WHS.ZIP AS CROSSDOCK_ZIP,
					CROSSDOCK_WHS.WHS_NUMBER + '' '' + CROSSDOCK_WHS.NAME AS CROSSDOCK_WHS_NAME,
					DEST_WHS.TMS_WHS_ID AS DESTINATION_WHS_ID,
					DEST_WHS.ADDRESS1 AS DESTINATION_WHS_ADDRESS,
					DEST_WHS.CITY AS DESTINATION_WHS_CITY,
					DEST_WHS.ZIP AS DESTINATION_ZIP,
					DEST_WHS.WHS_NUMBER + '' '' + DEST_WHS.NAME AS DESTINATION_WHS_NAME,
					DEST_WHS.WHS_NUMBER as WHS_NUMBER,
					ISNULL(FRM_VEN.CALC_RATE, 0) AS CALC_RATE,
					ISNULL(FRM_VEN.CALC_ALL_IN_RATE, 0) AS CALC_ALL_IN_RATE,
					RATE.RATE,
					ISNULL(FRM_VEN.ALLOWANCE_PER_LB, 0) AS ALLOWANCE_PER_LB,
					FRM_VEN.AVERAGE_PALLETS_PER_PO,
					FRM_VEN.AVERAGE_PO_UNITS,
					FRM_VEN.AVERAGE_PO_WEIGHT,
					ISNULL(FRM_VEN.BOOKED_FREIGHT_PER_LB, 0) AS BOOKED_FREIGHT_PER_LB,
					ISNULL(FRM_VEN.LANDED_EXPENSE_PER_LB, 0) AS LANDED_EXPENSE_PER_LB,
					FRM_VEN.OFFERED_PICKUP_ALLOWANCE,
					FRM_VEN.PROJECTED_LOAD_WEIGHT,
					FRM_VEN.PROPOSED_ALLOWANCE_PER_LB,
					ISNULL(FRM_VEN.PROPOSED_BOOKED_FREIGHT, 0) AS PROPOSED_BOOKED_FREIGHT,
					FRM_VEN.PROPOSED_FREIGHT_PER_LB,
					ISNULL(FRM_VEN.PROPOSED_PROJECTED_MARGIN, 0) AS PROPOSED_PROJECTED_MARGIN,
					ISNULL(FRM_VEN.PROPOSED_TOTAL_ALLOWANCE, 0) AS PROPOSED_TOTAL_ALLOWANCE,
					ISNULL(FRM_VEN.TOTAL_MARGIN, 0) AS TOTAL_MARGIN,
					ISNULL(FRM_VEN.TOTAL_ALLOWANCE, 0) AS TOTAL_ALLOWANCE,
					ISNULL(FRM_VEN.TOTAL_BOOKED_FREIGHT, 0) AS TOTAL_BOOKED_FREIGHT,
					ISNULL(FRM_VEN.PROPOSED_TOTAL_EXPENSE, 0) AS PROPOSED_TOTAL_EXPENSE,
					FRM_VEN.TOTAL_POS,
					ISNULL(FRM_VEN.BOOKED_FREIGHT_OVERRIDE, 0) AS BOOKED_FREIGHT_OVERRIDE,
					ISNULL(FRM_VEN.PROJECTED_LOAD_WEIGHT_OVERRIDE, 0) AS PROJECTED_LOAD_WEIGHT_OVERRIDE,
					FRM.EAST_BLENDED_FREIGHT_RATE,
					CAST(CASE WHEN DEST_WHS.SOURCE_SYSTEM = ''UBS'' THEN 1 ELSE 0 END AS bit) AS DISPLAY_EAST_BLENDED_FREIGHT_RATE,
					FRM.GILROC_BLENDED_FREIGHT_RATE,
					CAST(CASE WHEN DEST_WHS.TMS_WHS_ID IN (1, 114) THEN 1 ELSE 0 END AS bit) AS DISPLAY_GILROC_BLENDED_FREIGHT_RATE,
					ISNULL(DEST_WHS.SOURCE_SYSTEM, '''') AS SOURCE_SYSTEM,
					FRM_VEN.EFFECTIVE_DATE,
					FRM_VEN.PROCESSED_FLAG
				from FP_FREIGHT_FORM AS FRM
					INNER JOIN FP_FREIGHT_FORM_VENDOR as FRM_VEN
						ON FRM.FP_FREIGHT_FORM_ID = FRM_VEN.FP_FREIGHT_FORM_ID
							AND (FRM_VEN.IS_DELETED IS NULL OR FRM_VEN.IS_DELETED = 0)
					LEFT JOIN FP_FF_METHOD AS METHOD
						ON FRM_VEN.FP_FF_METHOD_ID = METHOD.FP_FF_METHOD_ID 
					LEFT JOIN TMS_VENDOR AS VEN
						ON FRM_VEN.TMS_VENDOR_ID = VEN.TMS_VENDOR_ID
					LEFT JOIN FP_FF_PICKUP_LOCATIONS AS PICKUP
						ON FRM_VEN.FP_FF_PICKUP_LOCATIONS_ID = PICKUP.FP_FF_PICKUP_LOCATIONS_ID
					LEFT JOIN TMS_WHS AS CROSSDOCK_WHS
						ON FRM_VEN.CROSSDOCK_WHS_ID = CROSSDOCK_WHS.TMS_WHS_ID
					LEFT JOIN TMS_WHS AS DEST_WHS
						ON FRM_VEN.TMS_WHS_ID = DEST_WHS.TMS_WHS_ID
					LEFT JOIN CR_RATE AS RATE
						ON FRM_VEN.CR_RATE_ID = RATE.CR_RATE_ID
				WHERE FRM.FP_FREIGHT_FORM_ID = ' + cast(@FORM_ID AS VARCHAR) 
				
				--CONTROL FILTER CRITERIA

				IF(@PICKUP_LOCATION_NAME IS NOT NULL AND @PICKUP_LOCATION_NAME <> '')
					SET @QUERY=@QUERY+  ' AND (PICKUP.PICKUP_NAME LIKE ''%'' + '''+cast(@PICKUP_LOCATION_NAME  AS VARCHAR)+''' + ''%'' )'

				IF(@DESTINATION_WHS_NAME IS NOT NULL AND @DESTINATION_WHS_NAME <> '')
					SET @QUERY=@QUERY+  ' AND DEST_WHS.NAME LIKE '  + '''' + '%' + cast(@DESTINATION_WHS_NAME  AS VARCHAR)+ '%' + '''' 

				IF(@CROSSDOCK_NAME IS NOT NULL AND @CROSSDOCK_NAME <> '')
					SET @QUERY=@QUERY+  ' AND ((CROSSDOCK_WHS.WHS_NUMBER + '' '' + CROSSDOCK_WHS.NAME) LIKE ''%'' + '''+cast(@CROSSDOCK_NAME  AS VARCHAR)+''' + ''%'' )'

				IF(@METHOD IS NOT NULL AND @METHOD <> '')
					SET @QUERY=@QUERY+  ' AND (METHOD.DESCRIPTION LIKE ''%'' + '''+cast(@METHOD  AS VARCHAR)+''' + ''%'' )'

	--CONTROL SORT CRITERIA
	SET @QUERY=@QUERY+ ') as Result ORDER BY Result.' + @Sort_Expression + ' ' + @Sort_Direction	

    PRINT (@QUERY)
    EXEC sp_executesql @QUERY

END
GO


