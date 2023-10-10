function GetPerformanceForComputer {
    param (
		[Parameter(Mandatory)]
        [string]$ComputerName
    )
    Write-Host "Getting usage data from computer:" $ComputerName
    #Get CPU Usage from processor data
    $processorData = Get-CimInstance -ClassName Win32_Processor -ComputerName $ComputerName
    $cpuUsage = $processorData.LoadPercentage
    #Get RAM Usage from OS data
    $osData = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName
    $ramUsage = (($osData.TotalVisibleMemorySize - $osData.FreePhysicalMemory) / $osData.TotalVisibleMemorySize) * 100
    #Get disk C details
    $disks = Get-CimInstance Win32_LogicalDisk -ComputerName $computer.Name -Filter "DeviceID = 'C:'"
    #Create a hash table for easier handling in CSV
    try {
	$computerProperties = [ordered]@{
	    ComputerName = $ComputerName
	    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	    CpuUsage = [math]::Round($cpuUsage, 2)
	    RamUsage = [math]::Round($ramUsage, 2)
	    FreeDiskGbInC = [math]::Round($disks.FreeSpace / 1Gb, 2)
	    DiskUsagePercentInC =  [math]::Round(100 - (($disks.FreeSpace / $disks.Size) * 100), 2)
	}
    } catch {
	$computerProperties = [ordered]@{
	    ComputerName = $ComputerName
	    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	    CpuUsage = [int]($cpuUsage)
	    RamUsage = [int]($ramUsage)
	    FreeDiskGbInC = [int]($disks.FreeSpace / 1Gb)
	    DiskUsagePercentInC =  [int](100 - (($disks.FreeSpace / $disks.Size) * 100))
	}
    }
    $computerData = New-Object -TypeName psobject -Property $computerProperties
    return $computerData;
}

function CheckForThresholdsAndNotify {
    param (
		[Parameter(Mandatory)]
        [string]$ComputerName,
		[Parameter(Mandatory)]
        [PsCustomObject]$ComputerData
    )
    $mailContent = $null
    $mailSubject = "Alert in your performance thresholds!"
    $hasCriticalAlert = $false
    # Check the CPU usage if over 90% or over 70%
    if ($ComputerData.CpuUsage -ge 90) {
    	$hasCriticalAlert = $true
        $mailContent = $mailContent + "Critical! CPU Usage is " + $ComputerData.CpuUsage + "%`n"
    } elseif ($ComputerData.CpuUsage -ge 70) {
        $mailContent = $mailContent + "Warning! CPU Usage is " + $ComputerData.CpuUsage + "%`n"
    }
    # Check the Ram usage if over 90% or over 70%
    if ($ComputerData.RamUsage -ge 90 ) {
    	$hasCriticalAlert = $true
        $mailContent = $mailContent + "Critical! RAM Usage is " + $ComputerData.RamUsage + "%`n"
    } elseif ($ComputerData.RamUsage -ge 70) {
        $mailContent = $mailContent + "Warning! RAM Usage is " + $ComputerData.RamUsage + "%`n"
    }
    # Check the percentage of free disk space if over 90% or over 70%
    if ($ComputerData.DiskUsagePercentInC -ge 90 ) {
    	$hasCriticalAlert = $true
        $mailContent = $mailContent + "Critical! Disk is already " + $ComputerData.DiskUsagePercentInC + "% full`n"
    } elseif ($ComputerData.DiskUsagePercentInC -ge 70) {
        $mailContent = $mailContent + "Warning! Disk is already " + $ComputerData.DiskUsagePercentInC + "% full`n"
    }
    # Call the email function here
    if ($null -ne $mailContent) {
    	if ($hasCriticalAlert -eq $true) {
     	    $mailSubject = "Critical alert in your performance thresholds!"
     	}
      	#Replace this with the call to the mailing script
        Write-Host $mailContent
    }
}

function WriteToCsv {
    param (
		[Parameter(Mandatory)]
        [string]$ComputerName,
		[Parameter(Mandatory)]
        [PsCustomObject]$Data,
		[Parameter(Mandatory)]
        [string]$Folder
    )
    $date = Get-Date -Format FileDate
    # Create the folder if it doesn't exist
    $folderName = "c:\HealthCheck\" + $Folder
    $null = New-Item -Path $folderName -ItemType Directory -Force
    $csvFileName = "c:\HealthCheck\" +$Folder + "\" + $ComputerName + "_" + $date + ".csv"
    Write-Host "Writing csv in " $csvFileName
    $Data | Export-CSV -Path $csvFileName -Append -NoTypeInformation -Force
}


function GetImportantServicesStatus {
    param (
		[Parameter(Mandatory)]
        [string]$ComputerName
    )
    Write-Host "Checking  for failed service for computer:" $ComputerName
    $computerServices = [PsCustomObject]@{
        ComputerName = $ComputerName
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $mailContent = $null
    #Get all services having the names: Dnscache, Spooler, RpcSs, W32Time, Netlogon
    $services = Get-CimInstance -Query 'SELECT * from Win32_Service WHERE (Name = "Dnscache" OR Name = "Spooler" OR Name = "RpcSs" OR Name = "W32Time" OR Name = "Netlogon")' -ComputerName $ComputerName | Sort-Object -Property Name
    foreach ($service in $services) {
        $computerServices | Add-Member -MemberType NoteProperty -Name $service.Name -Value $service.state
        if ($service.state -eq "Stopped") {
            if ($null -eq $mailContent) {
                $mailContent = "The following services are currently not running:`n"
            }
            $mailContent = $mailContent + $service.Name + "`n"
        }
        # Should we start the services here?
        # $service | Invoke-CimMethod -Name StartService -ComputerName $ComputerName
    }
    # Call the email function here
    if ($null -ne $mailContent) {
      	#Replace this with the call to the mailing script
        Write-Host $mailContent
    }
    return $computerServices
}


function MonitorAdComputers {
    $computers = Get-ADComputer -filter * | Select-Object Name
    foreach ($computer in $computers)
    {
        # Test if the computer in AD can be pinged
        if (Test-Connection -ComputerName $computer.Name -Quiet) {
            $computerData = GetPerformanceForComputer -ComputerName $computer.Name
            CheckForThresholdsAndNotify -ComputerName $computer.Name -ComputerData $computerData
            WriteToCsv -ComputerName $computer.Name -Data $computerData -Folder "Usage"
            $computerServices = GetImportantServicesStatus -ComputerName $computer.Name
            WriteToCsv -ComputerName $computer.Name -Data $computerServices -Folder "ServiceStat"
        } else {
            Write-Host ("Cannot commmunicate with computer:{0}" -f $computer.Name)
        }

    }
}

MonitorAdComputers
