# M3 — Ring buffers and retained snapshots

The pattern that makes a periodically-connecting phone see history instead of a blank
screen. Build it once here; every later feed uses it.

## The problem it solves

The app is not permanently connected. It wakes up, connects, and wants to know what
happened. A live-only MQTT topic gives it nothing until the next event, which for a
radiosonde is twelve hours away. So every feed keeps a **ring in RAM** and mirrors it to a
**retained snapshot topic**, and a fresh client gets the last ~50 entries the moment it
subscribes.

This was settled as the general pattern for all SIGINT-type feeds and the environment
history; see the decision log.

## Build

### Ring-buffer framework

A small generic core: bounded ring, newest-first ordering, cheap append, snapshot
serialisation. Pure logic, fully unit-tested, no MQTT knowledge inside it.

Around it, a publisher that mirrors a ring to its retained topic. Two things matter:

- **Do not republish on every append.** A feed at 1 Hz retaining 50 entries would write a
  retained message every second forever. Coalesce: publish on a short debounce, or at a
  fixed cadence when dirty. Pick one, write down which and why.
- **Payload shape comes from the contract** (`../../shared/README.md`): the envelope with
  a version field, entries newest first. Do not invent a second shape.

### Environment history

`env/recent`: one sample per minute over a few hours, from the ESP's live topics. The ESP
publishes plain numbers (ESPHome), borgd aggregates them into the timestamped
snapshot the app charts. **An absent ESP is normal**: the feed stays empty, the capability
reports `missing`, nothing crashes.

### Event ring

The retained ring of the last ~20 events, categorised, newest first. This is what the
app's watch window diffs against to raise notifications, so it is the most
consequence-carrying topic in the system: a missing entry is a notification the user never
gets.

### Time gating

Timestamps are only written once the clock is synced (M0 exposes this). Before sync, a
sample is dropped rather than stamped wrong. A bird log full of 1970 is worse than a bird
log with a gap.

## Exit criteria

- A fake publisher feeding the ESP topics produces a correct `env/recent` snapshot, and a
  client subscribing afterwards receives the history immediately.
- Restarting borgd does not lose the retained snapshot for a connecting client.
- With no ESP present at all, borgd runs, the capability reports missing, and no
  other feed is affected.
- Ring behaviour (capacity, ordering, eviction, serialisation) is unit-tested.
- `make check` green.
