import Foundation

/// The Metal source for the presence field, as a string.
///
/// It lives here rather than in a `.metal` file because compiling one needs
/// `xcrun metal`, which ships with Xcode and not with the Command Line Tools.
/// A `.metal` file in the target would make a full Xcode install a build
/// requirement for the whole package. `MTLDevice.makeLibrary(source:)` costs
/// one compile at launch and keeps the package building on any Mac.
let presenceFieldSource = ##"""
#include <metal_stdlib>
using namespace metal;

// The presence field: the other half of the presence surface.
//
// PresenceRing.swift answers "is it there" in sixteen points in one corner.
// This answers it in peripheral vision across the whole edge of the display,
// which is the only place a person is actually looking when they are working.
// Both are driven by the same `p <state> [amp=]` op and the same seven states,
// and the rule from the ring applies here twice over: each state must have a
// distinct motion signature identifiable without looking at it. Six states
// that all breathe are one state.
//
// What it draws is a pool of liquid banked against every edge of the screen,
// with one free surface facing in. The mass bulges, the bulges stretch and
// come home, and it is one connected body at every moment. The colour is a
// contour field over that body: a near transparent ground, blue filaments,
// and a rim on each filament running yellow out to an inferno orange.
//
// Ported from the WebGL prototype in the Chewbacca repo at
// skills/hud/presence/refined.html. The shading is the same arithmetic; the
// browser's separable bloom and Reinhard pass are not here, because a
// `colorEffect` is one pass with no render targets. The tonemap is folded in
// below. The glow is not, and the field is a little flatter for it.


static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static inline float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1.0, 0.0)), f.x),
               mix(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), f.x), f.y);
}

static inline float fbm(float2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * vnoise(p);
        p *= 2.03;
        a *= 0.5;
    }
    return s;
}


/// Belcour and Barla's pre-integrated spectral response, verbatim from
/// KHR_materials_iridescence. Only the shimmer is taken off it now, but it is
/// still the honest version: the whole visible spectrum interfering with itself
/// at one optical path difference, integrated against the eye's three
/// sensitivities, rather than a hue rotated by hand.
static inline float3 filmResponse(float opd) {
    float phase = 6.2831853 * opd * 1.0e-9;
    float3 val = float3(5.4856e-13, 4.4201e-13, 5.2481e-13);
    float3 pos = float3(1.6810e+06, 1.7953e+06, 2.2084e+06);
    float3 vr = float3(4.3278e+09, 9.3046e+09, 6.6121e+09);
    float3 xyz = val * sqrt(6.2831853 * vr) * cos(pos * phase) * exp(-phase * phase * vr);
    xyz.x += 9.7470e-14 * sqrt(6.2831853 * 4.5282e+09) * cos(2.2399e+06 * phase) *
             exp(-4.5282e+09 * phase * phase);
    xyz /= 1.0685e-7;
    float3x3 toRGB = float3x3(float3(3.2404542, -0.9692660, 0.0556434),
                              float3(-1.5371385, 1.8760108, -0.2040259),
                              float3(-0.4985314, 0.0415560, 1.0572252));
    return toRGB * xyz;
}

/// How deep into the liquid a point is, in screen heights, measured from a
/// silhouette that sits a constant distance off every edge of the display.
///
/// The level sets of a superelliptic norm are rounded at every depth. A rounded
/// rectangle's are not: that one only curves within its own corner radius and
/// goes back to square corners deeper in. But the norm is taken per axis, so a
/// fixed step in it is a longer step in points down the wide side of a screen.
/// Dividing by its own gradient turns it back into a distance, which keeps the
/// pool the same thickness the whole way round while still putting the four
/// screen corners inside it. The floor on the gradient stops the estimate
/// running away near the middle, where the norm has no useful gradient and the
/// answer is only ever "far".
static inline float depthAt(float2 uvp, float W, float margin) {
    float2 r2 = (uvp - 0.5) * 2.0;
    // How square the corners are. The level set through the diagonal sits at
    // 2^(-1/SQ) of the half-width, so the band's inner surface cuts each
    // corner by 13% of it at 5 and by 5.6% at 12, and the band fills the
    // whole wedge between that curve and the square screen corner. Was 5,
    // rendered side by side at 5, 8 and 12 by FieldRenderTests on
    // 2026-09-20 after the ask "decrease how much boundary its covering in
    // the corners": at 12 the corner still rounds, and the band runs at
    // close to one thickness into it instead of pooling.
    const float SQ = 12.0;
    float rad = pow(pow(abs(r2.x), SQ) + pow(abs(r2.y), SQ), 1.0 / SQ);
    float gk = pow(max(rad, 1e-3), 1.0 - SQ);
    float2 g = float2(gk * pow(abs(r2.x), SQ - 1.0) * (2.0 / W),
                      gk * pow(abs(r2.y), SQ - 1.0) * 2.0);
    return min((1.0 - rad) / max(length(g), 0.6) + margin, 0.95);
}

/// Where along the edge of the screen a point sits, 0 to 1, clockwise from the
/// top-left corner, measured to the nearest edge. The voice ripples, the done
/// sweep, the sparks and the tendril all travel along the edge rather than
/// across the screen, so all four read this one number.
static inline float perimeterAt(float2 uv, float W) {
    float x = uv.x * W, y = uv.y;
    float dl = x, dr = W - x, dt = y, db = 1.0 - y;
    float m = min(min(dl, dr), min(dt, db));
    float s;
    if (m == dt) s = x;
    else if (m == dr) s = W + y;
    else if (m == db) s = W + 1.0 + (W - x);
    else s = 2.0 * W + 1.0 + (1.0 - y);
    return s / (2.0 * W + 2.0);
}

/// How far apart two perimeter positions are, the short way round, in screen
/// heights.
static inline float along(float a, float b, float W) {
    return abs(fract(a - b + 0.5) - 0.5) * (2.0 * W + 2.0);
}

/// `position` is in points with a top-left origin, which is what the rest of
/// this app measures in. `size` is the view. Everything else is state.
///
/// `rest` is how thick the pool sits at rest, `drift` how fast the contour
/// field travels round the edge, `tint` is the colour the body takes and how
/// much of it, and `pulse` is how many times a second the whole thing breathes.
/// Those are the entire state vocabulary as far as this shader is concerned,
/// which is deliberate: PresenceField.swift owns the mapping from the named
/// states, so a new state is a row in a table there rather than a branch here.
///
/// `tint` is first because it is the only member wider than a `float2`, and
/// both Metal and Swift align a four-wide vector to sixteen bytes. Anywhere
/// else in this list it would need padding that one side would have to know
/// about and the other would get wrong.
struct Uniforms {
    /// rgb is what the body is multiplied by, a is how much of it to take.
    float4 tint;
    /// The hyper bar's rectangle, unit coordinates, top-left origin: x, y,
    /// width, height. Its body is drawn here, out of the same liquid as the
    /// band, so the bar and the edge read as one material.
    float4 pill;
    float2 size;
    /// Unit coordinates, top-left origin. Off screen when there is no pointer.
    float2 pointer;
    /// Where the agent's cursor is, the same way. Off screen when it has none.
    float2 agent;
    /// How far the far smoke layer has slid with the pointer, in noise units.
    float2 parallax;
    float time;
    /// Seconds into the arrival, or, on the way out, seconds left of it.
    float act;
    float rest;
    /// How far the contour field has travelled, already integrated on the
    /// Swift side from an eased drift. Multiplying `time` by a drift that had
    /// just changed moved the whole pattern in one frame.
    float travel;
    /// How much of the breath to take, 0 to 1, eased in and out.
    float pulse;
    /// Where in the breath, in cycles, integrated from an eased rate.
    float beat;
    float alpha;
    /// How far the band has parted round the pointer, 0 to 1.
    float part;
    /// The parting's clear radius and its soft edge, in screen heights,
    /// converted from points on the Swift side.
    float partRadius;
    float partFeather;
    /// How far the tendril toward the agent has grown, 0 to 1.
    float reach;
    /// Seconds since the run finished, for the sweep. Large when there is none.
    float sweep;
    /// Where on the perimeter the sweep starts: the agent's last spot, or the
    /// hyper bar.
    float sweepOrigin;
    /// How many sparks are lifting off the band, 0 to 1. Acting only.
    float embers;
    /// How much of the bar is there, 0 to 1, eased, so it condenses in and
    /// evaporates out rather than cutting.
    float pillOn;
};

/// How loud the voice was, one sample every RIPPLE_STEP seconds, newest first.
/// A point on the edge reads the sample from as long ago as a ripple takes to
/// travel to it from the hyper bar, so loudness moves outward along the edge
/// instead of swelling the whole band at once.
constant int RIPPLE_SAMPLES = 32;
constant float RIPPLE_STEP = 0.05;
/// Screen heights a second. Half the perimeter of a 16:10 display is about
/// 2.6 heights, so a syllable reaches the top edge in about a second and a
/// half, which is the whole history the buffer holds.
constant float RIPPLE_SPEED = 1.7;
/// Guessed, never measured: the done sweep's fronts meet on the far side in
/// about 1.2 s on the same display, quick enough to read as one gesture.
constant float SWEEP_SPEED = 2.2;

/// A full-screen triangle with no vertex buffer. Three vertices covering the
/// clip cube beat two triangles covering the quad: no shared edge down the
/// diagonal, so no pixels are shaded twice along it.
vertex float4 presenceVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    return float4(p * 2.0 - 1.0, 0.0, 1.0);
}

fragment half4 presenceFragment(float4 fragPos [[position]],
                                constant Uniforms &U [[buffer(0)]],
                                constant float *voice [[buffer(1)]]) {
    float2 size = U.size;
    float time = U.time, act = U.act;
    float rest = U.rest, pulse = U.pulse;
    float2 uv = float2(fragPos.x / size.x, fragPos.y / size.y);
    float t = act;
    float W = size.x / max(size.y, 1.0);

    // One breath drives the pool's thickness and its resting depth together.
    // Two sines at their own rates read as two layers sitting on each other
    // rather than as one object. The phase is modulated so the swing is not
    // symmetric, because a breath is not: it moves through the thin half faster
    // than it rests in the thick.
    // One oscillator, read twice: once on how much of the state's colour the
    // body takes and once on how bright the whole thing is. Driving only the
    // brightness gives a band that blinks, and driving only the hue gives one
    // that changes colour without ever seeming to move. Together they read as
    // something running.
    // Faded in by `pulse` rather than switched on, and run off `beat`, which
    // the Swift side integrates from an eased rate: a breath that starts at
    // whatever phase the clock is on lands as a brightness jump, and one that
    // starts at full depth lands as a flash.
    float wave = mix(1.0, 0.5 + 0.5 * sin(U.beat * 6.2831853), pulse);

    float bp = time * 0.72;
    float breath = sin(bp + 0.45 * sin(bp));

    // The whole arrival is one number: how far into the screen the band
    // reaches.
    //
    // It used to overshoot to 3.4x and settle through a damped cosine, on the
    // argument that a pushed volume of fluid oscillates in its second shape
    // mode and that the wobble is what reads as liquid rather than as
    // hardware. That was the right model for liquid and the wrong one for
    // this: it is not a pool, it is an instrument arriving, and an instrument
    // that bounces on arrival reads as a spring toy. A straight line to the
    // resting depth, and then it holds.
    // How far the silhouette sits off every edge, in the units `depthAt`
    // returns. It is the value that field takes at the screen edge itself, so
    // a pool shallower than this draws nothing along the straight runs and
    // survives only in the corners, where the superellipse dips to 0.15. That
    // is exactly what the 55% thickness cut did on 2026-09-19: every state
    // landed under 0.2, the four edges went empty, and the field read as four
    // smudges in the corners of the screen. So the band is measured from here
    // rather than from zero, and `rest` is now the visible depth above it.
    const float MARGIN = 0.200;

    float depth = rest * clamp(t / 0.45, 0.0, 1.0);

    float P = 2.0 * W + 2.0;
    float here = perimeterAt(uv, W);
    // How far into the screen this pixel is, before any lobe moves the surface.
    float intoScreen = depthAt(uv, W, MARGIN) - MARGIN;

    // The tendril. The band reaches a finger toward wherever the agent is
    // working, from the edge nearest it: the depth is raised along a Gaussian
    // in the distance round the edge from the agent's foot, so the finger is
    // wide where it leaves the band and narrows to a point. Raising the depth
    // rather than drawing a shape is what makes it the same liquid: every
    // term below, the lobes and the contours, measures itself against it.
    if (U.agent.x > -1.0 && U.reach > 0.001) {
        float2 a = U.agent;
        float toEdge = min(min(a.x * W, (1.0 - a.x) * W), min(a.y, 1.0 - a.y));
        // Toward it, never onto it: the finger stops short of the cursor so
        // it points rather than covers, and never longer than a finger.
        float len = min(toEdge * 0.8, depth + 0.12);
        float lat = along(here, perimeterAt(a, W), W);
        depth = max(depth, U.reach * len * exp(-pow(lat / 0.05, 2.0)));
    }

    // The voice. A point this far round the edge from the hyper bar shows how
    // loud it was that long ago, so each syllable leaves the bar and runs out
    // along the bottom edge and up the sides, fading as it goes. It swells
    // the band only where the ripple is: the whole band thickening with the
    // voice was the old behaviour, and it read as the screen inhaling.
    float fromBar = along(here, (W + 1.0 + 0.5 * W) / P, W);
    float slot = fromBar / RIPPLE_SPEED / RIPPLE_STEP;
    float ripple = 0.0;
    if (slot < float(RIPPLE_SAMPLES - 1)) {
        int i = int(slot);
        ripple = mix(voice[i], voice[i + 1], fract(slot)) * exp(-fromBar * 0.55);
    }
    depth *= 1.0 + 0.6 * ripple;

    // Nothing is drawn deeper into the screen than the band reaches, and the
    // band cannot reach past one and a half depths: the displacement below
    // moves the free surface by at most 0.375 of a depth. Measured on
    // 2026-09-19 on an M4 Pro at 5120x2880: the full pass cost 10.8 ms a
    // frame, two thirds of a 60fps frame, almost all of it on pixels that
    // came out empty, and the band stuttered under the pointer. Leaving here
    // is what makes the noise below affordable.
    // The hyper bar, as a capsule of the band's own liquid. A signed distance
    // in screen heights, negative inside. It grows from 60% of its size as it
    // condenses in, so it arrives as a bead forming rather than a fade.
    float pillSdf = 1.0;
    float2 pillCentre = float2(0.5, 1.0);
    float2 pillHalf = float2(0.0);
    if (U.pillOn > 0.001) {
        pillCentre = (U.pill.xy + U.pill.zw * 0.5) * float2(W, 1.0);
        pillHalf = U.pill.zw * 0.5 * float2(W, 1.0) * mix(0.6, 1.0, U.pillOn);
        float radius = pillHalf.y;
        float2 box = abs(uv * float2(W, 1.0) - pillCentre) - (pillHalf - radius);
        pillSdf = length(max(box, 0.0)) + min(max(box.x, box.y), 0.0) - radius;
    }
    bool inPill = pillSdf < 0.0;

    // The sparks rise past the band, so it keeps a little more when they are
    // on.
    if (!inPill && intoScreen > depth * 1.5 + 0.01 + 0.08 * U.embers) {
        return half4(0.0);
    }

    float born = smoothstep(0.0, 0.02, depth);

    // The band parts round the pointer so what is under it can be read. The
    // pool thins to nothing inside the clear radius and is back to full
    // depth one feather further out, with no edge at either end, so the free
    // surface bows out toward the glass around the cursor rather than
    // showing a hole cut in it. Thinning the depth rather than the alpha is
    // what moves the surface: every term below measures itself against
    // `depth`.
    float2 toPointer = (uv - U.pointer) * float2(W, 1.0);
    float hole = U.part * (1.0 - smoothstep(U.partRadius, U.partRadius + U.partFeather,
                                             length(toPointer)));
    depth *= 1.0 - hole;

    // Domain warped noise. The field is sampled at coordinates that are
    // themselves displaced by another sample of it, twice. Plain noise gives
    // soft round blobs; this gives drawn out filaments and folded sheets,
    // because the thickness of a real film is not sitting still, it is being
    // carried around by convection and the streaks are the flow.
    float2 p = uv * float2(W, 1.0) * 1.25;
    float dt = U.travel * 0.035;
    float2 w1 = float2(fbm(p + float2(0.0, dt)), fbm(p + float2(5.2, 1.3) - dt * 0.7));
    float2 w2 = float2(fbm(p + 3.4 * w1 + float2(1.7, 9.2) + dt * 0.5),
                       fbm(p + 3.4 * w1 + float2(8.3, 2.8)));
    float flow = fbm(p + 3.2 * w2);

    // A second, fainter layer behind the first, finer and drifting the other
    // way at a different rate, and sliding a little with the pointer. Two
    // layers moving past each other is what reads as volume; one reads as a
    // printed sheet.
    float2 p2 = p * 1.8 + U.parallax + float2(-dt * 1.7, dt * 0.45);
    float flow2 = fbm(p2 + 2.2 * w1.yx);

    // The silhouette sits off every edge, so the liquid runs past all four
    // sides and fills the corners instead of stopping short of them. The only
    // boundary in view is the inner one, and that is the one doing the work.
    float2 q = (uv - 0.5) * float2(W, 1.0);

    float inward = depthAt(uv, W, MARGIN);

    // Two lobes, both low, and that is the entire deformation of the surface.
    // A blob of wax filling four hundred points has one continuous curve for an
    // outline: no serration, no ripple, no texture at any scale. Three
    // overlapping fbm terms put detail down to sixteen points on this boundary,
    // and detail at sixteen points is what makes it read as torn. The second is
    // plain noise rather than fbm for the same reason: fbm's fourth octave is
    // exactly the detail this is trying not to have.
    // Scaled by the band's own depth. Written as a fixed displacement these
    // were tuned against a pool 0.268 deep, and against one 0.147 deep the
    // same numbers are two thirds of the whole band: the boundary stops being
    // a worked edge and becomes the shape of the noise, which is the blobby
    // look that reads as plastic.
    inward += ((fbm(q * 2.3 + float2(time * 0.155, -time * 0.118)) - 0.5) * 0.24 +
               (vnoise(q * 4.1 + float2(-time * 0.081, time * 0.136)) - 0.5) * 0.12) * depth;

    float u0 = clamp((inward - MARGIN) / max(depth, 1e-4), 0.0, 1.0);

    // One more on the inner edge alone, drifting mostly vertically while the
    // lobes run sideways, so the boundary is worked from two directions at
    // once. Lowest in frequency of the three and the largest in amplitude,
    // because what it is for is the long concave run: a wall of wax holds an
    // hourglass waist, two broad convex stretches with a concave one between
    // them, and that concave stretch is what reads as liquid rather than as a
    // bumpy line. Bumps come free from additive noise. A waist needs amplitude
    // at low frequency.
    inward += (fbm(q * 1.6 + float2(-time * 0.085, time * 0.50)) - 0.5) * 0.39 * depth *
              smoothstep(0.30, 1.0, u0);

    // Nothing leaves the edge. An earlier pass had blobs neck out of this
    // pool on a convection cycle and get absorbed back into it; it was
    // pulled out whole rather than tuned, so the band is the only body here
    // and the noise above is the only thing that moves it.

    // Off the silhouette there is nothing to draw. On screen this is one
    // everywhere, because the silhouette is off the edge: it is here for the
    // case where a lobe drags the boundary past a corner.
    float lit = smoothstep(0.0, 0.006, inward);

    // Where in the pool this pixel is: 0 at the free surface and 1 hard
    // against the glass. `inward` runs from MARGIN at the screen edge to
    // `band` at the surface, so this is the only normalisation that spends the
    // full 0 to 1 on the part of the field that is actually drawn.
    float u = clamp((inward - MARGIN) / max(depth, 1e-4), 0.0, 1.0);
    float v = 1.0 - u;

    // Inside the bar, the bar is the pool: its outline is the free surface
    // and its middle is the deep part, so the lip, the filaments and the
    // state's colour all land on it exactly as they land on the band. It wins
    // over the band where the two meet, which on a machine with the Dock
    // hidden makes the bar sit in the band like a bead on the edge.
    if (inPill) {
        v = clamp(-pillSdf / max(pillHalf.y, 1e-4), 0.0, 1.0);
        u = 1.0 - v;
        lit = 1.0;
        born = U.pillOn;
    }

    // Mapped back onto the window the film response was calibrated over
    // rather than handed the full 0 to 1. Taken literally the refracted angle
    // now sweeps half again as far as it used to, and the nm comment below
    // says what is at the ends of that: the only stretch of the cycle with no
    // dark in it is 265 to 335, and a wider sweep walks straight out of it.
    float cosI = mix(0.75, 1.0, u);
    float sinT = sqrt(max(1.0 - cosI * cosI, 0.0)) / 1.33;
    float cosT = sqrt(max(1.0 - sinT * sinT, 0.0));

    // A fixed amount of liquid over a surface that is still growing, so the
    // film thins as the pool arrives. The colour sweeps while the wall is
    // stretching and stops sweeping when it stops.
    float stretch = mix(1.9, 1.0, smoothstep(0.0, 0.70, t));

    // Measured rather than chosen. Ramping this across the screen and reading
    // the row back gives one full cycle every 210nm, and inside that cycle the
    // stretch from 265 to 335 is the only part with no dark in it. The
    // refracted angle is folded in at a sixth of its real weight: taken
    // literally it is a 1.5x multiplier on its own, which is most of a cycle
    // before anything else has moved.
    float angle = mix(0.86, 1.0, cosT);
    float nm = (296.0 + 24.0 * flow - (uv.y - 0.5) * 17.0 + 15.0 * breath) * angle * stretch;
    float3 refl = max(0.5 * (float3(1.0) - filmResponse(2.0 * 1.33 * nm)), float3(0.0));
    float shimmer = 0.86 + 0.34 * dot(refl, float3(0.333));

    // The contour field. Level sets of the same warped flow, plus the pool's
    // own depth, folded through a triangle wave so they repeat with no seam;
    // fract() alone puts a hard step at every period and it reads as a cut.
    // Weighted toward the flow and away from the depth, because depth alone
    // draws contours parallel to the edge, and concentric rings round a screen
    // are a racetrack.
    // How many filaments land inside the band. At 3.4 there are a dozen of
    // them across a band this width, all the same brightness, and a dozen
    // parallel lines of equal weight is a topographic map or a slab of
    // malachite: it is the one thing that stopped this reading as metal even
    // with a neutral palette and a tight specular. At 1.5 there are two or
    // three, and `fres` picks one of them out near the free surface, which is
    // what a lit edge actually looks like.
    float ctr = (flow * 1.5 + v * 1.0 + 0.16 * breath) * stretch;
    // In the bar the depth term would draw rings round a shape 34 points
    // tall, which is the racetrack this weighting exists to avoid, and the
    // band's flow barely changes across it. So the bar reads the finer far
    // layer and hardly the depth: filaments running along it, not round it.
    if (inPill) ctr = (flow2 * 3.2 + v * 0.2 + 0.16 * breath) * stretch;
    float tri = abs(fract(ctr) - 0.5) * 2.0;
    float d = tri - 0.5;

    // Clear is nearly transparent, not white: the ground between the filaments
    // is liquid you are meant to see through, and on a screen that is dim. The
    // pool does not thin out toward the glass, so the ground fills in solid
    // toward the screen edge and the only boundary in view is the inner one.
    // Steel, not liquid colour. Every one of these is within a few percent of
    // neutral with a slight cool cast, because that is what metal is: the hue
    // carries almost nothing and the whole read comes from how fast it goes
    // from dark body to hot specular. Saturate any of these and it stops being
    // steel and becomes tinted plastic, which is the failure this palette
    // replaced.
    const float3 CLEAR = float3(0.13, 0.14, 0.155);
    const float3 POOL = float3(0.16, 0.175, 0.20);
    // Two greys: a mid one on a filament's shoulders and a near white one
    // along its spine, where the liquid is thinnest and should read as clear.
    const float3 BLUE_DEEP = float3(0.26, 0.28, 0.32);
    const float3 BLUE_PALE = float3(0.84, 0.87, 0.92);
    // The specular. Near white and barely warm, which is what a polished
    // surface returns; the falloff beside it stays cool so the highlight reads
    // as a reflection rather than as a colour the object has.
    const float3 YEL = float3(1.00, 0.99, 0.96);
    const float3 ORG = float3(0.50, 0.54, 0.60);

    float3 blueC = mix(BLUE_DEEP, BLUE_PALE, smoothstep(0.26, 0.46, d));
    float3 ground = mix(CLEAR, POOL, smoothstep(0.22, 0.90, v));

    // The rim is a quarter of the period, not a third. At a third it stops
    // being the heat on the edge of a filament and becomes a rope running round
    // the screen.
    float toRim = smoothstep(-0.13, -0.05, d);
    float toBlue = smoothstep(0.03, 0.11, d);
    float3 col = mix(ground, mix(ORG, YEL, smoothstep(-0.05, 0.03, d)), toRim);
    col = mix(col, blueC, toBlue);

    // The rim is the only part hotter than the liquid carrying it, and how
    // hot and how wide is the whole difference between metal and moss. At 0.40
    // over a 0.070 wide falloff it is a soft green glow along a soft edge,
    // which is what an overgrown surface looks like. Narrow it to 0.045 and
    // drive it to 0.95 and the same filament becomes a thin bright line with
    // dark either side, which is what a machined one looks like. The line
    // stays near white whatever the state's tint is, because the tint block
    // below protects the specular core.
    col *= (1.0 + 0.95 * exp(-pow((d + 0.01) / 0.045, 2.0))) * shimmer;

    float tri2 = abs(fract(flow2 * 2.4 + v * 0.7) - 0.5) * 2.0;
    col += exp(-pow((tri2 - 0.49) / 0.03, 2.0)) * 0.20 * BLUE_PALE * (1.0 - 0.7 * toBlue);

    // Colour is the whole state channel and it is spent on three readings:
    // white while it is listening or waiting, green while it is doing
    // something, red when something failed. Steel is what is left when the
    // amount is zero, and it is most of the time.
    //
    // The hue goes on the body and never on the hot part of the specular. A
    // highlight that takes the object's own colour is the single thing that
    // makes a surface read as plastic: metal returns the light's colour at the
    // hot spot and tints only the falloff beside it. `core` is what holds that
    // line, and without it the green states came back looking like a moulded
    // toy however neutral the rest of the palette was.
    if (U.tint.a > 0.001) {
        // The hue breathes between 55% and 100% of its own amount, so a
        // pulsing state is a band that keeps its colour and moves through it
        // rather than one that switches on and off.
        float amt = U.tint.a * mix(0.45, 1.0, wave);
        // Ink in water. The colour lives in the filaments and their rims, and
        // the body between them takes a fifth of it, so a green state is dark
        // smoke with green running through it rather than a green band. The
        // whole band flooding green was what read as a gaming overlay.
        float strand = max(toRim * (1.0 - toBlue), exp(-pow((d + 0.01) / 0.07, 2.0)));
        amt = min(amt * mix(0.22, 1.2, strand), 1.0);
        float3 hue = float3(dot(col, float3(0.42, 0.34, 0.24))) * U.tint.rgb;
        // The window this protects is the hottest specular only. At 0.55 to
        // 1.05 it covered the filament rims as well, which are most of the
        // bright pixels in the band, and the measured result was a band whose
        // green channel led its red by seven levels out of 255: grey with a
        // rumour of green in it. Tinting those and keeping only the blown
        // highlight neutral is what a coloured light on steel actually does.
        float core = smoothstep(0.95, 1.60, max(max(col.r, col.g), col.b));
        col = mix(mix(col, hue, amt), col, core * 0.85);
    }

    // A touch hotter at the free surface and flat everywhere else. Driven off
    // the grazing angle it is a three hundred point ramp from bright to
    // nothing, and a ramp is a vignette however it was derived.
    //
    // The split between the two terms is what decides whether this reads as
    // metal or as fog. At 0.62 flat and 0.55 at the surface the body carried
    // more light than the surface did, and a screenshot on a grey checker came
    // back as an even haze with no highlight anywhere on the straight runs.
    // Steel is the other way round: a dark body and a narrow hot surface.
    float fres = 0.22 + 1.05 * exp(-v * 9.0);

    // The pool ends at its surface, over about a seventh of its own depth, and
    // is at full strength everywhere behind that.
    float env = smoothstep(0.0, 0.14, v);

    float3 sheen = normalize(col + float3(0.0015));
    float3 c = col * fres * env * born * lit;

    // The surface is a lip, not a place the gradient ran out. Liquid held by
    // surface tension beads along its own edge and the bead catches light, so
    // the thing that reads as an edge is a bright line sitting on it. Gated by
    // the same termination the body uses: without that gate it is the one term
    // with no idea where the liquid ends, and at a tenth of its peak across the
    // whole screen it reads as a haze over everything.
    // This is the line that makes it read as a machined edge rather than as a
    // lit slab, so it is much stronger and much narrower than it was: 0.30
    // over a 0.038 window instead of 0.11 over 0.055. One bright streak
    // running parallel to the screen edge, with dark on both sides of it.
    //
    // And it is mostly white rather than mostly the body's own colour. At 0.92
    // toward `sheen` the highlight took the state's tint with it, and a green
    // highlight on a green body is what plastic does. A metal one returns the
    // light.
    c += env * exp(-pow((v - 0.220) / 0.050, 2.0)) * 0.30 * mix(float3(1.0), sheen, 0.45) * born *
         lit;

    // The ripple is light as well as depth: most of what the eye catches is
    // the crest brightening as it passes.
    c *= 1.0 + 2.2 * ripple;

    // The bar lights the edge under it: a pool of light on the bottom of the
    // band, as wide as the bar, so the two read as one body even with the
    // Dock between them.
    if (!inPill && U.pillOn > 0.001) {
        float across = (uv.x * W - pillCentre.x) / max(pillHalf.x, 1e-3);
        c *= 1.0 + 0.7 * U.pillOn * exp(-across * across) * smoothstep(0.85, 1.0, uv.y);
    }
    c += env * born * lit * ripple * 0.35 * mix(float3(1.0), sheen, 0.3);

    // The done sweep: one crest leaves where the agent last was, runs both
    // ways round the band, and the two meet on the far side and fade.
    if (U.sweep < 2.0) {
        float fromOrigin = along(here, U.sweepOrigin, W);
        float crest = exp(-pow((fromOrigin - U.sweep * SWEEP_SPEED) / 0.10, 2.0));
        float fading = 1.0 - smoothstep(1.1, 1.6, U.sweep);
        c += crest * fading * env * born * lit * mix(float3(1.0), sheen, 0.45) * 0.75;
    }

    // Sparks, while it is doing something to the machine. The edge is cut
    // into cells and some of them carry one spark each on its own cycle,
    // rising off the free surface and shrinking as it goes. Only the cell
    // under this pixel and its neighbours are asked, so the cost is three
    // dots, not ninety.
    if (U.embers > 0.001) {
        const float CELLS = 90.0;
        float spark = 0.0;
        float cell0 = floor(here * CELLS);
        for (int k = -1; k <= 1; k++) {
            float cell = cell0 + float(k);
            if (hash21(float2(cell, 1.9)) < 0.55) continue;
            float seed = hash21(float2(cell, 3.1));
            float life = 2.2 + seed * 1.4;
            float phase = fract(time / life + seed * 7.3);
            float centre = (cell + 0.2 + 0.6 * hash21(float2(cell, 8.7))) / CELLS;
            float lat = (fract(here - centre + 0.5) - 0.5) * P +
                        sin(phase * 6.2831853 + seed * 9.0) * 0.006;
            float rise = depth + 0.005 + phase * (0.04 + 0.03 * seed);
            float r = 0.0028 * (1.0 - 0.6 * phase);
            float dot2 = lat * lat + (intoScreen - rise) * (intoScreen - rise);
            spark += exp(-dot2 / (r * r)) * smoothstep(0.0, 0.1, phase) *
                     (1.0 - smoothstep(0.55, 1.0, phase));
        }
        float3 hot = mix(float3(1.0, 0.98, 0.94), U.tint.rgb * 0.8, 0.5 * U.tint.a);
        c += spark * U.embers * born * hot * 0.8;
    }

    // The bar is for reading. The lip and the strands nearest it keep their
    // light and the middle, where the words sit, falls to about a quarter of
    // it. At full strength the filaments ran bright behind the text: Gavin,
    // 2026-09-23, "the smoke is too aggresive and bright in the hyper bar,
    // can barely read the text".
    if (inPill) c *= mix(1.0, 0.25, smoothstep(0.10, 0.40, v));

    // Going away is arriving, backwards. The Swift side runs `act` down from
    // wherever it was to zero at the same rate it came up, so the band draws
    // back into the edge along the exact path it came in on. It used to
    // burst: a rupture opening at a random point, a bright rim, drops thrown
    // off the tears. Reviewed on 2026-09-19 as "the same but reversed as the
    // intro animation, get rid of the pop".

    // Reinhard, folded in. The browser version tonemapped in a separate pass
    // over a half-float target; there is one pass here and no target, so it
    // happens on the way out.
    c = max(c * 2.60, 0.0);
    c = c / (1.0 + c);

    // Alpha is coverage, and coverage is how much liquid is at this point.
    // Everything on this layer composites over the person's actual screen, so
    // the middle of the display has to come back genuinely empty rather than
    // black: a background here, at any opacity, tints the entire display.
    //
    // SwiftUI wants premultiplied, and `c` is already the colour this adds over
    // what is behind it, so the premultiplied form is `c` itself with the
    // coverage in alpha.
    // `acting` breathes for as long as it is acting. The two-beat pulse in
    // PresenceField.swift is for a state that pulses and then holds; this is
    // for one that is genuinely still running, and a thing that is still
    // running has to keep saying so. Off the shader clock rather than off a
    // Swift timer, because the timer would have to tick at the frame rate to
    // drive it and that is a second clock doing the first one's job.
    c *= mix(0.74, 1.0, wave);

    // Coverage. Was 1.05, which put the film just above the noise floor on a
    // bright desktop: the band was there and you had to look for it. A layer
    // nobody can see without hunting is not quiet, it is broken.
    float a = clamp(max(max(c.r, c.g), c.b) * 1.75, 0.0, 1.0) * U.alpha;
    // The bar carries words, so its body is smoke you cannot quite see
    // through, where the band is smoke you can: white type needs something
    // dark behind it over a white page. Guessed, never measured.
    if (inPill) a = max(a, 0.78 * env * born);
    return half4(half3(min(c, float3(a))), half(a));
}

// The glow. The browser prototype had a separable bloom and the one-pass port
// could not, which is why the rims stopped at a hard edge. These run on a
// quarter-size copy: the field is drawn, its bright parts are shrunk into
// `bloomDown`, blurred across and then down, and `bloomComposite` lays the
// glow back under the field so the rims light the screen around them.

constexpr sampler bilinear(filter::linear, address::clamp_to_edge);

/// Only the rims and the sparks glow. Below this the body would add a haze
/// over everything near the edge, which is fog, not light.
constant float BLOOM_THRESHOLD = 0.25;

fragment half4 bloomDown(float4 fragPos [[position]],
                         texture2d<float> field [[texture(0)]]) {
    float2 outSize = float2(field.get_width(), field.get_height()) / 4.0;
    float2 uv = fragPos.xy / outSize;
    float2 texel = 1.0 / float2(field.get_width(), field.get_height());
    // Four bilinear taps cover the four by four block this pixel stands for.
    float4 c = 0.25 * (field.sample(bilinear, uv + texel * float2(-1.0, -1.0)) +
                       field.sample(bilinear, uv + texel * float2(1.0, -1.0)) +
                       field.sample(bilinear, uv + texel * float2(-1.0, 1.0)) +
                       field.sample(bilinear, uv + texel * float2(1.0, 1.0)));
    float bright = max(max(c.r, c.g), c.b);
    return half4(c * smoothstep(BLOOM_THRESHOLD, BLOOM_THRESHOLD + 0.35, bright));
}

fragment half4 bloomBlur(float4 fragPos [[position]],
                         texture2d<float> source [[texture(0)]],
                         constant float2 &direction [[buffer(0)]]) {
    float2 size = float2(source.get_width(), source.get_height());
    float2 uv = fragPos.xy / size;
    float2 pace = direction / size;
    // Thirteen taps a texel and a quarter apart, sigma 3.5 texels: at a
    // quarter of the screen's size that is a glow reaching about thirty
    // points past the rim.
    float4 sum = float4(0.0);
    float total = 0.0;
    for (int i = -6; i <= 6; i++) {
        float w = exp(-float(i * i) / (2.0 * 2.8 * 2.8));
        sum += source.sample(bilinear, uv + pace * float(i) * 1.25) * w;
        total += w;
    }
    return half4(sum / total);
}

fragment half4 bloomComposite(float4 fragPos [[position]],
                              texture2d<float> field [[texture(0)]],
                              texture2d<float> glow [[texture(1)]],
                              constant float &strength [[buffer(0)]]) {
    float2 uv = fragPos.xy / float2(field.get_width(), field.get_height());
    float4 f = field.sample(bilinear, uv);
    // The glow belongs round the liquid, not on top of it. Where the field is
    // already dense, which is the bar's body, the rim's glow is mostly held
    // back, or it washes over the words from both edges at once.
    float3 g = glow.sample(bilinear, uv).rgb * strength * (1.0 - 0.8 * f.a);
    float3 c = f.rgb + g;
    // Premultiplied, like the field: the glow brings its own coverage, so it
    // shows over a white document as well as a dark one.
    float a = clamp(max(f.a, max(max(g.r, g.g), g.b) * 0.9), 0.0, 1.0);
    return half4(half3(min(c, float3(a))), half(a));
}
"""##
