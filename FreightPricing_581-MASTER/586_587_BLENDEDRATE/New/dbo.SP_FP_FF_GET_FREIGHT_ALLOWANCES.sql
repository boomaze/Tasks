USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_FF_GET_FREIGHT_ALLOWANCES]    Script Date: 9/27/2022 10:48:13 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

  
/* =============================================    
-- Author:  Kaushik Talasila    
-- Create date: 1/15/2019    
-- Description: Gets a list of all Freight Pickup Allowances associated to the Form  
  
--MODIFICATION LIST  
 05/17/2019 - BK - ADDED SORTING  
 07/30/2019 - KT - Added CURRENT_ALLOWANCE_TYPE_DESCRIPTION and CURRENT_ALLOWANCE  
 09/09/2019 - TWL - SUBMIT PARTIAL FORM CHANGE  
 10/16/2019 - KT - FIXED CASE STATEMENT TO SHOW CALCULATION WHEN IMPLIED RATE FLAG IS TRUE AND INCREASED VARCHAR LENGTH  
 11/04/2019 - KT - Warehouse List added to Select Statement  
 11/08/2019 - KT - Modify Effective Date to string  
 11/19/2019 - KT - Modify select statement to use TMS_ALLOWANCE_TYPE_ID from Vendor table  
 04/14/2020 - BK - Added VEN.BOOKED_FREIGHT_PER_LB AS CURRENT_FREIGHT_RATE
 01/04/2020 - BK - Added new column CURRENT_FREIGHT_RATE  
-- =============================================  */  
ALTER PROCEDURE [dbo].[SP_FP_FF_GET_FREIGHT_ALLOWANCES]    
 -- Add the parameters for the stored procedure here    
 @FORM_ID BIGINT = NULL,  
 @Sort_Direction VARCHAR(250) = 'ASC',  
 @Sort_Expression VARCHAR(250) = 'WAREHOUSE_NAME',  
 @SOURCE_SYSTEM AS VARCHAR(50) = ''  
AS  
BEGIN  
 -- SET NOCOUNT ON added to prevent extra result sets from    
 -- interfering with SELECT statements.    
 SET NOCOUNT ON;  
    
   SELECT * FROM (  
   -- Insert statements for procedure here  
   SELECT  
     FFV.FP_FREIGHT_FORM_VENDOR_ID,  
     FFV.TMS_WHS_ID,  
     FFV.OFFERED_PICKUP_ALLOWANCE,  
     CASE WHEN FORM.IS_IMPLIED_RATE = 1  
      THEN CAST ('(Delivered - FOB) / Case Weight' as VARCHAR(100))       
     ELSE  
      CASE WHEN FORM.REJECTED_VSP_FLAG = 1  
    THEN CAST('VSP' AS VARCHAR)  
      WHEN FFV.FP_FF_METHOD_ID = 4  
    THEN CAST('VSP' AS VARCHAR)  
      WHEN WHS.SOURCE_SYSTEM = 'UBS'  
       THEN '$' + CAST(CAST(FORM.EAST_BLENDED_FREIGHT_RATE AS DECIMAL(18,3)) AS VARCHAR)  
      WHEN WHS.TMS_WHS_ID IN (1, 114)  
       THEN '$' + CAST(CAST(FORM.GILROC_BLENDED_FREIGHT_RATE AS DECIMAL(18,3)) AS VARCHAR)       
      WHEN WHS.TMS_WHS_ID IN (168, 169)  
       THEN '$' + CAST(CAST(FORM.HARCAR_BLENDED_FREIGHT_RATE AS DECIMAL(18,3)) AS VARCHAR)       
	  WHEN WHS.TMS_WHS_ID IN (160, 214)  
       THEN '$' + CAST(CAST(FORM.STKSGM_BLENDED_FREIGHT_RATE AS DECIMAL(18,3)) AS VARCHAR)       
	  WHEN WHS.TMS_WHS_ID IN (178, 186)  
       THEN '$' + CAST(CAST(FORM.ANNSER_BLENDED_FREIGHT_RATE AS DECIMAL(18,3)) AS VARCHAR)       
      ELSE  
       '$' + CAST(CAST(FFV.PROPOSED_FREIGHT_PER_LB AS DECIMAL(18,3)) AS VARCHAR)  
      END   
     END AS BOOKED_FREIGHT_PER_LB,  
     VEN.TMS_VENDOR_ID,  
     VEN.NAME as VENDOR_NAME,  
     VEN.VENDOR_NUMBER,  
     (WHS.WHS_NUMBER + ' - ' + WHS.NAME) AS WAREHOUSE_NAME,  
     FFV.FP_FF_PICKUP_LOCATIONS_ID,  
     VEN.TMS_ALLOWANCE_TYPE_ID,  
     FFV.AVERAGE_PO_WEIGHT,  
     FFV.AVERAGE_PALLETS_PER_PO,  
     FFV.PROPOSED_ALLOWANCE_PER_LB,  
     CASE WHEN VEN.TMS_VENDOR_ID IS NOT NULL  
      THEN VEN.SOURCE_SYSTEM  
     WHEN VEN.TMS_VENDOR_ID IS NULL  
      THEN WHS.SOURCE_SYSTEM  
     END AS SOURCE_SYSTEM,  
     (SELECT ALWNCETYPE.DESCRIPTION  
     FROM FP_FF_ALLOWANCE_TYPE ALWNCETYPE   
     WHERE FFV.CURRENT_ALLOWANCE_TYPE_ID = ALWNCETYPE.FP_FF_ALLOWANCE_TYPE_ID) AS CURRENT_ALLOWANCE_TYPE_DESCRIPTION,  
     FFV.CURRENT_ALLOWANCE,  
     convert(varchar, cast(FFV.EFFECTIVE_DATE as date), 1) as EFFECTIVE_DATE,  
     FFV.PROCESSED_FLAG,  
     STUFF((SELECT DISTINCT ',' +  CAST (FRMV.TMS_WHS_ID AS varchar)  
    FROM FP_FREIGHT_FORM_VENDOR FRMV  
    WHERE FRMV.FP_FREIGHT_FORM_ID = @FORM_ID  
    AND (FRMV.IS_DELETED IS NULL OR FRMV.IS_DELETED = 0)  
    FOR XML PATH('')), 1, 1, '') AS WAREHOUSE_LIST,  
     --VEN.BOOKED_FREIGHT_PER_LB AS CURRENT_FREIGHT_RATE  
	 FFV.CURRENT_FREIGHT_RATE
     FROM FP_FREIGHT_FORM_VENDOR FFV  
     JOIN FP_FREIGHT_FORM FORM ON FFV.FP_FREIGHT_FORM_ID = FORM.FP_FREIGHT_FORM_ID  
     JOIN TMS_WHS WHS ON FFV.TMS_WHS_ID = WHS.TMS_WHS_ID  
     LEFT JOIN TMS_VENDOR VEN ON VEN.TMS_VENDOR_ID = FFV.TMS_VENDOR_ID  
     WHERE FFV.FP_FREIGHT_FORM_ID = @FORM_ID  
     AND (FFV.IS_DELETED IS NULL OR FFV.IS_DELETED = 0)  
     AND ((@SOURCE_SYSTEM IS NULL OR @SOURCE_SYSTEM = '') OR @SOURCE_SYSTEM = WHS.SOURCE_SYSTEM)  
    --ORDER BY WHS.WHS_NUMBER ASC;  
    ) result  
    ORDER BY  
     CASE @Sort_Direction  
          WHEN 'DESC' THEN CASE @Sort_Expression  
               WHEN 'WAREHOUSE_NAME' THEN ROW_NUMBER() OVER(ORDER BY WAREHOUSE_NAME DESC)  
               WHEN 'SOURCE_SYSTEM' THEN ROW_NUMBER() OVER(ORDER BY SOURCE_SYSTEM DESC)  
               WHEN 'VENDOR_NAME' THEN ROW_NUMBER() OVER(ORDER BY VENDOR_NAME DESC)  
               WHEN 'VENDOR_NUMBER' THEN ROW_NUMBER() OVER(ORDER BY VENDOR_NUMBER DESC)  
               WHEN 'AVERAGE_PO_WEIGHT' THEN ROW_NUMBER() OVER(ORDER BY AVERAGE_PO_WEIGHT DESC)  
               WHEN 'AVERAGE_PALLETS_PER_PO' THEN ROW_NUMBER() OVER(ORDER BY AVERAGE_PALLETS_PER_PO DESC)  
      WHEN 'PROPOSED_ALLOWANCE_PER_LB' THEN ROW_NUMBER() OVER(ORDER BY VENDOR_NUMBER DESC)  
               WHEN 'BOOKED_FREIGHT_PER_LB' THEN ROW_NUMBER() OVER(ORDER BY AVERAGE_PO_WEIGHT DESC)  
      WHEN 'CURRENT_ALLOWANCE_TYPE_DESCRIPTION' THEN ROW_NUMBER() OVER(ORDER BY CURRENT_ALLOWANCE_TYPE_DESCRIPTION DESC)  
      WHEN 'CURRENT_ALLOWANCE' THEN ROW_NUMBER() OVER(ORDER BY CURRENT_ALLOWANCE DESC)  
            END  
          ELSE CASE @Sort_Expression  
               WHEN 'WAREHOUSE_NAME' THEN ROW_NUMBER() OVER(ORDER BY WAREHOUSE_NAME ASC)  
               WHEN 'SOURCE_SYSTEM' THEN ROW_NUMBER() OVER(ORDER BY SOURCE_SYSTEM ASC)  
               WHEN 'VENDOR_NAME' THEN ROW_NUMBER() OVER(ORDER BY VENDOR_NAME ASC)  
               WHEN 'VENDOR_NUMBER' THEN ROW_NUMBER() OVER(ORDER BY VENDOR_NUMBER ASC)  
               WHEN 'AVERAGE_PO_WEIGHT' THEN ROW_NUMBER() OVER(ORDER BY AVERAGE_PO_WEIGHT ASC)  
               WHEN 'AVERAGE_PALLETS_PER_PO' THEN ROW_NUMBER() OVER(ORDER BY AVERAGE_PALLETS_PER_PO ASC)  
      WHEN 'PROPOSED_ALLOWANCE_PER_LB' THEN ROW_NUMBER() OVER(ORDER BY VENDOR_NUMBER ASC)  
               WHEN 'BOOKED_FREIGHT_PER_LB' THEN ROW_NUMBER() OVER(ORDER BY AVERAGE_PO_WEIGHT ASC)  
      WHEN 'CURRENT_ALLOWANCE_TYPE_DESCRIPTION' THEN ROW_NUMBER() OVER(ORDER BY CURRENT_ALLOWANCE_TYPE_DESCRIPTION ASC)  
      WHEN 'CURRENT_ALLOWANCE' THEN ROW_NUMBER() OVER(ORDER BY CURRENT_ALLOWANCE ASC)  
       END  
 END  
END  
    
GO


