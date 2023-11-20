#requires -version 5

# Imports
Import-Module .\Manage-Logs.psm1 -Force

# Declarations
$IpAddressRegex = "^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$"
$DomainNameRegex = "\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b"
$NumericRegex = "^[0-9]*$"

# -----------------------------------------------------------------------
# --------------------- START OF EXPORTED FUNCTIONS ---------------------
# -----------------------------------------------------------------------

function Set-ComputerNetworkConfiguration {
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [CimSession]
        $CimSession
    )
    <#
    .SYNOPSIS
        PowerShell script that manages network configuration.
    .DESCRIPTION
        The script manages the network configuration including setting IP addresses 
        and DNS server addresses for computers. 
        The script prompts for the computer name or IP address, desired IP 
        address settings, and preferred DNS server addresses.
    .PARAMETER CimSession
        Specifies the Cim Session where the script has to run 
    .NOTES
        Version:        1.0
        Author:         Jason Cruz
        Creation Date:  11152023
        Purpose/Change: Initial script development
    #>
    begin {
    }
    process {
        try {
            $networkAdapters = Get-CimSessionNetworkAdapter $CimSession 
            $networkAdapters | Select-Object -Property InterfaceIndex, Caption, IPAddress, IPSubnet, DefaultIPGateway, DnsAddress | Format-List
            do {
                $networkIndex = Read-Host "Enter the index of the Network Adapter to be updated"
                $networkAdapter = $networkAdapters | Where-Object { $_.InterfaceIndex -eq $networkIndex }
                if ($null -ne $networkAdapter ) {
                    Write-Log -Message "Updating $($networkAdapter.Description)'s Configuration!"
                    Clear-Host
                    do {
                        $choice = Read-ConfigChoice 
                        if ($choice -eq 0 ) {
                            $networkAdapter | Format-List -Property InterfaceIndex, Caption, IPAddress, IPSubnet, DefaultIPGateway, DnsAddress 
                        }
                        elseif ($choice -eq 1 ) {
                            New-IpAddressConfig $networkAdapter $CimSession
                        }
                        elseif ($choice -eq 2 ) {
                            Set-IpAddressConfig $networkAdapter $CimSession
                        }
                        elseif ($choice -eq 3 ) {
                            New-DefaultGateway $networkAdapter $CimSession
                        }
                        elseif ($choice -eq 4 ) {
                            Remove-DefaultGateway $networkAdapter $CimSession
                        }
                        elseif ($choice -eq 5 ) {
                            Set-DnsAddress $networkAdapter $CimSession
                        }
                        elseif ($choice -eq 6 ) {
                            Set-DnsSuffix $networkAdapter $CimSession
                        }
                        $networkAdapters = Get-CimSessionNetworkAdapter $CimSession 
                        $networkAdapter = $networkAdapters | Where-Object { $_.InterfaceIndex -eq $networkIndex }
                    } while ($choice -ne 7)
                    Write-Log -Message "Updated $($networkAdapter.Description)'s Configuration!"
                }
                else {
                    Write-Log -Message "Network Adapter with Index $networkIndex does not exist!" -Level "Error"
                    Write-Host "Network Adapter with Index $networkIndex does not exist!" -ForegroundColor Red
                }
            } while ($null -eq $networkAdapter )
        }
    
        catch {
            Write-Log -Message $_.Exception.Message -Level "Error"
            Write-Host "An error occurred:"
            Write-Host $_.Exception.Message
            Write-Host $_.ScriptStackTrace
        }
    }
    end {
    }
}

# -----------------------------------------------------------------------
# --------------------- END OF EXPORTED FUNCTIONS -----------------------
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------
# --------------------- START OF INTERNAL FUNCTIONS ---------------------
# -----------------------------------------------------------------------

function Get-CimSessionNetworkAdapter {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $CimSession
    )
    $networkAdapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -CimSession $CimSession -Filter "IPEnabled = 'True'"
    foreach ($networkAdapter in $networkAdapters) {
        $dnsAddress = Get-DnsClientServerAddress -InterfaceIndex $networkAdapter.InterfaceIndex -CimSession $CimSession
        $networkAdapter | Add-Member -NotePropertyName DnsAddress -NotePropertyValue $dnsAddress.ServerAddresses
    }
    $networkAdapters
}
<# 
    Choice 0 is to show the current config
    Choice 1 is add an IP
    Choice 2 is update the subnet of an IP
    Choice 3 is set the DNS address
    Choice 3 is set the DNS suffix
    Choice 4 is to exit the manager
#>
function Read-ConfigChoice {
    $title = 'Network Manager'
    $question = 'What do you want to do?'
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Show current configuration", "Show the current configuration")
        [System.Management.Automation.Host.ChoiceDescription]::new("&Add IP Address", "Adds an IP Adddress. This will also remove all the previous IP Addresses added.")
        [System.Management.Automation.Host.ChoiceDescription]::new("&Update IP Subnet", "Update the subnet mask of an IP Address")
        [System.Management.Automation.Host.ChoiceDescription]::new("Add Default &Gateway", "Add a default gateway")
        [System.Management.Automation.Host.ChoiceDescription]::new("&Remove Default Gateway", "Remove a default gateway from the list of gateways")
        [System.Management.Automation.Host.ChoiceDescription]::new("Set &DNS Address", "Set the DNS Address")
        [System.Management.Automation.Host.ChoiceDescription]::new("Set DNS Su&ffix", "Set the DNS Suffix")
        [System.Management.Automation.Host.ChoiceDescription]::new("E&xit", "Exit")
    )
    $decision = $Host.UI.PromptForChoice($title, $question, $choices, 0)
    $decision
}

# --------------------- IP ADDRESS FUNCTIONS ---------------------
function New-IpAddressConfig {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $NetworkAdapter,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $CimSession
    )
    Remove-NetIPAddress -InterfaceIndex $NetworkAdapter.InterfaceIndex -CimSession $CimSession 
    $ipConfig = New-IpAddressSplat $NetworkAdapter $CimSession
    try {
        $newIp = New-NetIPAddress @ipConfig
        Clear-Host
        Write-Host "IP Address has been successfully added. Current values are `n" `
            "`tIP Address: $($newIp.IPAddress)`n" `
            "`tSubnet Mask: $($newIp.PrefixLength)"
        Write-Log "IP Address has been successfully added. Current values are `n`tIP Address: $($newIp.IPAddress)`n`tSubnet Mask: $($newIp.PrefixLength)"
    }
    catch {
        Write-Log -Message $_.Exception.Message -Level "Error"
        Write-Host "An error occurred:"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
    $newIp
}

function Set-IpAddressConfig {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $NetworkAdapter,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $CimSession
    )
    $ipAddresses = $NetworkAdapter.IPAddress
    if ($ipAddresses.Length -gt 0) {
        for ($ctr = 0; $ctr -lt $ipAddresses.Length; $ctr++) {
            Write-Host "[$ctr]: " $ipAddresses[$ctr] 
        }
        do {
            $ipIndex = Read-Host "Enter the index of the IP address from the list above"
        } while ($ipIndex -notmatch $NumericRegex -or [int]$ipIndex -ge $ipAddresses.Length -or [int]$ipIndex -lt 0)
        do {
            $subnet = Read-Host "Enter a valid subnet: (1-32)"
        } while ([int]$subnet -ge 33 -or [int]$subnet -le 0)
        $ipConfig = @{
            InterfaceIndex = $NetworkAdapter.InterfaceIndex
            IpAddress      = $ipAddresses[$ipIndex]
            CimSession     = $CimSession
            PrefixLength   = $subnet
        }
        try {
            $ip = Set-NetIPAddress @ipConfig -PassThru
            Clear-Host
            Write-Host "IP Address has been successfully updated. Current values are `n" `
                "`tIP Address: $($ip.IPAddress)`n" `
                "`tSubnet Mask: $($ip.PrefixLength)"
            Write-Log "IP Address has been successfully updated. Current values are `n `tIP Address: $($ip.IPAddress)`n`tSubnet Mask: $($ip.PrefixLength)"
        }
        catch {
            Write-Log -Message $_.Exception.Message -Level "Error"
            Write-Host "An error occurred:"
            Write-Host $_.Exception.Message
            Write-Host $_.ScriptStackTrace
        }
    }
    else {
        Write-Host "There are no IP Addresses to update"
    }
    $ip
}

#This function creates the IP config splat
function New-IpAddressSplat {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $NetworkAdapter,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $CimSession
    )
    do {
        $ipv4Address = Read-Host "Enter a valid IPv4 Address (0.0.0.0 - 255.255.255.255)"
    } while ($ipv4Address -notmatch $IpAddressRegex)
    do {
        $subnet = Read-Host "Enter a valid subnet: (1-32)"
    } while ([int]$subnet -ge 33 -or [int]$subnet -le 0)
    $ipConfig = @{
        InterfaceIndex = $NetworkAdapter.InterfaceIndex
        IpAddress      = $ipv4Address
        CimSession     = $CimSession
        PrefixLength   = $subnet
    }
    $ipConfig
}

# --------------------- DEFAULT GATEWAY FUNCTIONS ---------------------
function New-DefaultGateway {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $NetworkAdapter,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $CimSession
    )
    
    do {
        $defaultGateway = Read-Host "Enter a valid Gateway (0.0.0.0 - 255.255.255.255)"
    } while ($defaultGateway -notmatch $IpAddressRegex)
    try {
        New-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceIndex $NetworkAdapter.InterfaceIndex -NextHop $defaultGateway  -CimSession $CimSession
        Clear-Host
        Write-Host "$defaultGateway has been sucessfully added to the Default Gateways"
        Write-Log "$defaultGateway has been sucessfully added to the Default Gateways"
    }
    catch {
        Write-Log -Message $_.Exception.Message -Level "Error"
        Write-Host "An error occurred:"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
    $ip
}

function Remove-DefaultGateway {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $NetworkAdapter,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $CimSession
    )
    
    $gatewayRoutes = Get-NetRoute -InterfaceIndex $NetworkAdapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -CimSession $CimSession
    $gateways = $gatewayRoutes.NextHop
    if ($gateways.Length -gt 0) {
        for ($ctr = 0; $ctr -lt $gateways.Length; $ctr++) {
            Write-Host "[$ctr]: " $gateways[$ctr] 
        }
        do {
            $gatewayIndex = Read-Host "Enter the index of the Default Gateway to be removed from the list above"
        } while ($gatewayIndex -notmatch $NumericRegex -or [int]$gatewayIndex -ge $gateways.Length -or [int]$gatewayIndex -lt 0)
        try {
            Remove-NetRoute -NextHop $gateways[$gatewayIndex] -InterfaceIndex $NetworkAdapter.InterfaceIndex -CimSession $CimSession
            Clear-Host
            Write-Host "$($gateways[$gatewayIndex])has been sucessfully removed from the Default Gateways"
            Write-Log "$($gateways[$gatewayIndex])has been sucessfully removed from the Default Gateways"
        }
        catch {
            Write-Log -Message $_.Exception.Message -Level "Error"
            Write-Host "An error occurred:"
            Write-Host $_.Exception.Message
            Write-Host $_.ScriptStackTrace
        }
    }
    else {
        Write-Host "There are no default gateways to remove."
    }
}

# --------------------- DNS FUNCTIONS ---------------------

function Set-DnsAddress {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $NetworkAdapter,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $CimSession
    )
    do {
        $dns1 = Read-Host "Enter a valid DNS#1 (0.0.0.0 - 255.255.255.255)"
    } while ($dns1 -notmatch $IpAddressRegex)
    do {
        $dns2 = Read-Host "Enter a valid DNS#2 (0.0.0.0 - 255.255.255.255)"
    } while ($dns2 -notmatch $IpAddressRegex)
    $dnsConfig = @{
        InterfaceIndex  = $NetworkAdapter.InterfaceIndex
        ServerAddresses = @($dns1, $dns2)
        CimSession      = $CimSession
    }
    try {

        $dns = Set-DnsClientServerAddress @dnsConfig -PassThru
        Clear-Host
        Write-Host "DNS Configuration has been successfully updated. Current values are `n" `
            "`tDNS Address: $($dns.ServerAddresses)"
        Write-Log "DNS Configuration has been successfully updated. Current values are `n`tDNS Address: $($dns.ServerAddresses)"
        # Log something here
    }
    catch {
        Write-Log -Message $_.Exception.Message -Level "Error"
        Write-Host "An error occurred:"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
    $dns
}

function Set-DnsSuffix {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $NetworkAdapter,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $CimSession
    )
    try {
        Get-DnsClientGlobalSetting -CimSession $CimSession | Select-Object -Property SuffixSearchList
        do {
            $dns1 = Read-Host "Enter a valid DNS suffix (Domain)"
        } while ($dns1 -notmatch $DomainNameRegex)
        do {
            $dns2 = Read-Host "Enter another valid DNS Suffix (Domain)"
        } while ($dns2 -notmatch $DomainNameRegex)
        $dnsConfig = @{
            SuffixSearchList = @($dns1, $dns2)
            CimSession       = $CimSession
        }
        $dnsSuffix = Set-DnsClientGlobalSetting @dnsConfig -PassThru
        Clear-Host
        Write-Host "DNS Suffix has been successfully updated. Current values are `n" `
            "`tDNS Suffix: $($dnsSuffix.SuffixSearchList)"
        Write-Log "DNS Suffix has been successfully updated. Current values are `n`tDNS Suffix: $($dnsSuffix.SuffixSearchList)"
    }
    catch {
        Write-Log -Message $_.Exception.Message -Level "Error"
        Write-Host "An error occurred:"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
    $dnsSuffix
}

# -----------------------------------------------------------------------
# --------------------- END OF INTERNAL FUNCTIONS ---------------------
# -----------------------------------------------------------------------

Export-ModuleMember -Function Set-ComputerNetworkConfiguration
