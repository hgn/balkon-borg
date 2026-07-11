# Entscheidungslog — Balkon-Borg

Chronologisches Log der Designentscheidungen. Neueste Einträge oben anhängen.
Zweck: festhalten, *warum* der Aufbau so ist, damit geklärte Fragen nicht erneut
aufgerollt werden. Nicht loggen, was ohnehin im Code/YAML steht.

**Eintragsformat:**

```
## YYYY-MM-DD — Kurztitel

**Kontext:** Worum ging es, was war die Ausgangslage.
**Entscheidung:** Was wurde festgelegt.
**Begründung:** Warum so, nicht anders.
**Verworfen:** Welche Alternative(n) und aus welchem Grund. (optional)
**Folgen:** Was das für den weiteren Aufbau bedeutet. (optional)
```

---

## 2026-07-11 — Fertigung: SLS/PA12 schwarz (statt FDM/ASA)

**Entscheidung:** Gehäuse wird per **SLS** in **PA12-Nylon, schwarz** gefertigt,
nicht mehr FDM/ASA. Grund: **professionellere Optik** (matte, gleichmäßige
Oberfläche ohne Schichtlinien/Naht/Stützen), keine Stützen, isotrop fest.

**Wetter-Klärung entkräftet die PA12-Nachteile:** Standort vollständig geschützt,
**keine Sonne** (UV egal), **kein Regen** (Wasser egal), nur Luftfeuchte (PA12 nimmt
~0,5-1 % auf → für ein Gehäuse irrelevant). Kein Coating nötig.

**Metall verworfen:** Faradaykäfig blockiert WLAN + Radar; Metalldruck bei 4,5 l
zudem tausende Euro/kilo-schwer. (Optional Front als Alu-Blende möglich, Körper
Kunststoff.)

**Design auf SLS angepasst:** `TOL` 0,2 → **0,4 mm** (SLS-Passung), Front-Insert-
Löcher durchgehend (Pulver-Auslass statt Sackloch), Split bleibt (Bauraum ~230 mm).
ASA-spezifische Vorgabe (V-0-Trennung) in CLAUDE.md auf „gedrucktes Gehäuse"
verallgemeinert; README §6 „ASA/PLA" ist damit überholt (Material jetzt PA12).

**Anbieter:** JLC3DP (PayPal, billigst, China-Versand) vs. Craftcloud/ZELTA3D/
PRINCORE (EU/DE, schneller Versand). Details + Ablauf in
[[docs/enclosure-sintering.md]] (`docs/enclosure-sintering.md`).

---

## 2026-07-11 — Review-Fixes: Gehäuse robust, Firmware, Verteilung

Nach Gehäuse- und Komponenten-Review autonom abgearbeitet:

**Gehäuse (`cad/balkon_borg.py`):**
- **Nahtverschraubung:** Klemmblöcke an X=0 (Clearance -X / M3-Insert +X) + Dowels.
  Bezel klemmt zusätzlich die Front-Naht. (Kritischer Fehler behoben: Hälften waren
  vorher nur ausgerichtet, nicht gespannt.)
- **Verschraubbare Front:** separater **Bezel** (`balkon-borg-bezel-left/right`) klemmt
  den Diffusor (kein Kleben), Front-Zugang zum Service. RECESS=0, M2.5-Inserts in der
  Frontborde.
- **Lüftung neu:** 2-mm-Schlitze in der freien Rückwand-Mittelzone (vorher hinter den
  Platinen), Abluft hoch an den Stirnwänden, insektenfein.
- **Dome-Löcher auf Insert-Maß** (M2.5=3,4 / M3=4,0) statt Selbstschneid.
- **Mounts + Trenner:** WLED (Oberwand), Radar/Mikro/BME (Boden), Divider-Rippen
  (Carrier | Mitte | Pi). Pi+SDR als größerer Sperrbereich nach +X.
- **BME280-Bodenöffnung** (Gitter) für Außenluft.
Alle Features numerisch verifiziert, Body 622 cm³, baut fehlerfrei.

**Firmware (`firmware/esphome/balkon-borg.yaml`):** Taster/Encoder/Radar/BME →
**Lichtsteuerung direkt über WLED-MQTT** (Toggle, Presets, Helligkeit, Präsenz-
Automatik, Status-LEDs). YAML strukturell validiert.

**System-Docs:** `docs/power-distribution.md` (5-V-Stern mit **10-A-LED-/5-A-Pi-
Abzweigsicherungen**), `docs/build-notes.md` (Pi5-PD/`usb_max_current_enable`,
ESP-Flash vor Einbau, WLAN-Antennenlage, Druckorientierung, Hardware-Checkliste).

**Nutzerentscheidungen:** ADS-B nicht genutzt (keine Himmelsantenne); Heat-Inserts
statt Selbstschneid; Front verschraubbar gewünscht.

**Platzhalter zu verifizieren:** WLED-/BME280-Modulmaße, Athom-Lochbild.

---

## 2026-07-10 — Breite Power-Bahnen + ESP-Reihenabstand bestätigt

**Power-Bahnen:** Netzklasse "Power" (in `place-board.py` via
`NET_SETTINGS.SetNetclassPatternAssignment`) setzt **+5V/+5V_IN/GND auf 1,0 mm**
(hält ~3 A, 1oz), Signale bleiben 0,2 mm. Grund (Hinweis eines Freundes): eine
0,25-mm-Bahn hält nur ~0,7 A und würde vor der 2-A-Sicherung F1 durchbrennen →
F1 wäre sinnlos. Landet korrekt in der DSN (`(class Power ... (width 1000))`),
Freerouting routet entsprechend. Verifiziert: +5V/GND = 1,0 mm, DRC 0/0.

**ESP-Reihenabstand bestätigt: 25,4 mm (1 Zoll)**, offizielles Espressif-Maß für
DevKitC-V4 (mehrere Quellen). War schon der Platzhalterwert → keine Änderung.
(Klone wie AZ-Delivery: 25,0 mm, Differenz beim Stecken innerhalb Toleranz.)
Damit ist `ESP_ROW=25.4` final, kein offener Punkt mehr.

---

## 2026-07-10 — Board finalisiert + mit Gehäuse gekoppelt, HagiOne drauf

**Board final:** 150×92 mm, kompakt neu platziert, **4 M3-Eckbohrungen** (Muster
136×78), **"HagiOne" als F.Silkscreen** oben mittig. Neu autoroutet, **DRC 0/0**,
Aisler-Zip neu erzeugt. Der ganze Zyklus lief **headless per Skript**
(`place-board.py` → DSN via `pcbnew.ExportSpecctraDSN` → Freerouting →
`apply-ses.py` via `pcbnew.ImportSpecctraSES`); KiCad-GUI nur zum Ansehen.

**Kopplung Gehäuse↔Board (gemeinsame Wahrheit):**
- `cad/balkon_borg.py`: `CARR_BOARD_W/H=150/92`, `CARR_HOLE_DX/DZ=136/78`,
  `CARR_CENTER=(-105,55)`. Dome an (-173,16),(-173,94),(-37,16),(-37,94) =
  exakt die 4 Board-Löcher. Diese Werte MÜSSEN mit `pcb/place-board.py` übereinstimmen.
- Board sitzt auf der Rückwand-Innenseite links (x -180..-30), 96 mm Abstand zum
  Pi (x 66..124). **Status-LEDs nach rechts verschoben** (x 150-210), damit sie
  nicht hinter der Platine liegen.

**Offen bleibt nur:** ESP-Header-Reihenabstand (ESP_ROW, in place-board.py UND als
Sockel-Footprint) am realen DevKit final messen; Kontur ist jetzt real (150×92),
nicht mehr Platzhalter.

---

## 2026-07-10 — Board platziert + autoroutet (Unrouted 0)

**Platzierung:** `pcb/place-board.py` (KiCad pcbnew-Modul, System-Python) ordnet die
33 Footprints ordentlich an (2 senkrechte ESP-Spalten mittig, Widerstände
flankierend, Stecker an den Rändern, Transistoren über den Tastern) und zieht eine
Platzhalter-Kontur 160×110. ESP-Header sind senkrechte 1x19-Spalten, Abstand
ESP_ROW=25,4 mm (Platzhalter, am echten DevKit prüfen).

**Routing:** Freerouting **1.9.0** (Java 21; 2.x braucht Java 25) headless über die
aus KiCad exportierte DSN, Batch (`-de/-do -mp 30 -oit 1`) auf DISPLAY=:0. Voll
geroutet in ~1 s, Optimierung ~50 % kürzer, `.ses` zurück in KiCad importiert →
**Unrouted 0**. Jar liegt im Scratchpad (nicht im Projekt).

**DRC sauber (0/0).** Fertigungsdaten erzeugt via `scripts/gen-outputs.py` →
`pcb/output/balkon-borg-carrier-aisler.zip` (Gerber + Bohrdatei). BOM leer (Bauteile
im Board, kein Schaltplan) — für die nackte Platine egal.

**Vor dem echten Bestellen final setzen:** ESP-Header-Reihenabstand am realen
DevKit messen (sonst steckt das Modul nicht), Außenkontur aus der Gehäuse-Carrier-
Bucht übernehmen (aktuell Platzhalter 160×110).

---

## 2026-07-10 — Board: Netzliste per SKiDL (statt GUI-Schaltplan)

**Kontext:** Beim Board-Schritt "KiCad" stand die Wahl: kompletter GUI-Schaltplan
in Eeschema (viel Klickerei, fehleranfällig bei den 38 ESP-Pins) vs. Netzliste per
Code. Nutzer wählte **Code**.

**Umsetzung:** `pcb/gen-netlist.py` (SKiDL, Tool KICAD9) beschreibt die komplette
Schaltung aus `docs/board-spec.md` inkl. **korrekter ESP32-DevKitC-V4-Pinzuordnung**
(offizieller Pinout, J2 links / J3 rechts). ESP als 2× `Conn_01x19` (gesteckt).
Erzeugt `balkon-borg-carrier.net` (KiCad-Netzliste), **0 Fehler**, 33 Bauteile mit
Footprints. End-to-end verifiziert (I2C_SDA→J3.6/GPIO21, RADAR_TX→J3.12/GPIO16,
BTN_LEDK→Q.Collector, +5V/+3V3/GND korrekt).

**Ablauf:** Netzliste in KiCad-PCB-Editor importieren (*Datei → Importieren →
Netzliste*), dann Layout (Kontur, Platzierung, Routing) im GUI. Nutzer macht nur
das Layout, die fehleranfällige Pin-Logik ist im Code. Schaltungsänderungen immer
in `gen-netlist.py`.

**Toolchain:** SKiDL 2.2.3 im venv; braucht `KICAD9_SYMBOL_DIR` /
`KICAD9_FOOTPRINT_DIR` auf `/usr/share/kicad/{symbols,footprints}`.

---

## 2026-07-10 — XT60E-M real, Feinschliff (Gussets, Panel-Nasen, Toleranzen)

**Strom-Stecker: Amass XT60E-M** (real erhältliches Panel-Mount, UL94-V0, 30/60 A,
gut verfügbar). Aus Datenblatt: Körper-Ausschnitt ~16×9 mm, 2× M3 (ø3,2) mit
~14 mm Abstand. Im Modell so eingetragen (an realem Teil feinjustieren/kleben).
**Verdrahtung bestätigt:** externes Netzteil → kurzes 5-V-Kabel → XT60 in der
Rückwand → innen ein dediziertes 5-V-Kabel an die Verteilung → Abnehmer.

**Feinschliff im Modell:**
- **Ohr-Gussets:** dreieckige Stützrippen unter allen 4 Nasen (gegen Abbrechen an
  der Wurzel beim Anschrauben).
- **Panel-Positionier-Nasen:** 4 Ecknasen am Rahmen-Rücken (Panel klebt dazwischen,
  verrutscht nicht).
- **Druck-Toleranz:** globaler Parameter TOL=0,2 mm auf die Passungen (Taster-
  Löcher 12,2, Diffusor-Nut, Passstift-Löcher).

---

## 2026-07-10 — Netzteil extern (final), Strom-Stecker, Sensor-Durchbrüche

**Netzteil: extern (endgültig).** Netzteil-Gehäuse hängt neben dem Hub, ~5-m-Schuko
vom Netzteil-Gehäuse zur Steckdose, nur **kurzer 5-V-Sprung** in den Hub. Löst das
Brandschutz-Thema (überholt den geparkten "Netzteil innen"-Punkt); README §6 gilt
wieder.

**Bestätigt und verworfen:** Die Variante "Netzteil an der Steckdose, 5 m 5-V-Kabel
zum Hub" wurde geprüft und **verworfen** (5 V über 5 m bei 10-15 A: >1 V Abfall,
Brownout; bräuchte Schweißkabel). Langes Kabel gehört auf die 230-V-Seite, nicht
auf die 5-V-Seite. Nutzer bestätigt.

**Strom-Anschluss: steckbarer Panel-Stecker (XT60) in der Rückwand.** Nutzer will
einstecken/abziehen können. XT60: ~60 A, verpolungssicher, robust, deckt die
~10-15 A (Panel + Pi). Cutout = Rechteckloch + 2 Schraublöcher (Maße an den realen
Panel-Halter anpassen). Ersetzt die frühere Kabelverschraubung.

**Sensor-Durchbrüche in der Unterseite (-Z, schaut nach unten auf die Terrasse):**
- **Kamera** (Modul 3): 12 mm Objektivloch (großzügig) + 4 Montagedome. Werte aus
  der offiziellen RPi-Maßzeichnung: Board 25×23,862, Löcher ø2,2, Muster ~14,4×12,5
  (asymmetrisch). Versatz Objektiv↔Löcher ist in der Zeichnung nicht sauber
  angegeben (RPi-Forum bestätigt), daher Objektivloch groß; am realen Teil prüfen
  oder Kamera kleben. CSI-Kabel: **Standard-Mini 200 mm** (Reichweite Kamera unten
  ↔ Pi Rückwand damit unkritisch, CSI-Sorge erledigt).
- **Radar LD2410B: 2-mm-Membran** (Wand innen auf 2 mm ausgedünnt, 26×26 mm).
- **Mikrofon**: 4 mm Loch.
Rechte Hälfte der Unterseite (x>0), klar neben Balkon-Borg-Slogan (links) und Fuge.

**Offen/Platzhalter:** Kamera-Lochmuster + Standoff-Höhe, XT60-Halter-Maße,
Radar-/Kamera-Halterung im Detail.

---

## 2026-07-10 — Offen: Netzteil innen? (Brandschutz, geparkt)

**Kontext:** Nutzer möchte das 230-V-Netzteil INS Gehäuse und ein 4-m-Schuko-
Kabel nach außen. Das widerspricht README §6 (230 V getrennt im V-0-/Metall-
gehäuse, Druckteil nur Kleinspannung).

**Status: offen, geparkt.** Empfehlung, falls innen: Netzteil in eigenem Blech-/
V-0-Abteil im Gehäuse (230 V nur dort, Schuko mit Zugentlastung, PE an Chassis,
nur 5 V raus, Lüftung). Alternativen: offen im ASA (abgeraten, Brandrisiko) oder
extern nahe der Steckdose (am sichersten). Entscheidung vom Nutzer vertagt; keine
andere Arbeit dadurch blockiert.

---

## 2026-07-10 — Front-Sitz, mehr Tiefe, Taster an die Seite

**Front-Sitz (Nutzerantworten):** Opal-Acryl-Diffusor **3 mm**, in Front-Nut,
**1 mm versenkt**; **8 mm** Luftspalt LED→Diffusor; **Nut + kleben** (kein Bezel).
Umgesetzt als 12 mm tiefer Frontrahmen (FRAME_D): Lichtfenster 434×84, davor
Diffusor-Rebate 444×94 (4 mm tief), Panel klebt an der Rahmen-Rückseite.

**Tiefe 75 → 95 mm:** Platz für alle Boards (WLED-Controller, RTL-SDR, Mikro,
Verkabelung). Rückwandfläche 454×104 war nie eng; der Front-Sitz frisst 12 mm,
darum tiefer. Nutzer: "tiefer ist egal".

**Taster von unten an die -X-Stirnseite** (senkrechte Reihe). Grund (Nutzer):
hinten/innen liegen die Platinen im Weg; die Stirnseite ist beim Split-Zusammenbau
offen zugänglich, also einfacher zu montieren und zu verdrahten. Folge: -X-Slogan
entfällt, HagiOne bleibt +X, Balkon Borg bleibt unten. (Seite -X, per Parameter
spiegelbar.)

---

## 2026-07-10 — Orientierung umgekehrt: Licht nach vorne (überholt Downlight)

**Kontext:** Nach kurzem Hin und Her endgültig festgelegt. Das im Tool gewählte
"Downlight" wurde per Folgenachrichten korrigiert. **Überholt den Downlight-
Eintrag vom selben Tag.**

**Endgültige Orientierung ("Front zur Terrasse"):**
- **Vorderseite (+Y, senkrecht, zur Terrasse): LED-Panel, Licht nach vorne.**
  Offene Fläche = Lichtfenster (Panel + Diffusor). **Bleibt textfrei.**
- **Unterseite (-Z, unten): Taster + Encoder** (von unten erreichbar).
- **Rückseite (-Y, zum Haus): Status-/Effekt-LEDs** (kleine Einzel-LEDs, kein
  Flächenlicht), plus Kabelverschraubung und Lüftung.
- **Oberseite (+Z): Decke**, Ohren protrudieren in ±Y, Schrauben vertikal.
- **Stirnseiten (±X): Slogans** (HagiOne / Balkon Borg).

**Achsen im Modell:** X = Breite (Panel-Spalten, 460), Z = Höhe (Panel 80 + Rand,
110), Y = Tiefe (Front-Rück, ~78). Front +Y offen. Pi5 + Carrier hängen an der
Rückwand-Innenseite. Split X=0 bleibt.

**Begründung:** Nutzerentscheidung. Licht soll die Sitzecke anstrahlen, nicht den
Tisch von oben; Bedienung von unten; Rückseite für Statusanzeige.

**Offen:** Große Slogans / weitere Flächen erst platzieren, wenn die neue
Geometrie sichtbar ist (Flächen haben sich verschoben). CSI-Kameranähe zur Front
im Blick behalten (Pi an der Rückwand ~75 mm entfernt).

---

## 2026-07-10 — Slogans auf den Stirnseiten

**Entscheidung:** Erhabene Schrift (1,2 mm), mitgedruckt:
- **+X-Stirnseite: "HagiOne"** (Codename des Nutzers).
- **-X-Stirnseite: "Balkon Borg"** (Projektname, = Repo-Verzeichnis).
- Schriftgröße 12 mm, waagerecht entlang Y, mittig auf der Wand. Jede Schrift
  liegt komplett in einer Split-Hälfte (kein Fugenkonflikt).
- **Lüftungsschlitze dafür auf die +Y-Längswand verlegt** (Stirnseiten frei für Text).

**Begründung:** Codename + Projektname als Typenschild; erhaben gewünscht. Stirn-
seiten waren ohnehin frei (Bedienung -Y, Kabel +Y).

**Offen:** Slogan auf der unteren gedruckten Platte (früher gewünscht) noch offen;
kommt beim Bau des Front-Lichtfenster-Rahmens dazu, falls weiterhin erwünscht.
Druckorientierung so wählen, dass die erhabene Schrift nicht als Überhang druckt.

---

## 2026-07-10 — Thermik-Vorgabe gestrichen, untere Platte wird gedruckt

**Kontext:** Die Projektbeschreibung machte die Alu-Platte zum Pflicht-Kühlkörper
der LED-Ebene ("Thermik im Sommer" als Top-Risiko). Nutzer streicht das bewusst:
LED läuft vor allem nachts, Standort ausreichend kühl, Lüftung über seitliche
Schlitze reicht.

**Entscheidung:**
- **Kein Alu-Kühlkörper mehr zwingend.** Überschreibt README §6 Thermik und §4
  ("Alu-Platte = Front + Kühlkörper"). Risiko "Thermik im Sommer" herabgestuft.
- **Untere Platte wird gedruckt** (ASA), mit **Diffusor-Lichtfenster** über den
  LEDs (Licht muss durch, ASA ist opak). Alu entfällt als tragende Frontplatte.
- **Zusätzliche Lüftungsschlitze in den Seitenwänden.**
- Damit ist die untere gedruckte Fläche auch Träger des erhabenen Slogans.

**Begründung:** Nutzerentscheidung, Nutzungsprofil (Nacht, kühl) trägt das Risiko.
Vereinfacht Aufbau (kein Alu-Zukauf/-Kontaktierung) und macht die Slogan-Idee auf
der Unterseite überhaupt erst druckbar.

**Folge:** LED-Panel + Diffusor sitzen im Lichtfenster der gedruckten Unterplatte.
Falls es doch zu warm wird, ist ein Alu-Retrofit hinter den LEDs jederzeit möglich.

---

## 2026-07-10 — Deckenmontage: Orientierung, Ohren, seitliche Bedienung

**Kontext:** Gehäuse wird an die Decke (Balkonunterseite) geschraubt, Panel zeigt
nach unten auf den Tisch. Oben ist die Deckenseite (unzugänglich).

**Entscheidungen (im CadQuery-Modell umgesetzt):**
- **Orientierung:** +Z = oben (Decke, geschlossene Oberwand), -Z = unten (offene
  Front, Alu-Platte/Panel/Diffusor leuchtet nach unten). X = Breite, Y = Tiefe.
- **Bedienung an der Seitenwand**, nicht oben und nicht in der leuchtenden Front:
  4 Taster (12 mm) + Encoder (7 mm) als Bohrungen in der **-Y-Wand** (zur Terrasse).
  Als Cluster in **einer Hälfte** (x = 35..195), damit kein Loch auf der X=0-Fuge
  liegt.
- **Deckenbefestigung über seitliche "Nasen":** 4 Laschen an den oberen Ecken,
  ragen in ±Y heraus, vertikales Durchgangsloch (~M5). Von unten durch die Nase
  nach oben in den Deckendübel schrauben. Laschenoberseite bündig mit Gehäuseober-
  seite (liegt an der Decke an).
- **Kabelverschraubung in der +Y-Seitenwand** (M12), nicht mehr im Boden.
- **Lüftung** als Schlitze in den Stirnwänden nahe der offenen (unteren) Front, so
  dass Wärme/Kondensat nach unten entweichen kann.
- **Pi5 + Carrier** hängen an Domen von der Oberwand; Split X=0, Passstift-Posten.

**Begründung:** Deckenlage kehrt oben/unten um; Bedienung und Kabel müssen an die
Seite, weil oben die Decke und unten das Lichtfeld ist. Nasen sind die einfachste
werkzeugfreundliche Deckenbefestigung (von unten schraubbar).

**Offen / parametrisch:** genaue Seiten-/Positionswahl (Taster -Y, Kabel +Y als
Default), Ohr-Maße und Deckenschraubengröße, Vent-Anordnung. Alles Parameter in
`cad/balkon_borg.py`. Kamera-/Radar-/Mikro-Durchbrüche und die Alu-Frontplatte als
eigenes Teil folgen.

---

## 2026-07-10 — Gehäuse aus Datenblattmaßen, nicht aus Vermessung

**Kontext:** Ich hatte das CadQuery-Gehäuse als "blockiert bis Teile vermessen"
eingestuft. Nutzer widerspricht zu Recht: die Maße der Standardteile stehen als
Zeichnungen online, und sein Ansatz ist bewusst großzügig ("im Zweifel etwas
größer, hängt halt rum").

**Entscheidung:** Gehäuse **jetzt** aus Datenblattmaßen + großzügigen Freigaben
parametrisch bauen, keine physische Vermessung nötig. Toleranz über Schlupf statt
über Präzision. Gehäuse-Arbeit ist damit nicht länger vom Bauteil-Eingang blockiert.

**Einzige echte räumliche Randbedingung:** kurzes Pi-5-CSI-Kabel → Kamera nah am
Pi. Lösung: Pi-Kammer hinter der Kameraöffnung oder längeres CSI-FPC (200-300 mm).
Von "größer bauen" nicht abgedeckt, separat zu lösen.

**Folge:** Reihenfolge angepasst: CadQuery-Gehäuse kann parallel/vor dem
Schaltplan starten. Board-Kontur wird als großzügig reservierte Bucht im Gehäuse
geführt, damit Board-Layout und Gehäuse entkoppelt bleiben.

---

## 2026-07-10 — Konkrete Bauteile: ESP32-Board, Taster, BME280-Pullups

**Kontext:** Nutzer delegiert die Bauteilwahl ("nimm was technisch geeignet und
erhältlich ist, was alle verwenden") und bittet um Guide zu den I²C-Pullups.

**Entscheidungen:**
- **ESP32: Espressif ESP32-DevKitC-V4 (WROOM-32E), 38-Pin, offiziell.** Grund:
  Qualität vor Preis, dokumentierte Mechanik (Reihenabstand belegt), breit
  erhältlich. Gesteckt auf 2× `PinSocket_1x19_P2.54mm`. **KiCad hat keinen
  DevKitC-Footprint** → Buchsenleisten-Footprints, Abstand aus Espressif-Zeichnung.
- **Taster: 12-mm-Metall, momentan, beleuchtet, 5-V-Ring-LED, 1NO (IP65)**, der
  gängige Standardtyp. Folge: 5-V-LED nicht direkt von 3,3-V-GPIO treibbar →
  **je Taster ein NPN (BC337-40/2N3904, TO-92)** als Low-Side-Schalter, GPIO über
  1 kΩ an die Basis. Taster-Stecker dadurch **4-polig** (SW, GND, 5V, LEDK). Die
  4× 330 Ω LED-Vorwiderstände entfallen (LED bringt ihren mit).
- **BME280-Pullups: 2× 4,7 kΩ als DNP** vorsehen. Fast alle Breakouts haben
  Pullups an Bord → Plätze bleiben leer, nur im Ausnahmefall bestücken.
  **Echtes Bosch-BME280** kaufen, BMP280-Fälschungen (ohne Feuchte) vermeiden.

**Begründung:** Alle drei Wahlen zielen auf "verbreitet, erhältlich, robust,
lötarm für einen Nicht-Hardware-Bauer". Der NPN-Treiber ist der Preis dafür, dass
gängige Leuchttaster 5-V-LEDs haben; Alternative (2-V-LED direkt am GPIO) wäre
bauteilabhängig fragil.

**Verworfen:** 30-Pin-Klon-Board (geringere QC, variabler Reihenabstand) zugunsten
offiziellem DevKitC-V4. Direkter GPIO-LED-Antrieb zugunsten NPN-Treiber.

**Offen:** Reihenabstand-Maß aus Espressif-Zeichnung eintragen; beim Bestellen
5-V-Taster-Variante sicherstellen; Board-Kontur weiter aus dem Gehäuse.

---

## 2026-07-10 — Tastergröße final: 12 mm

**Kontext:** Kurz auf 16 mm gewechselt (wegen großer Finger), vom Nutzer aber
umgehend auf **12 mm zurückgenommen**. Also bleibt es bei 12 mm.

**Entscheidung:** Beleuchtete Taster **12 mm**. Ergonomie wird stattdessen über
**großzügige Abstände** zwischen den Tastern aufgefangen (siehe Ergonomie-
Eintrag), nicht über größere Taster. Board-Schaltplan unverändert; Frontbohrung
12 mm, LED-Modell in Board-Spec Punkt 2.

---

## 2026-07-10 — Ergonomie: großzügig dimensionieren

**Kontext:** Nutzer hat große Finger und ist eigenen Angaben nach eher
ungeschickt. Board und Gehäuse dürfen "ein wenig größer" sein.

**Entscheidung:** Durchgängig großzügig auslegen. Bedienelemente, Steckverbinder
und Befestigungen weit auseinander; Board darf über das Minimalmaß hinaus
wachsen; Gehäuse geräumig. Keine gedrängten Layouts, keine fummelige Montage.

**Folge / offene Spannung:** Der Nutzer fand die Edelstahltaster "grob" und wählte
12 mm, große Finger sprechen aber eher für größere Taster **oder** klar
großzügige Abstände zwischen den 12-mm-Tastern. Beim Front-Layout darauf achten;
Taster-Größe ggf. nochmal gegen Bedienbarkeit prüfen (16 mm bleibt Option).
Auch als persistente User-Notiz gespeichert ([[user-prefers-roomy-builds]]).

---

## 2026-07-10 — EDA-Tool auf KiCad, beleuchtete Taster, Gehäuse-Anforderungen

**Kontext:** Nutzer hat die Tool-Wahl wieder offengelassen ("wenn andere Software
auf Debian installierbar, gern") und ist kein Hardware-/Firmware-Mensch. Zudem
neue Wünsche: feinere, möglichst selbstleuchtende Taster; diverses im Gehäuse
festschraubbar (Pi5, Kamera); Hinweis, dass das Pi-5-CSI-Kamerakabel sehr kurz ist.

**Entscheidungen:**
- **EDA-Tool: KiCad (GUI)** statt atopile. **Überholt die atopile-Entscheidung**
  vom selben Tag. Grund: per apt auf Debian, riesige THT-Bibliothek, beste
  Aisler-Anbindung (direkter Push/nativer Import), kein Bibliotheks-Bastelaufwand.
  Passt zum nicht-Hardware-Profil. Python bleibt nur für Fertigungsoutput/DRC/BOM,
  nicht für den Erstentwurf. Code-Ethos gilt weiter fürs CadQuery-Gehäuse, nicht
  fürs PCB.
- **Taster: beleuchtet, 12 mm Metall**, momentan, mit LED, schraubbar in die
  Front (Ersatz für die als "zu grob" empfundenen Edelstahltaster). Anzahl "ein
  paar", vorerst 4 (anpassbar).
  - **Board-Folge:** je Taster **3-poliger JST-XH** (SW-Signal, LED-Ansteuerung,
    gemeinsames GND) statt des früheren Sammelsteckers. LED **GPIO-gesteuert**
    über THT-Vorwiderstand → kann Zustand (Szene/Automatik) anzeigen. GPIO-Budget
    des DevKitC reicht (Zählung: UART 2 + Radar-OUT 1 + I²C 2 + Encoder 3 +
    4 Taster-Inputs + 4 LED-Outputs = 15 nutzbare GPIOs, passt).
  - **Front-Folge:** 12-mm-Bohrungen mit Panelmutter statt großer Edelstahl-Ausschnitte.

**Erfasste Gehäuse-Anforderungen (CadQuery-Track, später zu detaillieren):**
- **Pi5 in eigener Kammer** mit Schraubdomen (M2,5-Lochraster des Pi5), nah an
  der Kamera wegen kurzem CSI; getrennt von der kühlen Sensor-Frontplatte, mit
  Belüftung/Active-Cooler-Platz.
- **Kamera** als eigenes Modul (nicht aufs Trägerboard, eigenes CSI-Interface) in
  eigener Aufnahme hinter Frontdurchbruch. Kurzes CSI → Pi-Kammer direkt dahinter
  oder längeres CSI-FPC beschaffen (beim Gehäuse klären).
- **Trägerboard** bekommt eigene Schraublöcher zu Gehäusedomen (Lochbild aus dem
  Gehäuse, noch offen).
- Weiter gilt: 230-V-Netzteil in eigener V-0-Kammer, getrennt vom Druckteil.

**Verworfen:** atopile (jung, SMD-lastig, THT-Bibliotheksaufwand) und SKiDL
zugunsten KiCad-GUI. Unbeleuchtete und 16-mm-Taster zugunsten 12 mm beleuchtet.

**Folge:** `pcb/` wird ein KiCad-Projekt. Nächster Schritt: KiCad auf Debian
installieren, Projektgerüst, Schaltplan nach aktueller Spec.

---

## 2026-07-10 — Trägerplatine: Werkzeug, ESP32, Strom, Verbinder

**Kontext:** Zusätzlich zum Gehäuse soll eine **Trägerplatine (Carrier/Backplane)
nur für Sensorik und Signale** entstehen (ESP32-Domäne: LD2410B-Radar, BME280,
4 Taster, Encoder), gefertigt bei **Aisler** (EU). Kein System-Backplane; die
Lichtseite (Athom-WLED + SK6812-Panel, eigenes 5 V/Datenkabel) und die Pi-Peripherie
(RTL-SDR, USB-Mikro, Kamera) bleiben getrennt.

**Entscheidungen:**
- **Werkzeug: atopile** (Code-first EDA, eigene Sprache), Export nach KiCad →
  Aisler. Gewählt trotz Hinweis, dass die offizielle KiCad-Python-API zum
  Erstentwurf schlecht taugt (Eeschema hat keine stabile Python-API).
  **>> ÜBERHOLT am selben Tag, siehe Eintrag "EDA-Tool auf KiCad, beleuchtete
  Taster". Jetzt KiCad-GUI.**
- **ESP32: ESP32-DevKitC (38-Pin), steckbar** auf Buchsenleisten, lötfrei
  tauschbar und regulär bestellbar. Nutzer ist ausdrücklich kein Hardware-/
  Firmware-Bastler, daher steckbar statt gelötetes Bare-Modul.
- **Strom: 5 V rein, 3,3 V vom ESP-Modul.** Board bringt nur abgesichertes 5 V
  an den DevKit; dessen Onboard-Regler versorgt ESP und Sensoren mit 3,3 V. Kein
  eigener Regler an Bord (minimal, robust). Grenze im Auge behalten: reicht der
  DevKit-LDO für BME280 + Radar? LD2410B läuft auf 5 V, zieht 3,3 V nicht.
- **Verbinder: JST-XH (2,5 mm) durchgängig** für alle Abgänge, verpolungssicher,
  gecrimpt. Einheitliches Rastermaß, günstig, lötarm.

**Begründung:** atopile passt am ehesten zum "alles als Code"-Ethos des Projekts
(vgl. CadQuery-Gehäuse) und kapselt Bausteine als wiederverwendbare Module, was
den nicht-Hardware-Nutzer entlastet. Steckbarer DevKit + JST + 5-V-Durchleitung
sind der lötärmste, robusteste Pfad und decken die Rolle "billige, austauschbare
Frontplatte" ab.

**Verworfen / abgewägt:**
- *KiCad-Python-API (pcbnew/kipy)* und *SKiDL* als primärer Weg verworfen zugunsten
  atopile; **bleiben aber Rückfalloption**, falls atopile an Reife-/Bibliotheks-
  grenzen stößt. Der Wechsel kostet Layout, nicht die Designentscheidungen.
- *Eigener 3V3-Regler an Bord* und *reine Signaldurchleitung* verworfen.
- *Qwiic/STEMMA* und *Schraubklemmen* zugunsten einheitlichem JST-XH verworfen.

**Bestückung & Schutz (bestätigt):**
- **Selbst gelötet, nur THT.** Board ausschließlich mit durchsteckbaren Teilen:
  JST-XH-Header, Buchsenleisten für den DevKit, THT-Widerstände. Keine
  Aisler-Bestückung. Folge: atopile braucht ggf. **THT-Footprints/Custom-Parts**
  (die Bibliothek ist SMD-lastig), das trage ich.
- **Schutz minimal: nur Serienwiderstände** (THT) auf Radar-UART, Encoder- und
  Tasterleitungen. **Keine TVS/ESD-Dioden** (wären klobig in THT). I²C braucht
  Pull-ups: entweder liefert das BME280-Breakout sie, sonst 4,7 kΩ THT an Bord
  (noch zu klären, hängt vom gewählten Breakout ab).

**Offen / Annahmen (noch zu bestätigen):**
- **Board-Outline + Befestigungslöcher** gekoppelt an CadQuery-Gehäuse (offener
  Punkt README §8.3, Board noch nicht vermessen) → vorerst parametrische Platzhalter.
- **Lagen:** Aisler-Default 2 Lagen angenommen (für Sensor-Carrier ausreichend).
- **GPIO-Pinmap** ESP32↔Sensoren/Taster noch festzulegen (mit ESPHome-Seite zu
  koordinieren, README §8.1).

**Folgen:** Neues Domänen-Verzeichnis `pcb/` (atopile-Projekt) sobald erster
Inhalt entsteht. CLAUDE.md-Domänentabelle entsprechend ergänzen.

---

## 2026-07-10 — Projekt- und Gedächtnisstruktur angelegt

**Kontext:** Projektstart Balkon-Borg. Hardware-plus-Software-Bastelprojekt mit
mehreren Domänen (CAD, ESP32-Firmware, WLED, Backend-Dienste). Wunsch nach einer
persistenten Gedächtnisschicht, damit Entscheidungen über die Zeit erhalten
bleiben und bei jedem Claude-Start verfügbar sind.

**Entscheidung:** Drei Kern-Dateien im Projektwurzelverzeichnis:
- `CLAUDE.md` — Arbeitskontext, wird bei jedem Claude-Start automatisch geladen;
  verweist explizit auf dieses Log und auf `README.md`.
- `README.md` — vollständiger Projektüberblick (die gelieferte Beschreibung).
- `log/decisions.md` — dieses Entscheidungslog.

**Begründung:** `CLAUDE.md` ist der Standard-Mechanismus, den Claude Code beim
Start einliest. Indem sie auf `log/decisions.md` verweist, wird das Log
verlässlich Teil des Startkontexts. Trennung von Referenz (README, statisch) und
Verlauf (Log, wächst) hält beides sauber.

**Folgen:** Künftige nicht-triviale Entscheidungen werden hier als datierte
Einträge angehängt. Domänen-Artefakte kommen in die in `CLAUDE.md` festgelegten
Verzeichnisse (`cad/`, `firmware/esphome/`, `wled/`, `deploy/quadlets/`,
`docs/`), sobald der erste echte Inhalt entsteht.

---

## Vorentschiedenes aus der Projektbeschreibung (Ausgangslage, Stand 2026-07-10)

Bereits mit der Beschreibung festgelegt, hier als Ausgangslage dokumentiert
(nicht erneut zu diskutieren, sofern kein neuer Grund auftaucht):

- **Rechenknoten-Rollen:** Edge-Pi 5 macht Aufnahme und lokale Inferenz; ESP32
  ist die austauschbare Sensor-/Bedien-Frontplatte; NAS-Pi 5 ist Broker/Storage.
- **Objekterkennung auf Pi-5-CPU**, kein AI-HAT/Hailo (PCIe bleibt für späteres
  Retrofit oder NVMe frei). Konsequenz: FPS-/Stream-begrenzt.
- **Licht** über Athom-WLED-Controller + SK6812-RGBW-WW-Panel (344 px, 8×43),
  ABL auf ~8 A begrenzt. Kein separater DMX-Blinder (Stairville gestrichen).
- **LoRa nur Empfang** über den RTL-SDR, kein aktiver Meshtastic-Sendeknoten.
- **Gehäuse in ASA**, 3D-gedruckt, 2-teilig (Split bei X=0, 4-mm-Passstifte);
  PLA ausgeschlossen (Sommerhitze). Alu-Platte dient zugleich als Kühlkörper.
- **Strom:** ein gemeinsames 5-V-Netzteil (Mean Well LRS-150F-5), auf 5,15 V
  getrimmt, abgesicherte Abgänge; 230 V getrennt im eigenen V-0-Gehäuse.
- **Gestrichen:** E-Ink-Display, AS3935-Blitzsensor (siehe README §7).

Detail-Kontext zu jedem Punkt in `README.md`.
