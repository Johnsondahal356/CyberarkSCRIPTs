# Define base group name
$BaseGroup = "abc"

# Output CSV path
$OutputCsv = "C:\Temp\GroupMembershipCheck.csv"

# Prepare array to store results
$Results = @()

# Get all members of the base group
$Members = Get-ADGroupMember -Identity $BaseGroup -Recursive | Where-Object { $_.objectClass -eq 'user' }

foreach ($Member in $Members) {
    $User = Get-ADUser -Identity $Member.SamAccountName -Properties memberOf, SamAccountName

    # --- Check 1: Group membership starting with 
    $GroupMatches = @()
    foreach ($GroupDN in $User.memberOf) {
        $GroupName = (Get-ADGroup -Identity $GroupDN).Name
        if ($GroupName -match '^()') {
            $GroupMatches += $GroupName
        }
    }

    # --- Check 2: Secondary account with dot (e.g., 43324.*) ---
    $DotAccount = Get-ADUser -Filter "SamAccountName -like '$($User.SamAccountName).*'" -Properties SamAccountName |
                  Where-Object { $_.SamAccountName -ne $User.SamAccountName }

    # --- Output results ---
    if ($GroupMatches.Count -gt 0) {
        foreach ($Group in $GroupMatches) {
            $Results += [PSCustomObject]@{
                SamAccountName = $User.SamAccountName
                Type           = 'GroupMembership'
                RelatedItem    = $Group
            }
        }
    }

    if ($DotAccount) {
        foreach ($Acc in $DotAccount) {
            $Results += [PSCustomObject]@{
                SamAccountName = $User.SamAccountName
                Type           = 'DotAccount'
                RelatedItem    = $Acc.SamAccountName
            }
        }
    }

    if (($GroupMatches.Count -eq 0) -and (-not $DotAccount)) {
        $Results += [PSCustomObject]@{
            SamAccountName = $User.SamAccountName
            Type           = 'CanBeRemoved'
            RelatedItem    = ''
        }
    }
}

# Export to CSV
$Results | Export-Csv -Path $OutputCsv -NoTypeInformation

Write-Host "Results exported to $OutputCsv"
