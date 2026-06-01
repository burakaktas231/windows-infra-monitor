<#
.SYNOPSIS
    DHCP Scope Raporu ve Lease Denetimi
.DESCRIPTION
    DHCP scope'ların doluluk oranını, aktif lease'leri,
    rezervasyonları ve scope istatistiklerini raporlar.
    IP tükenmesi uyarısı verir.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Get-DHCPReport.ps1
    .\Get-DHCPReport.ps1 -DHCPServer "DC01" -WarningPercent 80
#>

param(
    [string]$DHCPServer = "DC01",
    [int]$WarningPercent = 80,
    [switch]$ExportCSV
)

Write-Host "`n=== DHCP SCOPE RAPORU ===" -ForegroundColor Cyan
Write-Host "Sunucu    : $DHCPServer"
Write-Host "Uyarı Eşiği: %$WarningPercent doluluk`n"

# ============================================
# 1) SCOPE DURUMU
# ============================================
Write-Host "--- Scope Doluluk ---`n" -ForegroundColor Cyan

try {
    $Scopes = Get-DhcpServerv4Scope -ComputerName $DHCPServer -ErrorAction Stop
    $ScopeReport = @()

    foreach ($Scope in $Scopes) {
        $Stats = Get-DhcpServerv4ScopeStatistics -ScopeId $Scope.ScopeId -ComputerName $DHCPServer

        $UsedPercent = [math]::Round($Stats.PercentageInUse, 1)
        $FreeCount   = $Stats.Free
        $InUseCount  = $Stats.InUse

        $ScopeInfo = [PSCustomObject]@{
            ScopeID      = $Scope.ScopeId
            Ad           = $Scope.Name
            Aralik       = "$($Scope.StartRange) - $($Scope.EndRange)"
            Durum        = $Scope.State
            Kullanilan   = $InUseCount
            Bos          = $FreeCount
            Doluluk_Yzd  = $UsedPercent
        }
        $ScopeReport += $ScopeInfo

        # Renk kodlama
        $Color = if ($UsedPercent -ge 90) { "Red" }
                 elseif ($UsedPercent -ge $WarningPercent) { "Yellow" }
                 else { "Green" }

        $Flag = if ($UsedPercent -ge 90) { " [KRİTİK!]" }
                elseif ($UsedPercent -ge $WarningPercent) { " [UYARI]" }
                else { "" }

        $Bar = "█" * [math]::Min([math]::Round($UsedPercent / 5), 20)
        $EmptyBar = "░" * (20 - [math]::Min([math]::Round($UsedPercent / 5), 20))

        Write-Host "$($Scope.Name) ($($Scope.ScopeId))" -ForegroundColor White
        Write-Host ("  [{0}{1}] %{2}{3}" -f $Bar, $EmptyBar, $UsedPercent, $Flag) -ForegroundColor $Color
        Write-Host ("  Kullanılan: {0} | Boş: {1} | Aralık: {2}" -f $InUseCount, $FreeCount, "$($Scope.StartRange)-$($Scope.EndRange)")
        Write-Host ""
    }
}
catch {
    Write-Host "[HATA] DHCP sunucusuna bağlanılamadı: $_" -ForegroundColor Red
    exit 1
}

# ============================================
# 2) AKTİF LEASE'LER
# ============================================
Write-Host "--- Aktif Lease'ler ---`n" -ForegroundColor Cyan

foreach ($Scope in $Scopes) {
    $Leases = Get-DhcpServerv4Lease -ScopeId $Scope.ScopeId -ComputerName $DHCPServer |
        Where-Object { $_.AddressState -eq "Active" } |
        Sort-Object IPAddress

    Write-Host "$($Scope.Name) - $($Leases.Count) aktif lease:" -ForegroundColor White

    foreach ($Lease in $Leases | Select-Object -First 20) {
        $ExpiryDays = if ($Lease.LeaseExpiryTime) {
            ((New-TimeSpan -Start (Get-Date) -End $Lease.LeaseExpiryTime).Days)
        } else { "Sınırsız" }

        Write-Host ("  {0,-16} {1,-18} {2,-20} (Süre: {3})" -f `
            $Lease.IPAddress, $Lease.ClientId, $Lease.HostName, "$ExpiryDays gün")
    }

    if ($Leases.Count -gt 20) {
        Write-Host "  ... ve $($Leases.Count - 20) lease daha" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ============================================
# 3) REZERVASYONLAR
# ============================================
Write-Host "--- Rezervasyonlar ---`n" -ForegroundColor Cyan

foreach ($Scope in $Scopes) {
    $Reservations = Get-DhcpServerv4Reservation -ScopeId $Scope.ScopeId -ComputerName $DHCPServer -ErrorAction SilentlyContinue

    if ($Reservations) {
        Write-Host "$($Scope.Name):" -ForegroundColor White
        foreach ($Res in $Reservations) {
            Write-Host ("  {0,-16} {1,-18} {2}" -f $Res.IPAddress, $Res.ClientId, $Res.Name)
        }
        Write-Host ""
    }
}

# ============================================
# 4) SUNUCU İSTATİSTİKLERİ
# ============================================
Write-Host "--- Sunucu İstatistikleri ---`n" -ForegroundColor Cyan

try {
    $ServerStats = Get-DhcpServerv4Statistics -ComputerName $DHCPServer

    Write-Host "Toplam Scope       : $($Scopes.Count)"
    Write-Host "Toplam Discover    : $($ServerStats.Discovers)"
    Write-Host "Toplam Offer       : $($ServerStats.Offers)"
    Write-Host "Toplam Request     : $($ServerStats.Requests)"
    Write-Host "Toplam Ack         : $($ServerStats.Acks)"
    Write-Host "Toplam Nack        : $($ServerStats.Nacks)" -ForegroundColor $(if ($ServerStats.Nacks -gt 0) { "Yellow" } else { "Green" })
    Write-Host "Toplam Decline     : $($ServerStats.Declines)" -ForegroundColor $(if ($ServerStats.Declines -gt 0) { "Yellow" } else { "Green" })
    Write-Host "Sunucu Başlangıç   : $($ServerStats.ServerStartTime)"
}
catch {
    Write-Host "[BİLGİ] Sunucu istatistikleri alınamadı" -ForegroundColor Yellow
}

# CSV Export
if ($ExportCSV) {
    $ReportPath = "$PSScriptRoot\DHCP-Rapor_$(Get-Date -Format 'yyyy-MM-dd').csv"
    $ScopeReport | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nRapor kaydedildi: $ReportPath" -ForegroundColor Green
}
