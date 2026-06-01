<#
.SYNOPSIS
    Sunucu disk alanı izleme scripti
.DESCRIPTION
    Belirtilen sunucuların disk alanını kontrol eder.
    Eşik altına düşen diskleri uyarı olarak gösterir.
    Zamanlanmış görev olarak çalıştırılabilir.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Check-DiskSpace.ps1
    .\Check-DiskSpace.ps1 -ThresholdPercent 20
#>

param(
    [int]$ThresholdPercent = 15    # %15'ten az boş alan varsa uyarı
)

# ============================================
# SUNUCU LİSTESİ
# Kendi sunucularınıza göre düzenleyin
# ============================================
$Servers = @(
    "DC01",
    "EXCHANGE01",
    "FILESERVER",
    "BACKUP01"
)

Write-Host "`n=== DİSK ALANI RAPORU ===" -ForegroundColor Cyan
Write-Host "Uyarı Eşiği: %$ThresholdPercent boş alan altı`n"

$WarningFound = $false
$Results = @()

foreach ($Server in $Servers) {
    Write-Host "--- $Server ---" -ForegroundColor White

    try {
        $Disks = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $Server `
            -Filter "DriveType=3" -ErrorAction Stop

        foreach ($Disk in $Disks) {
            $TotalGB   = [math]::Round($Disk.Size / 1GB, 1)
            $FreeGB    = [math]::Round($Disk.FreeSpace / 1GB, 1)
            $UsedGB    = $TotalGB - $FreeGB
            $FreePercent = [math]::Round(($Disk.FreeSpace / $Disk.Size) * 100, 1)

            $Result = [PSCustomObject]@{
                Sunucu      = $Server
                Disk        = $Disk.DeviceID
                Toplam_GB   = $TotalGB
                Kullanilan_GB = $UsedGB
                Bos_GB      = $FreeGB
                Bos_Yuzde   = $FreePercent
            }
            $Results += $Result

            if ($FreePercent -lt $ThresholdPercent) {
                Write-Host ("  [UYARI] {0}  {1} GB / {2} GB  (%{3} boş)" -f `
                    $Disk.DeviceID, $FreeGB, $TotalGB, $FreePercent) -ForegroundColor Red
                $WarningFound = $true
            }
            else {
                Write-Host ("  [OK]    {0}  {1} GB / {2} GB  (%{3} boş)" -f `
                    $Disk.DeviceID, $FreeGB, $TotalGB, $FreePercent) -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  [HATA] $Server'a bağlanılamadı: $_" -ForegroundColor Red
    }
    Write-Host ""
}

# ============================================
# ÖZET
# ============================================
if ($WarningFound) {
    Write-Host "⚠ DİKKAT: Bazı disklerde alan kritik seviyede!" -ForegroundColor Red
}
else {
    Write-Host "Tüm diskler normal seviyede." -ForegroundColor Green
}

# Raporu kaydet
$ReportPath = "$PSScriptRoot\DiskSpace-Rapor_$(Get-Date -Format 'yyyy-MM-dd').csv"
$Results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
Write-Host "Rapor kaydedildi: $ReportPath`n"
