function Write-Log {
    param (
        [string]$ScriptName,
        [string]$Message,
        [string]$LogType = "INFO"
    )

    try {
        # Define SQL connection parameters
        $serverName = "DAHAL\SQLEXPRESS"
        $databaseName = "Cyberark"
        $tableName = "LogTable"

        # Define log entry properties
        $logEntry = @{
            TimeStamp           = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            UserName            = $env:USERNAME
            MachineName         = $env:COMPUTERNAME
            ScriptName          = $ScriptName
            LogType             = $LogType
            Message             = $Message
            ScriptParameters    = $args -join ', '
            ProcessID           = $PID
            PSVersion           = $PSVersionTable.PSVersion.ToString()
            MemoryUsage_MB      = (Get-Process -Id $PID).WorkingSet64 / 1MB
            OSVersion           = (Get-CimInstance Win32_OperatingSystem).Version
            #ExecutionPolicy     = Get-ExecutionPolicy
            ExecutionPolicy     =  $user.name[0]
        }

        

        # Construct SQL query with parameterized values
        $insertQuery = @"
        INSERT INTO $tableName (TimeStamp,
         UserName, MachineName, ScriptName,
          LogType, Message, ScriptParameters, ProcessID, PSVersion, MemoryUsage_MB, 
        OSVersion, ExecutionPolicy)
        VALUES ('$($logEntry.TimeStamp)', '$($logEntry.UserName)', '$($logEntry.MachineName)', '$($logEntry.ScriptName)', 
        '$($logEntry.LogType)', '$($logEntry.Message)', '$($logEntry.ScriptParameters)', $($logEntry.ProcessID), '$($logEntry.PSVersion)', 
        $($logEntry.MemoryUsage_MB), '$($logEntry.OSVersion)', '$($logEntry.ExecutionPolicy)')
"@

        # Execute insert query using Invoke-SqlCmd
        Invoke-Sqlcmd -ServerInstance $serverName -Database $databaseName -Query $insertQuery -TrustServerCertificate
    } catch {
        Write-Error "Failed to insert log entry into SQL database: $_"
    }
}

# Get filename of the calling script
$callingScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path

# Call Write-Log function with the calling script filename
Write-Log -ScriptName $callingScriptName -Message "Test log message"
