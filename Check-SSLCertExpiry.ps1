<#
.SYNOPSIS
    SSL Sertifika Süre Kontrolü
.DESCRIPTION
    Belirtilen sunucu ve portlardaki SSL sertifikalarının bitiş
    tarihini kontrol eder. Süresi yaklaşanları uyarı olarak gösterir.
    Exchange, IIS, ADFS gibi servislerin sertifika takibi için.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Check-SSLCertExpiry.ps1
#>

param(
    [int]$WarningDays = 30    # Bu kadar gün içinde dolacakları uyar
)

# ============================================
# KONTROL EDİLECEK SERVİSLER
# Kendi ortamınıza göre düzenleyin
# ============================================
$Services = @(
    @{ Name = "Exchange OWA";       Host = "mail.aschukuk.com";    Port = 443 },
    @{ Name = "Exchange SMTP/TLS";  Host = "mail.aschukuk.com";    Port = 587 },
    @{ Name = "ADFS";              Host = "adfs.aschukuk.com";    Port = 443 },
    @{ Name = "Intranet";          Host = "intranet.aschukuk.com"; Port = 443 },
    @{ Name = "VPN Portal";        Host = "vpn.aschukuk.com";     Port = 443 }
)

Write-Host "`n=== SSL SERTİFİKA SÜRE KONTROLÜ ===" -ForegroundColor Cyan
Write-Host "Uyarı Eşiği: $WarningDays gün"
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

$Results = @()

foreach ($Service in $Services) {
    try {
        # TCP bağlantısı kur
        $TcpClient = New-Object System.Net.Sockets.TcpClient
        $TcpClient.Connect($Service.Host, $Service.Port)

        $SslStream = New-Object System.Net.Security.SslStream(
            $TcpClient.GetStream(), $false,
            { param($s, $c, $ch, $e) return $true }  # Sertifika doğrulamayı atla
        )
        $SslStream.AuthenticateAsClient($Service.Host)

        $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $SslStream.RemoteCertificate
        )

        $ExpiryDate = $Cert.NotAfter
        $DaysLeft   = ($ExpiryDate - (Get-Date)).Days
        $Subject    = $Cert.Subject
        $Issuer     = ($Cert.Issuer -split ',')[0] -replace 'CN=',''

        $SslStream.Close()
        $TcpClient.Close()

        # Sonucu kaydet
        $Result = [PSCustomObject]@{
            Servis      = $Service.Name
            Adres       = "$($Service.Host):$($Service.Port)"
            Konu        = $Subject
            Veren       = $Issuer
            Bitis       = $ExpiryDate.ToString('dd.MM.yyyy')
            Kalan_Gun   = $DaysLeft
        }
        $Results += $Result

        # Ekrana yaz
        $Color = if ($DaysLeft -lt 0) { "Red" }
                 elseif ($DaysLeft -le $WarningDays) { "Yellow" }
                 else { "Green" }

        $Flag = if ($DaysLeft -lt 0) { " [SÜRESI DOLMUŞ!]" }
                elseif ($DaysLeft -le $WarningDays) { " [YAKIN!]" }
                else { "" }

        Write-Host ("{0,-20} : {1} gün kaldı  ({2}){3}" -f `
            $Service.Name, $DaysLeft, $ExpiryDate.ToString('dd.MM.yyyy'), $Flag) `
            -ForegroundColor $Color
    }
    catch {
        Write-Host ("{0,-20} : BAĞLANTI HATASI - {1}" -f $Service.Name, $_.Exception.Message) `
            -ForegroundColor Red
    }
}

# ============================================
# ÖZET
# ============================================
$Expired  = ($Results | Where-Object { $_.Kalan_Gun -lt 0 }).Count
$Warning  = ($Results | Where-Object { $_.Kalan_Gun -ge 0 -and $_.Kalan_Gun -le $WarningDays }).Count
$OK       = ($Results | Where-Object { $_.Kalan_Gun -gt $WarningDays }).Count

Write-Host "`n--- Özet ---" -ForegroundColor Cyan
Write-Host "Süresi Dolmuş  : $Expired" -ForegroundColor $(if ($Expired -gt 0) { "Red" } else { "Green" })
Write-Host "Süresi Yakın   : $Warning" -ForegroundColor $(if ($Warning -gt 0) { "Yellow" } else { "Green" })
Write-Host "Normal         : $OK" -ForegroundColor Green
