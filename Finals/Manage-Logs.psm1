function New-LogFiles {
    <#
    .SYNOPSIS
        PowerShell script that creates the log folder and files
    .DESCRIPTION
        The script creates the neccessary files for logging
    .NOTES
        Version:        1.0
        Author:         Jason Cruz
        Creation Date:  11152023
        Purpose/Change: Initial script development
    #>
    $logFolder = "C:\logs"
    $log = "C:\logs\$($global:computerName)_log.txt"
    $errorLog = "C:\logs\$($global:computerName)_error-log.txt"

    if ((Test-Path $logFolder) -eq $false) {
        $null = New-Item -Path $logFolder -ItemType "Directory"
    }
    if ((Test-Path $log) -eq $false) {
        $null = New-Item -Path $log -ItemType "File"
    }
    if ((Test-Path $errorLog) -eq $false) {
        $null = New-Item -Path $errorLog -ItemType "File"
    } 
}

function Write-Log {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [String]$Message,
        [Parameter(Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        [String]$Level = "Information"
    )
    <#
    .SYNOPSIS
        PowerShell script that writes the log 
    .DESCRIPTION
        The script writes to information and error level log file.
    .PARAMETER Message
        The message to be written in the log file
    .PARAMETER Level
        The level of the message to be written
    .NOTES
        Version:        1.0
        Author:         Jason Cruz
        Creation Date:  11152023
        Purpose/Change: Initial script development
    #>
    $log = "C:\logs\$($global:computerName)_log.txt"
    $errorLog = "C:\logs\$($global:computerName)_error-log.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $completeMessage = "$timestamp [$currentUser]:[$level] --- $Message"
    if ($Level -eq "Information") {
        Add-Content -Path $log $completeMessage
    }
    elseif ($Level -eq "Error") {
        Add-Content -Path $errorLog $completeMessage
    }
}

Export-ModuleMember -Function New-LogFiles
Export-ModuleMember -Function Write-Log
