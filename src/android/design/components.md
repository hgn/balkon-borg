# Komponenten-Spezifikation

Alle Maße in logischen px (1:1 auf Flutter `dp` übertragbar). Farben referenzieren `tokens.json`. Jede Zustandsänderung nutzt die Motion-Werte aus `motion.md`.

## App-Shell
- Screen-Radius: 42px (nur relevant, wenn die App in einem gerahmten Kontext läuft, z. B. Splitscreen/Widget)
- Statusbar: eigenes Zeit-Label (Space Grotesk, 15px/600) + Signal/Batterie-Glyphen in `text`-Farbe
- Header: Eyebrow "BALKON" (Space Grotesk, 12px/600, 0.22em Tracking, `primary`-Farbe) über Wordmark "Borg" (Manrope, 22px/800, -0.02em)

## Theme-Toggle
- Pill-Track 60×32px, Radius 16px, Border 1px `border`, Background `surface2`
- Thumb 26×26px rund, Background `primary`, Icon-Glyph zentriert (●/○ als Platzhalter — im Produkt: Sonne/Mond-Icon)
- Position: Dark → rechts (left:30px), Light → links (left:2px)
- Transition: `left` 350ms Spring-Overshoot

## Mode-Card (Home, 2×2 Grid)
- Container: `surface2`, Border 1px `border`, Radius 28px, Padding 18px, min-height 132px, Gap 14px zwischen Badge und Text
- Badge: 40×40px, Radius 13px, Background = Akzentfarbe bei 22% Deckkraft, Glyph zentriert (Space Grotesk 17px/700, Vollfarbe)
- Label: Eyebrow-Stil (11px/700, 0.14em Tracking, `textDim`)
- Value: **variable Typografie** — aktiv (submode ≠ "Aus"): 22px/800 `text`; inaktiv: 17px/600 `textDim`. Übergang über `font-size` 300ms Spring.
- Press-Feedback: `scale(0.95)` beim Tap-Down, zurück via Spring-Overshoot
- Tap → öffnet Bottom-Sheet mit Submode-Liste für diesen Modus

## Umgebungs-Stats (Home, 3-Spalten-Grid)
- Kachel: `surface`, Border 1px `border`, Radius 20px, Padding 14×8px, zentriert
- Wert: Space Grotesk 19px/700 `text`; Label darunter 10px/600 `textDim`
- Tap → `scale(0.94)` Press-Feedback, öffnet Chart-Sheet (siehe unten)
- Drei Kacheln: Temperatur (°C), Luftfeuchtigkeit (%), Luftdruck (hPa) — **kein Lärmpegel**

## Bottom Sheet — Submode-Auswahl
- Backdrop: `rgba(5,2,12,.55)`, Fade-in 250ms ease
- Panel: `surface3`, Radius 32px oben, Padding 10/22/30, max-height 70% Screen, Slide-up 380ms Spring-Overshoot
- Grabber: 36×4px Pill, `border`-Farbe
- Titel: 18px/800; Close-Button 30×30px rund, `surface2`
- Reihen: Padding 14×16px, Radius 18px; ausgewählt = `primary`-Background + weißer Text/700; sonst transparent + `text`/600. Übergang 250ms Spring.

## Bottom Sheet — Umgebungs-Chart
- Gleicher Panel-Stil wie oben, kein Grabber-Offset unten (34px Padding)
- Header: Eyebrow "{Titel} · 24H VERLAUF" + Großwert (Space Grotesk 26px/700)
- Linechart: SVG-Linie (`primary`, 2.5px, rounded caps/joins) + gefüllte Fläche darunter (`primary` bei 15% Deckkraft), 24 Datenpunkte, viewBox 300×100
- Footer-Zeile: "vor 24h" / "min X · max Y" / "jetzt" (11px/600 `textDim`)
- **Flutter-Hinweis**: SVG-Pfad 1:1 durch `CustomPainter` + `Path` ersetzen, oder `fl_chart`/`syncfusion_flutter_charts` LineChart mit identischer Farbgebung

## SENTRY-Karte (Kamera-Screen)
- Container: `surface2`, Radius 24px, Padding 18×20px, Border 1px `border` normal
- **Scharf-Zustand (dezent)**: Border wird `rgba(255,84,112,.45)` 1px (kein Vollflächen-Alarm, keine Puls-Animation auf der Karte selbst)
- Switch: Pill-Track 56×30px, Thumb 24×24px weiß mit Schatten; aus = `surface`-Track, scharf = `#ff5470`-Track. Thumb-Slide 300ms Spring.

## Live-Kamera
- Bildbereich: 220px Höhe, Radius 26px, Border 1px `border`, Kamerabild/Platzhalter füllt Container
- LIVE-Indikator: 6px Punkt in `#ff5470` mit Puls-Animation (1.4s) + Label 11px/700

## Push-to-Talk Button
- Idle: 92×92px Kreis, Background `primary`
- Recording (Hold): wächst auf 110×110px, Background wechselt zu `accent`, zusätzlicher Ring-Pulse (`recPulse`, 1.1s)
- Label im Button: "HALTEN" / "AUFNAHME" (12px/700, 0.08em, weiß)
- Interaktion: Press-and-hold (PTT), kein Toggle — `onTapDown`/`onTapUp`/`onTapCancel` in Flutter

## Chips (Stimm-Effekt, COMMS-Band, SIGINT-Funktion)
- Padding 9–10×16px, Radius 14–16px, 13px/700
- Ausgewählt: Vollfarbe-Background (je nach Kontext `primary` oder `cyan`) + kontrastierender Text; sonst `surface2` + `textDim`, Border 1px `border`
- Übergang: 250ms Spring

## Radio "Jetzt aktiv"-Karte
- Container: `surface2`, Radius 24px, Padding 18px
- Equalizer: 5 Balken (4px breit, unterschiedliche Höhen 14–22px), `primary`-Farbe, animiert (`scaleY`, 1s, gestaffelt 150ms) nur wenn COMMS/SIGINT aktiv sind, sonst statisch

## Segmented Tab (COMMS/SIGINT)
- Track: `surface`, Radius 18px, Padding 5px, Border 1px `border`
- Aktives Segment: `surface3`-Background, Radius 14px, 12px/700 0.05em; inaktiv transparent + `textDim`

## Preset-Listen (FM/DAB+/Flugfunk)
- Zeile: `surface2`, Radius 14px, Padding 11×14px, flex space-between
- Name 14px/600 `text` (bzw. Vollfarbe bei Auswahl im DAB+-Fall), Frequenz Space Grotesk 13px `textDim` (falls vorhanden; DAB+ zeigt nur Sendernamen ohne Frequenz)
- DAB+ ausgewählt: Background `cyan`, Text dunkel (`#06232a`) — Spring-Transition

## Vogel-Log
- "Vogel des Tages"-Header: 30px/800 Titel, Zeit + Zähler darunter (13px/600 `textDim`)
- Log-Zeile: Initial-Badge 38×38px Radius 12px `surface2`-Background, Initial in `primary` (Space Grotesk 700); Spezies 15px/700, Detail 12px `textDim`, Zeit rechts Space Grotesk 12px `textDim`; Divider 1px `border` unten

## Bottom Navigation
- Container: `surface3`, Radius 28px, Padding 8px, Gap 6px, Schatten `0 12px 30px rgba(0,0,0,.18)`, 4 Items gleich breit
- Aktives Item: `primary`-Background, Radius 20px, Glyph 19px weiß, Label 10px/700 weiß
- Inaktives Item: transparent, Glyph 17px `textDim`, Label 10px/700 `textDim`
- Items: Home (⌂) · Kamera (◎) · Radio (≈) · Log (☰) — im Produkt echte Icons statt Glyphen
