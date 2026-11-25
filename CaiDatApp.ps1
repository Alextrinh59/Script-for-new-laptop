#Requires -Version 5.1
<#
.SYNOPSIS
    Cài đặt các ứng dụng cần thiết bản mới nhất, bỏ qua ứng dụng đã có.

.DESCRIPTION
    Kiểm tra Telegram, Viber, WhatsApp, Office, UniKey và Google Chrome.
    - Nếu ứng dụng đã có (kể cả bản cũ) thì KHÔNG tải/cài lại.
    - Nếu chưa có, tải và cài bản mới nhất từ nguồn chính thức hoặc winget.
    - Chrome: đặt Google làm công cụ tìm kiếm, mở Windows Settings để đặt
      Chrome làm trình duyệt mặc định (Windows chặn script đặt mặc định hoàn toàn tự động).

.PARAMETER CheckOnly
    Chỉ kiểm tra trạng thái, không cài đặt và không thay đổi cấu hình.

.PARAMETER NoElevate
    Không tự yêu cầu quyền Administrator.

.PARAMETER SkipOffice
    Bỏ qua Office kể cả khi máy chưa cài.

.PARAMETER SkipDefaultBrowser
    Không mở phần cài đặt trình duyệt mặc định.

.PARAMETER DownloadFolder
    Thư mục lưu installer tải trực tiếp. Mặc định: Downloads\AppInstallers

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\CaiDatApp.ps1 -CheckOnly

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\CaiDatApp.ps1

.NOTES
    Có thể double-click ChayCaiDatApp.bat để tự chạy với quyền Administrator.
    Script không gỡ cài đặt và không xóa dữ liệu ứng dụng.
#>

[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$NoElevate,
    [switch]$SkipOffice,
    [switch]$SkipDefaultBrowser,
    [string]$DownloadFolder = "$env:USERPROFILE\Downloads\AppInstallers"
)

$ErrorActionPreference = 'Continue'
$script:StartedAt = Get-Date
$script:Version = '1.0'

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    [Console]::InputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
} catch { }
try { $null = & "$env:SystemRoot\System32\chcp.com" 65001 } catch { }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Set-ConsoleFont {
    param([string]$FaceName = 'Consolas', [int16]$PreferSize = 16)
    try {
        if ($Host.Name -ne 'ConsoleHost') { return }
        if ([Console]::IsOutputRedirected) { return }

        $source = @"
using System;
using System.Runtime.InteropServices;

namespace CaiDatApp {
    public static class ConsoleFont {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CONSOLE_FONT_INFO_EX {
            public uint cbSize;
            public uint nFont;
            public short dwFontSizeX;
            public short dwFontSizeY;
            public int FontFamily;
            public int FontWeight;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string FaceName;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool GetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFO_EX lpConsoleCurrentFontEx);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool SetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFO_EX lpConsoleCurrentFontEx);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleOutputCP(uint wCodePageID);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleCP(uint wCodePageID);
    }
}
"@

        if (-not ('CaiDatApp.ConsoleFont' -as [type])) {
            Add-Type -TypeDefinition $source
        }

        [void][CaiDatApp.ConsoleFont]::SetConsoleOutputCP(65001)
        [void][CaiDatApp.ConsoleFont]::SetConsoleCP(65001)

        $info = New-Object CaiDatApp.ConsoleFont+CONSOLE_FONT_INFO_EX
        $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($info)
        $handle = [CaiDatApp.ConsoleFont]::GetStdHandle(-11)
        if ([CaiDatApp.ConsoleFont]::GetCurrentConsoleFontEx($handle, $false, [ref]$info)) {
            $sizeY = $PreferSize
            if ($info.dwFontSizeY -ge 14) { $sizeY = $info.dwFontSizeY }
            $info.FaceName = $FaceName
            $info.FontFamily = 54
            $info.FontWeight = 400
            $info.dwFontSizeX = 0
            $info.dwFontSizeY = $sizeY
            [void][CaiDatApp.ConsoleFont]::SetCurrentConsoleFontEx($handle, $false, [ref]$info)
        }
    } catch { }
}

Set-ConsoleFont
try { $Host.UI.RawUI.WindowTitle = 'Cài đặt ứng dụng' } catch { }

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Skip { param([string]$Text) Write-Host "  [BỎ QUA] $Text" -ForegroundColor DarkGray }
function Write-Warn2 { param([string]$Text) Write-Host "  [LƯU Ý] $Text" -ForegroundColor Yellow }
function Write-Fail { param([string]$Text) Write-Host "  [LỖI] $Text" -ForegroundColor Red }

$isAdmin = Test-IsAdmin

if (-not $CheckOnly -and -not $isAdmin -and -not $NoElevate) {
    Write-Host ''
    Write-Host 'Cần quyền Administrator để cài ứng dụng và ghi policy Chrome.' -ForegroundColor Yellow
    $answer = Read-Host 'Chạy lại với quyền Administrator? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
        $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($SkipOffice) { $argString += ' -SkipOffice' }
        if ($SkipDefaultBrowser) { $argString += ' -SkipDefaultBrowser' }
        if ($DownloadFolder) { $argString += " -DownloadFolder `"$DownloadFolder`"" }
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argString -ErrorAction Stop
            exit
        } catch {
            Write-Warning "Không thể nâng quyền: $($_.Exception.Message)"
            Write-Host 'Tiếp tục với quyền hiện tại; một số bước có thể thất bại.' -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
}

$isAdmin = Test-IsAdmin

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '           CÀI ĐẶT ỨNG DỤNG - PHIÊN BẢN MỚI NHẤT' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host "  Chế độ: $(if ($CheckOnly) { 'CHỈ KIỂM TRA' } else { 'CÀI ĐẶT' })" -ForegroundColor White
Write-Host "  Quyền Administrator: $(if ($isAdmin) { 'Có' } else { 'Không' })" -ForegroundColor $(if ($isAdmin) { 'Green' } else { 'Yellow' })
Write-Host ''

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = $null
if (-not $CheckOnly) {
    try {
        if (-not (Test-Path $DownloadFolder)) {
            New-Item -ItemType Directory -Path $DownloadFolder -Force -ErrorAction Stop | Out-Null
        }
        $logPath = Join-Path $DownloadFolder "CaiDatApp_$stamp.log"
        try { Start-Transcript -Path $logPath -Force -ErrorAction Stop | Out-Null } catch { $logPath = $null }
    } catch {
        Write-Warn2 "Không tạo được thư mục tải: $($_.Exception.Message)"
    }
}

$script:WingetPath = $null
$wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($wingetCommand) { $script:WingetPath = $wingetCommand.Source }
if (-not $script:WingetPath) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $candidate) { $script:WingetPath = $candidate }
}

$uninstallRoots = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$uninstallEntries = @()
foreach ($root in $uninstallRoots) {
    try {
        $uninstallEntries += @(Get-ItemProperty -Path $root -ErrorAction Stop | Where-Object { $_.DisplayName })
    } catch { }
}

$allAppx = @()
try { $allAppx = @(Get-AppxPackage -AllUsers -ErrorAction Stop) } catch {
    try { $allAppx = @(Get-AppxPackage -ErrorAction Stop) } catch { }
}

$pf86 = ${env:ProgramFiles(x86)}
if (-not $pf86) { $pf86 = $env:ProgramFiles }

$appDefs = @(
    [pscustomobject]@{
        Key          = 'Telegram'
        Name         = 'Telegram Desktop'
        Pattern      = '^Telegram Desktop'
        Appx         = 'Telegram'
        Paths        = @(
            (Join-Path $env:APPDATA 'Telegram Desktop\Telegram.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Telegram Desktop\Telegram.exe')
        )
        WingetId     = 'Telegram.TelegramDesktop'
        WingetSource = 'winget'
        DirectUrl    = 'https://telegram.org/dl/desktop/win64'
        DirectFile   = 'TelegramSetup.exe'
        DirectType   = 'inno'
    },
    [pscustomobject]@{
        Key          = 'Viber'
        Name         = 'Viber'
        Pattern      = '^Viber'
        Appx         = 'Viber'
        Paths        = @(
            (Join-Path $env:LOCALAPPDATA 'Viber\Viber.exe'),
            (Join-Path $env:ProgramFiles 'Viber\Viber.exe'),
            (Join-Path $pf86 'Viber\Viber.exe')
        )
        WingetId     = 'Rakuten.Viber'
        WingetSource = 'winget'
        DirectUrl    = 'https://download.cdn.viber.com/cdn/desktop/windows/ViberSetup.exe'
        DirectFile   = 'ViberSetup.exe'
        DirectType   = 'exe'
    },
    [pscustomobject]@{
        Key          = 'WhatsApp'
        Name         = 'WhatsApp'
        Pattern      = '^WhatsApp'
        Appx         = 'WhatsApp'
        Paths        = @(
            (Join-Path $env:LOCALAPPDATA 'WhatsApp\WhatsApp.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\WhatsApp\WhatsApp.exe'),
            (Join-Path $env:ProgramFiles 'WhatsApp\WhatsApp.exe')
        )
        WingetId     = '9NKSQGP7F2NH'
        WingetSource = 'msstore'
        DirectUrl    = 'https://get.microsoft.com/installer/download/9NKSQGP7F2NH?cid=website_cta_psi'
        DirectFile   = 'WhatsAppInstaller.exe'
        DirectType   = 'exe'
    },
    [pscustomobject]@{
        Key          = 'Office'
        Name         = 'Microsoft Office / Microsoft 365'
        Pattern      = '^(Microsoft 365|Microsoft Office|Office 16 Click-to-Run)'
        Appx         = ''
        Paths        = @()
        WingetId     = 'Microsoft.Office'
        WingetSource = 'winget'
        DirectUrl    = 'https://www.microsoft.com/microsoft-365/download-office'
        DirectFile   = ''
        DirectType   = 'page'
    },
    [pscustomobject]@{
        Key          = 'UniKey'
        Name         = 'UniKey'
        Pattern      = '^UniKey'
        Appx         = ''
        Paths        = @(
            (Join-Path $env:ProgramFiles 'UniKey\UnikeyNT.exe'),
            (Join-Path $pf86 'UniKey\UnikeyNT.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\UniKey\UnikeyNT.exe'),
            (Join-Path $env:APPDATA 'UniKey\UnikeyNT.exe')
        )
        WingetId     = ''
        WingetSource = ''
        DirectUrl    = ''
        DirectFile   = ''
        DirectType   = 'unikey'
    },
    [pscustomobject]@{
        Key          = 'Chrome'
        Name         = 'Google Chrome'
        Pattern      = '^Google Chrome'
        Appx         = ''
        Paths        = @(
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $pf86 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
        )
        WingetId     = 'Google.Chrome'
        WingetSource = 'winget'
        DirectUrl    = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
        DirectFile   = 'GoogleChromeStandaloneEnterprise64.msi'
        DirectType   = 'msi'
    }
)

function Get-OfficeStatus {
    $ctr = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if ($ctr -and $ctr.ProductReleaseIds) {
        return [pscustomobject]@{
            Installed = $true
            Version   = [string]$ctr.VersionToReport
            Detail    = "ClickToRun: $($ctr.ProductReleaseIds)"
        }
    }
    $match = @($uninstallEntries | Where-Object {
            $_.DisplayName -match '^(Microsoft 365|Microsoft Office)' -and
            $_.DisplayName -notmatch 'Filter|Language|Proofing|Telemetry|Component|Update|Service Pack|Licensing'
        } | Select-Object -First 1)
    if ($match) {
        return [pscustomobject]@{ Installed = $true; Version = [string]$match.DisplayVersion; Detail = [string]$match.DisplayName }
    }
    return [pscustomobject]@{ Installed = $false; Version = ''; Detail = '' }
}

function Get-AppStatus {
    param($App)

    if ($App.Key -eq 'Office') { return (Get-OfficeStatus) }

    if ($App.Pattern) {
        $match = @($uninstallEntries | Where-Object { $_.DisplayName -match $App.Pattern } | Select-Object -First 1)
        if ($match) {
            return [pscustomobject]@{ Installed = $true; Version = [string]$match.DisplayVersion; Detail = [string]$match.DisplayName }
        }
    }

    if ($App.Appx) {
        $appxMatch = @($allAppx | Where-Object { $_.Name -match $App.Appx } | Select-Object -First 1)
        if (-not $appxMatch) {
            try {
                $appxMatch = @(Get-AppxPackage -Name "*$($App.Appx)*" -ErrorAction Stop | Select-Object -First 1)
            } catch { }
        }
        if (-not $appxMatch) {
            try {
                $appxMatch = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -match $App.Appx } | Select-Object -First 1)
            } catch { }
        }
        if ($appxMatch) {
            return [pscustomobject]@{ Installed = $true; Version = [string]$appxMatch.Version; Detail = [string]$appxMatch.PackageFullName }
        }
    }

    foreach ($path in @($App.Paths)) {
        if ($path -and (Test-Path $path)) {
            $version = ''
            try { $version = (Get-Item $path).VersionInfo.ProductVersion } catch { }
            return [pscustomobject]@{ Installed = $true; Version = $version; Detail = $path }
        }
    }

    return [pscustomobject]@{ Installed = $false; Version = ''; Detail = '' }
}

$statuses = @()
foreach ($app in $appDefs) {
    $status = Get-AppStatus $app
    $statuses += [pscustomobject]@{ App = $app; Status = $status }
}

if ($CheckOnly) {
    Write-Host ''
    Write-Host 'TRẠNG THÁI ỨNG DỤNG' -ForegroundColor Cyan
    Write-Host '------------------------------------------------------------------' -ForegroundColor DarkGray
    foreach ($item in $statuses) {
        if ($item.Status.Installed) {
            Write-Host ("  {0,-32} ĐÃ CÓ {1}" -f $item.App.Name, $item.Status.Version) -ForegroundColor Green
            Write-Host ("      {0}" -f $item.Status.Detail) -ForegroundColor DarkGray
        } else {
            Write-Host ("  {0,-32} CHƯA CÓ" -f $item.App.Name) -ForegroundColor Yellow
        }
    }
    Write-Host ''
    Write-Host 'Chế độ chỉ kiểm tra: không cài đặt, không thay đổi cấu hình.' -ForegroundColor DarkGray
    Write-Host 'Bỏ -CheckOnly để cài các ứng dụng còn thiếu.' -ForegroundColor DarkGray
    exit 0
}

$script:Results = New-Object System.Collections.ArrayList
function Add-Result {
    param([string]$Name, [string]$Status, [string]$Version = '', [string]$Note = '')
    [void]$script:Results.Add([pscustomobject]@{
            Name    = $Name
            Status  = $Status
            Version = $Version
            Note    = $Note
        })
}

function Get-AppVersionSafe {
    param($App)
    $s = Get-AppStatus $App
    if ($s.Installed) { return $s.Version }
    return ''
}

function Find-ChromeExe {
    foreach ($path in @(
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $pf86 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
        )) {
        if ($path -and (Test-Path $path)) { return $path }
    }
    return $null
}

function Install-ViaWinget {
    param($App)
    if (-not $script:WingetPath) { return $false }

    Write-Host "  Đang cài bằng winget: $($App.WingetId) ..." -ForegroundColor Yellow
    $wingetArgs = @(
        'install',
        '--id', $App.WingetId,
        '--exact',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )
    if ($App.WingetSource -eq 'msstore') {
        $wingetArgs += @('--source', 'msstore')
    }

    try {
        $output = & $script:WingetPath @wingetArgs 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in @($output)) { Write-Host "    $line" -ForegroundColor DarkGray }
        Write-Host "    Winget exit code: $exitCode" -ForegroundColor DarkGray
        if ($exitCode -eq 0) { return $true }
        return $false
    } catch {
        Write-Fail "Winget lỗi: $($_.Exception.Message)"
        return $false
    }
}

function Save-Download {
    param([string]$Url, [string]$Path)
    Write-Host "  Đang tải: $Url" -ForegroundColor Yellow
    try {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 180
        if (-not (Test-Path $Path)) { return $false }
        $size = (Get-Item $Path).Length
        Write-Host "  Đã tải: $Path ($([Math]::Round($size / 1MB, 1)) MB)" -ForegroundColor DarkGray
        return $true
    } catch {
        Write-Fail "Tải thất bại: $($_.Exception.Message)"
        return $false
    }
}

function Install-DirectInstaller {
    param($App)
    $appDir = Join-Path $DownloadFolder $App.Key
    if (-not (Test-Path $appDir)) { New-Item -ItemType Directory -Path $appDir -Force | Out-Null }

    if ($App.DirectType -eq 'page') {
        Write-Warn2 "Không cài tự động được Office trong trường hợp này. Mở trang tải chính thức..."
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList $App.DirectUrl -ErrorAction Stop } catch { }
        return $false
    }

    $filePath = Join-Path $appDir $App.DirectFile
    if (-not (Save-Download -Url $App.DirectUrl -Path $filePath)) { return $false }

    if ($App.DirectType -in @('inno', 'msi', 'exe')) {
        try {
            $signature = Get-AuthenticodeSignature -FilePath $filePath -ErrorAction Stop
            if ($signature.Status -ne 'Valid') {
                Write-Fail "Chữ ký số không hợp lệ ($($signature.Status)); không chạy installer."
                return $false
            }
            Write-Host "  Chữ ký số: $($signature.SignerCertificate.Subject)" -ForegroundColor DarkGray
        } catch {
            Write-Fail "Không kiểm tra được chữ ký số: $($_.Exception.Message)"
            return $false
        }
    }

    try {
        switch ($App.DirectType) {
            'inno' {
                $p = Start-Process -FilePath $filePath -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait -PassThru
                return ($p.ExitCode -eq 0)
            }
            'msi' {
                $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', "`"$filePath`"", '/qn', '/norestart' -Wait -PassThru
                return ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010)
            }
            'exe' {
                if ($App.Key -eq 'Viber') {
                    $p = Start-Process -FilePath $filePath -ArgumentList '/S' -Wait -PassThru
                    return ($p.ExitCode -eq 0)
                }
                $p = Start-Process -FilePath $filePath -Wait -PassThru
                return ($p.ExitCode -eq 0)
            }
        }
    } catch {
        Write-Fail "Chạy installer lỗi: $($_.Exception.Message)"
    }
    return $false
}

function New-Shortcut {
    param([string]$Path, [string]$TargetPath, [string]$WorkingDirectory)
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($Path)
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.Save()
    } catch { }
}

function Install-UniKey {
    Write-Host '  Đang tải UniKey bản mới nhất từ unikey.org...' -ForegroundColor Yellow
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'win64' }
    $page = $null
    try { $page = (Invoke-WebRequest -Uri 'https://www.unikey.org/download.html' -UseBasicParsing -TimeoutSec 60).Content } catch { }
    $url = $null
    if ($page) {
        $pattern = 'https://www\.unikey\.org/assets/release/unikey(\d+)(RC\d*)?-(\d+)-' + $arch + '\.zip'
        $candidates = @([regex]::Matches($page, $pattern) | ForEach-Object {
                [pscustomobject]@{
                    Url     = $_.Value
                    Version = [int]$_.Groups[1].Value
                    Date    = [int]$_.Groups[3].Value
                }
            } | Sort-Object Version, Date -Descending)
        if ($candidates.Count -gt 0) { $url = $candidates[0].Url }
    }
    if (-not $url -and $arch -eq 'win64') {
        $url = 'https://www.unikey.org/assets/release/unikey46RC2-230919-win64.zip'
    }
    if (-not $url) {
        Write-Fail 'Không tìm được link UniKey phù hợp.'
        return $false
    }

    $appDir = Join-Path $DownloadFolder 'UniKey'
    if (-not (Test-Path $appDir)) { New-Item -ItemType Directory -Path $appDir -Force | Out-Null }
    $zipPath = Join-Path $appDir 'UniKey.zip'
    if (-not (Save-Download -Url $url -Path $zipPath)) { return $false }

    $extractDir = Join-Path $appDir 'extract'
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force -ErrorAction Stop
    } catch {
        Write-Fail "Giải nén UniKey lỗi: $($_.Exception.Message)"
        return $false
    }

    $dest = if ($isAdmin) {
        Join-Path $env:ProgramFiles 'UniKey'
    } else {
        Join-Path $env:LOCALAPPDATA 'Programs\UniKey'
    }
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    Copy-Item -Path (Join-Path $extractDir '*') -Destination $dest -Recurse -Force -ErrorAction Continue

    $exe = Join-Path $dest 'UnikeyNT.exe'
    if (-not (Test-Path $exe)) {
        Write-Fail 'Không tìm thấy UnikeyNT.exe sau khi giải nén.'
        return $false
    }

    $startMenu = [Environment]::GetFolderPath('Programs')
    New-Shortcut -Path (Join-Path $startMenu 'UniKey.lnk') -TargetPath $exe -WorkingDirectory $dest
    $startup = [Environment]::GetFolderPath('Startup')
    New-Shortcut -Path (Join-Path $startup 'UniKey.lnk') -TargetPath $exe -WorkingDirectory $dest

    try { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$exe`"" -ErrorAction SilentlyContinue } catch { }
    return $true
}

function Install-App {
    param($App)
    $installed = Install-ViaWinget $App
    if ($installed) { return $true }

    if ($App.Key -eq 'UniKey') {
        return (Install-UniKey)
    }

    Write-Warn2 "Winget không cài được, chuyển sang tải trực tiếp..."
    return (Install-DirectInstaller $App)
}

function Set-ChromeGoogleSearchPolicy {
    $policyValues = @{
        'DefaultSearchProviderEnabled'  = 1
        'DefaultSearchProviderName'     = 'Google'
        'DefaultSearchProviderKeyword'  = 'google.com'
        'DefaultSearchProviderSearchURL' = 'https://www.google.com/search?q={searchTerms}'
        'DefaultSearchProviderSuggestURL' = 'https://www.google.com/complete/search?output=chrome&q={searchTerms}'
        'DefaultSearchProviderIconURL'  = 'https://www.google.com/favicon.ico'
        'DefaultBrowserSettingEnabled'  = 1
    }

    $ok = $false
    foreach ($policyPath in @(
            'HKLM:\SOFTWARE\Policies\Google\Chrome',
            'HKLM:\SOFTWARE\WOW6432Node\Policies\Google\Chrome',
            'HKCU:\Software\Policies\Google\Chrome'
        )) {
        try {
            if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null }
            foreach ($name in $policyValues.Keys) {
                $value = $policyValues[$name]
                $type = if ($value -is [int]) { 'DWord' } else { 'String' }
                New-ItemProperty -Path $policyPath -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null
            }
            $ok = $true
        } catch { }
    }
    return $ok
}

function Set-DefaultBrowserBestEffort {
    $chrome = Find-ChromeExe
    if (-not $chrome) { return 'Không tìm thấy Chrome' }

    $progId = $null
    try {
        $choice = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' -ErrorAction SilentlyContinue
        if ($choice) { $progId = [string]$choice.ProgId }
    } catch { }

    if ($progId -match '^ChromeHTML') {
        return 'Chrome đã là trình duyệt mặc định'
    }

    if ($SkipDefaultBrowser) { return 'Bỏ qua theo tùy chọn' }

    # Windows chặn đặt mặc định hoàn toàn tự động; mở đúng trang và hướng dẫn.
    try { Start-Process -FilePath $chrome -ArgumentList '--make-default-browser' -ErrorAction SilentlyContinue } catch { }
    Start-Sleep -Milliseconds 800
    $opened = $false
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList 'ms-settings:defaultapps?registeredAppUser=Google%20Chrome' -ErrorAction Stop
        $opened = $true
    } catch {
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList 'ms-settings:defaultapps' -ErrorAction Stop; $opened = $true } catch { }
    }
    if ($opened) {
        return 'Cần bấm "Đặt mặc định" trong Windows Settings'
    }
    return 'Không mở được Windows Settings'
}

Write-Step 'KIỂM TRA ỨNG DỤNG'
foreach ($item in $statuses) {
    if ($item.Status.Installed) {
        Write-Skip "$($item.App.Name) đã có (phiên bản $($item.Status.Version)) - không tải."
        Add-Result -Name $item.App.Name -Status 'Đã có' -Version $item.Status.Version -Note 'Bỏ qua vì đã cài đặt'
    } else {
        Write-Host "  [CHƯA CÓ] $($item.App.Name)" -ForegroundColor Yellow
    }
}

$toInstall = @($statuses | Where-Object { -not $_.Status.Installed })

if ($SkipOffice) {
    $officeItem = @($toInstall | Where-Object { $_.App.Key -eq 'Office' } | Select-Object -First 1)
    if ($officeItem) {
        $toInstall = @($toInstall | Where-Object { $_.App.Key -ne 'Office' })
        Write-Skip 'Office: bỏ qua theo tùy chọn -SkipOffice.'
        Add-Result -Name 'Microsoft Office / Microsoft 365' -Status 'Bỏ qua' -Note 'Theo tùy chọn -SkipOffice'
    }
}

if ($toInstall.Count -eq 0) {
    Write-Host ''
    Write-Ok 'Không có ứng dụng nào cần cài đặt.'
} else {
    Write-Step 'BẮT ĐẦU CÀI ĐẶT'
    $i = 0
    foreach ($item in $toInstall) {
        $i++
        Write-Host ''
        Write-Host "[$i/$($toInstall.Count)] $($item.App.Name)" -ForegroundColor Cyan
        if ($item.App.Key -eq 'Office') {
            Write-Warn2 'Office sẽ cài gói Microsoft 365 Apps; cần đăng nhập tài khoản Microsoft 365 để kích hoạt.'
        }
        $ok = $false
        try {
            $ok = Install-App $item.App
        } catch {
            Write-Fail "Lỗi cài $($item.App.Name): $($_.Exception.Message)"
        }

        Start-Sleep -Milliseconds 500
        $after = Get-AppStatus $item.App
        if ($after.Installed) {
            Write-Ok "$($item.App.Name) đã cài đặt (phiên bản $($after.Version))."
            Add-Result -Name $item.App.Name -Status 'Đã cài' -Version $after.Version -Note $after.Detail
        } elseif ($ok) {
            Write-Ok "$($item.App.Name): installer báo thành công, hãy mở ứng dụng để kiểm tra."
            Add-Result -Name $item.App.Name -Status 'Đã cài' -Version '' -Note 'Installer báo thành công'
        } else {
            Write-Fail "$($item.App.Name) chưa cài được."
            Add-Result -Name $item.App.Name -Status 'Lỗi' -Version '' -Note 'Cài đặt thất bại, xem log'
        }
    }
}

# Cấu hình Chrome nếu Chrome có mặt
$browserStatus = ''
$chromeExe = Find-ChromeExe
if ($chromeExe) {
    Write-Step 'CẤU HÌNH GOOGLE CHROME'
    if (Set-ChromeGoogleSearchPolicy) {
        Write-Ok 'Đã đặt Google làm công cụ tìm kiếm mặc định (áp dụng sau khi khởi động lại Chrome).'
        Add-Result -Name 'Chrome - Search engine' -Status 'Đã đặt' -Version 'Google' -Note 'Chính sách Chrome; khởi động lại Chrome để áp dụng'
    } else {
        Write-Warn2 'Không ghi được policy Google Search (cần Administrator).'
        Add-Result -Name 'Chrome - Search engine' -Status 'Chưa đặt' -Note 'Cần quyền Administrator'
    }

    $browserStatus = Set-DefaultBrowserBestEffort
    if ($browserStatus -match 'đã là') {
        Write-Ok $browserStatus
        Add-Result -Name 'Chrome - Trình duyệt mặc định' -Status 'Đã có' -Note $browserStatus
    } elseif ($browserStatus -match 'Bỏ qua') {
        Write-Skip $browserStatus
        Add-Result -Name 'Chrome - Trình duyệt mặc định' -Status 'Bỏ qua' -Note $browserStatus
    } else {
        Write-Warn2 $browserStatus
        Add-Result -Name 'Chrome - Trình duyệt mặc định' -Status 'Cần xác nhận' -Note $browserStatus
    }
} elseif (-not $CheckOnly) {
    Write-Warn2 'Không tìm thấy Chrome sau khi cài đặt.'
}

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '                       KẾT QUẢ' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
$resultTable = $script:Results | Format-Table Name, Status, Version, Note -AutoSize | Out-String -Width 220
Write-Host $resultTable

if (@($script:Results | Where-Object { $_.Status -eq 'Lỗi' }).Count -gt 0) {
    Write-Host 'Một số ứng dụng cài đặt thất bại. Xem log và thử chạy lại.' -ForegroundColor Yellow
}
if ($browserStatus -and $browserStatus -notmatch 'đã là|Bỏ qua') {
    Write-Host 'Nhắc lại: Windows 10/11 không cho script tự đặt trình duyệt mặc định.' -ForegroundColor DarkGray
    Write-Host 'Hãy chọn Chrome trong cửa sổ Default apps vừa mở để hoàn tất.' -ForegroundColor DarkGray
}
if (@($statuses | Where-Object { $_.App.Key -eq 'Office' -and -not $_.Status.Installed }).Count -gt 0 -and -not $SkipOffice) {
    Write-Host 'Office cần đăng nhập tài khoản Microsoft 365 để kích hoạt sau khi cài.' -ForegroundColor DarkGray
}
if ($logPath) {
    Write-Host ''
    Write-Host "Log: $logPath" -ForegroundColor Cyan
}

try { Stop-Transcript | Out-Null } catch { }

if ($Host.Name -eq 'ConsoleHost') {
    Write-Host ''
    [void](Read-Host 'Nhấn Enter để đóng...')
}
