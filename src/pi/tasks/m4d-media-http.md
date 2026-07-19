# M4d — Media and HTTP: sky images, time-lapse, APK hosting

The pieces where the Pi produces a file and something else has to find it.

## Sky images (U14)

NOAA weather-satellite passes and ISS SSTV, decoded from the SDR (coordinate with M4b's
tuner arbitration; a satellite pass is a scheduled claim on the tuner) into images.

The storage model is deliberate and slightly counterintuitive, so do not "fix" it:

- The Pi keeps a **rolling FIFO of about 50 images in tmpfs**. Volatile on purpose, since
  the Pi is not on all the time and its SD card is not an archive.
- On each new image the arbiter publishes a **retained pointer** (id, timestamp,
  satellite, HTTP URL) and serves the file over HTTP.
- The **phone** fetches it and keeps the permanent collection. The archive lives on the
  device that is always with the user, not on the box under the balcony.

The app side of this is not built yet, so the pointer topic and the HTTP path are the
contract surface it will be built against. Get them right and they will not need to move.

## Time-lapse (U18)

One camera frame every 30 minutes, **persisted on the borg-pi** (a season is roughly 4300
frames and a few hundred megabytes, which is affordable). Compiled into a **WebM** video,
rebuilt incrementally rather than only once the season ends, with a retained pointer to
the current video.

Frames are plain captures, not Frigate detections; taking them must not disturb whatever
the camera is otherwise doing, and must not fail when SENTRY has the camera pinned.

## HTTP endpoints

Served by the arbiter's aiohttp alongside the status page from M1:

- the media paths for the two feeds above;
- the **talk-down upload** endpoint (implemented in M4c, routed here);
- **APK self-hosting**: the current Android build plus a small version document, so
  installing on a new phone is "browse to the box, download, install". The app's build
  identity is the commit count of the tree it was built from (`rNNN`), which is
  monotonic; the version document should carry the same value so a phone can tell newer
  from older without guessing.

Keep the HTTP surface small, boring and server-rendered. No build step, no framework, no
JavaScript beyond what a page genuinely needs. This has to still work in five years.

## Exit criteria

- A decoded image lands in tmpfs, the retained pointer appears, the URL serves the file.
- The FIFO evicts correctly and never fills the tmpfs.
- Time-lapse frames accumulate on a schedule and the video rebuilds incrementally.
- Frame capture works while SENTRY is armed.
- The APK and its version document are reachable from a phone browser.
- `make check` green.

## Cannot be verified without hardware

Satellite decoding needs actual passes and the antenna. The FIFO, the pointer publishing
and the HTTP serving are all testable with fake image files, and should be tested that way.
