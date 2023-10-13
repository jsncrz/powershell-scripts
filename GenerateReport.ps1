
param(
    [boolean]$Quiet = $false, 
    $Date = (Get-Date),
    $Format = "Daily")
	
# Obtaining performance information
function AvgUsage {
    param(
    [string]$Date = ""
    )
    $DailyFiles = Get-ChildItem -Path "C:\HealthCheck\Usage" -Filter "*$Date.csv"
    $DailyReport = @()
    foreach ($DailyFile in $DailyFiles) {
        $dailyAverage = @{
            ReportDate = $DailyFile.CreationTime
            CpuUsage = 0
            RamUsage = 0
            FreeDiskGbInC = 0
            DiskUsagePercentInC = 0
        }
        $iterator = 0
        Import-Csv $DailyFile.Fullname | Foreach-Object { 
            foreach ($property in $_.PSObject.Properties)
            {
                if ($property.Name -eq "CpuUsage") {
                    $dailyAverage.CpuUsage = $dailyAverage.CpuUsage + [float]$property.Value
                    $iterator = $iterator + 1
                }
                if ($property.Name -eq "RamUsage") {
                    $dailyAverage.RamUsage = $dailyAverage.RamUsage + [float]$property.Value
                }
                if ($property.Name -eq "FreeDiskGbInC") {
                    $dailyAverage.FreeDiskGbInC = $dailyAverage.FreeDiskGbInC + [float]$property.Value
                }
                if ($property.Name -eq "DiskUsagePercentInC") {
                    $dailyAverage.DiskUsagePercentInC = $dailyAverage.DiskUsagePercentInC + [float]$property.Value
                }
            } 
            $dailyAverage.CpuUsage = [math]::Round($dailyAverage.CpuUsage / $iterator, 2)
            $dailyAverage.RamUsage = [math]::Round($dailyAverage.RamUsage / $iterator, 2)
            $dailyAverage.DiskUsagePercentInC = [math]::Round($dailyAverage.DiskUsagePercentInC / $iterator, 2)
            $dailyAverage.FreeDiskGbInC = [math]::Round($dailyAverage.FreeDiskGbInC / $iterator, 2)
        }
        $DailyReport += [PSCustomObject]$dailyAverage
    } 
    $null = New-Item -Path "C:\Reports" -ItemType Directory -Force
    if ($Date -eq "") {
        $fileName = ".\reports\Weekly_Average_Usage_Report_$((Get-Date).Year)$((Get-Date).Month)$((Get-Date).Day).html"
    
    } else {
        $fileName = ".\reports\Weekly_Average_Usage_Report_$Date.html"
    }
    $DailyReport  | ConvertTo-Html -CssUri .\table.css | Set-Content $fileName
}

function MergeCsvs {
    param(
    [string]$Date = "",
    [string]$Format = "Daily",
    [string]$Monitoring = "Usage"
    )
    
    $dateTime = Get-Date
    if ($Date -ne "") {
        $datetime = [datetime]::parseexact($Date, "yyyyMMdd", $null)
    }
    if ($Format -eq "Daily") {
        $data = Get-ChildItem -Path "C:\HealthCheck\$Monitoring" -Filter "*$Date.csv" `
        | Where-Object { $_.CreationTime -ge $dateTime.AddDays(-1) -and $_.CreationTime -le $dateTime.AddDays(1) } `
        | Select-Object -ExpandProperty FullName | Import-Csv
    } else {
        $Format = "Weekly"
        $data = Get-ChildItem -Path "C:\HealthCheck\$Monitoring" -Filter "*.csv" `
        | Where-Object { $_.CreationTime -ge $dateTime.AddDays(-7) -and $_.CreationTime -le $dateTime } `
        | Select-Object -ExpandProperty FullName | Import-Csv
    }
    $null = New-Item -Path "C:\HealthCheck\Reports" -ItemType Directory -Force
    $fileName = "C:\HealthCheck\Reports\"+$Format+"_"+$Monitoring+"_Report_$($datetime.Year)$($datetime.Month)$($datetime.Day).html"
    [PSCustomObject]$data  | ConvertTo-Html -CssUri .\table.css | Set-Content $fileName
}

if ($Quiet -eq $true) {
    # AvgUsage
    if ($Format -eq "Weekly") {
	    MergeCsvs -Format "Weekly" -Monitoring "Usage"
	    MergeCsvs -Format "Weekly" -Monitoring "ServiceStat"
    }
    if ($Format -eq "Daily") {
	    MergeCsvs -Format "Daily" -Monitoring "Usage"
	    MergeCsvs -Format "Daily" -Monitoring "ServiceStat"
    }
} else {
    $date = Read-Host -Prompt "Enter date in YYYYMMDD Format"
    $format = Read-Host -Prompt "Enter Daily Or Weekly"
    $monitoring = Read-Host -Prompt "Enter Usage Or ServiceStat"
    # AvgUsage -Date $date
    MergeCsvs -Date $date -Format $format -Monitoring $monitoring
}
