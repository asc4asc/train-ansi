param(
    [string]$VmName            = 'debian13-trixie',
    [string]$VmBaseFolder      = (Join-Path $env:USERPROFILE 'VirtualBox VMs'),
    [string]$IsoCache          = (Join-Path $env:USERPROFILE 'Downloads'),
    # <-- ANPASSEN: Pfad zu deinem Host-Public-Key (z. B. id_ed25519.pub oder id_rsa.pub)
    [string]$HostSshPubKeyPath = (Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub')
)

# =====================================================================
# Unattended-Installation Debian 13 "Trixie" (VirtualBox, Windows Host)
# - Ohne Post-Install-Skript
# - SSH nur per Public Key (Passwort-Login aus)
# - Preseed (d-i) mit late_command erledigt Paket/SSH-Konfiguration
# - VBoxManage unattended mit --script-template (Preseed)
# - NAT + Portweiterleitung: Host 127.0.0.1:2222 -> Gast 22
# - ISO-SHA512-Prüfung optional aktiviert
# =====================================================================

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# ---- Basis-Konfiguration ----
$DebianIsoUrl  = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.3.0-amd64-netinst.iso'
$CpuCount      = 2
$MemoryMB      = 2048
$VRAMMB        = 16
$DiskGB        = 20

$GuestUser     = 'ekf'
$GuestPass     = 'changeme'     # nur für den Installer; SSH-PW-Login wird deaktiviert
$FullUserName  = 'ekf'

$Locale        = 'de_DE'
$Country       = 'DE'
$TimeZone      = 'Europe/Berlin'
$Language      = 'de'           # ggf. leer lassen, falls VBox hier Probleme macht

$VBoxManage    = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path -LiteralPath $VBoxManage)) { throw "VBoxManage nicht gefunden: $VBoxManage" }

# ---- Logging ----
$LogDir     = Join-Path $env:TEMP "deb13_unattended_preseed"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Transcript = Join-Path $LogDir ("install_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $Transcript -Force | Out-Null
$VBoxUnattendedLog = Join-Path $LogDir "vbox_unattended.log"

function Invoke-Step {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][ScriptBlock]$Script,[switch]$CheckLastExitCode)
    Write-Host "==> $Name" -ForegroundColor Cyan
    try {
        & $Script
        if ($CheckLastExitCode -and ($LASTEXITCODE -ne $null) -and ($LASTEXITCODE -ne 0)) {
            throw "Exitcode: $LASTEXITCODE (Step: $Name)"
        }
    } catch {
        Write-Error "FEHLER in Schritt: $Name"
        Write-Error $_.Exception.Message
        Stop-Transcript | Out-Null
        exit 1
    }
}

# ---- Verzeichnisse / ISO ----
Invoke-Step -Name "Verzeichnisse anlegen" -Script {
    New-Item -ItemType Directory -Path $VmBaseFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $IsoCache    -Force | Out-Null
}

$IsoPath = Join-Path $IsoCache ([IO.Path]::GetFileName($DebianIsoUrl))
Invoke-Step -Name "ISO herunterladen/bereitstellen" -Script {
    if (-not (Test-Path -LiteralPath $IsoPath)) {
        Invoke-WebRequest -Uri $DebianIsoUrl -OutFile $IsoPath -UseBasicParsing
    }
}

# ---- Optional: ISO-Integrität (SHA512) prüfen ----
Invoke-Step -Name "ISO-Integrität (SHA512) prüfen" -Script {
    $ShaListUrl = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA512SUMS'
    $ShaFile    = Join-Path $IsoCache 'SHA512SUMS'
    if (-not (Test-Path -LiteralPath $ShaFile)) {
        Invoke-WebRequest -Uri $ShaListUrl -OutFile $ShaFile -UseBasicParsing
    }
    $isoName  = [IO.Path]::GetFileName($IsoPath)
    $line     = (Select-String -Path $ShaFile -Pattern ([regex]::Escape($isoName))).Line
    if (-not $line) { throw "Keine SHA512SUMS-Zeile für $isoName gefunden." }
    $expected = $line.Split(' ')[0].ToLower()
    $actual   = (Get-FileHash -Path $IsoPath -Algorithm SHA512).Hash.ToLower()
    if ($actual -ne $expected) { throw "SHA512-Mismatch für $isoName" }
}

# ---- VM entfernen / anlegen ----
Invoke-Step -Name "Vorhandene VM entfernen" -Script {
    $existing = & $VBoxManage list vms | Select-String -Pattern "^\`"$VmName\`""
    if ($existing) {
        try { & $VBoxManage controlvm $VmName poweroff } catch {}
        & $VBoxManage unregistervm $VmName --delete
    }
} -CheckLastExitCode

Invoke-Step -Name "Machine-Folder (global) setzen" -Script {
    & $VBoxManage setproperty machinefolder $VmBaseFolder
} -CheckLastExitCode

Invoke-Step -Name "VM erstellen + Ressourcen" -Script {
    & $VBoxManage createvm --name $VmName --ostype "Debian_64" --register
    & $VBoxManage modifyvm $VmName --cpus $CpuCount --memory $MemoryMB --vram $VRAMMB --firmware bios
    & $VBoxManage modifyvm $VmName --graphicscontroller vmsvga --audio-driver none
} -CheckLastExitCode

# ---- Storage ----
$DiskPath = Join-Path $VmBaseFolder "$VmName\$VmName.vdi"
Invoke-Step -Name "Storage anlegen" -Script {
    New-Item -ItemType Directory -Path (Split-Path $DiskPath) -Force | Out-Null
    & $VBoxManage createmedium disk --filename $DiskPath --format VDI --size ($DiskGB * 1024)
    & $VBoxManage storagectl  $VmName --name "SATA Controller" --add sata --controller IntelAhci
    & $VBoxManage storageattach $VmName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $DiskPath
    & $VBoxManage storagectl  $VmName --name "IDE Controller" --add ide
    & $VBoxManage storageattach $VmName --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium $IsoPath
} -CheckLastExitCode

# ---- NAT + Portweiterleitung für SSH ----
Invoke-Step -Name "Netzwerk: NAT + Portweiterleitung (2222->22)" -Script {
    # explizit NAT auf Adapter1 setzen (sicher, auch wenn Standard)
    & $VBoxManage modifyvm $VmName --nic1 nat

    # ggf. alte Regel entfernen, um Doppelnamen zu vermeiden
    try { & $VBoxManage modifyvm $VmName --natpf1 delete "ssh" } catch {}

    # neue Regel hinzufügen: Host 127.0.0.1:2222 -> Gast 22 (TCP)
    & $VBoxManage modifyvm $VmName --natpf1 "ssh,tcp,,2222,,22"
} -CheckLastExitCode

# ---- Aux/Preseed vorbereiten ----
$AuxPath = Join-Path $VmBaseFolder "$VmName\Unattended"
Invoke-Step -Name "Aux/Unattended Ordner anlegen" -Script {
    New-Item -ItemType Directory -Path $AuxPath -Force | Out-Null
}

# Host-Public-Key lesen
if (-not (Test-Path -LiteralPath $HostSshPubKeyPath)) {
    throw "SSH-Public-Key nicht gefunden: $HostSshPubKeyPath"
}
$SshPubKey = (Get-Content -LiteralPath $HostSshPubKeyPath -Raw).Trim()


# Preseed-Template erzeugen (Achtung: abschließendes "@ muss am Zeilenanfang stehen!)
$PreseedPath = Join-Path $AuxPath 'debian_preseed.cfg'
$PreseedContent = @"
### Locale / Keyboard / Time
d-i debian-installer/locale string $Locale
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select de
d-i time/zone string $TimeZone

### Network
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string $($VmName.ToLower()).local
d-i netcfg/get_domain string local

### Mirror
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

### Users
d-i passwd/user-fullname string $FullUserName
d-i passwd/username string $GuestUser
d-i passwd/user-password password $GuestPass
d-i passwd/user-password-again password $GuestPass
d-i passwd/root-login boolean false
d-i user-setup/allow-password-weak boolean true

### Clock
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true

### Partitioning (ganze Disk, guided, atomic)
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

### Packages
tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false
d-i apt-setup/use_mirror boolean true

### Bootloader
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default

# Installation fertig → automatischer Reboot
d-i cdrom-detect/eject boolean true
d-i finish-install/reboot_in_progress note

### SSH-Konfiguration per late_command (kein externes Postscript)
d-i preseed/late_command string \
  in-target mkdir -p /home/${GuestUser}/.ssh ; \
  in-target /bin/sh -c 'echo ${SshPubKey} > /home/${GuestUser}/.ssh/authorized_keys' ; \
  in-target chown -R ${GuestUser}:${GuestUser} /home/${GuestUser}/.ssh ; \
  in-target chmod 700 /home/${GuestUser}/.ssh ; \
  in-target chmod 600 /home/${GuestUser}/.ssh/authorized_keys ; \
  in-target sed -i "s/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/i" /etc/ssh/sshd_config ; \
  in-target sed -i "s/^[#[:space:]]*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/i" /etc/ssh/sshd_config ; \
  in-target sed -i "s/^[#[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/i" /etc/ssh/sshd_config ; \
  in-target sed -i "s/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/i" /etc/ssh/sshd_config ; \
  in-target /bin/sh -c 'grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config' ; \
  in-target /bin/sh -c 'grep -q "^KbdInteractiveAuthentication" /etc/ssh/sshd_config || echo "KbdInteractiveAuthentication no" >> /etc/ssh/sshd_config' ; \
  in-target /bin/sh -c 'grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config' ; \
  in-target /bin/sh -c 'grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config' ; \
  in-target systemctl enable ssh
"@

Invoke-Step -Name "Preseed schreiben (LF, UTF-8)" -Script {
    $lf  = $PreseedContent -replace "`r?`n", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllBytes($PreseedPath, $utf8NoBom.GetBytes($lf))
    if (-not (Test-Path -LiteralPath $PreseedPath)) { throw "Preseed-Datei wurde nicht erstellt." }
}

# ---- Unattended installieren (ohne Postscript) ----
$Hostname = "$VmName.local"

Invoke-Step -Name "VBoxManage unattended detect protokollieren" -Script {
    & $VBoxManage unattended detect --iso $IsoPath --machine-readable |
        Out-File -FilePath $VBoxUnattendedLog -Append -Encoding utf8
}

$unattArgs = @(
  'unattended','install',$VmName,
  '--iso', $IsoPath,
  '--user', $GuestUser,
  '--password', $GuestPass,            # nur für Installer; SSH-PW-Login später aus
  '--full-user-name', $FullUserName,
  '--locale', $Locale,
  '--country', $Country,
  '--time-zone', $TimeZone,
  '--hostname', $Hostname,
  '--package-selection-adjustment', 'minimal',
  '--script-template', $PreseedPath,   # unser Preseed mit late_command
  '--auxiliary-base-path', $AuxPath,
  '--start-vm', 'headless'
)
if ($Language -and $Language.Trim()) { $unattArgs += @('--language', $Language) }

Invoke-Step -Name "VBoxManage unattended install (Start)" -Script {
    # Für Diagnose: effektive Cmdline loggen
    $logLine = '"{0}" {1}' -f $VBoxManage, (($unattArgs | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }) -join ' ')
    $logLine | Out-File -FilePath $VBoxUnattendedLog -Append -Encoding utf8

    & $VBoxManage @unattArgs
} -CheckLastExitCode

Write-Host "`nUnattended-Installation gestartet." -ForegroundColor Green
Write-Host "SSH vom Host:  ssh -p 2222 $GuestUser@127.0.0.1" -ForegroundColor Yellow
Write-Host "Logs:" -ForegroundColor Green
Write-Host "  Transcript:           $Transcript"
Write-Host "  VBox-Unattended-Log:  $VBoxUnattendedLog"

Stop-Transcript | Out-Null
