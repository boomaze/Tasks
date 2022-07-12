DECLARE @source_system VARCHAR(50) 

DECLARE db_cursor CURSOR FOR 
SELECT DISTINCT SOURCE_SYSTEM 
FROM LO_PURCHASE_ORDERS WHERE SOURCE_SYSTEM IS NOT NULL

OPEN db_cursor  
FETCH NEXT FROM db_cursor INTO @source_system 

WHILE @@FETCH_STATUS = 0  
BEGIN  
--FETCH NEXT FROM db_cursor INTO @name  
PRINT @source_system
FETCH NEXT FROM db_cursor INTO @source_system  
END 

CLOSE db_cursor  

DEALLOCATE db_cursor 