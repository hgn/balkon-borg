#version 460 core

#include <flutter/runtime_effect.glsl>

// One-shot CRT interference pass over the camera view when SENTRY reports a
// person (E11, implementation-plan.md D6). Overlay-only: this never samples
// the widget underneath (no `AnimatedSampler`, D6) — everything here is
// synthesized and additive/alpha-blended over whatever `CameraScreen`
// already painted. `uProgress` runs 0..1 across the ~400ms one-shot; the
// envelope below gives it a fast attack, a short sustain, and a fade-out so
// it reads as a single deliberate glitch, not a loop.
uniform vec2 uResolution;
uniform float uTime;
uniform float uProgress;

out vec4 fragColor;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
    vec2 fragCoord = FlutterFragCoord();
    vec2 uv = fragCoord / uResolution;

    // Attack (0..0.1), sustain (0.1..0.8), decay (0.8..1.0).
    float envelope = uProgress < 0.1
        ? uProgress / 0.1
        : (uProgress > 0.8 ? (1.0 - uProgress) / 0.2 : 1.0);
    envelope = clamp(envelope, 0.0, 1.0);

    vec3 rgb = vec3(0.0);
    float a = 0.0;

    // Scanlines: a fine dark grid, barely-there outside the sustain window.
    float scan = sin(uv.y * uResolution.y * 1.5) * 0.5 + 0.5;
    a = max(a, (1.0 - scan) * 0.16 * envelope);

    // Two horizontal tear bands drifting slowly across the frame.
    float band1 = fract(uTime * 1.7 + 0.10);
    float band2 = fract(uTime * 1.1 + 0.55);
    float tear = max(
            smoothstep(0.02, 0.0, abs(uv.y - band1)),
            smoothstep(0.02, 0.0, abs(uv.y - band2))
        ) * envelope;

    // Fake RGB fringe: red/blue streaks offset a few pixels in x — no child
    // sampling means no real chromatic aberration, so this substitutes a
    // striped color offset that reads the same way at a glance.
    float fringe = 0.012;
    float redMask = step(fract((uv.x - fringe) * 4.0), 0.5);
    float blueMask = step(fract((uv.x + fringe) * 4.0), 0.5);
    rgb += vec3(0.95, 0.12, 0.18) * tear * redMask * 0.6;
    rgb += vec3(0.12, 0.55, 0.98) * tear * blueMask * 0.6;
    a = max(a, tear * 0.55);

    // Short noise flicker, only in the opening burst.
    float flicker = clamp(1.0 - uProgress / 0.15, 0.0, 1.0) * envelope;
    float n = hash(floor(fragCoord * 0.4) + uTime * 60.0);
    rgb += vec3(n) * flicker * 0.4;
    a = max(a, n * flicker * 0.3);

    fragColor = vec4(rgb * a, a);
}
