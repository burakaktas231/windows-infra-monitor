<#
.SYNOPSIS
    DNS Kayıt Yönetimi ve Denetim Raporu
.DESCRIPTION
    DNS sunucusundaki kayıtları listeler, eski kayıtları tespit eder,
    yeni kayıt ekler/siler. DNS zone sağlık kontrolü yapar.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Manage-DNS.ps1 -Action Report -ZoneName "aschukuk.com"
    .\Manage-DNS.ps1 -Action AddRecord -ZoneName "aschukuk.com" -RecordName "printer01" -IPAddress "192.168.1.50"
    .\Manage-DNS.ps1 -Action StaleRecords -ZoneName "aschukuk.com"
#>

param(
    [ValidateSet("Report", "AddRecord", "RemoveRecord", "StaleRecords", "ZoneHealth")]
    [string]$Action = "Report",

    [string]$ZoneName = "aschukuk.com",
    [string]$DNSServer = "DC01",
    [string]$RecordName,
    [string]$IPAddress,
    [string]$RecordType = "A",
    [switch]$ExportCSV
)

Write-Host "`n=== DNS YÖNETİMİ ===" -ForegroundColor Cyan
Write-Host "İşlem     : $Action"
Write-Host "Zone      : $ZoneName"
Write-Host "DNS Server: $DNSServer`n"

switch ($Action) {

    # ============================================
    # DNS KAYIT RAPORU
    # ============================================
    "Report" {
        try {
            $Records = Get-DnsServerResourceRecord -ZoneName $ZoneName -ComputerName $DNSServer

            # Kayıt türüne göre grupla
            Write-Host "--- Kayıt Türü Dağılımı ---`n" -ForegroundColor Cyan
            $Records | Group-Object RecordType | Sort-Object Count -Descending |
                ForEach-Object {
                    Write-Host ("  {0,-10} : {1}" -f $_.Name, $_.Count)
                }

            Write-Host "`n--- A Kayıtları ---`n" -ForegroundColor Cyan
            $ARecords = $Records | Where-Object { $_.RecordType -eq "A" } | Sort-Object HostName

            foreach ($Rec in $ARecords) {
                $IP = $Rec.RecordData.IPv4Address.IPAddressToString
                $Age = if ($Rec.Timestamp) {
                    "$((New-TimeSpan -Start $Rec.Timestamp -End (Get-Date)).Days) gün"
                } else { "Statik" }

                Write-Host ("{0,-30} --> {1,-16} ({2})" -f $Rec.HostName, $IP, $Age)
            }

            Write-Host "`n--- CNAME Kayıtları ---`n" -ForegroundColor Cyan
            $CNAMEs = $Records | Where-Object { $_.RecordType -eq "CNAME" }
            foreach ($Rec in $CNAMEs) {
                Write-Host ("{0,-30} --> {1}" -f $Rec.HostName, $Rec.RecordData.HostNameAlias)
            }

            Write-Host "`n--- MX Kayıtları ---`n" -ForegroundColor Cyan
            $MXRecords = $Records | Where-Object { $_.RecordType -eq "MX" }
            foreach ($Rec in $MXRecords) {
                Write-Host ("  Öncelik {0}: {1}" -f $Rec.RecordData.Preference, $Rec.RecordData.MailExchange)
            }

            Write-Host "`nToplam kayıt: $($Records.Count)"

            if ($ExportCSV) {
                $ReportPath = "$PSScriptRoot\DNS-Rapor_$(Get-Date -Format 'yyyy-MM-dd').csv"
                $ARecords | Select-Object HostName,
                    @{N="IP"; E={$_.RecordData.IPv4Address.IPAddressToString}},
                    Timestamp, RecordType |
                Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
                Write-Host "Rapor kaydedildi: $ReportPath" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[HATA] DNS sorgusu başarısız: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # KAYIT EKLE
    # ============================================
    "AddRecord" {
        if (-not $RecordName -or -not $IPAddress) {
            Write-Host "Kullanım: -Action AddRecord -RecordName 'sunucu01' -IPAddress '192.168.1.10'" -ForegroundColor Yellow
            exit
        }

        try {
            switch ($RecordType) {
                "A" {
                    Add-DnsServerResourceRecordA -Name $RecordName -ZoneName $ZoneName `
                        -IPv4Address $IPAddress -ComputerName $DNSServer
                }
                "CNAME" {
                    Add-DnsServerResourceRecordCName -Name $RecordName -ZoneName $ZoneName `
                        -HostNameAlias $IPAddress -ComputerName $DNSServer
                }
            }
            Write-Host "[OK] $RecordType kaydı eklendi: $RecordName --> $IPAddress" -ForegroundColor Green
        }
        catch {
            Write-Host "[HATA] Kayıt eklenemedi: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # KAYIT SİL
    # ============================================
    "RemoveRecord" {
        if (-not $RecordName) {
            Write-Host "Kullanım: -Action RemoveRecord -RecordName 'eski-sunucu'" -ForegroundColor Yellow
            exit
        }

        try {
            $Record = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $RecordName `
                -ComputerName $DNSServer -RRType $RecordType -ErrorAction Stop

            Write-Host "Silinecek kayıt:" -ForegroundColor Yellow
            Write-Host "  $RecordName ($RecordType)"

            $Confirm = Read-Host "Onaylıyor musunuz? (E/H)"
            if ($Confirm -eq "E") {
                Remove-DnsServerResourceRecord -ZoneName $ZoneName -Name $RecordName `
                    -RRType $RecordType -ComputerName $DNSServer -Force
                Write-Host "[OK] Kayıt silindi." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[HATA] Kayıt bulunamadı veya silinemedi: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # ESKİ KAYITLAR
    # ============================================
    "StaleRecords" {
        Write-Host "--- Eski DNS Kayıtları (90+ gün) ---`n" -ForegroundColor Yellow

        $CutoffDate = (Get-Date).AddDays(-90)

        $AllRecords = Get-DnsServerResourceRecord -ZoneName $ZoneName -ComputerName $DNSServer |
            Where-Object { $_.RecordType -eq "A" -and $_.Timestamp -and $_.Timestamp -lt $CutoffDate } |
            Sort-Object Timestamp

        if ($AllRecords) {
            foreach ($Rec in $AllRecords) {
                $AgeDays = (New-TimeSpan -Start $Rec.Timestamp -End (Get-Date)).Days
                Write-Host ("{0,-30} {1,-16} ({2} gün)" -f `
                    $Rec.HostName, $Rec.RecordData.IPv4Address.IPAddressToString, $AgeDays) `
                    -ForegroundColor Yellow
            }
            Write-Host "`nToplam: $($AllRecords.Count) eski kayıt"
            Write-Host "[İPUCU] DNS Scavenging aktif değilse etkinleştirmeyi düşünün."
        }
        else {
            Write-Host "90 günden eski kayıt bulunamadı." -ForegroundColor Green
        }
    }

    # ============================================
    # ZONE SAĞLIK KONTROLÜ
    # ============================================
    "ZoneHealth" {
        Write-Host "--- DNS Zone Sağlık Kontrolü ---`n" -ForegroundColor Cyan

        try {
            $Zone = Get-DnsServerZone -Name $ZoneName -ComputerName $DNSServer

            Write-Host "Zone Adı       : $($Zone.ZoneName)"
            Write-Host "Zone Tipi      : $($Zone.ZoneType)"
            Write-Host "Dinamik Güncelleme : $($Zone.DynamicUpdate)"
            Write-Host "AD Entegre     : $($Zone.IsAutoCreated -eq $false -and $Zone.ZoneType -eq 'Primary')"

            # Scavenging durumu
            $Scavenging = Get-DnsServerScavenging -ComputerName $DNSServer
            Write-Host "`nScavenging Durumu:" -ForegroundColor Cyan
            Write-Host "  Aktif     : $($Scavenging.ScavengingState)"
            Write-Host "  Aralık    : $($Scavenging.ScavengingInterval)"
            Write-Host "  Refresh   : $($Scavenging.RefreshInterval)"
            Write-Host "  No-Refresh: $($Scavenging.NoRefreshInterval)"

            if (-not $Scavenging.ScavengingState) {
                Write-Host "`n⚠ Scavenging kapalı! Eski kayıtlar birikmekte." -ForegroundColor Yellow
            }

            # Forwarder kontrolü
            $Forwarders = Get-DnsServerForwarder -ComputerName $DNSServer
            Write-Host "`nForwarder'lar:" -ForegroundColor Cyan
            $Forwarders.IPAddress | ForEach-Object {
                Write-Host "  $_"
            }
        }
        catch {
            Write-Host "[HATA] Zone bilgisi alınamadı: $_" -ForegroundColor Red
        }
    }
}
