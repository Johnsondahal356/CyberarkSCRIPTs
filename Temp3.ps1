# Define output CSV path
$OutputCsv = "C:\Temp\GroupMembersReport.csv"

# Initialize array to store results
$Results = @()

# skip

foreach ($Group in $Groups) {

    # Get members of the group
    $Members = Get-ADGroupMember -Identity $Group.SamAccountName -ErrorAction SilentlyContinue

    # If no members, add entry stating no member exists
    if (!$Members) {
        $Results += [PSCustomObject]@{
            GroupName           = $Group.Name
            MemberName          = "No member exists"
            MemberStatus        = "No member exists"
            FirstName           = ""
            LastName            = ""
            Department          = ""
            SamAccountName      = ""
            Email               = ""
        }
    } else {
        foreach ($Member in $Members) {
            $MemberBaseName = $Member.SamAccountName.Split(".")[0]

            # Regex pattern to check valid format (5 numbers + .sad/lsad or 1 letter + 4 numbers + .sad/lsad)
            if ($MemberBaseName -match '^([A-Za-z]\d{4}|\d{5})$') {

                # Try to get AD user info
                $ADUser = Get-ADUser -Identity $MemberBaseName -Properties GivenName, Surname, Department, SamAccountName, EmailAddress -ErrorAction SilentlyContinue

                if ($ADUser) {
                    $MemberStatus = "Exists"
                    $FirstName = $ADUser.GivenName
                    $LastName = $ADUser.Surname
                    $Department = $ADUser.Department
                    $SamAccountName = $ADUser.SamAccountName
                    $Email = $ADUser.EmailAddress
                } else {
                    $MemberStatus = "No longer exists"
                    $FirstName = ""
                    $LastName = ""
                    $Department = ""
                    $SamAccountName = $MemberBaseName
                    $Email = ""
                }

                $Results += [PSCustomObject]@{
                    GroupName      = $Group.Name
                    MemberName     = $Member.SamAccountName
                    MemberStatus   = $MemberStatus
                    FirstName      = $FirstName
                    LastName       = $LastName
                    Department     = $Department
                    SamAccountName = $SamAccountName
                    Email          = $Email
                }
            } else {
                # Skip members not matching the pattern
                continue
            }
        }
    }
}

# Export results to CSV
$Results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Report generated at $OutputCsv"
