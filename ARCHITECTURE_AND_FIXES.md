# Architektur-Entscheidungen & Gelöste Probleme (pins-t630-astro)

Diese Datei dokumentiert den geprüften, archivierten Endstand (`v1.0-stable`) und alle technischen Root-Cause-Fixes.

## 1. Geprüfter Endstand & Verbindliche Fixes
- **Kein Snap (`snapd`):** Entfernt und via `/etc/apt/preferences.d/nosnap.pref` dauerhaft gesperrt.
- **INDI FIFO Treiberstart (`NINA.INDI/INDIClient.cs`):** Gepatcht auf `/usr/bin/{driverName}`, damit N.I.N.A. Treiber über `/tmp/indiFIFO` zuverlässig startet.
- **`libXISF`-Trennung:** `libXISF*` liegt isoliert in `\(HOME/pins/` und wird nur gezielt per `LD_PRELOAD` im `/usr/bin/indiserver`-Wrapper geladen. Beim Neukompilieren von `indi_simulator_ccd` wird `libXISF.so*` nur kurzzeitig für den Ninja-Linker nach `/usr/local/lib/` verlinkt und sofort wieder entfernt.
- **`OpenCvSharpExtern`:** Wird passend zur installierten NuGet-Version (`opencvsharp4`) lokal kompiliert und nach `\)HOME/pins/` kopiert.
- **`CCD Simulator` (`ccd_simulator.cpp`) – Kaltstart- & Multi-FITS-fester C++-Patch:**
  - Defaults in `initProperties()` auf `\$HOME/test-fits`, `Use Dir. = Enabled (ISS_ON)`, `3008x3008` und `3.76 um` gepatcht.
  - `watchDirectory()` in `updateProperties()` beim Connect sowie in `StartExposure()` (`watchDirectory()` + `m_AllFiles.clear()` + `std::sort`) aktiviert, sodass `\$HOME/test-fits/` bei jeder Aufnahme live eingelesen und alphabetisch durchrotiert wird.
  - Fallback `pixel_size = 3.76; status = 0;` in `loadNextImage()`, falls `PIXSIZE1` im FITS-Header fehlt.
  - Vor `cmake --build` wird `ccd_simulator.cpp.o` gelöscht, damit Ninja Änderungen garantiert neu übersetzt.
  - **Hinweis bei SMB-Transfers vom Mac:** macOS Finder legt beim Kopieren versteckte AppleDouble-Dateien (`._*.fits`) an, die `cfitsio` beim Einlesen mit `tried to move past end of file` abbrechen lassen – bei Bedarf einfach per `rm -f ~/test-fits/._*` löschen.
  - **Wichtig:** Keinen Wrapper um `indi_simulator_ccd` bauen (führt sonst zu `DRIVER_INFO`-Timeout).
- **PHD2 Headless & VNC:** Xvfb `:99` mit `matchbox-window-manager -use_titlebar no` + `x11vnc` auf Port `5901` (`1234`); Touch 'N' Stars `GuidingPage-*.js` auf unbeschnittene 4:3-Darstellung gepatcht.
- **Bild-Speicherpfad (`ImageFilePath`):** Absoluter Pfad `\$HOME/astro-images` im `.profile` (verhindert `System.UriFormatException` in `ImageSaveController`).
- **Offline-Kataloge & Netzwerk:** Northern Sky Map (`1.4 GB`) in `~/.local/share/NINA/FramingAssistantCache`, ASTAP + D50 unter `/opt/astap/`, Samba-Share `[astro]` (mit interaktiver `smbpasswd`-Passwortabfrage am Ende des Setups) (`smb://10.42.0.1/astro`) und 2.4-GHz-Hotspot `pins-T630` (`astro1234`, `wifi-sec.psk` explizit per `nmcli modify` gesetzt).

- **`.NET 10.0.400 SDK`:** Muss exakt Version `10.0.400` sein (über `dotnet/install-scripts` nach `/usr/share/dotnet`), da ältere `10.0.1xx`-Ubuntu-Pakete die Roslyn-Source-Generatoren in `nitr57/pins` nicht ausführen (`CS9248`).

- **Hotspot (`pins-T630`, `10.42.0.1/24`):** Installiert `dnsmasq-base`, setzt `unmanaged-devices=none` in `/etc/NetworkManager/conf.d/99-manage-all.conf (dynamisches Ethernet DHCP + Duplikat-Bereinigung fuer pins-hotspot)` (damit Ubuntu Server `wlp2s0` nach jedem Reboot verwaltet) und aktiviert `pins-hotspot` direkt per `nmcli con up`.

- **CCD Simulator Binary (`/usr/bin/indi_simulator_ccd`):** Das kompilierte, gepatchte `indi_simulator_ccd` (`3008x3008`, `3.76 um`, `~/test-fits`, `Use Dir.`) wird explizit nach `/usr/bin/indi_simulator_ccd` installiert, damit N.I.N.A. nicht das unveraenderte `indi-bin`-Paketbinary laedt.

- **Touch 'N' Stars FITS-Dateibrowser (`~/.config/user-dirs.dirs`):** Setzt `XDG_DOCUMENTS_DIR="$HOME"`, damit .NET (`SpecialFolder.MyDocuments`) auf Ubuntu Server nicht `""` zurueckgibt und `FilesystemController.Browse()` ohne `Parameter 'path'`-Fehler startet.

- **Astro-Session-Schutz (`99-no-auto-restart.conf` - **Touch 'N' Stars VNC-Defaultport (`5901`):** Ersetzt in `vnc-remote-*.js` den Standardport `6080` durch `5901` (PHD2 `x11vnc`), damit bei Tab-Wechseln immer `5901` vorbelegt bleibt.

- **Terminal-VNC (`term-vnc.service`, Port `5902`):** Startet eine kopflose `Xvfb :2` + `xterm`-Shell per `x11vnc` auf Port `5902` (Passwort `1234`), direkt ueber den Touch 'N' Stars VNC-Tab nutzbar.

## 2. Skripte deaktivierte `apt-daily`-Timer):** Verhindert, dass Ubuntu morgens um ~06:41 Uhr ueber `unattended-upgrades`/`needrestart` laufende Astro-Dienste (`pins`, `phd2`, VNC) mitten in einer Session neu startet.

- **Touch 'N' Stars VNC-Defaultport (`5901`):** Ersetzt in `vnc-remote-*.js` den Standardport `6080` durch `5901` (PHD2 `x11vnc`), damit bei Tab-Wechseln immer `5901` vorbelegt bleibt.

- **Terminal-VNC (`term-vnc.service`, Port `5902`):** Startet eine kopflose `Xvfb :2` + `xterm`-Shell per `x11vnc` auf Port `5902` (Passwort `1234`), direkt ueber den Touch 'N' Stars VNC-Tab nutzbar.

## 2. Skripte & Dokumentation im Repository
- `setup-pins-astro.sh`: Vollautomatisches, idempotentes Setup (Schritte 1–12).
- `restart-astro.sh`: Sauberer Neustart aller Astro-Dienste in Boot-Reihenfolge ohne Reboot.
- `prepare-test-fits.sh`: Bereitet Test-FITS in `\$HOME/test-fits/` für den Simulator auf.
- `AGENT_RULES.md` & `.github/copilot-instructions.md`: Verbindliche Architektur- und Output-Regeln.
- `PROMPT_TEMPLATE.md`: URL-freie Start-Preamble für neue KI-Threads.
