CREATE TABLE dbo.ADAction
(
    ADActionId INT IDENTITY(1,1) PRIMARY KEY,
    ExecutionUser NVARCHAR(255),
    ScriptName NVARCHAR(255),
    MachineName NVARCHAR(255),
    ExecutionTime DATETIME,
    ActionType NVARCHAR(100),
    SamAccountName NVARCHAR(255),
    TargetOU NVARCHAR(MAX),
    Result NVARCHAR(50),
    Message NVARCHAR(MAX),
    ErrorMessage NVARCHAR(MAX)
)

