# PowerShell script to upload a log file to CyberArk using PACLI
# ---------------------------------------------------------------
# This script initializes PACLI, logs in, opens the safe, uploads the file, then closes and logs off.
# It includes error checking after each PACLI command.

# ========== CONFIGURATION ==========
# Path to the PACLI executable (update this path to where pacli.exe is installed)
$pacliExe = "<PACLIEXE>"
if (!(Test-Path $pacliExe)) {
    Write-Error "PACLI executable not found at $pacliExe. Update the path."
    exit 1
}

# Vault connection details (replace with your environment values)
$vaultName = "YourVaultName"           # CyberArk Vault name
$vaultAddress = "your.vault.address"   # CyberArk Vault IP or DNS
$vaultPort    = <Port>                  # Vault port 

# Safe and file details
$safeName      = "<Safename>"             # Target safe name
$folderName    = "Root"                # Folder inside the safe
$localFolder   = "<LogFolder>"             # Local directory of the log file
$localFileName = "<FileName>"             # Name of the log file to upload

# Prompt for CyberArk user credentials
$username = Read-Host "Enter CyberArk username"
$securePassword = Read-Host "Enter CyberArk password" -AsSecureString
$passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordPtr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)

# Check that the local file exists before calling PACLI
$sourceFilePath = Join-Path $localFolder $localFileName
if (!(Test-Path $sourceFilePath)) {
    Write-Error "Local file '$sourceFilePath' not found. Exiting."
    exit 1
}

# Function to run a PACLI command and capture output and exit code
function Run-PacliCommand {
    param([string]$Arguments)
    Write-Host "Executing: pacli $Arguments"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pacliExe
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute       = $false
    $psi.CreateNoWindow        = $true

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-Error "Failed to start PACLI: $_"
        exit 1
    }

    $stdOut = $proc.StandardOutput.ReadToEnd()
    $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return [PSCustomObject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdOut.Trim()
        StdErr   = $stdErr.Trim()
    }
}

# ========== PACLI COMMAND SEQUENCE ==========

# 1. Initialize PACLI session
$res = Run-PacliCommand "INIT"
if ($res.ExitCode -ne 0) {
    Write-Error "PACLI INIT failed: $($res.StdErr)$($res.StdOut)"
    exit 1
}

# 2. Define Vault (address and port)
$res = Run-PacliCommand "DEFINE VAULT=`"$vaultName`" ADDRESS=$vaultAddress PORT=$vaultPort"
if ($res.ExitCode -ne 0) {
    Write-Error "PACLI DEFINE failed: $($res.StdErr)$($res.StdOut)"
    exit 1
}

# 3. Log on to the Vault
$res = Run-PacliCommand "LOGON VAULT=`"$vaultName`" USER=`"$username`" PASSWORD=`"$password`""
if ($res.ExitCode -ne 0) {
    Write-Error "Failed to log on to Vault. Check credentials. Error: $($res.StdErr)"
    exit 1
}

# 4. Open the Safe 'tm-test'
$res = Run-PacliCommand "OPENSAFE VAULT=`"$vaultName`" USER=`"$username`" SAFE=`"$safeName`""
if ($res.ExitCode -ne 0) {
    Write-Error "Failed to open Safe '$safeName'. Check safe name/permissions. Error: $($res.StdErr)"
    # Clean up and exit
    Run-PacliCommand "LOGOFF VAULT=`"$vaultName`" USER=`"$username`"" | Out-Null
    Run-PacliCommand "TERM" | Out-Null
    exit 1
}

# 5. Store (upload) the log file into the Safe
$res = Run-PacliCommand "STOREFILE VAULT=`"$vaultName`" USER=`"$username`" SAFE=`"$safeName`" FOLDER=`"$folderName`" FILE=`"$localFileName`" LOCALFOLDER=`"$localFolder`" LOCALFILE=`"$localFileName`""
if ($res.ExitCode -ne 0) {
    Write-Error "Failed to store file '$localFileName' in Safe '$safeName'. Error: $($res.StdErr)"
    # Attempt to close safe and log off before exiting
    Run-PacliCommand "CLOSESAFE VAULT=`"$vaultName`" USER=`"$username`" SAFE=`"$safeName`"" | Out-Null
    Run-PacliCommand "LOGOFF VAULT=`"$vaultName`" USER=`"$username`"" | Out-Null
    Run-PacliCommand "TERM" | Out-Null
    exit 1
}
Write-Host "File '$localFileName' uploaded successfully to Safe '$safeName'."

# 6. Close the Safe
$res = Run-PacliCommand "CLOSESAFE VAULT=`"$vaultName`" USER=`"$username`" SAFE=`"$safeName`""
if ($res.ExitCode -ne 0) {
    Write-Warning "Warning: CLOSESAFE failed: $($res.StdErr)"
}

# 7. Log off and terminate session
$res = Run-PacliCommand "LOGOFF VAULT=`"$vaultName`" USER=`"$username`""
if ($res.ExitCode -ne 0) {
    Write-Error "LOGOFF failed: $($res.StdErr)"
}
$res = Run-PacliCommand "TERM"
if ($res.ExitCode -ne 0) {
    Write-Error "PACLI termination failed: $($res.StdErr)"
}

Write-Host "PACLI session terminated."
