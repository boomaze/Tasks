USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_TOOL_GET_FORM_LEVEL_DATA]    Script Date: 7/7/2022 9:42:16 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		TIM LEWIS
-- Create date: 01/03/2019
-- Description:	GET FORM LEVEL DATA FOR THE FRIEGHT PRICING TOOL

-- MODIFICATION LIST
--==============================================
-- 07/31/2019 - TWL -	CHANGED TO PULL THE CROSSDOCK AND BACKHAUL PALLET RATE FROM THE FORM NOT THE CONFIG
-- 08/01/2019 - KT  -   Add Implied Rate to select statement
-- 09/09/2019 - TWL - SUBMIT PARTIAL FORM CHANGE
-- =============================================
ALTER PROCEDURE [dbo].[SP_FP_TOOL_GET_FORM_LEVEL_DATA]
	@FORM_ID BIGINT = NULL

AS
BEGIN
	
	DECLARE @IS_CURRENT_ALLOWANCE BIT = 0,
			@COUNT INT;

	SELECT @COUNT = COUNT(*) 
	FROM FP_FREIGHT_FORM FORM
	JOIN FP_FREIGHT_FORM_VENDOR FVEN ON FORM.FP_FREIGHT_FORM_ID = FVEN.FP_FREIGHT_FORM_ID
	WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_ID
	AND FVEN.CURRENT_ALLOWANCE IS NOT NULL


	SELECT FRM.FP_FREIGHT_FORM_ID,
		STS.TMS_STATUS_ID AS FORM_STATUS_ID,
		STS.STATUS AS FORM_STATUS,
		FF_TYPE.FP_FF_TYPE_ID,
		FF_TYPE.DESCRIPTION AS FORM_TYPE,
		--FF_ALLOWANCE.FP_FF_ALLOWANCE_TYPE_ID,
		FRM.FP_FF_ALLOWANCE_TYPE_ID,
		FF_ALLOWANCE.DESCRIPTION AS FORM_ALLOWANCE,
		FF_TEMP.FP_FF_TEMPERATURE_ID AS FORM_TEMP_ID,
		FF_TEMP.DESCRIPTION as FORM_TEMP,
		FF_TEMP_PROTECTION.FP_FF_TEMPERATURE_PROTECTION_ID,
		FF_TEMP_PROTECTION.DESCRIPTION AS FORM_TEMP_PROTECTION,
		LOAD_TEMP.LO_LOAD_TEMPERATURES_ID,
		LOAD_TEMP.TEMPERATURE AS LOAD_TEMP,
		LOAD_TEMP.PROTECTION_LEVEL AS LOAD_PROTECTION_LEVEL,
		FRM.FREIGHT_ANALYST_USER_ID,
		ANALYST.FIRST_NAME + ' ' + ANALYST.LAST_NAME AS FRIEGHT_ANALYST_NAME,
		FRM.SUBMIT_DATE,
		FRM.LAWSON_NUMBER,
		FRM.IS_HUB_AND_SPOKE,
		FRM.IS_HUB_AND_SPOKE_VSP,
		FRM.IS_VSP_CROSSDOCK,
		FRM.IS_PRICE_LIST_SUBMITTED,
		FRM.MARGIN_TARGET,
		FRM.PFF_PFH_UP_CHARGE,
		FRM.CHILL_FRZ_UP_CHARGE,
		--FRM.EFFECTIVE_DATE,
		FRM.CROSSDOCK_PALLET_RATE,
		FRM.BACKHAUL_PALLET_RATE,
		CONFIG.SHUTTLE_RATE_PER_MILE,
		CONFIG.FUEL_SURCHARGE,
		CONFIG.ESTIMATED_LUMPER_EXPENSE,
		CONFIG.ESTIMATED_ACCESSORIAL_EXPENSE,
		FRM.TOOL_COOLER_FREEZER_UPCHARGE,
		FRM.TOOL_MARGIN_TARGET, 
		FRM.TOOL_PFF_PFH_UPCHARGE,
		FRM.TOOL_FUEL_SURCHARGE,
		CAST(CASE WHEN @COUNT > 0 THEN 1 ELSE 0 END AS BIT) AS IS_CURRENT_ALLOWANCE,
		ISNULL(FRM.IS_IMPLIED_RATE, 0) AS IS_IMPLIED_RATE
	FROM FP_FREIGHT_FORM AS FRM
		LEFT JOIN FP_FF_TYPE AS FF_TYPE
			ON FRM.FP_FF_TYPE_ID = FF_TYPE.FP_FF_TYPE_ID
		LEFT JOIN FP_FF_TEMPERATURE AS FF_TEMP
			ON FRM.FP_FF_TEMPERATURE_ID = FF_TEMP.FP_FF_TEMPERATURE_ID
		LEFT JOIN FP_FF_TEMPERATURE_PROTECTION AS FF_TEMP_PROTECTION
			ON FRM.FP_FF_TEMPERATURE_PROTECTION_ID = FF_TEMP_PROTECTION.FP_FF_TEMPERATURE_PROTECTION_ID
		LEFT JOIN FP_FF_ALLOWANCE_TYPE AS FF_ALLOWANCE
			ON FRM.FP_FF_ALLOWANCE_TYPE_ID = FF_ALLOWANCE.FP_FF_ALLOWANCE_TYPE_ID
		LEFT JOIN LO_LOAD_TEMPERATURES AS LOAD_TEMP
			ON FRM.LO_LOAD_TEMPERATURES_ID = LOAD_TEMP.LO_LOAD_TEMPERATURES_ID
		LEFT JOIN SEC_USERS AS ANALYST
			ON FRM.FREIGHT_ANALYST_USER_ID = ANALYST.SEC_USERS_ID
		LEFT JOIN TMS_STATUS AS STS
			ON FRM.TMS_STATUS_ID = STS.TMS_STATUS_ID
		LEFT JOIN FP_DEFAULT_CONFIG AS CONFIG
			ON FRM.FP_FREIGHT_FORM_ID = FRM.FP_FREIGHT_FORM_ID    -- freight form somehow attach to tms_whs?
	WHERE FRM.FP_FREIGHT_FORM_ID = @FORM_ID

END
GO


