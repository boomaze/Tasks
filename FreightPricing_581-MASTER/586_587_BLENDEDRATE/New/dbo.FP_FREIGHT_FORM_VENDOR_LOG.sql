CREATE TABLE [dbo].[FP_FREIGHT_FORM_VENDOR_LOG]
(
[FP_FREIGHT_FORM_VENDOR_LOG_ID] [bigint] NOT NULL IDENTITY(1, 1),
[FP_FREIGHT_FORM_VENDOR_ID] [bigint] NOT NULL,
[FP_FREIGHT_FORM_ID] [bigint] NOT NULL,
[TMS_VENDOR_ID] [bigint] NULL,
[TMS_WHS_ID] [bigint] NULL,
[FP_FF_PICKUP_LOCATIONS_ID] [bigint] NULL,
[CR_RATE_ID] [bigint] NULL,
[FP_FF_CROSSDOCK_STOPS_ID] [bigint] NULL,
[FP_FF_METHOD_ID] [bigint] NULL,
[CROSSDOCK_WHS_ID] [bigint] NULL,
[TOTAL_POS] [decimal] (18, 3) NULL,
[TOTAL_MARGIN] [decimal] (18, 3) NULL,
[TOTAL_ALLOWANCE] [decimal] (18, 3) NULL,
[TOTAL_BOOKED_FREIGHT] [decimal] (18, 3) NULL,
[OFFERED_PICKUP_ALLOWANCE] [decimal] (18, 3) NULL,
[AVERAGE_PO_WEIGHT] [decimal] (18, 3) NULL,
[AVERAGE_PO_UNITS] [decimal] (18, 3) NULL,
[AVERAGE_PALLETS_PER_PO] [decimal] (18, 3) NULL,
[PROPOSED_TOTAL_EXPENSE] [decimal] (18, 3) NULL,
[PROJECTED_LOAD_WEIGHT] [decimal] (18, 3) NULL,
[PROPOSED_ALLOWANCE_PER_LB] [decimal] (18, 6) NULL,
[PROPOSED_FREIGHT_PER_LB] [decimal] (18, 6) NULL,
[PROPOSED_TOTAL_ALLOWANCE] [decimal] (18, 3) NULL,
[PROPOSED_BOOKED_FREIGHT] [decimal] (18, 3) NULL,
[PROPOSED_PROJECTED_MARGIN] [decimal] (18, 3) NULL,
[BOOKED_FREIGHT_PER_LB] [decimal] (18, 6) NULL,
[ALLOWANCE_PER_LB] [decimal] (18, 6) NULL,
[LETTER_FREIGHT_PER_LB] [decimal] (18, 6) NULL,
[LANDED_EXPENSE_PER_LB] [decimal] (18, 6) NULL,
[CALC_RATE] [decimal] (18, 3) NULL,
[CALC_ALL_IN_RATE] [decimal] (18, 3) NULL,
[CREATED_DATE] [datetime] NULL,
[CREATED_BY] [bigint] NULL,
[MODIFIED_DATE] [datetime] NULL,
[MODIFIED_BY] [bigint] NULL,
[IS_DELETED] [bit] NULL,
[BOOKED_FREIGHT_OVERRIDE] [bit] NULL,
[PROJECTED_LOAD_WEIGHT_OVERRIDE] [bit] NULL,
[EFFECTIVE_DATE] [datetime] NULL,
[PROCESSED_FLAG] [bit] NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[FP_FREIGHT_FORM_VENDOR_LOG] ADD CONSTRAINT [PK_FP_FREIGHT_FORM_VENDOR_LOG] PRIMARY KEY CLUSTERED  ([FP_FREIGHT_FORM_VENDOR_LOG_ID]) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IDXFREIGHT_FORM_CREATED_DATE] ON [dbo].[FP_FREIGHT_FORM_VENDOR_LOG] ([FP_FREIGHT_FORM_ID]) INCLUDE ([CREATED_DATE]) ON [PRIMARY]
GO
ALTER TABLE [dbo].[FP_FREIGHT_FORM_VENDOR_LOG] ADD CONSTRAINT [FK_FP_FREIGHT_FORM_VENDOR_LOG_FP_FREIGHT_FORM_log] FOREIGN KEY ([FP_FREIGHT_FORM_ID]) REFERENCES [dbo].[FP_FREIGHT_FORM] ([FP_FREIGHT_FORM_ID])
GO
ALTER TABLE [dbo].[FP_FREIGHT_FORM_VENDOR_LOG] ADD CONSTRAINT [FK_FP_FREIGHT_FORM_VENDOR_LOG_VENDOR_ID] FOREIGN KEY ([FP_FREIGHT_FORM_VENDOR_ID]) REFERENCES [dbo].[FP_FREIGHT_FORM_VENDOR] ([FP_FREIGHT_FORM_VENDOR_ID])
GO
