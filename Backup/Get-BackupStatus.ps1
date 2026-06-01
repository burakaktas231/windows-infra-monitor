<#
.SYNOPSIS
    Veeam Backup Durum Raporu
.DESCRIPTION
    Son Veeam backup job'larının durumunu kontrol eder.
    Başarısız veya uyarılı job'ları vurgular.
    Günlük kontrol için zamanlanmış görev olarak çalıştırılabilir.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Veeam Backup & Replication PowerShell snap-in gerektirir.
    Veeam sunucusu üzerinde çalıştırılmalıdır.
.EXAMPLE
    .\Get-BackupStatus.ps1
    .\Get-BackupStatus.ps1 -Hours 48
#>

param(
    [int]$Hours = 24    # Son kaç saatlik job'ları kontrol et
)

Write-Host "`n=== VEEAM BACKUP DURUM RAPORU ===" -ForegroundColor Cyan
Write-Host "Kontrol Aralığı: Son $Hours saat"
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

# ============================================
# VEEAM SNAP-IN YÜKLE
# ============================================
try {
    if (-not (Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue)) {
        Add-PSSnapin VeeamPSSnapIn -ErrorAction Stop
    }
}
catch {
    Write-Host "[HATA] Veeam PowerShell snap-in yüklenemedi." -ForegroundColor Red
    Write-Host "Bu scripti Veeam sunucusu üzerinde çalıştırın."
    exit 1
}

# ============================================
# BACKUP JOB DURUMLARI
# ============================================
Write-Host "--- Backup Job'ları ---`n" -ForegroundColor Cyan

$StartDate = (Get-Date).AddHours(-$Hours)
$Jobs = Get-VBRJob

$WarningCount = 0
$FailCount    = 0
$SuccessCount = 0

foreach ($Job in $Jobs) {
    $LastSession = $Job.FindLastSession()

    if (-not $LastSession) {
        Write-Host ("{0,-35} : Henüz çalışmamış" -f $Job.Name) -ForegroundColor DarkGray
        continue
    }

    $Status    = $LastSession.Result
    $EndTime   = $LastSession.EndTime
    $Duration  = $LastSession.EndTime - $LastSession.CreationTime

    $StatusText = switch ($Status) {
        "Success" {
            $SuccessCount++
            "Başarılı"
        }
        "Warning" {
            $WarningCount++
            "Uyarılı"
        }
        "Failed" {
            $FailCount++
            "BAŞARISIZ"
        }
        default {
            $Status.ToString()
        }
    }

    $Color = switch ($Status) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Failed"  { "Red" }
        default   { "White" }
    }

    $Flag = if ($Status -eq "Failed") { " [!!!]" } else { "" }

    Write-Host ("{0,-35} : {1,-12} | {2} | Süre: {3:hh\:mm\:ss}{4}" -f `
        $Job.Name, $StatusText, $EndTime.ToString('dd.MM HH:mm'), $Duration, $Flag) `
        -ForegroundColor $Color
}

# ============================================
# REPOSITORY DOLULUK
# ============================================
Write-Host "`n--- Repository Doluluk ---`n" -ForegroundColor Cyan

try {
    $Repos = Get-VBRBackupRepository

    foreach ($Repo in $Repos) {
        $Info = [Veeam.Backup.Core.CBackupRepository]::GetContainer($Repo)
        if ($Info) {
            $TotalGB  = [math]::Round($Info.CachedTotalSpace.InGigabytes, 1)
            $FreeGB   = [math]::Round($Info.CachedFreeSpace.InGigabytes, 1)
            $UsedPercent = [math]::Round((($TotalGB - $FreeGB) / $TotalGB) * 100, 1)

            $Color = if ($UsedPercent -gt 85) { "Red" } elseif ($UsedPercent -gt 70) { "Yellow" } else { "Green" }
            $Flag  = if ($UsedPercent -gt 85) { " [KRİTİK!]" } else { "" }

            Write-Host ("{0,-30} : %{1} dolu ({2} GB boş / {3} GB toplam){4}" -f `
                $Repo.Name, $UsedPercent, $FreeGB, $TotalGB, $Flag) -ForegroundColor $Color
        }
    }
}
catch {
    Write-Host "[BİLGİ] Repository bilgisi alınamadı: $_" -ForegroundColor Yellow
}

# ============================================
# ÖZET
# ============================================
Write-Host "`n--- Özet ---" -ForegroundColor Cyan
Write-Host "Başarılı  : $SuccessCount" -ForegroundColor Green
Write-Host "Uyarılı   : $WarningCount" -ForegroundColor Yellow
Write-Host "Başarısız : $FailCount" -ForegroundColor Red

if ($FailCount -gt 0) {
    Write-Host "`n⚠ DİKKAT: Başarısız backup job'ları var! Kontrol edin." -ForegroundColor Red
}
