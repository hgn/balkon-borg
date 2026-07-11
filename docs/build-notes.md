# Bau- und Integrationsnotizen

Sammlung der Punkte, die leicht vergessen werden, aus dem Komponenten- und
Gehäuse-Review. Ergänzt `power-distribution.md` und das Log.

## Raspberry Pi 5 – Stromversorgung

- Pi 5 mit **5,1-5,15 V** versorgen (Netzteil-Trimmer), sonst Unterspannungswarnungen.
- Speist man 5 V über die **GPIO-Pins statt USB-C-PD**, erkennt der Pi kein
  PD-Netzteil und **drosselt die USB-Ports auf ~600 mA gesamt**. Für RTL-SDR + Mikro
  am USB in `/boot/firmware/config.txt` setzen:
  ```
  usb_max_current_enable=1
  ```
- **Active Cooler ist Pflicht** (Frigate/CPU-Objekterkennung, Sommer).

## RTL-SDR am Pi-USB

- Der SDR steckt im Pi-USB und ragt ~60 mm heraus → Pi-Sperrbereich im Gehäuse ist
  deutlich größer. Im CAD ist der SDR nach +X (zur Stirnseite) eingeplant, dort
  frei zwischen Pi-Kante (x≈124) und Strom-/Status-Bereich.
- **ADS-B wird nicht genutzt** (Nutzerentscheidung) → keine Himmelsantenne nötig.

## ESP32 flashen

- **Vor dem Einbau** per USB flashen (`esphome run`), danach OTA. Im eingebauten
  Zustand ist der DevKit-USB schlecht erreichbar; der DevKit ist gesteckt, also
  notfalls aus dem Sockel ziehen.

## WLAN-Antennen

- ESP32-DevKit und WLED-Controller haben PCB-Antennen. **Nicht hinter Metall**
  legen (Alu-Rückseite des LED-Panels!). ASA ist HF-durchlässig; die Module mit
  ihrer Antennenseite Richtung Kunststoffwand, nicht Richtung Panel-Alu.

## WLED-Controller (Athom High Power)

- **Athom veröffentlicht keine Mechanik-Maße** (Produktseite/Reseller/Forum geprüft),
  und die High-Power-Platine hat keine dokumentierten Montagelöcher. Daher im CAD
  eine **Cradle** (Aufnahme-Tasche mit Kabelöffnung) an der Oberwand, Board per
  **Kabelbinder** fixiert. Taschenmaß `WLED_BOARD_W/L` ist ein Schätzwert
  (66×44 mm) → am realen Board messen und anpassen.

## BME280

- Sitzt an der **Bodenöffnung** (Loch + Gitter im CAD), misst so die Außenluft und
  nicht die aufgewärmte Innenluft. Nicht luftdicht einbauen.

## Lüftung / Insektenschutz

- Einlass: 2-mm-Schlitze in der Rückwand in der freien Mittelzone (nicht mehr
  hinter den Platinen). Auslass: hohe Schlitze an den Stirnseiten (Wärme steigt,
  die Deckenseite ist zu). **2 mm hält die meisten Insekten**; für Mücken zusätzlich
  ein Stück feines Gaze-Gitter innen aufkleben.

## 3D-Druck (ASA)

- Jede Gehäusehälfte auf die **Split-Fläche (X=0) legen** → Rückwand/Front stehen
  senkrecht, saubere Schichten. Ohren ragen dann seitlich → **Stützen unter den
  Ohren** nötig (die Gussets helfen). Erhabener Text auf Stirn-/Unterseite druckt so
  ordentlich (senkrechte bzw. schräge Flächen, kein Boden-Overhang).
- **ASA:** geschlossener/beheizter Drucker, Brim, gute Betthaftung. Große Hälften
  (~230 mm) neigen zu Verzug.
- Erst den **Passungstest** (eine Ecke mit Insert-Dom, Diffusor-Nut, Taster-Loch)
  drucken, bevor die großen Hälften gedruckt werden.
- Bezel separat flach drucken (Front nach oben, damit die Auflagefläche glatt wird).

## Hardware-Checkliste (leicht vergessen)

- **Deckendübel** passend zum Deckenmaterial (4× M5 durch die Ohren, tragen alles).
- **Heat-Inserts**: M2,5 (Pi, Carrier, WLED, Front-Bezel), M3 (Nahtklemmen).
- **Schrauben**: M2,5 (Pi/Carrier/WLED/Bezel), M3 (Naht), M5 (Decke).
- **Passstifte 4 mm** (Split-Ausrichtung).
- **Panelmuttern** der 12-mm-Taster (Wanddicke 3 mm im Klemmbereich prüfen).
- **Kfz-Flachsicherungen** 10 A + 5 A + Halter (siehe `power-distribution.md`).
- **XT60E-M** + Gegenstecker, **Wago 221**, Litze 2,5/1,5/0,5 mm².
- **Längeres CSI-Kabel** ist unnötig: 200-mm-Standard-Mini reicht.
