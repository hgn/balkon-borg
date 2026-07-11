# 5-V-Verteilung mit Abzweigsicherungen

Ein Einspeisepunkt (XT60), dann eine abgesicherte Sternverteilung zu den Abnehmern.
Das 230-V-Netzteil bleibt **extern** in eigenem V-0-/Metallgehäuse; hierher kommt
nur 5 V DC.

## Schema

```
 externes Netzteil (Mean Well LRS-150-5, auf 5,15 V getrimmt)
        │ 5 V / GND, kurzes dickes Kabel (2,5 mm2)
        ▼
   [ XT60E-M ]  Panel-Stecker in der Rückwand
        │
        ▼
   5V+ Sammelpunkt (Wago 221, 5-Leiter)          GND Sammelpunkt (Wago 221)
        ├──[ Sicherung 10 A ]── LED-Panel / WLED-Controller   ── GND ─┤
        ├──[ Sicherung  5 A ]── Raspberry Pi 5                 ── GND ─┤
        └──[ Sicherung  2 A ]── Trägerplatine (J_PWR)          ── GND ─┤
                 (die 2 A macht die Platine selbst per F1/Polyfuse)
```

## Abzweige, Sicherung, Leiterquerschnitt

| Abzweig | Dauerstrom | Sicherung | Litze (5 V) |
|---|---|---|---|
| LED-Panel / WLED | ~8 A (WLED-ABL auf 8 A) | **10 A** Kfz-Flachsicherung (Mini) | 2,5 mm² |
| Raspberry Pi 5 | ~3-5 A | **5 A** Kfz-Flachsicherung (Mini) | 1,5 mm² |
| Trägerplatine | ~1 A | on-board **F1 (2 A Polyfuse)** | 0,5 mm² (JST-XH) |
| Summe | ~12-14 A | — | XT60 (60 A) trägt das locker |

Sicherungen als **Inline-Flachsicherungshalter** (Kfz-Mini) direkt am Sammelpunkt,
+5-V-seitig. GND gemeinsam, ungesichert.

## Wichtige Punkte

- **5 V kurz halten.** Netzteil-Gehäuse direkt neben dem Hub, langes Kabel nur auf
  der 230-V-Seite (siehe Log 2026-07-10). 5 V über lange Strecke = Spannungsabfall.
- **Pi 5 will 5,1-5,15 V** und zieht Einschaltspitzen; die 5-A-Sicherung ist träge
  genug wählen (Kfz-Flachsicherungen sind das von Natur aus). Siehe
  `build-notes.md` zum USB-Strom/PD-Thema.
- **LED-Einspeisung**: bei 344 RGBW-LEDs das 5 V möglichst nah am Panel einspeisen
  (kurze dicke Leitung), sonst Helligkeits-/Farbabfall am Strangende. WLED-ABL auf
  8 A hält Strom und Wärme im Rahmen.
- **Gemeinsames GND** für alle (WLED-Datenleitung braucht GND-Bezug zum Panel).

## Stückliste Verteilung

- 1× XT60E-M (Rückwand) + XT60-Buchse am Netzteilkabel
- 2× Wago 221 (5-Leiter) für 5V+ und GND
- 1× Inline-Flachsicherungshalter + 10-A-Mini-Sicherung (LED)
- 1× Inline-Flachsicherungshalter + 5-A-Mini-Sicherung (Pi)
- Litze 2,5 / 1,5 / 0,5 mm², Aderendhülsen
