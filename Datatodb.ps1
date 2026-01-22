function Write-DatasetToSql {
    param (
        [Parameter(Mandatory)]
        [array]$FinalResult
    )

    $server   = "server1"
    $database = "database1"
    $table    = "dataset"

    $connectionString = "Server=$server;Database=$database;Integrated Security=True;TrustServerCertificate=True;"

    $connection = $null

    # ---- Validate input early ----
    if (-not $FinalResult -or $FinalResult.Count -eq 0) {
        return @{
            Success = $false
            Stage   = "Validation"
            Message = "FinalResult is empty or null."
        }
    }

    try {
        # ---- Connection ----
        try {
            $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
            $connection.Open()
        }
        catch {
            return @{
                Success = $false
                Stage   = "Connection"
                Message = $_.Exception.Message
            }
        }

        # ---- Truncate ----
        try {
            $truncateCmd = $connection.CreateCommand()
            $truncateCmd.CommandText = "TRUNCATE TABLE dbo.$table"
            $truncateCmd.ExecuteNonQuery() | Out-Null
        }
        catch {
            return @{
                Success = $false
                Stage   = "Truncate"
                Message = $_.Exception.Message
            }
        }

        # ---- Build DataTable ----
        try {
            $dataTable = New-Object System.Data.DataTable

            $null = $dataTable.Columns.Add("Objectname",     [string])
            $null = $dataTable.Columns.Add("EnvironmentID",  [string])
            $null = $dataTable.Columns.Add("Alias",          [string])
            $null = $dataTable.Columns.Add("Safename",       [string])
            $null = $dataTable.Columns.Add("Username",       [string])

            foreach ($row in $FinalResult) {
                $dr = $dataTable.NewRow()
                $dr.Objectname    = $row.Objectname
                $dr.EnvironmentID = $row.EnvironmentID
                $dr.Alias         = $row.Alias
                $dr.Safename      = $row.Safename
                $dr.Username      = $row.Username
                $dataTable.Rows.Add($dr)
            }
        }
        catch {
            return @{
                Success = $false
                Stage   = "DataBuild"
                Message = $_.Exception.Message
            }
        }

        # ---- Bulk Copy ----
        try {
            $bulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy $connection
            $bulkCopy.DestinationTableName = "dbo.$table"
            $bulkCopy.BulkCopyTimeout = 0
            $bulkCopy.BatchSize = 5000

            $bulkCopy.ColumnMappings.Add("Objectname",     "Objectname")     | Out-Null
            $bulkCopy.ColumnMappings.Add("EnvironmentID",  "EnvironmentID")  | Out-Null
            $bulkCopy.ColumnMappings.Add("Alias",          "Alias")          | Out-Null
            $bulkCopy.ColumnMappings.Add("Safename",       "Safename")       | Out-Null
            $bulkCopy.ColumnMappings.Add("Username",       "Username")       | Out-Null

            $bulkCopy.WriteToServer($dataTable)
        }
        catch {
            return @{
                Success = $false
                Stage   = "BulkCopy"
                Message = $_.Exception.Message
            }
        }

        # ---- Success ----
        return @{
            Success = $true
            Stage   = "Completed"
            Message = "Dataset exported successfully."
        }
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
        }
    }
}
