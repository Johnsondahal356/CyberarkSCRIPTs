function send-email {

    param(
        [Parameter(Mandatory = $false)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$FromEmail,

        [Parameter(Mandatory = $true)]
        [string[]]$ToEmail,

        [Parameter(Mandatory = $false)]
        [string[]]$cc,

        [Parameter(Mandatory = $false)]
        [string[]]$Attachment,

        [Parameter(Mandatory = $false)]
        [string]$SMTPServer,

        [switch]$BodyAsHtml,

        [Parameter(Mandatory = $false)]
        [array]$Users,

        [Parameter(Mandatory = $false)]
        [string]$TableHeader
    )

    try {
        $mailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.From = $FromEmail

        foreach ($email in $ToEmail) {
            $mailMessage.To.Add($email)
        }

        if ($cc) {
            foreach ($ccemail in $cc) {
                $mailMessage.CC.Add($ccemail)
            }
        }

        $mailMessage.Subject  = "<Message>"
        $mailMessage.Priority = [System.Net.Mail.MailPriority]::High

        # -------- BODY HANDLING --------
        if ($BodyAsHtml -and $Users -and $Users.Count -gt 0) {

            $html = @"
<html>
<head>
<style>
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid black; padding: 6px; }
th { background-color: #f2f2f2; }
caption {
    font-weight: bold;
    text-align: left;
    margin-bottom: 8px;
    font-size: 14px;
}
</style>
</head>
<body>
<p>Dear Team,</p>
"@

            # Optional table header
            if ($TableHeader) {
                $html += "<h3>$TableHeader</h3>"
            }

            $html += @"
<table>
<tr>
<th>SamAccountName</th>
<th>Full Name</th>
<th>Department</th>
<th>Branch</th>
<th>Division</th>
</tr>
"@

            foreach ($user in $Users) {
                $html += @"
<tr>
<td>$($user.SamAccountName)</td>
<td>$($user.FullName)</td>
<td>$($user.Department)</td>
<td>$($user.Branch)</td>
<td>$($user.Division)</td>
</tr>
"@
            }

            $html += @"
</table>
</body>
</html>
"@

            $mailMessage.Body = $html
            $mailMessage.IsBodyHtml = $true
        }
        else {
            $mailMessage.Body = $Message
            $mailMessage.IsBodyHtml = $false
        }

        # -------- ATTACHMENTS --------
        if ($Attachment) {
            foreach ($file in $Attachment) {
                $mailMessage.Attachments.Add(
                    [System.Net.Mail.Attachment]::new($file)
                )
            }
        }

        # -------- SEND MAIL --------
        $smtp = New-Object System.Net.Mail.SmtpClient($SMTPServer)
        $smtp.Send($mailMessage)

        Write-Host "Email sent successfully." -ForegroundColor Green
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        Write-Host "Failed to send Email!!!"
        Exit
    }
}
