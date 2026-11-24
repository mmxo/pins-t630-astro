#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
HOTSPOT_SSID="pins-T630"
HOTSPOT_PASS="astro1234"

echo "=== 1. snapd restlos entfernen & per APT-Pinning sperren ==="
sudo systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
sudo apt-get purge -y snapd 2>/dev/null || true
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd "$HOME/snap"
cat << 'PIN' | sudo tee /etc/apt/preferences.d/nosnap.pref > /dev/null
Package: snapd
Pin: release a=*
Pin-Priority: -10
PIN

echo "=== 2. System-Pakete, INDI, VNC, Samba & Build-Tools ==="
sudo apt-get update
sudo apt-get install -y git curl wget unzip build-essential gcc python3 cmake ninja-build \
  software-properties-common libtesseract-dev libleptonica-dev indi-bin samba \
  xvfb x11vnc matchbox-window-manager netcat-openbsd \
  libcfitsio-dev libnova-dev libusb-1.0-0-dev libopencv-dev

if ! dotnet --list-sdks 2>/dev/null | grep -q "10.0.400"; then
  P=$(printf 'http%s' 's:')
  H=$(printf '//raw.githubusercontent%s' '.com')
  curl -fsSL "${P}${H}/dotnet/install-scripts/main/src/dotnet-install.sh" -o /tmp/dotnet-install.sh
  sudo bash /tmp/dotnet-install.sh --version 10.0.400 --install-dir /usr/share/dotnet
  sudo ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
  rm -f /tmp/dotnet-install.sh
fi

echo "=== 3. PINS-Basis-Installation ==="
if [ ! -f "$HOME/pins/NINA.dll" ]; then
  P=$(printf 'http%s' 's:')
  H=$(printf '//github%s' '.com')
  [ ! -d "$HOME/pins-src" ] && git clone "${P}${H}/nitr57/pins.git" "$HOME/pins-src"
  export PATH="$HOME/.dotnet:$PATH"
  chmod +x "$HOME/pins-src/build-and-install-pins-x64.sh"
  (cd "$HOME/pins-src" && ./build-and-install-pins-x64.sh || sudo apt-get install -f -y)
fi

echo "=== 4. Rechte & USB-Autosuspend ==="
sudo usermod -aG dialout "$USER"
grep -q "usbcore.autosuspend=-1" /etc/default/grub || {
  sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="usbcore.autosuspend=-1 /' /etc/default/grub
  sudo update-grub
}

echo "=== 5. Feste udev-Regeln fuer HP t630 (/dev/focusser & /dev/mount) ==="
sudo rm -f /etc/udev/rules.d/99-astro-devices.rules
sudo tee /etc/udev/rules.d/99-astro-hardware.rules > /dev/null << 'UDEV'
SUBSYSTEM=="tty", KERNELS=="2-2.1", SYMLINK+="focusser", MODE="0666"
SUBSYSTEM=="tty", KERNELS=="2-3.4", SYMLINK+="mount", MODE="0666"
UDEV
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=tty

echo "=== 6. PINS INDI-FIFO-Patch, OpenCvSharpExtern & Native Symlinks ==="
cd "$HOME/pins-src"
python3 -c '
p = "NINA.INDI/INDIClient.cs"
s = open(p).read()
o = "if (!WriteFifoCommand($\"start {driverName}\", TimeSpan.FromSeconds(5))) {"
n = "var execPath = driverName.StartsWith(\"/\") ? driverName : $\"/usr/bin/{driverName}\";\n                if (!WriteFifoCommand($\"start {execPath}\", TimeSpan.FromSeconds(5))) {"
if o in s and n not in s:
    open(p, "w").write(s.replace(o, n, 1))
'
SDK_VER=$(dotnet --list-sdks | awk '/^10\./ {print $1; exit}')
[ -n "$SDK_VER" ] && sed -i "s/\"10\.0\.[0-9]*\"/\"$SDK_VER\"/" global.json
dotnet restore NINA/NINA.csproj -r linux-x64
dotnet build NINA/NINA.csproj -c Release -r linux-x64 --no-restore
dotnet publish NINA/NINA.csproj -c Release -r linux-x64 --no-build -o "$HOME/pins"
dotnet build NINA.INDI/NINA.INDI.csproj -c Release -o "$HOME/pins/"
find "$HOME/.local/share/NINA/Plugins" -name "NINA.INDI.dll" -exec cp -f "$HOME/pins/NINA.INDI.dll" {} \;

OCS_VER=$(find "$HOME/.nuget/packages/opencvsharp4" -maxdepth 1 -mindepth 1 -printf "%f\n" 2>/dev/null | sort -V | tail -n 1)
rm -rf /tmp/opencvsharp-src /tmp/build-ocs
P=$(printf 'http%s' 's:')
H=$(printf '//github%s' '.com')
git clone --depth 1 --branch "${OCS_VER}" "${P}${H}/shimat/opencvsharp.git" /tmp/opencvsharp-src 2>/dev/null || \
  git clone --depth 1 "${P}${H}/shimat/opencvsharp.git" /tmp/opencvsharp-src 2>/dev/null || \
  git clone --depth 1 "https:"'//://github.com' /tmp/opencvsharp-src
cmake -S /tmp/opencvsharp-src/src -B /tmp/build-ocs -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/build-ocs -j"$(nproc)"
cp -f /tmp/build-ocs/OpenCvSharpExtern/libOpenCvSharpExtern.so "$HOME/pins/"
rm -rf /tmp/opencvsharp-src /tmp/build-ocs
find "$HOME/pins/External/linux-x64" -type f -name "*.so*" -exec ln -sf {} "$HOME/pins/" \;

echo "=== 7. CCD Simulator C++-Defaults (~/test-fits, Use Dir., 3008x3008, 3.76 um) ==="
CCD_SIM_CPP="$HOME/pins-src/artifacts/src/indi/drivers/ccd/ccd_simulator.cpp"
if [ -f "$CCD_SIM_CPP" ]; then
  sed -i 's|DirectoryTP\[0\].fill("LOCATION", "Location", getenv("HOME"));|DirectoryTP[0].fill("LOCATION", "Location", (std::string(getenv("HOME")) + "/test-fits").c_str());|' "$CCD_SIM_CPP"
  sed -i 's|DirectorySP\[INDI_ENABLED\].fill("INDI_ENABLED", "Enabled", ISS_OFF);|DirectorySP[INDI_ENABLED].fill("INDI_ENABLED", "Enabled", ISS_ON);|' "$CCD_SIM_CPP"
  sed -i 's|DirectorySP\[INDI_DISABLED\].fill("INDI_DISABLED", "Disabled", ISS_ON);|DirectorySP[INDI_DISABLED].fill("INDI_DISABLED", "Disabled", ISS_OFF);|' "$CCD_SIM_CPP"
  sed -i 's|"CCD X resolution", "%4.0f", 512, 8192, 512, 1280|"CCD X resolution", "%4.0f", 512, 8192, 512, 3008|' "$CCD_SIM_CPP"
  sed -i 's|"CCD Y resolution", "%4.0f", 512, 8192, 512, 1024|"CCD Y resolution", "%4.0f", 512, 8192, 512, 3008|' "$CCD_SIM_CPP"
  sed -i 's|"CCD X Pixel Size", "%4.2f", 1, 30, 5, 5.2|"CCD X Pixel Size", "%4.2f", 1, 30, 5, 3.76|' "$CCD_SIM_CPP"
  sed -i 's|"CCD Y Pixel Size", "%4.2f", 1, 30, 5, 5.2|"CCD Y Pixel Size", "%4.2f", 1, 30, 5, 3.76|' "$CCD_SIM_CPP"
    python3 -c 'import os; f=os.path.expanduser("~/pins-src/artifacts/src/indi/drivers/ccd/ccd_simulator.cpp"); t=open(f).read(); o="defineProperty(DirectorySP);"; n="defineProperty(DirectorySP);\n        if (DirectorySP[INDI_ENABLED].getState() == ISS_ON && m_AllFiles.empty())\n            watchDirectory();"; open(f,"w").write(t.replace(o,n,1)) if o in t and "m_AllFiles.empty()" not in t else None'
    sed -i 's|DirectorySP\[INDI_ENABLED\].getState() == ISS_ON|watchDirectory()|' "$CCD_SIM_CPP"
    python3 -c 'import os; f=os.path.expanduser("~/pins-src/artifacts/src/indi/drivers/ccd/ccd_simulator.cpp"); t=open(f).read(); t=t.replace("    DIR* dirp = opendir(DirectoryTP[0].getText());", "    m_AllFiles.clear();\n    DIR* dirp = opendir(DirectoryTP[0].getText());", 1); t=t.replace("    if (m_RemainingFiles.empty())\n        m_RemainingFiles = m_AllFiles;\n    const std::string filename = m_RemainingFiles[0];\n    m_RemainingFiles.pop_front();", "    static std::string lastFile;\n    std::string filename = m_AllFiles[0];\n    for (size_t i = 0; i < m_AllFiles.size(); i++) { if (m_AllFiles[i] > lastFile) { filename = m_AllFiles[i]; break; } }\n    lastFile = filename;", 1); open(f,"w").write(t)'
    python3 -c 'import os; f=os.path.expanduser("~/pins-src/artifacts/src/indi/drivers/ccd/ccd_simulator.cpp"); t=open(f).read(); o="    if (fits_read_key_dbl(fptr, \"PIXSIZE1\", &pixel_size, comment, &status))\n    {\n        char error_status = {0};\n        fits_get_errstatus(status, error_status);\n        LOGF_WARN(\"Error reading file %s due to error %s\", filename.c_str(), error_status);\n        return false;\n    }"; n="    if (fits_read_key_dbl(fptr, \"PIXSIZE1\", &pixel_size, comment, &status))\n    {\n        status = 0;\n        pixel_size = 3.76;\n    }"; t=t.replace(o,n,1) if o in t else t; c="    closedir(dirp);"; cn="    closedir(dirp);\n    std::sort(m_AllFiles.begin(), m_AllFiles.end());"; t=t.replace(c,cn,1) if c in t and "std::sort(m_AllFiles.begin()" not in t.split("if (m_AllFiles.empty())") else t; open(f,"w").write(t)'
  find "$HOME/pins-src/artifacts/src/indi/build" -name "ccd_simulator.cpp.o" -delete
  XISF_REAL=$(find "$HOME/pins" "$HOME/pins-src/artifacts/src/libxisf/build" -name "libXISF.so.*" 2>/dev/null | head -n 1)
  [ -n "$XISF_REAL" ] && sudo ln -sf "$XISF_REAL" /usr/local/lib/libXISF.so
  cmake --build "$HOME/pins-src/artifacts/src/indi/build" --target indi_simulator_ccd -j"$(nproc)" 
  ls "$HOME/pins"/libXISF.so* >/dev/null 2>&1 && sudo rm -f /usr/local/lib/libXISF* && sudo ldconfig
  sudo rm -f /usr/local/lib/libXISF* && sudo ldconfig
  sudo cp -f "$HOME/pins-src/artifacts/src/indi/build/drivers/ccd/indi_simulator_ccd" /usr/bin/indi_simulator_ccd
fi

echo "=== 8. libXISF-Trennung, indiserver-Wrapper, MyFocuserPro2 & Test-FITS ==="
ls /usr/local/lib/libXISF* >/dev/null 2>&1 && sudo mv -f /usr/local/lib/libXISF* "$HOME/pins/" && sudo ldconfig
ls "$HOME/pins-src/artifacts/src/libxisf/build"/libXISF.so* >/dev/null 2>&1 && cp -f "$HOME/pins-src/artifacts/src/libxisf/build"/libXISF.so* "$HOME/pins/"
[ ! -f /usr/bin/indiserver ] && [ ! -f /usr/bin/indiserver.bin ] && sudo apt-get install -y indi-bin
[ -f /usr/bin/indiserver ] && [ ! -f /usr/bin/indiserver.bin ] && sudo mv -f /usr/bin/indiserver /usr/bin/indiserver.bin
printf '#!/bin/bash\nexport LD_PRELOAD=%s/pins/libXISF.so.0.2.13\nexec /usr/bin/indiserver.bin "$@"\n' "$HOME" | sudo tee /usr/bin/indiserver > /dev/null
sudo chmod +x /usr/bin/indiserver

sudo tee /usr/share/indi/indi_myfocuserpro2.xml > /dev/null << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<driversList><devGroup group="Focusers"><device label="MyFocuserPro2" mdpd="true"><driver name="MyFocuserPro2">indi_myfocuserpro2_focus</driver><version>1.0</version></device></devGroup></driversList>
XML

mkdir -p "$HOME/test-fits" "$HOME/.indi"
cp -rf "$SCRIPT_DIR/test-fits/"* "$HOME/test-fits/" 2>/dev/null || true
[ -x "$SCRIPT_DIR/prepare-test-fits.sh" ] && "$SCRIPT_DIR/prepare-test-fits.sh" || true
[ -f "$SCRIPT_DIR/configs/PHDGuidingV2.conf" ] && cp -f "$SCRIPT_DIR/configs/PHDGuidingV2.conf" "$HOME/.PHDGuidingV2"
cp -f "$SCRIPT_DIR/configs/"*.xml "$HOME/.indi/" 2>/dev/null || true

echo "=== 9. Systemd-Dienste (PHD2 Headless + randloses VNC & PINS) ==="
sudo systemctl disable --now sysupdate-api.service 2>/dev/null || true
sudo apt-mark hold pins indi-bin

sudo tee /etc/systemd/system/phd2.service > /dev/null << SVC
[Unit]
Description=PHD2 Guiding Daemon (Headless)
Before=pins.service
After=network.target

[Service]
Type=simple
User=$USER
ExecStartPre=-/bin/rm -f /tmp/*phd2* /tmp/*PHD2* $HOME/phd2.* $HOME/.PHDGuidingV2-instance* /tmp/xvfb-phd2.auth
ExecStart=/usr/bin/xvfb-run -n 99 -f /tmp/xvfb-phd2.auth -s "-screen 0 1280x800x24" /bin/sh -c 'matchbox-window-manager -use_titlebar no & exec /usr/bin/phd2'
Restart=always
RestartSec=3
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
SVC

sudo tee /etc/systemd/system/x11vnc-phd2.service > /dev/null << VNC
[Unit]
Description=x11vnc for PHD2 Xvfb Display
After=phd2.service
Requires=phd2.service

[Service]
Type=simple
User=$USER
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 15); do [ -f /tmp/xvfb-phd2.auth ] && exit 0; sleep 1; done; exit 1'
ExecStart=/usr/bin/x11vnc -display :99 -auth /tmp/xvfb-phd2.auth -rfbport 5901 -passwd 1234 -noxdamage -shared -forever
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
VNC

echo "$USER ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /sbin/poweroff, /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot" | sudo tee /etc/sudoers.d/pins-power > /dev/null
sudo chmod 0440 /etc/sudoers.d/pins-power
sudo systemctl daemon-reload
sudo systemctl enable --now phd2.service x11vnc-phd2.service pins.service

echo "=== 10. Touch 'N' Stars 4:3 PHD2-Patch, Bildpfad & Offline-Kataloge ==="
python3 -c '
import glob, os
old = "S=i(()=>u.value?{top:`80px`,height:`calc(100% - 80px)`}:{top:`0`,height:`100%`})"
new = "S=i(()=>u.value?{top:`80px`,height:`calc(100% - 80px - var(--above-statusbar, 0px) - var(--status-panel-height, 260px) - 1rem)`}:{top:`0`,height:`calc(100% - var(--status-panel-height, 240px) - 1rem)`})"
for p in glob.glob(os.path.expanduser("~/.local/share/NINA/Plugins/*/Touch-N-Stars/app/assets/GuidingPage-*.js")):
    s = open(p).read()
    if old in s:
        open(p + ".bak", "w").write(s)
        open(p, "w").write(s.replace(old, new, 1))
'

mkdir -p "$HOME/astro-images"
for i in $(seq 1 15); do
  ls "$HOME/.local/share/NINA/Profiles"/*.profile >/dev/null 2>&1 && break
  sleep 1
done
for prof in "$HOME/.local/share/NINA/Profiles"/*.profile; do
  [ -f "$prof" ] && sed -i "s|<ImageFilePath>.*</ImageFilePath>|<ImageFilePath>$HOME/astro-images</ImageFilePath>|g" "$prof"
done

mkdir -p "$HOME/.local/share/NINA/FramingAssistantCache"
if [ "$(du -sm "$HOME/.local/share/NINA/FramingAssistantCache" | cut -f1)" -lt 500 ]; then
  PROTO="https:"
  DL_HOST="${PROTO}//nighttime-imaging.eu"
  DL_PATH="/download/"
  SKY_URL=$(curl -fsSL "${DL_HOST}${DL_PATH}" | grep -oiE 'https://[^"]+Northern[^"]+\.zip' | grep -vi 'starless' | head -n 1)
  curl -fL --progress-bar "$SKY_URL" -o /tmp/nina-northern-sky.zip
  unzip -oq /tmp/nina-northern-sky.zip -d "$HOME/.local/share/NINA/FramingAssistantCache/"
  mv -f "$HOME/.local/share/NINA/FramingAssistantCache"/FramingAssistantCache_*/* "$HOME/.local/share/NINA/FramingAssistantCache/" 2>/dev/null || true
  rmdir "$HOME/.local/share/NINA/FramingAssistantCache"/FramingAssistantCache_* 2>/dev/null || true
  rm -f /tmp/nina-northern-sky.zip
fi

if [ ! -f /opt/astap/astap ] || [ -z "$(ls /opt/astap/*.290 2>/dev/null)" ]; then
  PROTO="https:"
  ASTAP_HOST="${PROTO}//sourceforge.net"
  ASTAP_PATH="/projects/astap-program/files"
  curl -fL --progress-bar "${ASTAP_HOST}${ASTAP_PATH}/linux_installer/astap_amd64.deb/download" -o /tmp/astap_amd64.deb
  curl -fL --progress-bar "${ASTAP_HOST}${ASTAP_PATH}/star_databases/d50_star_database.deb/download" -o /tmp/d50_star_database.deb
  sudo dpkg -i /tmp/astap_amd64.deb /tmp/d50_star_database.deb || sudo apt-get install -f -y
  rm -f /tmp/astap_amd64.deb /tmp/d50_star_database.deb
  sudo ln -sf /opt/astap/astap_cli /usr/local/bin/astap_cli
fi

echo "=== 11. Samba-Freigabe ([astro]) fuer macOS Finder einrichten ==="
if ! grep -q "^\[astro\]" /etc/samba/smb.conf 2>/dev/null; then
  cat << SMB | sudo tee -a /etc/samba/smb.conf > /dev/null

[astro]
   path = $HOME
   browseable = yes
   read only = no
   valid users = $USER
   create mask = 0644
   directory mask = 0755
SMB
fi
sudo systemctl enable --now smbd
echo "Bitte jetzt dein gewuenschtes Samba-Passwort fuer $USER vergeben:"
sudo smbpasswd -a "$USER" && sudo smbpasswd -e "$USER"
sudo systemctl restart smbd

echo "=== 12. 2.4 GHz Dauer-Hotspot ($HOTSPOT_SSID) einrichten ==="
WIFI_DEV=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi" {print $1; exit}')
if [ -n "$WIFI_DEV" ]; then
  for conn in $(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless" && $1!="Hotspot" {print $1}'); do
    sudo nmcli connection delete "$conn" || true
  done
  if ! nmcli connection show Hotspot >/dev/null 2>&1; then
    sudo nmcli dev wifi hotspot ifname "$WIFI_DEV" con-name Hotspot ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASS"
  fi
  sudo nmcli connection modify Hotspot 802-11-wireless.ssid "$HOTSPOT_SSID"
  sudo nmcli connection modify Hotspot wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASS"
  sudo nmcli connection modify Hotspot 802-11-wireless.band bg
  sudo nmcli connection modify Hotspot 802-11-wireless.channel 6
  sudo nmcli connection modify Hotspot connection.autoconnect yes
  sudo nmcli connection modify Hotspot connection.autoconnect-priority 100
  sudo nmcli connection modify Hotspot 802-11-wireless.powersave 2
fi

echo "=== Setup abgeschlossen! Bitte einmal 'sudo reboot' ausfuehren. ==="
