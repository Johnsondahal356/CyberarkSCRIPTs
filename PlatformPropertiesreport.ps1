# Define the script as a cmdlet with parameters
[CmdletBinding()]
param(

    # Parameter for specifying the environment
    [parameter(Mandatory = $TRUE,
               HelpMessage="Enter the environment where you want to run this script."
    )]
    $EnvironmentType,

    # Parameter for specifying the path to save the report
    [Parameter(Mandatory=$TRUE,
               HelpMessage="Enter the location to Save the report."
    )]
    $Path,

    # Parameter for specifying the authentication type
    [parameter(Mandatory = $TRUE,
               HelpMessage="Enter the authentication type."
    )]
    [string]$AuthenticationType

)



# Validate the input parameters
# Ensure that the provided values are valid and meet the requirements

# Validate the EnvironmentType parameter
if ($EnvironmentType -notin @("DEV", "uat", "sit", "Perf", "Production")) {
    Write-Output "Invalid Environment Selection"
    exit 1 # Exit the script with a non-zero exit code to indicate failure
}

# Based on the selected environment, set the BaseURI
# This variable will be used to construct the URI for making API requests
if ($EnvironmentType -eq "DEV") {
    $BaseURI= "<HOSTNAME>"  # Change this to the appropriate hostname for the DEV environment
}
elseif ($EnvironmentType -eq "uat") {
    $BaseURI= "<HOSTNAME>"  # Change this to the appropriate hostname for the UAT environment
}
elseif ($EnvironmentType -eq "sit") {
    $BaseURI= "<HOSTNAME>"  # Change this to the appropriate hostname for the SIT environment
}
elseif ($EnvironmentType -eq "Perf") {
    $BaseURI= "<HOSTNAME>"  # Change this to the appropriate hostname for the Perf environment
}
elseif ($EnvironmentType -eq "Production") {
    $BaseURI= "<HOSTNAME>"  # Change this to the appropriate hostname for the Production environment
}

# Once the input parameters are validated and the BaseURI is set, you can proceed with the main logic of the script
# This typically involves fetching data, processing it, and generating the desired output





# Global URLS
# -----------
$PVWAURL= $BaseURI+"/PasswordVault"


# Based on the selected AuthenticationType, set the URLs for logon and logoff
if ($AuthenticationType -eq "CyberArk") {
    # If CyberArk authentication is selected
    $URL_Logon = $PVWAURL + "/API/Auth/Cyberark/Logon"
    $URL_Logoff = $PVWAURL + "/API/Auth/logoff"
}
elseif ($AuthenticationType -eq "RADIUS") {
    # If RADIUS authentication is selected
    $URL_Logon = $PVWAURL + "/API/Auth/RADIUS/Logon"
    $URL_Logoff = $PVWAURL + "/API/Auth/logoff"
}
elseif ($AuthenticationType -eq "LDAP") {
    # If LDAP authentication is selected
    $URL_Logon = $PVWAURL + "/API/Auth/LDAP/Logon"
    $URL_Logoff = $PVWAURL + "/API/Auth/logoff"
}
elseif ($AuthenticationType -eq "Windows") {
    # If Windows authentication is selected
    $URL_Logon = $PVWAURL + "/API/Auth/Windows/Logon"
    $URL_Logoff = $PVWAURL + "/API/Auth/logoff"
}
else {
    # If an invalid authentication type is provided
    Write-Output "Invalid authentication type! Session terminated."
    exit
}

#end region       
        


# Add a .NET type with C# code to define a custom policy for trusting all certificates
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

# Set the certificate policy to use the custom TrustAllCertsPolicy
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Set the security protocol to use SSL 3.0, TLS 1.0, TLS 1.1, and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12

# End of Region


#region [Logon]

# Get Credentials to Login
# Prompt the user to enter their username and password
$caption = "Login to Script"
$msg = "Enter your User name and Password"
$creds = $Host.UI.PromptForCredential($caption, $msg, "", "")
$username = $creds.username.Replace('\', '')  # Remove any backslashes from the username
$password = $creds.GetNetworkCredential().password  # Retrieve the password from the credential object

# Create the POST Body for the Logon
# Convert the credentials to JSON format for the logon request body
$logonBody = @{
    username = $username  # Set the username field in the JSON body
    password = $password  # Set the password field in the JSON body
}
$logonBody = $logonBody | ConvertTo-Json  # Convert the PowerShell object to JSON format

try {
    # Logon
    # Make a POST request to the logon URL with the logon body
    $logonResult = Invoke-RestMethod -Method Post -Uri $URL_Logon -Body $logonBody -ContentType "application/json"
    # Save the Logon Result - The Logon Token
    $logonToken = $logonResult  # Store the logon token returned from the server
} catch {
    # Handle any errors that occur during the logon process
    Write-Host -ForegroundColor Red $_.Exception.Response.StatusDescription  # Display the error message
    $logonToken = ""  # Set the logon token to empty
}

# If the logon token is empty, display an error message and exit the script
If ($logonToken -eq "") {
    Write-Host -ForegroundColor Red "Logon Token is Empty - Cannot login"  # Display an error message
    exit  # Exit the script
}

# Create a Logon Token Header
# This header will be used throughout the script for authentication
$logonHeader = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$logonHeader.Add("Authorization", $logonToken)  # Add the logon token to the header

#endregion



##


$Getplatformid = $PVWAURL + "/Api/Platforms" #PlatformID URL
try
 {
$Platform_ID = Invoke-RestMethod -Method get -Uri $Getplatformid -Headers $logonHeader -ContentType "application/json" | 
    Select-Object -ExpandProperty Platforms | 
    Select-Object -ExpandProperty General | 
    Select-Object id
    }

catch {

Write-Host $_

}
foreach ($value in $Platform_ID) {
    $id = $value.id
    try {
        $GetPlReport = $PVWAURL + "/Api/platforms/$id"
        $GetPtrmreport = Invoke-RestMethod -Method Get -Uri $GetPlReport -Headers $logonHeader -ContentType "application/json"

        $platformDetails = $GetPtrmreport.Details

        # Extract all properties dynamically
        $platformData = @{}
        $platformDetails.PSObject.Properties | ForEach-Object {
            $propertyName = $_.Name -replace '[^A-Za-z0-9_]', '_'  # Replace invalid characters with underscores
            $propertyValue = $_.Value

            # Check for null values or unexpected data types
            if ($propertyValue -eq $null) {
                $propertyValue = ""
            }
            elseif ($propertyValue -is [System.Collections.IEnumerable] -and $propertyValue -isnot [string]) {
                # Convert enumerable types to string
                try {
                    $propertyValue = $propertyValue -join ","
                } catch {
                    Write-Host "Error converting enumerable value to string: $_"
                    $propertyValue = ""
                }
            }

            # Handle non-string property names
            try {
                $platformData[$propertyName] = $propertyValue
            } catch {
                Write-Host "Error setting property '$propertyName': $_"
            }
        }

        # Check if platformData is empty
        if ($platformData.Count -eq 0) {
            Write-Host "Platform data is empty. Skipping CSV export."
        }
        else {
            # Export platform data to CSV
            $platformObject = New-Object PSObject -Property $platformData
            $platformObject | Export-Csv $Path\Plt.csv -NoTypeInformation -Append -Force
            Write-Host "Platform data exported to CSV successfully."
        }
    }
    catch {
        Write-Host "Error fetching or exporting platform details: $_"
    }
}





# Logoff the session
# Close the session to release resources
Write-Host "Logoff Session..."
try {
    Invoke-RestMethod -Method Post -Uri $URL_Logoff -Headers $logonHeader -ContentType "application/json" | Out-Null
} catch {
    # Handle errors during logoff
    Write-Host -ForegroundColor Red "Error logging off the session: $_"
}

# Script completion message
$Date = Get-Date
Write-Host "Script Ended at time $Date"

    