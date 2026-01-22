# ==========================================================
# NDv2 - Windows Multi-Tor IP Rotation
# Author: Christ ND 
# Version: 2026.1
# !!DISCLAIMER:
# This script is provided for educational and research purposes only.
# It does NOT provide anonymity guarantees.
# It does NOT bypass laws, authentication, or access controls.
# The author is not responsible for misuse.
# Use only on systems you own or have permission to test.
# ==========================================================

Clear-Host
Write-Host "._______________________        __          __  .__               " -ForegroundColor Cyan
Write-Host "|   \______   \______   \ _____/  |______ _/  |_|__| ____   ____  " -ForegroundColor Cyan
Write-Host "|   ||     ___/|       _//  _ \   __\__  \\   __\  |/  _ \ /    \ " -ForegroundColor DarkCyan
Write-Host "|   ||    |    |    |   (  <_> )  |  / __ \|  | |  (  <_> )   |  \ " -ForegroundColor Cyan
Write-Host "|___||____|    |____|_  /\____/|__| (____  /__| |__|\____/|___|  / " -ForegroundColor DarkCyan
Write-Host "                      \/                 \/                    \/  " -ForegroundColor Cyan
Write-Host "               By.ND" -ForegroundColor Blue
Write-Host ""
Write-Host "[+] Starting Windows IPRotation setup..." -ForegroundColor Green
Write-Host ""

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------
# 1. Check if we are running as Administrator
# ----------------------------------------------------------
function Ensure-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "[!] Not running as Administrator. Relaunching..." -ForegroundColor Yellow
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $psi.Verb      = "runas"
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
}
Ensure-Admin

# ----------------------------------------------------------
# 2. Chech if Chocolatey is present
# ----------------------------------------------------------
function Ensure-Choco {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "[+] Chocolatey found." -ForegroundColor Green
        return
    }

    Write-Host "[+] Chocolatey not found. Installing..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    # enable TLS 1.2
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    Write-Host "[+] Chocolatey installed." -ForegroundColor Green
}
Ensure-Choco

# ----------------------------------------------------------
# 3. Install or update required packages
#    - tor: headless Tor
#    - privoxy: HTTP proxy that forwards to our Tor SOCKS
#    - nmap: to get ncat.exe
# ----------------------------------------------------------
$packagesToEnsure = @("tor", "privoxy", "nmap")

foreach ($pkg in $packagesToEnsure) {
    $installed = choco list --local-only --exact $pkg | Select-String -Pattern " $pkg "
    if ($installed) {
        Write-Host "[+] $pkg already installed → upgrading..." -ForegroundColor Cyan
        choco upgrade $pkg -y | Out-Null
    } else {
        Write-Host "[+] Installing $pkg..." -ForegroundColor Yellow
        choco install $pkg -y | Out-Null
    }
}

# detect curl (Win10/11 usually has this)
$curlExe = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source

# ----------------------------------------------------------
# 4. Helper to find executables on disk
# ----------------------------------------------------------
function Find-Exe {
    param(
        [Parameter(Mandatory)]
        [string]$ExeName,
        [string[]]$FallbackPaths = @()
    )

    # try PATH first
    $cmd = Get-Command $ExeName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # then try common dirs
    foreach ($path in $FallbackPaths) {
        if (Test-Path $path) { return $path }
    }

    return $null
}

# ----------------------------------------------------------
# 5. Auto-detect tor.exe, privoxy.exe, ncat.exe
#    (adjust these fallback paths if your environment differs)
# ----------------------------------------------------------
$chocoRoot = Join-Path $env:ProgramData "chocolatey"

$torExe = Find-Exe -ExeName "tor.exe" -FallbackPaths @(
    (Join-Path $chocoRoot "bin\tor.exe")
    (Join-Path $chocoRoot "lib\tor\tools\tor.exe")
)

$privoxyExe = Find-Exe -ExeName "privoxy.exe" -FallbackPaths @(
    (Join-Path $chocoRoot "lib\privoxy\tools\privoxy.exe")
    "C:\Program Files (x86)\Privoxy\privoxy.exe"
)

$ncatExe = Find-Exe -ExeName "ncat.exe" -FallbackPaths @(
    "C:\Program Files (x86)\Nmap\ncat.exe"
    "C:\Program Files\Nmap\ncat.exe"
)

if (-not $torExe)     { throw "tor.exe not found. Update fallback paths in script." }
if (-not $privoxyExe) { throw "privoxy.exe not found. Update fallback paths in script." }
if (-not $ncatExe)    { throw "ncat.exe not found (from nmap). Update fallback paths in script." }

Write-Host "[+] tor.exe     → $torExe"
Write-Host "[+] privoxy.exe → $privoxyExe"
Write-Host "[+] ncat.exe    → $ncatExe"

# ----------------------------------------------------------
# 6. Runtime configuration (safe to edit)
# ----------------------------------------------------------
$userHome   = $env:USERPROFILE
$torBase    = Join-Path $userHome ".tor_multi"
$privoxyDir = Join-Path $userHome ".privoxy"
$privoxyCfg = Join-Path $privoxyDir "config"

# Tor instances: add/remove ports in BOTH arrays to match
$socksPorts   = 9050, 9060, 9070, 9080, 9090
$controlPorts = 9051, 9061, 9071, 9081, 9091

# Privoxy listen port (change if 8118 is taken)
$privoxyPort  = 8118

# ----------------------------------------------------------
# 6.1 Graceful shutdown handler (cleanup on exit)
# When the PowerShell session exits (Ctrl+C, window close, error, etc.),
# kill Tor and Privoxy so ports are released and reruns work cleanly.
# ----------------------------------------------------------

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    try {
        Get-Process tor     -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Get-Process privoxy -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    } catch {
        # Best-effort cleanup only
    }
}

# ----------------------------------------------------------
# 7. Clean up old tor/privoxy and recreate dirs
# ----------------------------------------------------------
Write-Host "[+] Cleaning old Tor/Privoxy instances..." -ForegroundColor Yellow

Get-Process tor     -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process privoxy -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path $torBase)    { Remove-Item $torBase -Recurse -Force }
if (Test-Path $privoxyDir) { Remove-Item $privoxyDir -Recurse -Force }

New-Item -ItemType Directory -Path $torBase    | Out-Null
New-Item -ItemType Directory -Path $privoxyDir | Out-Null

# ----------------------------------------------------------
# 8. Start multiple Tor instances
# ----------------------------------------------------------
Write-Host "[+] Launching Tor nodes..." -ForegroundColor Green

for ($i = 0; $i -lt $socksPorts.Count; $i++) {
    $torDir      = Join-Path $torBase ("tor{0}" -f $i)
    $socksPort   = $socksPorts[$i]
    $controlPort = $controlPorts[$i]

    New-Item -ItemType Directory -Path $torDir | Out-Null

    # build torrc for this instance
    $torrc = @"
SocksPort $socksPort
ControlPort $controlPort
DataDirectory $torDir
CookieAuthentication 0
"@

    $torrcPath = Join-Path $torDir "torrc"
    $torrc | Set-Content -Path $torrcPath -Encoding ASCII

    # start tor with this torrc
    Start-Process -FilePath $torExe -ArgumentList @("-f", "`"$torrcPath`"") -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# ----------------------------------------------------------
# 9. Configure and start Privoxy
# ----------------------------------------------------------
Write-Host "[+] Configuring Privoxy..." -ForegroundColor Green

$privoxyContent = @"
listen-address  127.0.0.1:$privoxyPort
"@

foreach ($p in $socksPorts) {
    $privoxyContent += "forward-socks5   /   127.0.0.1:$p .`r`n"
}

$privoxyContent | Set-Content -Path $privoxyCfg -Encoding ASCII

Start-Process -FilePath $privoxyExe -ArgumentList "`"$privoxyCfg`"" -WindowStyle Hidden
Start-Sleep -Seconds 2

# ----------------------------------------------------------
# 10. Ask user how often to rotate IP
# ----------------------------------------------------------
$rotationTime = Read-Host "Enter IP rotation interval in seconds (min 5)"
if (-not ($rotationTime -as [int]) -or [int]$rotationTime -lt 5) {
    Write-Host "[!] Invalid value. Using 10 seconds." -ForegroundColor Yellow
    $rotationTime = 10
}
$rotationTime = [int]$rotationTime

Write-Host "[+] IPR rotation loop started. Set your browser/system proxy to http://127.0.0.1:$privoxyPort" -ForegroundColor Cyan
Write-Host "[i] Press Ctrl+C to stop." -ForegroundColor DarkRed

# ----------------------------------------------------------
# 11. Rotation loop
# ----------------------------------------------------------
while ($true) {
    # send SIGNAL NEWNYM to each Tor control port
    foreach ($cp in $controlPorts) {
        $command = "AUTHENTICATE `"`"`"`r`nSIGNAL NEWNYM`r`nQUIT`r`n"

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName               = $ncatExe
        $pinfo.Arguments              = "127.0.0.1 $cp"
        $pinfo.UseShellExecute        = $false
        $pinfo.RedirectStandardInput  = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError  = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $pinfo
        $proc.Start() | Out-Null
        $proc.StandardInput.Write($command)
        $proc.StandardInput.Close()
        $proc.WaitForExit(2000) | Out-Null
    }

    # check current IP through our proxy
    if ($curlExe) {
        $ip = (& $curlExe --proxy http://127.0.0.1:$privoxyPort -s https://api64.ipify.org) 2>$null
    } else {
        try {
            $ip = (Invoke-WebRequest -Uri "https://api64.ipify.org" -Proxy "http://127.0.0.1:$privoxyPort" -UseBasicParsing).Content
        } catch {
            $ip = "Unknown"
        }
    }

    Write-Host ("[+] New IP: {0}" -f $ip) -ForegroundColor Green
    Write-Host ("[+] Proxy: 127.0.0.1:{0}" -f $privoxyPort) -ForegroundColor DarkCyan

    Start-Sleep -Seconds $rotationTime
}

