<#
  DSC Signer Service 4.1.8 - Check & Fix  :  online setup
  ---------------------------------------------------------
  Paste in PowerShell (normal user is fine):

    [Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/girishtiwari007/DSC-FIXR/main/install.ps1 | iex

  1. downloads the latest DSC_Signer_OneClick_Fix.bat from GitHub (checked with SHA256)
  2. if DigitalSignerService 4.1.8 is NOT installed: downloads the 4.1.8 package (~100 MB, once)
     from the Northern Railway site, unpacks and checks the installer
  3. opens the check window - nothing is changed without your permission
#>
& {
param(
    [ValidateSet('gui', 'console', 'check')] [string]$Mode = 'gui',
    [switch]$WithPackage,          # download the 4.1.8 package even if DSS is already installed
    [switch]$NoPackage,            # never download the package
    [switch]$NoRun,                # only prepare, do not start the tool
    [string]$Repo       = 'girishtiwari007/DSC-FIXR',
    [string]$Branch     = 'main',
    [string]$BaseUrl    = '',
    [string]$PackageUrl = 'https://nr.indianrailways.gov.in/uploads/files/1792736602773-DSC_Signer_Tool_with_DSS_4.1.8.zip',
    [string]$InstallDir = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$DssVersion = '4.1.8'
if (-not $BaseUrl)    { $BaseUrl = "https://raw.githubusercontent.com/$Repo/$Branch" }
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'DSC-FIXR\tool' }
$PkgDir = Join-Path $InstallDir 'package'

function Step([string]$t, [string]$c = 'Cyan') { Write-Host "  $t" -ForegroundColor $c }
function Join-Url($a, $b) { if ($a -match '^https?://') { "$a/$b" } else { Join-Path $a $b } }
function Get-Text([string]$url) {
    if ($url -notmatch '^https?://') { return [IO.File]::ReadAllText($url) }
    $wc = New-Object Net.WebClient
    try { $wc.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $wc.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials } catch {}
    $wc.Headers['User-Agent'] = 'DSC-Signer-Fixer'
    return $wc.DownloadString($url + $(if ($url -match '\?') { '&' } else { '?' }) + 't=' + [DateTime]::UtcNow.Ticks)   # avoid stale cache
}
# download with resume, system proxy, browser user-agent, progress and plain-language errors
function Get-WebFileResume([string]$Url, [string]$OutFile, [int]$Tries = 4) {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    $part = "$OutFile.part"; $why = ''
    for ($try = 1; $try -le $Tries; $try++) {
        $have = 0; if (Test-Path -LiteralPath $part) { $have = (Get-Item -LiteralPath $part).Length }
        $resp = $null; $in = $null; $out = $null
        try {
            $req = [Net.HttpWebRequest][Net.WebRequest]::Create($Url)
            $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 DSC-Signer-Fixer'
            $req.Timeout = 30000; $req.ReadWriteTimeout = 60000; $req.AllowAutoRedirect = $true
            try { $req.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $req.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials } catch {}
            if ($have -gt 0) { $req.AddRange([long]$have) }
            $resp = $req.GetResponse()
            $append = ($have -gt 0 -and [int]$resp.StatusCode -eq 206)
            if (-not $append) { $have = 0 }
            $total = $have + [long]$resp.ContentLength
            $in = $resp.GetResponseStream()
            $out = New-Object IO.FileStream($part, $(if ($append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }), [IO.FileAccess]::Write)
            $buf = New-Object byte[] 1MB; $done = $have; $last = [DateTime]::MinValue
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n); $done += $n
                if (((Get-Date) - $last).TotalMilliseconds -gt 700) {
                    $last = Get-Date
                    $pct = $(if ($total -gt 0) { [int](100 * $done / $total) } else { 0 })
                    Write-Progress -Activity 'Downloading DigitalSignerService 4.1.8 package' -Status ("{0:N1} of {1:N1} MB" -f ($done / 1MB), ($total / 1MB)) -PercentComplete $pct
                }
            }
            $out.Close(); $out = $null
            if ($total -gt 0 -and (Get-Item -LiteralPath $part).Length -lt $total) { throw (New-Object IO.IOException('connection closed before the download finished')) }
            Write-Progress -Activity 'Downloading DigitalSignerService 4.1.8 package' -Completed
            Move-Item -LiteralPath $part -Destination $OutFile -Force
            return @{ Ok = $true; Text = 'downloaded' }
        } catch {
            $ex = $_.Exception; while ($ex.InnerException -and $ex -isnot [Net.WebException]) { $ex = $ex.InnerException }
            $we = $ex -as [Net.WebException]; $code = 0
            if ($we -and $we.Response) { try { $code = [int]$we.Response.StatusCode } catch {} }
            $why = $ex.Message; $retry = $true
            if ($we) {
                switch -Regex ($we.Status.ToString()) {
                    'NameResolutionFailure'      { $why = "cannot find the server $(([Uri]$Url).Host) - no internet, or DNS is blocked on this network"; $retry = $false }
                    'ProxyNameResolutionFailure' { $why = 'the proxy server set on this PC cannot be found - check Internet Options > Connections > LAN settings'; $retry = $false }
                    'TrustFailure|SecureChannel' { $why = 'secure (HTTPS) connection failed - check the PC date and time, or the network blocks this site'; $retry = $false }
                    'Timeout'                    { $why = 'the server did not answer in time (slow or blocked network)' }
                    'ConnectFailure'             { $why = 'could not connect to the server (firewall / network blocks it, or the site is down)' }
                }
            }
            if (-not $code -and $why -match '(?i)proxy') {
                if ($why -match '407') { $code = 407 } elseif ($why -match '403') { $why = 'the network proxy / firewall of this office blocks this website - ask IT to allow it, or download it in the browser'; $retry = $false }
            }
            if ($why -match '(?i)No such host|could not be resolved|Name or service not known') { $why = "cannot find the server $(([Uri]$Url).Host) - no internet, or DNS is blocked on this network"; $retry = $false }
            if ($code -eq 404) { $why = 'the file is no longer at this address (404 - moved or deleted on the website)'; $retry = $false }
            elseif ($code -eq 407) { $why = 'the proxy server needs a login - open the link once in the browser, then try again'; $retry = $false }
            elseif ($code -eq 403) { $why = 'the website refused the download (403 - blocked for this network)'; $retry = $false }
            elseif ($code -eq 416) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
            Write-Host "      try $try of ${Tries}: $why" -ForegroundColor Yellow
            if (-not $retry) { break }
            Start-Sleep -Seconds ([Math]::Min(2 * $try, 8))
        } finally {
            if ($out) { try { $out.Close() } catch {} }
            if ($in) { try { $in.Close() } catch {} }
            if ($resp) { try { $resp.Close() } catch {} }
        }
    }
    # last resort: Windows background transfer (works through most company proxies)
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        try {
            Write-Host '      trying Windows background download (BITS) ...' -ForegroundColor Yellow
            Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName 'DSC Signer package' -ErrorAction Stop
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            return @{ Ok = $true; Text = 'downloaded (BITS)' }
        } catch { $why = "$why | BITS: $($_.Exception.Message)" }
    }
    return @{ Ok = $false; Text = $why }
}

# a 'single-file tool' .bat carries the installer zip after a marker line - copy that zip out
function Export-BatPayload([string]$Bat, [string]$OutZip) {
    $fs = [IO.File]::OpenRead($Bat)
    try {
        $n = [int][Math]::Min($fs.Length, 16MB); $buf = New-Object byte[] $n; $got = 0
        while ($got -lt $n) { $r = $fs.Read($buf, $got, $n - $got); if ($r -le 0) { break }; $got += $r }
        $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf, 0, $got)
        $i = $txt.IndexOf('#__DSSF_' + 'PAYLOAD_ZIP__')
        if ($i -lt 0) { return $false }
        $j = $txt.IndexOf("`n", $i); if ($j -lt 0) { return $false }
        $start = $j + 1
        if ($buf[$start] -ne 0x50 -or $buf[$start + 1] -ne 0x4B) { return $false }   # 'PK' = zip
        [void]$fs.Seek($start, 'Begin')
        $o = [IO.File]::Create($OutZip); try { $fs.CopyTo($o) } finally { $o.Close() }
        return $true
    } finally { $fs.Close() }
}

# is the file a DigitalSignerService 4.1.8 msi? (checks the content, not the name)
function Test-DssMsi([string]$p) {
    try {
        $fs = [IO.File]::OpenRead($p); $buf = New-Object byte[] 4MB; $got = 0
        try { while ($got -lt $buf.Length) { $r = $fs.Read($buf, $got, $buf.Length - $got); if ($r -le 0) { break }; $got += $r } } finally { $fs.Close() }
        if ($got -lt 8 -or $buf[0] -ne 0xD0 -or $buf[1] -ne 0xCF -or $buf[2] -ne 0x11 -or $buf[3] -ne 0xE0) { return $false }
        return ([Text.Encoding]::GetEncoding(28591).GetString($buf, 0, $got) -match "Digital ?Signer ?Service\s*v?$([regex]::Escape($DssVersion))")
    } catch { return $false }
}
function Expand-Zip([string]$Zip, [string]$Dest) {
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop; [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Dest); return }
    catch { Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force }
}
function Get-ReadyMsi { if (Test-Path $PkgDir) { Get-ChildItem -LiteralPath $PkgDir -Recurse -File -Filter *.msi -ErrorAction SilentlyContinue | Where-Object { Test-DssMsi $_.FullName } | Select-Object -First 1 } }

Write-Host ''
Write-Host "  DSC Signer Service $DssVersion - Check & Fix  (online setup)" -ForegroundColor White
Write-Host "  Folder: $InstallDir" -ForegroundColor DarkGray
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# ---- 1. the tool (always the latest from GitHub)
$sums = @{}
try { foreach ($l in ((Get-Text (Join-Url $BaseUrl 'SHA256SUMS.txt')) -split "`r?`n")) { if ($l -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') { $sums[$matches[2].Trim()] = $matches[1].ToUpper() } } }
catch { Step 'SHA256SUMS.txt not reachable - the tool download is not verified' 'Yellow' }
$tool = Join-Path $InstallDir 'DSC_Signer_OneClick_Fix.bat'
try {
    Step 'Downloading the latest DSC_Signer_OneClick_Fix.bat from GitHub ...'
    $txt = Get-Text (Join-Url $BaseUrl 'DSC_Signer_OneClick_Fix.bat')
    $txt = ($txt -replace "`r`n", "`n") -replace "`n", "`r`n"            # cmd.exe needs Windows line endings
    $tmp = "$tool.new"; [IO.File]::WriteAllText($tmp, $txt, (New-Object Text.ASCIIEncoding))
    $want = $sums['DSC_Signer_OneClick_Fix.bat']
    if ($want -and (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne $want) { Remove-Item $tmp -Force; throw 'downloaded tool failed the SHA256 check' }
    Move-Item -LiteralPath $tmp -Destination $tool -Force
    try { Unblock-File -LiteralPath $tool } catch {}
    Step 'Tool ready.' 'Green'
} catch {
    if (Test-Path $tool) { Step "Could not update the tool ($($_.Exception.Message)) - using the copy downloaded earlier." 'Yellow' }
    else { Step "Could not download the tool from GitHub: $($_.Exception.Message)" 'Red'; Step 'Check the internet connection (github.com must be reachable) and run the command again.' 'Yellow'; return }
}

# ---- 2. the 4.1.8 package - only when it is needed
$dssExe = @("$env:ProgramFiles\Digital Signer Service\$DssVersion\Digital Signer Service.exe", "${env:ProgramFiles(x86)}\Digital Signer Service\$DssVersion\Digital Signer Service.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
$need = (-not $NoPackage) -and ($WithPackage -or -not $dssExe)
if ($dssExe -and -not $WithPackage) { Step "DigitalSignerService $DssVersion is installed ($dssExe) - package download not needed." 'Green' }
if ($need) {
    $ready = Get-ReadyMsi
    if ($ready) { Step "Installer $DssVersion already here: $($ready.FullName)" 'Green' }
    else {
        Step "DigitalSignerService $DssVersion is not installed - getting the installer package (about 100 MB, only this once) ..."
        $zip = Join-Path $InstallDir 'DSS-package-download.zip'
        if ($PackageUrl -match '^https?://') { $res = Get-WebFileResume $PackageUrl $zip }
        else { Copy-Item -LiteralPath $PackageUrl -Destination $zip -Force; $res = @{ Ok = $true } }
        if (-not $res.Ok) {
            Step "Package download failed: $($res.Text)" 'Red'
            Step 'The tool still opens. When it asks, choose the 4.1.8 zip / msi from a pen drive or shared folder,' 'Yellow'
            Step "or download it in the browser:  $PackageUrl" 'Yellow'
        } else {
            try {
                Step 'Unpacking and checking the installer ...'
                $x = Join-Path $InstallDir 'pkg-extract'; Remove-Item -LiteralPath $x -Recurse -Force -ErrorAction SilentlyContinue
                Expand-Zip $zip $x
                $msi = Get-ChildItem -LiteralPath $x -Recurse -File -Filter *.msi | Where-Object { Test-DssMsi $_.FullName } | Select-Object -First 1
                if (-not $msi) {
                    foreach ($bat in @(Get-ChildItem -LiteralPath $x -Recurse -File -Filter *.bat | Where-Object { $_.Length -gt 1MB })) {
                        $pz = Join-Path $x 'payload.zip'
                        if (Export-BatPayload $bat.FullName $pz) { Expand-Zip $pz (Join-Path $x 'payload'); break }
                    }
                    $msi = Get-ChildItem -LiteralPath $x -Recurse -File -Filter *.msi | Where-Object { Test-DssMsi $_.FullName } | Select-Object -First 1
                }
                if (-not $msi) { throw "no DigitalSignerService $DssVersion installer inside the downloaded file" }
                New-Item -ItemType Directory -Force -Path $PkgDir | Out-Null
                Copy-Item -LiteralPath $msi.FullName -Destination $PkgDir -Force
                $cer = Get-ChildItem -LiteralPath $x -Recurse -File -Filter *.cer | Select-Object -First 1
                if ($cer) { Copy-Item -LiteralPath $cer.FullName -Destination $PkgDir -Force }
                Step "Installer ready: $(Join-Path $PkgDir $msi.Name)" 'Green'
            } catch { Step "The downloaded package could not be used: $($_.Exception.Message)" 'Red' }
            finally {
                Remove-Item -LiteralPath (Join-Path $InstallDir 'pkg-extract') -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

if ($NoRun) { Step "Done. Start it any time: $tool" 'Green'; return }

# ---- 3. start the tool (it tests first and asks before changing anything)
$env:DSSF_PKGURL = $PackageUrl          # lets the tool fetch the package later if a fix needs it
Step 'Opening the DSC Signer check window ...'
if ($Mode -eq 'gui') { Start-Process -FilePath $tool -WorkingDirectory $InstallDir }
else { Start-Process -FilePath $tool -ArgumentList $Mode -WorkingDirectory $InstallDir }
Step 'Done - you can close this PowerShell window.' 'Green'
} @args
