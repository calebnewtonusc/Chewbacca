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

static inline float hash11(float p) { return fract(sin(p * 127.1) * 43758.5453); }

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

static inline float stage(float t, float a, float b) { return clamp((t - a) / (b - a), 0.0, 1.0); }

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
    const float SQ = 5.0;
    float rad = pow(pow(abs(r2.x), SQ) + pow(abs(r2.y), SQ), 1.0 / SQ);
    float gk = pow(max(rad, 1e-3), 1.0 - SQ);
    float2 g = float2(gk * pow(abs(r2.x), SQ - 1.0) * (2.0 / W),
                      gk * pow(abs(r2.y), SQ - 1.0) * 2.0);
    return min((1.0 - rad) / max(length(g), 0.6) + margin, 0.95);
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
    float2 size;
    float2 popAt;
    /// Unit coordinates, top-left origin. Off screen when there is no pointer.
    float2 pointer;
    float time;
    float act;
    float closing;
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
};

/// A full-screen triangle with no vertex buffer. Three vertices covering the
/// clip cube beat two triangles covering the quad: no shared edge down the
/// diagonal, so no pixels are shaded twice along it.
vertex float4 presenceVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    return float4(p * 2.0 - 1.0, 0.0, 1.0);
}

fragment half4 presenceFragment(float4 fragPos [[position]],
                                constant Uniforms &U [[buffer(0)]]) {
    float2 size = U.size;
    float time = U.time, act = U.act, closing = U.closing;
    float2 popAt = U.popAt;
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
    // survives only in the corners, where the superellipse dips to 0.09. That
    // is exactly what the 55% thickness cut did on 2026-09-19: every state
    // landed under 0.2, the four edges went empty, and the field read as four
    // smudges in the corners of the screen. So the band is measured from here
    // rather than from zero, and `rest` is now the visible depth above it.
    const float MARGIN = 0.200;

    float depth = rest * clamp(t / 0.45, 0.0, 1.0);

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

    // --- going away ------------------------------------------------------
    // Nothing here is eased either. A rupturing film does not decelerate: the
    // hole opens at the speed where surface tension balances the film's own
    // inertia, and high speed footage shows that speed holding from the first
    // frame to the last. Straight in, straight out, and nothing in this file
    // eases any more: the last easing function went with the arrival wobble.
    if (closing >= 0.0) {
        float k = closing;
        float2 dp = (uv - popAt) * float2(W, 1.0);
        float rr = length(dp), ang = atan2(dp.y, dp.x);

        // It thins where it is about to go. In a real bubble this is the black
        // spot: the two surfaces come within a wavelength of each other and
        // their reflections cancel, so the last thing you see before it bursts
        // is darkness opening in a place that still has film in it.
        c *= 1.0 - 0.9 * exp(-rr * 13.0) * stage(k, 0.0, 0.10);

        float R = max(k - 0.10, 0.0) * 7.0;

        // Smooth while the rim is thin, then shear against the still air tears
        // indentations into it. They appear past a critical radius, which is
        // why a pop ends in a scatter instead of starting as one.
        float tear = smoothstep(0.30, 0.95, R);
        float edge = R * (1.0 + 0.10 * tear * sin(ang * 13.0 + 1.7));

        c *= smoothstep(edge - 0.02, edge + 0.01, rr);

        // The film the hole swallowed has to go somewhere and it collects in
        // the rim. That is why the edge of a bursting bubble is brighter than
        // the film was, and why fading one out looks nothing like one.
        float ring = exp(-pow((rr - edge) / 0.014, 2.0)) * (0.35 + R * 1.1) * (1.0 - tear * 0.5);
        c += ring * mix(float3(1.0), sheen, 0.55);

        // Drops thrown out of the indentations, flying a little ahead of the
        // rim that threw them.
        float b = floor((ang + 3.14159265) * 15.0 / 6.2831853);
        float sd = hash11(b * 7.31);
        float detach = 0.30 + sd * 0.55;
        if (R > detach) {
            float dr = detach + (R - detach) * 1.45;
            float da = (b + 0.5) / 15.0 * 6.2831853 - 3.14159265 + (sd - 0.5) * 0.26;
            c += exp(-pow(length(dp - float2(cos(da), sin(da)) * dr) / 0.011, 2.0)) * 1.5 *
                 exp(-(R - detach) * 1.7);
        }

        c *= 1.0 - stage(k, 0.44, 0.60);
    }

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
    return half4(half3(min(c, float3(a))), half(a));
}
"""##
