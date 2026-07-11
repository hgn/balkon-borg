# Gehäuse & Fertigung (SLS-Sintern)

Alles zum gedruckten Gehäuse und zur Herstellung per SLS. Modell:
`cad/balkon_borg.py`. Ergänzt `build-notes.md`.

## Fertigungsentscheidung: SLS / PA12, schwarz

**Verfahren: SLS** (Selective Laser Sintering, Laser verschmilzt Nylon-Pulver).
**Material: PA12-Nylon, schwarz eingefärbt.**

Warum SLS statt FDM/ASA oder Metall:

- **Optik:** SLS liefert eine gleichmäßige, fein-matte Oberfläche **ohne Schicht-
  linien, ohne Stütz-/Nahtstellen** → Serienprodukt-Look. FDM/ASA zeigt Schicht-
  linien (gerade an Gussets/Nasen/Rundungen) und wirkt „gedruckt".
- **Keine Stützen** nötig (Pulverbett stützt), komplexe Geometrie problemlos,
  isotrop fest.
- **Metall scheidet aus:** ein Metallgehäuse ist ein Faradaykäfig und blockiert
  WLAN (ESP, WLED) und das LD2410B-Radar (das *durch* die Kunststoffmembran sieht).
  Metalldruck wäre bei 4,5 l zudem tausende Euro und kilo-schwer. Falls Metall-
  Optik gewünscht: nur die Front als Alu-Blende, Körper bleibt Kunststoff.

### Wetter-Einordnung (entscheidend für die Materialwahl)

Standort: unter dem Balkon, **vollständig wettergeschützt**.
- **Keine direkte Sonne** → PA12-Schwäche „UV" ist praktisch **kein Thema**.
- **Kein Regen/Wasser.**
- **Nur Luftfeuchte:** PA12 nimmt ~0,5-1 % Feuchte auf, quillt minimal, wird eher
  zäher. Für ein Gehäuse **irrelevant**. Keine Beschichtung nötig.

→ Unter diesen Bedingungen ist SLS/PA12 die richtige Wahl. (ASA/FDM wäre nur bei
direkter Sonne/Bewitterung materialtechnisch überlegen.)

## SLS-Designregeln (im Modell umgesetzt)

| Regel | Anforderung | Status im Modell |
|---|---|---|
| Wandstärke | ≥ 1 mm (tragend 2,5-3) | 3 mm (`WALL`) ✓ |
| Passungsspalt | 0,4-0,6 mm | `TOL = 0,4` ✓ |
| Pulver-Auslass | Sacklöcher vermeiden, Auslass ≥ 3,5 mm | Front-Inserts durchgehend; Körper vorne offen ✓ |
| Min. Loch | ≥ 1,5 mm | kleinste 2 mm ✓ |
| Stützen | keine | entfällt (SLS) ✓ |
| Split-Grund | Bauraum (nicht Verzug) | Split X=0, Hälften ~230 mm |

Hinweise: Blinde Insert-Löcher (Dome) vor dem Insert **mit Druckluft ausblasen**.
Heat-Inserts (M2,5/M3) wie gehabt setzen.

## Druckteile (aus `cad/build/`)

| Teil | Größe (mm) | Anzahl |
|---|---|---|
| `balkon-borg-left` / `-right` | je ~230 × 122 × 110 | 2 (Gehäusehälften) |
| `balkon-borg-bezel-left` / `-right` | je ~230 × 110 × 4 | 2 (Front-Rahmen) |

Alle als **STEP** an den Dienst (STL geht auch). Material **PA12 SLS**, Farbe
**schwarz** (eingefärbt).

## Anbieter (schnell, günstig, einfach, PayPal, gute Bewertung)

| Anbieter | Preis | Versand | PayPal | Bewertung / Hinweis |
|---|---|---|---|---|
| **JLC3DP** | sehr günstig | China (~1-2 Wo., Express schneller) | **ja** | einfachster Upload, sehr beliebt, Top-Zufriedenheit |
| **Craftcloud** | günstig (Aggregator, findet EU-Drucker) | oft **EU → schnell** | am Checkout prüfen | Trustpilot 4,5 (82 % 5★), dead-easy |
| **Weerg** (IT) | mittel | EU, schnell, Sofortangebot | prüfen | in-house, gut für PA12 |
| **ZELTA3D / PRINCORE** (DE) | mittel-höher | DE, 2-4 Tage | prüfen | lokal, am schnellsten geliefert |

**Empfehlung:**
- Willst du **PayPal + billigst** und nimmst ~1-2 Wochen Lieferzeit in Kauf →
  **JLC3DP** (PayPal gesichert, einfachster Prozess, hohe Zufriedenheit).
- Willst du **schnell in DE** und PayPal ist am Checkout ok → **Craftcloud**
  (findet einen EU-Sinterer) oder direkt **ZELTA3D/PRINCORE** (lokal, 2-4 Tage).

Für „schnell versandt" ist ein EU/DE-Dienst (Craftcloud EU-Partner, ZELTA3D,
PRINCORE) klar im Vorteil; für „günstig + PayPal sicher" JLC3DP.

## Bestellablauf

1. `cad/build/*.step` der 4 Teile hochladen.
2. Verfahren **SLS**, Material **PA12 / Nylon**, Farbe **schwarz**.
3. Menge 1 Satz, Vorschau prüfen (Wandstärken-Warnungen? sollten keine kommen).
4. Erst den **Passungstest** (eine Ecke) mitbestellen oder separat, bevor der volle
   Satz geht (siehe `build-notes.md`).
5. Bezahlen (PayPal), liefern lassen.
