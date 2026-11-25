#Requires -Version 5.1
<#
.SYNOPSIS
    Kiểm tra toàn diện máy tính mới và xuất báo cáo Markdown + HTML.

.DESCRIPTION
    Script thu thập thông tin hệ thống, phần cứng, pin, ổ cứng, màn hình, mạng,
    bảo mật, phần mềm... Mặc định kiểm tra tay loa (1 tiếng bíp ngắn), mic,
    camera và bàn phím. Dùng -FullManual để bật thêm các bài test màn hình,
    cảm ứng, touchpad, sạc/pin, vân tay. Kết quả test tay được ghi lại và
    tổng hợp vào 2 file báo cáo: .md và .html.

.PARAMETER OutputFolder
    Thư mục chứa báo cáo. Mặc định: <thư mục script>\BaoCaoKiemTra

.PARAMETER Technician
    Tên kỹ thuật viên kiểm tra.

.PARAMETER Customer
    Tên khách hàng / mã đơn (không bắt buộc).

.PARAMETER SkipManual
    Bỏ qua phần kiểm tra tay, chỉ thu thập thông tin tự động và xuất báo cáo.

.PARAMETER FullManual
    Bật lại toàn bộ bài kiểm tra tay cũ (màn hình, cảm ứng, touchpad, bàn phím,
    micro, camera, sạc/pin, vân tay...). Mặc định chỉ test loa bằng 1 tiếng bíp.

.PARAMETER AllTests
    Vẫn chạy các bài test tay ngay cả khi không phát hiện phần cứng tương ứng.

.PARAMETER NoElevate
    Không hỏi chạy lại với quyền Administrator.

.PARAMETER NoOpen
    Không tự mở file HTML sau khi tạo báo cáo.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\KiemTraMayMoi.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\KiemTraMayMoi.ps1 -SkipManual -NoOpen

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\KiemTraMayMoi.ps1 -FullManual

.NOTES
    Nên chạy bằng quyền Administrator để đọc được TPM, SMART, BitLocker.
    Có thể double-click file ChayKiemTra.bat để tự chạy với quyền Administrator.
    Script không cài đặt hay thay đổi cấu hình máy.
#>

[CmdletBinding()]
param(
    [string]$OutputFolder = '',
    [string]$Technician = '',
    [string]$Customer = '',
    [switch]$SkipManual,
    [switch]$FullManual,
    [switch]$AllTests,
    [switch]$NoElevate,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Continue'
$script:Version = '1.0'
$script:StartedAt = Get-Date

# Đảm bảo hiển thị tiếng Việt đúng trong cửa sổ console.
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    [Console]::InputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
} catch { }
try { $null = & "$env:SystemRoot\System32\chcp.com" 65001 } catch { }

function Set-ConsoleFont {
    param([string]$FaceName = 'Consolas', [int16]$PreferSize = 16)
    try {
        if ($Host.Name -ne 'ConsoleHost') { return }
        if ([Console]::IsOutputRedirected) { return }

        $source = @"
using System;
using System.Runtime.InteropServices;

namespace KiemTraMayMoi {
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

        if (-not ('KiemTraMayMoi.ConsoleFont' -as [type])) {
            Add-Type -TypeDefinition $source
        }

        [void][KiemTraMayMoi.ConsoleFont]::SetConsoleOutputCP(65001)
        [void][KiemTraMayMoi.ConsoleFont]::SetConsoleCP(65001)

        $info = New-Object KiemTraMayMoi.ConsoleFont+CONSOLE_FONT_INFO_EX
        $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($info)
        $handle = [KiemTraMayMoi.ConsoleFont]::GetStdHandle(-11)
        if ([KiemTraMayMoi.ConsoleFont]::GetCurrentConsoleFontEx($handle, $false, [ref]$info)) {
            $sizeY = $PreferSize
            if ($info.dwFontSizeY -ge 14) { $sizeY = $info.dwFontSizeY }
            $info.FaceName = $FaceName
            $info.FontFamily = 54
            $info.FontWeight = 400
            $info.dwFontSizeX = 0
            $info.dwFontSizeY = $sizeY
            [void][KiemTraMayMoi.ConsoleFont]::SetCurrentConsoleFontEx($handle, $false, [ref]$info)
        }
    } catch { }
}

Set-ConsoleFont

try { $Host.UI.RawUI.WindowTitle = 'Kiểm tra máy mới' } catch { }

# =====================================================================
#  HÀM TIỆN ÍCH
# =====================================================================

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-CimData {
    param(
        [Parameter(Mandatory = $true)][string]$Class,
        [string]$Namespace = 'root/cimv2',
        [string]$Filter = ''
    )
    try {
        $params = @{
            ClassName   = $Class
            Namespace   = $Namespace
            ErrorAction = 'Stop'
        }
        if ($Filter) { $params['Filter'] = $Filter }
        return @(Get-CimInstance @params)
    } catch {
        return @()
    }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Format-Text {
    param($Value, [string]$Empty = '—')
    if ($null -eq $Value) { return $Empty }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $Empty }
        return $Value.Trim()
    }
    if ($Value -is [datetime]) { return $Value.ToString('dd/MM/yyyy HH:mm:ss') }
    if ($Value -is [bool]) { if ($Value) { return 'Có' } else { return 'Không' } }
    if ($Value -is [array]) {
        $parts = @($Value | Where-Object { $null -ne $_ -and "$_" -ne '' } | ForEach-Object { [string]$_ })
        if ($parts.Count -eq 0) { return $Empty }
        return ($parts -join '; ')
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Empty }
    return $text.Trim()
}

function Format-Size {
    param($Bytes)
    try { $value = [double]$Bytes } catch { return '—' }
    if ($value -le 0) { return '—' }
    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $index = 0
    while ($value -ge 1024 -and $index -lt ($units.Count - 1)) {
        $value = $value / 1024
        $index++
    }
    if ($index -ge 3) {
        return ('{0:N0} {1}' -f $value, $units[$index])
    }
    return ('{0:N1} {1}' -f $value, $units[$index])
}

function Format-Percent {
    param($Value, [int]$Decimals = 1)
    if ($null -eq $Value -or "$Value" -eq '') { return '—' }
    try {
        $format = '{0:N' + $Decimals + '}%'
        return ($format -f [double]$Value)
    } catch {
        return '—'
    }
}

function Format-DateValue {
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return '—' }
    try { return ([datetime]$Value).ToString('dd/MM/yyyy HH:mm') } catch { }
    try {
        return ([System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)).ToString('dd/MM/yyyy HH:mm')
    } catch { }
    return [string]$Value
}

function Format-Duration {
    param([TimeSpan]$Span)
    if ($Span.TotalDays -ge 1) {
        return ('{0} ngày {1} giờ {2} phút' -f [int]$Span.Days, $Span.Hours, $Span.Minutes)
    }
    if ($Span.TotalHours -ge 1) {
        return ('{0} giờ {1} phút' -f [int]$Span.TotalHours, $Span.Minutes)
    }
    return ('{0} phút' -f [int]$Span.TotalMinutes)
}

function Get-MemoryTypeName {
    param([int]$Code)
    switch ($Code) {
        20 { return 'DDR' }
        21 { return 'DDR2' }
        22 { return 'DDR2 FB-DIMM' }
        24 { return 'DDR3' }
        26 { return 'DDR4' }
        27 { return 'LPDDR' }
        28 { return 'LPDDR2' }
        29 { return 'LPDDR3' }
        30 { return 'LPDDR4' }
        34 { return 'DDR5' }
        35 { return 'LPDDR5' }
        default {
            if ($Code -gt 0) { return "Không rõ ($Code)" }
            return '—'
        }
    }
}

function Get-FormFactorName {
    param([int]$Code)
    switch ($Code) {
        8 { return 'DIMM' }
        12 { return 'SODIMM' }
        13 { return 'SRIMM' }
        11 { return 'RIMM' }
        9 { return 'TSOP' }
        default {
            if ($Code -gt 0) { return "Khác ($Code)" }
            return '—'
        }
    }
}

function Get-ChassisName {
    param([int]$Code)
    switch ($Code) {
        1 { return 'Other' }
        2 { return 'Unknown' }
        3 { return 'Desktop' }
        4 { return 'Low Profile Desktop' }
        5 { return 'Pizza Box' }
        6 { return 'Mini Tower' }
        7 { return 'Tower' }
        8 { return 'Portable' }
        9 { return 'Laptop' }
        10 { return 'Notebook' }
        11 { return 'Hand Held' }
        12 { return 'Docking Station' }
        13 { return 'All in One' }
        14 { return 'Sub Notebook' }
        15 { return 'Space-saving' }
        16 { return 'Lunch Box' }
        17 { return 'Main System Chassis' }
        18 { return 'Expansion Chassis' }
        19 { return 'Sub Chassis' }
        20 { return 'Bus Expansion Chassis' }
        21 { return 'Peripheral Chassis' }
        22 { return 'Storage Chassis' }
        23 { return 'Rack Mount' }
        24 { return 'Sealed Case' }
        30 { return 'Tablet' }
        31 { return 'Convertible' }
        32 { return 'Detachable' }
        35 { return 'Mini PC' }
        36 { return 'Stick PC' }
        default { return "Khác ($Code)" }
    }
}

function Get-BatteryChemistryName {
    param([int]$Code)
    switch ($Code) {
        1 { return 'Other' }
        2 { return 'Unknown' }
        3 { return 'Lead Acid' }
        4 { return 'Nickel Cadmium' }
        5 { return 'Nickel Metal Hydride' }
        6 { return 'Lithium-ion' }
        7 { return 'Zinc Air' }
        8 { return 'Lithium Polymer' }
        default { return "Không rõ ($Code)" }
    }
}

function Get-FirewallActionName {
    param($Action)
    switch ("$Action") {
        'Allow' { return 'Cho phép' }
        'Block' { return 'Chặn' }
        'NotConfigured' { return 'Theo mặc định' }
        default { return (Format-Text $Action) }
    }
}

function Get-FirewallStateName {
    param($Value)
    switch ("$Value") {
        'True' { return 'Có' }
        'False' { return 'Không' }
        'NotConfigured' { return 'Chưa cấu hình' }
        default { return (Format-Text $Value) }
    }
}

function Get-VbsStatusName {
    param([int]$Code)
    switch ($Code) {
        0 { return 'Tắt' }
        1 { return 'Bật nhưng chưa chạy' }
        2 { return 'Đang chạy' }
        3 { return 'Không xác định' }
        default { return "Không rõ ($Code)" }
    }
}

function Get-VbsServiceNames {
    param($Codes)
    if ($null -eq $Codes) { return '—' }
    $names = @()
    foreach ($code in @($Codes)) {
        switch ([int]$code) {
            1 { $names += 'Credential Guard' }
            2 { $names += 'HVCI / Memory Integrity' }
            3 { $names += 'System Guard Secure Launch' }
            4 { $names += 'SMM Firmware Measurement' }
            default { $names += "Dịch vụ $code" }
        }
    }
    if ($names.Count -eq 0) { return '—' }
    return ($names -join ', ')
}

function Get-BatteryStatusName {
    param([int]$Code)
    switch ($Code) {
        1 { return 'Khác' }
        2 { return 'Không xác định' }
        3 { return 'Đã sạc đầy' }
        4 { return 'Sắp hết pin' }
        5 { return 'Pin yếu' }
        6 { return 'Đang sạc' }
        7 { return 'Đang sạc (cao)' }
        8 { return 'Đang sạc (thấp)' }
        9 { return 'Đang sạc (rất thấp)' }
        10 { return 'Không xác định' }
        11 { return 'Sạc một phần' }
        default { return "Không rõ ($Code)" }
    }
}

function Get-LicenseStatusName {
    param([int]$Code)
    switch ($Code) {
        0 { return 'Chưa kích hoạt' }
        1 { return 'Đã kích hoạt' }
        2 { return 'Thời gian dùng thử (OOB)' }
        3 { return 'Hết thời gian dùng thử' }
        4 { return 'Không chính hãng (grace)' }
        5 { return 'Chế độ thông báo' }
        6 { return 'Gia hạn grace' }
        default { return "Không rõ ($Code)" }
    }
}

function Get-DeviceErrorName {
    param([int]$Code)
    switch ($Code) {
        1 { return 'Thiết bị chưa cấu hình đúng' }
        3 { return 'Driver hỏng hoặc thiếu bộ nhớ' }
        10 { return 'Không khởi động được' }
        12 { return 'Không đủ tài nguyên' }
        14 { return 'Cần khởi động lại máy' }
        18 { return 'Cần cài lại driver' }
        22 { return 'Thiết bị bị vô hiệu hóa' }
        24 { return 'Thiết bị không hiện diện' }
        28 { return 'Chưa cài driver' }
        31 { return 'Không tải được driver' }
        43 { return 'Thiết bị dừng do lỗi' }
        default { return "Mã lỗi $Code" }
    }
}

function ConvertFrom-MonitorBytes {
    param($Bytes)
    if ($null -eq $Bytes) { return '' }
    $chars = @()
    foreach ($b in @($Bytes)) {
        if ($b -ne 0) { $chars += [char]$b }
    }
    return (-join $chars).Trim()
}

function Get-DeviceNames {
    param($Devices)
    $names = @($Devices | Where-Object { $_.Name } | ForEach-Object { $_.Name } | Sort-Object -Unique)
    if ($names.Count -eq 0) { return 'Không phát hiện' }
    return ($names -join '; ')
}

function Get-AudioEndpoints {
    param([ValidateSet('Render', 'Capture')][string]$Flow)
    $root = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$Flow"
    $result = @()
    if (-not (Test-Path $root)) { return @() }
    foreach ($key in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
        $name = ''
        $state = $null
        try {
            $props = Get-ItemProperty -Path "$($key.PSPath)\Properties" -ErrorAction Stop
            $nameProp = $props.PSObject.Properties | Where-Object {
                $_.Name -like '*a45c254e-df1c-4efd-8020-67d146a850e0*' -and $_.Name -like '*,2'
            } | Select-Object -First 1
            if ($nameProp) { $name = [string]$nameProp.Value }
        } catch { }
        try { $state = (Get-ItemProperty -Path $key.PSPath -Name 'DeviceState' -ErrorAction Stop).DeviceState } catch { }
        if (-not $name) { $name = '(Không rõ tên)' }
        $stateText = switch ([int]$state) {
            1 { 'Đang hoạt động' }
            2 { 'Bị vô hiệu hóa' }
            4 { 'Không hiện diện' }
            8 { 'Chưa kết nối' }
            default { 'Không xác định' }
        }
        $result += [pscustomobject]@{
            Name      = $name
            State     = $stateText
            StateCode = $state
        }
    }
    return @($result | Sort-Object Name)
}

function Get-BestSerial {
    param($Candidates)
    foreach ($candidate in @($Candidates)) {
        if ($candidate -and "$candidate".Trim() -notmatch '^(To Be Filled|Default string|None|N/A|No Asset|0+$|\.+$|Unknown)') {
            return "$candidate".Trim()
        }
    }
    return ''
}

function Get-GpuMemoryBytes {
    param([string]$GpuName)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $found = $null
    try {
        foreach ($key in @(Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ($props -and $props.DriverDesc -eq $GpuName) {
                $mem = $props.'HardwareInformation.qwMemorySize'
                if ($mem) { $found = $mem }
            }
        }
    } catch { }
    return $found
}

function Get-InternalMonitorSummary {
    param($Monitors, $Sizes)
    $parts = @()
    foreach ($monitor in @($Monitors)) {
        if (-not $monitor.Active) { continue }
        $name = ConvertFrom-MonitorBytes $monitor.UserFriendlyName
        if (-not $name) { $name = ConvertFrom-MonitorBytes $monitor.ManufacturerName }
        $sizeInfo = @($Sizes | Where-Object { $_.InstanceName -eq $monitor.InstanceName }) | Select-Object -First 1
        $sizeText = ''
        if ($sizeInfo) {
            try {
                $diag = [math]::Sqrt([double]$sizeInfo.MaxHorizontalImageSize * [double]$sizeInfo.MaxHorizontalImageSize + [double]$sizeInfo.MaxVerticalImageSize * [double]$sizeInfo.MaxVerticalImageSize) / 2.54
                if ($diag -gt 5 -and $diag -lt 60) { $sizeText = ('{0:N1}"' -f $diag) }
            } catch { }
        }
        $label = (@($name, $sizeText) | Where-Object { $_ }) -join ' '
        if ($label) { $parts += $label.Trim() }
    }
    return ($parts -join '; ')
}

# =====================================================================
#  MÔ HÌNH DỮ LIỆU BÁO CÁO
# =====================================================================

$script:Sections = New-Object System.Collections.ArrayList
$script:Warnings = New-Object System.Collections.ArrayList
$script:Attachments = New-Object System.Collections.ArrayList

function New-Section {
    param([string]$Title)
    $section = [pscustomobject]@{
        Title  = $Title
        Info   = [ordered]@{}
        Tables = New-Object System.Collections.ArrayList
    }
    [void]$script:Sections.Add($section)
    return $section
}

function Add-Info {
    param($Section, [string]$Key, $Value)
    $Section.Info[$Key] = $Value
}

function Add-Table {
    param($Section, [string]$Title, [string[]]$Columns, $Rows)
    [void]$Section.Tables.Add([pscustomobject]@{
        Title   = $Title
        Columns = $Columns
        Rows    = @($Rows)
    })
}

function Add-Warning {
    param([string]$Level, [string]$Text)
    [void]$script:Warnings.Add([pscustomobject]@{ Level = $Level; Text = $Text })
}

function Add-Attachment {
    param([string]$Label, [string]$File)
    if ($File) {
        [void]$script:Attachments.Add([pscustomobject]@{ Label = $Label; File = $File })
    }
}

function ConvertTo-HtmlText {
    param($Value)
    $text = Format-Text $Value
    $text = $text.Replace('&', '&amp;')
    $text = $text.Replace('<', '&lt;')
    $text = $text.Replace('>', '&gt;')
    $text = $text.Replace('"', '&quot;')
    $text = $text.Replace("'", '&#39;')
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`n", '<br>'
    return $text
}

function ConvertTo-MdCell {
    param($Value)
    $text = Format-Text $Value
    $text = $text.Replace('<', '&lt;').Replace('>', '&gt;')
    $text = $text.Replace('|', '\|')
    $text = $text -replace "`r`n", '<br>'
    $text = $text -replace "`n", '<br>'
    return $text
}

# =====================================================================
#  KHỞI ĐỘNG / QUYỀN ADMIN / THÔNG TIN BUỔI KIỂM TRA
# =====================================================================

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '                    KIỂM TRA MÁY MỚI  -  v1.0' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '     Thu thập thông tin + kiểm tra loa + xuất báo cáo MD/HTML' -ForegroundColor DarkGray
Write-Host ''

$script:IsAdmin = Test-IsAdmin

# Tự đề nghị chạy lại với quyền Administrator (bỏ qua khi -SkipManual / -NoElevate).
if ((-not $script:IsAdmin) -and (-not $NoElevate) -and (-not $SkipManual) -and $PSCommandPath) {
    Write-Host 'Bạn đang chạy KHÔNG có quyền Administrator.' -ForegroundColor Yellow
    Write-Host 'Một số thông tin như TPM, SMART, BitLocker có thể không đọc được.' -ForegroundColor Yellow
    $answer = Read-Host 'Chạy lại với quyền Administrator? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
        $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($OutputFolder) {
            $resolvedOutput = $OutputFolder
            try {
                if (-not [System.IO.Path]::IsPathRooted($resolvedOutput)) {
                    $resolvedOutput = Join-Path (Get-Location).Path $resolvedOutput
                }
                $resolvedOutput = [System.IO.Path]::GetFullPath($resolvedOutput)
            } catch { }
            $argString += " -OutputFolder `"$resolvedOutput`""
        }
        if ($SkipManual) { $argString += ' -SkipManual' }
        if ($FullManual) { $argString += ' -FullManual' }
        if ($AllTests) { $argString += ' -AllTests' }
        if ($NoElevate) { $argString += ' -NoElevate' }
        if ($NoOpen) { $argString += ' -NoOpen' }
        if ($Technician) { $argString += " -Technician `"$Technician`"" }
        if ($Customer) { $argString += " -Customer `"$Customer`"" }
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argString -ErrorAction Stop
            exit
        } catch {
            Write-Warning "Không thể nâng quyền: $($_.Exception.Message)"
            Write-Host 'Tiếp tục chạy với quyền hiện tại...' -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
}

if (-not $Technician) {
    if ($SkipManual) {
        $Technician = $env:USERNAME
    } else {
        $inputTech = Read-Host "Kỹ thuật viên (Enter = $env:USERNAME)"
        if ([string]::IsNullOrWhiteSpace($inputTech)) { $Technician = $env:USERNAME } else { $Technician = $inputTech.Trim() }
    }
}

if (-not $Customer -and -not $SkipManual) {
    $Customer = (Read-Host 'Khách hàng / mã đơn (Enter = bỏ qua)').Trim()
}

$script:ComputerName = $env:COMPUTERNAME
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not $OutputFolder) {
    $baseFolder = $PSScriptRoot
    if (-not $baseFolder) { $baseFolder = (Get-Location).Path }
    $OutputFolder = Join-Path $baseFolder 'BaoCaoKiemTra'
}

$script:ReportDir = Join-Path $OutputFolder "$script:ComputerName`_$stamp"
try {
    if (-not (Test-Path $script:ReportDir)) {
        New-Item -ItemType Directory -Path $script:ReportDir -Force -ErrorAction Stop | Out-Null
    }
} catch {
    $fallbackBase = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'BaoCaoKiemTra'
    $script:ReportDir = Join-Path $fallbackBase "$script:ComputerName`_$stamp"
    New-Item -ItemType Directory -Path $script:ReportDir -Force | Out-Null
}

$script:AssetsDir = Join-Path $script:ReportDir 'assets'
if (-not (Test-Path $script:AssetsDir)) {
    New-Item -ItemType Directory -Path $script:AssetsDir -Force | Out-Null
}

Write-Host "Máy: $script:ComputerName" -ForegroundColor White
Write-Host "Kỹ thuật viên: $Technician" -ForegroundColor White
Write-Host "Quyền Administrator: $(if ($script:IsAdmin) { 'Có' } else { 'Không' })" -ForegroundColor $(if ($script:IsAdmin) { 'Green' } else { 'Yellow' })
Write-Host "Thư mục báo cáo: $script:ReportDir" -ForegroundColor DarkGray

# =====================================================================
#  THU THẬP DỮ LIỆU
# =====================================================================

Write-Host ''
Write-Host '[1/15] Đang đọc thông tin hệ thống...' -ForegroundColor Cyan

$cs = @(Get-CimData 'Win32_ComputerSystem') | Select-Object -First 1
$csp = @(Get-CimData 'Win32_ComputerSystemProduct') | Select-Object -First 1
$os = @(Get-CimData 'Win32_OperatingSystem') | Select-Object -First 1
$bios = @(Get-CimData 'Win32_BIOS') | Select-Object -First 1
$board = @(Get-CimData 'Win32_BaseBoard') | Select-Object -First 1
$enclosure = @(Get-CimData 'Win32_SystemEnclosure') | Select-Object -First 1
$winReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue

$chassisCode = 0
if ($enclosure -and $enclosure.ChassisTypes) {
    try { $chassisCode = [int](@($enclosure.ChassisTypes)[0]) } catch { }
}
$chassisName = Get-ChassisName $chassisCode
$isLaptop = $chassisCode -in @(8, 9, 10, 11, 14, 30, 31, 32)

$serial = Get-BestSerial @(
    $csp.IdentifyingNumber,
    $enclosure.SerialNumber,
    $bios.SerialNumber,
    $cs.SerialNumber
)
if (-not $serial) { $serial = '—' }

$model = ("$($cs.Manufacturer) $($cs.Model)").Trim()
$model = $model -replace '\s+', ' '
if (-not $model) { $model = '—' }

$osCaption = Format-Text $os.Caption
$build = if ($winReg.CurrentBuild) { $winReg.CurrentBuild } else { $os.BuildNumber }
$ubr = $winReg.UBR
$buildFull = "$build"
if ($ubr) { $buildFull = "$build.$ubr" }
$displayVersion = if ($winReg.DisplayVersion) { $winReg.DisplayVersion } else { '' }

$uptime = $null
if ($os.LastBootUpTime) { $uptime = (Get-Date) - [datetime]$os.LastBootUpTime }

$activation = @(Get-CimData 'SoftwareLicensingProduct' -Filter "PartialProductKey IS NOT NULL AND LicenseIsAddon=FALSE AND Name LIKE 'Windows%'") | Select-Object -First 1
$licenseCode = -1
if ($activation) {
    try { $licenseCode = [int]$activation.LicenseStatus } catch { }
}
$licenseText = Get-LicenseStatusName $licenseCode
$productKeyChannel = if ($activation) { Format-Text $activation.ProductKeyChannel } else { '—' }

$secureBootStatus = 'Không xác định'
$sbReg = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
if ($null -ne $sbReg) {
    if ([int]$sbReg -eq 1) { $secureBootStatus = 'Bật' } else { $secureBootStatus = 'Tắt' }
} else {
    try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) { $secureBootStatus = 'Bật' } else { $secureBootStatus = 'Tắt' }
    } catch {
        $secureBootStatus = 'Không hỗ trợ / BIOS Legacy'
    }
}

$summaryModel = $model
$summarySerial = $serial
$secOverview = New-Section 'Tổng quan máy'
Add-Info $secOverview 'Tên máy' $script:ComputerName
Add-Info $secOverview 'Hãng / Model' $model
Add-Info $secOverview 'Số serial' $serial
Add-Info $secOverview 'Mã sản phẩm (SKU)' $cs.SystemSKUNumber
Add-Info $secOverview 'Dòng máy' $cs.SystemFamily
Add-Info $secOverview 'Loại máy (chassis)' "$chassisName (code $chassisCode)"
Add-Info $secOverview 'UUID' $csp.UUID
Add-Info $secOverview 'Bo mạch chủ' (("$($board.Manufacturer) $($board.Product)").Trim())
Add-Info $secOverview 'Serial bo mạch' $board.SerialNumber
Add-Info $secOverview 'BIOS' (("$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)").Trim())
Add-Info $secOverview 'Ngày BIOS' (Format-DateValue $bios.ReleaseDate)
Add-Info $secOverview 'Phiên bản SMBIOS' (("$($bios.SMBIOSMajorVersion).$($bios.SMBIOSMinorVersion)").Trim('.'))
Add-Info $secOverview 'Hệ điều hành' $osCaption
Add-Info $secOverview 'Phiên bản Windows' "$displayVersion (build $buildFull)"
Add-Info $secOverview 'Kiến trúc' $os.OSArchitecture
Add-Info $secOverview 'Ngày cài Windows' (Format-DateValue $os.InstallDate)
Add-Info $secOverview 'Khởi động cuối' (Format-DateValue $os.LastBootUpTime)
Add-Info $secOverview 'Thời gian hoạt động' (Format-Duration $uptime)
Add-Info $secOverview 'Kích hoạt Windows' "$licenseText (kênh: $productKeyChannel)"
Add-Info $secOverview 'Product ID' $os.SerialNumber
Add-Info $secOverview 'Người dùng hiện tại' "$env:USERDOMAIN\$env:USERNAME"
Add-Info $secOverview 'Tên miền / Workgroup' $cs.Domain
Add-Info $secOverview 'Múi giờ' (Get-TimeZone).DisplayName
Add-Info $secOverview 'Ngôn ngữ hệ thống' (Get-Culture).DisplayName
Add-Info $secOverview 'Quyền Administrator' $(if ($script:IsAdmin) { 'Có' } else { 'Không' })
Add-Info $secOverview 'Khởi động an toàn (Secure Boot)' $secureBootStatus

if ($licenseCode -ne 1) {
    Add-Warning 'Cao' "Windows chưa được kích hoạt hoặc không xác định được trạng thái bản quyền ($licenseText)."
}

# ---------------------------------------------------------------------
Write-Host '[2/15] Đang đọc thông tin CPU...' -ForegroundColor Cyan
$cpus = @(Get-CimData 'Win32_Processor')
$cpu = $cpus | Select-Object -First 1
$cpuName = if ($cpu) { $cpu.Name } else { '—' }
$cpuShort = ($cpuName -replace '\(R\)', '' -replace '\(TM\)', '' -replace 'CPU\s*', '' -replace '\s+', ' ').Trim()

$secCpu = New-Section 'CPU'
if ($cpu) {
    Add-Info $secCpu 'Tên CPU' $cpuName
    Add-Info $secCpu 'Hãng' $cpu.Manufacturer
    Add-Info $secCpu 'Số nhân vật lý' $cpu.NumberOfCores
    Add-Info $secCpu 'Số luồng' $cpu.NumberOfLogicalProcessors
    Add-Info $secCpu 'Xung nhịp tối đa' "$($cpu.MaxClockSpeed) MHz"
    Add-Info $secCpu 'Socket' $cpu.SocketDesignation
    Add-Info $secCpu 'L2 Cache' (Format-Size ([double]$cpu.L2CacheSize * 1KB))
    Add-Info $secCpu 'L3 Cache' (Format-Size ([double]$cpu.L3CacheSize * 1KB))
    Add-Info $secCpu 'Kiến trúc' $(if ($cpu.AddressWidth -eq 64) { '64-bit' } else { "$($cpu.AddressWidth)-bit" })
    Add-Info $secCpu 'ID vi xử lý' $cpu.ProcessorId
    Add-Info $secCpu 'Ảo hóa phần cứng' $cpu.VirtualizationFirmwareEnabled
    Add-Info $secCpu 'Hypervisor đang bật' $cs.HypervisorPresent
    Add-Info $secCpu 'Số CPU vật lý' $cs.NumberOfProcessors
} else {
    Add-Info $secCpu 'Tên CPU' 'Không đọc được'
}
$summaryCpu = $cpuShort

# ---------------------------------------------------------------------
Write-Host '[3/15] Đang đọc bộ nhớ RAM...' -ForegroundColor Cyan
$ramModules = @(Get-CimData 'Win32_PhysicalMemory')
$memArray = @(Get-CimData 'Win32_PhysicalMemoryArray') | Select-Object -First 1
$ramTotal = $cs.TotalPhysicalMemory
if (-not $ramTotal -and $os) { $ramTotal = [double]$os.TotalVisibleMemorySize * 1KB }
$ramSpeed = ($ramModules | Where-Object { $_.ConfiguredClockSpeed } | Select-Object -First 1).ConfiguredClockSpeed

$secRam = New-Section 'Bộ nhớ RAM'
Add-Info $secRam 'Tổng dung lượng' (Format-Size $ramTotal)
Add-Info $secRam 'Dung lượng Windows thấy' (Format-Size ([double]$os.TotalVisibleMemorySize * 1KB))
Add-Info $secRam 'RAM còn trống' (Format-Size ([double]$os.FreePhysicalMemory * 1KB))
if ($memArray) {
    Add-Info $secRam 'Tổng số khe RAM' $memArray.MemoryDevices
    $maxRam = $memArray.MaxCapacityEx
    if (-not $maxRam) { $maxRam = $memArray.MaxCapacity }
    Add-Info $secRam 'Dung lượng tối đa hỗ trợ' (Format-Size ([double]$maxRam * 1KB))
}
Add-Info $secRam 'Số module đang gắn' $ramModules.Count
if ($memArray) {
    Add-Info $secRam 'Số khe RAM còn trống' ([Math]::Max(0, [int]$memArray.MemoryDevices - $ramModules.Count))
}
Add-Info $secRam 'Tốc độ' $(if ($ramSpeed) { "$ramSpeed MHz" } else { '—' })

$ramRows = @()
foreach ($module in $ramModules) {
    $ramRows += , @(
        (Format-Text $module.DeviceLocator),
        (Format-Size $module.Capacity),
        $(if ($module.ConfiguredClockSpeed) { "$($module.ConfiguredClockSpeed) MHz" } else { "$($module.Speed) MHz" }),
        (Get-MemoryTypeName ([int]$module.SMBIOSMemoryType)),
        (Get-FormFactorName ([int]$module.FormFactor)),
        (Format-Text $module.Manufacturer),
        (Format-Text $module.PartNumber),
        (Format-Text $module.SerialNumber),
        $(if ($module.ConfiguredVoltage) { ('{0:N2} V' -f ([double]$module.ConfiguredVoltage / 1000)) } else { '—' })
    )
}
if ($ramRows.Count -gt 0) {
    Add-Table $secRam 'Chi tiết từng module' @('Khe', 'Dung lượng', 'Tốc độ', 'Loại', 'Form factor', 'Hãng', 'Part number', 'Serial', 'Điện áp') $ramRows
}

$summaryRam = (Format-Size $ramTotal)
if ($ramSpeed) { $summaryRam += " $ramSpeed MHz" }

if ($ramTotal -gt 0 -and $ramTotal -lt 8GB) {
    Add-Warning 'Trung bình' "Dung lượng RAM chỉ $(Format-Size $ramTotal), có thể không đủ cho nhu cầu văn phòng/đa nhiệm."
}

# ---------------------------------------------------------------------
Write-Host '[4/15] Đang đọc ổ cứng và tình trạng SMART...' -ForegroundColor Cyan
$physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
$disks = @(Get-Disk -ErrorAction SilentlyContinue)
$diskDrives = @(Get-CimData 'Win32_DiskDrive')
$volumes = @(Get-CimData 'Win32_LogicalDisk' -Filter 'DriveType=3')

$secStorage = New-Section 'Ổ cứng & lưu trữ'
if ($physicalDisks.Count -gt 0) {
    $diskRows = @()
    foreach ($pd in $physicalDisks) {
        $partitionStyle = '—'
        $matchingDisk = @($disks | Where-Object { "$($_.Number)" -eq "$($pd.DeviceId)" }) | Select-Object -First 1
        if ($matchingDisk) { $partitionStyle = [string]$matchingDisk.PartitionStyle }
        $media = $pd.MediaType
        if (-not $media) { if ("$($pd.BusType)" -eq 'NVMe') { $media = 'SSD' } else { $media = '—' } }
        $diskRows += , @(
            "$($pd.DeviceId)",
            (Format-Text $pd.FriendlyName),
            (Format-Text $media),
            (Format-Text $pd.BusType),
            (Format-Size $pd.Size),
            (Format-Text $pd.HealthStatus),
            (Format-Text $pd.OperationalStatus),
            (Format-Text $pd.FirmwareVersion),
            (Format-Text $pd.SerialNumber),
            $partitionStyle
        )
    }
    Add-Table $secStorage 'Ổ cứng vật lý' @('#', 'Model', 'Loại', 'Bus', 'Dung lượng', 'Sức khỏe', 'Trạng thái', 'Firmware', 'Serial', 'Partition') $diskRows
} else {
    $diskRows = @()
    $index = 0
    foreach ($drive in $diskDrives) {
        $diskRows += , @(
            "$index",
            (Format-Text $drive.Model),
            (Format-Text $drive.MediaType),
            (Format-Text $drive.InterfaceType),
            (Format-Size $drive.Size),
            (Format-Text $drive.Status),
            '—',
            (Format-Text $drive.FirmwareRevision),
            (Format-Text $drive.SerialNumber),
            '—'
        )
        $index++
    }
    if ($diskRows.Count -gt 0) {
        Add-Table $secStorage 'Ổ cứng vật lý' @('#', 'Model', 'Loại', 'Bus', 'Dung lượng', 'Sức khỏe', 'Trạng thái', 'Firmware', 'Serial', 'Partition') $diskRows
    }
}

# SMART / reliability (thường cần quyền Administrator)
$smartRows = @()
$smartError = ''
$maxPowerOnHours = 0
$maxWear = -1
foreach ($pd in $physicalDisks) {
    try {
        $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop
        if ($rel) {
            $wear = $rel.Wear
            $powerOn = $rel.PowerOnHours
            if ($null -ne $wear -and [double]$wear -gt $maxWear) { $maxWear = [double]$wear }
            if ($null -ne $powerOn -and [double]$powerOn -gt $maxPowerOnHours) { $maxPowerOnHours = [double]$powerOn }
            $smartRows += , @(
                (Format-Text $pd.FriendlyName),
                $(if ($null -ne $rel.Temperature -and $rel.Temperature -gt 0) { "$($rel.Temperature) °C" } else { '—' }),
                $(if ($null -ne $wear) { "$wear%" } else { '—' }),
                $(if ($null -ne $powerOn) { "$powerOn giờ" } else { '—' }),
                (Format-Text $rel.ReadErrorsTotal),
                (Format-Text $rel.WriteErrorsTotal),
                (Format-Text $rel.StartStopCycleCount),
                (Format-Text $rel.LoadUnloadCycleCount)
            )
        }
    } catch {
        if (-not $smartError) { $smartError = $_.Exception.Message }
    }
}
if ($smartRows.Count -gt 0) {
    Add-Table $secStorage 'Sức khỏe SMART / độ bền' @('Ổ', 'Nhiệt độ', 'Độ mòn', 'Giờ hoạt động', 'Lỗi đọc', 'Lỗi ghi', 'Chu kỳ bật/tắt', 'Chu kỳ load/unload') $smartRows
}
if ($smartError) {
    Add-Info $secStorage 'Chi tiết SMART' "Không đọc được ($smartError). Thường cần quyền Administrator hoặc ổ không hỗ trợ."
}

$volumeRows = @()
foreach ($vol in $volumes) {
    $freePercent = '—'
    $free = [double]$vol.FreeSpace
    $size = [double]$vol.Size
    if ($size -gt 0) { $freePercent = Format-Percent (($free / $size) * 100) }
    $volumeRows += , @(
        (Format-Text $vol.DeviceID),
        (Format-Text $vol.VolumeName),
        (Format-Text $vol.FileSystem),
        (Format-Size $size),
        (Format-Size $free),
        $freePercent
    )
    if ($size -gt 0) {
        $pct = ($free / $size) * 100
        if ($pct -lt 10) {
            Add-Warning 'Cao' "Ổ $($vol.DeviceID) chỉ còn $(Format-Size $free) ($(Format-Percent $pct)), rất thấp."
        } elseif ($pct -lt 20) {
            Add-Warning 'Trung bình' "Ổ $($vol.DeviceID) chỉ còn $(Format-Percent $pct) dung lượng trống."
        }
    }
}
if ($volumeRows.Count -gt 0) {
    Add-Table $secStorage 'Phân vùng / ổ đĩa logic' @('Ổ', 'Nhãn', 'File system', 'Dung lượng', 'Còn trống', '% trống') $volumeRows
}

$storageSummary = '—'
if ($physicalDisks.Count -gt 0) {
    $firstDisk = $physicalDisks[0]
    $storageSummary = "$($firstDisk.FriendlyName) ($(Format-Size $firstDisk.Size))"
} elseif ($diskDrives.Count -gt 0) {
    $storageSummary = "$($diskDrives[0].Model) ($(Format-Size $diskDrives[0].Size))"
}

foreach ($pd in $physicalDisks) {
    if ("$($pd.HealthStatus)" -and "$($pd.HealthStatus)" -notin @('Healthy', 'Unknown')) {
        Add-Warning 'Cao' "Ổ $($pd.FriendlyName) có trạng thái sức khỏe: $($pd.HealthStatus)."
    }
}
if ($maxWear -ge 80) {
    Add-Warning 'Cao' "Độ mòn ổ SSD đã ở mức $maxWear%, cần theo dõi hoặc thay ổ."
} elseif ($maxWear -ge 50) {
    Add-Warning 'Trung bình' "Độ mòn ổ SSD ở mức $maxWear%."
}
if ($maxPowerOnHours -gt 1000) {
    Add-Warning 'Cao' "Ổ cứng đã hoạt động $maxPowerOnHours giờ, có dấu hiệu máy đã được sử dụng nhiều."
} elseif ($maxPowerOnHours -gt 300) {
    Add-Warning 'Trung bình' "Ổ cứng đã hoạt động $maxPowerOnHours giờ, nên kiểm tra nguồn gốc máy."
}

# ---------------------------------------------------------------------
Write-Host '[5/15] Đang đọc GPU và màn hình...' -ForegroundColor Cyan
$gpus = @(Get-CimData 'Win32_VideoController')
$monitors = @(Get-CimData 'WmiMonitorID' -Namespace 'root/wmi')
$monitorSizes = @(Get-CimData 'WmiMonitorBasicDisplayParams' -Namespace 'root/wmi')

$secDisplay = New-Section 'GPU & màn hình'
$gpuRows = @()
foreach ($gpu in $gpus) {
    $vram = Get-GpuMemoryBytes $gpu.Name
    if (-not $vram) { $vram = $gpu.AdapterRAM }
    $resolution = '—'
    if ($gpu.CurrentHorizontalResolution -and $gpu.CurrentVerticalResolution) {
        $resolution = "$($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution)"
        if ($gpu.CurrentRefreshRate) { $resolution += " @ $($gpu.CurrentRefreshRate) Hz" }
    }
    $gpuRows += , @(
        (Format-Text $gpu.Name),
        (Format-Size $vram),
        (Format-Text $gpu.DriverVersion),
        (Format-DateValue $gpu.DriverDate),
        $resolution,
        (Format-Text $gpu.Status)
    )
}
if ($gpuRows.Count -gt 0) {
    Add-Table $secDisplay 'Bộ xử lý đồ họa' @('GPU', 'VRAM', 'Driver', 'Ngày driver', 'Độ phân giải hiện tại', 'Trạng thái') $gpuRows
}
$gpuSummary = if ($gpus.Count -gt 0) { $gpus[0].Name } else { '—' }

$monitorRows = @()
foreach ($monitor in $monitors) {
    $sizeInfo = @($monitorSizes | Where-Object { $_.InstanceName -eq $monitor.InstanceName }) | Select-Object -First 1
    $diag = '—'
    if ($sizeInfo) {
        try {
            $inch = [math]::Sqrt([double]$sizeInfo.MaxHorizontalImageSize * [double]$sizeInfo.MaxHorizontalImageSize + [double]$sizeInfo.MaxVerticalImageSize * [double]$sizeInfo.MaxVerticalImageSize) / 2.54
            if ($inch -gt 5 -and $inch -lt 60) { $diag = ('{0:N1} inch' -f $inch) }
        } catch { }
    }
    $made = '—'
    if ($monitor.YearOfManufacture) {
        $made = "$($monitor.YearOfManufacture)"
        if ($monitor.WeekOfManufacture -gt 0) { $made += " (tuần $($monitor.WeekOfManufacture))" }
    }
    $monitorRows += , @(
        (Format-Text (ConvertFrom-MonitorBytes $monitor.ManufacturerName)),
        (Format-Text (ConvertFrom-MonitorBytes $monitor.UserFriendlyName)),
        (Format-Text (ConvertFrom-MonitorBytes $monitor.SerialNumberID)),
        $diag,
        $made,
        (Format-Text $monitor.InstanceName)
    )
}
if ($monitorRows.Count -gt 0) {
    Add-Table $secDisplay 'Màn hình (EDID)' @('Hãng', 'Model', 'Serial', 'Kích thước', 'Năm sản xuất', 'Instance') $monitorRows
}

$monitorSummary = Get-InternalMonitorSummary $monitors $monitorSizes
$resolutionSummary = ''
if ($gpus.Count -gt 0) {
    $gpu0 = $gpus[0]
    if ($gpu0.CurrentHorizontalResolution -and $gpu0.CurrentVerticalResolution) {
        $resolutionSummary = "$($gpu0.CurrentHorizontalResolution)x$($gpu0.CurrentVerticalResolution)"
        if ($gpu0.CurrentRefreshRate) { $resolutionSummary += "@$($gpu0.CurrentRefreshRate)Hz" }
    }
}
$displaySummary = (@($monitorSummary, $resolutionSummary) | Where-Object { $_ }) -join ' • '
if (-not $displaySummary) { $displaySummary = $resolutionSummary }
if (-not $displaySummary) { $displaySummary = '—' }

# ---------------------------------------------------------------------
Write-Host '[6/15] Đang đọc pin, sạc và nguồn...' -ForegroundColor Cyan
$battery = @(Get-CimData 'Win32_Battery') | Select-Object -First 1
$batteryStatic = @(Get-CimData 'BatteryStaticData' -Namespace 'root/wmi') | Select-Object -First 1
$batteryFull = @(Get-CimData 'BatteryFullChargedCapacity' -Namespace 'root/wmi') | Select-Object -First 1
$batteryCycles = @(Get-CimData 'BatteryCycleCount' -Namespace 'root/wmi') | Select-Object -First 1
$batteryStatus = @(Get-CimData 'BatteryStatus' -Namespace 'root/wmi') | Select-Object -First 1

$secBattery = New-Section 'Pin & nguồn'
$batteryReportFile = 'pin-chi-tiet.html'
$batteryReportPath = Join-Path $script:ReportDir $batteryReportFile
$hasBattery = [bool]$battery

$designCapacity = $null
$fullCapacity = $null
$cycleCount = $null

if ($batteryStatic) { $designCapacity = $batteryStatic.DesignedCapacity }
if ($batteryFull) { $fullCapacity = $batteryFull.FullChargedCapacity }
if ($batteryCycles) { $cycleCount = $batteryCycles.CycleCount }

if ($hasBattery) {
    $pcfgOutput = $null
    try {
        $pcfgOutput = & powercfg.exe /batteryreport /output $batteryReportPath /duration 14 2>&1
    } catch { }
    $batteryManufacturer = if ($batteryStatic) { $batteryStatic.ManufacturerName } else { '' }
    $batterySerial = if ($batteryStatic) { $batteryStatic.SerialNumber } else { '' }
    $batteryChemistry = ''
    if (Test-Path $batteryReportPath) {
        Add-Attachment 'Báo cáo pin chi tiết (powercfg /batteryreport)' $batteryReportFile
        try {
            $reportHtml = Get-Content -Path $batteryReportPath -Raw -Encoding UTF8 -ErrorAction Stop
            if (-not $designCapacity -and $reportHtml -match '(?s)DESIGN CAPACITY.{0,400}?<td>\s*([\d\.,]+)\s*mWh') {
                $designCapacity = [double](($matches[1] -replace '\D', ''))
            }
            if (-not $fullCapacity -and $reportHtml -match '(?s)FULL CHARGE CAPACITY.{0,400}?<td>\s*([\d\.,]+)\s*mWh') {
                $fullCapacity = [double](($matches[1] -replace '\D', ''))
            }
            if (-not $batteryManufacturer -and $reportHtml -match '(?s)MANUFACTURER</span></td><td>\s*([^<]+)') {
                $batteryManufacturer = $matches[1].Trim()
            }
            if (-not $batterySerial -and $reportHtml -match '(?s)SERIAL NUMBER</span></td><td>\s*([^<]+)') {
                $batterySerial = $matches[1].Trim()
            }
            if (-not $batteryChemistry -and $reportHtml -match '(?s)CHEMISTRY</span></td><td>\s*([^<]+)') {
                $batteryChemistry = $matches[1].Trim()
            }
        } catch { }
    }

    if (-not $designCapacity -and $battery.DesignCapacity) { $designCapacity = $battery.DesignCapacity }
    if (-not $fullCapacity -and $battery.FullChargeCapacity) { $fullCapacity = $battery.FullChargeCapacity }

    Add-Info $secBattery 'Tên pin' $battery.Name
    Add-Info $secBattery 'Nhà sản xuất' $(if ($batteryManufacturer) { $batteryManufacturer } else { '—' })
    Add-Info $secBattery 'Serial pin' $(if ($batterySerial) { $batterySerial } else { '—' })
    Add-Info $secBattery 'Loại pin' $(if ($batteryChemistry) { $batteryChemistry } elseif ([int]$battery.Chemistry -ne 2) { Get-BatteryChemistryName ([int]$battery.Chemistry) } else { 'Không xác định' })
    Add-Info $secBattery 'Dung lượng thiết kế' $(if ($designCapacity) { "$(Format-Text $designCapacity) mWh" } else { '—' })
    Add-Info $secBattery 'Dung lượng sạc đầy' $(if ($fullCapacity) { "$(Format-Text $fullCapacity) mWh" } else { '—' })
    Add-Info $secBattery 'Số chu kỳ sạc' $(if ($null -ne $cycleCount) { $cycleCount } else { '—' })
    Add-Info $secBattery 'Mức pin hiện tại' "$($battery.EstimatedChargeRemaining)%"
    $batteryStateText = Get-BatteryStatusName ([int]$battery.BatteryStatus)
    if ($batteryStatus -and (([int]$battery.BatteryStatus -in @(2, 10)) -or $batteryStateText -like 'Không*')) {
        if ($batteryStatus.PowerOnline -and $batteryStatus.Charging) { $batteryStateText = 'Đang cắm sạc, đang sạc' }
        elseif ($batteryStatus.PowerOnline) { $batteryStateText = 'Đang cắm sạc (không sạc)' }
        elseif ($batteryStatus.Discharging) { $batteryStateText = 'Đang dùng pin' }
    }
    Add-Info $secBattery 'Trạng thái pin' $batteryStateText
    Add-Info $secBattery 'Điện áp thiết kế' $(if ($battery.DesignVoltage) { "$($battery.DesignVoltage) mV" } else { '—' })
    if ($batteryStatus) {
        Add-Info $secBattery 'Đang cắm sạc' $batteryStatus.PowerOnline
        Add-Info $secBattery 'Đang sạc' $batteryStatus.Charging
        Add-Info $secBattery 'Dung lượng còn lại (WMI)' "$($batteryStatus.RemainingCapacity) mWh"
        Add-Info $secBattery 'Điện áp hiện tại' "$($batteryStatus.Voltage) mV"
    }

    $health = $null
    if ($designCapacity -and $fullCapacity -and [double]$designCapacity -gt 0) {
        $health = ([double]$fullCapacity / [double]$designCapacity) * 100
        Add-Info $secBattery 'Sức khỏe pin' "$(Format-Percent $health) ($(Format-Text $fullCapacity) / $(Format-Text $designCapacity) mWh)"
        if ($health -lt 80) {
            Add-Warning 'Cao' "Sức khỏe pin chỉ còn $(Format-Percent $health) (dưới 80%)."
        } elseif ($health -lt 90) {
            Add-Warning 'Thấp' "Sức khỏe pin còn $(Format-Percent $health), nên theo dõi."
        }
    } else {
        Add-Info $secBattery 'Sức khỏe pin' 'Không đủ dữ liệu thiết kế/đầy'
    }

    if ($null -ne $cycleCount) {
        if ([int]$cycleCount -gt 300) {
            Add-Warning 'Cao' "Pin đã trải qua $cycleCount chu kỳ sạc, có dấu hiệu đã sử dụng nhiều."
        } elseif ([int]$cycleCount -gt 100) {
            Add-Warning 'Trung bình' "Pin đã trải qua $cycleCount chu kỳ sạc."
        }
    }

    $batterySummary = if ($health) { "$(Format-Percent $health) • $cycleCount chu kỳ" } else { "$($battery.EstimatedChargeRemaining)% • $cycleCount chu kỳ" }
} else {
    Add-Info $secBattery 'Pin' 'Không phát hiện pin (máy để bàn hoặc không đọc được).'
    $batterySummary = 'Không có pin'
}

$powerPlanGuid = ''
$powerPlanName = '—'
try {
    $planOutput = (& powercfg.exe /getactivescheme 2>&1 | Out-String)
    if ($planOutput -match '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') {
        $powerPlanGuid = $Matches[1].ToLower()
    }
    $planNames = @{
        '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Balanced'
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'High performance'
        'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Power saver'
        'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Ultimate performance'
    }
    if ($powerPlanGuid -and $planNames.ContainsKey($powerPlanGuid)) { $powerPlanName = $planNames[$powerPlanGuid] }
    if ($planOutput -and $powerPlanName -eq '—') {
        $powerPlanName = ($planOutput -replace '\s+', ' ').Trim()
    }
} catch { }
Add-Info $secBattery 'Chế độ nguồn' $powerPlanName

# ---------------------------------------------------------------------
Write-Host '[7/15] Đang đọc âm thanh...' -ForegroundColor Cyan
$renderEndpoints = @(Get-AudioEndpoints -Flow Render)
$captureEndpoints = @(Get-AudioEndpoints -Flow Capture)
$soundDevices = @(Get-CimData 'Win32_SoundDevice')
$audioService = Get-Service -Name Audiosrv -ErrorAction SilentlyContinue

$secAudio = New-Section 'Âm thanh (loa / micro)'
Add-Info $secAudio 'Thiết bị phát đang hoạt động' $(if (@($renderEndpoints | Where-Object { [int]$_.StateCode -eq 1 }).Count -gt 0) { (@($renderEndpoints | Where-Object { [int]$_.StateCode -eq 1 }).Name -join '; ') } else { 'Không có' })
Add-Info $secAudio 'Thiết bị thu đang hoạt động' $(if (@($captureEndpoints | Where-Object { [int]$_.StateCode -eq 1 }).Count -gt 0) { (@($captureEndpoints | Where-Object { [int]$_.StateCode -eq 1 }).Name -join '; ') } else { 'Không có' })
Add-Info $secAudio 'Dịch vụ âm thanh' $(if ($audioService) { "$($audioService.Status)" } else { 'Không tìm thấy' })
Add-Info $secAudio 'Thiết bị âm thanh (WMI)' $(if ($soundDevices.Count -gt 0) { (@($soundDevices | ForEach-Object { $_.Name }) -join '; ') } else { '—' })

$renderRows = @()
foreach ($endpoint in $renderEndpoints) {
    $renderRows += , @((Format-Text $endpoint.Name), $endpoint.State)
}
if ($renderRows.Count -gt 0) {
    Add-Table $secAudio 'Thiết bị phát (loa / tai nghe)' @('Tên thiết bị', 'Trạng thái') $renderRows
}

$captureRows = @()
foreach ($endpoint in $captureEndpoints) {
    $captureRows += , @((Format-Text $endpoint.Name), $endpoint.State)
}
if ($captureRows.Count -gt 0) {
    Add-Table $secAudio 'Thiết bị thu (micro)' @('Tên thiết bị', 'Trạng thái') $captureRows
}

# ---------------------------------------------------------------------
Write-Host '[8/15] Đang đọc camera...' -ForegroundColor Cyan
$pnp = @(Get-CimData 'Win32_PnPEntity')
$cameras = @($pnp | Where-Object {
        $_.PNPClass -in @('Camera', 'Image') -and
        $_.Name -and
        $_.Status -eq 'OK'
    })

$secCamera = New-Section 'Camera'
$cameraRows = @()
foreach ($camera in $cameras) {
    $cameraRows += , @((Format-Text $camera.Name), (Format-Text $camera.Manufacturer), (Format-Text $camera.Status))
}
if ($cameraRows.Count -gt 0) {
    Add-Table $secCamera 'Camera phát hiện được' @('Tên', 'Hãng', 'Trạng thái') $cameraRows
} else {
    Add-Info $secCamera 'Camera' 'Không phát hiện camera.'
}

# ---------------------------------------------------------------------
Write-Host '[9/15] Đang đọc bàn phím, touchpad, cảm ứng, vân tay...' -ForegroundColor Cyan
$keyboards = @($pnp | Where-Object { $_.PNPClass -eq 'Keyboard' -and $_.Name })
$mice = @($pnp | Where-Object { $_.PNPClass -eq 'Mouse' -and $_.Name })
$touchpads = @($pnp | Where-Object {
        $_.PNPClass -in @('Mouse', 'HIDClass') -and $_.Name -and
        $_.Name -match 'touch\s*pad|trackpad|precision|synaptics|elan|alps'
    })
$touchscreens = @($pnp | Where-Object {
        $_.PNPClass -in @('HIDClass', 'Mouse', 'USB') -and $_.Name -and
        $_.Name -match 'touch\s*screen|touchscreen|digitizer|touch digitizer'
    })
$biometrics = @($pnp | Where-Object {
        $_.PNPClass -eq 'Biometric' -or ($_.Name -and $_.Name -match 'fingerprint|vân tay|Windows Hello')
    })
$precisionTouchpad = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'

$secInput = New-Section 'Bàn phím / touchpad / cảm ứng'
Add-Info $secInput 'Bàn phím' (Get-DeviceNames $keyboards)
Add-Info $secInput 'Chuột / touchpad' (Get-DeviceNames @($mice + $touchpads))
Add-Info $secInput 'Touchpad precision' $(if ($precisionTouchpad) { 'Có' } else { 'Không phát hiện' })
Add-Info $secInput 'Màn hình cảm ứng' (Get-DeviceNames $touchscreens)
Add-Info $secInput 'Vân tay / Windows Hello' (Get-DeviceNames $biometrics)

$inputRows = @()
foreach ($device in @($keyboards + $mice + $touchpads + $touchscreens + $biometrics)) {
    $inputRows += , @((Format-Text $device.PNPClass), (Format-Text $device.Name), (Format-Text $device.Status))
}
if ($inputRows.Count -gt 0) {
    Add-Table $secInput 'Thiết bị nhập liệu & sinh trắc học' @('Lớp', 'Tên thiết bị', 'Trạng thái') $inputRows
}

# ---------------------------------------------------------------------
Write-Host '[10/15] Đang đọc mạng và Bluetooth...' -ForegroundColor Cyan
$netAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
$hardwareAdapters = @($netAdapters | Where-Object { $_.HardwareInterface -or $_.Status -eq 'Up' })
$wifiAdapters = @($netAdapters | Where-Object {
        $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11' -or $_.Name -match 'Wi-?Fi|WLAN'
    })
$bluetoothRadios = @($pnp | Where-Object {
        $_.PNPClass -eq 'Bluetooth' -and $_.Name -and
        $_.Name -notmatch 'Enumerator|Protocol|Service|RFCOMM|Avrcp|Transport'
    })

$secNetwork = New-Section 'Mạng & Bluetooth'
$adapterRows = @()
foreach ($adapter in $hardwareAdapters) {
    $adapterRows += , @(
        (Format-Text $adapter.Name),
        (Format-Text $adapter.InterfaceDescription),
        (Format-Text $adapter.Status),
        (Format-Text $adapter.LinkSpeed),
        (Format-Text $adapter.MacAddress),
        (Format-Text $adapter.DriverVersion),
        (Format-DateValue $adapter.DriverDate)
    )
}
if ($adapterRows.Count -gt 0) {
    Add-Table $secNetwork 'Card mạng (vật lý và đang hoạt động)' @('Tên', 'Mô tả', 'Trạng thái', 'Tốc độ', 'MAC', 'Driver', 'Ngày driver') $adapterRows
}

$ipRows = @()
try {
    $ipConfigs = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.NetAdapter.Status -eq 'Up' })
    foreach ($ip in $ipConfigs) {
        $ipv4 = @($ip.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', '
        $gateway = @($ip.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ', '
        $dns = @($ip.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ', '
        $ipRows += , @((Format-Text $ip.InterfaceAlias), (Format-Text $ipv4), (Format-Text $gateway), (Format-Text $dns))
    }
} catch { }
if ($ipRows.Count -gt 0) {
    Add-Table $secNetwork 'Địa chỉ IP đang dùng' @('Card', 'IPv4', 'Gateway', 'DNS') $ipRows
}

$wifiRows = @()
try {
    $profiles = @(Get-NetConnectionProfile -ErrorAction Stop)
    foreach ($profile in $profiles) {
        $wifiRows += , @(
            (Format-Text $profile.Name),
            (Format-Text $profile.InterfaceAlias),
            (Format-Text $profile.NetworkCategory),
            (Format-Text $profile.IPv4Connectivity)
        )
    }
} catch { }
if ($wifiRows.Count -gt 0) {
    Add-Table $secNetwork 'Kết nối mạng hiện tại' @('Tên (SSID)', 'Card', 'Loại mạng', 'Kết nối IPv4') $wifiRows
}

$wifiStandards = @()
try {
    $wlanDrivers = (& netsh.exe wlan show drivers 2>&1 | Out-String)
    $wifiStandards = @([regex]::Matches($wlanDrivers, '802\.11[a-zA-Z]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
} catch { }
if ($wifiAdapters.Count -gt 0) {
    Add-Info $secNetwork 'Chuẩn Wi-Fi hỗ trợ' $(if ($wifiStandards.Count -gt 0) { $wifiStandards -join ', ' } else { 'Không đọc được' })
}
Add-Info $secNetwork 'Bluetooth' $(if ($bluetoothRadios.Count -gt 0) { 'Có' } else { 'Không' })
Add-Info $secNetwork 'Thiết bị Bluetooth' $(if ($bluetoothRadios.Count -gt 0) { Get-DeviceNames $bluetoothRadios } else { '—' })

# ---------------------------------------------------------------------
Write-Host '[11/15] Đang đọc cổng kết nối và thiết bị ngoại vi...' -ForegroundColor Cyan
$usbControllers = @(Get-CimData 'Win32_USBController')
$usbDevices = @($pnp | Where-Object { $_.PNPClass -eq 'USB' -and $_.Name })
$portDevices = @($pnp | Where-Object { $_.PNPClass -eq 'Ports' -and $_.Name })
$sdHosts = @($pnp | Where-Object { $_.PNPClass -eq 'SDHost' -and $_.Name })

$secPorts = New-Section 'Cổng kết nối & thiết bị ngoại vi'
$usbRows = @()
foreach ($controller in $usbControllers) {
    $usbRows += , @((Format-Text $controller.Name), (Format-Text $controller.Manufacturer), (Format-Text $controller.Status))
}
if ($usbRows.Count -gt 0) {
    Add-Table $secPorts 'Bộ điều khiển USB' @('Tên', 'Hãng', 'Trạng thái') $usbRows
}
Add-Info $secPorts 'Số thiết bị USB hiện diện' $usbDevices.Count
Add-Info $secPorts 'Đầu đọc thẻ nhớ (SD)' $(if ($sdHosts.Count -gt 0) { Get-DeviceNames $sdHosts } else { 'Không phát hiện' })
Add-Info $secPorts 'Cổng COM / LPT' $(if ($portDevices.Count -gt 0) { Get-DeviceNames $portDevices } else { 'Không phát hiện' })

$usbDeviceRows = @()
foreach ($device in $usbDevices) {
    $errorCode = [int]$device.ConfigManagerErrorCode
    $errorNote = if ($errorCode -ne 0) { Get-DeviceErrorName $errorCode } else { '—' }
    $usbDeviceRows += , @((Format-Text $device.Name), (Format-Text $device.Status), $errorNote)
}
if ($usbDeviceRows.Count -gt 0) {
    Add-Table $secPorts 'Thiết bị USB đang hiện diện' @('Tên', 'Trạng thái', 'Ghi chú') $usbDeviceRows
}

$problemDevices = @($pnp | Where-Object { $null -ne $_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -ne 0 })
$problemRows = @()
foreach ($device in $problemDevices) {
    $problemRows += , @(
        (Format-Text $device.Name),
        (Format-Text $device.PNPClass),
        "$($device.ConfigManagerErrorCode)",
        (Get-DeviceErrorName ([int]$device.ConfigManagerErrorCode))
    )
}
if ($problemRows.Count -gt 0) {
    Add-Table $secPorts 'Thiết bị đang báo lỗi' @('Tên', 'Lớp', 'Mã lỗi', 'Mô tả') $problemRows
    $names = @($problemDevices | Select-Object -First 3 | ForEach-Object { $_.Name }) -join '; '
    Add-Warning 'Cao' "Có $($problemDevices.Count) thiết bị báo lỗi trong Device Manager: $names"
}

# ---------------------------------------------------------------------
Write-Host '[12/15] Đang đọc thông tin bảo mật...' -ForegroundColor Cyan
$tpm = $null
$tpmError = ''
try { $tpm = Get-Tpm -ErrorAction Stop } catch { $tpmError = $_.Exception.Message }
$tpmWmi = @(Get-CimData 'Win32_Tpm' -Namespace 'root/cimv2/security/microsofttpm') | Select-Object -First 1
$tpmPresent = ($tpm -and $tpm.TpmPresent) -or $tpmWmi
$tpmReady = ($tpm -and $tpm.TpmReady)
$tpmSpec = if ($tpmWmi) { $tpmWmi.SpecVersion } elseif ($tpm) { $tpm.SpecVersion } else { '' }

$tpmSummary = 'TPM: Không đọc được'
if ($tpmPresent) {
    if ($tpmReady) { $tpmSummary = 'TPM - Hiện diện, sẵn sàng' } else { $tpmSummary = 'TPM - Hiện diện, chưa sẵn sàng' }
    $tpmSpecShort = ''
    if ($tpmSpec) { $tpmSpecShort = (@($tpmSpec -split ',')[0]).Trim() }
    if ($tpmSpecShort) { $tpmSummary = "TPM $tpmSpecShort - $($tpmSummary -replace '^TPM\s*-\s*', '')" }
} elseif ($tpmError) {
    $tpmSummary = 'TPM: Không đọc được (cần Administrator)'
}

$bitlockerVolumes = @()
$bitlockerError = ''
try { $bitlockerVolumes = @(Get-BitLockerVolume -ErrorAction Stop) } catch { $bitlockerError = $_.Exception.Message }

$defender = $null
$defenderError = ''
try { $defender = Get-MpComputerStatus -ErrorAction Stop } catch { $defenderError = $_.Exception.Message }

$firewallProfiles = @()
try { $firewallProfiles = @(Get-NetFirewallProfile -ErrorAction Stop) } catch { }
$avProducts = @(Get-CimData 'AntiVirusProduct' -Namespace 'root/SecurityCenter2')

$secSecurity = New-Section 'Bảo mật hệ thống'
Add-Info $secSecurity 'TPM' $tpmSummary
if ($tpmWmi) {
    Add-Info $secSecurity 'TPM Manufacturer' $tpmWmi.ManufacturerIdTxt
    Add-Info $secSecurity 'TPM Firmware' $tpmWmi.ManufacturerVersion
}
Add-Info $secSecurity 'Secure Boot' $secureBootStatus
Add-Info $secSecurity 'BitLocker' $(if ($bitlockerVolumes.Count -gt 0) { 'Có dữ liệu' } elseif ($bitlockerError) { 'Không đọc được (cần Administrator)' } else { 'Không bật / không có ổ hỗ trợ' })
Add-Info $secSecurity 'Windows Defender' $(if ($defender) { if ($defender.AntivirusEnabled) { 'Đang bật' } else { 'Đang tắt' } } elseif ($defenderError) { 'Không đọc được' } else { '—' })
if ($defender) {
    Add-Info $secSecurity 'Bảo vệ thời gian thực' $defender.RealTimeProtectionEnabled
    Add-Info $secSecurity 'Bảo vệ chống giả mạo' $defender.IsTamperProtected
    Add-Info $secSecurity 'Phiên bản signature' $defender.AntivirusSignatureVersion
    Add-Info $secSecurity 'Cập nhật signature' (Format-DateValue $defender.AntivirusSignatureLastUpdated)
}
$uacEnable = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
$uacLevel = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
Add-Info $secSecurity 'UAC' $(if ($null -ne $uacEnable) { if ([int]$uacEnable -eq 1) { "Bật (mức $uacLevel)" } else { 'Tắt' } } else { '—' })

if ($bitlockerVolumes.Count -gt 0) {
    $blRows = @()
    foreach ($vol in $bitlockerVolumes) {
        $blRows += , @(
            (Format-Text $vol.MountPoint),
            (Format-Text $vol.VolumeStatus),
            (Format-Text $vol.ProtectionStatus),
            (Format-Text $vol.EncryptionPercentage),
            (Format-Text $vol.EncryptionMethod)
        )
    }
    Add-Table $secSecurity 'BitLocker' @('Ổ', 'Trạng thái', 'Bảo vệ', 'Tiến độ mã hóa', 'Phương thức') $blRows
}

$fwRows = @()
foreach ($profile in $firewallProfiles) {
    $fwRows += , @(
        (Format-Text $profile.Name),
        (Get-FirewallStateName $profile.Enabled),
        (Get-FirewallActionName $profile.DefaultInboundAction),
        (Get-FirewallActionName $profile.DefaultOutboundAction)
    )
}
if ($fwRows.Count -gt 0) {
    Add-Table $secSecurity 'Windows Firewall' @('Profile', 'Bật', 'Inbound mặc định', 'Outbound mặc định') $fwRows
}

if ($avProducts.Count -gt 0) {
    $avRows = @()
    foreach ($av in $avProducts) {
        $avRows += , @((Format-Text $av.displayName), (Format-Text $av.pathToSignedProductExe))
    }
    Add-Table $secSecurity 'Phần mềm diệt virus (Security Center)' @('Tên', 'Đường dẫn') $avRows
}

$deviceGuard = @(Get-CimData 'Win32_DeviceGuard' -Namespace 'root/Microsoft/Windows/DeviceGuard') | Select-Object -First 1
if ($deviceGuard) {
    Add-Info $secSecurity 'Virtualization-Based Security (VBS)' (Get-VbsStatusName ([int]$deviceGuard.VirtualizationBasedSecurityStatus))
    Add-Info $secSecurity 'Dịch vụ bảo mật VBS' (Get-VbsServiceNames $deviceGuard.SecurityServicesRunning)
}

if (-not $tpmPresent -and $script:IsAdmin) {
    Add-Warning 'Cao' 'Không phát hiện TPM. Windows 11 yêu cầu TPM 2.0.'
}
if ($secureBootStatus -eq 'Tắt') {
    Add-Warning 'Trung bình' 'Secure Boot đang tắt. Nên bật trong BIOS/UEFI nếu không có yêu cầu đặc biệt.'
}
if ($defender -and -not $defender.RealTimeProtectionEnabled -and $avProducts.Count -eq 0) {
    Add-Warning 'Trung bình' 'Windows Defender đang tắt bảo vệ thời gian thực và không thấy phần mềm diệt virus khác.'
}
$enabledFw = @($firewallProfiles | Where-Object { $_.Enabled })
if ($firewallProfiles.Count -gt 0 -and $enabledFw.Count -lt $firewallProfiles.Count) {
    Add-Warning 'Cao' 'Có profile Windows Firewall đang tắt.'
}

$securitySummary = "$tpmSummary • Secure Boot: $secureBootStatus"

# ---------------------------------------------------------------------
Write-Host '[13/15] Đang đọc cập nhật Windows và nhật ký sự kiện...' -ForegroundColor Cyan
$hotfixes = @()
try { $hotfixes = @(Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending) } catch { }
$pendingReboot = $false
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pendingReboot = $true }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pendingReboot = $true }
$pendingFileRename = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
if ($pendingFileRename) { $pendingReboot = $true }
$wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue

$secUpdates = New-Section 'Cập nhật & sự kiện hệ thống'
Add-Info $secUpdates 'Cần khởi động lại' $(if ($pendingReboot) { 'Có' } else { 'Không' })
Add-Info $secUpdates 'Dịch vụ Windows Update' $(if ($wuService) { "$($wuService.Status) / $($wuService.StartType)" } else { 'Không tìm thấy' })
Add-Info $secUpdates 'Số bản cập nhật đã cài' $hotfixes.Count
if ($hotfixes.Count -gt 0) {
    Add-Info $secUpdates 'Cập nhật gần nhất' "$($hotfixes[0].HotFixID) - $(Format-DateValue $hotfixes[0].InstalledOn)"
    $hfRows = @()
    foreach ($hf in @($hotfixes | Select-Object -First 12)) {
        $hfRows += , @((Format-Text $hf.HotFixID), (Format-Text $hf.Description), (Format-DateValue $hf.InstalledOn), (Format-Text $hf.InstalledBy))
    }
    Add-Table $secUpdates 'Các bản cập nhật gần đây' @('Mã KB', 'Mô tả', 'Ngày cài', 'Người cài') $hfRows
}

$eventErrors = @()
try {
    $eventErrors = @(Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 1, 2
            StartTime = (Get-Date).AddDays(-7)
        } -MaxEvents 300 -ErrorAction Stop)
} catch { }
Add-Info $secUpdates 'Lỗi/Nghiêm trọng (System, 7 ngày)' $eventErrors.Count
if ($eventErrors.Count -gt 0) {
    $eventRows = @()
    foreach ($eventItem in @($eventErrors | Select-Object -First 10)) {
        $message = ''
        try { $message = ($eventItem.Message -replace '\s+', ' ').Trim() } catch { }
        if ($message.Length -gt 180) { $message = $message.Substring(0, 180) + '...' }
        $eventRows += , @(
            $eventItem.TimeCreated.ToString('dd/MM/yyyy HH:mm'),
            "$($eventItem.Id)",
            (Format-Text $eventItem.LevelDisplayName),
            (Format-Text $eventItem.ProviderName),
            $message
        )
    }
    Add-Table $secUpdates 'Sự kiện lỗi gần đây' @('Thời gian', 'Event ID', 'Mức độ', 'Nguồn', 'Nội dung') $eventRows
}
if ($eventErrors.Count -gt 50) {
    Add-Warning 'Trung bình' "Có $($eventErrors.Count) sự kiện lỗi/nghiêm trọng trong System log 7 ngày qua."
}
if ($pendingReboot) {
    Add-Warning 'Thấp' 'Máy đang có thay đổi chờ khởi động lại để hoàn tất cài đặt/cập nhật.'
}

# ---------------------------------------------------------------------
Write-Host '[14/15] Đang đọc phần mềm đã cài...' -ForegroundColor Cyan
$uninstallPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$rawApps = @()
foreach ($path in $uninstallPaths) {
    $rawApps += @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -and $_.SystemComponent -ne 1 -and $_.DisplayName -notmatch '^(Update for|Security Update|Hotfix)'
        })
}
$apps = @($rawApps | Group-Object { "$($_.DisplayName)|$($_.DisplayVersion)" } | ForEach-Object { $_.Group[0] } | Sort-Object DisplayName)
$appxCount = 0
try { $appxCount = @(Get-AppxPackage -ErrorAction Stop).Count } catch { }
$startupItems = @(Get-CimData 'Win32_StartupCommand')

$secSoftware = New-Section 'Phần mềm đã cài'
Add-Info $secSoftware 'Số ứng dụng desktop' $apps.Count
Add-Info $secSoftware 'Số ứng dụng Microsoft Store' $appxCount
Add-Info $secSoftware 'Chương trình khởi động cùng Windows' $startupItems.Count

$appRows = @()
foreach ($app in $apps) {
    $installDate = '—'
    if ($app.InstallDate -match '^\d{8}$') {
        try { $installDate = ([datetime]::ParseExact($app.InstallDate, 'yyyyMMdd', $null)).ToString('dd/MM/yyyy') } catch { $installDate = $app.InstallDate }
    } elseif ($app.InstallDate) {
        $installDate = $app.InstallDate
    }
    $appRows += , @(
        (Format-Text $app.DisplayName),
        (Format-Text $app.DisplayVersion),
        (Format-Text $app.Publisher),
        $installDate
    )
}
if ($appRows.Count -gt 0) {
    Add-Table $secSoftware 'Ứng dụng desktop đã cài' @('Tên', 'Phiên bản', 'Nhà phát hành', 'Ngày cài') $appRows
}

$startupRows = @()
foreach ($item in $startupItems) {
    $startupRows += , @((Format-Text $item.Name), (Format-Text $item.Command), (Format-Text $item.Location), (Format-Text $item.User))
}
if ($startupRows.Count -gt 0) {
    Add-Table $secSoftware 'Chương trình khởi động cùng Windows' @('Tên', 'Lệnh', 'Vị trí', 'Người dùng') $startupRows
}

# ---------------------------------------------------------------------
Write-Host '[15/15] Đang đọc thông tin bổ sung...' -ForegroundColor Cyan
$secOther = New-Section 'Thông tin bổ sung'
Add-Info $secOther 'Phiên bản PowerShell' $PSVersionTable.PSVersion.ToString()
Add-Info $secOther 'Kiến trúc tiến trình' $env:PROCESSOR_ARCHITECTURE
Add-Info $secOther 'Múi giờ' (Get-TimeZone).DisplayName
Add-Info $secOther 'Culture' (Get-Culture).Name
Add-Info $secOther 'Thời gian bắt đầu kiểm tra' $script:StartedAt.ToString('dd/MM/yyyy HH:mm:ss')
Add-Info $secOther 'Thời gian thu thập dữ liệu' (Format-Duration ((Get-Date) - $script:StartedAt))

$temps = @(Get-CimData 'MSAcpi_ThermalZoneTemperature' -Namespace 'root/wmi')
$tempRows = @()
foreach ($temp in $temps) {
    $celsius = '—'
    try { $celsius = ('{0:N1} °C' -f (([double]$temp.CurrentTemperature / 10) - 273.15)) } catch { }
    $tempRows += , @((Format-Text $temp.InstanceName), $celsius, (Format-Text $temp.Active))
    if ($celsius -ne '—') {
        $tempValue = ([double]$temp.CurrentTemperature / 10) - 273.15
        if ($tempValue -ge 85) {
            Add-Warning 'Cao' "Nhiệt độ cảm biến $($temp.InstanceName) đang ở $celsius."
        } elseif ($tempValue -ge 75) {
            Add-Warning 'Trung bình' "Nhiệt độ cảm biến $($temp.InstanceName) đang ở $celsius."
        }
    }
}
if ($tempRows.Count -gt 0) {
    Add-Table $secOther 'Cảm biến nhiệt độ' @('Cảm biến', 'Nhiệt độ', 'Đang hoạt động') $tempRows
}

$serviceNames = @('Audiosrv', 'BTAGService', 'bthserv', 'WlanSvc', 'wuauserv', 'WinDefend', 'Spooler', 'Themes')
$serviceRows = @()
foreach ($serviceName in $serviceNames) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        $serviceRows += , @($svc.Name, (Format-Text $svc.DisplayName), (Format-Text $svc.Status), (Format-Text $svc.StartType))
    }
}
if ($serviceRows.Count -gt 0) {
    Add-Table $secOther 'Dịch vụ hệ thống quan trọng' @('Tên', 'Mô tả', 'Trạng thái', 'Khởi động') $serviceRows
}

# Biến phục vụ test tay / báo cáo
$script:HwCamera = $cameras
$script:HwTouchscreen = $touchscreens
$script:HwTouchpad = $touchpads
$script:HwBiometric = $biometrics
$script:HwRender = @($renderEndpoints | Where-Object { [int]$_.StateCode -eq 1 })
$script:HwCapture = @($captureEndpoints | Where-Object { [int]$_.StateCode -eq 1 })
if ($script:HwRender.Count -eq 0) {
    Add-Warning 'Trung bình' 'Không phát hiện thiết bị phát âm thanh đang hoạt động.'
}
$script:HwHasBattery = $hasBattery
$script:IsLaptop = $isLaptop
$script:MonitorSummary = $displaySummary
$script:BatterySummary = $batterySummary

# =====================================================================
#  CÔNG CỤ KIỂM TRA TAY
# =====================================================================

function Open-SettingsPage {
    param([string]$Uri)
    # Mở qua explorer.exe để các ứng dụng UWP (Settings, Camera, Sound Recorder...)
    # vẫn khởi chạy được khi script đang chạy bằng quyền Administrator.
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $Uri -ErrorAction Stop
        return $true
    } catch {
        try {
            Start-Process -FilePath $Uri -ErrorAction Stop
            return $true
        } catch {
            Write-Host "  ! Không mở được $Uri : $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }
}

function Start-InstalledApp {
    param([string]$Pattern, [string]$FallbackUri = '')
    $app = $null
    try {
        $app = Get-StartApps -ErrorAction Stop | Where-Object { $_.Name -match $Pattern } | Select-Object -First 1
    } catch { }
    if ($app) {
        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($app.AppID)" -ErrorAction Stop
            return $true
        } catch {
            try {
                Start-Process -FilePath "shell:AppsFolder\$($app.AppID)" -ErrorAction Stop
                return $true
            } catch { }
        }
    }
    if ($FallbackUri) { return (Open-SettingsPage $FallbackUri) }
    return $false
}

function Show-ScreenTest {
    param([int]$AutoCloseSeconds = 0)
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $script:ScreenForm = New-Object System.Windows.Forms.Form
    $script:ScreenForm.Text = 'Kiểm tra màn hình'
    $script:ScreenForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $script:ScreenForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $script:ScreenForm.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $script:ScreenForm.TopMost = $true
    $script:ScreenForm.KeyPreview = $true
    $script:ScreenForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

    $script:ScreenLabel = New-Object System.Windows.Forms.Label
    $script:ScreenLabel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $script:ScreenLabel.Height = 42
    $script:ScreenLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:ScreenLabel.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
    $script:ScreenLabel.ForeColor = [System.Drawing.Color]::White
    $script:ScreenLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Regular)
    $script:ScreenForm.Controls.Add($script:ScreenLabel)

    $script:ScreenColors = @(
        [pscustomobject]@{ Name = 'ĐEN'; Color = [System.Drawing.Color]::Black },
        [pscustomobject]@{ Name = 'TRẮNG'; Color = [System.Drawing.Color]::White },
        [pscustomobject]@{ Name = 'ĐỎ'; Color = [System.Drawing.Color]::FromArgb(220, 0, 0) },
        [pscustomobject]@{ Name = 'XANH LÁ'; Color = [System.Drawing.Color]::FromArgb(0, 180, 0) },
        [pscustomobject]@{ Name = 'XANH DƯƠNG'; Color = [System.Drawing.Color]::FromArgb(0, 80, 220) },
        [pscustomobject]@{ Name = 'XÁM'; Color = [System.Drawing.Color]::FromArgb(128, 128, 128) }
    )
    $script:ScreenColorIndex = 0

    $script:ScreenUpdateAction = {
        $item = $script:ScreenColors[$script:ScreenColorIndex]
        $script:ScreenForm.BackColor = $item.Color
        $script:ScreenLabel.Text = "Màu: $($item.Name)   |   Space / chạm / chuột trái: màu tiếp   |   H: ẩn/hiện hướng dẫn   |   Esc / chuột phải: thoát"
    }

    $script:ScreenForm.Add_KeyDown({
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                $script:ScreenForm.Close()
            } elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Space) {
                $script:ScreenColorIndex = ($script:ScreenColorIndex + 1) % $script:ScreenColors.Count
                & $script:ScreenUpdateAction
            } elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::H) {
                $script:ScreenLabel.Visible = -not $script:ScreenLabel.Visible
            }
        })
    $script:ScreenForm.Add_MouseClick({
            if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                $script:ScreenForm.Close()
            } else {
                $script:ScreenColorIndex = ($script:ScreenColorIndex + 1) % $script:ScreenColors.Count
                & $script:ScreenUpdateAction
            }
        })
    $script:ScreenForm.Add_Shown({
            $script:ScreenForm.Activate()
            $script:ScreenForm.Focus()
            & $script:ScreenUpdateAction
        })

    $script:ScreenTimer = $null
    if ($AutoCloseSeconds -gt 0) {
        $script:ScreenTimer = New-Object System.Windows.Forms.Timer
        $script:ScreenTimer.Interval = $AutoCloseSeconds * 1000
        $script:ScreenTimer.Add_Tick({
                $script:ScreenTimer.Stop()
                $script:ScreenForm.Close()
            })
        $script:ScreenTimer.Start()
    }

    try {
        [void]$script:ScreenForm.ShowDialog()
    } finally {
        if ($script:ScreenTimer) {
            $script:ScreenTimer.Stop()
            $script:ScreenTimer.Dispose()
            $script:ScreenTimer = $null
        }
        if ($script:ScreenForm) {
            $script:ScreenForm.Dispose()
            $script:ScreenForm = $null
        }
    }
}

function Show-TouchTest {
    param([int]$AutoCloseSeconds = 0)
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $script:TouchForm = New-Object System.Windows.Forms.Form
    $script:TouchForm.Text = 'Kiểm tra màn hình cảm ứng'
    $script:TouchForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $script:TouchForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $script:TouchForm.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $script:TouchForm.TopMost = $true
    $script:TouchForm.KeyPreview = $true
    $script:TouchForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $script:TouchForm.BackColor = [System.Drawing.Color]::White

    $script:TouchPic = New-Object System.Windows.Forms.PictureBox
    $script:TouchPic.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:TouchPic.BackColor = [System.Drawing.Color]::White
    $script:TouchPic.Cursor = [System.Windows.Forms.Cursors]::Cross
    $script:TouchForm.Controls.Add($script:TouchPic)

    $script:TouchLabel = New-Object System.Windows.Forms.Label
    $script:TouchLabel.AutoSize = $false
    $script:TouchLabel.Width = [Math]::Max(500, $script:TouchForm.Bounds.Width - 240)
    $script:TouchLabel.Height = 34
    $script:TouchLabel.Location = New-Object System.Drawing.Point(16, 12)
    $script:TouchLabel.BackColor = [System.Drawing.Color]::White
    $script:TouchLabel.ForeColor = [System.Drawing.Color]::FromArgb(20, 60, 100)
    $script:TouchLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $script:TouchLabel.Text = 'Dùng ngón tay/bút vẽ lên vùng trắng, thử cả 4 góc và viền màn hình. Nhấn XONG hoặc Esc khi hoàn tất.'
    $script:TouchForm.Controls.Add($script:TouchLabel)

    $script:TouchButton = New-Object System.Windows.Forms.Button
    $script:TouchButton.Text = 'XONG'
    $script:TouchButton.Size = New-Object System.Drawing.Size(140, 44)
    $script:TouchButton.Location = New-Object System.Drawing.Point(($script:TouchForm.Bounds.Width - 160), 8)
    $script:TouchButton.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
    $script:TouchButton.BackColor = [System.Drawing.Color]::FromArgb(11, 79, 122)
    $script:TouchButton.ForeColor = [System.Drawing.Color]::White
    $script:TouchButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $script:TouchButton.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $script:TouchForm.Controls.Add($script:TouchButton)
    $script:TouchLabel.BringToFront()
    $script:TouchButton.BringToFront()

    $script:TouchDrawing = $false
    $script:TouchLast = $null
    $script:TouchBitmap = $null
    $script:TouchGraphics = $null
    $script:TouchPen = $null
    $script:TouchBrush = $null

    $script:TouchForm.Add_Shown({
            $w = [Math]::Max(100, $script:TouchPic.ClientSize.Width)
            $h = [Math]::Max(100, $script:TouchPic.ClientSize.Height)
            $script:TouchBitmap = New-Object System.Drawing.Bitmap($w, $h)
            $script:TouchGraphics = [System.Drawing.Graphics]::FromImage($script:TouchBitmap)
            $script:TouchGraphics.Clear([System.Drawing.Color]::White)
            $script:TouchGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $script:TouchPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 110, 200), 5)
            $script:TouchBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 110, 200))
            $script:TouchPic.Image = $script:TouchBitmap
            $script:TouchForm.Activate()
            $script:TouchForm.Focus()
        })
    $script:TouchPic.Add_MouseDown({
            $script:TouchDrawing = $true
            $script:TouchLast = $_.Location
            if ($script:TouchGraphics) {
                $script:TouchGraphics.FillEllipse($script:TouchBrush, ($_.X - 4), ($_.Y - 4), 8, 8)
                $script:TouchPic.Invalidate()
            }
        })
    $script:TouchPic.Add_MouseMove({
            if ($script:TouchDrawing -and $script:TouchLast -and $script:TouchGraphics) {
                $script:TouchGraphics.DrawLine($script:TouchPen, $script:TouchLast, $_.Location)
                $script:TouchLast = $_.Location
                $script:TouchPic.Invalidate()
            }
        })
    $script:TouchPic.Add_MouseUp({
            $script:TouchDrawing = $false
            $script:TouchLast = $null
        })
    $script:TouchForm.Add_KeyDown({
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $script:TouchForm.Close() }
        })
    $script:TouchButton.Add_Click({ $script:TouchForm.Close() })
    $script:TouchForm.Add_FormClosed({
            try {
                if ($script:TouchPic) { $script:TouchPic.Image = $null }
                if ($script:TouchPen) { $script:TouchPen.Dispose() }
                if ($script:TouchBrush) { $script:TouchBrush.Dispose() }
                if ($script:TouchGraphics) { $script:TouchGraphics.Dispose() }
                if ($script:TouchBitmap) { $script:TouchBitmap.Dispose() }
            } catch { }
        })

    $script:TouchTimer = $null
    if ($AutoCloseSeconds -gt 0) {
        $script:TouchTimer = New-Object System.Windows.Forms.Timer
        $script:TouchTimer.Interval = $AutoCloseSeconds * 1000
        $script:TouchTimer.Add_Tick({
                $script:TouchTimer.Stop()
                $script:TouchForm.Close()
            })
        $script:TouchTimer.Start()
    }

    try {
        [void]$script:TouchForm.ShowDialog()
    } finally {
        if ($script:TouchTimer) {
            $script:TouchTimer.Stop()
            $script:TouchTimer.Dispose()
            $script:TouchTimer = $null
        }
        if ($script:TouchForm) {
            $script:TouchForm.Dispose()
            $script:TouchForm = $null
        }
    }
}

function New-KbKey {
    param([string]$Id, [string]$Label, [string[]]$Keys = @(), [int]$Width = 44)
    return [pscustomobject]@{
        Id    = $Id
        Label = $Label
        Keys  = $Keys
        Width = $Width
    }
}

function Show-KeyboardTest {
    param([int]$AutoCloseSeconds = 0)
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $script:KeyboardTestResult = $null
    $script:KbButtons = @{}
    $script:KbKeyMap = @{}
    $script:KbTested = @{}

    $row1 = @(New-KbKey 'Escape' 'Esc' @('Escape'))
    for ($i = 1; $i -le 12; $i++) { $row1 += New-KbKey "F$i" "F$i" @("F$i") }
    $row1 += @(
        New-KbKey 'Snapshot' 'PrtSc' @('Snapshot')
        New-KbKey 'Scroll' 'ScrLk' @('Scroll')
        New-KbKey 'Pause' 'Pause' @('Pause') 60
    )

    $row2 = @(New-KbKey 'OemTilde' '~' @('OemTilde'))
    for ($i = 1; $i -le 9; $i++) { $row2 += New-KbKey "D$i" "$i" @("D$i") }
    $row2 += New-KbKey 'D0' '0' @('D0')
    $row2 += @(
        New-KbKey 'OemMinus' '-' @('OemMinus')
        New-KbKey 'OemPlus' '=' @('OemPlus')
        New-KbKey 'Back' 'Backspace' @('Back') 74
        New-KbKey 'Insert' 'Ins' @('Insert')
        New-KbKey 'Home' 'Home' @('Home') 54
        New-KbKey 'PageUp' 'PgUp' @('PageUp')
    )

    $row3 = @(New-KbKey 'Tab' 'Tab' @('Tab') 58)
    foreach ($ch in 'QWERTYUIOP'.ToCharArray()) { $row3 += New-KbKey ([string]$ch) ([string]$ch) @([string]$ch) }
    $row3 += @(
        New-KbKey 'OemOpenBrackets' '[' @('OemOpenBrackets')
        New-KbKey 'Oem6' ']' @('Oem6')
        New-KbKey 'OemPipe' '\' @('OemPipe')
        New-KbKey 'Delete' 'Del' @('Delete')
        New-KbKey 'End' 'End' @('End')
        New-KbKey 'PageDown' 'PgDn' @('PageDown')
    )

    $row4 = @(New-KbKey 'CapsLock' 'Caps' @('CapsLock') 72)
    foreach ($ch in 'ASDFGHJKL'.ToCharArray()) { $row4 += New-KbKey ([string]$ch) ([string]$ch) @([string]$ch) }
    $row4 += @(
        New-KbKey 'OemSemicolon' ';' @('OemSemicolon')
        New-KbKey 'OemQuotes' "'" @('OemQuotes')
        New-KbKey 'Enter' 'Enter' @('Enter') 78
    )

    $row5 = @(New-KbKey 'LShiftKey' 'Shift' @('LShiftKey') 80)
    foreach ($ch in 'ZXCVBNM'.ToCharArray()) { $row5 += New-KbKey ([string]$ch) ([string]$ch) @([string]$ch) }
    $row5 += @(
        New-KbKey 'OemComma' ',' @('OemComma')
        New-KbKey 'OemPeriod' '.' @('OemPeriod')
        New-KbKey 'OemQuestion' '/' @('OemQuestion')
        New-KbKey 'RShiftKey' 'Shift' @('RShiftKey') 80
        New-KbKey 'Up' '↑' @('Up') 44
    )

    $row6 = @(
        New-KbKey 'LControlKey' 'Ctrl' @('LControlKey') 56
        New-KbKey 'LWin' 'Win' @('LWin') 48
        New-KbKey 'LMenu' 'Alt' @('LMenu') 52
        New-KbKey 'Fn' 'Fn' @() 44
        New-KbKey 'Space' 'Space' @('Space') 260
        New-KbKey 'RMenu' 'AltGr' @('RMenu') 52
        New-KbKey 'RControlKey' 'Ctrl' @('RControlKey') 56
        New-KbKey 'Apps' 'Menu' @('Apps') 48
        New-KbKey 'Left' '←' @('Left') 44
        New-KbKey 'Down' '↓' @('Down') 44
        New-KbKey 'Right' '→' @('Right') 44
    )

    $rows = @($row1, $row2, $row3, $row4, $row5, $row6)

    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formWidth = [Math]::Min(1180, [Math]::Max(920, $area.Width - 40))
    $formHeight = [Math]::Min(540, [Math]::Max(500, $area.Height - 100))

    $script:KeyboardForm = New-Object System.Windows.Forms.Form
    $script:KeyboardForm.Text = 'Kiểm tra bàn phím'
    $script:KeyboardForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $script:KeyboardForm.ClientSize = New-Object System.Drawing.Size($formWidth, $formHeight)
    $script:KeyboardForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $script:KeyboardForm.MaximizeBox = $false
    $script:KeyboardForm.MinimizeBox = $false
    $script:KeyboardForm.TopMost = $true
    $script:KeyboardForm.KeyPreview = $true
    $script:KeyboardForm.BackColor = [System.Drawing.Color]::White

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = [System.Windows.Forms.DockStyle]::Fill
    $table.ColumnCount = 1
    $table.RowCount = $rows.Count
    $table.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 8)
    $table.BackColor = [System.Drawing.Color]::White
    $table.RowStyles.Clear()
    for ($r = 0; $r -lt $rows.Count; $r++) {
        $rowStyle = New-Object System.Windows.Forms.RowStyle
        $rowStyle.SizeType = [System.Windows.Forms.SizeType]::Absolute
        $rowStyle.Height = 54
        [void]$table.RowStyles.Add($rowStyle)
    }

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = [System.Windows.Forms.DockStyle]::Fill
    $header.Height = 112
    $header.BackColor = [System.Drawing.Color]::FromArgb(243, 248, 252)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = 'KIỂM TRA BÀN PHÍM'
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(11, 79, 122)
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(14, 8)
    $header.Controls.Add($titleLabel)

    $helpLabel = New-Object System.Windows.Forms.Label
    $helpLabel.Text = 'Nhấn từng phím trên bàn phím thật. Phím đã test sẽ chuyển xanh. Với phím đặc biệt như Fn, PrtSc, Pause..., có thể click trực tiếp lên phím trên hình để đánh dấu. Sơ đồ gồm bàn phím chính, không gồm numpad.'
    $helpLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $helpLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 98, 115)
    $helpLabel.AutoSize = $false
    $helpLabel.Size = New-Object System.Drawing.Size(($formWidth - 190), 38)
    $helpLabel.Location = New-Object System.Drawing.Point(14, 40)
    $header.Controls.Add($helpLabel)

    $script:KbStatusLabel = New-Object System.Windows.Forms.Label
    $script:KbStatusLabel.Text = "Đã test 0/$($rows | ForEach-Object { $_.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum) phím"
    $script:KbStatusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
    $script:KbStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(30, 90, 50)
    $script:KbStatusLabel.AutoSize = $true
    $script:KbStatusLabel.Location = New-Object System.Drawing.Point(14, 82)
    $header.Controls.Add($script:KbStatusLabel)

    $script:KbLastLabel = New-Object System.Windows.Forms.Label
    $script:KbLastLabel.Text = 'Phím vừa nhấn: —'
    $script:KbLastLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $script:KbLastLabel.ForeColor = [System.Drawing.Color]::FromArgb(70, 80, 95)
    $script:KbLastLabel.AutoSize = $true
    $script:KbLastLabel.Location = New-Object System.Drawing.Point(330, 82)
    $header.Controls.Add($script:KbLastLabel)

    $doneButton = New-Object System.Windows.Forms.Button
    $doneButton.Text = 'XONG'
    $doneButton.Size = New-Object System.Drawing.Size(120, 40)
    $doneButton.Location = New-Object System.Drawing.Point(($formWidth - 144), 12)
    $doneButton.BackColor = [System.Drawing.Color]::FromArgb(11, 79, 122)
    $doneButton.ForeColor = [System.Drawing.Color]::White
    $doneButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $doneButton.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $doneButton.TabStop = $false
    $header.Controls.Add($doneButton)

    $resetButton = New-Object System.Windows.Forms.Button
    $resetButton.Text = 'LÀM LẠI'
    $resetButton.Size = New-Object System.Drawing.Size(120, 34)
    $resetButton.Location = New-Object System.Drawing.Point(($formWidth - 144), 60)
    $resetButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $resetButton.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $resetButton.TabStop = $false
    $header.Controls.Add($resetButton)

    $rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $rootLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $rootLayout.ColumnCount = 1
    $rootLayout.RowCount = 2
    $rootLayout.RowStyles.Clear()
    $headerStyle = New-Object System.Windows.Forms.RowStyle
    $headerStyle.SizeType = [System.Windows.Forms.SizeType]::Absolute
    $headerStyle.Height = 112
    [void]$rootLayout.RowStyles.Add($headerStyle)
    $bodyStyle = New-Object System.Windows.Forms.RowStyle
    $bodyStyle.SizeType = [System.Windows.Forms.SizeType]::Percent
    $bodyStyle.Height = 100
    [void]$rootLayout.RowStyles.Add($bodyStyle)
    $rootLayout.Controls.Add($header, 0, 0)
    $rootLayout.Controls.Add($table, 0, 1)
    $script:KeyboardForm.Controls.Add($rootLayout)

    $script:KbMarkAction = {
        param([string]$Id)
        if (-not $Id) { return }
        if (-not $script:KbTested.ContainsKey($Id)) {
            $script:KbTested[$Id] = $true
            $button = $script:KbButtons[$Id]
            if ($button) {
                $button.BackColor = [System.Drawing.Color]::FromArgb(198, 239, 206)
                $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 165, 105)
            }
        }
        if ($script:KbStatusLabel) {
            $script:KbStatusLabel.Text = "Đã test $($script:KbTested.Count)/$($script:KbButtons.Count) phím"
        }
    }

    $ri = 0
    foreach ($row in $rows) {
        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Dock = [System.Windows.Forms.DockStyle]::Fill
        $flow.WrapContents = $false
        $flow.AutoScroll = $false
        $flow.BackColor = [System.Drawing.Color]::White
        $flow.Margin = New-Object System.Windows.Forms.Padding(0)
        $flow.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)

        foreach ($def in $row) {
            $button = New-Object System.Windows.Forms.Button
            $button.Text = $def.Label
            $button.Width = $def.Width
            $button.Height = 44
            $button.Margin = New-Object System.Windows.Forms.Padding(2)
            $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $button.BackColor = [System.Drawing.Color]::White
            $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(184, 196, 208)
            $button.FlatAppearance.BorderSize = 1
            $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(232, 243, 252)
            $button.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $button.UseMnemonic = $false
            $button.TabStop = $false
            $button.Cursor = [System.Windows.Forms.Cursors]::Hand
            $button.Tag = $def
            $button.Add_Click({
                    param($sender, $eventArgs)
                    $keyDef = $sender.Tag
                    & $script:KbMarkAction $keyDef.Id
                    if ($script:KbLastLabel) { $script:KbLastLabel.Text = "Đã đánh dấu: $($keyDef.Label)" }
                    if ($script:KeyboardForm) { $script:KeyboardForm.Focus() }
                })
            $flow.Controls.Add($button)
            $script:KbButtons[$def.Id] = $button
            foreach ($keyName in @($def.Keys)) {
                if ($keyName) { $script:KbKeyMap[[string]$keyName] = $def.Id }
            }
        }

        $table.Controls.Add($flow, 0, $ri)
        $ri++
    }

    $script:KeyboardForm.Add_KeyDown({
            $code = $_.KeyCode.ToString()
            if ($script:KbKeyMap.ContainsKey($code)) {
                $mappedId = $script:KbKeyMap[$code]
                & $script:KbMarkAction $mappedId
                if ($script:KbLastLabel -and $script:KbButtons[$mappedId]) {
                    $script:KbLastLabel.Text = "Phím vừa nhấn: $($script:KbButtons[$mappedId].Tag.Label)"
                }
            } elseif ($script:KbLastLabel) {
                $script:KbLastLabel.Text = "Phím vừa nhấn: $code"
            }
        })
    $script:KeyboardForm.Add_Shown({
            $script:KeyboardForm.Activate()
            $script:KeyboardForm.Focus()
        })
    $doneButton.Add_Click({ $script:KeyboardForm.Close() })
    $resetButton.Add_Click({
            $script:KbTested.Clear()
            foreach ($button in $script:KbButtons.Values) {
                $button.BackColor = [System.Drawing.Color]::White
                $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(184, 196, 208)
            }
            $script:KbStatusLabel.Text = "Đã test 0/$($script:KbButtons.Count) phím"
            $script:KbLastLabel.Text = 'Phím vừa nhấn: —'
            $script:KeyboardForm.Focus()
        })
    $script:KeyboardForm.Add_FormClosed({
            $allIds = @($script:KbButtons.Keys)
            $untested = @($allIds | Where-Object { -not $script:KbTested.ContainsKey($_) } | ForEach-Object { $script:KbButtons[$_].Tag.Label })
            $script:KeyboardTestResult = [pscustomobject]@{
                Total    = $allIds.Count
                Tested   = $script:KbTested.Count
                Untested = $untested
            }
        })

    $script:KbTimer = $null
    if ($AutoCloseSeconds -gt 0) {
        $script:KbTimer = New-Object System.Windows.Forms.Timer
        $script:KbTimer.Interval = $AutoCloseSeconds * 1000
        $script:KbTimer.Add_Tick({
                $script:KbTimer.Stop()
                $script:KeyboardForm.Close()
            })
        $script:KbTimer.Start()
    }

    try {
        [void]$script:KeyboardForm.ShowDialog()
    } finally {
        if ($script:KbTimer) {
            $script:KbTimer.Stop()
            $script:KbTimer.Dispose()
            $script:KbTimer = $null
        }
        if ($script:KeyboardForm) {
            $script:KeyboardForm.Dispose()
            $script:KeyboardForm = $null
        }
    }
}

function New-TestToneWav {
    param([string]$Path)
    $sampleRate = 22050
    $segments = @(
        [pscustomobject]@{ Duration = 0.9; Left = 880.0; Right = 880.0 }
    )
    $dataSize = 0
    foreach ($segment in $segments) { $dataSize += [int]($sampleRate * $segment.Duration) * 4 }

    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([int](36 + $dataSize))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
        $writer.Write([int]16)
        $writer.Write([int16]1)
        $writer.Write([int16]2)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]($sampleRate * 4))
        $writer.Write([int16]4)
        $writer.Write([int16]16)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([int]$dataSize)

        foreach ($segment in $segments) {
            $count = [int]($sampleRate * $segment.Duration)
            $fade = [Math]::Max(1, [int]($sampleRate * 0.02))
            for ($i = 0; $i -lt $count; $i++) {
                $time = $i / [double]$sampleRate
                $envelope = 1.0
                if ($i -lt $fade) { $envelope = $i / [double]$fade }
                elseif ($i -gt ($count - $fade)) { $envelope = ($count - $i) / [double]$fade }
                $left = 0.0
                $right = 0.0
                if ($segment.Left -gt 0) {
                    $left = [Math]::Sin(2 * [Math]::PI * $segment.Left * $time) * 0.28 * $envelope
                }
                if ($segment.Right -gt 0) {
                    $right = [Math]::Sin(2 * [Math]::PI * $segment.Right * $time) * 0.28 * $envelope
                }
                $writer.Write([int16][Math]::Round($left * 32767))
                $writer.Write([int16][Math]::Round($right * 32767))
            }
        }
        $writer.Flush()
        [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Invoke-SpeakerTest {
    $wavPath = Join-Path $script:AssetsDir 'test-loa-beep.wav'
    Write-Host '  Chuẩn bị phát 1 tiếng bíp qua loa...' -ForegroundColor Yellow
    Start-Sleep -Milliseconds 1200
    try {
        if (-not (Test-Path $wavPath)) { New-TestToneWav -Path $wavPath }
        $player = New-Object System.Media.SoundPlayer($wavPath)
        try { $player.PlaySync() } finally { $player.Dispose() }
        Write-Host '  Đã phát xong. Nếu nghe rõ tiếng bíp, chọn Đạt.' -ForegroundColor DarkGray
    } catch {
        Write-Host "  ! Không phát được tiếng bíp: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Invoke-MicrophoneTest {
    $opened = Start-InstalledApp -Pattern 'Sound Recorder|Voice Recorder|Ghi âm' -FallbackUri 'ms-settings:sound'
    if ($opened) {
        Write-Host '  Ứng dụng ghi âm đã mở. Hãy thu thử 5-10 giây và phát lại để nghe rõ tiếng.' -ForegroundColor Yellow
    } else {
        Write-Host '  Mở Sound Settings: chọn Input → Microphone → Test your microphone.' -ForegroundColor Yellow
    }
    Write-Host '  Nếu ứng dụng không thu được tiếng, kiểm tra Settings → Privacy → Microphone.' -ForegroundColor DarkGray
}

function Invoke-CameraTest {
    $opened = Start-InstalledApp -Pattern '^Camera$|Windows Camera|Máy ảnh' -FallbackUri 'ms-settings:privacy-webcam'
    if ($opened) {
        Write-Host '  Ứng dụng Camera đã mở. Kiểm tra hình ảnh, màu sắc, lấy nét và camera hồng ngoại (nếu có).' -ForegroundColor Yellow
    } else {
        Write-Host '  Không mở được Camera. Kiểm tra Settings → Privacy → Camera.' -ForegroundColor Yellow
    }
}

# =====================================================================
#  CHẠY KIỂM TRA TAY
# =====================================================================

$script:ManualResults = New-Object System.Collections.ArrayList
$script:GeneralNote = ''

function Add-ManualResult {
    param($Test, $No, [string]$Code, [string]$Note)
    [void]$script:ManualResults.Add([pscustomobject]@{
            No    = $No
            Id    = $Test.Id
            Name  = $Test.Name
            Code  = $Code
            Note  = $Note
        })
}

$touchpadDetection = Get-DeviceNames @($script:HwTouchpad + @($mice | Where-Object { $_.Name -match 'HID-compliant mouse' }))
$touchscreenDetection = Get-DeviceNames $script:HwTouchscreen
$cameraDetection = Get-DeviceNames $script:HwCamera
$fingerprintDetection = Get-DeviceNames $script:HwBiometric
$speakerDetection = if ($script:HwRender.Count -gt 0) { (@($script:HwRender | ForEach-Object { $_.Name }) -join '; ') } else { 'Không có thiết bị phát đang hoạt động' }
$micDetection = if ($script:HwCapture.Count -gt 0) { (@($script:HwCapture | ForEach-Object { $_.Name }) -join '; ') } else { 'Không có thiết bị thu đang hoạt động' }

$manualTests = @(
    [pscustomobject]@{
        Id              = 'appearance'
        Name            = 'Ngoại hình, tem máy & phụ kiện'
        Available       = $true
        Detection       = 'Kiểm tra bằng mắt'
        UnavailableNote = ''
        Steps           = @(
            'Kiểm tra vỏ máy, 4 góc, bản lề, khung màn hình: không nứt, trầy sâu, cong vênh.',
            'Đối chiếu tem serial trên thân máy với số serial trong báo cáo.',
            'Kiểm tra sạc, cáp nguồn, hộp và phụ kiện đi kèm (nếu có).',
            'Mở/đóng nắp máy, kiểm tra kê chân cao su và độ chắc của các cổng.'
        )
        Action          = $null
    },
    [pscustomobject]@{
        Id              = 'screen'
        Name            = 'Màn hình: điểm chết, màu sắc, độ sáng'
        Available       = $true
        Detection       = $script:MonitorSummary
        UnavailableNote = ''
        Steps           = @(
            'Cửa sổ test toàn màn hình sẽ mở với các màu đen, trắng, đỏ, xanh lá, xanh dương, xám.',
            'Nhấn Space / chạm / click trái để đổi màu. Nhấn H để ẩn/hiện dòng hướng dẫn.',
            'Quan sát điểm chết, điểm sáng, ám màu, vệt sáng, hở sáng ở viền và 4 góc.',
            'Nhấn Esc hoặc click chuột phải để thoát, sau đó quay lại cửa sổ PowerShell.'
        )
        Action          = { Show-ScreenTest }
    },
    [pscustomobject]@{
        Id              = 'touch'
        Name            = 'Màn hình cảm ứng / bút cảm ứng'
        Available       = (($script:HwTouchscreen.Count -gt 0) -or $AllTests)
        Detection       = $touchscreenDetection
        UnavailableNote = 'Không phát hiện màn hình cảm ứng.'
        Steps           = @(
            'Cửa sổ vẽ toàn màn hình sẽ mở. Dùng ngón tay hoặc bút vẽ lên vùng trắng.',
            'Thử vẽ ở 4 góc, sát viền và kéo dài liên tục để kiểm tra điểm đứt.',
            'Thử chạm nhiều ngón nếu máy hỗ trợ đa điểm.',
            'Nhấn XONG hoặc Esc để thoát; sau đó kiểm tra cài đặt bút cảm ứng vừa mở.'
        )
        Action          = { Show-TouchTest; Open-SettingsPage 'ms-settings:pen' | Out-Null }
    },
    [pscustomobject]@{
        Id              = 'touchpad'
        Name            = 'Touchpad & cử chỉ'
        Available       = (($script:IsLaptop) -or ($script:HwTouchpad.Count -gt 0) -or $AllTests)
        Detection       = $touchpadDetection
        UnavailableNote = 'Không phát hiện touchpad (máy để bàn).'
        Steps           = @(
            'Cài đặt Touchpad sẽ mở. Di chuyển con trỏ bằng touchpad, thử click trái/phải.',
            'Thử cuộn 2 ngón, zoom 2 ngón, vuốt 3 ngón (chuyển app/desktop), vuốt 4 ngón nếu có.',
            'Kiểm tra độ nhạy, hiện tượng nhảy con trỏ, vùng chết và phản hồi lực nhấn (nếu có).',
            'Đóng Settings và quay lại cửa sổ PowerShell để ghi kết quả.'
        )
        Action          = { Open-SettingsPage 'ms-settings:devices-touchpad' | Out-Null }
    },
    [pscustomobject]@{
        Id              = 'keyboard'
        Name            = 'Bàn phím'
        Available       = $true
        Detection       = (Get-DeviceNames $keyboards)
        UnavailableNote = ''
        Steps           = @(
            'Cửa sổ sơ đồ bàn phím sẽ mở. Nhấn thử từng phím trên bàn phím thật.',
            'Phím nào đã nhấn sẽ chuyển màu xanh; phím vừa nhấn hiện ở dòng trạng thái.',
            'Với phím đặc biệt như Fn, PrtSc, Pause hoặc phím không nhận được, có thể click lên phím trên hình để đánh dấu.',
            'Thử cả đèn nền bàn phím (Fn + phím đèn) nếu máy có, rồi nhấn XONG.'
        )
        Action          = { Show-KeyboardTest }
    },
    [pscustomobject]@{
        Id              = 'speakers'
        Name            = 'Loa ngoài'
        Available       = (($script:HwRender.Count -gt 0) -or $AllTests)
        Detection       = $speakerDetection
        UnavailableNote = 'Không có thiết bị phát âm thanh đang hoạt động.'
        Steps           = @(
            'Script sẽ phát 1 tiếng bíp ngắn qua loa.',
            'Tăng âm lượng vừa đủ nghe và kiểm tra xem có nghe thấy tiếng bíp không.',
            'Nếu không nghe thấy, kiểm tra âm lượng, chế độ im lặng và thiết bị phát mặc định.'
        )
        Action          = { Invoke-SpeakerTest }
    },
    [pscustomobject]@{
        Id              = 'microphone'
        Name            = 'Microphone & ghi âm'
        Available       = (($script:HwCapture.Count -gt 0) -or $AllTests)
        Detection       = $micDetection
        UnavailableNote = 'Không có micro đang hoạt động.'
        Steps           = @(
            'Ứng dụng ghi âm sẽ mở. Thu thử 5-10 giây, nói to/nhỏ và phát lại.',
            'Kiểm tra tiếng rè, tạp âm, âm lượng và khả năng thu âm thanh hai bên.',
            'Nếu không thu được, kiểm tra quyền Micro trong Settings → Privacy & security.',
            'Đóng ứng dụng và quay lại PowerShell để ghi kết quả.'
        )
        Action          = { Invoke-MicrophoneTest }
    },
    [pscustomobject]@{
        Id              = 'camera'
        Name            = 'Webcam'
        Available       = (($script:HwCamera.Count -gt 0) -or $AllTests)
        Detection       = $cameraDetection
        UnavailableNote = 'Không phát hiện camera.'
        Steps           = @(
            'Ứng dụng Camera sẽ mở. Kiểm tra hình ảnh, màu sắc, độ nét, lấy nét gần/xa.',
            'Che camera để kiểm tra cảm biến sáng, thử camera hồng ngoại/Windows Hello nếu có.',
            'Kiểm tra quyền Camera trong Settings → Privacy & security nếu ứng dụng không lên hình.'
        )
        Action          = { Invoke-CameraTest }
    },
    [pscustomobject]@{
        Id              = 'charging'
        Name            = 'Sạc, pin & nguồn'
        Available       = $script:HwHasBattery
        Detection       = $script:BatterySummary
        UnavailableNote = 'Không phát hiện pin.'
        Steps           = @(
            'Kiểm tra sạc đang cắm, đèn báo sạc và mức pin hiện tại.',
            'Rút sạc, quan sát pin chuyển sang trạng thái dùng pin; cắm lại, kiểm tra báo đang sạc.',
            'Lắc nhẹ đầu cắm và cáp để phát hiện tiếp xúc chập chờn.',
            'Kiểm tra nhiệt độ, tiếng quạt và khả năng giữ pin trong vài phút.'
        )
        Action          = { Open-SettingsPage 'ms-settings:batterysaver' | Out-Null }
    },
    [pscustomobject]@{
        Id              = 'fingerprint'
        Name            = 'Cảm biến vân tay / Windows Hello'
        Available       = (($script:HwBiometric.Count -gt 0) -or $AllTests)
        Detection       = $fingerprintDetection
        UnavailableNote = 'Không phát hiện cảm biến vân tay/Windows Hello.'
        Steps           = @(
            'Cài đặt Sign-in options sẽ mở. Kiểm tra cảm biến vân tay hoặc nhận diện khuôn mặt.',
            'Thử đăng ký/đăng nhập bằng Windows Hello nếu đã thiết lập.',
            'Kiểm tra độ nhạy, tốc độ nhận và trường hợp nhận sai.'
        )
        Action          = { Open-SettingsPage 'ms-settings:signinoptions' | Out-Null }
    }
)

if (-not $FullManual) {
    $selectedTests = @()
    foreach ($testId in @('speakers', 'microphone', 'camera', 'keyboard')) {
        $selectedTests += @($manualTests | Where-Object { $_.Id -eq $testId })
    }
    $manualTests = $selectedTests
}

$manualSectionTitle = 'Kết quả kiểm tra tay'
$manualCardLabel = 'Kiểm tra tay'
$totalAvailable = @($manualTests | Where-Object { $_.Available }).Count

if (-not $SkipManual -and $totalAvailable -gt 0) {
    Write-Host ''
    Write-Host '==================================================================' -ForegroundColor Yellow
    Write-Host '                    BẮT ĐẦU KIỂM TRA TAY' -ForegroundColor Yellow
    Write-Host '==================================================================' -ForegroundColor Yellow
    if ($FullManual) {
        Write-Host 'Mỗi hạng mục sẽ tự mở công cụ/cài đặt liên quan.' -ForegroundColor White
        Write-Host 'Sau khi test xong, quay lại PowerShell và nhập 1/2/0/q.' -ForegroundColor White
    } else {
        Write-Host 'Sẽ test tay: loa, mic, camera và bàn phím.' -ForegroundColor White
        Write-Host 'Mỗi mục tự mở công cụ; sau khi test nhập 1/2/0/q.' -ForegroundColor White
    }
    Write-Host '  [1] Đạt   [2] Không đạt   [0] Bỏ qua   [q] Dừng phần test tay' -ForegroundColor DarkGray
    [void](Read-Host 'Nhấn Enter để bắt đầu...')
}

$runIndex = 0
$aborted = $false

foreach ($test in $manualTests) {
    if (-not $test.Available) {
        Add-ManualResult -Test $test -No '—' -Code 'na' -Note $test.UnavailableNote
        continue
    }

    $runIndex++

    if ($SkipManual) {
        Add-ManualResult -Test $test -No $runIndex -Code 'untested' -Note 'Bỏ qua kiểm tra tay (--SkipManual).'
        continue
    }
    if ($aborted) {
        Add-ManualResult -Test $test -No $runIndex -Code 'untested' -Note 'Đã dừng phần kiểm tra tay.'
        continue
    }

    Write-Host ''
    Write-Host "[$runIndex/$totalAvailable] $($test.Name)" -ForegroundColor Cyan
    if ($test.Detection) { Write-Host "  Phát hiện: $($test.Detection)" -ForegroundColor DarkGray }
    foreach ($step in $test.Steps) {
        Write-Host "  - $step" -ForegroundColor Gray
    }
    $autoNote = ''
    if ($test.Action -and $env:KIEMTRA_SKIP_ACTIONS -ne '1') {
        try {
            & $test.Action
            if ($test.Id -eq 'keyboard' -and $script:KeyboardTestResult) {
                $kb = $script:KeyboardTestResult
                Write-Host "  Đã test $($kb.Tested)/$($kb.Total) phím." -ForegroundColor DarkGreen
                if ($kb.Untested.Count -gt 0) {
                    $previewList = @($kb.Untested | Select-Object -First 12)
                    $preview = $previewList -join ', '
                    if ($kb.Untested.Count -gt 12) {
                        $preview += " ... (+$($kb.Untested.Count - 12))"
                    }
                    Write-Host "  Chưa test: $preview" -ForegroundColor Yellow
                    $autoNote = "Đã test $($kb.Tested)/$($kb.Total) phím; chưa test: $preview"
                } else {
                    $autoNote = "Đã test đủ $($kb.Tested)/$($kb.Total) phím"
                }
            }
        } catch {
            Write-Host "  ! Không mở được công cụ test: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $status = ''
    while (-not $status) {
        $answer = Read-Host '  Kết quả [1] Đạt  [2] Không đạt  [0] Bỏ qua  [q] Dừng'
        switch ($answer.Trim().ToLower()) {
            '1' { $status = 'pass' }
            '2' { $status = 'fail' }
            '0' { $status = 'skip' }
            'q' { $status = 'quit' }
            default { Write-Host '  Vui lòng nhập 1, 2, 0 hoặc q.' -ForegroundColor Yellow }
        }
    }

    if ($status -eq 'quit') {
        Add-ManualResult -Test $test -No $runIndex -Code 'untested' -Note 'Người kiểm tra dừng tại hạng mục này.'
        Write-Host '  Đã dừng phần kiểm tra tay.' -ForegroundColor Yellow
        $aborted = $true
        continue
    }

    $note = (Read-Host '  Ghi chú tình trạng (Enter = không có)').Trim()
    if ($autoNote) {
        if ($note) { $note = "$note | $autoNote" } else { $note = $autoNote }
    }
    Add-ManualResult -Test $test -No $runIndex -Code $status -Note $note

    $color = switch ($status) {
        'pass' { 'Green' }
        'fail' { 'Red' }
        default { 'DarkGray' }
    }
    $label = switch ($status) {
        'pass' { 'ĐẠT' }
        'fail' { 'KHÔNG ĐẠT' }
        default { 'BỎ QUA' }
    }
    Write-Host "  -> $label" -ForegroundColor $color
}

if (-not $SkipManual -and $totalAvailable -gt 1) {
    $script:GeneralNote = (Read-Host 'Ghi chú tổng thể / tình trạng chung của máy (Enter = bỏ trống)').Trim()
}

$script:FinishedAt = Get-Date

# =====================================================================
#  TỔNG HỢP KẾT QUẢ
# =====================================================================

$passCount = @($script:ManualResults | Where-Object { $_.Code -eq 'pass' }).Count
$failCount = @($script:ManualResults | Where-Object { $_.Code -eq 'fail' }).Count
$skipCount = @($script:ManualResults | Where-Object { $_.Code -eq 'skip' }).Count
$untestedCount = @($script:ManualResults | Where-Object { $_.Code -eq 'untested' }).Count
$naCount = @($script:ManualResults | Where-Object { $_.Code -eq 'na' }).Count
$testedCount = $passCount + $failCount + $skipCount + $untestedCount

$sortedWarnings = @($script:Warnings | Sort-Object @{ Expression = {
                switch ($_.Level) {
                    'Cao' { 1 }
                    'Trung bình' { 2 }
                    'Thấp' { 3 }
                    default { 4 }
                }
            }
        })

if ($failCount -gt 0) {
    $verdictText = 'KHÔNG ĐẠT'
    $verdictClass = 'bad'
    $verdictDetail = "$failCount hạng mục kiểm tra không đạt, cần xử lý trước khi bàn giao."
} elseif ($untestedCount -gt 0 -or $skipCount -gt 0) {
    $verdictText = 'CHƯA HOÀN TẤT'
    $verdictClass = 'warn'
    $verdictDetail = "Còn $($untestedCount + $skipCount) hạng mục chưa test hoặc bị bỏ qua."
} elseif ($sortedWarnings.Count -gt 0) {
    $verdictText = 'CẦN LƯU Ý'
    $verdictClass = 'warn'
    $verdictDetail = "$($sortedWarnings.Count) cảnh báo tự động cần được xem lại."
} else {
    $verdictText = 'ĐẠT'
    $verdictClass = 'ok'
    $verdictDetail = 'Tất cả hạng mục kiểm tra đều đạt, không có cảnh báo tự động.'
}

$testSummary = if ($testedCount -eq 0) {
    'Chưa có bài test'
} elseif ($untestedCount -eq $testedCount) {
    "Chưa test ($testedCount mục)"
} elseif ($failCount -eq 0 -and $skipCount -eq 0) {
    "$passCount/$testedCount đạt"
} else {
    $testParts = @()
    if ($passCount -gt 0) { $testParts += "$passCount đạt" }
    if ($failCount -gt 0) { $testParts += "$failCount lỗi" }
    if ($skipCount -gt 0) { $testParts += "$skipCount bỏ qua" }
    if ($untestedCount -gt 0) { $testParts += "$untestedCount chưa test" }
    $testParts -join ' • '
}
$warningSummary = if ($sortedWarnings.Count -eq 0) { 'Không có' } else { "$($sortedWarnings.Count) mục" }
$wifiPresence = if ($wifiAdapters.Count -gt 0) { 'Có' } else { 'Không' }
$bluetoothPresence = if ($bluetoothRadios.Count -gt 0) { 'Có' } else { 'Không' }

$summaryCards = @(
    [pscustomobject]@{ Label = 'Máy'; Value = $summaryModel },
    [pscustomobject]@{ Label = 'Serial'; Value = $summarySerial },
    [pscustomobject]@{ Label = 'Windows'; Value = "$($osCaption -replace '^Microsoft\s+', '') $displayVersion • $licenseText" },
    [pscustomobject]@{ Label = 'CPU'; Value = $summaryCpu },
    [pscustomobject]@{ Label = 'RAM'; Value = $summaryRam },
    [pscustomobject]@{ Label = 'Lưu trữ'; Value = $storageSummary },
    [pscustomobject]@{ Label = 'GPU'; Value = $gpuSummary },
    [pscustomobject]@{ Label = 'Màn hình'; Value = $displaySummary },
    [pscustomobject]@{ Label = 'Pin'; Value = $script:BatterySummary },
    [pscustomobject]@{ Label = 'Bảo mật'; Value = $securitySummary },
    [pscustomobject]@{ Label = 'Wi-Fi'; Value = $wifiPresence },
    [pscustomobject]@{ Label = 'Bluetooth'; Value = $bluetoothPresence },
    [pscustomobject]@{ Label = $manualCardLabel; Value = $testSummary },
    [pscustomobject]@{ Label = 'Cảnh báo'; Value = $warningSummary }
)

$adminNote = ''
if (-not $script:IsAdmin) {
    $adminNote = 'Script không chạy bằng quyền Administrator nên một số thông tin như TPM, SMART và BitLocker có thể chưa đọc được. Nên chạy lại bằng Administrator để báo cáo đầy đủ hơn.'
}

$metaRows = [ordered]@{
    'Người kiểm tra'       = $Technician
    'Khách hàng / mã đơn'  = $(if ($Customer) { $Customer } else { '—' })
    'Bắt đầu'              = $script:StartedAt.ToString('dd/MM/yyyy HH:mm:ss')
    'Kết thúc'             = $script:FinishedAt.ToString('dd/MM/yyyy HH:mm:ss')
    'Thời lượng'           = (Format-Duration ($script:FinishedAt - $script:StartedAt))
    'Quyền Administrator'  = $(if ($script:IsAdmin) { 'Có' } else { 'Không' })
    'Phiên bản script'     = "KiemTraMayMoi.ps1 v$script:Version"
}

function Get-ManualStatusMeta {
    param([string]$Code)
    switch ($Code) {
        'pass' { return [pscustomobject]@{ Label = 'Đạt'; Css = 'ok'; Icon = '✅' } }
        'fail' { return [pscustomobject]@{ Label = 'Không đạt'; Css = 'bad'; Icon = '❌' } }
        'skip' { return [pscustomobject]@{ Label = 'Bỏ qua'; Css = 'info'; Icon = '⏭️' } }
        'untested' { return [pscustomobject]@{ Label = 'Chưa test'; Css = 'warn'; Icon = '⏳' } }
        'na' { return [pscustomobject]@{ Label = 'Không có'; Css = 'na'; Icon = '➖' } }
        default { return [pscustomobject]@{ Label = 'Không rõ'; Css = 'na'; Icon = '?' } }
    }
}

function Get-WarningClass {
    param([string]$Level)
    switch ($Level) {
        'Cao' { return 'bad' }
        'Trung bình' { return 'warn' }
        'Thấp' { return 'info' }
        default { return 'na' }
    }
}

function Render-MarkdownReport {
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# BÁO CÁO KIỂM TRA MÁY MỚI')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("> **Kết luận: $verdictText** — $verdictDetail")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## Thông tin buổi kiểm tra')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| Thông tin | Giá trị |')
    [void]$md.AppendLine('|---|---|')
    foreach ($key in $metaRows.Keys) {
        [void]$md.AppendLine("| **$(ConvertTo-MdCell $key)** | $(ConvertTo-MdCell $metaRows[$key]) |")
    }
    [void]$md.AppendLine('')
    if ($adminNote) {
        [void]$md.AppendLine("> **Lưu ý:** $adminNote")
        [void]$md.AppendLine('')
    }
    [void]$md.AppendLine('## Tóm tắt nhanh')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| Hạng mục | Thông tin |')
    [void]$md.AppendLine('|---|---|')
    foreach ($card in $summaryCards) {
        [void]$md.AppendLine("| **$(ConvertTo-MdCell $card.Label)** | $(ConvertTo-MdCell $card.Value) |")
    }
    [void]$md.AppendLine('')

    if ($script:Attachments.Count -gt 0) {
        [void]$md.AppendLine('### Tệp đính kèm')
        [void]$md.AppendLine('')
        foreach ($attachment in $script:Attachments) {
            [void]$md.AppendLine("- [$(ConvertTo-MdCell $attachment.Label)]($($attachment.File))")
        }
        [void]$md.AppendLine('')
    }

    [void]$md.AppendLine("## 1. $manualSectionTitle")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| # | Hạng mục | Kết quả | Ghi chú |')
    [void]$md.AppendLine('|---:|---|---|---|')
    foreach ($result in $script:ManualResults) {
        $status = Get-ManualStatusMeta $result.Code
        [void]$md.AppendLine("| $(ConvertTo-MdCell $result.No) | $(ConvertTo-MdCell $result.Name) | $($status.Icon) $(ConvertTo-MdCell $status.Label) | $(ConvertTo-MdCell $result.Note) |")
    }
    [void]$md.AppendLine('')

    if ($script:GeneralNote) {
        [void]$md.AppendLine('**Ghi chú tổng thể:** ' + (ConvertTo-MdCell $script:GeneralNote))
        [void]$md.AppendLine('')
    }

    [void]$md.AppendLine('## 2. Cảnh báo tự động')
    [void]$md.AppendLine('')
    if ($sortedWarnings.Count -eq 0) {
        [void]$md.AppendLine('Không phát hiện cảnh báo tự động.')
    } else {
        [void]$md.AppendLine('| Mức độ | Nội dung |')
        [void]$md.AppendLine('|---|---|')
        foreach ($warning in $sortedWarnings) {
            [void]$md.AppendLine("| **$(ConvertTo-MdCell $warning.Level)** | $(ConvertTo-MdCell $warning.Text) |")
        }
    }
    [void]$md.AppendLine('')

    $sectionNo = 2
    foreach ($section in $script:Sections) {
        $sectionNo++
        [void]$md.AppendLine("## $sectionNo. $($section.Title)")
        [void]$md.AppendLine('')
        if ($section.Info.Count -gt 0) {
            [void]$md.AppendLine('| Thông tin | Giá trị |')
            [void]$md.AppendLine('|---|---|')
            foreach ($key in $section.Info.Keys) {
                [void]$md.AppendLine("| **$(ConvertTo-MdCell $key)** | $(ConvertTo-MdCell $section.Info[$key]) |")
            }
            [void]$md.AppendLine('')
        }
        foreach ($table in $section.Tables) {
            [void]$md.AppendLine("### $($table.Title)")
            [void]$md.AppendLine('')
            if ($table.Rows.Count -eq 0) {
                [void]$md.AppendLine('*Không có dữ liệu.*')
                [void]$md.AppendLine('')
                continue
            }
            $header = ($table.Columns | ForEach-Object { ConvertTo-MdCell $_ }) -join ' | '
            $separator = ($table.Columns | ForEach-Object { '---' }) -join ' | '
            [void]$md.AppendLine("| $header |")
            [void]$md.AppendLine("| $separator |")
            foreach ($row in $table.Rows) {
                $cells = @($row | ForEach-Object { ConvertTo-MdCell $_ })
                [void]$md.AppendLine("| $($cells -join ' | ') |")
            }
            [void]$md.AppendLine('')
        }
    }

    [void]$md.AppendLine('---')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("*Báo cáo được tạo tự động bởi KiemTraMayMoi.ps1 v$script:Version — $($script:FinishedAt.ToString('dd/MM/yyyy HH:mm:ss'))*")
    return $md.ToString()
}

function Render-HtmlReport {
    $css = @'
:root{
  --bg:#eef2f7;--card:#ffffff;--ink:#1e293b;--muted:#64748b;--line:#dbe3ec;
  --brand:#0b4f7a;--brand2:#1b7fb5;--ok:#16794a;--ok-bg:#e5f7ee;
  --bad:#b42318;--bad-bg:#feeceb;--warn:#9a6700;--warn-bg:#fff4d6;
  --info:#335c81;--info-bg:#e8f0f8;--na:#6b7280;--na-bg:#f1f5f9;
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{
  margin:0;background:var(--bg);color:var(--ink);line-height:1.55;
  font-family:"Segoe UI","Helvetica Neue",Arial,sans-serif;font-size:15px;
}
.wrap{max-width:1320px;margin:0 auto;padding:0 22px}
.hero{
  background:linear-gradient(135deg,#08324f 0%,#0b4f7a 55%,#1b7fb5 100%);
  color:#fff;padding:34px 0 30px;box-shadow:0 8px 24px rgba(8,50,79,.18);
}
.hero-inner{display:flex;gap:24px;align-items:center;justify-content:space-between;flex-wrap:wrap}
.kicker{font-size:12px;letter-spacing:1.6px;text-transform:uppercase;color:#c9e6f7;font-weight:700}
.hero h1{margin:8px 0 8px;font-size:31px;line-height:1.2;font-weight:700}
.hero-sub{color:#d7ecfa;font-size:14px}
.verdict{
  font-size:20px;font-weight:800;letter-spacing:.6px;padding:14px 26px;border-radius:10px;
  border:1px solid rgba(255,255,255,.35);background:rgba(255,255,255,.12);white-space:nowrap;
}
.verdict.ok{background:#d9fbe8;color:#0d5c38;border-color:#a9edc7}
.verdict.bad{background:#ffe1df;color:#8f1d14;border-color:#ffc2bd}
.verdict.warn{background:#fff0c2;color:#7a5000;border-color:#f5d77b}
main{padding-top:26px;padding-bottom:40px}
.layout{display:grid;grid-template-columns:240px minmax(0,1fr);gap:22px;align-items:start}
.content{min-width:0}
.sidebar{
  position:sticky;top:20px;align-self:start;background:var(--card);border:1px solid var(--line);
  border-radius:12px;padding:16px;box-shadow:0 1px 2px rgba(15,23,42,.04);
  max-height:calc(100vh - 40px);overflow:auto;
}
.sidebar-title{font-size:12px;font-weight:800;letter-spacing:1.2px;text-transform:uppercase;color:var(--brand);border-bottom:2px solid #e8f1f8;padding-bottom:8px;margin-bottom:8px}
.side-nav{display:flex;flex-direction:column;gap:2px}
.side-nav a{display:block;padding:6px 8px;border-radius:6px;color:#335c81;text-decoration:none;font-size:13px;line-height:1.35}
.side-nav a:hover{background:#edf5fb;color:#0b4f7a}
.back-top{display:inline-block;margin-top:10px;padding:6px 8px;color:var(--muted);font-size:12px;text-decoration:none;border-top:1px solid var(--line);width:100%}
.back-top:hover{color:var(--brand)}
.overview-note{margin:-4px 0 12px;font-size:13px}
table.overview-table th{width:14%;background:#f8fafc;color:#3d556b;font-weight:600;border-right:1px solid #edf2f7}
table.overview-table td{width:36%}
table.overview-table td:empty{background:#fbfdff}
.panel{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:20px 22px;margin-bottom:20px;box-shadow:0 1px 2px rgba(15,23,42,.04)}
.panel h2{margin:0 0 14px;font-size:20px;color:var(--brand);border-bottom:2px solid #e8f1f8;padding-bottom:9px}
.panel h3{margin:20px 0 10px;font-size:15px;color:#24425c}
.muted{color:var(--muted)}
table{width:100%;border-collapse:collapse;background:#fff;font-size:13.5px;margin:4px 0 8px}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top;overflow-wrap:anywhere}
thead th{background:#f3f7fb;color:#334e68;font-size:12px;letter-spacing:.3px;text-transform:uppercase}
table.kv th{width:30%;background:#f8fafc;color:#3d556b;font-weight:600}
tbody tr:nth-child(even){background:#fbfdff}
tbody tr:last-child td,tbody tr:last-child th{border-bottom:none}
.badge{display:inline-block;padding:2px 9px;border-radius:999px;font-size:12px;font-weight:700;white-space:nowrap}
.badge.ok{background:var(--ok-bg);color:var(--ok)}
.badge.bad{background:var(--bad-bg);color:var(--bad)}
.badge.warn{background:var(--warn-bg);color:var(--warn)}
.badge.info{background:var(--info-bg);color:var(--info)}
.badge.na{background:var(--na-bg);color:var(--na)}
.num{color:var(--muted);text-align:right;white-space:nowrap}
.note-box{background:#f8fafc;border-left:4px solid var(--brand2);padding:12px 15px;border-radius:0 8px 8px 0;margin:10px 0}
footer{color:var(--muted);font-size:12.5px;text-align:center;padding:14px 0 4px}
@media (max-width:980px){
  .layout{grid-template-columns:1fr}
  .sidebar{position:static;max-height:none;padding:12px 14px}
  .side-nav{flex-direction:row;flex-wrap:wrap;gap:4px}
  .side-nav a{background:#f6fafd;border:1px solid #e5eef6;padding:5px 8px}
  .back-top{margin-top:8px;border-top:none;width:auto;padding-left:0}
}
@media (max-width:900px){.hero h1{font-size:25px}table.overview-table th{width:20%}table.overview-table td{width:30%}}
@media (max-width:560px){.wrap{padding:0 14px}.panel{padding:15px}table.overview-table th{width:28%}table.overview-table td{width:22%}}
@media print{
  @page{size:A4;margin:12mm}
  body{background:#fff;font-size:10.5px}
  .hero{box-shadow:none;padding:20px 0}
  .verdict{font-size:15px;padding:8px 14px}
  .panel{box-shadow:none;break-inside:avoid;page-break-inside:avoid;padding:12px}
  .layout{display:block}
  .sidebar{display:none}
  table{font-size:9.5px}
  th,td{padding:4px 6px}
  a{text-decoration:none;color:inherit}
}
'@

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="vi">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine("<title>Báo cáo kiểm tra máy - $(ConvertTo-HtmlText $script:ComputerName)</title>")
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine($css)
    [void]$sb.AppendLine('</style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body id="top">')

    [void]$sb.AppendLine('<header class="hero">')
    [void]$sb.AppendLine('<div class="wrap hero-inner">')
    [void]$sb.AppendLine('<div>')
    [void]$sb.AppendLine('<div class="kicker">Báo cáo kiểm tra máy mới</div>')
    [void]$sb.AppendLine("<h1>$(ConvertTo-HtmlText $summaryModel)</h1>")
    [void]$sb.AppendLine("<div class=""hero-sub"">Serial: $(ConvertTo-HtmlText $summarySerial) &nbsp;•&nbsp; Máy: $(ConvertTo-HtmlText $script:ComputerName) &nbsp;•&nbsp; $($script:FinishedAt.ToString('dd/MM/yyyy HH:mm'))</div>")
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine("<div class=""verdict $verdictClass"">$(ConvertTo-HtmlText $verdictText)</div>")
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</header>')

    $tocItems = @(
        '<a href="#overview">Thông tin chung</a>',
        ('<a href="#manual">1. ' + (ConvertTo-HtmlText $manualSectionTitle) + '</a>'),
        '<a href="#warnings">2. Cảnh báo tự động</a>'
    )
    $tocSectionNo = 2
    foreach ($section in $script:Sections) {
        $tocSectionNo++
        $tocItems += ('<a href="#sec-' + $tocSectionNo + '">' + $tocSectionNo + '. ' + (ConvertTo-HtmlText $section.Title) + '</a>')
    }

    [void]$sb.AppendLine('<main>')
    [void]$sb.AppendLine('<div class="layout wrap">')
    [void]$sb.AppendLine('<aside class="sidebar" aria-label="Mục lục">')
    [void]$sb.AppendLine('<div class="sidebar-title">Mục lục</div>')
    [void]$sb.AppendLine('<nav class="side-nav">')
    foreach ($tocItem in $tocItems) {
        [void]$sb.AppendLine($tocItem)
    }
    [void]$sb.AppendLine('</nav>')
    [void]$sb.AppendLine('<a class="back-top" href="#top">↑ Về đầu trang</a>')
    [void]$sb.AppendLine('</aside>')
    [void]$sb.AppendLine('<div class="content">')

    $overviewItems = New-Object System.Collections.ArrayList
    foreach ($card in $summaryCards) {
        [void]$overviewItems.Add([pscustomobject]@{ Label = $card.Label; Value = $card.Value })
    }
    foreach ($key in $metaRows.Keys) {
        if ($key -eq 'Khách hàng / mã đơn') { continue }
        [void]$overviewItems.Add([pscustomobject]@{ Label = $key; Value = $metaRows[$key] })
    }
    [void]$overviewItems.Add([pscustomobject]@{ Label = 'Kết luận'; Value = $verdictText })

    [void]$sb.AppendLine('<section class="panel" id="overview">')
    [void]$sb.AppendLine('<h2>Thông tin chung</h2>')
    [void]$sb.AppendLine('<p class="muted overview-note">Thông tin sơ bộ về máy trước khi xem các mục chi tiết bên dưới.</p>')
    [void]$sb.AppendLine('<table class="overview-table"><tbody>')
    for ($i = 0; $i -lt $overviewItems.Count; $i += 2) {
        $left = $overviewItems[$i]
        $right = $null
        if (($i + 1) -lt $overviewItems.Count) { $right = $overviewItems[$i + 1] }
        if ($right) {
            [void]$sb.AppendLine("<tr><th>$(ConvertTo-HtmlText $left.Label)</th><td>$(ConvertTo-HtmlText $left.Value)</td><th>$(ConvertTo-HtmlText $right.Label)</th><td>$(ConvertTo-HtmlText $right.Value)</td></tr>")
        } else {
            [void]$sb.AppendLine("<tr><th>$(ConvertTo-HtmlText $left.Label)</th><td colspan=""3"">$(ConvertTo-HtmlText $left.Value)</td></tr>")
        }
    }
    [void]$sb.AppendLine('</tbody></table>')
    [void]$sb.AppendLine("<div class=""note-box""><strong>Kết luận:</strong> $(ConvertTo-HtmlText $verdictText) — $(ConvertTo-HtmlText $verdictDetail)</div>")
    if ($adminNote) {
        [void]$sb.AppendLine("<div class=""note-box""><strong>Lưu ý:</strong> $(ConvertTo-HtmlText $adminNote)</div>")
    }
    [void]$sb.AppendLine('</section>')

    if ($script:GeneralNote) {
        [void]$sb.AppendLine('<section class="panel">')
        [void]$sb.AppendLine('<h2>Ghi chú tổng thể</h2>')
        [void]$sb.AppendLine("<p>$(ConvertTo-HtmlText $script:GeneralNote)</p>")
        [void]$sb.AppendLine('</section>')
    }

    [void]$sb.AppendLine('<section class="panel" id="manual">')
    [void]$sb.AppendLine("<h2>1. $(ConvertTo-HtmlText $manualSectionTitle)</h2>")
    [void]$sb.AppendLine('<table class="data"><thead><tr><th>#</th><th>Hạng mục</th><th>Kết quả</th><th>Ghi chú</th></tr></thead><tbody>')
    foreach ($result in $script:ManualResults) {
        $status = Get-ManualStatusMeta $result.Code
        [void]$sb.AppendLine("<tr><td class=""num"">$(ConvertTo-HtmlText $result.No)</td><td>$(ConvertTo-HtmlText $result.Name)</td><td><span class=""badge $($status.Css)"">$(ConvertTo-HtmlText $status.Label)</span></td><td>$(ConvertTo-HtmlText $result.Note)</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table>')
    [void]$sb.AppendLine('</section>')

    [void]$sb.AppendLine('<section class="panel" id="warnings">')
    [void]$sb.AppendLine('<h2>2. Cảnh báo tự động</h2>')
    if ($sortedWarnings.Count -eq 0) {
        [void]$sb.AppendLine('<p class="muted">Không phát hiện cảnh báo tự động.</p>')
    } else {
        [void]$sb.AppendLine('<table class="data"><thead><tr><th>Mức độ</th><th>Nội dung</th></tr></thead><tbody>')
        foreach ($warning in $sortedWarnings) {
            $cssClass = Get-WarningClass $warning.Level
            [void]$sb.AppendLine("<tr><td><span class=""badge $cssClass"">$(ConvertTo-HtmlText $warning.Level)</span></td><td>$(ConvertTo-HtmlText $warning.Text)</td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table>')
    }
    [void]$sb.AppendLine('</section>')

    $sectionNo = 2
    foreach ($section in $script:Sections) {
        $sectionNo++
        [void]$sb.AppendLine("<section class=""panel"" id=""sec-$sectionNo"">")
        [void]$sb.AppendLine("<h2>$sectionNo. $(ConvertTo-HtmlText $section.Title)</h2>")
        if ($section.Info.Count -gt 0) {
            [void]$sb.AppendLine('<table class="kv"><tbody>')
            foreach ($key in $section.Info.Keys) {
                [void]$sb.AppendLine("<tr><th>$(ConvertTo-HtmlText $key)</th><td>$(ConvertTo-HtmlText $section.Info[$key])</td></tr>")
            }
            [void]$sb.AppendLine('</tbody></table>')
        }
        foreach ($table in $section.Tables) {
            [void]$sb.AppendLine("<h3>$(ConvertTo-HtmlText $table.Title)</h3>")
            if ($table.Rows.Count -eq 0) {
                [void]$sb.AppendLine('<p class="muted">Không có dữ liệu.</p>')
                continue
            }
            [void]$sb.AppendLine('<table class="data"><thead><tr>')
            foreach ($column in $table.Columns) {
                [void]$sb.AppendLine("<th>$(ConvertTo-HtmlText $column)</th>")
            }
            [void]$sb.AppendLine('</tr></thead><tbody>')
            foreach ($row in $table.Rows) {
                [void]$sb.AppendLine('<tr>')
                foreach ($cell in $row) {
                    [void]$sb.AppendLine("<td>$(ConvertTo-HtmlText $cell)</td>")
                }
                [void]$sb.AppendLine('</tr>')
            }
            [void]$sb.AppendLine('</tbody></table>')
        }
        [void]$sb.AppendLine('</section>')
    }

    [void]$sb.AppendLine("<footer>Báo cáo được tạo tự động bởi KiemTraMayMoi.ps1 v$script:Version — $($script:FinishedAt.ToString('dd/MM/yyyy HH:mm:ss'))</footer>")
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</main>')
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')
    return $sb.ToString()
}

# =====================================================================
#  XUẤT BÁO CÁO
# =====================================================================

$mdPath = Join-Path $script:ReportDir "BaoCao_KiemTra_$($script:ComputerName)_$stamp.md"
$htmlPath = Join-Path $script:ReportDir "BaoCao_KiemTra_$($script:ComputerName)_$stamp.html"

$markdown = Render-MarkdownReport
$html = Render-HtmlReport

[System.IO.File]::WriteAllText($mdPath, $markdown, (New-Object System.Text.UTF8Encoding($true)))
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Green
Write-Host '                     ĐÃ TẠO BÁO CÁO XONG' -ForegroundColor Green
Write-Host '==================================================================' -ForegroundColor Green
Write-Host "Kết luận: $verdictText - $verdictDetail" -ForegroundColor $(switch ($verdictClass) { 'ok' { 'Green' } 'bad' { 'Red' } default { 'Yellow' } })
Write-Host "Kiểm tra tay: $testSummary" -ForegroundColor White
Write-Host "Cảnh báo tự động: $warningSummary" -ForegroundColor White

$failedItems = @($script:ManualResults | Where-Object { $_.Code -eq 'fail' })
if ($failedItems.Count -gt 0) {
    Write-Host 'Hạng mục không đạt:' -ForegroundColor Red
    foreach ($item in $failedItems) { Write-Host "  - $($item.Name)" -ForegroundColor Red }
}
if ($sortedWarnings.Count -gt 0) {
    Write-Host 'Cảnh báo chính:' -ForegroundColor Yellow
    foreach ($warning in @($sortedWarnings | Select-Object -First 6)) {
        Write-Host "  - [$($warning.Level)] $($warning.Text)" -ForegroundColor Yellow
    }
}
Write-Host ''
Write-Host "Markdown : $mdPath" -ForegroundColor Cyan
Write-Host "HTML     : $htmlPath" -ForegroundColor Cyan
if ($script:Attachments.Count -gt 0) {
    foreach ($attachment in $script:Attachments) {
        Write-Host "Đính kèm : $(Join-Path $script:ReportDir $attachment.File)" -ForegroundColor DarkCyan
    }
}
Write-Host ''

if (-not $NoOpen) {
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$htmlPath`"" -ErrorAction Stop
    } catch {
        try { Start-Process -FilePath $htmlPath -ErrorAction Stop } catch { }
    }
}

if (-not $SkipManual) {
    [void](Read-Host 'Nhấn Enter để đóng cửa sổ...')
}
