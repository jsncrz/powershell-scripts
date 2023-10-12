# Author: Ken

function EventLogMonitoring($FileDir){
    
    #Event Logs to be checked
    $event_log = @("Application","System","Security")

    for($cnt=0;$cnt -lt $event_log.Count; $cnt++){
        switch($cnt+1){
            1 {run_monitoring $event_log[$cnt] $cnt+1 $FileDir ;break}
            2 {run_monitoring $event_log[$cnt] $cnt+1 $FileDir ;break}
            3 {run_monitoring $event_log[$cnt] $cnt+1 $FileDir ;break}
    
        }  
    }

}

function send_email($emailbody) {

    #Mail default values
    $EmailFrom = "EMAILFROM@COMPANY.COM" 
    $EmailTo = "EMAILTO@COMPANY.COM" 
    $EmailSubject = "Server event notification."   

    #Mail Server Settings
    $SMTPServer = "YOUR.SMTP.SERVER" 
    $SMTPAuthUsername = "EMAIL-FROM-ACCOUNT-NAME" 
    $SMTPAuthPassword = "EMAIL-FROM-PASSWORD"

    #Mail Settings 
    $mailmessage = New-Object System.Net.Mail.mailmessage  
    $mailmessage.from = ($emailfrom)  
    $mailmessage.To.add($emailto) 
    $mailmessage.Subject = $emailsubject 
    $mailmessage.Body = $emailbody 
    $mailmessage.IsBodyHTML = $true 
    $SMTPClient = New-Object Net.Mail.SMTPClient($SMTPServer, 25)   
    $SMTPClient.Credentials = New-Object System.Net.NetworkCredential("$SMTPAuthUsername", "$SMTPAuthPassword")  

    #Send Mail
    $SMTPClient.Send($mailmessage) 
}

function run_monitoring($log,$cnt,$FileDir){

    #Boolean Variables
    [switch]$ShowEvents = $false
    [switch]$NoEmail = $false
    [switch]$useinstanceid = $false
 
    #History List
    $hist_file = $log + "_loghist.xml" 
    $seed_depth = 100 
 
    #run interval in minutes - set to zero for runonce, "C" for 0 delay continuous loop. 
    $run_interval = 1 

    #monitored_computers.txt is the .TXT file that lists the Computers you wished to be reported on 
    $computers = @(gc $FileDir\monitored_computers.txt)  
    $File = $FileDir + "\" + $log + "_alert_events.csv"
    $event_list = @{} 
    Import-Csv $File |% {$event_list[$_.source + '#' + $_.id] = 1};

 
    #see if we have a history file to use, if not create an empty $histlog 
    if (Test-Path $hist_file){$loghist = Import-Clixml $hist_file} 
    else {$loghist = @{}} 
 
 
    $timer = [System.Diagnostics.Stopwatch]::StartNew() 
 
    #START Log Processing 
 
    $EmailBody = $log + " Event Log Monitoring has alerted on the following events: `n" 
 
    $computers |%{ 
    $timer.reset() 
    $timer.start() 

    $computerName = $_ 
    
    Write-Host "Started processing $($_)" 
 
    #Get the index number of the last log entry 
    $index = (Get-EventLog -ComputerName $_ -LogName $log -newest 1).index 
 
    #if we have a history entry calculate number of events to retrieve 
    #if we don't have an event history, use the $seed_depth to do initial seeding 
    if ($loghist[$_]){$n = $index - $loghist[$_]} 
    else {$n = $seed_depth} 
  
    if ($n -lt 0){ 
        Write-Host "Log index changed since last run. The log may have been cleared. Re-seeding index." 
        $events_found = $true 
        $EmailBody += "`n Possible Log Reset $($_)`nEvent Index reset detected by Log Monitor`n" | ConvertTo-Html 
        $n = $seed_depth 
    } 
  
    Write-Host "Processing $($n) events." 
 
    #get the log entries 
 
    if ($useinstanceid){ 
        $log_hits = Get-EventLog -ComputerName $_ -LogName $log -Newest $n | 
        ? {$event_list[$_.source + "#" + $_.instanceid]} 
    } 
    else {
        $log_hits = Get-EventLog -ComputerName $_ -LogName $log -Newest $n | 
        ? {$event_list[$_.source + "#" + $_.eventid]} 
    } 
 
    #save the current index to $loghist for the next pass 
    $loghist[$_] = $index 
 
    #report number of alert events found and how long it took to do it 
    if ($log_hits){ 
        $events_found = $true 
        $hits = $log_hits.count 
        $EmailBody += "<br><br><hr /> Alert Events on server $($_) `n <br><hr /><br>" 
        $log_hits |%{ 
            $emailbody += "<br>" 
            $emailbody += $_ | select MachineName,EventID,Message | ConvertTo-Html  
            $emailbody += "<br>" 
 
        } 
    } 
    else {$hits = 0} 
    
    $duration = ($timer.elapsed).totalseconds
    write-host "Found $($hits) alert events in $($duration) seconds." 
    "-"*60 
    " " 
    if ($ShowEvents){$log_hits | fl | Out-String |? {$_}} 
    } 
 
    #save the history file to disk for next script run  
    $loghist | export-clixml $hist_file 
 
    #Send email to the IT Support if there were any monitored events found. 
    if ($events_found -and -not $NoEmail){
        #Save Event Log
        $timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }  
        $logfilename = "\event_Logs_" + $computerName + "_" + $timestamp  
        $filepath = $FileDir + $logfilename + ".csv"
        $log_entry = $log_hits | select TimeGenerated,MachineName,EventID,Message 
        $log_entry | Export-CSv -Path $filepath -NoTypeInformation -Append
        send_email $EmailBody
    } 
}

#Main Processing
Write-Host "`n$("*"*60)" 
Write-Host "Log monitor started at $(get-date)" 
Write-Host "$("*"*60)`n" 
 
#run the first pass 
$start_pass = Get-Date 
$FilePath = $MyInvocation.MyCommand.Path
$FileDir = Split-Path -Parent $FilePath
EventLogMonitoring $FileDir
 
#if $run_interval is set, calculate how long to sleep before the next pass 
while ($run_interval -gt 0){ 
    if ($run_interval -eq "C"){
        EventLogMonitoring $FileDir
    } 
    else{ 
        $last_run = (Get-Date) - $start_pass 
        $sleep_time = ([TimeSpan]::FromMinutes($run_interval) - $last_run).totalseconds 
        Write-Host "`n$("*"*10) Sleeping for $($sleep_time) seconds `n" 
  
        #sleep, and then start the next pass 
        Start-Sleep -seconds $sleep_time 
        $start_pass = Get-Date  
        EventLogMonitoring $FileDir
    } 
}  
