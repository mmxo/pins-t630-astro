# Architektur-Entscheidungen & Gelöste Probleme (pins-t630-astro)

Diese Datei dokumentiert den geprüften Endstand und alle technischen Root-Cause-Fixes, damit künftige Änderungen keine bereits gelösten Probleme erneut aufreißen.

## 1. Geprüfter Endstand & Verbindliche Fixes
- **Kein Snap (`snapd`):** Entfernt und via `/etc/apt/preferences.d/nosnap.pref` dauerhaft gesperrt.
- **INDI FIFO Treiberstart (`NINA.INDI/INDIClient.cs`):** Gepatcht auf `/usr/bin/{driverName}`, damit N.I.N.A. Treiber über `/tmp/indiFIFO` zuverlässig startet.
- **`libXISF`-Trennung:** `libXISF*` liegt isoliert in `\(HOME/pins/` (nicht dauerhaft in `/usr/local/lib`) und wird nur gezielt per `LD_PRELOAD` im `/usr/bin/indiserver`-Wrapper geladen. Beim Neukompilieren von `indi_simulator_ccd` wird `libXISF.so*` nur kurzzeitig für den Ninja-Linker nach `/usr/local/lib/` verlinkt und sofort wieder entfernt. - **`OpenCvSharpExtern`:** Wird passend zur installierten NuGet-Version (`opencvsharp4`) lokal kompiliert und nach `\)HOME/pins/` kopiert.
- **`CCD Simulator` (`ccd_simulator.cpp`) – Kaltstart- & Reboot-fester C++-Patch:**
  - Defaults in `initProperties()` auf `\$HOME/test-fits`, `Use Dir. = Enabled (ISS_ON)`, `3008x3008` und `3.76 um` gepatcht.
  - `watchDirectory()` in `updateProperties()` beim Connect ergänzt, damit `m_AllFiles` sofort gefüllt wird.
  - `StartExposure()` auf `watchDirectory() (liest Verzeichnis bei jeder Aufnahme live neu ein und rotiert alphabetisch durch alle .fits)` gepatcht, damit N.I.N.A.s `.profile`-Switch-Reset beim Connect das FITS-Replay nie wieder abschaltet.
  - Vor `cmake --build` wird `ccd_simulator.cpp.o` gelöscht, damit Ninja die C++-Änderungen garantiert neu übersetzt.
  - **Wichtig:** Keinen Wrapper um `indi_simulator_ccd` bauen (führt sonst zu `DRIVER_INFO`-Timeout).
- **PHD2 Headless & VNC:** Xvfb `:99` mit `matchbox-window-manager -use_titlebar no` + `x11vnc` auf Port `5901` (`1234`); Touch 'N' Stars `GuidingPage-*.js` auf unbeschnittene 4:3-Darstellung gepatcht.
- **Bild-Speicherpfad (`ImageFilePath`):** Absoluter Pfad `\$HOME/astro-images` im `.profile` (verhindert `System.UriFormatException` in `ImageSaveController`).
- **Offline-Kataloge & Netzwerk:** Northern Sky Map (`1.4 GB`) in `~/.local/share/NINA/FramingAssistantCache`, ASTAP + D50 unter `/opt/astap/`, Samba-Share `[astro]` (`smb://10.42.0.1/astro`) und 2.4-GHz-Hotspot `pins-T630` (`astro1234`, `wifi-sec.psk` explizit per `nmcli modify` gesetzt).

## 2. Skripte im Repository
- `setup-pins-astro.sh`: Vollautomatisches, idempotentes Setup (Schritte 1–12).
- `restart-astro.sh`: Sauberer Neustart aller Astro-Dienste in Boot-Reihenfolge ohne Reboot.
- `prepare-test-fits.sh`: Bereitet Test-FITS in `\$HOME/test-fits/` für den Simulator auf.
