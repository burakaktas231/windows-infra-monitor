<#
.SYNOPSIS
    Windows Update Durum Kontrolü
.DESCRIPTION
    Sunucuların Windows Update durumunu kontrol eder:
    - Bekleyen güncellemeler
    - Son güncelleme tarihi
    - Yeniden başlatma gerektiren sunucular
    - Güncelleme geçmişi
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Check-WindowsUpdates.ps1
    .\Check-WindowsUpdates.ps1 -IncludeWorkstations
#>

param(
    [switch]$IncludeWorkstations,
    [int]$WarningDays = 30       # Bu kadar gündür güncelleme almamışları uyar
)

Write-Host "`n=== WINDOWS UPDATE DURUM RAPORU ===" -ForegroundColor Cyan
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

# Sunucu listesi (AD'den çek veya elle tanımla)
if ($IncludeWorkstations) {
    $Targets = Get-ADComputer -Filter { Enabled -eq $true } -Properties OperatingSystem, LastLogonDate |
        Where-Object { $_.LastLogonDate -gt (Get-Date).AddDays(-7) }
}
else {
    $Targets = Get-ADComputer -Filter { OperatingSystem -like "*Server*" -and Enabled -eq $true } `
        -Properties OperatingSystem, LastLogonDate |
        Where-Object { $_.LastLogonDate -gt (Get-Date).AddDays(-7) }
}

Write-Host "Kontrol edilecek: $($Targets.Count) cihaz`n"

$Results       = @()
$NeedsReboot   = @()
$Outdated      = @()

foreach ($Target in $Targets) {
    Write-Host "$($Target.Name) " -NoNewline

    try {
        $UpdateInfo = Invoke-Command -ComputerName $Target.Name -ScriptBlock {
            # Son yüklenen güncelleme
            $LastUpdate = Get-HotFix | Sort-Object InstalledOn -Descending -ErrorAction SilentlyContinue |
                Select-Object -First 1

            # Yeniden başlatma gerekiyor mu
            $RebootPending = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
            $CBSReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

            # Bekleyen güncellemeler
            try {
                $Session = New-Object -ComObject Microsoft.Update.Session
                $Searcher = $Session.CreateUpdateSearcher()
                $PendingUpdates = $Searcher.Search("IsInstalled=0").Updates
                $PendingCount = $PendingUpdates.Count
                $CriticalCount = ($PendingUpdates | Where-Object { $_.MsrcSeverity -eq "Critical" }).Count
            }
            catch {
                $PendingCount = -1
                $CriticalCount = 0
            }

            [PSCustomObject]@{
                LastUpdateDate = $LastUpdate.InstalledOn
                LastUpdateKB   = $LastUpdate.HotFixID
                RebootNeeded   = ($RebootPending -or $CBSReboot)
                PendingUpdates = $PendingCount
                CriticalCount  = $CriticalCount
                OSVersion      = (Get-WmiObject Win32_OperatingSystem).Caption
            }
        } -ErrorAction Stop

        # Güncellik hesapla
        $DaysSinceUpdate = if ($UpdateInfo.LastUpdateDate) {
            ((Get-Date) - $UpdateInfo.LastUpdateDate).Days
        } else { 999 }

        $Result = [PSCustomObject]@{
            Sunucu         = $Target.Name
            OS             = $UpdateInfo.OSVersion
            SonGuncelleme  = $UpdateInfo.LastUpdateDate
            SonKB          = $UpdateInfo.LastUpdateKB
            GunOnce        = $DaysSinceUpdate
            Bekleyen       = $UpdateInfo.PendingUpdates
            Kritik         = $UpdateInfo.CriticalCount
            RebootGerekli  = $UpdateInfo.RebootNeeded
        }
        $Results += $Result

        # Duruma göre renk
        if ($UpdateInfo.RebootNeeded) {
            Write-Host "[REBOOT GEREKLİ]" -ForegroundColor Red
            $NeedsReboot += $Target.Name
        }
        elseif ($DaysSinceUpdate -gt $WarningDays) {
            Write-Host "[ESKİ - $DaysSinceUpdate gün]" -ForegroundColor Yellow
            $Outdated += $Target.Name
        }
        elseif ($UpdateInfo.CriticalCount -gt 0) {
            Write-Host "[KRİTİK GÜNCELLEME VAR]" -ForegroundColor Yellow
        }
        else {
            Write-Host "[GÜNCEL]" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[ERİŞİLEMEDİ]" -ForegroundColor DarkGray
    }
}

# ============================================
# ÖZET
# ============================================
Write-Host "`n--- Özet ---" -ForegroundColor Cyan
Write-Host "Taranan Cihaz        : $($Results.Count)"
Write-Host "Reboot Gerekli       : $($NeedsReboot.Count)" -ForegroundColor $(if ($NeedsReboot.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Eski ($WarningDays+ gün)     : $($Outdated.Count)" -ForegroundColor $(if ($Outdated.Count -gt 0) { "Yellow" } else { "Green" })

if ($NeedsReboot.Count -gt 0) {
    Write-Host "`n⚠ Reboot bekleyen sunucular:" -ForegroundColor Red
    $NeedsReboot | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

# Detaylı tablo
Write-Host "`n--- Detay ---`n" -ForegroundColor Cyan
$Results | Format-Table Sunucu, GunOnce, Bekleyen, Kritik, RebootGerekli -AutoSize
