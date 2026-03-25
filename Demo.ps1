Import-Module ActiveDirectory

# ==========================
# Configuration
# ==========================

$Config = @{
    TypeDescriptionMap = @{
        "asd"  = "asd"
        "asds"  = "assd"
        "asdsa" = "asdasw"
    }
    LogFile = "C:\Logs\AD_Admin_Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

# ==========================
# Logging
# ==========================

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    Write-Output $logEntry
    Add-Content -Path $Config.LogFile -Value $logEntry
}

# ==========================
# Get Users
# ==========================

function Get-AllADUsers {
    try {
        Write-Log "Fetching AD users..."
        return Get-ADUser -Filter * -Properties Description, adminDisplayName, Manager, SamAccountName
    }
    catch {
        Write-Log "Failed to fetch AD users: $_" "ERROR"
        throw
    }
}

# ==========================
# Parse Account
# ==========================

function Parse-Account {
    param ([string]$SamAccountName)

    if ($SamAccountName -notmatch "\.") { return $null }

    $parts = $SamAccountName.Split(".")
    if ($parts.Count -lt 2) { return $null }

    return [PSCustomObject]@{
        EMPID = $parts[0]
        Type  = $parts[1]
        PrivID = $SamAccountName
    }
}

# ==========================
# Get Expected Description
# ==========================

function Get-ExpectedDescription {
    param ([string]$Type)

    if ($Config.TypeDescriptionMap.ContainsKey($Type)) {
        return $Config.TypeDescriptionMap[$Type]
    }

    return $null
}

# ==========================
# Get Manager Sam
# ==========================

function Get-ManagerSamAccountName {
    param ([string]$EMPID)

    try {
        $baseUser = Get-ADUser -Identity $EMPID -Properties Manager -ErrorAction Stop

        if (-not $baseUser.Manager) {
            Write-Log "Manager missing for $EMPID" "WARN"
            return $null
        }

        $manager = Get-ADUser -Identity $baseUser.Manager -Properties SamAccountName -ErrorAction Stop
        return $manager.SamAccountName
    }
    catch {
        Write-Log "EMPID or Manager lookup failed for $EMPID : $_" "WARN"
        return $null
    }
}

# ==========================
# Update Description
# ==========================

function Update-Description {
    param (
        $User,
        [string]$ExpectedDescription
    )

    try {
        if ($User.Description -ne $ExpectedDescription) {
            Write-Log "Updating Description for $($User.SamAccountName) -> $ExpectedDescription"

            Set-ADUser -Identity $User -Replace @{
                Description = $ExpectedDescription
            }

            Write-Log "Description updated for $($User.SamAccountName)"
        }
    }
    catch {
        Write-Log "Failed to update Description for $($User.SamAccountName): $_" "ERROR"
    }
}

# ==========================
# Update AdminDisplayName
# ==========================

function Update-AdminDisplayName {
    param (
        $User,
        [string]$ManagerSam
    )

    try {
        if ([string]::IsNullOrEmpty($User.adminDisplayName) -or $User.adminDisplayName -ne $ManagerSam) {

            Write-Log "Updating adminDisplayName for $($User.SamAccountName) -> $ManagerSam"

            Set-ADUser -Identity $User -Replace @{
                adminDisplayName = $ManagerSam
            }

            Write-Log "adminDisplayName updated for $($User.SamAccountName)"
        }
    }
    catch {
        Write-Log "Failed to update adminDisplayName for $($User.SamAccountName): $_" "ERROR"
    }
}

# ==========================
# Process User
# ==========================

function Process-User {
    param ($User)

    try {
        $parsed = Parse-Account -SamAccountName $User.SamAccountName
        if (-not $parsed) { return }

        Write-Log "Processing $($parsed.PrivID)"

        $expectedDescription = Get-ExpectedDescription -Type $parsed.Type
        if (-not $expectedDescription) {
            Write-Log "Unknown type $($parsed.Type)" "WARN"
            return
        }

        # Always ensure Description is correct
        Update-Description -User $User -ExpectedDescription $expectedDescription

        # Try to get manager
        $managerSam = Get-ManagerSamAccountName -EMPID $parsed.EMPID

        # If EMPID or manager missing → skip adminDisplayName
        if (-not $managerSam) {
            Write-Log "Skipping adminDisplayName update for $($parsed.PrivID) due to missing EMPID/Manager" "WARN"
            return
        }

        # Otherwise update adminDisplayName
        Update-AdminDisplayName -User $User -ManagerSam $managerSam
    }
    catch {
        Write-Log "Error processing $($User.SamAccountName): $_" "ERROR"
    }
}

# ==========================
# Main
# ==========================

function Start-ADAdminSync {
    try {
        Write-Log "===== Script Started ====="

        $users = Get-AllADUsers

        foreach ($user in $users) {
            Process-User -User $user
        }

        Write-Log "===== Script Completed ====="
    }
    catch {
        Write-Log "Fatal error: $_" "ERROR"
    }
}

# ==========================
# Run
# ==========================

Start-ADAdminSync
