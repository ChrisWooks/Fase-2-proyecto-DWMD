USE [Datos Financieros];
GO


IF OBJECT_ID('dbo.vw_StageClean','V')       IS NOT NULL DROP VIEW dbo.vw_StageClean;
IF OBJECT_ID('dbo.vw_KPI_SalesFinance','V') IS NOT NULL DROP VIEW dbo.vw_KPI_SalesFinance;
GO

IF OBJECT_ID('dbo.Fact_SalesFinance','U')   IS NOT NULL DROP TABLE dbo.Fact_SalesFinance;
GO

IF OBJECT_ID('dbo.Dim_Region','U')          IS NOT NULL DROP TABLE dbo.Dim_Region;
IF OBJECT_ID('dbo.Dim_Product','U')         IS NOT NULL DROP TABLE dbo.Dim_Product;
IF OBJECT_ID('dbo.Dim_Date','U')            IS NOT NULL DROP TABLE dbo.Dim_Date;
GO


CREATE VIEW dbo.vw_StageClean AS
SELECT
     s.[Segmento]                       AS Segment,
     s.[País]                           AS Country,
     s.[Producto]                       AS Product,
     s.[Discount_Band]                  AS DiscountBand,

     TRY_CAST(REPLACE(s.[Unidades_vendidas],',','')                    AS decimal(10,1))  AS UnitsSold,
     TRY_CAST(REPLACE(REPLACE(s.[Precio_manufactura],'$',''),',','')   AS decimal(18,2))  AS MfgPrice,
     TRY_CAST(REPLACE(REPLACE(s.[Precio_de_venta],'$',''),',','')      AS decimal(18,2))  AS SalePrice,
     TRY_CAST(REPLACE(REPLACE(s.[Ventas_brutas],'$',''),',','')        AS decimal(18,2))  AS GrossSales,
     TRY_CAST(
       CASE 
         WHEN s.[Descuento] IN ('-','–','') THEN '0'
         ELSE REPLACE(REPLACE(s.[Descuento],'$',''),',','')
       END                                                           
       AS decimal(18,2)
     )                                                                  AS Discount,
     TRY_CAST(REPLACE(REPLACE(s.[Ventas],'$',''),',','')                AS decimal(18,2))  AS NetSales,
     TRY_CAST(REPLACE(REPLACE(s.[Costos],'$',''),',','')                AS decimal(18,2))  AS Costs,
     TRY_CAST(REPLACE(REPLACE(s.[Beneficio],'$',''),',','')             AS decimal(18,2))  AS Profit,

     TRY_CAST(s.[Fecha]          AS date)      AS FullDate,
     TRY_CAST(s.[Número_de_mes]  AS tinyint)   AS MonthNumber,
     s.[Nombre_de_mes]                          AS MonthName,
     TRY_CAST(s.[Año]            AS smallint)  AS YearNumber
FROM dbo.stg_FinancialData AS s;
GO

CREATE TABLE dbo.Dim_Date(
    Date_ID       int IDENTITY(1,1) PRIMARY KEY,
    FullDate      date        NOT NULL,
    DayNum        tinyint     NOT NULL,
    MonthNum      tinyint     NOT NULL,
    MonthName     nvarchar(15),
    QuarterNum    tinyint,
    YearNum       smallint    NOT NULL
);
GO

CREATE TABLE dbo.Dim_Product(
    Product_ID    int IDENTITY(1,1) PRIMARY KEY,
    ProductName   nvarchar(100),
    Category      nvarchar(50),
    Brand         nvarchar(50)
);
GO

CREATE TABLE dbo.Dim_Region(
    Region_ID     int IDENTITY(1,1) PRIMARY KEY,
    Country       nvarchar(50),
    City          nvarchar(50),
    Zone          nvarchar(50)
);
GO

CREATE TABLE dbo.Fact_SalesFinance(
    Fact_ID       bigint    IDENTITY(1,1) PRIMARY KEY,
    Date_ID       int       NOT NULL REFERENCES dbo.Dim_Date(Date_ID),
    Product_ID    int       NOT NULL REFERENCES dbo.Dim_Product(Product_ID),
    Region_ID     int       NOT NULL REFERENCES dbo.Dim_Region(Region_ID),
    NetSales      decimal(18,2),
    UnitsSold     decimal(10,1),
    SalePrice     decimal(18,2),
    Discount      decimal(18,2),
    Costs         decimal(18,2),
    Profit        decimal(18,2)
);
GO


-- Dim_Date
INSERT INTO dbo.Dim_Date(FullDate,DayNum,MonthNum,MonthName,QuarterNum,YearNum)
SELECT DISTINCT
    sc.FullDate,
    DAY(sc.FullDate),
    sc.MonthNumber,
    sc.MonthName,
    DATEPART(QUARTER,sc.FullDate),
    sc.YearNumber
FROM dbo.vw_StageClean sc
WHERE NOT EXISTS(
  SELECT 1 FROM dbo.Dim_Date d WHERE d.FullDate = sc.FullDate
);

-- Dim_Product
INSERT INTO dbo.Dim_Product(ProductName,Category,Brand)
SELECT DISTINCT
    sc.Product,
    CASE 
      WHEN sc.Product LIKE '%Premium%' THEN 'Premium'
      WHEN sc.Product LIKE '%Basic%'   THEN 'Basic'
      ELSE 'Standard'
    END,
    'Generic'
FROM dbo.vw_StageClean sc
WHERE NOT EXISTS(
  SELECT 1 FROM dbo.Dim_Product p WHERE p.ProductName = sc.Product
);

-- Dim_Region
INSERT INTO dbo.Dim_Region(Country,City,Zone)
SELECT DISTINCT
    sc.Country,
    sc.Segment,
    'N/A'
FROM dbo.vw_StageClean sc
WHERE NOT EXISTS(
  SELECT 1 FROM dbo.Dim_Region r 
   WHERE r.Country = sc.Country
     AND r.City    = sc.Segment
);
GO


INSERT INTO dbo.Fact_SalesFinance
  (Date_ID,Product_ID,Region_ID,NetSales,UnitsSold,SalePrice,Discount,Costs,Profit)
SELECT
   d.Date_ID,
   p.Product_ID,
   r.Region_ID,
   sc.NetSales,
   sc.UnitsSold,
   sc.SalePrice,
   sc.Discount,
   sc.Costs,
   sc.Profit
FROM dbo.vw_StageClean sc
JOIN dbo.Dim_Date     d ON d.FullDate      = sc.FullDate
JOIN dbo.Dim_Product  p ON p.ProductName   = sc.Product
JOIN dbo.Dim_Region   r ON r.Country       = sc.Country
                        AND r.City          = sc.Segment;
GO


CREATE VIEW dbo.vw_KPI_SalesFinance AS
SELECT
   YEAR(d.FullDate)                AS [Year],
   MONTH(d.FullDate)               AS [Month],
   r.Country,
   r.City,
   p.Category,
   SUM(f.NetSales)                 AS TotalRevenue,
   SUM(f.UnitsSold)                AS TotalUnits,
   AVG(f.SalePrice)                AS AvgUnitPrice,
   AVG(f.Discount)                 AS AvgDiscount,
   SUM(f.Profit)                   AS NetProfit,
   SUM(f.Costs)                    AS TotalCosts,
   SUM(f.NetSales)-SUM(f.Costs)    AS GrossMargin,
   CAST((SUM(f.NetSales)-SUM(f.Costs))
        /NULLIF(SUM(f.NetSales),0)*100 AS decimal(5,2)) AS GrossMarginPct
FROM dbo.Fact_SalesFinance f
JOIN dbo.Dim_Date     d ON d.Date_ID     = f.Date_ID
JOIN dbo.Dim_Product  p ON p.Product_ID  = f.Product_ID
JOIN dbo.Dim_Region   r ON r.Region_ID   = f.Region_ID
GROUP BY YEAR(d.FullDate),MONTH(d.FullDate),r.Country,r.City,p.Category;
GO


CREATE NONCLUSTERED INDEX IX_Fact_DateID    ON dbo.Fact_SalesFinance(Date_ID);
CREATE NONCLUSTERED INDEX IX_Fact_ProductID ON dbo.Fact_SalesFinance(Product_ID);
CREATE NONCLUSTERED INDEX IX_Fact_RegionID  ON dbo.Fact_SalesFinance(Region_ID);

CREATE NONCLUSTERED INDEX IX_Dim_Date_FullDate    ON dbo.Dim_Date(FullDate);
CREATE NONCLUSTERED INDEX IX_Dim_Product_Name     ON dbo.Dim_Product(ProductName);
GO

UPDATE STATISTICS dbo.Dim_Date       WITH FULLSCAN;
UPDATE STATISTICS dbo.Dim_Product    WITH FULLSCAN;
UPDATE STATISTICS dbo.Dim_Region     WITH FULLSCAN;
UPDATE STATISTICS dbo.Fact_SalesFinance WITH FULLSCAN;
GO

---------------------------------------------------------------------------------------------------
SELECT 
  (SELECT COUNT(*) FROM dbo.stg_FinancialData)   AS RawRows,
  (SELECT COUNT(*) FROM dbo.vw_StageClean)       AS CleanRows,
  (SELECT COUNT(*) FROM dbo.Fact_SalesFinance)   AS FactRows;
GO

SELECT TOP 5 *
FROM dbo.vw_KPI_SalesFinance
ORDER BY [Year],[Month];
GO




