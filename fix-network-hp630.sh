#!/usr/bin/env bash
set -e

echo "=== HP t630 Netzwerk einrichten (Ethernet DHCP + Hotspot pins-T630) ==="
sudo rm -f /etc/NetworkManager/conf.d/10-globally-managed-devices.conf
printf '[keyfile]\nunmanaged-devices=none\n' | sudo tee /etc/NetworkManager/conf.d/99-manage-all.conf > /dev/null
sudo systemctl enable --now NetworkManager
sudo systemctl restart NetworkManager
sleep 2

while sudo nmcli con delete wired-dhcp 2>/dev/null; do :; done
ETH_IF=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1; exit}')
if [ -n "$ETH_IF" ]; then
  sudo nmcli device set "$ETH_IF" managed yes
  sudo nmcli con add type ethernet ifname "$ETH_IF" con-name wired-dhcp autoconnect yes
  sudo nmcli con up wired-dhcp || true
fi

while sudo nmcli con delete pins-hotspot 2>/dev/null; do :; done
WIFI_IF=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
if [ -n "$WIFI_IF" ]; then
  sudo nmcli device set "$WIFI_IF" managed yes
  sudo nmcli con add type wifi ifname "$WIFI_IF" con-name pins-hotspot autoconnect yes ssid "pins-T630"
  sudo nmcli con modify pins-hotspot \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    802-11-wireless.channel 6 \
    802-11-wireless.powersave 2 \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "astro1234" \
    ipv4.method shared \
    ipv4.addresses 10.42.0.1/24 \
    connection.autoconnect yes
  sudo nmcli con up pins-hotspot || true
fi

nmcli device status
echo "=== Fertig! Hotspot 'pins-T630' (10.42.0.1) und Ethernet sind aktiv. ==="
