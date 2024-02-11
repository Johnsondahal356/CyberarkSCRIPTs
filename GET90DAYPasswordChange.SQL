-- Common Table Expression (CTE) to filter and number rows
WITH CTE AS (
    -- Selecting all columns and adding a row number based on the partition of CAAINFO1 and ordering by CAATIME in descending order
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY CAAINFO1 ORDER BY CAATIME DESC) AS ROWNUM
    FROM [CYBERARK].[DBO].[CALOG]
    -- Filtering rows where CAAACTION contains 'STORE PASSWORD'
    WHERE CAAACTION LIKE '%STORE PASSWORD%'
)
-- Selecting specific columns from the CTE
SELECT 
    [CAATIME] AS 'ACTIONTIME',  -- Selecting CAATIME column and renaming it as 'ACTIONTIME'
    [CAAACTION] AS 'ACTION',     -- Selecting CAAACTION column and renaming it as 'ACTION'
    [CAASAFENAME] AS 'SAFENAME', -- Selecting CAASAFENAME column and renaming it as 'SAFENAME'
    [CAAUSERNAME] AS 'USERNAME', -- Selecting CAAUSERNAME column and renaming it as 'USERNAME'
    [CAAINFO1] AS 'ACCOUNTNAME', -- Selecting CAAINFO1 column and renaming it as 'ACCOUNTNAME'
    [CAAINTERFACEID] AS 'INTERFACE', -- Selecting CAAINTERFACEID column and renaming it as 'INTERFACE'
    [CAVAULTID] AS 'VAULTID'     -- Selecting CAVAULTID column and renaming it as 'VAULTID'
FROM CTE
-- Filtering rows where ROWNUM is less than or equal to 90
WHERE ROWNUM <= 90;


