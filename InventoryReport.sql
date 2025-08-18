/* CyberArk EVD – Account Inventory (MSSQL) */
WITH Props AS (
  SELECT
      op.CAOPSafeID,
      op.CAOPFileID,
      MAX(CASE WHEN op.CAOPObjectPropertyName = 'PolicyID'  THEN op.CAOPObjectPropertyValue END) AS PlatformID,
      MAX(CASE WHEN op.CAOPObjectPropertyName = 'UserName'  THEN op.CAOPObjectPropertyValue END) AS UserName,
      MAX(CASE WHEN op.CAOPObjectPropertyName = 'Address'   THEN op.CAOPObjectPropertyValue END) AS Address,
      MAX(CASE WHEN op.CAOPObjectPropertyName = 'DeviceType' THEN op.CAOPObjectPropertyValue END) AS DeviceType,
      MAX(CASE WHEN op.CAOPObjectPropertyName = 'CPM'       THEN op.CAOPObjectPropertyValue END) AS CPM,
      MAX(CASE WHEN op.CAOPObjectPropertyName = 'CPMStatus' THEN op.CAOPObjectPropertyValue END) AS CPMStatus
  FROM [CyberArk].[dbo].[CAObjectProperties] op
  GROUP BY op.CAOPSafeID, op.CAOPFileID
)
SELECT
    s.CASafeName                      AS SafeName,
    f.CAFFileName                     AS AccountName,      -- Vault object (account) name
    p.PlatformID,                                         -- aka PolicyID / platform
    p.DeviceType,
    p.UserName,
    p.Address,
    p.CPM,
    p.CPMStatus,
    f.CAFCreationDate                 AS CreatedOn,
    f.CAFDeletedDate                  AS DeletedOn
FROM [CyberArk].[dbo].[CAFiles]  f
JOIN [CyberArk].[dbo].[CASafes]  s  ON s.CASafeID = f.CAFSafeID
LEFT JOIN Props                  p  ON p.CAOPSafeID = f.CAFSafeID
                                   AND p.CAOPFileID = f.CAFFileID
-- keep active (non-deleted) accounts; comment this out if you want everything
WHERE f.CAFDeletedDate IS NULL
ORDER BY s.CASafeName, f.CAFFileName;
