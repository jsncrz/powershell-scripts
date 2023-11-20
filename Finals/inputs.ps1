Import-Module .\Manage-Network.psm1 -Force
Import-Module .\Manage-Logs.psm1 -Force

Clear-Host
Get-ADComputer -Filter * | Format-Table Name, PrimaryGroup, IPv4Address -AutoSize
$ComputerName = Read-Host "Please enter the computer name"
$global:computerName = $ComputerName.ToUpper()
New-LogFiles
Write-Host "Trying to connect with $ComputerName..."
Write-Log "Trying to connect with $ComputerName..."
if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet) {
    Write-Log "Connection to $ComputerName is successful."
    Clear-Host
    $CimSession = New-CimSession -ComputerName $ComputerName
    Set-ComputerNetworkConfiguration -CimSession $CimSession
    $CimSession | Remove-CimSession
} else {
    Write-Error "Cannot connect to $ComputerName. The computer is either off or doesn't exist."
    Write-Log "Cannot connect to $ComputerName. The computer is either off or doesn't exist." -Level "Error"
}
