# Network

How the pieces talk, and which machine is on when.

## Roles

- **borg-pi5** — the edge Pi *inside the balcony enclosure*. Capture (camera/audio/SDR) and
  local inference (Frigate, readsb/tar1090, BirdNET-Go). **Powered on only when needed,
  not 24/7.** Reaches the LAN over WiFi via a repeater.
- **ESP32 + WLED** — the front panel (buttons, encoder, radar, environment) and the light
  controller. On WiFi; talk to the light and the broker over MQTT.
- **nas-Pi5** — a **separate, always-on** Raspberry Pi 5, **not** the enclosure Pi. Wired
  to the Fritz!Box. Runs the **MQTT broker (Mosquitto)**, dashboards and storage, and is the
  **permanent and remote (from outside) access point** — everything is reached through it.

## Physical path

```mermaid
graph LR
  borg["borg-pi5<br/>(edge · on-demand)"]
  esp["ESP32 + WLED<br/>(front panel)"]
  rep["WiFi repeater"]
  fb["FRITZ!Box"]
  nas["nas-Pi5<br/>(always on)<br/>MQTT broker · dashboards · storage"]
  wan(["Internet / remote"])

  borg -->|WiFi| rep
  esp -->|WiFi| rep
  rep -->|LAN cable| fb
  fb --- nas
  wan -.->|remote access| fb
```

So: **borg-pi5 → WiFi repeater → (cable) → Fritz!Box → nas-Pi5.**

## Communication

- The **broker lives on the nas-Pi5**. Because it is always on, the bus is always up even
  when the borg-pi5 is off.
- **borg-pi5** publishes events/metadata (detections, aircraft, birds) to the broker while
  it is running; it does not stream raw video/audio over the network.
- **ESP32** publishes sensor readings and controls the **WLED light over MQTT** (via the
  broker); button/encoder/radar actions become MQTT messages.
- **Remote access** (dashboards, status, control from outside the home) goes through the
  **nas-Pi5** via the Fritz!Box — the borg-pi5 is never exposed directly.

## Consequences

- Anything that must be reachable 24/7 (broker, dashboards, remote access) belongs on the
  **nas-Pi5**, not the borg-pi5.
- On-demand edge jobs (camera recognition, ADS-B, bird logging) run on the **borg-pi5** and
  are simply unavailable while it is powered down — the rest of the system keeps working.
