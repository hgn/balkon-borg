#version 460 core

#include <flutter/runtime_effect.glsl>

// Condensation/droplet wash on the background above 85% humidity (E11,
// implementation-plan.md D6). Deliberately near-invisible: `uIntensity`
// (0..1, driven by the app's fade-in/out) caps the whole effect's opacity
// far below anything foreground. A tiled grid of cells each hash to at most
// one droplet (position, radius, highlight offset); cell rows drift slowly
// downward with `uTime`. No loops beyond the fixed 3x3 neighbor search
// (cheap, constant cost per pixel) and no dynamic branching on uniforms.
uniform vec2 uResolution;
uniform float uTime;
uniform float uIntensity;

out vec4 fragColor;

const float kCellSize = 46.0;
const float kDriftPerSecond = 3.2; // px/s downward — "very slowly".

vec2 hash2(vec2 p) {
    vec2 q = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(q) * 43758.5453123);
}

float droplet(vec2 pixel, vec2 cell) {
    vec2 rnd = hash2(cell);
    // Not every cell gets a droplet — sparse, so the wash reads as a few
    // scattered drops rather than a uniform texture.
    if (rnd.x > 0.55) return 0.0;

    vec2 center = (cell + rnd) * kCellSize;
    float radius = mix(2.5, 6.5, rnd.y);
    float d = length(pixel - center);

    // Soft body plus a small bright highlight offset toward one corner —
    // the "faint refractive shimmer" without ever sampling the content
    // behind it (overlay-only, D6).
    float body = smoothstep(radius, radius * 0.25, d);
    vec2 highlightCenter = center - vec2(radius, radius) * 0.35;
    float highlight = smoothstep(radius * 0.4, 0.0, length(pixel - highlightCenter));

    return body * 0.55 + highlight * 0.6;
}

void main() {
    vec2 fragCoord = FlutterFragCoord();
    vec2 pixel = vec2(fragCoord.x, fragCoord.y + uTime * kDriftPerSecond);

    vec2 cellF = pixel / kCellSize;
    vec2 cellI = floor(cellF);

    float total = 0.0;
    for (float dy = -1.0; dy <= 1.0; dy += 1.0) {
        for (float dx = -1.0; dx <= 1.0; dx += 1.0) {
            total += droplet(pixel, cellI + vec2(dx, dy));
        }
    }
    total = clamp(total, 0.0, 1.0);

    // Barely-there ceiling: even at full intensity this stays a mood, not a
    // foreground element.
    float a = total * uIntensity * 0.10;
    vec3 rgb = vec3(0.86, 0.90, 0.98); // cool, faintly blue highlight tint.

    fragColor = vec4(rgb * a, a);
}
