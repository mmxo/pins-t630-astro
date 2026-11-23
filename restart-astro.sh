#!/bin/bash
set -e

echo "=== 1. Astro-Dienste sauber herunterfahren ==="
sudo systemctl stop pins.service phd2.service x11vnc-phd2.service 2>/dev/null || true
pkill -TERM -f "indiserver|indi_" 2>/dev/null || true
sleep 2

echo "=== 2. Astro-Dienste wie beim Boot neu starten ==="
sudo systemctl start x11vnc-phd2.service
sudo systemctl start phd2.service
sleep 2
sudo systemctl start pins.service

echo "=== 3. CCD Simulator FITS-Replay aktivieren (wartet auf Connect) ==="
(
  for i in $(seq 1 60); do
    if [ "$(indi_getprop -1 "CCD Simulator.CONNECTION.CONNECT" 2>/dev/null)" = "On" ]; then
      sleep 2
      indi_setprop "CCD Simulator.CCD_DIRECTORY_TOGGLE.INDI_ENABLED=On" >/dev/null 2>&1
      break
    fi
    sleep 1
  done
) &

echo "=== Status ==="
systemctl is-active x11vnc-phd2.service phd2.service pins.service
echo "Fertig! Touch 'N' Stars ist unter http://$(hostname -I | awk '{print $1}'):5000 erreichbar."
