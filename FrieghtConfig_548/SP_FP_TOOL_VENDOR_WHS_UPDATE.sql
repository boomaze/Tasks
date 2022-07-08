USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_TOOL_VENDOR_WHS_UPDATE]    Script Date: 7/7/2022 9:43:12 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Tim Lewis
-- Create date: 01/28/19 
-- Description:	Update for Form Vendor on Tool screen 

--		MODIFICATION LIST	--
--
--	03/06/19 - TWL	- REMOVED ZIP TO ZIP AND CITY/ZIP FILTERS FOR RATE
--					- FILTERED RATE TO USE ONLY THE CHEAPEST
--  03/22/19 - BK   - ADDED ERROR LOG 
--	03/27/19 - TWL	- Crossdock mileage
--	03/28/19 - TWL	- Removed PO_weight_estimate, and PO_pallet estimate due to duplicate columns
--  03/28/19 - BK   - ADDED PROJECTED_LOAD_WEIGHT_OVERRIDE
--  03/29/19 - BK   - PROPOSED_FREIGHT_PER_LB ELSE logic updated
--	04/03/19 - TWL	- LANDED_EXPENSE_PER_LB logic updated 
--	04/04/19 - twl	- LANDED_EXPENSE_PER_LB logic updated 
--  04/05/19 - BK   - MODIFIED RATE COUNT ERROR LOGIC
--	04/12/19 - TWL	- VSP METHOD MODIFICATION
--  04/24/19 - TWL  - NULL OUT PROJECTED_LOAD_WEIGHT FOR VPS
--  08/30/19 - KT   - ADDED CALCULATIONS OF DIRECT CROSSDOCK
--  10/10/19 - BK   - UPDATED CROSSDOCK AND BACKHAUL PALLET RATES TO FREIGHTFORM
--	11/18/19 - TWL	- FILTER OUT VSP VENDORS FROM EAST_BLEND_FREIGHT_RATE
--	11/20/19 - TWL	- Mile cacl change
--	11/25/19 - TWL	- Mile cacl change
--  07/01/22 - BK   - Added logic for PRIMARY_RATE and INCLUDE_IN_FREIGHT_PRICING
-- =============================================
ALTER PROCEDURE [dbo].[SP_FP_TOOL_VENDOR_WHS_UPDATE]
	-- Add the parameters for the stored procedure here
	@FORM_ID BIGINT = NULL,
	@FORM_VENDOR_ID BIGINT = NULL,
	@PICKUP_LOCATION_ID BIGINT = NULL,
	@METHOD_ID BIGINT = NULL,
	@CROSSDOCK_ID BIGINT = NULL,
	@TOTAL_POS DECIMAL(18,3) = 0, 
	@PROJECTED_LOAD_WEIGHT DECIMAL(18,3) = 0,
	@PROJECTED_PO_UNITS DECIMAL(18,3) = 0,
	@AVERAGE_PALLETS_POS DECIMAL(18,3) = 0, 
	@AVERAGE_PO_WEIGHT DECIMAL(18,3) = 0,
	@PROPOSED_ALLOWANCE_PER_LB DECIMAL(18,3) = 0,
	@PROPOSED_BOOKED_FRIEGHT_PER_LB DECIMAL(18,3) = 0,
	@BOOKED_FRIEGHT_OVERRIDE BIT = 0,
	@PROJECTED_LOAD_WEIGHT_OVERRIDE BIT = 0

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	--ERROR LOG TABLE
    DECLARE @ERROR_LOG TABLE (
			ERROR_ID BIGINT IDENTITY(1,1) primary key,
			ERROR_MESSGAE_TITLE VARCHAR(1000) NULL,
			ERROR_MESSAGE_DETAIL VARCHAR(1000) NULL,
			FIELD_NAME VARCHAR(100) NULL,
			FORM_ID BIGINT NULL
		)

	DECLARE @PROPOSED_BOOKED_FREIGHT DECIMAL(18,3) = NULL,
			@RATE DECIMAL(10,3) = NULL,
			@PROPOSED_TOTAL_ALLOWANCE DECIMAL(18,3) = NULL,
			@LANDED_EXPENSE_PER_LB DECIMAL(18,3) = NULL,
			@PROPOSED_TOTAL_EXPENSE DECIMAL(18,3) = NULL, 
			@CR_RATE_ID BIGINT = NULL,
			@CR_CARRIER_ID BIGINT = NULL,
			@MILES DECIMAL(10,4) = NULL,
			@STOPS INT = 0,
			--@METHOD BIGINT = NULL,
			@FUEL_SURCHAGE_DATE DATETIME = NULL,
			@FUEL_AVG_PRICE AS DECIMAL(10,3) = 0,
			@FUEL_SURCHARGE AS FLOAT = 0,
			@CALC_RATE AS DECIMAL(18,3) = NULL,
			@CALC_ALL_IN_RATE AS DECIMAL(18,3) = NULL,
			--@TOTAL_ALLOWANCE AS DECIMAL(18,3) = NULL,
			--@TOTAL_BOOKED_FREIGHT AS DECIMAL(18,3) = NULL,
			--@PROPOSED_ALLOWANCE_PER_LB AS DECIMAL(10,3) = NULL,
			@PROPOSED_PROJECTED_MARGIN AS DECIMAL(18,3) = NULL,
			--@TOTAL_MARGIN AS DECIMAL(18,3) = NULL,
			@PROPOSED_FREIGHT_PER_LB AS DECIMAL(18,3) = NULL,
			@EAST_BLENDED_FREIGHT_RATE AS DECIMAL(10,3) = NULL,
			@GILROC_BLENDED_FREIGHT_RATE AS DECIMAL(10,3) = NULL

	--GET THE DAY WE ARE CALCULATING THE FUEL SURCHARGE FOR
	SELECT TOP 1 @FUEL_SURCHAGE_DATE = FL.CREATED_DATE
	FROM FP_FREIGHT_FORM_LOG AS FL
	WHERE FL.TMS_STATUS_ID = 58 --IBL: Initial Analysis
	ORDER BY FL.CREATED_DATE ASC

	--GET FUEL AVERAGE PRICE
	SELECT @FUEL_AVG_PRICE = tfap.PRICE
	FROM TMS_FUEL_AVG_PRICE tfap WITH (NOLOCK)
	WHERE CAST(@FUEL_SURCHAGE_DATE AS DATE) >= CAST(tfap.[START_DATE] AS DATE)
		AND CAST(@FUEL_SURCHAGE_DATE AS DATE) <= CAST(tfap.END_DATE AS DATE)
		AND ISNULL(tfap.IS_DELETED, 0) <> 1


	
	--MILEAGE AND STOPS BASED OFF METHOD ID
	IF(@METHOD_ID = 1) --BACKHAUL
	BEGIN
		--MILES WILL ALWAYS BE 0 FOR BACKHAUL
		SET @MILES = 0

	END
	ELSE IF(@METHOD_ID = 2) --BACKHAUL CROSSDOCK
	BEGIN
		--MILEAGE FOR CROSSDOCK
		SELECT TOP 1 @MILES = MILES.MILES
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR
			INNER JOIN FP_FF_CROSSDOCK_MILES AS MILES 
				ON VENDOR.TMS_WHS_ID = MILES.DESTINATION_WHS_ID
					AND @CROSSDOCK_ID = MILES.ORIGIN_WHS_ID
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID

		--STOPS FOR CROSSDOCK
		SELECT TOP 1 @STOPS = STOPS.NUMBER_OF_STOPS
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR
			INNER JOIN FP_FF_CROSSDOCK_STOPS AS STOPS 
				ON VENDOR.TMS_WHS_ID = STOPS.DESTINATION_WHS_ID
					AND @CROSSDOCK_ID = STOPS.ORIGIN_WHS_ID
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID
	END
	ELSE IF(@METHOD_ID = 3) --DIRECT
	BEGIN

		--GET THE CHEEPEST RATE 
		SELECT TOP 1 --@CR_RATE_ID = RT.CR_RATE_ID,
						@CR_RATE_ID = CASE WHEN RT_PRIMARY_RATE.RATE IS NOT NULL THEN RT_PRIMARY_RATE.CR_RATE_ID ELSE RT.CR_RATE_ID END,


						--@MILES = RT.MILEAGE,
						@MILES = CASE WHEN RT_PRIMARY_RATE.RATE IS NOT NULL THEN RT_PRIMARY_RATE.MILEAGE ELSE RT.MILEAGE END,


						--@METHOD = @METHOD_ID,


						--@CR_CARRIER_ID = RT.CR_CARRIER_ID,
						@CR_CARRIER_ID = CASE WHEN RT_PRIMARY_RATE.RATE IS NOT NULL THEN RT_PRIMARY_RATE.CR_CARRIER_ID ELSE RT.CR_CARRIER_ID END,


						--@RATE = ISNULL((CASE WHEN (RT.RATE_UNIT = 'Flat') THEN RT.RATE
						--				  ELSE (CASE WHEN (RT.RATE_UNIT = 'Per Mile') THEN (RT.RATE * RT.MILEAGE)
						--						END
						--						)
						--				  END), 0)
						@RATE = CASE WHEN RT_PRIMARY_RATE.RATE IS NOT NULL THEN RT_PRIMARY_RATE.RATE ELSE RT.RATE END 
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR
			INNER JOIN FP_FREIGHT_FORM AS FORM
				ON VENDOR.FP_FREIGHT_FORM_ID = FORM.FP_FREIGHT_FORM_ID
			INNER JOIN TMS_WHS AS DESTINATION
				ON VENDOR.TMS_WHS_ID = DESTINATION.TMS_WHS_ID
			LEFT JOIN TMS_WHS AS CROSSDOCK
				ON CROSSDOCK.TMS_WHS_ID = @CROSSDOCK_ID
			LEFT JOIN FP_FF_PICKUP_LOCATIONS AS PICKUP
				ON @PICKUP_LOCATION_ID = PICKUP.FP_FF_PICKUP_LOCATIONS_ID


			LEFT JOIN (SELECT dbo.CR_RATE.*
					   FROM dbo.CR_RATE 
						INNER JOIN dbo.CR_CARRIERS 
							ON dbo.CR_RATE.CR_CARRIER_ID = dbo.CR_CARRIERS.CR_CARRIER_ID
					   WHERE (dbo.CR_CARRIERS.INCLUDE_IN_FREIGHT_PRICING = 1)
					   AND
					   (dbo.CR_RATE.IS_DELETED IS NULL OR dbo.CR_RATE.IS_DELETED = 0)
					   AND
					   (dbo.CR_CARRIERS.IS_DELETED IS NULL OR dbo.CR_CARRIERS.IS_DELETED = 0)) AS RT
				ON CASE WHEN DESTINATION.[CAMPUS_WHS_ID] IS NULL THEN  DESTINATION.TMS_WHS_ID ELSE DESTINATION.[CAMPUS_WHS_ID] END = RT.DESTINATION_WHS_ID
					AND RT.IS_CHEAPEST_RATE = 1
					AND (--PICKUP FILTER
							PICKUP.FP_FF_PICKUP_LOCATIONS_ID IS NOT NULL
							AND (PICKUP.CITY = RT.ORIGIN_CITY AND PICKUP.STATE = RT.ORIGIN_STATE)
					)
					
			LEFT JOIN (SELECT dbo.CR_RATE.*
					   FROM dbo.CR_RATE 
						INNER JOIN dbo.CR_CARRIERS 
							ON dbo.CR_RATE.CR_CARRIER_ID = dbo.CR_CARRIERS.CR_CARRIER_ID
					   WHERE (dbo.CR_CARRIERS.INCLUDE_IN_FREIGHT_PRICING = 1)
					   AND
					   (dbo.CR_RATE.IS_DELETED IS NULL OR dbo.CR_RATE.IS_DELETED = 0)
					   AND
					   (dbo.CR_CARRIERS.IS_DELETED IS NULL OR dbo.CR_CARRIERS.IS_DELETED = 0)) AS RT_PRIMARY_RATE
				ON CASE WHEN DESTINATION.[CAMPUS_WHS_ID] IS NULL THEN  DESTINATION.TMS_WHS_ID ELSE DESTINATION.[CAMPUS_WHS_ID] END = RT_PRIMARY_RATE.DESTINATION_WHS_ID
					AND RT_PRIMARY_RATE.[PRIMARY_RATE] = 1
					AND RT_PRIMARY_RATE.IS_CHEAPEST_RATE = 1
					AND (--PICKUP FILTER
							PICKUP.FP_FF_PICKUP_LOCATIONS_ID IS NOT NULL
							AND (PICKUP.CITY = RT_PRIMARY_RATE.ORIGIN_CITY AND PICKUP.STATE = RT_PRIMARY_RATE.ORIGIN_STATE)
					) 
										
					
										 
			WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID
					--AND (RT.IS_DELETED IS NULL OR RT.IS_DELETED = 0)
					--AND (RT_PRIMARY_RATE.IS_DELETED IS NULL OR RT_PRIMARY_RATE.IS_DELETED = 0)
					AND RT.PROTECTION_LEVEL = (CASE WHEN FORM.FP_FF_TEMPERATURE_ID = 3 THEN 'Dry' ELSE RT.PROTECTION_LEVEL END)
					AND RT_PRIMARY_RATE.PROTECTION_LEVEL = (CASE WHEN FORM.FP_FF_TEMPERATURE_ID = 3 THEN 'Dry' ELSE RT_PRIMARY_RATE.PROTECTION_LEVEL END)
	END

	ELSE IF(@METHOD_ID = 5) --DIRECT CROSSDOCK
	BEGIN
		--MILEAGE FOR CROSSDOCK
		SELECT TOP 1 @MILES = MILES.MILES
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR
			INNER JOIN FP_FF_CROSSDOCK_MILES AS MILES 
				ON VENDOR.TMS_WHS_ID = MILES.DESTINATION_WHS_ID
					AND @CROSSDOCK_ID = MILES.ORIGIN_WHS_ID
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID

		--STOPS FOR CROSSDOCK
		SELECT TOP 1 @STOPS = STOPS.NUMBER_OF_STOPS
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR
			INNER JOIN FP_FF_CROSSDOCK_STOPS AS STOPS 
				ON VENDOR.TMS_WHS_ID = STOPS.DESTINATION_WHS_ID
					AND @CROSSDOCK_ID = STOPS.ORIGIN_WHS_ID
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID
	END
	

	--TWL 03/28/2019 - WE NO LONGER USE THIS
	--GET THE FUEL_SURCHARGE AMOUNT
	--SELECT @FUEL_SURCHARGE =  CAST(REPLACE(dbo.FN_CALCULATE_FUEL_SURCHARGE(@FUEL_AVG_PRICE, 'OTR', @CR_CARRIER_ID), '_OTR', '' ) AS DECIMAL(10,3))

	--TWL 04/12/2018 - VSP REQUIRES NO CALCULATIONS
	IF(@METHOD_ID <> 4) 
	BEGIN
		--START CALCULATIONS
		SELECT --CALC_RATE
				@CALC_RATE = CASE WHEN @METHOD_ID = 1 or @METHOD_ID = 2 --BACKHAUL(1), BACKHAUL CROSSDOCK(2)
							 THEN(@AVERAGE_PALLETS_POS * (FORM.CROSSDOCK_PALLET_RATE + FORM.BACKHAUL_PALLET_RATE) + (@MILES * CONFIG.SHUTTLE_RATE_PER_MILE))
							 WHEN @METHOD_ID = 3 --DIRECT(3)
							 THEN @RATE
							 WHEN @METHOD_ID = 5--DIRECT CROSSDOCK(5)
							 THEN @RATE
							 --THEN(@AVERAGE_PALLETS_POS * (FORM.CROSSDOCK_PALLET_RATE) + (@MILES * CONFIG.SHUTTLE_RATE_PER_MILE))
							 END,
				--TOTAL_ALLOWANCE
				--@TOTAL_ALLOWANCE = (ISNULL(VENDOR.ALLOWANCE_PER_LB, 0) * ISNULL(@AVERAGE_PO_WEIGHT, 0) * @TOTAL_POS),
				--TOTAL_BOOKED_FREIGHT
				--@TOTAL_BOOKED_FREIGHT = (ISNULL(VENDOR.BOOKED_FREIGHT_PER_LB, 0) * @AVERAGE_PO_WEIGHT * @TOTAL_POS),
				--PROPOSED_ALLOWANCE_PER_LB
				--@PROPOSED_ALLOWANCE_PER_LB = (ISNULL(VENDOR.ALLOWANCE_PER_LB, 0) * @AVERAGE_PO_WEIGHT * @TOTAL_POS)
				--PROJECTED_LOAD_WEIGHT
				@PROJECTED_LOAD_WEIGHT = CASE WHEN @PROJECTED_LOAD_WEIGHT_OVERRIDE = 1 THEN @PROJECTED_LOAD_WEIGHT
												ELSE CASE WHEN @METHOD_ID = 1 THEN CONFIG.ANTICIPATED_BACKHAUL_LOAD_WEIGHT
														WHEN  @METHOD_ID = 2 THEN CONFIG.ANTICIPATED_CROSSDOCK_LOAD_WEIGHT
														WHEN  @METHOD_ID = 5 THEN CONFIG.ANTICIPATED_CROSSDOCK_LOAD_WEIGHT
														ELSE CONFIG.ANTICIPATED_TL_LOAD_WEIGHT END
											END
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR 
			INNER JOIN FP_FREIGHT_FORM AS FORM
				ON VENDOR.FP_FREIGHT_FORM_ID = FORM.FP_FREIGHT_FORM_ID
			INNER JOIN FP_DEFAULT_CONFIG AS CONFIG
				ON CONFIG.FP_DEFAULT_CONFIG_ID = (SELECT  TOP 1 CONFIG.FP_DEFAULT_CONFIG_ID FROM FP_DEFAULT_CONFIG AS CONFIG) --TODOMAZE VENDOR.TMS_WHS_ID	
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID
			AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)

		--STEP 2 CALCULATIONS 
		SELECT --CALC_ALL_IN_RATE
				@CALC_ALL_IN_RATE = (@CALC_RATE + (@MILES * FORM.TOOL_FUEL_SURCHARGE)),
				--PROPOSED_TOTAL_ALLOWANCE (REVISIT)
				@PROPOSED_TOTAL_ALLOWANCE = (ISNULL(@PROPOSED_ALLOWANCE_PER_LB, 0) * ISNULL(@AVERAGE_PO_WEIGHT, 0) * @TOTAL_POS)
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR
		INNER JOIN FP_FREIGHT_FORM AS FORM
				ON VENDOR.FP_FREIGHT_FORM_ID = FORM.FP_FREIGHT_FORM_ID
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID
			AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)
	
		--STEP 3 CALCULATIONS 
		SELECT  --LANDED_EXPENSE_PER_LB
				@LANDED_EXPENSE_PER_LB = CASE WHEN @METHOD_ID = 1 --BACKHAUL(1)
											THEN CASE	WHEN (@AVERAGE_PO_WEIGHT = 0 OR @AVERAGE_PO_WEIGHT IS NULL) OR (@CALC_ALL_IN_RATE = 0 OR @CALC_ALL_IN_RATE IS NULL) THEN NULL
														ELSE (@CALC_ALL_IN_RATE / @AVERAGE_PO_WEIGHT)
												 END
										WHEN @METHOD_ID = 2 --BACKHAUL CROSSDOCK(2)
											THEN CASE	WHEN (@AVERAGE_PO_WEIGHT = 0 OR @AVERAGE_PO_WEIGHT IS NULL) OR (@CALC_ALL_IN_RATE = 0 OR @CALC_ALL_IN_RATE IS NULL) THEN NULL 
														ELSE ((((((CONFIG.CROSSDOCK_PALLET_RATE + CONFIG.BACKHAUL_PALLET_RATE) * ISNULL(@AVERAGE_PALLETS_POS, 0)) / (CASE WHEN @AVERAGE_PO_WEIGHT = 0 THEN 1 ELSE @AVERAGE_PO_WEIGHT END)) 
															+ @CALC_ALL_IN_RATE / (CASE WHEN @PROJECTED_LOAD_WEIGHT = 0 OR @PROJECTED_LOAD_WEIGHT IS NULL THEN 1 ELSE @PROJECTED_LOAD_WEIGHT END)) + CONFIG.ESTIMATED_LUMPER_EXPENSE * @STOPS) + CONFIG.ESTIMATED_ACCESSORIAL_EXPENSE)
												 END
										 WHEN @METHOD_ID = 3 --DIRECT(3)
											THEN CASE	WHEN (@AVERAGE_PO_WEIGHT = 0 OR @AVERAGE_PO_WEIGHT IS NULL) OR (@CALC_ALL_IN_RATE = 0 OR @CALC_ALL_IN_RATE IS NULL) THEN NULL 
														ELSE ((@CALC_ALL_IN_RATE / (CASE WHEN @PROJECTED_LOAD_WEIGHT = 0 OR @PROJECTED_LOAD_WEIGHT IS NULL THEN 1 ELSE @PROJECTED_LOAD_WEIGHT END)) + CONFIG.ESTIMATED_LUMPER_EXPENSE + CONFIG.ESTIMATED_ACCESSORIAL_EXPENSE)
												 END
										WHEN @METHOD_ID = 5 --DIRECT CROSSDOCK(5)
											THEN CASE	WHEN (@AVERAGE_PO_WEIGHT = 0 OR @AVERAGE_PO_WEIGHT IS NULL) OR (@CALC_ALL_IN_RATE = 0 OR @CALC_ALL_IN_RATE IS NULL) THEN NULL 
														ELSE ((((((CONFIG.CROSSDOCK_PALLET_RATE) * ISNULL(@AVERAGE_PALLETS_POS, 0)) / (CASE WHEN @AVERAGE_PO_WEIGHT = 0 THEN 1 ELSE @AVERAGE_PO_WEIGHT END)) 
															+ @CALC_ALL_IN_RATE / (CASE WHEN @PROJECTED_LOAD_WEIGHT = 0 OR @PROJECTED_LOAD_WEIGHT IS NULL THEN 1 ELSE @PROJECTED_LOAD_WEIGHT END)) + CONFIG.ESTIMATED_LUMPER_EXPENSE * @STOPS) + CONFIG.ESTIMATED_ACCESSORIAL_EXPENSE)
												 END
										 END
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR 
			INNER JOIN FP_DEFAULT_CONFIG AS CONFIG
				ON CONFIG.FP_DEFAULT_CONFIG_ID = (SELECT TOP 1 CONFIG.FP_DEFAULT_CONFIG_ID FROM FP_DEFAULT_CONFIG AS CONFIG) --TODOMAZE VENDOR.TMS_WHS_ID	
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID
			AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)

		--STEP 4 CALCULATIONS 
		SELECT  --@PROPOSED_TOTAL_EXPENSE
				@PROPOSED_TOTAL_EXPENSE = ((@LANDED_EXPENSE_PER_LB * @AVERAGE_PO_WEIGHT) * @TOTAL_POS),
				--TOTAL_MARGIN
				--@TOTAL_MARGIN = ((VEN.TOTAL_ALLOWANCE + VEN.TOTAL_BOOKED_FREIGHT) - ((@LANDED_EXPENSE_PER_LB * @AVERAGE_PO_WEIGHT) * @TOTAL_POS)),			
				--PROPOSED_FREIGHT_PER_LB
				@PROPOSED_FREIGHT_PER_LB = CASE WHEN @BOOKED_FRIEGHT_OVERRIDE = 1 THEN @PROPOSED_BOOKED_FRIEGHT_PER_LB
											--ELSE (@LANDED_EXPENSE_PER_LB * (ISNULL(FORM.TOOL_MARGIN_TARGET, 0) + ISNULL(FORM.TOOL_COOLER_FREEZER_UPCHARGE, 0) + 1) + ISNULL(FORM.TOOL_PFF_PFH_UPCHARGE, 0)) END
												ELSE (@LANDED_EXPENSE_PER_LB * (ISNULL(FORM.TOOL_COOLER_FREEZER_UPCHARGE, 0) + 1) + ISNULL(FORM.TOOL_MARGIN_TARGET, 0) + ISNULL(FORM.TOOL_PFF_PFH_UPCHARGE, 0)) END
		FROM FP_FREIGHT_FORM AS FORM
		WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_ID

		--STEP 5 CALCULATIONS
		SELECT  --PROPOSED_BOOKED_FREIGHT
				@PROPOSED_BOOKED_FREIGHT = (@PROPOSED_FREIGHT_PER_LB * @AVERAGE_PO_WEIGHT * @TOTAL_POS)

		--STEP 6 CALCULATIONS 
		SELECT	--PROPOSED_PROJECTED_MARGIN
				@PROPOSED_PROJECTED_MARGIN = (@PROPOSED_TOTAL_ALLOWANCE + @PROPOSED_BOOKED_FREIGHT) - @PROPOSED_TOTAL_EXPENSE

	END
	
	ELSE 
	BEGIN
		--VSP SPECFIC CALCULATIONS
		SELECT  --PROJECTED_LOAD_WEIGHT
				@PROJECTED_LOAD_WEIGHT = CASE WHEN @PROJECTED_LOAD_WEIGHT_OVERRIDE = 1 THEN @PROJECTED_LOAD_WEIGHT
												ELSE NULL
										 END,
				@PROPOSED_FREIGHT_PER_LB =	CASE WHEN @BOOKED_FRIEGHT_OVERRIDE = 1 THEN @PROPOSED_BOOKED_FRIEGHT_PER_LB
												ELSE NULL 
											END
		FROM FP_FREIGHT_FORM AS FORM
			INNER JOIN FP_DEFAULT_CONFIG AS CONFIG --TODOMAZE this isn't used??/ 
				ON CONFIG.FP_DEFAULT_CONFIG_ID = (SELECT  TOP 1 CONFIG.FP_DEFAULT_CONFIG_ID FROM FP_DEFAULT_CONFIG AS CONFIG)
		WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_ID
	END 

	--FINAL TABLE UPDATE
	UPDATE VENDOR
	SET VENDOR.FP_FF_PICKUP_LOCATIONS_ID = @PICKUP_LOCATION_ID, 
		VENDOR.FP_FF_METHOD_ID = @METHOD_ID,
		VENDOR.CROSSDOCK_WHS_ID = @CROSSDOCK_ID,
		VENDOR.TOTAL_POS = @TOTAL_POS,
		VENDOR.PROJECTED_LOAD_WEIGHT = @PROJECTED_LOAD_WEIGHT,
		VENDOR.AVERAGE_PALLETS_PER_PO = @AVERAGE_PALLETS_POS,
		VENDOR.AVERAGE_PO_WEIGHT = @AVERAGE_PO_WEIGHT,
		VENDOR.PROPOSED_ALLOWANCE_PER_LB = @PROPOSED_ALLOWANCE_PER_LB,
		VENDOR.PROPOSED_FREIGHT_PER_LB = @PROPOSED_FREIGHT_PER_LB,
		VENDOR.PROPOSED_BOOKED_FREIGHT = @PROPOSED_BOOKED_FREIGHT,
		VENDOR.BOOKED_FREIGHT_OVERRIDE = @BOOKED_FRIEGHT_OVERRIDE,
		VENDOR.CR_RATE_ID = @CR_RATE_ID,
		VENDOR.PROPOSED_TOTAL_ALLOWANCE = @PROPOSED_TOTAL_ALLOWANCE, 
		VENDOR.LANDED_EXPENSE_PER_LB = @LANDED_EXPENSE_PER_LB,
		VENDOR.PROPOSED_TOTAL_EXPENSE = @PROPOSED_TOTAL_EXPENSE,
		VENDOR.CALC_RATE = @CALC_RATE,
		VENDOR.CALC_ALL_IN_RATE = @CALC_ALL_IN_RATE,
		--VENDOR.TOTAL_ALLOWANCE = @TOTAL_ALLOWANCE,
		--VENDOR.TOTAL_BOOKED_FREIGHT = @TOTAL_BOOKED_FREIGHT,
		VENDOR.PROPOSED_PROJECTED_MARGIN = @PROPOSED_PROJECTED_MARGIN,
		--VENDOR.TOTAL_MARGIN = @TOTAL_MARGIN, 
		VENDOR.AVERAGE_PO_UNITS = @PROJECTED_PO_UNITS,
		VENDOR.PROJECTED_LOAD_WEIGHT_OVERRIDE = @PROJECTED_LOAD_WEIGHT_OVERRIDE
	FROM FP_FREIGHT_FORM_VENDOR AS VENDOR
	where VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID

	--STEP 7 CALCULATIONS	
	SELECT  --EAST_BLENDED_FREIGHT_RATE
			@EAST_BLENDED_FREIGHT_RATE = AVG(ISNULL(VENDOR.PROPOSED_FREIGHT_PER_LB, 0))
	FROM FP_FREIGHT_FORM AS FORM
	INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR
		ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID
		AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)
	INNER JOIN TMS_WHS AS WHS 
		ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID
	WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_ID
		AND WHS.SOURCE_SYSTEM='UBS'
		AND VENDOR.FP_FF_METHOD_ID <> 4 --VSP
	GROUP BY FORM.FP_FREIGHT_FORM_ID, FORM.EAST_BLENDED_FREIGHT_RATE;

	UPDATE FORM
	SET EAST_BLENDED_FREIGHT_RATE = @EAST_BLENDED_FREIGHT_RATE
	FROM FP_FREIGHT_FORM AS FORM
	WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_ID

	--STEP 8 CALCULATIONS	
	SELECT  --GILROC_BLENDED_FREIGHT_RATE
			@GILROC_BLENDED_FREIGHT_RATE = AVG(ISNULL(VENDOR.PROPOSED_FREIGHT_PER_LB, 0))
	FROM FP_FREIGHT_FORM AS FORM
	INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR
		ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID
		AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)
	INNER JOIN TMS_WHS AS WHS 
		ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID
	WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_ID
	AND WHS.TMS_WHS_ID IN (1, 114)
	GROUP BY FORM.FP_FREIGHT_FORM_ID, FORM.EAST_BLENDED_FREIGHT_RATE;

	UPDATE FORM
	SET GILROC_BLENDED_FREIGHT_RATE = @GILROC_BLENDED_FREIGHT_RATE
	FROM FP_FREIGHT_FORM AS FORM
	WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_ID

	--NO RATE CHECK
	IF(@CR_RATE_ID IS NULL and @METHOD_ID = 3)
	BEGIN
		INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID)
		SELECT 'No Rate', 'No Rate found for this Warehouse ' + WHS.WHS_NUMBER + ' ' + WHS.NAME + '', 'CR_RATE_ID', @FORM_ID
		FROM FP_FREIGHT_FORM_VENDOR AS VENDOR  
			INNER JOIN TMS_WHS AS WHS  
				ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID
		WHERE VENDOR.FP_FREIGHT_FORM_VENDOR_ID = @FORM_VENDOR_ID
	END

    --RETURN ERROR LOG
     SELECT * FROM @ERROR_LOG
END
GO


