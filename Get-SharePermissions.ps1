<#
.SYNOPSIS
    Paylaşımlı Klasör Yetki Denetimi
.DESCRIPTION
    Belirtilen sunucudaki paylaşımlı klasörlerin NTFS ve Share
    izinlerini listeler. Güvenlik denetimi ve yetki kontrolü için.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.EXAMPLE
    .\Get-SharePermissions.ps1 -ServerName "FILESERVER"
    .\Get-SharePermissions.ps1 -ServerName "FILESERVER" -ExportCSV
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerName,

    [switch]$ExportCSV
)

Write-Host "`n=== PAYLAŞIMLI KLASÖR YETKİ RAPORU ===" -ForegroundColor Cyan
Write-Host "Sunucu: $ServerName"
Write-Host "Tarih : $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

$AllPermissions = @()

# ============================================
# PAYLAŞIMLARI LİSTELE
# ============================================
try {
    $Shares = Get-WmiObject -Class Win32_Share -ComputerName $ServerName |
        Where-Object { $_.Type -eq 0 }   # Sadece disk paylaşımları (admin$ vb. hariç)

    foreach ($Share in $Shares) {
        Write-Host "--- \\$ServerName\$($Share.Name) ---" -ForegroundColor White
        Write-Host "    Yol: $($Share.Path)" -ForegroundColor DarkGray

        # Share-level izinler
        try {
            $ShareSec = Get-SmbShareAccess -Name $Share.Name -CimSession $ServerName -ErrorAction Stop

            foreach ($Ace in $ShareSec) {
                $Permission = [PSCustomObject]@{
                    Paylasim     = $Share.Name
                    Yol          = $Share.Path
                    IzinTipi     = "Share"
                    Hesap        = $Ace.AccountName
                    Erisim       = $Ace.AccessRight
                    DurumTipi    = $Ace.AccessControlType
                }
                $AllPermissions += $Permission

                $Color = if ($Ace.AccountName -match "Everyone") { "Red" } else { "White" }
                Write-Host ("    [Share] {0,-30} : {1} ({2})" -f `
                    $Ace.AccountName, $Ace.AccessRight, $Ace.AccessControlType) -ForegroundColor $Color
            }
        }
        catch {
            Write-Host "    [BİLGİ] Share izinleri okunamadı" -ForegroundColor Yellow
        }

        # NTFS izinler (üst düzey)
        try {
            $Acl = Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param($Path)
                (Get-Acl -Path $Path).Access
            } -ArgumentList $Share.Path -ErrorAction Stop

            foreach ($Ace in $Acl) {
                if ($Ace.IsInherited) { continue }  # Miras alınanları atla

                $Permission = [PSCustomObject]@{
                    Paylasim     = $Share.Name
                    Yol          = $Share.Path
                    IzinTipi     = "NTFS"
                    Hesap        = $Ace.IdentityReference.ToString()
                    Erisim       = $Ace.FileSystemRights.ToString()
                    DurumTipi    = $Ace.AccessControlType.ToString()
                }
                $AllPermissions += $Permission

                $Color = if ($Ace.IdentityReference -match "Everyone") { "Red" } else { "DarkGray" }
                Write-Host ("    [NTFS]  {0,-30} : {1}" -f `
                    $Ace.IdentityReference, $Ace.FileSystemRights) -ForegroundColor $Color
            }
        }
        catch {
            Write-Host "    [BİLGİ] NTFS izinleri okunamadı" -ForegroundColor Yellow
        }

        Write-Host ""
    }

    # ============================================
    # GÜVENLİK UYARILARI
    # ============================================
    $EveryoneAccess = $AllPermissions | Where-Object { $_.Hesap -match "Everyone" }
    if ($EveryoneAccess) {
        Write-Host "⚠ UYARI: 'Everyone' yetkisi olan paylaşımlar:" -ForegroundColor Red
        $EveryoneAccess | ForEach-Object {
            Write-Host "  \\$ServerName\$($_.Paylasim) - $($_.IzinTipi): $($_.Erisim)" -ForegroundColor Red
        }
    }

    # ============================================
    # ÖZET & EXPORT
    # ============================================
    Write-Host "`n--- Özet ---" -ForegroundColor Cyan
    Write-Host "Toplam Paylaşım    : $($Shares.Count)"
    Write-Host "Toplam Yetki Kaydı : $($AllPermissions.Count)"
    Write-Host "Everyone Yetkisi   : $($EveryoneAccess.Count) adet" -ForegroundColor $(if ($EveryoneAccess) { "Red" } else { "Green" })

    if ($ExportCSV) {
        $ReportPath = "$PSScriptRoot\SharePerms_${ServerName}_$(Get-Date -Format 'yyyy-MM-dd').csv"
        $AllPermissions | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nRapor kaydedildi: $ReportPath" -ForegroundColor Green
    }
}
catch {
    Write-Host "[HATA] Paylaşım bilgisi alınamadı: $_" -ForegroundColor Red
}
