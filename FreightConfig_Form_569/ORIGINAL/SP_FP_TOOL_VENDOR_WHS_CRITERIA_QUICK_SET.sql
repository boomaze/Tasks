USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_TOOL_VENDOR_WHS_CRITERIA_QUICK_SET]    Script Date: 7/28/2022 2:32:03 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Tim Lewis
-- Create date: 01/15/19
-- Description:	Form Vendor whs criteria Quick Set 

--MODIFICATION LIST
--
-- 03/28/2019 - TWL - CALL EXECUTE OF UPDATE_ALL SP
--
--
-- =============================================
ALTER PROCEDURE [dbo].[SP_FP_TOOL_VENDOR_WHS_CRITERIA_QUICK_SET]
(
	@FORM_ID BIGINT = NULL,
	@PICKUP_LOCATION_ID BIGINT = NULL, 
	@METHOD_ID BIGINT = NULL,
	@CROSSDOCK_WHS_ID BIGINT = NULL,
	@PROJECTED_LOAD_WEIGHT DECIMAL(18,3) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;

	IF(@FORM_ID IS NOT NULL)
	BEGIN
		UPDATE FV
		SET FV.FP_FF_PICKUP_LOCATIONS_ID = ISNULL(@PICKUP_LOCATION_ID, FV.FP_FF_PICKUP_LOCATIONS_ID),
			--CASE WHEN @PICKUP_LOCATION_ID IS NOT NULL THEN @PICKUP_LOCATION_ID 
			--	ELSE FV.FP_FF_PICKUP_LOCATIONS_ID END,
			FV.FP_FF_METHOD_ID =  ISNULL(@METHOD_ID, FV.FP_FF_METHOD_ID),
			--CASE WHEN @METHOD_ID IS NOT NULL THEN @METHOD_ID 
			--	ELSE FV.FP_FF_METHOD_ID END,
			FV.CROSSDOCK_WHS_ID = ISNULL(@CROSSDOCK_WHS_ID, FV.CROSSDOCK_WHS_ID),
			--CASE WHEN @CROSSDOCK_WHS_ID IS NOT NULL THEN @CROSSDOCK_WHS_ID 
			--	ELSE FV.CROSSDOCK_WHS_ID END,
			FV.PROJECTED_LOAD_WEIGHT = ISNULL(@PROJECTED_LOAD_WEIGHT, FV.PROJECTED_LOAD_WEIGHT)
			--CASE WHEN @PROJECTED_LOAD_WEIGHT IS NOT NULL THEN @PROJECTED_LOAD_WEIGHT 
			--	ELSE FV.PROJECTED_LOAD_WEIGHT END
		FROM FP_FREIGHT_FORM AS FF
			INNER JOIN FP_FREIGHT_FORM_VENDOR AS FV
				ON FF.FP_FREIGHT_FORM_ID = FV.FP_FREIGHT_FORM_ID
				AND (FV.IS_DELETED IS NULL OR FV.IS_DELETED = 0)
		WHERE FF.FP_FREIGHT_FORM_ID = @FORM_ID


		--============================================================================================================================
		--	WE NOW HAVE TO RECALCULATE
		--============================================================================================================================
		EXEC SP_FP_TOOL_VENDOR_WHS_UPDATE_ALL @FORM_ID

	END
END
GO

