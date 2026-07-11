# Light scenarios

Use cases for the WLED panel (SK6812 RGBW-WW, 8×43 2D matrix), driven by the radar
presence, the four buttons + encoder, schedules, and MQTT. These seed the WLED presets and
the ESP button mapping.

| # | Scenario | Trigger | Light | How |
|---|---|---|---|---|
| L1 | **Table light** | presence after dusk (auto mode on) | warm white, soft fade-in | radar → ESP → `wled/balkon "ON"`; off 2 min after absence |
| L2 | **Cozy** | button 2 | low warm amber, static | WLED **preset 1** (`{ps:1}`) |
| L3 | **Party** | button 3 | 2D colour effects / cycle / strobe | WLED **preset 2** (`{ps:2}`) on the matrix |
| L4 | **Golden hour** | schedule (sunset) | slow warm ramp to a sunset glow | WLED time preset / playlist, or MQTT from the nas-Pi5 |
| L5 | **Welcome** | presence after long absence | gentle fade up, settle warm | ESP presence + a "was away" timer → preset |
| L6 | **Bug-friendly amber** | late night / dedicated scene | amber / warm-white only (fewer insects) | WLED preset limited to the WW + red channels |
| L7 | **Wind-down** | evening schedule | dim + warmer over the night | WLED nightly playlist ramping brightness/CCT down |
| L8 | **Reading / task** | scene | bright neutral white | WLED preset (WW + balanced RGB, high brightness) |
| L9 | **Notification pulse** | MQTT event (doorbell, timer, weather alert) | short colour pulse, then restore | nas-Pi5 automation publishes to `wled/balkon/api` |
| L10 | **Weather glance** | on demand / MQTT forecast | brief colour wash (blue = rain, …) | nas-Pi5 maps forecast → colour, publishes to WLED |
| L11 | **Scrolling text** | on demand | message / animation on the 8×43 matrix | WLED 2D text/effect preset |
| L12 | **All off** | encoder push, or presence timeout | fade off | `wled/balkon "OFF"` |

## Notes

- **Buttons today** (firmware): B1 toggle, B2 cozy (preset 1), B3 party (preset 2), B4
  presence-automatic on/off; encoder = brightness, encoder push = off. More scenes = more
  WLED presets + more button/long-press actions.
- **ABL:** keep the WLED Automatic Brightness Limiter at ~8 A so party/white scenes stay
  within the LED branch fuse and heat budget.
- **RGBW-WW** means real warm white — prefer the WW channel for L1/L6/L7 rather than faking
  white from RGB (better colour, less power/heat).
- **Schedules & MQTT scenes** (L4/L7/L9/L10) live on the always-on **nas-Pi5** (WLED time
  presets/playlists, or a Home Assistant / Node-RED automation), so they work even when the
  borg-pi5 is off. See [network](network.md).
