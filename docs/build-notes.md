# Build and integration notes

The things that are easy to forget, from the component and enclosure reviews.
Complements `power-distribution.md`, `enclosure-sintering.md` and the log.

## borg-pi5 — power

- Feed borg-pi5 with **5.1-5.15 V** (PSU trimmer), otherwise undervoltage warnings.
- If you feed 5 V over the **GPIO pins instead of USB-C PD**, the Pi does not detect
  a PD supply and **throttles the USB ports to ~600 mA total**. For the RTL-SDR +
  mic on USB, set in `/boot/firmware/config.txt`:
  ```
  usb_max_current_enable=1
  ```
- **Active Cooler is mandatory** (Frigate / CPU inference, summer heat).

## RTL-SDR on the borg-pi5 USB

- The SDR plugs into a Pi USB port and sticks out ~60 mm → the Pi keep-out in the
  enclosure is much larger. In the CAD it points towards +X (to the end wall),
  clear between the Pi edge (x≈124) and the power/status area.
- **ADS-B is not used** (user decision) → no sky antenna needed.

## Flashing the ESP32

- Flash it **before installing** (`esphome run`), then OTA. The DevKit USB is hard
  to reach once installed; the DevKit is socketed, so pull it if you must re-flash.

## WiFi antennas

- The ESP32-DevKit and the WLED controller have PCB antennas. **Do not place them
  behind metal** (the LED panel's aluminium back!). PA12/plastic is RF-transparent;
  point the antenna side towards a plastic wall, not the panel aluminium.

## WLED controller (Athom High Power)

- **Athom publishes no mechanical dimensions** (product page/reseller/forum checked),
  and the High-Power board has no documented mounting holes. So the CAD has a
  **cradle** (pocket with a cable opening) on the top wall, board held by a **zip
  tie**. Pocket size `WLED_BOARD_W/L` is an estimate (66×44 mm) → measure the real
  board and adjust.

## BME280

- Sits at the **bottom opening** (hole + grid in the CAD), so it reads outside air,
  not the warmed interior. Do not seal it in airtight.

## Ventilation / insect protection

- Intake: 2 mm slits in the rear wall, in the clear middle zone (no longer behind
  the boards). Exhaust: high slits on the end walls (heat rises, the ceiling side is
  closed). **2 mm keeps most insects out**; for mosquitoes glue a piece of fine mesh
  on the inside.

## SLS printing (PA12)

- See `enclosure-sintering.md` for the full manufacturing notes. In short: no
  supports, clearance 0.4-0.5 mm, avoid blind cavities (powder escape), black-dyed
  PA12 for the professional matte look.
- Print the **fit test** first (one corner with an insert boss, diffuser rebate,
  button hole) before the full two-half print.

## Hardware checklist (easy to forget)

- **Ceiling anchors** to match the ceiling material (**4× M5** through the ears, they
  carry everything). The ear hole is a through-hole with a counterbore, so the M5 head
  seats flat under the ear; any standard M5 head (≤11 mm) fits. A washer helps.
- **Heat-set inserts**: **M2.5** ×~8 (Pi + carrier 4 + WLED) plus **M3** ×3 for the
  seam clamps that bolt the two halves together. Also **2× 4 mm dowel pins** to align
  the halves.
- **Screws**: **M2.5** (Pi/carrier/WLED — the carrier PCB holes are M2.5/2.7 mm),
  **M3** ×3 (seam clamps), **M5** ×4 (ceiling).
- **Panel nuts** for the 12 mm buttons (check the 3 mm wall is within their clamp
  range).
- **Blade fuses** 10 A + 5 A + holders (see `power-distribution.md`).
- **XT60E-M** + mating plug, **Wago 221**, wire 2.5/1.5/0.5 mm².
- **CSI cable:** the 200 mm standard-mini is enough; no longer cable needed.
- **4 indicator LEDs** for the bottom LED tower: **LighthouseLEDs 5 mm, built-in resistor,
  5–15 V** (lights straight off 5 V), **four different cool colours**. Holes are 5.2 mm;
  glue from inside, wire all to +5 V/GND (always on). Do not buy generic 12 V pre-wired
  LEDs (too dim on 5 V). If they turn out too bright, dim them later with a series
  resistor or a small inline trimmer — no board or firmware change (decision: keep plain,
  always-on LEDs; PWM/PCA9685/addressable control was considered and skipped). Now **3
  LEDs** — the front (+Y) tower face holds the radar instead.
- **Radar LD2410B** (35×7 mm) mounts **inside the bottom LED tower**, facing **forward and
  down** through an **18 mm window** (`RADAR_WIN_D`) in the front tower face (the front LED
  was dropped for it). Cable runs up into the cavity to `J_RADAR` (now 4-pin, no OUT). It
  is no longer on the bottom face.
- **Microphone**: USB mic on the **Pi 5 only** — no acoustic port in the enclosure.
- **Audio out**: USB sound card (C-Media, e.g. DELOCK 61645) on a Pi 5 USB port →
  **PAM8403** mini class-D amp → **Visaton BF 45** speaker. The Pi 5 has no analogue out,
  so the USB card is required (plug-and-play via `snd_usb_audio`; make it the default in
  ALSA). The amp takes 5 V/GND off the **borg-pi5 5 V branch** (same reference as the
  sound card → no ground-loop hum), not a USB port. Plays a wav on events (detection /
  greeting). Nothing on the carrier board changes. See [`power-distribution.md`](power-distribution.md).
- **Camera lens hole** is **conical** (12 mm inside → 20 mm outside) so a wide-FOV Camera
  Module 3 is not vignetted by the wall.
- **SDR antenna**: a cheap **telescopic SMA whip** (extends to ~30 cm+, wideband when
  length-tuned) is the best budget "covers a lot" antenna. For one specific band (e.g.
  ADS-B 1090 MHz) a tuned antenna beats a whip.
  - **Connector chain:** RTL-SDR is **SMA female** → pigtail end **SMA male** to the SDR,
    **SMA female bulkhead** in the 6.5 mm end-wall hole (`ANT_POS`), pushed through from
    inside and locked outside with the nut + star washer; the antenna (SMA male) screws
    onto the bulkhead outside. Buy a pigtail with **RG316** cable (PTFE, more durable,
    slightly lower loss than RG174; ~5-8 €) — on a short pigtail the loss gain is tiny but
    the quality is worth it.
  - **Ground plane (for a whip/monopole):** the plastic wall gives the antenna no
    counterpoise, which hurts reception. Stick a piece of **copper tape** (better than
    aluminium foil: alu oxidises and won't contact reliably) on the inside wall and make
    sure the SMA nut/star washer bites onto it, so the foil is grounded to the connector
    shell. Size it ~quarter-wave: ~7 cm helps a lot at ADS-B/UHF; low VHF would need an
    impractically large sheet. A **dipole** antenna needs none of this (it is balanced).
