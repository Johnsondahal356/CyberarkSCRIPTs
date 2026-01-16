# Hashtable to cache owners
$safeOwnerMap = @{}
# Optional: log errors
$errorLog = @()

# Get unique SafeNames for performance
$uniqueSafes = $allaccounts | Select-Object -ExpandProperty safename -Unique

foreach ($safe in $uniqueSafes) {

    $pattern = "MARK_$safe*"

    try {
        # Attempt to get matching groups
        $groups = Get-ADGroup -Filter "Name -like '$pattern'" -Properties ManagedBy -ErrorAction Stop
    }
    catch {
        $errorLog += "[$safe] Failed to get AD group: $_"
        $safeOwnerMap[$safe] = "ERROR_GETTING_GROUP"
        continue
    }

    if (-not $groups) {
        $safeOwnerMap[$safe] = "NO_GROUP_FOUND"
        continue
    }

    # Prefer group with ManagedBy
    $group = $groups | Where-Object ManagedBy | Select-Object -First 1
    if (-not $group) { $group = $groups | Select-Object -First 1 }

    # 1️⃣ ManagedBy
    if ($group.ManagedBy) {
        try {
            $owner = Get-ADUser $group.ManagedBy -Properties DisplayName,SamAccountName -ErrorAction Stop
            $safeOwnerMap[$safe] = $owner.SamAccountName
        }
        catch {
            $errorLog += "[$safe] Failed to get ManagedBy user: $_"
            $safeOwnerMap[$safe] = "ERROR_MANAGEDBY"
        }
        continue
    }

    # 2️⃣ Check members for title
    try {
        $members = Get-ADGroupMember $group.DistinguishedName -Recursive -ErrorAction Stop |
                   Where-Object ObjectClass -eq 'user'
    }
    catch {
        $errorLog += "[$safe] Failed to get group members: $_"
        $safeOwnerMap[$safe] = "ERROR_GETTING_MEMBERS"
        continue
    }

    if ($members) {
        try {
            $users = Get-ADUser $members -Properties Title,Manager -ErrorAction Stop
        }
        catch {
            $errorLog += "[$safe] Failed to get AD users from members: $_"
            $safeOwnerMap[$safe] = "ERROR_GETTING_USERS"
            continue
        }

        $titleOwner = $users | Where-Object { $_.Title -match '(?i)mgr|vp|avp|svp' } | Select-Object -First 1
        if ($titleOwner) {
            $safeOwnerMap[$safe] = $titleOwner.SamAccountName
            continue
        }

        # 3️⃣ Fallback: any member's manager
        $managerDN = ($users | Where-Object Manager | Select-Object -First 1).Manager
        if ($managerDN) {
            try {
                $mgr = Get-ADUser $managerDN -Properties SamAccountName -ErrorAction Stop
                $safeOwnerMap[$safe] = $mgr.SamAccountName
            }
            catch {
                $errorLog += "[$safe] Failed to get manager of member: $_"
                $safeOwnerMap[$safe] = "ERROR_GETTING_MANAGER"
            }
            continue
        }
    }

    # Absolute fallback
    $safeOwnerMap[$safe] = "OWNER_NOT_FOUND"
}

# Expand back to original 1000 records
$result = foreach ($row in $allaccounts) {
    [PSCustomObject]@{
        SafeName = $row.safename
        UserName = $row.username
        Address  = $row.address
        Owner    = $safeOwnerMap[$row.safename]
    }
}

# Optional: export errors
if ($errorLog.Count -gt 0) {
    $errorLog | Out-File "C:\temp\AD_Owner_Errors.log"
}
