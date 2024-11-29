if (Test-Path -Path "$PSScriptRoot\Transcript*.log") {
    Write-Host "Log files found. Attempting to move them to the Archive folder..."

    try {
        # Attempt to move the files
        Move-Item -Path "$PSScriptRoot\Transcript*.log" -Destination "$PSScriptRoot\Archive" -Force -ErrorAction Stop
        Write-Host "Files moved successfully."
    } catch {
        # Handle the error if a file is locked
        if ($_ -match "being used by another process") {
            Write-Host "File(s) locked. Attempting to find and stop locking processes..."

            # Loop through each file and handle locking
            Get-ChildItem -Path "$PSScriptRoot\Transcript*.log" | ForEach-Object {
                $lockedFile = $_.FullName

                # Identify locking processes
                $lockingProcesses = Get-Process | Where-Object {
                    $_.Modules | ForEach-Object { $_.FileName -eq $lockedFile }
                }

                if ($lockingProcesses) {
                    # Stop all locking processes
                    $lockingProcesses | ForEach-Object {
                        Write-Host "Stopping process: $($_.Name) (ID: $($_.Id))"
                        Stop-Process -Id $_.Id -Force
                    }

                    # Retry moving the file
                    try {
                        Move-Item -Path $lockedFile -Destination "$PSScriptRoot\Archive" -Force -ErrorAction Stop
                        Write-Host "File '$lockedFile' moved successfully after stopping the locking process."
                    } catch {
                        Write-Error "Failed to move '$lockedFile' even after stopping the locking process. Error: $_"
                    }
                } else {
                    Write-Error "No locking process found, but the file '$lockedFile' cannot be accessed."
                }
            }
        } else {
            Write-Error "An unexpected error occurred: $_"
        }
    }
} else {
    Write-Host "No log files found in the Transcript folder."
}
