USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_INSERT_INTO_FP_PRICING_OUT]    Script Date: 9/27/2022 10:47:43 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* =====================================================================================================
 Author:		Johana Aleman
 Create date:   7/22/2019
 Description:	Insert ALW/FRT record(s) into FP_PRICING_OUT table and it is called
				from SP_FP_NEXT_STAGE_VALIDATION_AND_SUBMIT right after the form is 
				update to TMS_STATUS_ID=66(COMPLETED) OR TMS_STATUS_ID=65(Rejected: VSP)
				When status is 65 then send DRTE = VSP and Null out freight and allowance.
				Form with IS_IMPLIED_RATE =1 should be excluded from integration. 
 Log Update:
 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
 11/12/19	JAleman		We are not sending updates for Rejected forms(TMS_STATUS_ID=65)to the Host system
						when FP_FF_METHOD_ID = 4 reset value to 0 for WBS execpt Gil/Roc
 11/14/19	JAleman		Added the MKF(York Freight) identifier for YORK whs. Also, generate data for the DCs that doesnt 
						have entry in the Form but in the TMS_VENDOR table		
 11/21/19	JAleman		When FP_FF_ALLOWANCE_TYPE = 4(% Off Invoice), we multiplied the OFFERED_PICKUP_ALLOWANCE * 100		
 12/23/19	JAleman		reference TMS_WHS_ID from WHS_REFERENCE_DATA table										
 ==============================================================================================================================*/
ALTER PROCEDURE [dbo].[SP_FP_INSERT_INTO_FP_PRICING_OUT] 
(
	@FP_FREIGHT_FORM_ID BIGINT
	, @TMS_STATUS_ID BIGINT 
	, @SOURCE_SYSTEM varchar(max) -- 'UBS,WBS'
)
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/******************************************************************************************************************************************
Declare @FP_FREIGHT_FORM_ID bigint = 7
	, @TMS_STATUS_ID BIGINT = 66
	, @SOURCE_SYSTEM varchar(max) = 'UBS,WBS'

	EXEC SP_FP_INSERT_INTO_FP_PRICING_OUT @FP_FREIGHT_FORM_ID, @TMS_STATUS_ID, @SOURCE_SYSTEM
********************************************************************************************************************************************/
	SELECT * 
	INTO #CompletedForm
	FROM FP_FREIGHT_FORM fff
	WHERE FP_FREIGHT_FORM_ID = @FP_FREIGHT_FORM_ID
	--	AND fff.TMS_STATUS_ID = @TMS_STATUS_ID		
		AND (fff.IS_IMPLIED_RATE = 0 OR fff.IS_IMPLIED_RATE IS NULL)

	CREATE CLUSTERED INDEX #IDX_FP_FREIGHT_FORM ON #CompletedForm(FP_FREIGHT_FORM_ID)

	SELECT DISTINCT cf.FP_FREIGHT_FORM_ID
		,  fffv.EFFECTIVE_DATE  ---It should be one Effective_date per Source System
		,  tv.TMS_VENDOR_ID
		,  tv.VENDOR_NUMBER
		,  wrd.WHS_Number AS HOST_WAREHOUSE
		,  CASE WHEN ISNULL(cf.FP_FF_ALLOWANCE_TYPE_ID,0) IN (0,1) OR fffv.FP_FF_METHOD_ID = 4 THEN 0 ELSE 1 END AS IS_ALLOWANCE_FLAG_ON --0:flag is off
		,  CASE WHEN ISNULL(cf.FP_FF_ALLOWANCE_TYPE_ID,0) IN (0,1) OR fffv.FP_FF_METHOD_ID = 4 THEN 1 ELSE cf.FP_FF_ALLOWANCE_TYPE_ID END as TMS_ALLOWANCE_TYPE_ID --1:No allowance
		,  CASE WHEN fffv.FP_FF_METHOD_ID = 4 THEN 0 ELSE CASE WHEN cf.FP_FF_ALLOWANCE_TYPE_ID = 4 THEN fffv.[OFFERED_PICKUP_ALLOWANCE] * 100 ELSE fffv.[OFFERED_PICKUP_ALLOWANCE] END END as ALLOWANCE
		,  CASE WHEN tw.SOURCE_SYSTEM = 'UBS' THEN cf.EAST_BLENDED_FREIGHT_RATE 
				WHEN tw.TMS_WHS_ID IN (1, 114) THEN cf.GILROC_BLENDED_FREIGHT_RATE 
				WHEN tw.TMS_WHS_ID IN (168, 169) THEN cf.HARCAR_BLENDED_FREIGHT_RATE 
				WHEN tw.TMS_WHS_ID IN (160, 214) THEN cf.STKSGM_BLENDED_FREIGHT_RATE 
				WHEN tw.TMS_WHS_ID IN (178, 186) THEN cf.ANNSER_BLENDED_FREIGHT_RATE 
				WHEN fffv.FP_FF_METHOD_ID = 4 THEN 0
		   ELSE fffV.[PROPOSED_FREIGHT_PER_LB] END AS BOOKED_FREIGHT_PER_LB
		,  CASE WHEN fffv.FP_FF_METHOD_ID = 4 THEN 'VSP' ELSE ffpl.D_RTE END AS D_RTE
		,  CASE ffpl.PICKUP_DAY WHEN 0 THEN 1 --'Monday'
								  WHEN 1 THEN 2 --'Tuesday'
								  WHEN 2 THEN 3 --'Wednesday'
								  WHEN 3 THEN 4 --'Thursday'
								  WHEN 4 THEN 5 --'Friday'
								  WHEN 5 THEN 6--'Saturday'
								  WHEN 6 THEN 7--'Sunday' 
			END AS PICKUP_DAY
		,  tw.SOURCE_SYSTEM
		,  tw.TMS_WHS_ID
		,  CASE WHEN fffv.TMS_WHS_ID = 12 THEN ISNULL(fffv.PROPOSED_FREIGHT_PER_LB,0) END AS TRUE_YORK
	into #DataSet
	FROM #CompletedForm cf
		INNER JOIN FP_FREIGHT_FORM_VENDOR fffv
			ON cf.FP_FREIGHT_FORM_ID = fffv.FP_FREIGHT_FORM_ID
				AND (fffv.IS_DELETED IS NULL OR fffv.IS_DELETED = 0)
		LEFT JOIN TMS_VENDOR tv
			ON fffv.TMS_VENDOR_ID = tv.TMS_VENDOR_ID 
				AND fffv.TMS_WHS_ID = tv.TMS_WHS_ID
				AND (tv.IS_DELETED IS NULL OR tv.IS_DELETED = 0)
		INNER JOIN TMS_WHS tw
			ON tv.TMS_WHS_ID = tw.TMS_WHS_ID				
		INNER JOIN WHS_REFERENCE_DATA wrd
			ON tw.SOURCE_SYSTEM = wrd.SOURCE_SYSTEM
				AND	tw.TMS_WHS_ID = wrd.TMS_WHS_ID
		LEFT JOIN [dbo].[FP_FF_PICKUP_LOCATIONS] ffpl
			ON ffpl.FP_FF_PICKUP_LOCATIONS_ID = fffv.FP_FF_PICKUP_LOCATIONS_ID
				AND (ffpl.IS_DELETED IS NULL OR ffpl.IS_DELETED = 0)
		CROSS APPLY dbo.fnParseStack(@SOURCE_SYSTEM, 'C') sc
	WHERE sc.c = tw.SOURCE_SYSTEM 

	/*Generate the data for the UBS DCs that are not in the form. The Host system needs all of them*/
	SELECT DISTINCT cast(null as bigint) as FP_FREIGHT_FORM_ID
		,  cast(null as date) as EFFECTIVE_DATE 
		,  t.TMS_VENDOR_ID
		,  t.VENDOR_NUMBER
		,  wrd.WHS_Number AS HOST_WAREHOUSE
		,  cast(null as bit) as IS_ALLOWANCE_FLAG_ON --0:flag is off
		,  cast(null as int) as TMS_ALLOWANCE_TYPE_ID --1:No allowance
		,  cast(null as decimal(18, 6)) as ALLOWANCE
		,  cast(null as decimal(18, 6)) as BOOKED_FREIGHT_PER_LB
		,  cast(null as varchar) AS D_RTE
		,  cast(null as varchar) AS PICKUP_DAY
		,  'UBS' AS SOURCE_SYSTEM
		,  tw.TMS_WHS_ID
		,  cast(null as decimal(18, 6)) as TRUE_YORK
	INTO #DCsNOIntheForm
	FROM
	(
		SELECT distinct tv.TMS_WHS_ID, tv.TMS_VENDOR_ID, tv.VENDOR_NUMBER
		FROM TMS_WHS tw		
			LEFT JOIN #DataSet d
				ON tw.TMS_WHS_ID = d.TMS_WHS_ID
			LEFT JOIN TMS_VENDOR tv
				ON d.VENDOR_NUMBER = tv.VENDOR_NUMBER		
		WHERE tw.INCLUDE_IN_FREIGHT_PRICING = 1 
			AND TW.SOURCE_SYSTEM = 'UBS'
			AND tv.TMS_WHS_ID NOT IN (SELECT TMS_WHS_ID FROM #DataSet WHERE SOURCE_SYSTEM = 'UBS')	
	)t
	INNER JOIN TMS_WHS tw	
		ON t.TMS_WHS_ID = tw.TMS_WHS_ID
			AND tw.INCLUDE_IN_FREIGHT_PRICING = 1 
			AND TW.SOURCE_SYSTEM = 'UBS'
	INNER JOIN WHS_REFERENCE_DATA wrd		
		ON tw.SOURCE_SYSTEM = wrd.SOURCE_SYSTEM
			AND	tw.TMS_WHS_ID = wrd.TMS_WHS_ID
	
	--Update the fields from the #Dateset table
	UPDATE #DCsNOIntheForm
	SET FP_FREIGHT_FORM_ID = d.FP_FREIGHT_FORM_ID
	,	EFFECTIVE_DATE = d.EFFECTIVE_DATE
	,	VENDOR_NUMBER = d.VENDOR_NUMBER
	,	IS_ALLOWANCE_FLAG_ON = d.IS_ALLOWANCE_FLAG_ON
	,	TMS_ALLOWANCE_TYPE_ID = d.TMS_ALLOWANCE_TYPE_ID
	,	BOOKED_FREIGHT_PER_LB = d.BOOKED_FREIGHT_PER_LB
	,	TRUE_YORK = d.TRUE_YORK
	FROM #DCsNOIntheForm t
		INNER JOIN #DataSet	d
			ON d.VENDOR_NUMBER = t.VENDOR_NUMBER
				AND d.SOURCE_SYSTEM = 'UBS'	

	SELECT * 
	INTO #output 
	FROM (
		SELECT 'ALW' as IDENTIFIER
			,  FP_FREIGHT_FORM_ID
			,  VENDOR_NUMBER
			,  HOST_WAREHOUSE 
			,  EFFECTIVE_DATE
			,  IS_ALLOWANCE_FLAG_ON
			,  TMS_ALLOWANCE_TYPE_ID
			,  ALLOWANCE AS VALUE
			,  D_RTE
			,  PICKUP_DAY
			, SOURCE_SYSTEM
		FROM #DataSet

		UNION ALL
-----------------------------------------------------------------FRT---------------------------------------------
		SELECT 'FRT' as IDENTIFIER
			,  FP_FREIGHT_FORM_ID
			,  VENDOR_NUMBER
			,  HOST_WAREHOUSE
			,  EFFECTIVE_DATE
			,  NULL as IS_ALLOWANCE_FLAG_ON
			,  NULL AS TMS_ALLOWANCE_TYPE_ID
			,  BOOKED_FREIGHT_PER_LB AS VALUE
			,  D_RTE
			,  PICKUP_DAY
			, SOURCE_SYSTEM
		FROM #DataSet

		UNION ALL

		SELECT 'FRT' as IDENTIFIER
			,  FP_FREIGHT_FORM_ID
			,  VENDOR_NUMBER
			,  HOST_WAREHOUSE
			,  EFFECTIVE_DATE
			,  NULL as IS_ALLOWANCE_FLAG_ON
			,  NULL AS TMS_ALLOWANCE_TYPE_ID
			,  BOOKED_FREIGHT_PER_LB AS VALUE
			,  D_RTE
			,  PICKUP_DAY
			, SOURCE_SYSTEM
		FROM #DCsNOIntheForm  --Missing DCs in the form we send them with the same values as the others DC. For UBS only
----------------------------------------------------------------FRT-------------------------------------------------		
		UNION ALL

		SELECT 'MKF' as IDENTIFIER
			,  FP_FREIGHT_FORM_ID
			,  VENDOR_NUMBER
			,  HOST_WAREHOUSE
			,  EFFECTIVE_DATE
			,  NULL as IS_ALLOWANCE_FLAG_ON
			,  NULL AS TMS_ALLOWANCE_TYPE_ID
			,  TRUE_YORK AS VALUE
			,  D_RTE
			,  PICKUP_DAY
			, SOURCE_SYSTEM
		FROM #DataSet
		WHERE TMS_WHS_ID = 12  /*Send this value for YORK WHS*/
	)t

	----Insert into the FP_PRICING_OUT table the Form information
	INSERT INTO FP_PRICING_OUT([IDENTIFIER]
      ,[FP_FREIGHT_FORM_ID]
      ,[VENDOR_NUMBER]
      ,[HOST_WAREHOUSE]
      ,[EFFECTIVE_DATE]
      ,[IS_ALLOWANCE_FLAG_ON]
      ,[TMS_ALLOWANCE_TYPE_ID]
      ,[VALUE]
      ,[D_RTE]
      ,[PICKUP_DAY]
      ,[SOURCE_SYSTEM]
      ,[CREATED_DATE]
      ,[PROCESS_STATUS]
      ,[PROCESSED_DATETIME])
	SELECT  IDENTIFIER
		,  FP_FREIGHT_FORM_ID
		,  VENDOR_NUMBER
		,  HOST_WAREHOUSE
		,  EFFECTIVE_DATE
		,  IS_ALLOWANCE_FLAG_ON
		,  TMS_ALLOWANCE_TYPE_ID
		,  VALUE
		,  D_RTE
		,  PICKUP_DAY
		, SOURCE_SYSTEM
		, GETDATE() AS CREATED_DATE 
		, 'N' AS PROCESS_STATUS --Status values: N:No Processed ,Z:intermediate, P:complete, E:if it errored
		, NULL AS PROCESSED_DATETIME 
	FROM #output

	DROP TABLE IF EXISTS #DataSet
	DROP TABLE IF EXISTS #CompletedForm
	DROP TABLE IF EXISTS #output
	DROP TABLE IF EXISTS #DCsNOIntheForm 

END


GO


