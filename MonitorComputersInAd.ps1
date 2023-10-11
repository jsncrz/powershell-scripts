function GetPerformanceForComputer {
    param (
		[Parameter(Mandatory)]
        [string]$ComputerName
    )
    Write-Host "Getting usage data from computer:" $ComputerName
    #Get CPU Usage from processor data
    $processorData = Get-CimInstance -ClassName Win32_Processor -ComputerName $ComputerName
    #Get RAM Usage from OS data
    $osData = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName
    $ramUsage = (($osData.TotalVisibleMemorySize - $osData.FreePhysicalMemory) / $osData.TotalVisibleMemorySize) * 100
    #Get disk C details
    $disks = Get-CimInstance Win32_LogicalDisk -ComputerName $computer.Name -Filter "DeviceID = 'C:'"
    #Create a hash table for easier handling in CSV
    $computerProperties = [PsCustomObject]@{
        ComputerName = $ComputerName
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $index = 0
    foreach ($processor in $processorData) {
        $index++
        $computerProperties | Add-Member -MemberType NoteProperty -Name ("CpuUsage" +$index)  -Value ([math]::Round($processor.LoadPercentage, 2))
    }
    $computerProperties | Add-Member -MemberType NoteProperty -Name NumCpus  -Value $index
    $computerProperties | Add-Member -MemberType NoteProperty -Name RamUsage -Value ([math]::Round($ramUsage, 2))
    $computerProperties | Add-Member -MemberType NoteProperty -Name FreeDiskGbInC -Value ([math]::Round($disks[0].FreeSpace / 1Gb, 2))
    $computerProperties | Add-Member -MemberType NoteProperty -Name DiskUsagePercentInC -Value ([math]::Round(100 - (($disks.FreeSpace / $disks.Size) * 100), 2))
    return $computerProperties;
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
    for($i=1; $i -le $ComputerData.NumCpus; $i++){
        $cpuUsage = $ComputerData | select -ExpandProperty ("CpuUsage"+$i)
        if ($cpuUsage -ge 90) {
    	    $hasCriticalAlert = $true
            $mailContent = $mailContent + "Critical! CPU Usage for Processor#" +$i+ " is " + $cpuUsage + "%`n"
        } elseif ($cpuUsage -ge 70) {
            $mailContent = $mailContent + "Warning! CPU Usage for Processor#" +$i+ " is " + $cpuUsage + "%`n"
        }
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
            Write-Host ("Finished monitoring for computer:{0}" -f $computer.Name)
        } else {
            Write-Host ("Cannot commmunicate with computer:{0}" -f $computer.Name)
        }

    }
}

MonitorAdComputers
