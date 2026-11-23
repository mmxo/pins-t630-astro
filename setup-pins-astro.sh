#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOTSPOT_SSID="pins-T630"
HOTSPOT_PASS="astro1234" # Hier bei Bedarf eigenes Passwort eintragen (min. 8 Zeichen)

echo "=== 1. System-Pakete, INDI, PHD2, VNC & Build-Tools ==="
sudo apt update
sudo apt install -y software-properties-common
sudo apt update
sudo apt install -y git curl wget unzip build-essential gcc python3 cmake ninja-build \
  libtesseract-dev libleptonica-dev indi-bin    \
   xvfb x11vnc matchbox-window-manager netcat-openbsd \
  libcfitsio-dev libnova-dev libusb-1.0-0-dev libopencv-dev

if ! dotnet --list-sdks 2>/dev/null | grep -q "10.0.400"; then
  URL=$(echo "aHR0cHM6Ly9idWlsZHMuZG90bmV0Lm1pY3Jvc29mdC5jb20vZG90bmV0L3NjcmlwdHMvdjEvZG90bmV0LWluc3RhbGwuc2g=" | base64 -d)
  curl -sSL "$URL" -o /tmp/dotnet-install.sh
  sudo bash /tmp/dotnet-install.sh --version 10.0.400 --install-dir /usr/share/dotnet
  sudo ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
  rm -f /tmp/dotnet-install.sh
fi
echo "=== 2. PINS-Basis-Installation (falls noch nicht vorhanden) ==="
if [ ! -f "$HOME/pins/NINA.dll" ]; then
  [ ! -d "$HOME/pins-src" ] && git clone https://github.com/nitr57/pins.git "$HOME/pins-src"
  export PATH="$HOME/.dotnet:$PATH"
  chmod +x "$HOME/pins-src/build-and-install-pins-x64.sh"
  cd "$HOME/pins-src"
  ./build-and-install-pins-x64.sh || sudo apt-get install -f -y
fi

echo "=== 3. Rechte & USB-Autosuspend ==="
sudo usermod -aG dialout "$USER"
grep -q "usbcore.autosuspend=-1" /etc/default/grub || {
  sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="usbcore.autosuspend=-1 /' /etc/default/grub
  sudo update-grub
}

echo "=== 4. Feste udev-Regeln fuer HP t630 (/dev/focusser & /dev/mount) ==="
sudo rm -f /etc/udev/rules.d/99-astro-devices.rules
sudo tee /etc/udev/rules.d/99-astro-hardware.rules > /dev/null << 'UDEV'
SUBSYSTEM=="tty", KERNELS=="2-2.1", SYMLINK+="focusser", MODE="0666"
SUBSYSTEM=="tty", KERNELS=="2-3.4", SYMLINK+="mount", MODE="0666"
UDEV
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=tty

echo "=== 5. PINS, INDI-FIFO-Patch, OpenCvSharpExtern & CCD-Simulator-FITS-Replay ==="
cd "$HOME/pins-src"
python3 -c '
p="NINA.INDI/INDIClient.cs"
s=open(p).read()
o="if (!WriteFifoCommand($\"start {driverName}\", TimeSpan.FromSeconds(5))) {"
n="var execPath = driverName.StartsWith(\"/\") ? driverName : $\"/usr/bin/{driverName}\";\n                if (!WriteFifoCommand($\"start {execPath}\", TimeSpan.FromSeconds(5))) {"
if o in s and n not in s: open(p,"w").write(s.replace(o,n,1))
'
dotnet restore NINA/NINA.csproj -r linux-x64
dotnet build NINA/NINA.csproj -c Release -r linux-x64 --no-restore
dotnet publish NINA/NINA.csproj -c Release -r linux-x64 --no-build -o "$HOME/pins"
dotnet build NINA.INDI/NINA.INDI.csproj -c Release -o "$HOME/pins/"
find "$HOME/.local/share/NINA/Plugins" -name "NINA.INDI.dll" -exec cp -f "$HOME/pins/NINA.INDI.dll" {} \;

OCS_VER=$(find "$HOME/.nuget/packages/opencvsharp4" -maxdepth 1 -mindepth 1 -printf "%f\n" 2>/dev/null | sort -V | tail -n 1)
rm -rf /tmp/opencvsharp-src /tmp/build-ocs
OCS_URL=$(echo "aHR0cHM6Ly9naXRodWIuY29tL3NoaW1hdC9vcGVuY3ZzaGFycC5naXQ=" | base64 -d)
git clone --depth 1 --branch "${OCS_VER}" "$OCS_URL" /tmp/opencvsharp-src 2>/dev/null || git clone --depth 1 "$OCS_URL" /tmp/opencvsharp-src
cmake -S /tmp/opencvsharp-src/src -B /tmp/build-ocs -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/build-ocs -j$(nproc)
cp -f /tmp/build-ocs/OpenCvSharpExtern/libOpenCvSharpExtern.so "$HOME/pins/"
rm -rf /tmp/opencvsharp-src /tmp/build-ocs

find "$HOME/pins/External/linux-x64" -type f -name "*.so*" -exec ln -sf {} "$HOME/pins/" \;

echo "=== 6. libXISF-Trennung, indiserver-Wrapper & MyFocuserPro2-XML ==="
command -v indiserver >/dev/null 2>&1 || sudo apt-get install -y indi-bin
ls /usr/local/lib/libXISF* >/dev/null 2>&1 && sudo mv -f /usr/local/lib/libXISF* "$HOME/pins/" && sudo ldconfig
[ ! -f /usr/bin/indiserver.bin ] && sudo mv -f /usr/bin/indiserver /usr/bin/indiserver.bin
printf '#!/bin/bash\nexport LD_PRELOAD=/home/hase/pins/libXISF.so.0.2.13\nexec /usr/bin/indiserver.bin "$@"\n' | sudo tee /usr/bin/indiserver > /dev/null
sudo chmod +x /usr/bin/indiserver


sudo tee /usr/share/indi/indi_myfocuserpro2.xml > /dev/null << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<driversList><devGroup group="Focusers"><device label="MyFocuserPro2" mdpd="true"><driver name="MyFocuserPro2">indi_myfocuserpro2_focus</driver><version>1.0</version></device></devGroup></driversList>
XML

[ -x "$SCRIPT_DIR/prepare-test-fits.sh" ] && "$SCRIPT_DIR/prepare-test-fits.sh" || true

echo "=== 7. Gespeicherte PHD2- & INDI-Configs wiederherstellen ==="
mkdir -p "$HOME/.indi"
[ -f "$SCRIPT_DIR/configs/CCD Simulator_config.xml" ] && cp -f "$SCRIPT_DIR/configs/CCD Simulator_config.xml" "$HOME/.indi/"
[ -f "$SCRIPT_DIR/configs/PHDGuidingV2.conf" ] && cp -f "$SCRIPT_DIR/configs/PHDGuidingV2.conf" "$HOME/.PHDGuidingV2"
cp -f "$SCRIPT_DIR/configs/"*.xml "$HOME/.indi/" 2>/dev/null || true

echo "=== 8. Systemd-Dienste (PHD2 Headless + randloses VNC & PINS) ==="
sudo systemctl disable --now sysupdate-api.service 2>/dev/null || true
sudo apt-mark hold pins indi-bin

sudo tee /etc/systemd/system/phd2.service > /dev/null << 'SVC'
[Unit]
Description=PHD2 Guiding Daemon (Headless)
Before=pins.service
After=network.target

[Service]
Type=simple
User=hase
ExecStartPre=-/bin/rm -f /tmp/*phd2* /tmp/*PHD2* /home/hase/phd2.* /home/hase/.PHDGuidingV2-instance* /tmp/xvfb-phd2.auth
ExecStart=/usr/bin/xvfb-run -n 99 -f /tmp/xvfb-phd2.auth -s "-screen 0 1280x800x24" /bin/sh -c 'matchbox-window-manager -use_titlebar no & exec /usr/bin/phd2'
Restart=always
RestartSec=3
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
SVC

sudo tee /etc/systemd/system/x11vnc-phd2.service > /dev/null << 'VNC'
[Unit]
Description=x11vnc for PHD2 Xvfb Display
After=phd2.service
Requires=phd2.service

[Service]
Type=simple
User=hase
ExecStartPre=/bin/sh -c 'for i in $(seq 1 15); do [ -f /tmp/xvfb-phd2.auth ] && exit 0; sleep 1; done; exit 1'
ExecStart=/usr/bin/x11vnc -display :99 -auth /tmp/xvfb-phd2.auth -rfbport 5901 -passwd 1234 -noxdamage -shared -forever
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
VNC

echo "hase ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /sbin/poweroff, /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot" | sudo tee /etc/sudoers.d/pins-power > /dev/null
sudo chmod 0440 /etc/sudoers.d/pins-power
sudo systemctl daemon-reload
sudo systemctl enable phd2.service x11vnc-phd2.service pins.service

echo "=== 9. Touch 'N' Stars Patch: Unbeschnittenes 4:3 PHD2-Vorschaubild ==="
python3 -c '
import glob
old = "S=i(()=>u.value?{top:`80px`,height:`calc(100% - 80px)`}:{top:`0`,height:`100%`})"
new = "S=i(()=>u.value?{top:`80px`,height:`calc(100% - 80px - var(--above-statusbar, 0px) - var(--status-panel-height, 260px) - 1rem)`}:{top:`0`,height:`calc(100% - var(--status-panel-height, 240px) - 1rem)`})"
for p in glob.glob("/home/hase/.local/share/NINA/Plugins/*/Touch-N-Stars/app/assets/GuidingPage-*.js"):
    s = open(p).read()
    if old in s:
        open(p + ".bak", "w").write(s)
        open(p, "w").write(s.replace(old, new, 1))
        print("Patch angewendet auf:", p)
'

echo "=== N.I.N.A. Northern Sky Offline Sky Map Cache (1.4 GB) laden ==="
mkdir -p "$HOME/.local/share/NINA/FramingAssistantCache"
if [ "$(du -sm "$HOME/.local/share/NINA/FramingAssistantCache" | cut -f1)" -lt 500 ]; then
  SKY_URL=$(curl -fsSL "https://nighttime-imaging.eu/download/" | grep -oiE 'https://[^"]+Northern[^"]+\.zip' | grep -vi 'starless' | head -n 1)
  curl -fL --progress-bar "$SKY_URL" -o /tmp/nina-northern-sky.zip && \
  unzip -oq /tmp/nina-northern-sky.zip -d "$HOME/.local/share/NINA/FramingAssistantCache/" && \
    mv -f "$HOME/.local/share/NINA/FramingAssistantCache"/FramingAssistantCache_*/* "$HOME/.local/share/NINA/FramingAssistantCache/" 2>/dev/null || true && \
    rmdir "$HOME/.local/share/NINA/FramingAssistantCache"/FramingAssistantCache_* 2>/dev/null || true && \
  rm -f /tmp/nina-northern-sky.zip
fi

echo "=== ASTAP Plate Solver & D50 Sternkatalog installieren ==="
if [ ! -f /opt/astap/astap ] || [ -z "$(ls /opt/astap/*.290 2>/dev/null)" ]; then
  ASTAP_BASE=$(echo "aHR0cHM6Ly9zb3VyY2Vmb3JnZS5uZXQvcHJvamVjdHMvYXN0YXAtcHJvZ3JhbS9maWxlcw==" | base64 -d)
  curl -fL --progress-bar "$ASTAP_BASE/linux_installer/astap_amd64.deb/download" -o /tmp/astap_amd64.deb && \
  curl -fL --progress-bar "$ASTAP_BASE/star_databases/d50_star_database.deb/download" -o /tmp/d50_star_database.deb && \
  (sudo dpkg -i /tmp/astap_amd64.deb /tmp/d50_star_database.deb || sudo apt-get install -f -y) && \
  rm -f /tmp/astap_amd64.deb /tmp/d50_star_database.deb
  sudo ln -sf /opt/astap/astap_cli /usr/local/bin/astap_cli
fi

echo "=== Absoluten Bild-Speicherpfad (/home/hase/astro-images) setzen ==="
mkdir -p "$HOME/astro-images"
for prof in "$HOME/.local/share/NINA/Profiles"/*.profile; do
  [ -f "$prof" ] && sed -i "s|<ImageFilePath>.*</ImageFilePath>|<ImageFilePath>$HOME/astro-images</ImageFilePath>|g" "$prof"
done

echo "=== 10. 2.4 GHz Dauer-Hotspot ($HOTSPOT_SSID) einrichten ==="
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
