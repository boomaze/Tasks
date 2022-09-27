USE [TMS]
GO

/****** Object:  StoredProcedure [dbo].[SP_FP_NEXT_STAGE_VALIDATION_AND_SUBMIT]    Script Date: 9/27/2022 10:47:08 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ==============================================================================================================    
 Author: Tim Lewis    
 Create date: 01/18/19    
 Description: Next Stage Process    
  
--MODIFICATION LIST  
 04/04/2019 - BK - ADDED PICKUP LOCATION CHECK FOR EVERY STATUS  
 04/09/2019 - TWL - FIXED VENDOR ASSIGNMENT  
 04/11/2019 - TWL - ADDED LOAWSON NUMBER FOR COMPLETE PROCESS  
 04/15/2019 - TWL - Email status fix  
 04/19/2019 - TWL - User role query change (ON ROL.SEC_ROLES_ID = E_ROL.SEC_ROLES_ID)  
 04/24/2019 - TWL - Fix for email status, and proposed Freight per Lb check   
 04/25/2019 - TWL - Email link url update for QA, UAT, and PROD to use the TMS_ENVIRONMENTS.BASE_URL  
     - Costing and coding email update to NATIONALCOSTING@UNFI.COM  
     - Booked Freight validation for Vendor Confirmation  
 04/30/2019 - TWL - Removed Lawson number validation on form Complete   
 05/01/2019 - TWL - DYNAMIC EMAILFROM BASED OFF ENVIORMENT  
 05/01/2019 - TWL - backhaul email   
 05/07/2019 - TWL - backhaul email update- method check   
 05/22/2019 - KT - Added Check for SM Name and Supplier Name for each status change refactor  
 06/19/2019 - TWL - Added York WHS Check  
 06/27/2019 - BK - Added Form Vendor or WHS check  
 07/17/2019   TWL  Change to match TMS_Enviorments.Short_Name for QAII & DEVII  
 08/01/2019 - KT - Added validation for Freight Analyst starting at IBL initial analysis  
 08/01/2019 - TWL - On form completion insert record into FP_PRICING_OUT table using SP  
     Rejected: VSP status Added  
     On form VSP reject insert record into FP_PRICING_OUT table using SP  
 08/22/2019 - JA - Set the email from using the TMS_ENVIRONMENTS table  
 09/09/2019 - twl - submit by source system  
 09/16/2019 - KT - Check to see if D-Route and Pickup Day has been entered for Pickup Locations that have warehouses attached  
 09/17/2019 - TWL - Prevent the form from being marked as completed if all form vendors have not been Processed  
 10/16/2019 - TWL - check whs has vendor assigned to it based off source system  
 10/16/2019 - TWL - Modified pickup, and d_roud count for validation  
 10/29/2019 - KT  - Freight Analyst Check at SRM Vendor Confirmation and IBL: VSP Confirmation  
 10/30/2019 - TWL - Added source system list to reject click  
 11/01/2019 - TWL - Added Modified by and modified date on form vendor update during complete   
 11/06/2019 - TWL - Added check for form venders to have pickup location assigned to them  
 11/12/2019 - TWL - Removed out log, and altered email for reject VSP status  
 11/12/2019 - TWL - Filter out form vendors with method 4 for missing pickup location  
 11/15/2019 - BK  - Added check for Lawson Number and moved Lawson Number save before form vendor  
 11/12/2019 - TWL - effective date must be greater than todays date  
 11/12/2019 - TWL - validation changes for IBL: Initial Analysis next stage  
 11/22/2019 - KT  - Allowance Type check; Modify Costing and Coding validation; refactor Freigt Analyst Check  
 11/25/2019 - TWL - validation changes for IBL: Initial Analysis next stage  
 12/02/2019 - TWL - Preventing change when error logs are raised in form complete process  
 12/03/2019 - TWL - only one ubs vendor number on a form  
 12/06/2019 - TWL - a source system can only be processsed once per form  
 12/11/2019 - TWL - Prevent sending 'New' for types to the host system  
 04/20/2020 - BK  - Added Next Stage comment  
 07/08/2020 - KT  - Added Freight Change Reason check at IBL: Initial Analysis stage  
 11/04/2020 - BK  - Added Freight Change Reason check at IBL: Final Analysis stage  
 11/05/2020 - BK  - Removed Freight Change Reason check at IBL: Initial Analysis stage  
 11/06/2020 - BK  - Added Freight Change Reason check at Costing and Coding: Closing Process stage  
 11/12/2020 - BK  - Added Freight Change Reason check at SRM: Vendor Confirmation  
 11/27/2020 - BK  - Re-added Freight Change Reason check at IBL: Initial Analysis stage  
 12/04/2020 - BK  - Added Freight Change Reason check at IBL: Revised Analysis stage  
 01/29/2021 - KT  - Added Link to Form when sending Mail to Bakchaul from IBL Initial Analysis --> Backhaul Analysis  
 09/16/2022 - BK  - Added validation for UCS Merchandisers   
==============================================================================================================  */  
ALTER PROCEDURE [dbo].[SP_FP_NEXT_STAGE_VALIDATION_AND_SUBMIT]    
(  
 @FORM_NUM BIGINT = NULL,    
 @USER_ID BIGINT = NULL,    
 @SEND_TO_BACKHAUL BIT = NULL,    
 @VENDOR_NUMBERS VARCHAR(MAX) = NULL,    
 @SERVER_NAME VARCHAR(100) = NULL,  
 @LAWSON_NUMBER BIGINT = NULL,  
 @SOURCE_SYSTEM_AND_EFFECTIVE_DATE_LIST VARCHAR(MAX) = NULL,  
 @NEXT_STAGE_COMMENT VARCHAR(MAX) = NULL  
)    
AS    
BEGIN    
 SET NOCOUNT ON;  
   
 DECLARE @CR VARCHAR(10)  
  
 --Used to put carriage returns in emails  
 SET @CR = '<br>'  
  
 BEGIN TRY  
  --ERROR LOG TABLE    
  DECLARE @ERROR_LOG TABLE (    
   ERROR_ID BIGINT IDENTITY(1,1) primary key,    
   ERROR_MESSGAE_TITLE VARCHAR(1000) NULL,    
   ERROR_MESSAGE_DETAIL VARCHAR(1000) NULL,    
   FIELD_NAME VARCHAR(100) NULL,    
   FORM_ID BIGINT NULL,    
   FORM_VENDOR_ID BIGINT NULL,    
   PICKUP_LOCATION_ID BIGINT NULL    
  )    
    
  DECLARE @FORM_TYPE BIGINT = 0  
  
  SELECT @FORM_TYPE = FP_FF_TYPE_ID  
  FROM FP_FREIGHT_FORM WHERE FP_FREIGHT_FORM_ID = @FORM_NUM  
  
  DECLARE @PICKUPLOCATIONWITHWAREHOUSES_COUNT INT = 0  
  
  SELECT @PICKUPLOCATIONWITHWAREHOUSES_COUNT  = COUNT(*)  
  FROM(SELECT PCK.FP_FF_PICKUP_LOCATIONS_ID  
   FROM FP_FF_PICKUP_LOCATIONS PCK  
    INNER JOIN FP_FREIGHT_FORM_VENDOR AS VEN  
     ON PCK.FP_FF_PICKUP_LOCATIONS_ID = VEN.FP_FF_PICKUP_LOCATIONS_ID  
   WHERE PCK.FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND (PCK.IS_DELETED IS NULL OR PCK.IS_DELETED = 0)  
    AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)  
   GROUP BY PCK.FP_FF_PICKUP_LOCATIONS_ID  
  ) AS PICKUP_COUNT  
  
  -- CHECK TO SEE IF FORM HAS AT LEAST 1 PICKUP LOCATION  
  DECLARE @DROUTE_COUNT INT = 0   
  
  SELECT @DROUTE_COUNT = COUNT(*)  
  FROM(SELECT PCK.FP_FF_PICKUP_LOCATIONS_ID  
   FROM FP_FF_PICKUP_LOCATIONS PCK  
    INNER JOIN FP_FREIGHT_FORM_VENDOR AS VEN  
     ON PCK.FP_FF_PICKUP_LOCATIONS_ID = VEN.FP_FF_PICKUP_LOCATIONS_ID  
   WHERE PCK.FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND PCK.D_RTE IS NOT NULL  
    AND PCK.PICKUP_DAY IS NOT NULL  
    AND (PCK.IS_DELETED IS NULL OR PCK.IS_DELETED = 0)  
    AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)  
   GROUP BY PCK.FP_FF_PICKUP_LOCATIONS_ID  
  ) AS DROUT_COUNT  
  
  -- CHECK TO SEE IF FORM HAS AT LEAST 1 PICKUP LOCATION  
  DECLARE @LOCATION_COUNT INT  
  
  SELECT @LOCATION_COUNT = COUNT(*)   
  FROM FP_FF_PICKUP_LOCATIONS PCK  
  WHERE PCK.FP_FREIGHT_FORM_ID = @FORM_NUM   
   AND (PCK.IS_DELETED IS NULL OR PCK.IS_DELETED = 0)  
    
  --CHECK TO SEE IF SM NAME HAS BEEN ENTERED  
  DECLARE @SMNAMECHECK INT  
  
  SELECT @SMNAMECHECK  = COUNT(*)   
   FROM FP_FREIGHT_FORM   
   WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
    AND TMS_SRM_ID IS NOT NULL  

--CHECK TO SEE IF UCS Merchandisers HAS BEEN ENTERED  
  DECLARE @UCSMerdisersCHECK INT  
  
  SELECT @UCSMerdisersCHECK  = COUNT(*)   
   FROM FP_FF_APPROVAL_STATUS   
   WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND (IS_DELETED IS NULL OR IS_DELETED = 0) 
  
  --CHECK TO SEE IF SUPPLIER NAME HAS BEEN ENTERED  
  DECLARE @SUPPLIERNAMECHECK INT  
  
  SELECT @SUPPLIERNAMECHECK  = COUNT(*)   
   FROM FP_FREIGHT_FORM   
   WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
    AND SUPPLIER_NAME IS NOT NULL  
  
  -- CHECK TO SEE IF FORM HAS AT LEAST 1 FORM VENDOR  
  DECLARE @FORM_VENDORS_COUNT INT  
  
   SELECT @FORM_VENDORS_COUNT = COUNT(*)   
   FROM FP_FREIGHT_FORM_VENDOR   
   WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
  
  --CHECK TO SEE IF FREIGHT ANALYST HAS BEEN ENTERED  
  DECLARE @FREIGHTANALYST INT  
  
  SELECT @FREIGHTANALYST  = COUNT(*)   
   FROM FP_FREIGHT_FORM   
   WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
    AND FREIGHT_ANALYST_USER_ID IS NULL  
  
  --CHECK TO SEE IF FREIGHT CHANGE REASON HAS BEEN ENTERED  
  DECLARE @FREIGHTCHANGEREASON INT  
  
  SELECT @FREIGHTCHANGEREASON  = COUNT(*)   
   FROM FP_FREIGHT_FORM   
   WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
    AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
    AND FP_FF_FREIGHT_CHANGE_REASON_ID IS NULL  
  
  --CHECK TO SEE IF ALLOWANCE TYPE HAS BEEN ENTERED  
  DECLARE @MISSING_ALLOWANCE_TYPE INT  
  
  SELECT @MISSING_ALLOWANCE_TYPE = COUNT(*)  
   FROM FP_FREIGHT_FORM   
   WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
   AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
   AND FP_FF_ALLOWANCE_TYPE_ID IS NULL  
  
  --CHECK TO SEE IF FORM VENDORS MISSING PICKUP LOCATION  
  DECLARE @VENDOR_MISSING_PICKUP_LOCATION INT  
  
  SELECT @VENDOR_MISSING_PICKUP_LOCATION = COUNT(*)  
  FROM FP_FREIGHT_FORM_VENDOR AS VEN  
  WHERE VEN.FP_FREIGHT_FORM_ID = @FORM_NUM  
   AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)  
   AND VEN.FP_FF_PICKUP_LOCATIONS_ID IS NULL  
   AND VEN.FP_FF_METHOD_ID <> 4 --VSP  
  
  IF(@LOCATION_COUNT = 0)  
  --MISSING PICKUP LOCATION    
  BEGIN    
   INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
   SELECT 'Pickup Location missing', 'This Freight Form requires at least 1 pickup location ', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
   FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
  END  
  ELSE IF (@SMNAMECHECK = 0 and @UCSMerdisersCHECK =0 )  
  -- MISSING SM NAME  
  BEGIN    
   INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
   SELECT 'SM Name or UCS Merchandisers is missing', 'This Freight Form requires a SM Name or UCS Merchandisers', 'TMS_SRM_ID', @FORM_NUM, NULL, NULL    
   FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
  END  
  ELSE IF (@SUPPLIERNAMECHECK = 0)  
  -- MISSING SUPPLIER NAME  
  BEGIN    
   INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
   SELECT 'Supplier Name is missing', 'This Freight Form requires a Supplier Name ', 'SUPPLIER_NAME', @FORM_NUM, NULL, NULL    
   FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
  END  
  ELSE IF (@FORM_VENDORS_COUNT = 0)  
  -- MISSING FORM VENDOR  
  BEGIN    
   INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
   SELECT 'At least 1 Vendor or WHS is required to next stage', 'This Freight Form requires a Vendor or WHS', 'FP_FREIGHT_FORM_VENDOR_ID', @FORM_NUM, NULL, NULL    
   FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
  END  
  
  --CHECK IF YORK IS REQUIRED (WHS_ID 12)  
  DECLARE @YORK_CHECK BIT = 0,  
    @UBS_WHS_COUNT INT = 0  
    
  SELECT @UBS_WHS_COUNT = COUNT(*)   
  FROM FP_FREIGHT_FORM_VENDOR AS VEN  
   INNER JOIN TMS_WHS AS WHS  
    ON VEN.TMS_WHS_ID = WHS.TMS_WHS_ID  
  WHERE VEN.FP_FREIGHT_FORM_ID = @FORM_NUM  
   AND WHS.SOURCE_SYSTEM = 'UBS'  
   AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)  
  
  IF(@UBS_WHS_COUNT > 0)  
  BEGIN   
   --IF UBS WHS'S ARE ON THE FORM, WE NEED TO ENSURE YORK IS ALSO ON THE FORM  
   IF NOT EXISTS (SELECT 1   
       FROM FP_FREIGHT_FORM_VENDOR AS VEN  
       WHERE VEN.FP_FREIGHT_FORM_ID = @FORM_NUM     
       AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)  
       AND VEN.TMS_WHS_ID = 12)  
   BEGIN  
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'York Warehouse required', 'This Freight Form requires the York Warehouse to be added', 'SUPPLIER_NAME', @FORM_NUM, NULL, NULL    
   END  
  END  
    
  --GATHER VARIABLES    
  DECLARE @FORM_STATUS_ID BIGINT = NULL,    
   @FORM_TYPE_ID AS BIGINT = NULL,    
   @IS_SRM BIT = 0,    
   @IS_IBL BIT = 0,    
   @IS_C_OR_C BIT = 0,    
   @IS_SUPER_ADMIN BIT = 0,    
   @SRM_EMAIL VARCHAR(100) = '',    
   @SRMC_EMAIL VARCHAR(100) = '',    
   @FREIGHT_ANALYST_EMAIL VARCHAR(100) = '',    
   @FORM_URL VARCHAR(1000) = '',  
   @MISSING_PROPOSED_FREIGHT_PER_LB_COUNT AS INT = 0, --CHECK THAT ALL VENDORS HAVE AN ASSIGNED PROPOSED_FREIGHT_PER_LB  
   @Environment varchar(10),  
   @Base_URL VARCHAR(1000),  
   @EmailFrom VARCHAR(250);  
  
  ----Get Server Environment  
  SELECT @Environment = dbo.fnGetEnvironment()  
  
  ----Get the Base_URL based on the @Environment  
  SELECT @Base_URL =  ISNULL(BASE_URL,'')  
  FROM TMS_ENVIRONMENTS   
  WHERE SHORT_NAME = @Environment        
    
  ----URL CREATION  
  SELECT @FORM_URL =  @Base_URL + 'FreightManager/AddNewFreightForm?FFNum='+ CAST(@FORM_NUM AS VARCHAR)  
  
  --Check the environment and set EMAIL FROM accordingly.  
  SELECT @EmailFrom = [EMAIL_FROM]  
  FROM [dbo].[TMS_ENVIRONMENTS]  
  WHERE SHORT_NAME = @Environment   
    
  ----FORM INFORMATION    
  SELECT @FORM_STATUS_ID = FORM.TMS_STATUS_ID,    
    @FORM_TYPE_ID = FORM.FP_FF_TYPE_ID,    
    @SRM_EMAIL = CASE WHEN SRM.SEC_USERS_ID IS NOT NULL THEN SRM_USR.EMAIL_ADDRESS  
         WHEN SRM.SEC_USERS_ID IS NULL AND BUYER.EMAIL <> 'EMAIL' AND BUYER.EMAIL <> '' THEN BUYER.EMAIL   
        END,  
    @SRMC_EMAIL = SRMC.EMAIL_ADDRESS,  
    @FREIGHT_ANALYST_EMAIL = ANALYST.EMAIL_ADDRESS    
  FROM FP_FREIGHT_FORM AS FORM    
   LEFT JOIN TMS_SRM AS SRM --If we have an SRM ID populated in the Form, we got to get the SRM userId  
    ON FORM.TMS_SRM_ID = SRM.TMS_SRM_ID    
   LEFT JOIN SEC_USERS AS SRM_USR    
    ON SRM.SEC_USERS_ID = SRM_USR.SEC_USERS_ID    
   LEFT JOIN SEC_USERS AS ANALYST    
    ON FORM.FREIGHT_ANALYST_USER_ID = ANALYST.SEC_USERS_ID    
   LEFT JOIN TMS_BUYER AS BUYER  
    ON SRM.TMS_BUYER_ID = BUYER.TMS_BUYER_ID  
   LEFT JOIN SEC_USERS AS SRMC  
    ON FORM.SRMC_USER_ID = SRMC.SEC_USERS_ID  
  WHERE FP_FREIGHT_FORM_ID = @FORM_NUM    
    
  --USER PRIVLEDGES    
  SELECT @IS_SUPER_ADMIN = USR.SUPER_ADMIN,    
    @IS_SRM = CAST((CASE WHEN SUM(CASE WHEN E_ROL.FP_ESCALATION_CLASS = 'A' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) AS BIT),    
    @IS_IBL = CAST((CASE WHEN SUM(CASE WHEN E_ROL.FP_ESCALATION_CLASS = 'B' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) AS BIT),    
    @IS_C_OR_C = CAST((CASE WHEN SUM(CASE WHEN E_ROL.FP_ESCALATION_CLASS = 'C' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) AS BIT)    
  FROM SEC_USERS AS USR    
   LEFT JOIN SEC_USER_ROLES AS USR_ROL     
    ON USR.SEC_USERS_ID = USR_ROL.SEC_USERS_ID    
     AND (USR_ROL.IS_DELETED IS NULL OR USR_ROL.IS_DELETED = 0)    
   LEFT JOIN SEC_ROLES AS ROL    
    ON USR_ROL.SEC_ROLES_ID = ROL.SEC_ROLES_ID    
     AND (ROL.IS_DELETED IS NULL OR ROL.IS_DELETED = 0)    
   LEFT JOIN FP_ESCALATION_ROLES AS E_ROL    
    ON ROL.SEC_ROLES_ID = E_ROL.SEC_ROLES_ID    
  WHERE @USER_ID = USR.SEC_USERS_ID    
  GROUP BY USR.SEC_USERS_ID, USR.SUPER_ADMIN    
    
  --PROCEED WITH VALIDATION    
  -- =============================================    
  -- NEW    
  -- =============================================    
  IF(@FORM_STATUS_ID = 53)    
  BEGIN    
   IF(@IS_SRM = 1 OR @IS_IBL = 1 OR @IS_SUPER_ADMIN = 1)    
    BEGIN    
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN   
      --update form status based off selected form type    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = CASE WHEN FORM.FP_FF_TYPE_ID IN (1,2) THEN 54 --SRM: Submit Freight Form    
              WHEN FORM.FP_FF_TYPE_ID IN (3,4) THEN 57 --IBL: Submit Freight Form    
              ELSE 54 END, --DEFAULT - SRM: Submit Freight Form    
       FORM.MODIFIED_BY = @USER_ID,    
       FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
     END    
    END  
   ELSE    
   BEGIN     
    --ERROR LOG INSERT    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'Insufficient Clearance', 'Only SRM or IBL security roles are able to process this form into the next stage',    
    '', @FORM_NUM, NULL, NULL    
   END     
  END    
    
  -- =============================================    
  -- SRM: Submit Freight Form    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 54)    
  BEGIN    
   IF(@IS_SRM = 1 OR @IS_SUPER_ADMIN = 1)  
    BEGIN  
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN    
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 58, --IBL: Initial Analysis,  
      FORM.SUBMIT_DATE = GETDATE(),  
      FORM.MODIFIED_BY = @USER_ID,    
      FORM.MODIFIED_DATE = GETDATE()  
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT   
    
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, 'InboundFreightPricing@unfi.com', 'Freight Form action required',     
       'An active Freight Form that requires action has been assigned to you.' + @CR + @CR +   
       '<strong>' +'Form Id: '+'</strong>' + CAST(@FORM_NUM AS varchar(MAX)) + @CR +     
       '<strong>' + 'Form Status: ' +'</strong>'+'IBL Initial Analysis' + @CR +  
       '<strong>' +'Link: ' +'</strong>' + @FORM_URL + @CR,      
       @USER_ID, GETDATE(), 14, 'N'   
  
      --EMAIL WHS(S)  
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_CC, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT DISTINCT @EmailFrom, WHS.BACKHAUL_EMAIL, 'InboundFreightPricing@unfi.com', 'Freight Form action required',     
         'Hello,' + @CR +  @CR +   
         'Please contact the Inbound Freight Pricing team <InboundFreightPricing@unfi.com> informing them if you can backhaul from the following location: ' + @CR + @CR +   
         '<strong>' +'Form Id: ' +'</strong>' + CAST(@FORM_NUM AS varchar(MAX)) +@CR +     
         '<strong>' +'Address: ' +'</strong>' +  
         ltrim(rtrim(PICKUP.ADDRESS))  +', ' +    
         ltrim(rtrim(PICKUP.CITY)) +', ' +  
         ltrim(rtrim(PICKUP.STATE)) +' ' +    
         ltrim(rtrim(PICKUP.ZIP))  + @CR +             
         '<strong>' +'Average PO Volume: '+'</strong>' + CAST(FORMAT(VENDOR.AVERAGE_PO_UNITS,'#,###,##0.000') AS varchar(MAX)) + ' lbs' + @CR +  
         '<strong>' +'Temperature Requirement: '+'</strong>' + TEMP.DESCRIPTION + @CR ,     
         @USER_ID, GETDATE(), 14, 'N'   
      FROM FP_FREIGHT_FORM AS FORM    
       INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR  
        ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID  
       INNER JOIN FP_FF_PICKUP_LOCATIONS AS PICKUP  
        ON VENDOR.FP_FF_PICKUP_LOCATIONS_ID = PICKUP.FP_FF_PICKUP_LOCATIONS_ID  
       INNER JOIN TMS_WHS AS WHS  
        ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID  
       LEFT JOIN FP_FF_TEMPERATURE AS TEMP  
        ON FORM.FP_FF_TEMPERATURE_ID = TEMP.FP_FF_TEMPERATURE_ID  
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
       AND VENDOR.FP_FF_METHOD_ID IN (1, 2)  
       AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)  
     END    
    END  
   ELSE    
   BEGIN     
    --ERROR LOG INSERT    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'Insufficient Clearance', 'Only SRM security roles are able to process this form into the next stage',    
    '', @FORM_NUM, NULL, NULL    
    
   END     
  END    
    
  -- =============================================    
  -- SRM: Vendor Confirmation    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 55)  
  BEGIN     
   IF(@IS_SRM = 1 OR @IS_SUPER_ADMIN = 1)   
    BEGIN  
     IF (@FREIGHTANALYST > 0)  
     -- MISSING FREIGHT ANALYST  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF (@FREIGHTCHANGEREASON > 0)  
     -- MISSING FREIGHT CHANGE REASON  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Change Reason is missing', 'This Freight Form requires a Freight Change Reason', 'FP_FF_FREIGHT_CHANGE_REASON_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF(@MISSING_ALLOWANCE_TYPE > 0)       
     -- MISSING ALLOWANCE TYPE  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL)    
      SELECT 'Allowance Type is missing', 'This Freight Form requires an Allowance Type '    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
       
     IF (@VENDOR_MISSING_PICKUP_LOCATION > 0)  
     --CHECK TO SEE IF PICKUP LOCATION HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing Pickup Location', 'All Collect warehouses require a selected Pick Up Location', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
     END  
  
     IF (@DROUTE_COUNT != @PICKUPLOCATIONWITHWAREHOUSES_COUNT)  
     --CHECK TO SEE IF D-ROUTE AND PICKUP DAY HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing D-Route/Pickup Day', 'This Freight Form requires D-Route and Pickup Day', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
     END  
  
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)   
     BEGIN    
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 62, --Costing and Coding: Closing Process    
      FORM.MODIFIED_BY = @USER_ID,    
      FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT    
    
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, 'NATIONALCOSTING@UNFI.COM', 'Freight Form action required',     
       'An active Freight Form that requires action has been assigned to you.'+ @CR + @CR +   
       '<strong>' +'Form Id: '+'</strong>'  + CAST(@FORM_NUM AS varchar(MAX)) + @CR +   
       '<strong>' +'Form Status: '+'</strong>'+'Costing and Coding: Closing Process' + @CR +  
       '<strong>' +'Link: '+'</strong>' + @FORM_URL + @CR ,   
       @USER_ID, GETDATE(), 14, 'N'  
     END  
    END  
   ELSE    
   BEGIN     
    --ERROR LOG INSERT    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'Insufficient Clearance', 'Only SRM security roles are able to process this form into the next stage',    
    '', @FORM_NUM, NULL, NULL      
   END     
  END  
    
  -- =============================================    
  -- SRM: Freight Form Confirmation    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 56)    
  BEGIN  
   IF(@IS_SRM = 1 OR @IS_SUPER_ADMIN = 1)  
    BEGIN  
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN  
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 58, --IBL: Initial Analysis  
      FORM.SUBMIT_DATE = GETDATE(),  
      FORM.MODIFIED_BY = @USER_ID,    
      FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
    
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, 'InboundFreightPricing@unfi.com', 'Freight Form action required',     
       'An active Freight Form that requires action has been assigned to you.' + @CR + @CR +    
       '<strong>' +'Form Id: ' +'</strong>'+ CAST(@FORM_NUM AS varchar(MAX)) + @CR +     
       '<strong>' +'Form Status: ' +'</strong>' +'IBL Initial Analysis' + @CR +  
       '<strong>' +'Link: '+'</strong>' + @FORM_URL + @CR ,   
       @USER_ID, GETDATE(), 14, 'N'    
     END  
    END    
   ELSE    
   BEGIN     
    --ERROR LOG INSERT    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'Insufficient Clearance', 'Only SRM security roles are able to process this form into the next stage',    
    '', @FORM_NUM, NULL, NULL  
  
   END     
  END    
    
  -- =============================================    
  -- IBL: Submit Freight Form    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 57)    
  BEGIN      
   IF(@IS_IBL = 1 OR @IS_SUPER_ADMIN = 1)        
    BEGIN   
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN   
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 56, --SRM: Data Validation  
      FORM.MODIFIED_BY = @USER_ID,    
      FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT    
    
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, isnull(@SRM_EMAIL,'') + ';' + isnull(@SRMC_EMAIL,''), 'Freight Form action required',     
       'An active Freight Form that requires action has been assigned to you.' + @CR + @CR +      
       '<strong>' +'Form Id: ' + CAST(@FORM_NUM AS varchar(MAX))+'</strong>'  + @CR +    
       '<strong>' +'Form Status: ' +'</strong>' +'SRM Data Validation' + @CR +  
       '<strong>' +'Link: '+'</strong>'  + @FORM_URL + @CR ,     
       @USER_ID, GETDATE(), 14, 'N'    
    
     END    
    END  
   ELSE    
   BEGIN     
    --ERROR LOG INSERT    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'Insufficient Clearance', 'Only IBL security roles are able to process this form into the next stage',    
    '', @FORM_NUM, NULL, NULL    
    
   END     
  END    
    
  -- =============================================    
  -- IBL: Initial Analysis    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 58)    
  BEGIN  
   IF(@IS_IBL = 1 OR @IS_SUPER_ADMIN = 1)        
   BEGIN    
    IF (@FREIGHTANALYST > 0)  
    -- MISSING FREIGHT ANALYST  
    BEGIN    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
     FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
    END  
  
    IF (@FREIGHTCHANGEREASON > 0)  
    -- MISSING FREIGHT CHANGE REASON  
    BEGIN    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Freight Change Reason is missing', 'This Freight Form requires a Freight Change Reason', 'FP_FF_FREIGHT_CHANGE_REASON_ID', @FORM_NUM, NULL, NULL    
     FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
    END  
  
    --CHECK FOR ANY AND ALL VENDORS MISSING METHOD    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'All warehouses require a selected method', 'Warehouse ' + WHS.WHS_NUMBER + ' ' + whs.NAME + ' has no selected method',    
      NULL, @FORM_NUM, VENDOR.FP_FREIGHT_FORM_VENDOR_ID, NULL   
    FROM FP_FREIGHT_FORM_VENDOR AS VENDOR  
     INNER JOIN TMS_WHS AS WHS    
      ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID    
    WHERE VENDOR.FP_FREIGHT_FORM_ID = @FORM_NUM  
     AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)  
     AND VENDOR.FP_FF_METHOD_ID IS NULL  
  
    IF(@MISSING_ALLOWANCE_TYPE > 0)       
    -- MISSING ALLOWANCE TYPE  
    BEGIN    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL)    
     SELECT 'Allowance Type is missing', 'This Freight Form requires an Allowance Type '    
     FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
    END  
  
    IF (@VENDOR_MISSING_PICKUP_LOCATION > 0)  
    --CHECK TO SEE IF PICKUP LOCATION HAS BEEN ENTERED  
    BEGIN  
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Missing Pickup Location', 'All Collect warehouses require a selected Pick Up Location', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
    END  
  
    --IF THERE WERE NO ERRORS THEN PROCEED    
    IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
    BEGIN  
     --DETERMINE HOW TO PROCEEDE BASED OFF USER INPUT    
     IF(@SEND_TO_BACKHAUL IS NOT NULL)    
     BEGIN    
      IF(@SEND_TO_BACKHAUL = 0)    
      BEGIN     
       --CHECK THAT ALL VENDORS HAVE AN ASSIGNED PROPOSED_FREIGHT_PER_LB  
       SELECT @MISSING_PROPOSED_FREIGHT_PER_LB_COUNT = COUNT(*)   
       FROM FP_FREIGHT_FORM_VENDOR AS VENDOR   
       WHERE VENDOR.FP_FREIGHT_FORM_ID = @FORM_NUM   
        AND VENDOR.PROPOSED_FREIGHT_PER_LB IS NULL  
        AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
        AND (VENDOR.FP_FF_METHOD_ID IS NULL OR VENDOR.FP_FF_METHOD_ID <> 4) --NOT VSP  
  
       IF(@MISSING_PROPOSED_FREIGHT_PER_LB_COUNT > 0)  
       --MISSING PROPOSED_FREIGHT_PER_LB    
       BEGIN    
        INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
        SELECT 'Proposed Booked Freight Per Pound required', 'All warehouses require a UNFI Proposed Booked Freight Per Pound', 'PROPOSED_FREIGHT_PER_LB', @FORM_NUM, NULL, NULL    
        FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
       END  
  
       IF (@DROUTE_COUNT != @PICKUPLOCATIONWITHWAREHOUSES_COUNT)  
       --CHECK TO SEE IF D-ROUTE AND PICKUP DAY HAS BEEN ENTERED  
       BEGIN  
        INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
        SELECT 'Missing D-Route/Pickup Day', 'This Freight Form requires D-Route and Pickup Day', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
        FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
       END  
          
       --IF THERE WERE NO ERRORS THEN PROCEED    
       IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
       BEGIN  
        --update form status    
        UPDATE FORM    
        SET FORM.TMS_STATUS_ID = 55, --SRM: Vendor Confirmation    
         FORM.MODIFIED_BY = @USER_ID,    
         FORM.MODIFIED_DATE = GETDATE()    
        FROM FP_FREIGHT_FORM AS FORM    
        WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
        --CREATE FORM LOG    
        EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
    
        --EMAIL INBOUND FREIGHT PRICING    
        INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
        SELECT @EmailFrom, isnull(@SRM_EMAIL,'') + ';' + isnull(@SRMC_EMAIL,'') , 'Freight Form action required',     
         'An active Freight Form that requires action has been assigned to you.' + @CR + @CR +   
         '<strong>' +'Form Id: '+'</strong>' + CAST(@FORM_NUM AS varchar(MAX)) + @CR +  
         '<strong>' +'Form Status: '+'</strong>'+ 'SRM Vendor Confirmation' + @CR +  
         '<strong>' +'Link: '+'</strong>'  + @FORM_URL + @CR ,     
         @USER_ID, GETDATE(), 14, 'N'    
       END    
      END    
      ELSE IF(@SEND_TO_BACKHAUL = 1)    
      BEGIN    
       --IF THERE WERE NO ERRORS THEN PROCEED    
       IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
       BEGIN  
        --update form status    
        UPDATE FORM    
        SET FORM.TMS_STATUS_ID = 61, --Backhaul Analysis    
         FORM.MODIFIED_BY = @USER_ID,    
         FORM.MODIFIED_DATE = GETDATE()    
        FROM FP_FREIGHT_FORM AS FORM    
        WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
        --CREATE FORM LOG    
        EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
    
        --EMAIL INBOUND FREIGHT PRICING    
        INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
        SELECT @EmailFrom, @FREIGHT_ANALYST_EMAIL, 'Freight Form action required',     
         'An active Freight Form that requires action has been assigned to you.' + @CR +   @CR +   
         '<strong>' +'Form Number: '+'</strong>' + CAST(@FORM_NUM AS varchar(MAX)) + @CR +    
         '<strong>' +'Form Status: '+'</strong>'+'Backhaul Analysis' + @CR +   
         '<strong>' +'Link: '+'</strong>' + @FORM_URL + @CR ,      
         @USER_ID, GETDATE(), 14, 'N'    
  
        --Backhaul Email  
        INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
        SELECT 'InboundFreightPricing@unfi.com',   
          RESULTS.EMAIL_TO,   
          'Freight Form action required',     
          'Hello,' + @CR +  @CR +   
          'Please contact the Inbound Freight Pricing team <InboundFreightPricing@unfi.com> informing them if you can backhaul from the following location: '  + @CR + @CR +    
          '<strong>' +'Form Id: ' +'</strong>' + CAST(@FORM_NUM AS varchar(MAX)) +@CR +     
          '<strong>' +'Address: ' +'</strong>'+  
          ltrim(rtrim(RESULTS.ADDRESS))  +', ' +    
          ltrim(rtrim(RESULTS.CITY))  +', ' +    
          ltrim(rtrim(RESULTS.STATE))  +' ' +    
          ltrim(rtrim(RESULTS.ZIP)) + @CR +  
          '<strong>' +'Average PO Volume: ' +'</strong>' + CAST(FORMAT(SUM(RESULTS.AVERAGE_PO_WEIGHT),'#,###,##0.000') AS varchar(MAX)) + ' LBS, ' + CAST(FORMAT(SUM(RESULTS.AVERAGE_PALLETS_PER_PO),'#,###,##0') AS varchar(MAX)) + ' Pallets' + @CR +  
          '<strong>' +'Temperature Requirement: ' +'</strong>' + RESULTS.TEMPERATURE + @CR +  
          '<strong>' +'Link: '+'</strong>' + @FORM_URL + @CR ,            
          @USER_ID, GETDATE(), 14, 'N'   
        FROM(  
          SELECT CASE WHEN VENDOR.FP_FF_METHOD_ID = 1 THEN WHS.BACKHAUL_EMAIL   
              WHEN VENDOR.FP_FF_METHOD_ID = 2 THEN CROSSDOCK_WHS.BACKHAUL_EMAIL  
              ELSE WHS.BACKHAUL_EMAIL  
            END AS EMAIL_TO,  
            CASE WHEN VENDOR.FP_FF_METHOD_ID = 1 THEN WHS.TMS_WHS_ID   
              WHEN VENDOR.FP_FF_METHOD_ID = 2 THEN CROSSDOCK_WHS.TMS_WHS_ID  
              ELSE WHS.BACKHAUL_EMAIL  
            END AS TMS_WHS_ID,  
            ISNULL(VENDOR.AVERAGE_PO_WEIGHT, 0) AS AVERAGE_PO_WEIGHT,  
            ISNULL(VENDOR.AVERAGE_PALLETS_PER_PO, 0) AS AVERAGE_PALLETS_PER_PO,  
            PICKUP.ADDRESS,  
            PICKUP.CITY,  
            PICKUP.STATE,  
            PICKUP.ZIP,  
            TEMP.DESCRIPTION AS TEMPERATURE  
           FROM FP_FREIGHT_FORM AS FORM    
            INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR  
             ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID  
            INNER JOIN FP_FF_PICKUP_LOCATIONS AS PICKUP  
             ON VENDOR.FP_FF_PICKUP_LOCATIONS_ID = PICKUP.FP_FF_PICKUP_LOCATIONS_ID  
            INNER JOIN TMS_WHS AS WHS  
             ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID  
            LEFT JOIN TMS_WHS AS CROSSDOCK_WHS  
             ON VENDOR.CROSSDOCK_WHS_ID = CROSSDOCK_WHS.TMS_WHS_ID  
            LEFT JOIN FP_FF_TEMPERATURE AS TEMP  
             ON FORM.FP_FF_TEMPERATURE_ID = TEMP.FP_FF_TEMPERATURE_ID  
           WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
            AND VENDOR.FP_FF_METHOD_ID IN (1, 2)  
            AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)  
        ) AS RESULTS  
        GROUP BY RESULTS.EMAIL_TO,  
          RESULTS.TMS_WHS_ID,  
          RESULTS.ADDRESS,  
          RESULTS.CITY,  
          RESULTS.STATE,  
          RESULTS.ZIP,  
          RESULTS.TEMPERATURE  
       END  
      END     
      ELSE    
      BEGIN     
       --ERROR LOG INSERT    
       INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
       SELECT 'Unable to proceed', 'User needs to select if Form is to be sent to Backhaul',    
        '', @FORM_NUM, NULL, NULL    
  
      END    
     END     
    END   
   END    
   ELSE    
   BEGIN     
    --ERROR LOG INSERT    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'Insufficient Clearance', 'Only IBL security roles are able to process this form into the next stage',    
     '', @FORM_NUM, NULL, NULL    
    
   END    
  END    
    
  -- =============================================    
  -- IBL: Revised Analysis    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 59)    
  BEGIN  
   IF(@IS_IBL = 1 OR @IS_SUPER_ADMIN = 1)        
    BEGIN    
     --CHECK THAT ALL VENDORS HAVE AN ASSIGNED PROPOSED_FREIGHT_PER_LB  
     SELECT @MISSING_PROPOSED_FREIGHT_PER_LB_COUNT = COUNT(*)   
     FROM FP_FREIGHT_FORM_VENDOR AS VENDOR   
     WHERE VENDOR.FP_FREIGHT_FORM_ID = @FORM_NUM   
      AND VENDOR.PROPOSED_FREIGHT_PER_LB IS NULL  
      AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
      AND (VENDOR.FP_FF_METHOD_ID IS NULL OR VENDOR.FP_FF_METHOD_ID <> 4) --NOT VSP  
       
     IF (@FREIGHTANALYST > 0)  
     -- MISSING FREIGHT ANALYST  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF (@FREIGHTCHANGEREASON > 0)  
     -- MISSING FREIGHT CHANGE REASON  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Change Reason is missing', 'This Freight Form requires a Freight Change Reason', 'FP_FF_FREIGHT_CHANGE_REASON_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF(@MISSING_ALLOWANCE_TYPE > 0)       
     -- MISSING ALLOWANCE TYPE  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL)    
      SELECT 'Allowance Type is missing', 'This Freight Form requires an Allowance Type '    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF(@MISSING_PROPOSED_FREIGHT_PER_LB_COUNT > 0)  
     --MISSING PROPOSED_FREIGHT_PER_LB    
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Proposed Booked Freight Per Pound required', 'All warehouses require a UNFI Proposed Booked Freight Per Pound', 'PROPOSED_FREIGHT_PER_LB', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF (@VENDOR_MISSING_PICKUP_LOCATION > 0)  
     --CHECK TO SEE IF PICKUP LOCATION HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing Pickup Location', 'All Collect warehouses require a selected Pick Up Location', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
     END  
  
     IF (@DROUTE_COUNT != @PICKUPLOCATIONWITHWAREHOUSES_COUNT)   
     --CHECK TO SEE IF D-ROUTE AND PICKUP DAY HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing D-Route/Pickup Day', 'This Freight Form requires D-Route and Pickup Day', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
     END  
  
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN   
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 55, --SRM: Vendor Confirmation    
       FORM.MODIFIED_BY = @USER_ID,    
       FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
    
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, isnull(@SRM_EMAIL, '') + ';' + isnull(@SRMC_EMAIL,''), 'Freight Form action required',     
       'An active Freight Form that requires action has been assigned to you.'  + @CR +  @CR +     
       '<strong>' +'Form Id: '+'</strong>' + CAST(@FORM_NUM AS varchar(MAX))  + @CR +    
       '<strong>' +'Form Status: '+'</strong>'+ 'SRM: Vendor Confirmation'  + @CR +     
       '<strong>' +'Link: '+'</strong>' + @FORM_URL  + @CR  ,      
       @USER_ID, GETDATE(), 14, 'N'    
     END   
    END   
    ELSE    
    BEGIN     
     --ERROR LOG INSERT    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Insufficient Clearance', 'Only IBL security roles are able to process this form into the next stage',    
      '', @FORM_NUM, NULL, NULL    
    
    END     
     
  END    
    
  -- =============================================    
  -- IBL: Final Analysis    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 60)    
  BEGIN  
   IF(@IS_IBL = 1 OR @IS_SUPER_ADMIN = 1)        
    BEGIN    
     --CHECK THAT ALL VENDORS HAVE AN ASSIGNED PROPOSED_FREIGHT_PER_LB  
     SELECT @MISSING_PROPOSED_FREIGHT_PER_LB_COUNT = COUNT(*)   
     FROM FP_FREIGHT_FORM_VENDOR AS VENDOR   
     WHERE VENDOR.FP_FREIGHT_FORM_ID = @FORM_NUM   
      AND VENDOR.PROPOSED_FREIGHT_PER_LB IS NULL  
      AND (IS_DELETED IS NULL OR IS_DELETED = 0)  
      AND (VENDOR.FP_FF_METHOD_ID IS NULL OR VENDOR.FP_FF_METHOD_ID <> 4) --NOT VSP  
       
     IF (@FREIGHTANALYST > 0)  
     -- MISSING FREIGHT ANALYST  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF (@FREIGHTCHANGEREASON > 0)  
     -- MISSING FREIGHT CHANGE REASON  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Change Reason is missing', 'This Freight Form requires a Freight Change Reason', 'FP_FF_FREIGHT_CHANGE_REASON_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF(@MISSING_ALLOWANCE_TYPE > 0)       
     -- MISSING ALLOWANCE TYPE  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL)    
      SELECT 'Allowance Type is missing', 'This Freight Form requires an Allowance Type '    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF(@MISSING_PROPOSED_FREIGHT_PER_LB_COUNT > 0)  
     --MISSING PROPOSED_FREIGHT_PER_LB    
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Proposed Booked Freight Per Pound required', 'All warehouses require a UNFI Proposed Booked Freight Per Pound', 'PROPOSED_FREIGHT_PER_LB', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF (@VENDOR_MISSING_PICKUP_LOCATION > 0)  
     --CHECK TO SEE IF PICKUP LOCATION HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing Pickup Location', 'All Collect warehouses require a selected Pick Up Location', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
     END  
  
     IF (@DROUTE_COUNT != @PICKUPLOCATIONWITHWAREHOUSES_COUNT)   
     --CHECK TO SEE IF D-ROUTE AND PICKUP DAY HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing D-Route/Pickup Day', 'This Freight Form requires D-Route and Pickup Day', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
     END  
  
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN   
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 55, --SRM: Vendor Confirmation    
       FORM.MODIFIED_BY = @USER_ID,    
       FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
    
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, isnull(@SRM_EMAIL, '') + ';' + isnull(@SRMC_EMAIL,''), 'Freight Form action required',     
       'An active Freight Form that requires action has been assigned to you.' + @CR +  @CR +     
       '<strong>' +'Form Id: '+'</strong>' + CAST(@FORM_NUM AS varchar(MAX))+ @CR +   
       '<strong>' +'Form Status: ' +'</strong>'+'SRM: Vendor Confirmation' + @CR +   
       '<strong>' +'Link: '+'</strong>' + @FORM_URL + @CR ,      
       @USER_ID, GETDATE(), 14, 'N'    
     END  
    END    
    ELSE    
    BEGIN     
     --ERROR LOG INSERT    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Insufficient Clearance', 'Only IBL security roles are able to process this form into the next stage',    
     '', @FORM_NUM, NULL, NULL    
    
    END     
  END    
    
  -- =============================================    
  -- Backhaul Analysis    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 61)    
  BEGIN  
   IF(@IS_IBL = 1 OR @IS_SUPER_ADMIN = 1)      
    BEGIN  
     IF (@FREIGHTANALYST > 0)  
     -- MISSING FREIGHT ANALYST  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF(@MISSING_ALLOWANCE_TYPE > 0)       
     -- MISSING ALLOWANCE TYPE  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL)    
      SELECT 'Allowance Type is missing', 'This Freight Form requires an Allowance Type '    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF (@VENDOR_MISSING_PICKUP_LOCATION > 0)  
     --CHECK TO SEE IF PICKUP LOCATION HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing Pickup Location', 'All Collect warehouses require a selected Pick Up Location', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
     END  
  
     IF (@DROUTE_COUNT != @PICKUPLOCATIONWITHWAREHOUSES_COUNT)   
     --CHECK TO SEE IF D-ROUTE AND PICKUP DAY HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing D-Route/Pickup Day', 'This Freight Form requires D-Route and Pickup Day', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
     END  
    
     --IF THERE WERE NO ERRORS THEN PROCEEDE    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN    
     --update form status    
     UPDATE FORM    
     SET FORM.TMS_STATUS_ID = 60, --IBL: Final Analysis     
      FORM.MODIFIED_BY = @USER_ID,    
      FORM.MODIFIED_DATE = GETDATE()    
     FROM FP_FREIGHT_FORM AS FORM    
     WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
     --CREATE FORM LOG    
     EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
    
     --EMAIL INBOUND FREIGHT PRICING    
     INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
     SELECT @EmailFrom, 'InboundFreightPricing@unfi.com', 'Freight Form action required',     
      'An active Freight Form that requires action has been assigned to you.' + @CR + @CR +      
      '<strong>' +'Form Id: '+'</strong>'  + CAST(@FORM_NUM AS varchar(MAX))+ @CR +   
      '<strong>' +'Form Status: ' +'</strong>' + 'IBL: Final Analysis' + @CR +   
      '<strong>' +'Link: '+'</strong>'  + @FORM_URL + @CR ,      
      @USER_ID, GETDATE(), 14, 'N'    
     END    
    END    
    ELSE    
    BEGIN     
     --ERROR LOG INSERT    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Insufficient Clearance', 'Only IBL security roles are able to process this form into the next stage',    
      '', @FORM_NUM, NULL, NULL    
    
    END     
  END    
    
  -- =============================================    
  -- Costing and Coding: Closing Process    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 62)    
  BEGIN     
   IF(@IS_C_OR_C = 1 OR @IS_SUPER_ADMIN = 1)       
   BEGIN    
    --VARIABLES FOR COLLECTION    
    DECLARE @REQUIRES_VENDOR_NUMBERS BIT = 0,    
    @DUPLICATE_WHS BIT = 0,    
    @FORM_VENDORS_MISSING_WHS BIT = 0,    
    @FORM_VENDOR_DOSE_NOT_EXIST_IN_TMS BIT = 0,  
    @MISSING_EFFECTIVE_DATE BIT = 0,  
    @SAVED_LAWSON_NUMBER BIGINT = NULL,  
    @INVALID_EFFECTIVE_DATE BIT = 0,  
    @TODAYS_DATE DATETIME = DATEADD(d,0,DATEDIFF(d,0,GETDATE())),  
    @REPROCESSING_WHS BIT = 0  
    --@FORM_VENDORS_MULTIPLE_LAWSON_NUMBER BIT = 0;    
  
  
    --Get a list of source systems and effective dates for each source system we are submitting  
    DECLARE @SOURCE_SYSTEM_TBL AS TABLE(  
     SOURCE_SYSTEM VARCHAR(50) NULL,  
     EFFECTIVE_DATE DATETIME NULL  
    )  
  
    INSERT INTO @SOURCE_SYSTEM_TBL(SOURCE_SYSTEM, EFFECTIVE_DATE)  
    SELECT SUBSTRING(lst.c, 0, CHARINDEX('_', lst.c)),  
      CAST(CASE WHEN SUBSTRING(lst.c, CHARINDEX('_', lst.c) + 1, LEN(lst.c)) = '' THEN NULL  
       ELSE SUBSTRING(lst.c, CHARINDEX('_', lst.c) + 1, LEN(lst.c)) END AS DATETIME)  
    FROM   dbo.fnParseStack(@SOURCE_SYSTEM_AND_EFFECTIVE_DATE_LIST, 'c') lst  
      
    IF (@FREIGHTANALYST > 0)  
     -- MISSING FREIGHT ANALYST  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
    IF (@FREIGHTANALYST > 0)  
     -- MISSING FREIGHT ANALYST  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
    IF(@MISSING_ALLOWANCE_TYPE > 0)       
    -- MISSING ALLOWANCE TYPE  
    BEGIN    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL)    
     SELECT 'Allowance Type is missing', 'This Freight Form requires an Allowance Type '    
     FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
    END  
  
    --Check for missing effective dates  
    SELECT @MISSING_EFFECTIVE_DATE = CAST((CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END) AS BIT)  
    FROM @SOURCE_SYSTEM_TBL AS SORC  
    WHERE SORC.EFFECTIVE_DATE IS NULL  
  
    --REQUIRES EFFECTIVE_DATE    
    IF(@MISSING_EFFECTIVE_DATE = 1)    
    BEGIN     
     --ERROR LOG INSERT    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Effective Date Required', 'The effective date is required before processing the form to the next stage',    
     '', @FORM_NUM, NULL, NULL    
    
    END   
  
    --Check for missing effective dates  
    SELECT @INVALID_EFFECTIVE_DATE = CAST((CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END) AS BIT)  
    FROM @SOURCE_SYSTEM_TBL AS SORC  
    WHERE SORC.EFFECTIVE_DATE <= @TODAYS_DATE  
  
    --REQUIRES VALID EFFECTIVE DATE  
    IF (@INVALID_EFFECTIVE_DATE > 0)  
    --CHECK TO SEE IF VALID EFFECTIVE DATE HAS BEEN ENTERED  
    BEGIN  
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Valid Effective Date Required', 'The effective date must be greater than today', '', @FORM_NUM, NULL, NULL    
    END  
      
    --CHECK IF SOURCE SYSTEM HAS ALREADY BEEN PROCESSED  
    SELECT @REPROCESSING_WHS = CAST((CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END) AS BIT)  
    FROM FP_FREIGHT_FORM_VENDOR AS VEN  
     INNER JOIN TMS_WHS AS WHS  
      ON VEN.TMS_WHS_ID = WHS.TMS_WHS_ID  
     INNER JOIN @SOURCE_SYSTEM_TBL AS SORC  
      ON WHS.SOURCE_SYSTEM = SORC.SOURCE_SYSTEM  
    WHERE VEN.FP_FREIGHT_FORM_ID = @FORM_NUM  
     AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)  
     AND VEN.PROCESSED_FLAG = 1   
      
    --IF SOURCE SYSTEM HAS ALREADY BEEN PROCESSED  
    IF (@REPROCESSING_WHS > 0)  
    BEGIN  
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Source System has already been processed', 'A selected Source System or Vendor has already been processed', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
    END  
  
    IF (@VENDOR_MISSING_PICKUP_LOCATION > 0)  
    --CHECK TO SEE IF PICKUP LOCATION HAS BEEN ENTERED  
    BEGIN  
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Missing Pickup Location', 'All Collect warehouses require a selected Pick Up Location', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
    END  
  
    IF (@DROUTE_COUNT != @PICKUPLOCATIONWITHWAREHOUSES_COUNT)  
    --CHECK TO SEE IF D-ROUTE AND PICKUP DAY HAS BEEN ENTERED  
    BEGIN  
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Missing D-Route/Pickup Day', 'This Freight Form requires D-Route and Pickup Day', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
     FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    END  
  
    --Get the Lawson Number for this form from FP_FREIGHT_FORM  
    SELECT @SAVED_LAWSON_NUMBER = FORM.LAWSON_NUMBER  
    FROM FP_FREIGHT_FORM AS FORM  
    WHERE FP_FREIGHT_FORM_ID = @FORM_NUM AND @FORM_TYPE_ID = 1  
  
    IF (@SAVED_LAWSON_NUMBER IS NOT NULL)  
    BEGIN  
     IF (@LAWSON_NUMBER != @SAVED_LAWSON_NUMBER)  
     --CHECK TO SEE IF LAWSON NUMBER SAVED IN THE TABLE IS NOT SAME AS THE ONE ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Lawson Number', 'Only one Lawson number can be added to a form', '', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
     END  
    END  
     
    ----REQUIRES LAWSON_NUMBER IF FORM TYPE IS NEW  
    --IF(@FORM_TYPE_ID = 1 AND @LAWSON_NUMBER IS NULL)    
    --BEGIN     
    -- --ERROR LOG INSERT    
    -- INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    -- SELECT 'Lawson Number required', 'The lawson number is required before processing the form to the next stage',    
    -- '', @FORM_NUM, NULL, NULL    
    
    --END     
  
    ----CHECK ALL VENDORS SHARE THE SAME LAWSON NUMBER   
    --IF(@FORM_TYPE_ID = 1 AND @LAWSON_NUMBER IS NOT NULL)    
    --BEGIN  
    -- SELECT @FORM_VENDORS_MULTIPLE_LAWSON_NUMBER = CAST((CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END) AS BIT)    
    -- FROM FP_FREIGHT_FORM AS FORM    
    --  INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR    
    --   ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID    
    --    AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)   
    --  INNER JOIN TMS_VENDOR AS TVEN  
    --   ON VENDOR.TMS_VENDOR_ID = TVEN.TMS_VENDOR_ID  
    -- WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    -- AND TVEN.REMIT_VENDOR <> @LAWSON_NUMBER  
    --END  
  
    --IF(@FORM_VENDORS_MULTIPLE_LAWSON_NUMBER = 1) --MULTIPLE LAWSON NUMBERS  
    --BEGIN    
    -- --ERROR LOG INSERT    
    -- INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    -- SELECT 'Multiple Lawson Numbers', 'Multiple different lawson numbers have been assiend to the vendors for this form',    
    --  '', @FORM_NUM, NULL, NULL    
    
    --END    
    
    --ALL FORM VENDORS HAVE AN ASSIGNED WHS    
    SELECT @FORM_VENDORS_MISSING_WHS = CAST((CASE WHEN SUM(CASE WHEN WHS.TMS_WHS_ID IS NULL THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) AS BIT)    
    FROM FP_FREIGHT_FORM AS FORM    
     INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR    
      ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID    
       AND (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)    
     LEFT JOIN TMS_WHS AS WHS    
      ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID    
    WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
    
    IF(@FORM_VENDORS_MISSING_WHS = 1) --MISSING WHS    
    BEGIN    
     --ERROR LOG INSERT    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Vendor numbers required', 'Not all Form Vendors have a warehouse assigned to them',    
      '', @FORM_NUM, NULL, NULL    
    
    END    
    
    --DUPLICATE WHS CHECK    
    SELECT @DUPLICATE_WHS = CAST((CASE WHEN COUNT(WHS.TMS_WHS_ID) > 1 THEN 1 ELSE 0 END) AS BIT)    
    FROM TMS_VENDOR AS VENDOR    
     INNER JOIN TMS_WHS AS WHS    
      ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID    
       AND (WHS.IS_DELETED IS NULL OR WHS.IS_DELETED = 0)    
    WHERE (VENDOR.IS_DELETED IS NULL OR VENDOR.IS_DELETED = 0)    
     AND VENDOR.TMS_VENDOR_ID IN (SELECT  i  
             FROM DBO.fnParseStack(@VENDOR_NUMBERS, 'i'))     
    GROUP BY WHS.TMS_WHS_ID    
    
    IF(@DUPLICATE_WHS = 1) --DUPLICATE WHS'    
    BEGIN    
     --ERROR LOG INSERT    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Duplicate warehouses', 'Two or more vendors share the same warehouse',    
       '', @FORM_NUM, NULL, NULL    
    END    
     
   --IF THERE WERE NO ERRORS THEN PROCEED  
   IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
   BEGIN  
    IF(@FORM_TYPE = 1)  
    BEGIN  
     --CHECK TO SEE IF THERE ARE ANY VENDOR/WAREHOUSE NOT SELECTED  
     SELECT FVEN.TMS_WHS_ID, FP_FREIGHT_FORM_VENDOR_ID   
     INTO #MISSING_WHS  
     FROM FP_FREIGHT_FORM_VENDOR FVEN  
     JOIN TMS_WHS WHS ON FVEN.TMS_WHS_ID = WHS.TMS_WHS_ID  
     JOIN @SOURCE_SYSTEM_TBL AS SS ON WHS.SOURCE_SYSTEM = SS.SOURCE_SYSTEM  
     WHERE FP_FREIGHT_FORM_ID = @FORM_NUM   
     AND FVEN.TMS_WHS_ID NOT IN (SELECT TMS_WHS_ID FROM TMS_VENDOR FVEN1  
               WHERE TMS_VENDOR_ID IN (SELECT  i FROM DBO.fnParseStack(@VENDOR_NUMBERS, 'i'))   
               AND (FVEN1.IS_DELETED IS NULL OR FVEN1.IS_DELETED = 0)  
               )  
     AND (FVEN.IS_DELETED IS NULL OR FVEN.IS_DELETED = 0)  
     AND (WHS.IS_DELETED IS NULL OR WHS.IS_DELETED = 0)  
     ORDER BY TMS_WHS_ID ASC  
  
     --THROW ERROR OR UPDATE BASED ON ANY MISSING WAREHOUSES  
     IF((SELECT COUNT(*) FROM #MISSING_WHS) > 0)    
     BEGIN   
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Warehouse has no vendor assigned to it', 'Warehouse ' + WHS.WHS_NUMBER + ' ' + WHS.NAME + ' has no associated vendor from the list you have provided',    
        NULL, @FORM_NUM, FP_FREIGHT_FORM_VENDOR_ID, NULL    
      FROM #MISSING_WHS  
      JOIN TMS_WHS WHS ON #MISSING_WHS.TMS_WHS_ID = WHS.TMS_WHS_ID ORDER BY WHS.TMS_WHS_ID ASC  
     END  
  
     --Ensure user only added one vendor number is UBS was entered  
     IF((SELECT COUNT(*) FROM @SOURCE_SYSTEM_TBL WHERE SOURCE_SYSTEM = 'UBS') > 0)  
     BEGIN  
      --UBS vendor validation  
      DECLARE @UBS_VENDOR_LIST AS TABLE(  
       TMS_VENDOR_ID BIGINT NULL,  
       VENDOR_NUMBER VARCHAR(255) NULL,  
       SOURCE_SYSTEM VARCHAR(255) NULL  
      );  
  
      --GET NEW VENDORS  
      INSERT INTO @UBS_VENDOR_LIST (TMS_VENDOR_ID, VENDOR_NUMBER, SOURCE_SYSTEM)  
      SELECT VEN.TMS_VENDOR_ID, VEN.VENDOR_NUMBER, VEN.SOURCE_SYSTEM  
      FROM TMS_VENDOR VEN  
      WHERE TMS_VENDOR_ID IN (SELECT  i FROM DBO.fnParseStack(@VENDOR_NUMBERS, 'i'))   
       AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)  
       AND VEN.SOURCE_SYSTEM = 'UBS'  
  
      --RUN VALIDATION  
      DECLARE @MULTIPLE_UBS_VENDOR_NUMBERS AS BIT = 0;  
      SELECT @MULTIPLE_UBS_VENDOR_NUMBERS = CAST((CASE WHEN EXISTS (SELECT 1 FROM @UBS_VENDOR_LIST R2 where R1.VENDOR_NUMBER <> R2.VENDOR_NUMBER)  
          THEN 1  
          ELSE 0  
        END) AS BIT)  
      FROM (SELECT TOP 1 VL.VENDOR_NUMBER FROM @UBS_VENDOR_LIST VL) AS R1;  
  
      --MULTIPLE UBS VENDOR NUMBERS  
      IF(@MULTIPLE_UBS_VENDOR_NUMBERS = 1)   
      BEGIN    
       --ERROR LOG INSERT    
       INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
       SELECT 'Different UBS vendor numbers', 'Two or more UBS vendors have different vendor numbers',    
         '', @FORM_NUM, NULL, NULL    
      END    
     END  
       
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)  
     BEGIN  
      UPDATE VENDOR     
      SET VENDOR.TMS_VENDOR_ID = SOURCEVENDOR.TMS_VENDOR_ID,    
       VENDOR.MODIFIED_BY = @USER_ID,    
       VENDOR.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
       INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID    
       INNER JOIN TMS_VENDOR AS SOURCEVENDOR   
        ON VENDOR.TMS_WHS_ID = SOURCEVENDOR.TMS_WHS_ID    
         AND SOURCEVENDOR.TMS_VENDOR_ID IN (SELECT  i  
               FROM DBO.fnParseStack(@VENDOR_NUMBERS, 'i'))    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
     END  
    END  
  
    IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)  
    BEGIN   
     --WHEN THE FORM TYPE IS NEW AND THE ENTERED LAWSON NUMBER IS NOT NULL  
     UPDATE FORM    
     SET FORM.LAWSON_NUMBER = (CASE WHEN FORM.FP_FF_TYPE_ID = 1 AND @LAWSON_NUMBER IS NOT NULL THEN @LAWSON_NUMBER  
              ELSE FORM.LAWSON_NUMBER END),  
      FORM.MODIFIED_BY = @USER_ID,  
      FORM.MODIFIED_DATE = GETDATE()  
     FROM FP_FREIGHT_FORM AS FORM  
     WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
  
     --update vendor effective date and processed flag  
     UPDATE VENDOR     
     SET VENDOR.EFFECTIVE_DATE = SS.EFFECTIVE_DATE,  
      VENDOR.PROCESSED_FLAG = 1,  
      VENDOR.MODIFIED_BY = @USER_ID,    
      VENDOR.MODIFIED_DATE = GETDATE()    
     FROM FP_FREIGHT_FORM AS FORM    
      INNER JOIN FP_FREIGHT_FORM_VENDOR AS VENDOR ON FORM.FP_FREIGHT_FORM_ID = VENDOR.FP_FREIGHT_FORM_ID    
      INNER JOIN TMS_WHS AS WHS ON VENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID  
      INNER JOIN @SOURCE_SYSTEM_TBL AS SS ON WHS.SOURCE_SYSTEM = SS.SOURCE_SYSTEM  
     WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
  
     UPDATE TMSVEN  
     SET TMSVEN.BOOKED_FREIGHT_PER_LB = CAST(  
      CASE WHEN WHS.SOURCE_SYSTEM = 'UBS'  
       THEN FORM.EAST_BLENDED_FREIGHT_RATE  
      WHEN WHS.TMS_WHS_ID IN (1, 114)  
       THEN FORM.GILROC_BLENDED_FREIGHT_RATE  
      ELSE   
       FORMVENDOR.PROPOSED_FREIGHT_PER_LB  
      END AS DECIMAL(18, 6)),  
      TMSVEN.MODIFIED_BY = @USER_ID,  
      TMSVEN.MODIFIED_DATE = GETDATE()  
     FROM FP_FREIGHT_FORM AS FORM  
      INNER JOIN FP_FREIGHT_FORM_VENDOR AS FORMVENDOR   
       ON FORM.FP_FREIGHT_FORM_ID = FORMVENDOR.FP_FREIGHT_FORM_ID  
      INNER JOIN TMS_VENDOR AS TMSVEN  
       ON FORMVENDOR.TMS_VENDOR_ID = TMSVEN.TMS_VENDOR_ID  
      INNER JOIN TMS_WHS WHS  
       ON FORMVENDOR.TMS_WHS_ID = WHS.TMS_WHS_ID  
     WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
      AND (FORMVENDOR.IS_DELETED IS NULL OR FORMVENDOR.IS_DELETED = 0)  
    
     --IF ALL FORM_VENDORS ARE SUBMITED WE CAN COMPLETE THE FORM  
     IF((SELECT COUNT(*)   
      FROM FP_FREIGHT_FORM_VENDOR AS VEN   
      WHERE VEN.FP_FREIGHT_FORM_ID = @FORM_NUM   
       AND (VEN.PROCESSED_FLAG IS NULL OR VEN.PROCESSED_FLAG = 0)   
       AND (VEN.IS_DELETED IS NULL OR VEN.IS_DELETED = 0)) = 0)  
     BEGIN  
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 66, --Completed    
       --WHEN THE FORM TYPE IS NEW AND THE ENTERED LAWSON NUMBER IS NOT NULL  
       --FORM.LAWSON_NUMBER = (CASE WHEN FORM.FP_FF_TYPE_ID = 1 AND @LAWSON_NUMBER IS NOT NULL THEN @LAWSON_NUMBER  
       --       ELSE FORM.LAWSON_NUMBER END),  
       FORM.MODIFIED_BY = @USER_ID,    
       FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
  
      --CREATE FORM LOG          EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
  
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, 'InboundFreightPricing@unfi.com', 'Freight Form completed',     
        'A Freight Form has been completed.' + @CR + @CR +      
        '<strong>' +'Form Number: ' +'</strong>' + CAST(@FORM_NUM AS varchar(MAX)) + @CR +     
        '<strong>' +'Form Status: '+'</strong>' +'Completed' + @CR +   
        '<strong>' +'Link: '+'</strong>'  + @FORM_URL + @CR ,      
        @USER_ID, GETDATE(), 14, 'N'   
     END    
   
     --WE NEED TO CREATE A COMMA DELIMITED LIST OF SOURCE SYSTEM FOR FP_PRICING_OUT  
     DECLARE @SOURCE_SYSTEM_LIST AS VARCHAR(MAX) = '';  
     SELECT @SOURCE_SYSTEM_LIST = COALESCE(@SOURCE_SYSTEM_LIST+',' , '') + SS.SOURCE_SYSTEM  
     FROM @SOURCE_SYSTEM_TBL AS SS  
       
     --We do not insert 'New' form types into the host systems  
     IF(@FORM_TYPE != 1)  
     BEGIN  
      --CREATE ENTRY IN FP_PRICING_OUT  
      EXEC [dbo].[SP_FP_INSERT_INTO_FP_PRICING_OUT] @FP_FREIGHT_FORM_ID = @FORM_NUM, @TMS_STATUS_ID = 66, @SOURCE_SYSTEM = @SOURCE_SYSTEM_LIST     
     END  
  
     END  
   END    
  END    
  ELSE    
   BEGIN     
    --ERROR LOG INSERT    
    INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
    SELECT 'Insufficient Clearance', 'Only Costing or Coding security roles are able to process this form into the next stage',    
    '', @FORM_NUM, NULL, NULL    
    
   END     
  END    
  
  -- =============================================    
  -- IBL: VSP Confirmation    
  -- =============================================    
  ELSE IF(@FORM_STATUS_ID = 67)    
  BEGIN  
   IF(@IS_IBL = 1 OR @IS_SUPER_ADMIN = 1)        
    BEGIN   
     IF (@FREIGHTANALYST > 0)  
     -- MISSING FREIGHT ANALYST  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Freight Analyst is missing', 'This Freight Form requires a Freight Analyst ', 'FREIGHT_ANALYST_USER_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
     IF(@MISSING_ALLOWANCE_TYPE > 0)       
     -- MISSING ALLOWANCE TYPE  
     BEGIN    
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL)    
      SELECT 'Allowance Type is missing', 'This Freight Form requires an Allowance Type '    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM  
     END  
  
     IF (@VENDOR_MISSING_PICKUP_LOCATION > 0)  
     --CHECK TO SEE IF PICKUP LOCATION HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing Pickup Location', 'All Collect warehouses require a selected Pick Up Location', 'FP_FF_PICKUP_LOCATIONS_ID', @FORM_NUM, NULL, NULL    
     END  
  
     IF (@DROUTE_COUNT != @PICKUPLOCATIONWITHWAREHOUSES_COUNT)   
     --CHECK TO SEE IF D-ROUTE AND PICKUP DAY HAS BEEN ENTERED  
     BEGIN  
      INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
      SELECT 'Missing D-Route/Pickup Day', 'This Freight Form requires D-Route and Pickup Day', 'PICKUP_LOCATION_ID', @FORM_NUM, NULL, NULL    
      FROM FP_FREIGHT_FORM AS FORM  WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
     END  
     --IF THERE WERE NO ERRORS THEN PROCEED    
     IF((SELECT COUNT(*) FROM @ERROR_LOG) = 0)    
     BEGIN   
      --update form status    
      UPDATE FORM    
      SET FORM.TMS_STATUS_ID = 65, --Rejected: VSP  
      FORM.MODIFIED_BY = @USER_ID,    
      FORM.MODIFIED_DATE = GETDATE()    
      FROM FP_FREIGHT_FORM AS FORM    
      WHERE FORM.FP_FREIGHT_FORM_ID = @FORM_NUM    
  
      --CREATE FORM LOG    
      EXEC [dbo].[SP_FP_TOOL_CREATE_FORM_LOG] @FORM_ID = @FORM_NUM, @USER_ID = @USER_ID, @NEXT_STAGE_COMMENT = @NEXT_STAGE_COMMENT  
  
      ----WE NEED TO CREATE A COMMA DELIMITED LIST OF SOURCE SYSTEM FOR FP_PRICING_OUT  
      --DECLARE @SOURCE_SYSTEM_LIST2 AS VARCHAR(MAX) = '';  
      --SELECT @SOURCE_SYSTEM_LIST2 = COALESCE(@SOURCE_SYSTEM_LIST2+',' , '') + RESULTS.SOURCE_SYSTEM  
      --FROM(  
      -- SELECT DISTINCT WHS.SOURCE_SYSTEM  
      -- FROM FP_FREIGHT_FORM_VENDOR AS FV  
      --  INNER JOIN TMS_WHS AS WHS  
      --   ON FV.TMS_WHS_ID = WHS.TMS_WHS_ID  
      -- WHERE FV.FP_FREIGHT_FORM_ID =  @FORM_NUM  
      --  AND (FV.IS_DELETED IS NULL OR FV.IS_DELETED = 0)  
      --) RESULTS  
  
      --11/12/2019 TWL Note: Removed this to handle new reject process  
      ----CREATE ENTRY IN FP_PRICING_OUT  
      --EXEC [dbo].[SP_FP_INSERT_INTO_FP_PRICING_OUT] @FP_FREIGHT_FORM_ID = @FORM_NUM, @TMS_STATUS_ID = 65 , @SOURCE_SYSTEM = @SOURCE_SYSTEM_LIST2   
  
      ----EMAIL INBOUND FREIGHT PRICING    
      --INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      --SELECT @EmailFrom, 'InboundFreightPricing@unfi.com', 'Freight Form action required',   
      -- 'The IBL has rejected the offered pricing and the vendor has chosen to go VSP.' + @CR + @CR +      
      -- '<strong>' +'Form Id: ' + CAST(@FORM_NUM AS varchar(MAX))+'</strong>'  + @CR +    
      -- '<strong>' +'Form Status: ' +'</strong>' +'Rejected: VSP' + @CR +  
      -- '<strong>' +'Link: '+'</strong>'  + @FORM_URL + @CR ,     
      -- @USER_ID, GETDATE(), 14, 'N'    
  
      --EMAIL INBOUND FREIGHT PRICING    
      INSERT INTO TMS_COR_EMAIL (EMAIL_FROM, EMAIL_TO, EMAIL_SUBJECT, EMAIL_BODY, CREATED_BY, CREATED_DATE, TMS_NOTIFICATIONS_TYPE_ID,STATUS)    
      SELECT @EmailFrom, 'InboundFreightPricing@unfi.com;NATIONALCOSTING@UNFI.COM;' + isnull(@SRM_EMAIL, '') + ';' + isnull(@SRMC_EMAIL, ''), 'Freight Form ' + CAST(@FORM_NUM AS varchar(MAX)) + ' Action Required: Rejected VSP',   
       'Freight Form ' + CAST(@FORM_NUM AS varchar(MAX))+ @CR +    
       'The IBL Pricing team have reviewed and accepted to move this Supplier to Vendor Ship Prepaid.' + @CR +  
       'The SRM/SRMC will supply National Costing with the delivered price list, effective date and TMS ticket number by separate email to complete.' + @CR,     
       @USER_ID, GETDATE(), 14, 'N'    
  
     END    
    END  
   ELSE    
    BEGIN     
     --ERROR LOG INSERT    
     INSERT INTO @ERROR_LOG(ERROR_MESSGAE_TITLE, ERROR_MESSAGE_DETAIL, FIELD_NAME, FORM_ID, FORM_VENDOR_ID, PICKUP_LOCATION_ID)    
     SELECT 'Insufficient Clearance', 'Only IBL security roles are able to process this form into the next stage',    
     '', @FORM_NUM, NULL, NULL    
    
    END   
  END    
    
  --RETURN ERROR LOG    
  SELECT *    
  FROM @ERROR_LOG    
  
 END TRY    
 BEGIN CATCH    
  SELECT ERROR_NUMBER() AS ErrorNumber    
    ,ERROR_SEVERITY() AS ErrorSeverity    
    ,ERROR_STATE() AS ErrorState    
    ,ERROR_PROCEDURE() AS ErrorProcedure    
    ,ERROR_LINE() AS ErrorLine    
    ,ERROR_MESSAGE() AS ErrorMessage;    
 END CATCH    
END  
GO


