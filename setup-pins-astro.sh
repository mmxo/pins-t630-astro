#!/bin/bash
set -e

HOTSPOT_SSID="pins-T630"
HOTSPOT_PASS="astro1234" # Hier bei Bedarf eigenes Passwort eintragen (min. 8 Zeichen)

echo "=== 1. Pakete, INDI, PHD2, VNC & Build-Tools ==="
sudo apt update
sudo apt install -y git curl wget unzip build-essential gcc python3 cmake ninja-build \
  libtesseract-dev libleptonica-dev indi-bin indi-svbony indi-asi indi-lx200-onstep \
  indi-myfocuserpro2 phd2 xvfb x11vnc netcat-openbsd libcfitsio-dev libnova-dev libusb-1.0-0-dev

echo "=== 2. Rechte & USB-Autosuspend ==="
sudo usermod -aG dialout "$USER"
grep -q "usbcore.autosuspend=-1" /etc/default/grub || {
  sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="usbcore.autosuspend=-1 /' /etc/default/grub
  sudo update-grub
}

echo "=== 3. Feste udev-Regeln fuer HP t630 (/dev/focusser & /dev/mount) ==="
sudo rm -f /etc/udev/rules.d/99-astro-devices.rules
sudo tee /etc/udev/rules.d/99-astro-hardware.rules > /dev/null << 'UDEV'
SUBSYSTEM=="tty", KERNELS=="2-2.1", SYMLINK+="focusser", MODE="0666"
SUBSYSTEM=="tty", KERNELS=="2-3.4", SYMLINK+="mount", MODE="0666"
UDEV
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=tty

echo "=== 4. PINS, INDI-FIFO-Patch, OpenCvSharpExtern & CCD-Simulator-FITS-Replay ==="
cd "$HOME/pins-src"
python3 -c '
p="NINA.INDI/INDIClient.cs"
s=open(p).read()
o="if (!WriteFifoCommand($\"start {driverName}\", TimeSpan.FromSeconds(5))) {"
n="var execPath = driverName.StartsWith(\"/\") ? driverName : $\"/usr/bin/{driverName}\";\n                if (!WriteFifoCommand($\"start {execPath}\", TimeSpan.FromSeconds(5))) {"
if o in s and n not in s: open(p,"w").write(s.replace(o,n,1))
'
dotnet publish NINA/NINA.csproj -c Release -r linux-x64 --self-contained false -o "$HOME/pins"
dotnet build NINA.INDI/NINA.INDI.csproj -c Release -o "$HOME/pins/"
find "$HOME/.local/share/NINA/Plugins" -name "NINA.INDI.dll" -exec cp -f "$HOME/pins/NINA.INDI.dll" {} \;

if [ -d "$HOME/pins-src/artifacts/src/opencvsharp/src" ]; then
  cmake -S "$HOME/pins-src/artifacts/src/opencvsharp/src" -B /tmp/build-ocs -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build /tmp/build-ocs -j$(nproc)
  cp -f /tmp/build-ocs/OpenCvSharpExtern/libOpenCvSharpExtern.so "$HOME/pins/"
  rm -rf /tmp/build-ocs
fi

if [ -d "$HOME/pins-src/artifacts/src/indi/build" ]; then
  sudo ln -sf "$HOME/pins/libXISF.so.0.2.13" /usr/local/lib/libXISF.so
  cmake --build "$HOME/pins-src/artifacts/src/indi/build" --target indi_simulator_ccd -j$(nproc)
  sudo rm -f /usr/local/lib/libXISF.so
  sudo cp -f "$HOME/pins-src/artifacts/src/indi/build/drivers/ccd/indi_simulator_ccd" /usr/bin/indi_simulator_ccd
fi

echo "=== 5. libXISF-Trennung, indiserver-Wrapper & MyFocuserPro2-XML ==="
ls /usr/local/lib/libXISF* >/dev/null 2>&1 && sudo mv -f /usr/local/lib/libXISF* "$HOME/pins/" && sudo ldconfig
[ ! -f /usr/bin/indiserver.bin ] && sudo mv -f /usr/bin/indiserver /usr/bin/indiserver.bin
printf '#!/bin/bash\nexport LD_PRELOAD=/home/hase/pins/libXISF.so.0.2.13\nexec /usr/bin/indiserver.bin "$@"\n' | sudo tee /usr/bin/indiserver > /dev/null
sudo chmod +x /usr/bin/indiserver

sudo tee /usr/share/indi/indi_myfocuserpro2.xml > /dev/null << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<driversList><devGroup group="Focusers"><device label="MyFocuserPro2" mdpd="true"><driver name="MyFocuserPro2">indi_myfocuserpro2_focus</driver><version>1.0</version></device></devGroup></driversList>
XML

echo "=== 6. Systemd-Dienste (PHD2 Headless + VNC & PINS), Paket-Hold & Power-Rechte ==="
sudo systemctl disable --now sysupdate-api.service 2>/dev/null || true
sudo apt-mark hold pins indi-bin

sudo tee /etc/systemd/system/phd2.service > /dev/null << 'SVC'
[Unit]
Description=PHD2 Guiding Daemon (Headless + VNC)
Before=pins.service
After=network.target

[Service]
Type=simple
User=hase
ExecStartPre=-/bin/rm -f /tmp/*phd2* /tmp/*PHD2* /home/hase/phd2.* /home/hase/.PHDGuidingV2-instance*
ExecStart=/usr/bin/xvfb-run -a -s "-screen 0 1024x768x24" /usr/bin/phd2
ExecStartPost=/bin/sh -c 'sleep 4 && echo "{\"method\": \"set_connected\", \"params\": [true], \"id\": 1}" | nc -w 2 127.0.0.1 4400 || true'
ExecStartPost=/bin/sh -c 'XAUTH=$(ps aux | grep -o "/tmp/xvfb-run[^ ]*/Xauthority" | head -n 1); /usr/bin/x11vnc -display :99 -auth "$XAUTH" -rfbport 5901 -passwd 1234 -forever -bg'
ExecStopPost=-/usr/bin/pkill -f "x11vnc.*5901"
Restart=always
RestartSec=3
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
SVC

echo "hase ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /sbin/poweroff, /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot" | sudo tee /etc/sudoers.d/pins-power > /dev/null
sudo chmod 0440 /etc/sudoers.d/pins-power
sudo systemctl daemon-reload
sudo systemctl enable phd2.service pins.service

echo "=== 7. 2.4 GHz Dauer-Hotspot ($HOTSPOT_SSID) einrichten ==="
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
