function Get-SafeNameOwners {
    param (
        [Parameter(Mandatory=$true)]
        [array]$AllAccounts,

        [Parameter(Mandatory=$false)]
        [string]$OutputCsvPath = "C:\temp\SafeNameOwners.csv"
    )

    # Hashtable to cache owners per SafeName
    $safeOwnerMap = @{}
    $errorLog = @()

    # Get unique SafeNames
    $uniqueSafes = $AllAccounts | Select-Object -ExpandProperty safename -Unique

    foreach ($safe in $uniqueSafes) {

        $pattern = "MARK_$safe*"

        try {
            $groups = Get-ADGroup -Filter "Name -like '$pattern'" -Properties ManagedBy,Member -ErrorAction Stop
        }
        catch {
            $errorLog += "[$safe] Failed to get AD groups: $_"
            $safeOwnerMap[$safe] = "ERROR_GETTING_GROUP"
            continue
        }

        if (-not $groups) {
            $safeOwnerMap[$safe] = "NO_GROUP_FOUND"
            continue
        }

        # 1️⃣ Prefer group with ManagedBy
        $groupWithManager = $groups | Where-Object ManagedBy | Select-Object -First 1
        if ($groupWithManager) {
            try {
                $owner = Get-ADUser $groupWithManager.ManagedBy -Properties SamAccountName -ErrorAction Stop
                $safeOwnerMap[$safe] = $owner.SamAccountName
            }
            catch {
                $errorLog += "[$safe] Failed to get ManagedBy user: $_"
                $safeOwnerMap[$safe] = "ERROR_MANAGEDBY"
            }
            continue
        }

        # 2️⃣ No ManagedBy → collect all members from all groups
        $allMembersDN = @()
        foreach ($group in $groups) {
            if ($group.Member) { $allMembersDN += $group.Member }
        }

        # Unique members per SafeName
        $allMembersDN = $allMembersDN | Sort-Object -Unique

        if ($allMembersDN.Count -gt 0) {
            try {
                $users = Get-ADUser -Identity $allMembersDN -Properties Title,Manager -ErrorAction Stop
            }
            catch {
                $errorLog += "[$safe] Failed to get AD users from members: $_"
                $safeOwnerMap[$safe] = "ERROR_GETTING_USERS"
                continue
            }

            # 2️⃣ Pick member with title
            $titleOwner = $users | Where-Object { $_.Title -match '(?i)mgr|vp|avp|svp' } | Select-Object -First 1
            if ($titleOwner) {
                $safeOwnerMap[$safe] = $titleOwner.SamAccountName
                continue
            }

            # 3️⃣ Pick any member’s manager
            $managerDN = ($users | Where-Object Manager | Select-Object -First 1).Manager
            if ($managerDN) {
                try {
                    $mgr = Get-ADUser $managerDN -Properties SamAccountName -ErrorAction Stop
                    $safeOwnerMap[$safe] = $mgr.SamAccountName
                    continue
                }
                catch {
                    $errorLog += "[$safe] Failed to get manager of member: $_"
                    $safeOwnerMap[$safe] = "ERROR_GETTING_MANAGER"
                    continue
                }
            }
        }

        # Absolute fallback
        $safeOwnerMap[$safe] = "OWNER_NOT_FOUND"
    }

    # Expand back to all original records
    $result = foreach ($row in $AllAccounts) {
        [PSCustomObject]@{
            SafeName = $row.safename
            UserName = $row.username
            Address  = $row.address
            Owner    = $safeOwnerMap[$row.safename]
        }
    }

    # Export to CSV
    try {
        $result | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Force
        Write-Host "CSV exported to $OutputCsvPath"
    }
    catch {
        Write-Warning "Failed to export CSV: $_"
    }

    # Optional: export error log if any
    if ($errorLog.Count -gt 0) {
        $errorLogPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($OutputCsvPath), "SafeNameOwnerErrors.log")
        $errorLog | Out-File $errorLogPath -Force
        Write-Warning "Some errors occurred. See log at $errorLogPath"
    }

    return $result
}
