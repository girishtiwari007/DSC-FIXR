# DSC Signer Service 4.1.8 – Check & Fix

One command checks and repairs eOffice **DSC signing** (DigitalSignerService 4.1.8) on a Windows PC.

## Run it

Open **PowerShell** (Start → type *PowerShell* → Enter) and paste:

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/girishtiwari007/DSC-FIXR/main/install.ps1 | iex
```

Or press **Win + R** and paste:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/girishtiwari007/DSC-FIXR/main/install.ps1 | iex"
```

No admin rights are needed to start. The tool asks for admin only when you click **Fix**.

## What happens

1. The latest `DSC_Signer_OneClick_Fix.bat` is downloaded from this repository and checked against `SHA256SUMS.txt`.
2. If `C:\Program Files\Digital Signer Service\4.1.8\Digital Signer Service.exe` is **missing**, the 4.1.8 package (about 100 MB) is downloaded once from
   `https://nr.indianrailways.gov.in/uploads/files/1792736602773-DSC_Signer_Tool_with_DSS_4.1.8.zip`,
   and the installer inside it is unpacked and checked. If DSS is already installed, nothing big is downloaded.
3. The check window opens: overall test → fix dashboard → **Fix ALL / Select items / Not now**.

Everything is kept in `%LOCALAPPDATA%\DSC-FIXR\tool`. Running the command again updates the tool and reuses the package.

## Options

```powershell
$s = [scriptblock]::Create((irm https://raw.githubusercontent.com/girishtiwari007/DSC-FIXR/main/install.ps1))
& $s -Mode console      # text version instead of the window
& $s -Mode check        # only test, change nothing
& $s -WithPackage       # download the 4.1.8 package even if DSS is installed
& $s -NoPackage         # never download the package
& $s -PackageUrl <url>  # use another download location for the package
```

## If the package download fails

The setup says why in plain words (no internet, office proxy/firewall blocks the site, file moved – 404, wrong PC date). The tool still opens; when it asks, pick the 4.1.8 zip / msi / folder from a pen drive or shared folder, or download the zip in the browser and pick it.

## Files

| File | Purpose |
| --- | --- |
| `install.ps1` | the online setup run by the command above |
| `DSC_Signer_OneClick_Fix.bat` | the tool itself (also works on its own: double-click) |
| `SHA256SUMS.txt` | checksum the setup verifies before running the tool |

**After you change `DSC_Signer_OneClick_Fix.bat`**, update `SHA256SUMS.txt` (PowerShell: `(Get-FileHash .\DSC_Signer_OneClick_Fix.bat).Hash.ToLower() + "  DSC_Signer_OneClick_Fix.bat"`), otherwise the setup keeps the old copy.
