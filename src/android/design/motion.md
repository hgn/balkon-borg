# Motion-Spezifikation

Prinzip: Material 3 Expressive — jede Interaktion hat spürbare Physik (Overshoot/Spring), keine linearen oder harten Cuts. Zwei Kurven-Familien dominieren:

## 1. Spring-Overshoot — `cubic-bezier(.34,1.56,.64,1)`
Flutter-Äquivalent: `Curve balkonSpring = Cubic(0.34, 1.56, 0.64, 1.0)` (in `flutter_theme.dart`).

Einsatz (Dauer i. d. R. 250–350ms):
- Mode-Card Press: `scale(1) → scale(0.95)` beim Tap-Down, zurück beim Loslassen
- Stat-Kachel Press: `scale(1) → scale(0.94)`
- Card-Value Font-Size-Wechsel (17px ↔ 22px) beim Aktivieren/Deaktivieren eines Modus
- Theme-Toggle-Thumb Slide (links ↔ rechts)
- Sentry-Switch-Thumb Slide + Track-Farbwechsel
- PTT-Button Größenwechsel (92px ↔ 110px) beim Halten
- Nav-Item Background-Einblendung bei Aktivierung
- Chip-/Preset-Zeile Auswahl-Farbwechsel
- Sheet-Zeilen-Auswahl (Submode-Liste)

**Flutter-Umsetzung**: `AnimatedContainer`/`AnimatedScale`/`AnimatedDefaultTextStyle` mit `curve: balkonSpring, duration: balkonSpringDuration`. Für Press-Zustände: `GestureDetector.onTapDown/onTapUp` + `AnimatedScale`, oder `flutter_animate`'s `.scale()` mit derselben Kurve.

## 2. Sheet-Enter — `cubic-bezier(.22,1.1,.36,1)`, 380ms
Bottom-Sheets (Submode-Picker, Umgebungs-Chart) faden nicht nur ein, sie federn leicht über die Endposition (Overshoot `1.1` im zweiten Kontrollpunkt) beim Hochfahren aus `translateY(28px)`.

**Flutter**: `showModalBottomSheet` Standard-Transition ersetzen durch eigenes `AnimationController` + `Tween<Offset>` mit `Curve = Cubic(0.22, 1.1, 0.36, 1.0)`, `duration: 380ms`.

## 3. Screen-Enter — `cubic-bezier(.22,1,.36,1)`, 450ms
Beim Wechsel der Bottom-Nav-Tabs faden Screens von `opacity:0, translateY(10px) scale(.99)` auf `opacity:1, translateY(0) scale(1)`.

**Flutter**: `PageTransitionSwitcher` oder eigener `AnimatedSwitcher` mit kombiniertem Fade+Slide+Scale, gleiche Kurve/Dauer.

## 4. Backdrop-Fade — `ease`, 250ms
Sheet-Backdrops faden linear-ease ein/aus (kein Overshoot — Backdrops sollen ruhig wirken, nicht "springen").

## 5. Theme-Crossfade — `ease`, 400ms
Hintergrundfarbe des gesamten Screens crossfaded beim Light/Dark-Toggle. Idealerweise mit `AnimatedTheme`/`AnimatedContainer` auf Screen- und Card-Ebene, damit keine Farbe hart springt.

## Ambient-Loops (kontinuierlich, kein Trigger)
| Element | Keyframes | Dauer | Loop |
|---|---|---|---|
| Live-Status-Punkt (Vision aktiv) | opacity 1↔.35, scale 1↔1.4 | 1800ms ease-in-out | ∞ |
| LIVE-Kamera-Punkt | gleich, aber | 1400ms | ∞ |
| Equalizer-Balken (5×, gestaffelt 150ms) | scaleY .25↔1 | 1000ms ease-in-out | ∞, nur wenn COMMS/SIGINT aktiv |
| PTT-Aufnahme-Ring | box-shadow Ring 0→18px, verblassend | 1100ms ease-out | ∞, nur während Halten |

**Flutter**: `AnimationController(vsync: this, duration: ...)..repeat(reverse: true)` pro Loop-Element; Equalizer-Balken teilen einen Controller mit `Interval`-Staffelung pro Balken.

## Nicht verwenden
- Keine linearen Transitions auf interaktiven Controls (Cards, Switches, Chips, Nav) — immer Spring-Overshoot.
- Keine harten Sprünge bei Zustandswechseln (Farbe, Größe, Position) — immer über eine der oben genannten Kurven animieren, minimal 200ms.
- Kein aggressiver Vollflächen-Blink bei SENTRY-Alarm (dezente Vorgabe) — nur Border-Farbe + Switch ändern sich.
