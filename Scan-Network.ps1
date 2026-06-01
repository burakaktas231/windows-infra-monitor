<#
.SYNOPSIS
    Ağ Tarama - Ping Sweep ve Port Kontrolü
.DESCRIPTION
    Belirtilen IP aralığını tarar, aktif cihazları tespit eder.
    Yaygın portları kontrol ederek servisleri tanımlar.
    Ağ envanteri ve sorun giderme için kullanılır.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Scan-Network.ps1 -Subnet "192.168.1"
    .\Scan-Network.ps1 -Subnet "192.168.1" -ScanPorts
    .\Scan-Network.ps1 -Subnet "192.168.1" -StartIP 1 -EndIP 50
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Subnet,            # Örn: "192.168.1"

    [int]$StartIP = 1,
    [int]$EndIP   = 254,
    [int]$Timeout = 100,        # Ping timeout (ms)
    [switch]$ScanPorts,         # Port taraması da yap
    [switch]$ExportCSV
)

# Yaygın portlar ve servis adları
$CommonPorts = @{
    22   = "SSH"
    53   = "DNS"
    80   = "HTTP"
    135  = "RPC"
    139  = "NetBIOS"
    389  = "LDAP"
    443  = "HTTPS"
    445  = "SMB"
    587  = "SMTP"
    636  = "LDAPS"
    1433 = "MSSQL"
    3306 = "MySQL"
    3389 = "RDP"
    5985 = "WinRM"
    8080 = "HTTP-Alt"
}

Write-Host "`n=== AĞ TARAMA ===" -ForegroundColor Cyan
Write-Host "Alt Ağ   : $Subnet.0/24"
Write-Host "Aralık   : $Subnet.$StartIP - $Subnet.$EndIP"
Write-Host "Port     : $(if ($ScanPorts) { 'Açık' } else { 'Kapalı' })`n"

$ActiveHosts = @()
$TotalScanned = 0

Write-Host "Taranıyor..." -ForegroundColor Yellow

for ($i = $StartIP; $i -le $EndIP; $i++) {
    $IP = "$Subnet.$i"
    $TotalScanned++

    # İlerleme göstergesi (her 10 IP'de bir)
    if ($i % 10 -eq 0) {
        Write-Host "  $IP ..." -ForegroundColor DarkGray -NoNewline
        Write-Host "`r" -NoNewline
    }

    $Ping = Test-Connection -ComputerName $IP -Count 1 -Quiet -ErrorAction SilentlyContinue

    if ($Ping) {
        # DNS çözümleme
        $HostName = try {
            ([System.Net.Dns]::GetHostEntry($IP)).HostName
        } catch { "---" }

        # MAC adresi (arp tablosundan)
        $MAC = try {
            $ArpEntry = arp -a $IP | Select-String $IP
            if ($ArpEntry) {
                ($ArpEntry -split '\s+' | Where-Object { $_ -match '([0-9a-f]{2}[-:]){5}[0-9a-f]{2}' })[0]
            } else { "---" }
        } catch { "---" }

        $HostInfo = [PSCustomObject]@{
            IP       = $IP
            Hostname = $HostName
            MAC      = $MAC
            Ports    = ""
        }

        # Port taraması
        if ($ScanPorts) {
            $OpenPorts = @()
            foreach ($Port in $CommonPorts.Keys | Sort-Object) {
                try {
                    $TcpClient = New-Object System.Net.Sockets.TcpClient
                    $Connect = $TcpClient.BeginConnect($IP, $Port, $null, $null)
                    $Wait = $Connect.AsyncWaitHandle.WaitOne(200, $false)

                    if ($Wait -and $TcpClient.Connected) {
                        $OpenPorts += "$Port($($CommonPorts[$Port]))"
                    }
                    $TcpClient.Close()
                }
                catch { }
            }
            $HostInfo.Ports = $OpenPorts -join ", "
        }

        $ActiveHosts += $HostInfo

        Write-Host ("[AKTIF] {0,-16} {1,-30} {2,-18} {3}" -f `
            $IP, $HostName, $MAC, $HostInfo.Ports) -ForegroundColor Green
    }
}

# ============================================
# ÖZET
# ============================================
Write-Host "`n--- Özet ---" -ForegroundColor Cyan
Write-Host "Taranan IP       : $TotalScanned"
Write-Host "Aktif Cihaz      : $($ActiveHosts.Count)" -ForegroundColor Green
Write-Host "Pasif/Kapalı     : $($TotalScanned - $ActiveHosts.Count)"

if ($ActiveHosts.Count -gt 0 -and $ScanPorts) {
    Write-Host "`nRDP açık cihazlar (3389):" -ForegroundColor Yellow
    $ActiveHosts | Where-Object { $_.Ports -match "3389" } | ForEach-Object {
        Write-Host "  $($_.IP) - $($_.Hostname)" -ForegroundColor Yellow
    }
}

# CSV Export
if ($ExportCSV) {
    $ReportPath = "$PSScriptRoot\NetworkScan_${Subnet}_$(Get-Date -Format 'yyyy-MM-dd').csv"
    $ActiveHosts | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nRapor kaydedildi: $ReportPath" -ForegroundColor Green
}
