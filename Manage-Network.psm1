#requires -version 5


$IpAddressRegex = "^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$"
$DomainNameRegex = "\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b"

function Set-ComputerNetworkConfiguration {
    <#
.SYNOPSIS
    PowerShell script that manages network configuration.

.DESCRIPTION
    The script manages the network configuration including setting IP addresses 
    and DNS server addresses for computers. 
    The script prompts for the computer name or IP address, desired IP 
    address settings, and preferred DNS server addresses.

.PARAMETER <Parameter_Name>

.INPUTS

.OUTPUTS

.NOTES
    Version:        1.0
    Author:         Jason Cruz
    Creation Date:  11152023
    Purpose/Change: Initial script development

.EXAMPLE
#>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [CimSession]
        $CimSession
    )
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
                    Clear-Host
                    do {
                        $choice = Read-ConfigChoice 
                        if ($choice -eq 0 ) {
                            $networkAdapter | Format-List -Property InterfaceIndex, Caption, IPAddress, IPSubnet, DefaultIPGateway, DnsAddress 
                        } elseif ($choice -eq 1 ) {
                            $newIpAddress = New-IpAddressConfig $networkAdapter $CimSession
                        } elseif ($choice -eq 2 ) {
                            $updatedIpAddress = Set-IpAddressConfig $networkAdapter $CimSession
                        } elseif ($choice -eq 3 ) {
                            $dnsConfig = Set-DnsAddress $networkAdapter $CimSession
                        } elseif ($choice -eq 4 ) {
                            $dnsSuffix = Set-DnsSuffix $networkAdapter $CimSession
                        }
                        $networkAdapters = Get-CimSessionNetworkAdapter $CimSession 
                        $networkAdapter = $networkAdapters | Where-Object { $_.InterfaceIndex -eq $networkIndex }
                    } while ($choice -ne 3)
                }
                else {
                    # TODO: Add logging
                    Write-Host "Network Adapter with Index $networkIndex does not exist!" -ForegroundColor Red
                }
            } while ($null -eq $networkAdapter )
        }
    
        catch {
            Write-Host "An error occurred:"
            Write-Host $_.Exception.Message
            Write-Host $_.ScriptStackTrace
        }
    }
    end {
    }
}

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
        [System.Management.Automation.Host.ChoiceDescription]::new("&Add IP Address", "Adds an IP Adddress and default Gateway. This will also remove all the previous IP Addresses added.")
        [System.Management.Automation.Host.ChoiceDescription]::new("&Update IP Subnet", "Update the subnet mask of an IP Address")
        [System.Management.Automation.Host.ChoiceDescription]::new("Set &DNS Address", "Set the DNS Address")
        [System.Management.Automation.Host.ChoiceDescription]::new("Set DNS Su&ffix", "Set the DNS Suffix")
        [System.Management.Automation.Host.ChoiceDescription]::new("E&xit", "Exit")
    )
    $decision = $Host.UI.PromptForChoice($title, $question, $choices, 0)
    $decision
}

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
        InterfaceIndex = $NetworkAdapter.InterfaceIndex
        ServerAddresses = @($dns1, $dns2)
        CimSession = $CimSession
    }
    try {

        $dns = Set-DnsClientServerAddress @dnsConfig -PassThru
        Clear-Host
        Write-Host "DNS Configuration has been successfully updated. Current values are `n" `
            "`tDNS Address: $($dns.ServerAddresses)"
        # Log something here
    } catch {
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
            CimSession = $CimSession
        }
        $dnsSuffix = Set-DnsClientGlobalSetting @dnsConfig -PassThru
        Clear-Host
        Write-Host "DNS Suffix has been successfully updated. Current values are `n" `
            "`tDNS Suffix: $($dnsSuffix.SuffixSearchList)"
        # Log something here
    } catch {
        Write-Host "An error occurred:"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
    $dnsSuffix
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
    for ($ctr = 0; $ctr -lt $ipAddresses.Length; $ctr++) {
        Write-Host "[$ctr]: " $ipAddresses[$ctr] 
    }
    do {
        $ipIndex = Read-Host "Enter the index of the IP address from the list above"
    } while ([int]$ipIndex -ge $ipAddresses.Length -or [int]$ipIndex -lt 0)
    do {
        $subnet = Read-Host "Enter a valid subnet: (1-32)"
    } while ([int]$subnet -ge 33 -or [int]$subnet -le 0)
    $ipConfig = @{
        InterfaceIndex = $NetworkAdapter.InterfaceIndex
        IpAddress = $ipAddresses[$ipIndex]
        CimSession = $CimSession
        PrefixLength = $subnet
    }
    try {
        $ip = Set-NetIPAddress @ipConfig -PassThru
        Clear-Host
        Write-Host "IP Address has been successfully updated. Current values are `n" `
            "`tIP Address: $($ip.IPAddress)`n" `
            "`tSubnet Mask: $($ip.PrefixLength)"
        # Log something here
    } catch {
        Write-Host "An error occurred:"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
    $ip
}

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
    do {
        $defaultGateway = Read-Host "Enter a valid Gateway (0.0.0.0 - 255.255.255.255). Leave blank for no default gateway"
    } while ($defaultGateway -notmatch $IpAddressRegex -and $defaultGateway.Length -gt 0)
    if ($defaultGateway.Length -gt 0) {
        $ipConfig | Add-Member -NotePropertyName DefaultGateway -NotePropertyValue $defaultGateway
    }
    try {
        $newIp = New-NetIPAddress @ipConfig
        Clear-Host
        Write-Host "IP Address has been successfully added. Current values are `n" `
            "`tIP Address: $($newIp.IPAddress)`n" `
            "`tSubnet Mask: $($newIp.PrefixLength)"
        # Log something here
    } catch {
        Write-Host "An error occurred:"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace
    }
    $newIp
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
        IpAddress = $ipv4Address
        CimSession = $CimSession
        PrefixLength = $subnet
    }
    $ipConfig
}

Export-ModuleMember -Function Set-ComputerNetworkConfiguration
