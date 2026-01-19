function Get-CyberArkSafeOwnersEnriched {

    param (
        [Parameter(Mandatory = $true)]
        [array]$AllAccounts,

        [Parameter(Mandatory = $false)]
        [string]$OutputCsvPath = "C:\temp\FinalSafeOwners.csv",

        [Parameter(Mandatory = $false)]
        [string]$CyberArkBaseURI = "https://cyberark.company.com"
    )

    Write-Host "[INFO] Loading required modules..."
    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module PSPAS -ErrorAction Stop

    # ==============================
    # CYBERARK SESSION
    # ==============================

    Write-Host "[INFO] Connecting to CyberArk..."
    New-PASSession -BaseURI $CyberArkBaseURI `
                   -Credential (Get-Credential) `
                   -Type RADIUS

    # ==============================
    # SAFE OWNER RESOLUTION (AD)
    # ==============================

    Write-Host "[INFO] Resolving Safe owners using AD..."

    $safeOwnerMap = @{}
    $errorLog = @()

    $uniqueSafes = $AllAccounts | Select-Object -ExpandProperty safename -Unique

    foreach ($safe in $uniqueSafes) {

        Write-Host "[TRACE] Resolving owner for Safe: $safe"

        $pattern = "MARK_$safe*"

        try {
            $groups = Get-ADGroup -Filter "Name -like '$pattern'" `
                                  -Properties ManagedBy,Member `
                                  -ErrorAction Stop
        }
        catch {
            Write-Host "[ERROR] AD group lookup failed for $safe" -ForegroundColor Red
            $safeOwnerMap[$safe] = "ERROR_GETTING_GROUP"
            continue
        }

        if (-not $groups) {
            $safeOwnerMap[$safe] = "NO_GROUP_FOUND"
            continue
        }

        # 1️⃣ Prefer ManagedBy
        $groupWithManager = $groups | Where-Object ManagedBy | Select-Object -First 1
        if ($groupWithManager) {
            try {
                $owner = Get-ADUser $groupWithManager.ManagedBy `
                                   -Properties SamAccountName `
                                   -ErrorAction Stop
                $safeOwnerMap[$safe] = $owner.SamAccountName
                continue
            }
            catch {
                $safeOwnerMap[$safe] = "ERROR_MANAGEDBY"
                continue
            }
        }

        # 2️⃣ Members fallback
        $allMembersDN = @()
        foreach ($group in $groups) {
            if ($group.Member) { $allMembersDN += $group.Member }
        }

        $allMembersDN = $allMembersDN | Sort-Object -Unique

        if ($allMembersDN.Count -gt 0) {
            try {
                $users = Get-ADUser -Identity $allMembersDN `
                                   -Properties Title,Manager `
                                   -ErrorAction Stop
            }
            catch {
                $safeOwnerMap[$safe] = "ERROR_GETTING_USERS"
                continue
            }

            $titleOwner = $users |
                Where-Object { $_.Title -match '(?i)mgr|vp|avp|svp' } |
                Select-Object -First 1

            if ($titleOwner) {
                $safeOwnerMap[$safe] = $titleOwner.SamAccountName
                continue
            }

            $managerDN = ($users | Where-Object Manager | Select-Object -First 1).Manager
            if ($managerDN) {
                try {
                    $mgr = Get-ADUser $managerDN -Properties SamAccountName -ErrorAction Stop
                    $safeOwnerMap[$safe] = $mgr.SamAccountName
                    continue
                }
                catch {
                    $safeOwnerMap[$safe] = "ERROR_GETTING_MANAGER"
                    continue
                }
            }
        }

        $safeOwnerMap[$safe] = "OWNER_NOT_FOUND"
    }

    # ==============================
    # EXPAND TO BASE RESULT
    # ==============================

    Write-Host "[INFO] Building base dataset..."

    $baseResult = foreach ($row in $AllAccounts) {
        [PSCustomObject]@{
            SafeName = $row.safename
            UserName = $row.username
            Address  = $row.address
            Owner    = $safeOwnerMap[$row.safename]
        }
    }

    # ==============================
    # CHECK OWNER_NOT_FOUND
    # ==============================

    $ownerNotFound = $baseResult | Where-Object { $_.Owner -eq 'OWNER_NOT_FOUND' }

    if ($ownerNotFound.Count -eq 0) {
        Write-Host "[INFO] All Safes have owners. Exporting CSV..."

        $baseResult | Export-Csv $OutputCsvPath -NoTypeInformation -Force
        Close-PASSession
        return $baseResult
    }

    Write-Host "[WARNING] OWNER_NOT_FOUND count: $($ownerNotFound.Count)"

    # ==============================
    # APPLICATION LOOKUP (ONE CALL)
    # ==============================

    Write-Host "[INFO] Retrieving CyberArk applications..."
    $applications = Get-PASApplication

    $appDescLookup = @{}
    foreach ($app in $applications) {
        $appDescLookup[$app.AppID] = $app.Description
    }

    # ==============================
    # SAFE DESCRIPTION CACHE
    # ==============================

    $safeDescCache = @{}

    # ==============================
    # ENRICH OWNER_NOT_FOUND
    # ==============================

    Write-Host "[INFO] Enriching OWNER_NOT_FOUND records..."

    $enrichedOwnerNotFound = foreach ($row in $ownerNotFound) {

        Write-Host "[TRACE] Enriching Safe: $($row.SafeName)"

        if (-not $safeDescCache.ContainsKey($row.SafeName)) {
            try {
                $safe = Get-PASSafe -SafeName $row.SafeName
                $safeDescCache[$row.SafeName] = $safe.Description
            }
            catch {
                Write-Host "[ERROR] Failed to retrieve Safe $($row.SafeName)" -ForegroundColor Red
                $safeDescCache[$row.SafeName] = $null
            }
        }

        [PSCustomObject]@{
            SafeName  = $row.SafeName
            UserName  = $row.UserName
            Address   = $row.Address
            Owner     = $row.Owner
            SafeDesc  = $safeDescCache[$row.SafeName]
            AppIDDesc = $appDescLookup[$row.SafeName]
        }
    }

    # ==============================
    # FINAL MERGE & EXPORT
    # ==============================

    Write-Host "[INFO] Merging final dataset..."

    $finalResult = @(
        $baseResult | Where-Object { $_.Owner -ne 'OWNER_NOT_FOUND' }
        $enrichedOwnerNotFound
    )

    Write-Host "[INFO] Exporting final CSV to $OutputCsvPath"
    $finalResult | Export-Csv $OutputCsvPath -NoTypeInformation -Force

    Close-PASSession
    Write-Host "[SUCCESS] Function completed successfully"

    return $finalResult
}
