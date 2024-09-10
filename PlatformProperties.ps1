##Generate Platform Properties using Pacli. The script logs into private ark client and Gets all the ini files from PasswordManagerShared Safe and parses it to a CSV file#

$PACLI = "<Pacli exe>"
$username = "<username>"
$password = "<Password>"
$Vault = "Vault"
$Address = "VaultAddress"

& $PACLI init
& $PACLI DEFINE Vault=`"$Vault`" Address=`"$Address`"
& $PACLI Logon Vault=`"$Vault`" User=`"$username`" Password=`"$Password`"
& $PACLI OPENSAFE Vault=`"$Vault`" User=`"$username`" SAFE="PasswordManagerShared"
$files = & $PACLI FINDFILES  Vault=`"$Vault`" User=`"$username`" SAFE="PasswordManagerShared" FOLDER="Root\Policies" output"(NAME)" | ForEach-Object {

$file = $_

& $PACLI RETRIEVEFILE  Vault=`"$Vault`" User=`"$username`" SAFE="PasswordManagershared" FOLDER="Root\Policies" FILE=`"$file`" LOCALFOLDER="$folder" LOCALFile=`"$file`"


} 

# Define the path to the folder containing .ini files
$folderPath = "C:\Test"

# Get all .ini files in the folder
$iniFiles = Get-ChildItem -Path $folderPath -Filter "*.ini"

# Create a hashtable to store all unique keys
$allKeys = @{}

# First pass: Collect all unique keys
foreach ($file in $iniFiles) {
    # Read the content of each ini file
    $fileContent = Get-Content -Path $file.FullName

    foreach ($line in $fileContent) {
        # Ignore lines with '; ' (semicolon followed by a space)
        if ($line -match '^\s*;\s') { continue }

        # Handle lines with ';key=value' or ';key='
        if ($line -match '^\s*;(\w+)=([^\s;]*)') {
            $key = $matches[1].Trim()

            # Add key to the unique keys hashtable
            $allKeys[$key] = $true
        }
        # Handle lines with 'Policy=somevalue' or any other key=value pairs
        elseif ($line -match '^\s*(\w+)=([^\s;]*)') {
            $key = $matches[1].Trim()

            # Add key to the unique keys hashtable
            $allKeys[$key] = $true
        }
    }
}

# Convert the unique keys hashtable to an array
$allKeysArray = $allKeys.Keys

# Second pass: Build CSV data with all keys
$csvData = @()

foreach ($file in $iniFiles) {
    # Read the content of each ini file
    $fileContent = Get-Content -Path $file.FullName

    # Create a hashtable for storing key-value pairs for each file
    $fileData = @{}

    foreach ($line in $fileContent) {
        # Ignore lines that have '; ' (semicolon followed by a space)
        if ($line -match '^\s*;\s') { continue }

        # Handle lines with ';key=value' or ';key=' (no space after semicolon)
        if ($line -match '^\s*;(\w+)=([^\s;]*)') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            # Add or update the key-value in the hashtable
            $fileData[$key] = $value
        }
        # Handle lines with 'Policy=somevalue' or any other key=value pairs
        elseif ($line -match '^\s*(\w+)=([^\s;]*)') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            # Add or update the key-value in the hashtable
            $fileData[$key] = $value
        }
    }

    # Initialize a new PSCustomObject for the CSV row
    $csvRow = New-Object PSCustomObject

    # Populate the CSV row with values, using all unique keys
    foreach ($key in $allKeysArray) {
        $csvRow | Add-Member -MemberType NoteProperty -Name $key -Value ($fileData[$key] -as [string])
    }

    # Add the row to the CSV data array
    $csvData += $csvRow
}

# Convert the data to a CSV format and export it
$csvPath = "$folder\Output.csv"
$csvData | Export-Csv -Path $csvPath -NoTypeInformation
