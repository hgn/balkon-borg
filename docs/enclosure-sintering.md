# Enclosure and manufacturing (SLS sintering)

Everything about the printed enclosure and its manufacture by SLS. Model:
`cad/balkon_borg.py`. Complements `build-notes.md`.

## Manufacturing decision: SLS / PA12, black

**Process: SLS** (Selective Laser Sintering, a laser fuses nylon powder).
**Material: PA12 nylon, dyed black.**

Why SLS over FDM/ASA or metal:

- **Look:** SLS gives an even, finely matte surface **with no layer lines and no
  support or seam marks** → a production-product look. FDM/ASA shows layer lines
  (especially on gussets, ears, rounds) and reads as "printed".
- **No supports** needed (the powder bed supports), complex geometry is no problem,
  isotropically strong.
- **Metal is ruled out:** a metal enclosure is a Faraday cage and blocks WiFi (ESP,
  WLED) and the LD2410B radar (which sees *through* the plastic membrane). Metal
  printing would also be thousands of euros and kilograms heavy at this volume. If a
  metal look is wanted: only the front as an aluminium bezel, the body stays plastic.

### Weather assessment (decisive for the material choice)

Location: under the balcony, **fully weather-protected**.
- **No direct sun** → PA12's UV weakness is practically **a non-issue**.
- **No rain/water.**
- **Humidity only:** PA12 takes up ~0.5-1 % moisture, swells minimally, gets a bit
  tougher. **Irrelevant** for an enclosure. No coating needed.

→ Under these conditions SLS/PA12 is the right choice. (ASA/FDM would only be
materially superior under direct sun/weathering.)

## SLS design rules (applied in the model)

| Rule | Requirement | Status in the model |
|---|---|---|
| Wall thickness | ≥ 1 mm (structural 2.5-3) | 3 mm (`WALL`) ✓ |
| Fit clearance | 0.4-0.6 mm | `TOL = 0.5` ✓ |
| Powder escape | avoid blind cavities, escape ≥ 3.5 mm | body open at the front ✓ |
| Min. hole | ≥ 1.5 mm | smallest 2 mm ✓ |
| Supports | none | not applicable (SLS) ✓ |
| Split reason | build volume (not warpage) | split at X=0, halves ~254 mm |

Notes: blow out blind insert holes (bosses) **with compressed air** before pressing
the insert. Set heat-set inserts (M2.5/M3) as usual.

## Printed parts (from `cad/build/`)

| Part | Size (mm) | Count |
|---|---|---|
| `balkon-borg-left` / `-right` | ~254 × 150 × 152 each (incl. ears/towers) | 2 (enclosure halves) |

Both as **STEP** to the service (STL works too). Material **PA12 SLS**, colour
**black** (dyed). The front stays open; the diffuser and LED panel are glued in at
the end, so there is no separate bezel part.

## Providers (Germany first, then EU)

Preference: a **German** service for fast delivery and easy PayPal handling; go
abroad only for a clearly bigger advantage.

| Provider | Location | Delivery | Note |
|---|---|---|---|
| **PRINCORE** | AT/DE | 2-4 days | German-speaking, fast, PA12 SLS in-house |
| **Reents3D** | DE | few days | small German shop, personal support |
| **3D-Druckdienstleister.de** | DE | few days | German portal, PA12 SLS, PayPal |
| **Craftcloud** | EU aggregator | often EU → fast | finds an EU sinterer, check PayPal at checkout |
| **JLC3DP** | China | ~1-2 weeks | cheapest, PayPal, only if price beats the rest clearly |

**Recommendation:** order from a **German** service (PRINCORE / Reents3D /
3D-Druckdienstleister.de) for fast shipping and easy PayPal. Only fall back to
Craftcloud (EU) or JLC3DP (China) if the price advantage is clearly worth the wait.

## Ordering

1. Upload `cad/build/*.step` of the two halves.
2. Process **SLS**, material **PA12 / nylon**, colour **black**.
3. Quantity 1 set, check the preview (wall-thickness warnings? there should be none).
4. Order the **fit test** first (one corner) or separately, before the full set goes
   out (see `build-notes.md`).
5. Pay (PayPal), have it shipped.
