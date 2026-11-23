#!/bin/bash
set -e

echo "=== 1. Astro-Dienste sauber herunterfahren ==="
sudo systemctl stop pins.service x11vnc-phd2.service phd2.service 2>/dev/null || true
pkill -TERM -f "indiserver|indi_" 2>/dev/null || true
sleep 2

echo "=== 2. Astro-Dienste in Boot-Reihenfolge neu starten ==="
sudo systemctl start phd2.service
sudo systemctl start x11vnc-phd2.service
sleep 2
sudo systemctl start pins.service

echo "=== Status ==="
systemctl is-active phd2.service x11vnc-phd2.service pins.service
echo "Fertig! Touch 'N' Stars ist unter http://$(hostname -I | awk '{print $1}'):5000 erreichbar."
