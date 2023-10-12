
param(
    [boolean]$Quiet = $false, 
    $Date = (Get-Date))
	
# Obtaining performance information
function GatherPerInfo {
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
    if ($Date -eq "") {
        $fileName = ".\reports\Weekly_Average_Usage_Report_$((Get-Date).Year)$((Get-Date).Month)$((Get-Date).Day).html"
    
    } else {
        $fileName = ".\reports\Weekly_Average_Usage_Report_$Date.html"
    }
    $DailyReport  | ConvertTo-Html -CssUri .\table.css | Set-Content $fileName
}

function MergeCsvs {
    param(
    [string]$Date = ""
    )
    $weeklyData = Get-ChildItem -Path "C:\HealthCheck\Usage" -Filter "*$.csv" `
    | Where-Object { $_.CreationTime -ge (Get-Date).AddDays(-7) -and $_.CreationTime -le (Get-Date) } `
    | Select-Object -ExpandProperty FullName | Import-Csv
    
    if ($Date -eq "") {
        $fileName = ".\reports\Weekly_Usage_Report_$((Get-Date).Year)$((Get-Date).Month)$((Get-Date).Day).html"
    } else {
        $fileName = ".\reports\Weekly_Usage_Report_$Date.html"
    }
    [PSCustomObject]$weeklyData  | ConvertTo-Html -CssUri .\table.css | Set-Content $fileName
}

if ($Quiet -eq $true) {
    GatherPerInfo
    MergeCsvs
} else {
    $date = Read-Host -Prompt "Enter date in YYYYMMDD Format"
    GatherPerInfo -Date $date
    MergeCsvs -Date $date
}
