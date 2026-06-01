<#
.SYNOPSIS
    Kritik Servis İzleme ve Otomatik Yeniden Başlatma
.DESCRIPTION
    Belirlenen sunuculardaki kritik Windows servislerini kontrol eder.
    Durmuş servisleri tespit eder ve opsiyonel olarak yeniden başlatır.
    Zamanlanmış görev olarak düzenli çalıştırılmak üzere tasarlanmıştır.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Watch-CriticalServices.ps1
    .\Watch-CriticalServices.ps1 -AutoRestart
#>

param(
    [switch]$AutoRestart    # Durmuş servisleri otomatik başlat
)

# ============================================
# İZLENECEK SERVİSLER
# Sunucu ve servis listesini ortamınıza göre düzenleyin
# ============================================
$MonitorList = @(
    # Domain Controller
    @{
        Server   = "DC01"
        Services = @("NTDS", "DNS", "kdc", "Netlogon", "W32Time")
    },
    # Exchange Server
    @{
        Server   = "EXCHANGE01"
        Services = @(
            "MSExchangeIS",           # Information Store
            "MSExchangeTransport",    # Transport
            "MSExchangeServiceHost",  # Service Host
            "W3SVC",                  # IIS (OWA)
            "MSExchangeMailboxAssistants"
        )
    },
    # File Server
    @{
        Server   = "FILESERVER"
        Services = @("LanmanServer", "Spooler", "BITS")
    },
    # Backup Server
    @{
        Server   = "BACKUP01"
        Services = @("VeeamBackupSvc", "VeeamTransportSvc", "VeeamDeploySvc")
    }
)

Write-Host "`n=== KRİTİK SERVİS İZLEME ===" -ForegroundColor Cyan
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
Write-Host "Otomatik Başlatma: $(if ($AutoRestart) { 'AÇIK' } else { 'Kapalı' })`n"

$StoppedServices = @()
$RunningCount    = 0
$StoppedCount    = 0
$ErrorCount      = 0

foreach ($Entry in $MonitorList) {
    $Server = $Entry.Server
    Write-Host "--- $Server ---" -ForegroundColor White

    foreach ($ServiceName in $Entry.Services) {
        try {
            $Svc = Get-Service -ComputerName $Server -Name $ServiceName -ErrorAction Stop

            if ($Svc.Status -eq "Running") {
                Write-Host ("  [OK]     {0,-40} : Çalışıyor" -f $Svc.DisplayName) -ForegroundColor Green
                $RunningCount++
            }
            else {
                Write-Host ("  [DURDU!] {0,-40} : {1}" -f $Svc.DisplayName, $Svc.Status) -ForegroundColor Red
                $StoppedCount++

                $StoppedServices += [PSCustomObject]@{
                    Sunucu  = $Server
                    Servis  = $Svc.DisplayName
                    KisaAd  = $ServiceName
                    Durum   = $Svc.Status.ToString()
                }

                # Otomatik yeniden başlatma
                if ($AutoRestart) {
                    try {
                        Get-Service -ComputerName $Server -Name $ServiceName | Start-Service -ErrorAction Stop
                        Write-Host ("           --> Yeniden başlatıldı!") -ForegroundColor Yellow
                    }
                    catch {
                        Write-Host ("           --> Başlatılamadı: $_") -ForegroundColor Red
                    }
                }
            }
        }
        catch {
            Write-Host ("  [HATA]   {0,-40} : Erişilemedi" -f $ServiceName) -ForegroundColor DarkRed
            $ErrorCount++
        }
    }
    Write-Host ""
}

# ============================================
# ÖZET
# ============================================
Write-Host "--- Özet ---" -ForegroundColor Cyan
Write-Host "Çalışan   : $RunningCount" -ForegroundColor Green
Write-Host "Durmuş    : $StoppedCount" -ForegroundColor $(if ($StoppedCount -gt 0) { "Red" } else { "Green" })
Write-Host "Erişilmez : $ErrorCount" -ForegroundColor $(if ($ErrorCount -gt 0) { "Yellow" } else { "Green" })

if ($StoppedCount -gt 0) {
    Write-Host "`n⚠ DİKKAT: Durmuş servisler var! Acil kontrol edin." -ForegroundColor Red
}
