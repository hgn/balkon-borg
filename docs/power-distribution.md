# 5 V distribution with branch fuses

One feed-in point (XT60), then a fused star distribution to the loads. The 230 V
power supply stays **external** in its own enclosure (next section); only 5 V DC
comes in here.

## External PSU box (ceiling-mounted, water-protected)

The LRS-150F-5 is an open-frame supply and lives in its **own IP66 junction box on
the ceiling next to the hub**, XT60 side:

- **Enclosure:** Spelsberg **TK PC 2518-11-m** (254 × 180 × 111, IP66, polycarbonate,
  glow-wire tested — proper 230 V installation class), mounted via the outer lugs
  (outside the seal), like the hub's ears. The generous depth is deliberate.
- **Thermals (checked):** everyday load 10–30 W, party peak ~60–70 W → at ~90 %
  efficiency 1–7 W of waste heat in the box; the 2518 sheds that through its walls at
  ~10–15 K rise, so ~45 °C inside on a 30 °C evening. The LRS is specified to 50 °C
  at full load and runs at only ~55 % here. Mount the PSU on ~10 mm standoffs,
  vent slots free.
- **Water + breathing:** both cable glands point **down**, drip loops in both cables,
  and a **pressure-compensation membrane plug** (M12, Gore-style) instead of a
  hermetic seal — otherwise the day/night cycle pumps moisture in that never leaves.
- **230 V side:** H07RN-F 3G1.5 with a moulded Schuko plug, length measured to the
  terrace socket (~5 m per the log), through an **M20 gland** (strain relief built
  in). **PE to the LRS PE terminal** — mandatory even in a plastic box. Work on it
  only unplugged; the terrace socket is RCD-protected.
- **5 V side:** short and thick — box right next to the hub's XT60 wall, ~0.5 m of
  2 × 2.5 mm² through an **M16 gland** to the XT60 plug (~0.2 V drop at 15 A, which
  the 5.15 V trim absorbs). Ferrules on everything entering the LRS screw terminals.
- **Box parts:** enclosure ~30 €, M20 + M16 glands + locknuts, M12 vent plug,
  H07RN-F lead with plug — ~50 € all in.

## Diagram

```
 external PSU (Mean Well LRS-150F-5, trimmed to 5.15 V, in the IP66 ceiling box)
        │ 5 V / GND, short thick cable (2.5 mm2)
        ▼
   [ XT60E-M ]  panel connector in the rear wall
        │
        ▼
   5V+ junction (Wago 221, 5-way)                GND junction (Wago 221)
        ├──[ fuse 10 A ]── LED panel / WLED controller       ── GND ─┤
        ├──[ fuse  5 A ]── borg-pi5                           ── GND ─┤
        └──[ fuse  2 A ]── carrier board (J_PWR)              ── GND ─┤
                 (the 2 A is the board's own F1 / polyfuse)
```

## Branches, fuse, wire gauge

| Branch | Continuous current | Fuse | Wire (5 V) |
|---|---|---|---|
| LED panel / WLED | ~8 A (WLED ABL at 8 A) | **10 A** blade fuse (mini) | 2.5 mm² |
| borg-pi5 | ~3-5 A | **5 A** blade fuse (mini) | 1.5 mm² |
| carrier board | ~1 A | on-board **F1 (2 A polyfuse)** | 0.5 mm² (JST-XH) |
| total | ~12-14 A | — | XT60 (60 A) carries it easily |

Fuses as **inline blade-fuse holders** (automotive mini) at the junction, on the
+5 V side. GND common, unfused.

## Key points

- **Keep 5 V short.** PSU enclosure right next to the hub, the long run only on the
  230 V side (see log 2026-07-10). 5 V over a long run drops too much.
- **borg-pi5 wants 5.1-5.15 V** and draws inrush spikes; pick the 5 A fuse slow
  enough (automotive blade fuses are, by nature). See `build-notes.md` for the
  USB current / PD topic.
- **LED feed:** with 200 RGBW LEDs, inject 5 V as close to the panel as possible
  (short thick wire), else brightness/colour drops at the strip end. WLED ABL at
  8 A keeps current and heat in check.
- **Common GND** for everything (the WLED data line needs a GND reference to the
  panel).
- **Audio amp (PAM8403, ~0.3 A):** tap 5 V/GND from the **borg-pi5 branch**, not a
  separate run — same reference as the USB sound card feeding it, so no ground loop or
  hum on the speaker line. It sits well under the 5 A fuse; no extra fuse needed. Keep
  the analogue audio lead (sound card → amp) short. **Nothing on the carrier board
  changes** — the whole audio chain lives on the Pi side + this branch.

## Distribution parts list

- 1× XT60E-M (rear wall) + XT60 socket on the PSU cable. Low-solder tip: XT60 cable
  connectors have solder cups — buy the socket as a **pre-soldered pigtail** ("XT60
  female with lead", 12 AWG silicone, ~50 cm): that IS the whole PSU-to-XT60 cable —
  socket end to the hub, wire end through the M16 gland, ferrules on, into the LRS
  screw terminals. No soldering.
- 2× Wago 221 (5-way) for 5V+ and GND
- 1× inline blade-fuse holder + 10 A mini fuse (LED)
- 1× inline blade-fuse holder + 5 A mini fuse (borg-pi5)
- wire 2.5 / 1.5 / 0.5 mm², ferrules

## Audio output chain (Pi side, not the carrier board)

- USB sound adapter (C-Media, e.g. DELOCK 61645) on a Pi 5 **USB 2.0** port — plug-and-
  play via `snd_usb_audio`; make it the default with `snd-usb-audio index=0` in
  `/etc/modprobe.d/alsa-base.conf` (or an `~/.asoundrc`).
- Mini class-D amp (PAM8403, 2×3 W): 5 V/GND off the borg-pi5 branch, L/R + GND in from
  the sound card's headphone jack, output to the speaker.
- Speaker: Visaton BF 45 (4 Ω, 45 mm). Passive, no supply of its own.
