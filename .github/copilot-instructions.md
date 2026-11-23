# Engineering & KI-Arbeitsregeln (pins-t630-astro)

## 1. Architektur-Prinzipien
- **Keine Wrapper-Skripte oder Background-Watchdogs**, wenn ein Defaultwert direkt im Quellcode (z. B. C++/C#) gesetzt und kompiliert werden kann.
- **Kein Snap (`snapd`)**: Ubuntu-Systeme bleiben komplett snap-frei (`nosnap.pref`).
- **Idempotenz**: Jedes Setup-Skript muss beliebig oft wiederholbar sein (`set -e`, `mkdir -p`, Guards vor `mv`/`append`), ohne bestehende Zustände zu zerstören.
- **Keine hardcodierten Benutzerpfade**: Immer `\(HOME` und `\)USER` statt `/home/hase` verwenden.
- **Hardware-Unabhängigkeit**: Netzwerkschnittstellen und USB-Geräte dynamisch oder über stabile `KERNELS`-udev-Regeln erkennen, nicht über flüchtige Interface-Namen.
- **CMake/Ninja Rebuilds**: Bei gezielten C++-Treiber-Patches vorher die jeweilige `.cpp.o`-Objektdatei löschen und benötigte Build-Symlinks (`libXISF.so*`) nur für die Dauer des Link-Schritts bereitstellen.

## 2. Umgang mit Änderungen, Output & Debugging
- **Gebündelte Diagnose**: Bei Fehlern immer EINEN zusammenhängenden Diagnosebefehl (Service-Status + Logs + Config + Prozesse) anfordern statt scheibchenweiser Einzelabfragen.
- **URLs ausschließlich in Code-Blöcken (` ``` `) ausgeben**, niemals als Link im normalen Fließtext (verhindert Link-Chip-Kürzungen durch die Web-Oberfläche).
- **Kompakte Code-Blöcke unter 100 Zeilen**: Längere Skripte in Teil-Blöcke unter 100 Zeilen aufteilen und Download-URLs in `HOST` + `PATH` trennen.
- **Regelmäßige Konsolidierung**: Nach 3–4 Hotfixes das gesamte Skript gegenlesen, tote Workarounds entfernen und Änderungen in `ARCHITECTURE_AND_FIXES.md` dokumentieren.
