#!/bin/bash
set -e

PKG_DIR="/tmp/pins-t630-release"
OUT_FILE="$HOME/pins-t630-astro-release-$(date +%Y%m%d).tar.gz"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/bins" "$PKG_DIR/configs" "$PKG_DIR/systemd" "$PKG_DIR/udev"

# 1. Fertig kompilierte PINS- & Plugin-Verzeichnisse sichern (ohne riesige Log-/Image-Caches)
cp -a "$HOME/pins" "$PKG_DIR/bins/pins"
cp -a "$HOME/.local/share/NINA" "$PKG_DIR/bins/NINA-data"
rm -rf "$PKG_DIR/bins/NINA-data/Logs/"* "$PKG_DIR/bins/NINA-data/TnsCache/"* 2>/dev/null || true
cp -f /usr/bin/indi_simulator_ccd "$PKG_DIR/bins/"

# 2. System-Konfigurationen & Services einsammeln
cp -f /etc/systemd/system/phd2.service /etc/systemd/system/x11vnc-phd2.service "$PKG_DIR/systemd/"
[ -f /etc/systemd/system/pins.service ] && cp -f /etc/systemd/system/pins.service "$PKG_DIR/systemd/"
cp -f /etc/udev/rules.d/99-astro-hardware.rules "$PKG_DIR/udev/"
cp -f "$HOME/.PHDGuidingV2" "$PKG_DIR/configs/PHDGuidingV2.conf"
cp -f "$HOME/.indi/"*.xml "$PKG_DIR/configs/" 2>/dev/null || true

# 3. 1-Klick-Installer fuer das Zielsystem erzeugen
cat << 'INST' > "$PKG_DIR/install-offline.sh"
#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
HOTSPOT_SSID="pins-T630"
HOTSPOT_PASS="astro1234"

sudo apt update
sudo apt install -y dotnet-runtime-8.0 aspnetcore-runtime-8.0 indi-bin indi-svbony indi-asi \
  indi-lx200-onstep indi-myfocuserpro2 phd2 xvfb x11vnc matchbox-window-manager netcat-openbsd \
  libcfitsio10t64 libnova-0.16-0t64 libusb-1.0-0 libtesseract5 libleptonica6

sudo usermod -aG dialout "$USER"
grep -q "usbcore.autosuspend=-1" /etc/default/grub || {
  sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="usbcore.autosuspend=-1 /' /etc/default/grub
  sudo update-grub
}

rm -rf "$HOME/pins" "$HOME/.local/share/NINA"
mkdir -p "$HOME/.local/share" "$HOME/.indi"
cp -a "$DIR/bins/pins" "$HOME/pins"
cp -a "$DIR/bins/NINA-data" "$HOME/.local/share/NINA"
sudo cp -f "$DIR/bins/indi_simulator_ccd" /usr/bin/indi_simulator_ccd

[ ! -f /usr/bin/indiserver.bin ] && sudo mv -f /usr/bin/indiserver /usr/bin/indiserver.bin
printf '#!/bin/bash\nexport LD_PRELOAD=/home/hase/pins/libXISF.so.0.2.13\nexec /usr/bin/indiserver.bin "$@"\n' | sudo tee /usr/bin/indiserver > /dev/null
sudo chmod +x /usr/bin/indiserver

sudo tee /usr/share/indi/indi_myfocuserpro2.xml > /dev/null << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<driversList><devGroup group="Focusers"><device label="MyFocuserPro2" mdpd="true"><driver name="MyFocuserPro2">indi_myfocuserpro2_focus</driver><version>1.0</version></device></devGroup></driversList>
XML

sudo cp -f "$DIR/udev/99-astro-hardware.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=tty

cp -f "$DIR/configs/PHDGuidingV2.conf" "$HOME/.PHDGuidingV2"
cp -f "$DIR/configs/"*.xml "$HOME/.indi/" 2>/dev/null || true

sudo cp -f "$DIR/systemd/"*.service /etc/systemd/system/
echo "hase ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /sbin/poweroff, /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot" | sudo tee /etc/sudoers.d/pins-power > /dev/null
sudo chmod 0440 /etc/sudoers.d/pins-power
sudo systemctl daemon-reload
sudo systemctl enable phd2.service x11vnc-phd2.service pins.service
sudo apt-mark hold pins indi-bin

WIFI_DEV=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi" {print $1; exit}')
if [ -n "$WIFI_DEV" ]; then
  for conn in $(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless" && $1!="Hotspot" {print $1}'); do
    sudo nmcli connection delete "$conn" || true
  done
  if ! nmcli connection show Hotspot >/dev/null 2>&1; then
    sudo nmcli dev wifi hotspot ifname "$WIFI_DEV" con-name Hotspot ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASS"
  fi
  sudo nmcli connection modify Hotspot 802-11-wireless.ssid "$HOTSPOT_SSID"
  sudo nmcli connection modify Hotspot 802-11-wireless.band bg
  sudo nmcli connection modify Hotspot 802-11-wireless.channel 6
  sudo nmcli connection modify Hotspot connection.autoconnect yes
  sudo nmcli connection modify Hotspot connection.autoconnect-priority 100
  sudo nmcli connection modify Hotspot 802-11-wireless.powersave 2
fi

echo "Installation abgeschlossen! Bitte jetzt 'sudo reboot' ausfuehren."
INST
chmod +x "$PKG_DIR/install-offline.sh"

tar -czf "$OUT_FILE" -C /tmp pins-t630-release
rm -rf "$PKG_DIR"
echo "Fertiges Installationspaket erstellt: $OUT_FILE"
