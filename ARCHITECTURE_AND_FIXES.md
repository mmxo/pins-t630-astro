# Architektur-Entscheidungen & Gelöste Probleme (pins-t630-astro)

Diese Datei dokumentiert alle technischen Fixes aus der Entwicklung, damit künftige Änderungen keine bereits gelösten Probleme erneut aufreißen.

## 1. Gelöste Stolpersteine & verbindliche Lösungen
- **Kein Snap (`snapd`):** Entfernt und via `/etc/apt/preferences.d/nosnap.pref` gesperrt (spart RAM/Bootzeit).
- **INDI FIFO Treiberstart (`NINA.INDI/INDIClient.cs`):** Gepatcht auf `/usr/bin/{driverName}`, da N.I.N.A. sonst Treiber ohne vollen Pfad nicht über `/tmp/indiFIFO` starten kann.
- **`libXISF`-Trennung:** `libXISF*` liegt isoliert in `$HOME/pins/` (nicht in `/usr/local/lib`) und wird nur gezielt per `LD_PRELOAD` im `/usr/bin/indiserver`-Wrapper geladen.
- **`OpenCvSharpExtern`:** Wird passend zur installierten NuGet-Version (`opencvsharp4`) lokal kompiliert und nach `$HOME/pins/` kopiert.
- **`CCD Simulator` (`ccd_simulator.cpp`):** Defaults direkt im C++-Quellcode auf `$HOME/test-fits`, `Use Dir. = Enabled (ISS_ON)`, `3008x3008` und `3.76 um` gepatcht. **Wichtig:** Kein Wrapper um `indi_simulator_ccd` bauen (führt sonst zu `DRIVER_INFO`-Timeout)!
- **PHD2 Headless & VNC:** Läuft auf Xvfb `:99` mit `matchbox-window-manager -use_titlebar no` + `x11vnc` auf Port `5901`; Touch 'N' Stars `GuidingPage-*.js` ist auf unbeschnittene 4:3-Darstellung gepatcht.
- **Bild-Speicherpfad (`ImageFilePath`):** Muss ein absoluter Pfad (`$HOME/astro-images`) im `.profile` sein (relativer Pfad führt zu `System.UriFormatException` in `ImageSaveController`).
- **Offline-Kataloge & Netzwerk:** Northern Sky Map (`1.4 GB`) in `~/.local/share/NINA/FramingAssistantCache`, ASTAP + D50 unter `/opt/astap/`, Samba-Share `[astro]` (`smb://10.42.0.1/astro`) und 2.4-GHz-Hotspot `pins-T630` (`astro1234`, `wifi-sec.psk` explizit per `nmcli modify` gesetzt).

## 2. Hilfsskripte im Repo
- `setup-pins-astro.sh`: Vollautomatisches, idempotentes Setup (Schritte 1–12).
- `restart-astro.sh`: Sauberer Kaltstart-ähnlicher Neustart aller Astro-Dienste ohne Reboot.
- `prepare-test-fits.sh`: Bereitet Test-FITS in `$HOME/test-fits/` für den Simulator auf.
