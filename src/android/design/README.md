# Balkon-Borg — Design System Export

Quelle: `Balkon-Borg App.dc.html` (interaktiver HTML-Prototyp). Dieser Ordner überführt das dort erarbeitete visuelle System in implementierungsfertige Referenzen für die Flutter-App.

## Inhalt

- `tokens.json` — alle Design-Tokens (Farben Light/Dark, Typografie, Radien, Spacing, Schatten, Motion-Kurven) maschinenlesbar
- `flutter_theme.dart` — fertiges `ThemeData`/`ColorScheme` für Light & Dark, direkt einbindbar
- `components.md` — Spezifikation jeder Komponente (Zustände, Maße, Verhalten)
- `motion.md` — Animations-Kurven, Dauern, Einsatzregeln (Material 3 Expressive / Spring-Charakter)
- `../Balkon-Borg App.dc.html` — lebender visueller Referenz-Prototyp (im Browser öffnen)

## Grundprinzipien

1. **Zwei Themes, ein System**: Dark ist der native Ton (satte Violett/Neon-Akzente auf sehr dunklem Grund), Light ist die cleane Variante (viel Weißraum, gleiche Akzentfarben, reduzierter Kontrast). Beide teilen exakt dieselben Radien, Abstände und Bewegungs-Kurven — nur Farbwerte tauschen.
2. **Expressive Typografie**: Fließtext/Werte variieren in Größe und Gewicht je nach Zustand (aktiv/inaktiv, ausgewählt/nicht) — nie statisch. Space Grotesk (mono) für Zahlen/Zeit/Frequenzen, Manrope für alles andere.
3. **Physik statt harter Schnitte**: Jede Zustandsänderung (Card-Tap, Sheet-Open, Nav-Wechsel, Switch) läuft über eine Spring-artige `cubic-bezier(.34,1.56,.64,1)`-Kurve (Overshoot) oder abgestimmte Ease-Kurven für Screens/Backdrops. Keine linearen oder harten Schnitt-Transitions.
4. **Keine harten Kanten**: Durchgängig große Radien (16–32px auf Controls, 28–32px auf Cards/Sheets, "pill" auf Switches/Chips).
5. **SENTRY dezent hervorgehoben**: Alarm-/Scharf-Zustand zeigt sich nur über eine dünne rote Border + Switch-Farbe — kein aggressiver Vollflächen-Alarm.
