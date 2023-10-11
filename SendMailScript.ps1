#Author: Doreen

param(
    [string]$From = "fromTest@mailinator.com", 
    [string]$To = "toTest@mailinator.com", 
    [string]$Subject = "Warning!", 
    [string]$Body = "There is an error in your servers!", 
    [string]$SMTPServer)

$params = @{
    From       = $From
    To         = $To
    Subject    = $Subject
    Body       = $Body
    SMTPServer = $SMTPServer
    Port       = 25
}

try {
    Send-MailMessage @params
} catch {
    Write-Host "There is an error when sending the email"
    Write-Host @params
}
