# M1 — Broker, arbiter skeleton, health, status page

The moment the system becomes observable. After this package the Android app can connect
to the real broker instead of its demo source, and a browser shows what the unit thinks of
itself.

## Build

### Mosquitto

A **system quadlet** (`quadlets/mosquitto.container`), port 1883, no TLS (settled, do not
revisit). Password file and ACL per the contract's broker table: `arbiter` writes
everything, `app` and `esp` are restricted. Credentials come from `../../shared/borg.yaml`,
which is checked in. Persistence on for retained messages, since the whole client model
depends on retained state surviving a broker restart.

### Configuration

`../../shared/borg.yaml`, validated with **pydantic** at startup. A typo fails the process
immediately with a message naming the field, rather than surfacing as strange behaviour
later. The schema starts small (broker, host, paths, capability enable flags) and grows
per service; do not design it all up front.

### Arbiter skeleton

One asyncio process (`aiomqtt` + `aiohttp`), running as a **user unit** with linger.
Modular inside, no microservices: the coupling between mode state, the audio mixer and the
resource table is real and belongs in one process.

- Publishes the retained **mode state** topics with sane defaults on startup, so a client
  connecting to a fresh system sees a complete picture rather than nothing.
- Accepts the **command topics** and echoes the resulting state. The contract's rule: the
  state topic *is* the acknowledgement, there is no separate ack and no optimistic client.
  The app is already built this way.
- Clean shutdown, and an **LWT** so a dead arbiter is visible rather than silently stale.

### Health registry

The heart of the stability principle. Every capability (SDR, mic, speaker, camera, ESP
data, each container service) has:

- a **probe**: device present, service running, data flowing;
- a **state**: `ok` / `degraded` / `missing` / `disabled`;
- a **reason** and a **since** timestamp, because "camera missing since 14:02" is
  actionable and "camera missing" is not.

Published as retained MQTT, per capability and as an aggregate. **Re-probed periodically**,
so plugging the SDR in later brings the capability up without a restart. A probe that
throws is a degraded capability, never a crashed arbiter.

### Status page

`http://borg-pi/` served by the arbiter's aiohttp on port 80: one glance at what is up,
what is missing, why, and since when. Plain server-rendered HTML, no build step, no
JavaScript framework. It has to work from a phone browser in a garden with one bar of
signal, five years from now.

Also serve `/health.json` with the same data, which is what the app uses when MQTT is not
available.

### Deploy loop

`make deploy` (rsync + restart units), `make logs`, `make status`, `make shell` working
against the real host.

## Contract compliance

`../../shared/README.md` is authoritative for every topic name, payload shape and port.
The Android app is already built against it and its tests encode those shapes. If
something there is wrong or missing, fix the contract file, the app and the Pi in one
commit with a decision-log entry. Do not silently diverge; a mismatch here surfaces as a
UI that shows nothing, with no error anywhere.

## Exit criteria

- `mosquitto_sub -h borg-pi -t 'balkon/#' -v` shows the retained mode and health topics
  immediately on connect.
- A command topic changes the state topic, and the app reflects it.
- `http://borg-pi/` renders the health picture; `/health.json` returns the same data.
- Killing the arbiter marks it dead through the LWT; restarting it restores the picture.
- Unplugging a capability degrades exactly that capability and nothing else.
- `make check` green: the mode state machine and the health registry are pure logic and
  unit-tested without a broker.
