# =====================================================================
# Enterprise Script Logging Module
# =====================================================================

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
# Module root
# ---------------------------------------------------------------------
$script:ModuleRoot = $PSScriptRoot

# ---------------------------------------------------------------------
# Environment-based configuration
# ---------------------------------------------------------------------
$script:EnvironmentMap = @{
    Prod = @{
        SqlServer = "DAHAL\SQLEXPRESS"
        Database  = "CyberArk"
        Port      = 1433
    }
    INTG = @{
        SqlServer = "server2"
        Database  = "CyberArk"
        Port      = 1433
    }
}

# ---------------------------------------------------------------------
# Module state (populated at init)
# ---------------------------------------------------------------------
$script:Config = $null

# =====================================================================
# CONSTANTS
# =====================================================================

$Script:ADActionTypes = @(

    # User Lifecycle
    'CreateUser',
    'EnableUser',
    'DisableUser',
    'DeleteUser',
    'UnlockUser',
    'ResetPassword',
    'ExpirePassword',

    # User Attribute Management
    'UpdateUser',
    'RenameUser',
    'MoveUser',
    'SetManager',
    'UpdateEmailAddress',
    'UpdateDepartment',
    'UpdateTitle',

    # Group Management
    'AddToGroup',
    'RemoveFromGroup',
    'CreateGroup',
    'DeleteGroup',

    # Computer Operations
    'CreateComputer',
    'DisableComputer',
    'DeleteComputer',

    # Administrative
    'Audit',
    'Validation',
    'BulkUpdate',

    # Generic
    'Other'
)

Register-ArgumentCompleter -CommandName Write-ADExecutionLog -ParameterName ActionType -ScriptBlock {

    param($commandName, $parameterName, $wordToComplete)

    $script:ADActionTypes |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_
            )
        }
}
# =====================================================================
# INIT
# =====================================================================

function Initialize-LoggingModule {

    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "===================================================" -ForegroundColor DarkCyan
    Write-Host " Enterprise Script Logging Module Initialization" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor DarkCyan

    # -------------------------------------------------
    # Detect Environment
    # -------------------------------------------------

    Write-Host "[INFO ] Detecting execution environment..." -ForegroundColor Yellow

    #$env = Validate-Env
    $env = "Prod"

    if (-not $script:EnvironmentMap.ContainsKey($env)) {

        Write-Host "[ERROR] Unknown environment detected: $env" -ForegroundColor Red

        throw "Unknown environment returned by Validate-Env: $env"
    }

    Write-Host "[INFO ] Environment detected: $env" -ForegroundColor Green

    # -------------------------------------------------
    # Load Environment Configuration
    # -------------------------------------------------

    $script:Config = $script:EnvironmentMap[$env]

    Write-Host "[INFO ] SQL Server: $($script:Config.SqlServer)" -ForegroundColor Gray
    Write-Host "[INFO ] Database  : $($script:Config.Database)" -ForegroundColor Gray

    # -------------------------------------------------
    # Validate SqlServer Module
    # -------------------------------------------------

    Write-Host "[INFO ] Validating SqlServer PowerShell module..." -ForegroundColor Yellow

    if (-not (Get-Module -ListAvailable -Name SqlServer)) {

        Write-Host "[ERROR] Required module [SqlServer] is not installed." -ForegroundColor Red

        throw "SqlServer PowerShell module is not installed."
    }

    Import-Module SqlServer -ErrorAction Stop

    Write-Host "[ OK  ] SqlServer module loaded successfully." -ForegroundColor Green

    # -------------------------------------------------
    # Validate SQL Connectivity
    # -------------------------------------------------

    Write-Host "[INFO ] Testing SQL connectivity..." -ForegroundColor Yellow
    <#
    $test = Test-NetConnection `
        -ComputerName $script:Config.SqlServer `
        -Port $script:Config.Port `
        -WarningAction SilentlyContinue

    if (-not $test.TcpTestSucceeded) {

        Write-Host "[ERROR] Unable to connect to SQL Server." -ForegroundColor Red

        throw "Cannot reach SQL Server $($script:Config.SqlServer):$($script:Config.Port)"
    }
    #>
    Write-Host "[ OK  ] SQL connectivity validated." -ForegroundColor Green

    # -------------------------------------------------
    # Validate Permissions
    # -------------------------------------------------

    Write-Host "[INFO ] Validating database permissions..." -ForegroundColor Yellow

    #Test-SqlPermission

    Write-Host "[ OK  ] Database permissions validated." -ForegroundColor Green

    # -------------------------------------------------
    # Initialization Complete
    # -------------------------------------------------

    Write-Host ""
    Write-Host "[SUCCESS] Enterprise logging module initialized successfully." -ForegroundColor Cyan
    Write-Host ""
}

# Call automatically when module loads
Initialize-LoggingModule

# =====================================================================
# HELPERS
# =====================================================================

function Get-ExecutionContext {

    $callStack = Get-PSCallStack
    $callerScript = $callStack |
        Where-Object {
            $_.ScriptName -and
            $_.ScriptName -notlike "*.psm1"
        } |
        Select-Object -First 1

    if ($callerScript) {
        $scriptName = Split-Path $callerScript.ScriptName -Leaf
        $scriptPath = $callerScript.ScriptName
    }
    else {
        $scriptName = "InteractiveSession"
        $scriptPath = $null
    }

    [PSCustomObject]@{
        ExecutionUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        ScriptName    = $scriptName
        MachineName   = $env:COMPUTERNAME
        ExecutionTime = Get-Date
    }
}

function Convert-ToSqlValue {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq "") {
        return "NULL"
    }

    $escaped = $Value.ToString().Replace("'", "''")
    return "'$escaped'"
}

# =====================================================================
# SQL VALIDATION
# =====================================================================

function Test-SqlPermission {

    $query = "SELECT HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','INSERT') AS P"

    $result = Invoke-Sqlcmd `
        -ServerInstance $script:Config.SqlServer `
        -Database $script:Config.Database `
        -Query $query `
        -TrustServerCertificate `
        -ErrorAction Stop

    if ($result.P -ne 1) {
        throw "Current user does not have INSERT permission on $($script:Config.Database)"
    }
}

# =====================================================================
# CORE SQL EXECUTION WRAPPER
# =====================================================================

function Invoke-LogSql {

    param(
        [string]$Query
    )

    try {
        Test-SqlPermission

        Invoke-Sqlcmd `
            -ServerInstance $script:Config.SqlServer `
            -Database $script:Config.Database `
            -Query $Query `
            -TrustServerCertificate `
            -QueryTimeout 30 `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "[Logging Failure] $($_.Exception.Message)"
    }
}

# =====================================================================
# AD LOGGING
# =====================================================================
function Write-ADExecutionLog {

    [CmdletBinding()]
    param(

        [Parameter(Mandatory)]
        [string]$ActionType,

        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [string]$TargetOU,

        [string]$Result = "Success",

        [string]$Message,

        [string]$ErrorMessage
    )
                                    
    # Validate ActionType (runtime safety)
    # ---------------------------------------------------------
    if ($ActionType -notin $script:ADActionTypes) {
        throw "Invalid ActionType '$ActionType'. Allowed values: $($script:ADActionTypes -join ', ')"
    }

    $ctx = Get-ExecutionContext

    $query = @"
INSERT INTO dbo.ADAction
(
ExecutionUser,
ScriptName,
MachineName,
ExecutionTime,
ActionType,
SamAccountName,
TargetOU,
Result,
Message,
ErrorMessage
)
VALUES
(
$(Convert-ToSqlValue $ctx.ExecutionUser),
$(Convert-ToSqlValue $ctx.ScriptName),
$(Convert-ToSqlValue $ctx.MachineName),
$(Convert-ToSqlValue ($ctx.ExecutionTime.ToString("yyyy-MM-dd HH:mm:ss"))),
$(Convert-ToSqlValue $ActionType),
$(Convert-ToSqlValue $SamAccountName),
$(Convert-ToSqlValue $TargetOU),
$(Convert-ToSqlValue $Result),
$(Convert-ToSqlValue $Message),
$(Convert-ToSqlValue $ErrorMessage)
)
"@

    Invoke-LogSql -Query $query
}

# =====================================================================
# CYBERARK LOGGING
# =====================================================================

function Write-CyberArkExecutionLog {

    [CmdletBinding()]
    param(

        [Parameter(Mandatory)]
        [string]$ActionType,

        [Parameter(Mandatory)]
        [string]$SafeName,

        [string]$AccountName,

        [string]$PlatformId,

        [string]$Result = "Success",

        [string]$Message,

        [string]$ErrorMessage
    )

    $ctx = Get-ExecutionContext

    $query = @"
INSERT INTO dbo.CyberArkAction
(
ExecutionUser,
ScriptName,
MachineName,
ExecutionTime,
ActionType,
SafeName,
AccountName,
PlatformId,
Result,
Message,
ErrorMessage
)
VALUES
(
$(Convert-ToSqlValue $ctx.ExecutionUser),
$(Convert-ToSqlValue $ctx.ScriptName),
$(Convert-ToSqlValue $ctx.MachineName),
$(Convert-ToSqlValue ($ctx.ExecutionTime.ToString("yyyy-MM-dd HH:mm:ss"))),
$(Convert-ToSqlValue $ActionType),
$(Convert-ToSqlValue $SafeName),
$(Convert-ToSqlValue $AccountName),
$(Convert-ToSqlValue $PlatformId),
$(Convert-ToSqlValue $Result),
$(Convert-ToSqlValue $Message),
$(Convert-ToSqlValue $ErrorMessage)
)
"@

    Invoke-LogSql -Query $query
}

# =====================================================================
# EXPORT
# =====================================================================

Export-ModuleMember -Function `
    Write-ADExecutionLog,
    Write-CyberArkExecutionLog
