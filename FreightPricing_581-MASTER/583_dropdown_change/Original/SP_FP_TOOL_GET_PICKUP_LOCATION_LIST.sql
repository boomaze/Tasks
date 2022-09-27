USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_TOOL_GET_PICKUP_LOCATION_LIST]    Script Date: 8/22/2022 10:32:42 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		TIM LEWIS
-- Create date: 01/07/19
-- Description:	GET PICKUP LIST FOR DROPDOWNS
-- =============================================
ALTER PROCEDURE [dbo].[SP_FP_TOOL_GET_PICKUP_LOCATION_LIST] 
	-- Add the parameters for the stored procedure here
	@FORM_ID BIGINT = NULL
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	SELECT FF.FP_FF_PICKUP_LOCATIONS_ID,
			FF.ADDRESS,
			FF.CITY,
			FF.ZIP,
			FF.PICKUP_NAME
	FROM FP_FF_PICKUP_LOCATIONS AS FF
	WHERE FF.FP_FREIGHT_FORM_ID = @FORM_ID
	AND (FF.IS_DELETED IS NULL OR FF.IS_DELETED = 0)

END
GO


