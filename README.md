# HP t630 – PINS / N.I.N.A. & PHD2 Astro-Setup (Ubuntu x64)

## Hardware & USB-Port-Zuordnung (`udev`)
- **Hauptkamera:** SVBONY SV605CC (USB 3.0, nativer Treiber in PINS)
- **Guiding-Kamera:** ZWO ASI120MM Mini (USB 2.0, via PHD2)
- **Montierung:** Terrans OnStep (9600 Baud, INDI `LX200 OnStep`) -> `/dev/mount` (Port `2-3.4`)
- **Focuser:** Gemini Focuser (nativer Treiber) -> `/dev/focusser` (Port `2-2.1`)

## Netzwerk & Zugriff
- **Dauer-Hotspot (WLAN `wlp2s0`):** SSID `pins-T630` (2,4 GHz, Kanal 6, Powersave aus)
- **Touch 'N' Stars Web-Oberflaeche:** `http://10.42.0.1:5000`
- **PHD2 Live-VNC:** `10.42.0.1:5901` (Passwort: `1234`)
- **Wartung / Updates:** LAN-Kabel an `enp1s0` anstecken (laeuft parallel zum Hotspot)
