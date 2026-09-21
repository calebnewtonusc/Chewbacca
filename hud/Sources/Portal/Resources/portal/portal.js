(() => {
  var __defProp = Object.defineProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

  // vendor/smooth.ts
  function smoothPath(points, passes = 2) {
    let pts = points.map((p) => ({ x: p.x, y: p.y }));
    for (let pass = 0; pass < passes; pass++) {
      const out = pts.slice();
      for (let i = 1; i < pts.length - 1; i++) {
        out[i] = {
          x: (pts[i - 1].x + pts[i].x * 2 + pts[i + 1].x) / 4,
          y: (pts[i - 1].y + pts[i].y * 2 + pts[i + 1].y) / 4
        };
      }
      pts = out;
    }
    return pts;
  }

  // vendor/mirror-gl.ts
  var VERT = `#version 300 es
in vec2 aPos;
out vec2 vPix;
uniform vec2 uSize;
void main() {
  vPix = (aPos * 0.5 + 0.5) * uSize;
  gl_Position = vec4(aPos, 0.0, 1.0);
}`;
  var FRAG = `#version 300 es
precision highp float;
in vec2 vPix;
out vec4 outColor;

uniform vec2  uC;
uniform float uR;
uniform float uAStart, uASpan, uDir;
uniform float uLead, uSpiral, uFog, uVeil, uStrength, uInset;
uniform vec4  uImg;
uniform sampler2D uTex;

const float TAU = 6.283185307179586;

// CLOUD IS NOT A BENT EDGE, IT IS AN EDGE THAT BREAKS UP.
//
// "The dynamics of the edges are still sharp, super far from water/clouds
// fading into each other."
//
// Everything before this moved the boundary: lobes on the inner edge, a
// ragged reach on the ends. But the falloff across it stayed a single clean
// smoothstep, and a clean ramp reads as a clean ramp however you bend its
// centreline. What makes something look like cloud is the edge dissolving
// into patches at several sizes at once, so there is no one line to find.
//
// Four octaves of value noise. The coarse ones tear the front into lobes
// the size of a fist, the fine ones fray those into wisps, and because it
// is sampled in screen position it does not swim when the circle grows.
float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, amp = 0.5;
  for (int k = 0; k < 4; k++) { v += amp * vnoise(p); p *= 2.03; amp *= 0.5; }
  return v;
}

// The inner edge, as a fraction of the radius consumed, at position u along
// the arc. u 0 is where the line joined the circle, u 1 is the leading edge.
//
// wind makes it a spiral: shallow where the circle began, deepest at the
// leading edge. It relaxes as the fill completes, so the two ends converge
// and what is left at the end is a disc in the middle rather than a crescent
// lying against the rim.
float depthAt(float u) {
  // A GREAT DIFFERENCE BETWEEN THE TWO ENDS, CONVERGING LATE.
  //
  // "There's supposed to be a great difference between the length of the
  // starting radii to the ending radii from the outside, and they
  // exponentially reach the same distance of hitting the middle at the end."
  //
  // Two knobs, both measured rather than felt. The coefficient sets how far
  // apart the ends get, and the exponent on the convergence sets how long
  // they stay apart before meeting. Gap between the two ends, as a fraction
  // of the radius, at fills of 0.3 / 0.5 / 0.7 / 0.85 / 0.95 / 1.0:
  //
  //   1.6, linear      5  16  23  13   2  0     peak 23% at 0.70
  //   6.0, ^0.55       5  18  40  49  19  0     peak 49% at 0.85
  //
  // The first was a lean; the second is a spiral that is still visibly a
  // spiral at 85% drawn and then closes up fast. Both still arrive at
  // exactly zero, so the two ends hit the middle together.
  float wind = 1.0 + 6.0 * pow(max(0.0, 1.0 - u), 1.6)
                   * uSpiral * pow(max(0.0, 1.0 - uLead), 0.55);
  return clamp(pow(max(uLead, 1e-5), wind), 0.0, 1.0);
}

void main() {
  vec2 d = vPix - uC;
  float r = length(d);

  // Position along the arc. Taken the way the hand went, so it is 0 at the
  // start and grows to 1 at the leading edge, and anything past 1 is the
  // wedge that has not been drawn.
  float rel = mod((atan(d.y, d.x) - uAStart) * uDir + TAU, TAU);
  float span = max(uASpan, 1e-4);
  float u = rel / span;

  // THE WEDGE TAKES THE DEPTH OF THE END IT IS NEAR.
  //
  // "There's this weird ledge at the starting radii that is sharp and
  // sticks out towards the middle."
  //
  // clamp(u, 0, 1) hands every pixel in the undrawn wedge the depth of the
  // LEADING edge, which is the deepest point of the spiral. That includes
  // the pixels sitting right beside where the circle STARTED, where the
  // spiral is at its shallowest. So the inner edge jumped from shallow to
  // deepest across that boundary, and a jump in the inner edge is a ledge
  // pointing at the middle. It is worst exactly when the spiral is widest,
  // which is now.
  //
  // Each half of the wedge belongs to the end it is nearer, so the depth
  // carries on continuously round both sides instead of stepping.
  // THE TWO ENDS RUN INTO EACH OTHER ACROSS THE GAP.
  //
  // "The second radii has a hard firm radii too. What happened to making it
  // like 2 cloudy liquid ends that combine into each other? Not just lego
  // pieces that stack."
  //
  // Killing the earlier ledge, each half of the undrawn gap was given the
  // depth of whichever end it was nearer. That removed the step at the
  // start of the arc and put a new one exactly halfway round the gap, where
  // the depth flipped from the leading end's to the start's in one pixel.
  // It did not show while the gap was empty. It shows now, because the
  // spill reaches into the gap, and a discontinuity inside something
  // visible is a hard radial line: two ends stacked rather than merged.
  //
  // Interpolated across the gap instead. The depth leaves the leading edge
  // at its deepest, eases round through the empty part, and arrives at the
  // start's shallow depth, so the two ends are one continuous surface
  // meeting itself. Smoothstepped, so there is no corner where the blend
  // starts or finishes either.
  float gapAng = max(TAU - span, 1e-4);
  float across = clamp((rel - span) / gapAng, 0.0, 1.0);
  float uSafe = rel <= span ? u : mix(1.0, 0.0, smoothstep(0.0, 1.0, across));
  float depth = depthAt(uSafe);
  float inner = uR * (1.0 - depth);

  // LIQUID, NOT A COMPASS ARC. "It should feel like liquid on a table,
  // expanding to fill the canvas and dissolving into each other."
  //
  // A few sines of different periods around the angle put slow lobes in the
  // front, so it spreads unevenly the way a spill does instead of advancing
  // as a perfect circle. It is a field, so where two lobes meet they simply
  // add up and there is no join: dissolving into each other is not arranged
  // here, it is what adding smooth functions does.
  //
  // Faded out by the fill, so the front is at its most liquid while it is
  // spreading and is exactly circular by the time it arrives. Nothing
  // survives completion.
  float a2 = atan(d.y, d.x);
  float lobes = sin(a2 * 3.0 + 1.7) * 0.55
              + sin(a2 * 5.0 - 0.9) * 0.30
              + sin(a2 * 8.0 + 2.3) * 0.15;
  // Heavier, so the front reads as something spreading rather than a curve
  // being swept. Still faded out by the fill, so it is gone by the end.
  inner *= 1.0 + 0.16 * lobes * (1.0 - uLead);
  inner = max(inner, 0.0);

  // THE BAND IS A FRACTION OF THE HOLE, NOT OF THE REVEALED RIBBON.
  //
  // "It looks like a really hard spiral now."
  //
  // This was (uR - inner) * uFog, the thickness of what had ALREADY been
  // revealed. Early in a fill that ribbon is a sliver: at 30% filled it is
  // 1.9% of the radius, so the soft band came out about 5px and the spiral
  // had a hard edge exactly when it is most visible.
  //
  // Measured against the hole the front is moving INTO instead, held at a
  // constant width so the softness does not change as it advances, and
  // capped by the hole itself so it cannot reach past the middle and is
  // squeezed to nothing as the hole closes.
  //
  //   fill   hole    band was   band now
  //   0.30   95.1%      1.9%      18.0%
  //   0.60   72.1%     10.6%      18.0%
  //   0.90   23.2%     29.2%      18.0%
  //   0.97    7.3%     35.2%       7.3%
  //   1.00    0.0%     38.0%       0.0%
  // A FLOOR, OR THE ROUNDING VANISHES EXACTLY WHEN THE WEDGE IS BIGGEST.
  //
  // Capping the band by the remaining hole keeps the fog from reaching past
  // the middle, which is right for the RADIAL side. But it also shrinks the
  // band to nothing as the circle finishes, and the band is what rounds the
  // ends. So the last wedge before completion, the most visible thing on
  // screen, got knife edges: still a pie, after being told it was a pie.
  //
  //   fill 0.80   hole 42.8% of R   band 18.0%
  //   fill 0.90   hole 23.2%        band 18.0%
  //   fill 0.95   hole 12.0%        band 12.0%
  //   fill 0.98   hole  4.9%        band  4.9%   <- knife
  //
  // Floored at a tenth of the radius. The radial side cannot overshoot
  // anyway, because the distance into the hole is at most the hole itself,
  // so a wider band there just means the last scrap dissolves rather than
  // being cut out.
  // BLURRED, THEN PROGRESSIVELY SHARP. "We're not having the edges blur and
  // then progressively unblur."
  //
  // The band is a fraction of the hole, so it is at its widest while the
  // hole is, and narrows with it: soft at the start, crisp by the end, with
  // nothing to switch off. A floor of a tenth of the radius was holding it
  // soft to the last frame, which is what stopped it ever sharpening. The
  // floor was there to keep the ends rounded once the hole got small, and
  // it is not needed any more: the spill's over-reach closes the gap before
  // the hole is small enough to matter, so there is no wedge left to round.
  float band = max(1.0, min(uR * uFog, inner));

  // ONE DISTANCE, NOT TWO FADES MULTIPLIED. THIS IS WHAT STOPS IT BEING A
  // PIE.
  //
  // "It is a pie bruh. What happened to all the stuff we did?"
  //
  // Fair. The move to a shader carried over the spiral and the fog and quietly
  // dropped the two things that had killed the pie in the first place: the
  // rounded end caps and the dissolve at the ends. What replaced them was a
  // radial fade times an angular fade, and multiplying two separable fades
  // gives a SQUARE corner. The end of the ribbon was still a straight cut
  // from the rim down to the spiral, feathered a little. A feathered wedge
  // is a wedge.
  //
  // Measured as a distance instead. For a pixel outside the revealed sector,
  // take how far outside it is along the arc and how far inside the inner
  // edge it is, in pixels, and take the length of that pair. One falloff on
  // that distance rounds every corner by construction, which is the same
  // trick a rounded rectangle uses, and it is exactly what the hand built
  // caps were faking.
  //
  // Three things fall out of it for free:
  //
  //   The ends are round, so there is no wedge and no cap to draw.
  //   The corner where the end meets the spiral is one falloff rather than
  //   two meeting, so "the two things go into each other seamlessly".
  //   At a full turn nothing is ever outside the sector, so the angular term
  //   is zero everywhere and the seam cannot exist. The special case that
  //   used to blend it away is gone.
  // THE SPILL KEEPS SPREADING AFTER THE HAND PASSES.
  //
  // "It should feel like liquid on a table, expanding to fill the canvas and
  // dissolving into each other", and, on the sector that is left, "it is a
  // pie bruh."
  //
  // Softening the ends was never going to be enough. While any of the arc is
  // undrawn there is a sector with two straight sides, and feathering 26px
  // of a 261px radius still reads as a slice. The shape is the problem, not
  // its edges.
  //
  // Liquid does not stop where the hand stopped. It runs on, and the two
  // ends of a ring of liquid reach toward each other and merge before the
  // circle is mechanically closed. So the revealed sector over-reaches its
  // own ends by a distance that grows as the fill completes: early it is
  // almost nothing and the reveal tracks the hand honestly, late the two
  // ends run together and the gap closes itself instead of being cut.
  //
  // Squared, so the reaching is late and sudden rather than a steady
  // widening that would just look like the arc leading the finger.
  // THE ARC'S EDGE IS THE BOUNDARY. "Make the edge of the arc the boundary,
  // like a mask revealing the layer below."
  //
  // This used to run the reveal AHEAD of the line by up to 0.76 of the
  // radius, so the other side arrived somewhere the hand had not been yet.
  // It was put there to close the wedge at the end, and it is not needed
  // for that any more: the reveal is scaled to the 309 degrees that
  // actually opens a portal, so the sector is already a full turn by then
  // and there is no wedge left to fake shut.
  //
  // What remains is a few pixels of softness at the head, not a lead. The
  // mask now ends where the line is, which is the whole point of a mask.
  float reach = uR * 0.04;
  // THE ENDS ARE CLOUDY, NOT STRAIGHT RADII. "The starting radii and ending
  // radii have super sharp edges bruh theyre legos."
  //
  // Softening them was never going to fix it, because the problem was the
  // shape and not the gradient. Computed across the leading end at three
  // different radii, the old alpha profile was:
  //
  //   r=55% of R   1.00  1.00  0.94  0.30  0.00
  //   r=75% of R   1.00  1.00  0.94  0.30  0.00
  //   r=92% of R   1.00  1.00  0.94  0.30  0.00
  //
  // Identical at every radius, which is the definition of a straight line.
  // A perfectly straight edge reads as a cut however soft it is, and two of
  // them meeting a curve is a lego brick. The lobes above only ever
  // perturbed the INNER boundary; the ends had nothing.
  //
  // So the end wanders along its own length. The waves are in r, so how far
  // the spill has reached changes as you travel out from the centre, and
  // the front is ragged rather than radial:
  //
  //   r=55% of R   1.00  1.00  0.89  0.54  0.17  0.00
  //   r=75% of R   1.00  1.00  0.97  0.68  0.29  0.02
  //   r=92% of R   1.00  1.00  1.00  0.83  0.45  0.10
  //
  // Faded out by the fill like everything else, so a finished portal has
  // no ends to be ragged. The 0.55 widens the angular falloff against the
  // same band, taking the fade from about 10 degrees to about 20.
  float endWave = sin(r * 0.055 + 2.1) * 0.55
                + sin(r * 0.033 - 0.9) * 0.30
                + sin(r * 0.019 + 1.7) * 0.15;
  float reachHere = reach + uR * 0.13 * endWave * (1.0 - uLead);
  // THE TWO ENDS COMBINE INTO EACH OTHER, THEY DO NOT MEET. "What happened
  // to clouds/liquid that combine INTO each other not just next to each
  // other."
  //
  // This was min() of the distance to each end, and a plain minimum is the
  // operator for "whichever shape you are nearer to". Each end therefore
  // terminated on its own terms and the two of them met along the line
  // halfway between, which is precisely two things next to each other.
  // Rounding the corners and fraying the edges made them prettier and kept
  // them separate.
  //
  // Liquid merges because the fields ADD. As two droplets approach, each
  // one's surface is pulled toward the other and they fuse with a neck
  // rather than touching. The operator for that is a smooth minimum, which
  // is what a metaball is, and it is one line:
  //
  //   smin(a, b) = -log(exp(-ka) + exp(-kb)) / k
  //
  // Far apart it is the plain minimum and nothing changes. Close together
  // it dips below both, so the surface reaches out toward the other end and
  // the gap closes early and smoothly. With the blend radius at 0.22 R:
  //
  //   ends 400px apart   min 200px   smin 160px
  //   ends 240px apart   min 120px   smin  80px
  //   ends 140px apart   min  70px   smin  30px
  //   ends  80px apart   min  40px   smin   0px   <- fused
  //
  // The 40px it pulls by is the neck. That is the "into".
  float dAng;
  if (rel <= span) {
    dAng = 0.0;
  } else {
    float dA1 = (rel - span) * uR;
    float dA2 = (TAU - rel) * uR;
    float k = 1.0 / max(uR * 0.22, 1.0);
    float sm = -log(exp(-k * dA1) + exp(-k * dA2)) / k;
    dAng = max(sm - reachHere, 0.0) * 0.55;
  }
  float dRad = max(inner - r, 0.0);
  float dist = length(vec2(dAng, dRad));
  // The distance as a fraction of the band: 0 solid, 1 gone. Expressed this
  // way so the noise below is in the same units whatever the band is doing.
  float edge = dist / max(band, 1.0);

  // Two scales of the same field. The coarse one decides which parts of the
  // front have run ahead and which have lagged; the fine one frays those
  // into wisps. Together they make the boundary a region rather than a line.
  //
  // Faded out by the fill, like every other irregularity here, so a
  // finished portal has a clean rim and nothing survives completion.
  float wispy = 1.0 - uLead;
  float nCoarse = fbm(vPix * (2.6 / uR) + vec2(11.3, 7.9));
  float nFine   = fbm(vPix * (9.0 / uR) + vec2(31.7, 2.4));
  float wisp = ((nCoarse - 0.5) * 1.15 + (nFine - 0.5) * 0.45) * wispy;

  float fBody = 1.0 - smoothstep(0.0, 1.0, edge + wisp);

  // AND IT FADES OUT OVER A REAL DISTANCE, NOT TWO PIXELS. "Bro there's
  // still a rough edge."
  //
  // That edge was always there. Until the inset went in, the image ran all
  // the way to the rim and the ring's own stroke sat on top of exactly
  // those pixels, so the cut was hidden under the fire rather than absent.
  // Holding the image inside the ring exposed it, with 2.5px of softness
  // against a 261px radius, which is a cut with a hint of anti-aliasing.
  //
  // AND IT IS WIDE AT THE START AND CLOSED BY THE END. "It should start
  // with this gap/cloud on the outside, but as the circle closes it
  // progresses and it fades in, liquid expands to fill the circle."
  //
  // Making this independent of the fill was wrong in the other direction:
  // a finished portal kept a permanent cloudy vignette inside its own ring,
  // which is what the screenshot showed. The cloud belongs at the
  // BEGINNING, when the other side is only just bleeding through the rim,
  // and the liquid should push it out as it spreads.
  //
  //   fill 0.00   the image fades over 18% of the radius, all cloud
  //   fill 0.50   over 11%
  //   fill 1.00   over 2%, just enough not to alias
  //
  // Still fading inward from the ring's inner edge, so however wide it
  // gets it never crosses the arc.
  float outerEdge = uR - uInset;
  float outerFade = max(2.0, uR * (0.02 + 0.16 * (1.0 - uLead)));
  float fRim = smoothstep(outerEdge, outerEdge - outerFade, r);

  // Fades toward the rim while the circle is still filling.
  float veil = 1.0 - uVeil * mix(0.3, 1.0, clamp(r / uR, 0.0, 1.0));

  float a = fBody * fRim * veil * uStrength;
  if (a <= 0.002) discard;

  vec3 col = texture(uTex, (vPix - uImg.xy) / uImg.zw).rgb;
  // STRAIGHT ALPHA, NOT PREMULTIPLIED. "There's a shadow on the outside now
  // that I don't like." drawImage reads this canvas as an ordinary image,
  // which means straight alpha; handed premultiplied pixels it darkens
  // everything the closer that pixel is to transparent, which draws a dirty
  // ring exactly where the edge fades out.
  outColor = vec4(col, a);
}`;
  function compile(gl, type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(sh) || "shader failed");
    }
    return sh;
  }
  var MirrorGL = class {
    constructor() {
      __publicField(this, "canvas");
      __publicField(this, "gl", null);
      __publicField(this, "prog", null);
      __publicField(this, "tex", null);
      __publicField(this, "loc", {});
      /** Set once the image is uploaded. */
      __publicField(this, "uploaded", false);
      /** Non-null once something has gone wrong; the caller falls back. */
      __publicField(this, "error", null);
      this.canvas = document.createElement("canvas");
      try {
        const gl = this.canvas.getContext("webgl2", {
          alpha: true,
          premultipliedAlpha: false,
          antialias: false,
          // TRUE, OR drawImage READS AN EMPTY CANVAS.
          //
          // This canvas is never displayed; it exists to be copied into the 2D
          // canvas with drawImage. With preserveDrawingBuffer false the
          // drawing buffer may be discarded as soon as the frame is
          // composited, and a copy taken afterwards comes back blank. It
          // rendered during the draw and vanished once the portal opened,
          // which looked like a shader bug and was a lifetime bug.
          preserveDrawingBuffer: true
        });
        if (!gl) throw new Error("no webgl2");
        this.gl = gl;
        const prog = gl.createProgram();
        gl.attachShader(prog, compile(gl, gl.VERTEX_SHADER, VERT));
        gl.attachShader(prog, compile(gl, gl.FRAGMENT_SHADER, FRAG));
        gl.linkProgram(prog);
        if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
          throw new Error(gl.getProgramInfoLog(prog) || "link failed");
        }
        this.prog = prog;
        gl.useProgram(prog);
        const buf = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, buf);
        gl.bufferData(
          gl.ARRAY_BUFFER,
          new Float32Array([-1, -1, 3, -1, -1, 3]),
          gl.STATIC_DRAW
        );
        const aPos = gl.getAttribLocation(prog, "aPos");
        gl.enableVertexAttribArray(aPos);
        gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);
        for (const n of [
          "uSize",
          "uC",
          "uR",
          "uAStart",
          "uASpan",
          "uDir",
          "uLead",
          "uSpiral",
          "uFog",
          "uVeil",
          "uStrength",
          "uInset",
          "uImg",
          "uTex"
        ]) {
          this.loc[n] = gl.getUniformLocation(prog, n);
        }
        this.tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, this.tex);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      } catch (e) {
        this.error = String(e);
        this.gl = null;
      }
    }
    /** Upload the other side. Once; the image never changes. */
    setImage(img) {
      const gl = this.gl;
      if (!gl || !this.tex) return;
      try {
        gl.bindTexture(gl.TEXTURE_2D, this.tex);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, 1);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
        this.uploaded = true;
      } catch (e) {
        this.error = "texture upload: " + String(e);
        this.uploaded = false;
      }
    }
    get ready() {
      return !!this.gl && this.uploaded;
    }
    /** Draw one frame. Returns the canvas to composite, or null. */
    render(f) {
      const gl = this.gl;
      if (!gl || !this.prog || !this.uploaded) return null;
      if (this.canvas.width !== f.size || this.canvas.height !== f.size) {
        this.canvas.width = f.size;
        this.canvas.height = f.size;
      }
      gl.viewport(0, 0, f.size, f.size);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.useProgram(this.prog);
      gl.uniform2f(this.loc.uSize, f.size, f.size);
      gl.uniform2f(this.loc.uC, f.cx, f.size - f.cy);
      gl.uniform1f(this.loc.uR, f.R);
      gl.uniform1f(this.loc.uAStart, -f.aStart);
      gl.uniform1f(this.loc.uASpan, f.aSpan);
      gl.uniform1f(this.loc.uDir, -f.dir);
      gl.uniform1f(this.loc.uLead, f.lead);
      gl.uniform1f(this.loc.uSpiral, f.spiral);
      gl.uniform1f(this.loc.uFog, f.fog);
      gl.uniform1f(this.loc.uVeil, f.veil);
      gl.uniform1f(this.loc.uStrength, f.strength);
      gl.uniform1f(this.loc.uInset, f.inset);
      gl.uniform4f(
        this.loc.uImg,
        f.img.x,
        f.size - f.img.y - f.img.h,
        f.img.w,
        f.img.h
      );
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, this.tex);
      gl.uniform1i(this.loc.uTex, 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      return this.canvas;
    }
  };

  // vendor/circle.ts
  var EMPTY = {
    progress: 0,
    sweep: 0,
    center: null,
    radius: 0,
    completed: false,
    direction: null,
    startAngle: null,
    endAngle: null,
    roundness: 0
  };
  var CircleGestureDetector = class {
    constructor(options = {}) {
      __publicField(this, "trail", []);
      __publicField(this, "smooth", null);
      __publicField(this, "sweep", 0);
      __publicField(this, "lastT", 0);
      __publicField(this, "o");
      this.o = {
        // 5.4 rad is 309 degrees. 4.6 was 264, and "I barely drew part of a
        // circle and the portal opened" is what 264 degrees feels like. It
        // was lowered to 4.6 back when a display-scaling bug was shrinking
        // segments below minSegment and eating the sweep; that bug is fixed,
        // so the low threshold was compensating for something gone.
        // 5.6 rad is 321 degrees. Swept against arcs and circles across
        // radius, noise, speed profile and arm drift, as firing rate:
        //
        //     threshold   full circle   324 deg arc   270 deg arc
        //     5.4 (309)          79%           38%            5%
        //     5.6 (321)          77%           14%            2%
        //     5.8 (332)          57%           11%            3%
        //
        // 5.6 is the knee. Circles barely move and arcs fall by two thirds.
        // Past it real circles start failing hard, because a hand that has
        // come most of the way round has already stopped.
        // 5.4 rad is 309 degrees. 5.6 was over-correcting: it bought 18 points
        // against a 324 degree arc, which is very nearly a circle anyway, and
        // cost 23 points on a real circle that stops a little early. "Bro I
        // can't make circles lmao" is what that trade actually felt like.
        //
        //     threshold   circle 342deg  360deg   arc 300deg  arc 324deg
        //       5.40           84%        92%         12%         47%
        //       5.50           76%        90%          9%         39%
        //       5.60           61%        86%          7%         29%
        //
        // A 300 degree arc still only fires 12% of the time, which is the case
        // "I barely drew part of a circle and the portal opened" was about.
        sweepThreshold: options.sweepThreshold ?? 5.4,
        // How far the end may sit from the start, as a fraction of the fitted
        // radius, and still count as a closed loop.
        closeWithin: options.closeWithin ?? 0.75,
        // Roundness required to fire at all, the same gate the renderer uses
        // to decide something is becoming a circle.
        // 0.45, NOT 0.55. "Did you make it so u hv to do a perfect circle wtf."
        //
        // A circle drawn in the air with a fingertip is not round. Measured on
        // synthetic paths with realistic deformation: a 1.2:1 oval scores
        // 0.81, a 1.4:1 oval 0.61, and a circle with 8% radial wobble 0.56.
        // A real hand lands in that band, which put the bar right in the
        // middle of ordinary human input: some circles opened and some did
        // not, and nothing about the hand told you which.
        //
        // Swept the threshold against the shapes that must be refused. At
        // 0.45 every real circle still opens and nothing bad gets through; at
        // 0.38 a 1.6:1 oval does. So the bar sits at 0.45 with the evidence
        // for it rather than at a number that felt safe.
        minRoundness: options.minRoundness ?? 0.5,
        trailLength: options.trailLength ?? 240,
        // 0.004 of the frame is about 6px across, and a small circle drawn
        // with a fingertip has segments shorter than that: a 45px radius over
        // 80 samples is 3.5px a step. Every one was dropped, no turning
        // accumulated, and a small circle simply did not work. It fired 12% of
        // the time against 55% for a large one. 0.002 is 3px, still above the
        // ~2px the landmarks wander after the input average, and below
        // anything a moving hand covers.
        minSegment: options.minSegment ?? 2e-3,
        maxTurn: options.maxTurn ?? Math.PI / 2.2,
        staleMs: options.staleMs ?? 400,
        smoothing: options.smoothing ?? 0.45,
        roundDivisor: options.roundDivisor ?? 0.26
      };
    }
    /** Feed one frame. Pass null when the hand is gone. */
    update(lm, now = Date.now()) {
      if (!lm || lm.length < 21) {
        this.reset();
        return EMPTY;
      }
      return this.push(lm[8].x, lm[8].y, now);
    }
    /** Feed a raw point, for tests and for non-MediaPipe sources. */
    push(x, y, now = Date.now()) {
      if (this.lastT && now - this.lastT > this.o.staleMs) this.reset();
      this.lastT = now;
      if (!this.smooth) {
        this.smooth = { x, y };
      } else {
        const a = this.o.smoothing;
        this.smooth = {
          x: this.smooth.x + (x - this.smooth.x) * a,
          y: this.smooth.y + (y - this.smooth.y) * a
        };
      }
      x = this.smooth.x;
      y = this.smooth.y;
      const prev = this.trail[this.trail.length - 1];
      if (prev) {
        if (Math.hypot(x - prev.x, y - prev.y) < this.o.minSegment) {
          return this.report();
        }
      }
      this.trail.push({ x, y, t: now });
      if (this.trail.length > this.o.trailLength) this.trail.shift();
      const n = this.trail.length;
      if (n >= 3) {
        const a = this.trail[n - 3];
        const b = this.trail[n - 2];
        const c = this.trail[n - 1];
        const v1x = b.x - a.x;
        const v1y = b.y - a.y;
        const v2x = c.x - b.x;
        const v2y = c.y - b.y;
        const turn = Math.atan2(v1x * v2y - v1y * v2x, v1x * v2x + v1y * v2y);
        if (Math.abs(turn) > this.o.maxTurn) {
          this.smooth = null;
        } else {
          this.sweep += turn;
        }
      }
      const turned = Math.abs(this.sweep) >= this.o.sweepThreshold;
      let done = false;
      if (turned) {
        const probe = this.report(false);
        const win = this.window();
        const c = probe.center;
        let closes = false;
        if (win.length > 3 && probe.radius > 1e-6 && c) {
          const r0 = Math.hypot(win[0].x - c.x, win[0].y - c.y);
          const r1 = Math.hypot(win[win.length - 1].x - c.x, win[win.length - 1].y - c.y);
          closes = Math.abs(r1 - r0) <= probe.radius * this.o.closeWithin;
        }
        done = closes && probe.roundness >= this.o.minRoundness;
      }
      const out = this.report(done);
      if (done) {
        this.sweep = 0;
        this.trail = [];
      }
      return out;
    }
    report(completed = false) {
      if (this.trail.length < 3) {
        return { ...EMPTY, completed: false };
      }
      const { center, radius } = this.fit();
      const win = this.window();
      const first = win[0];
      const last = win[win.length - 1];
      let roundness = 0;
      const pts = this.window();
      if (pts.length >= 4) {
        const m = this.centroid();
        const spread = Math.sqrt(
          pts.reduce(
            (a, q) => a + (q.x - m.x) ** 2 + (q.y - m.y) ** 2,
            0
          ) / pts.length
        );
        const radii = pts.map((q) => Math.hypot(q.x - center.x, q.y - center.y));
        const mean = radii.reduce((a, b) => a + b, 0) / radii.length;
        const sd = Math.sqrt(
          radii.reduce((a, r) => a + (r - mean) ** 2, 0) / radii.length
        );
        if (spread > 1e-6) roundness = Math.max(0, 1 - sd / spread / this.o.roundDivisor);
      }
      if (pts.length >= 12) {
        const BINS = 8;
        const sm = smoothPath(pts, 2);
        let total = 0;
        for (let i = 1; i < sm.length; i++) {
          total += Math.hypot(sm[i].x - sm[i - 1].x, sm[i].y - sm[i - 1].y);
        }
        if (total > 1e-6) {
          const acc = new Array(BINS).fill(0);
          let run = 0;
          for (let i = 1; i < sm.length - 1; i++) {
            const ax = sm[i].x - sm[i - 1].x, ay = sm[i].y - sm[i - 1].y;
            const bx = sm[i + 1].x - sm[i].x, by = sm[i + 1].y - sm[i].y;
            const la = Math.hypot(ax, ay), lb = Math.hypot(bx, by);
            run += la;
            if (la < 1e-7 || lb < 1e-7) continue;
            const b = Math.min(BINS - 1, Math.floor(run / total * BINS));
            acc[b] += Math.atan2(ax * by - ay * bx, ax * bx + ay * by);
          }
          const sum = acc.reduce((a, v) => a + Math.abs(v), 0);
          if (sum > 1e-6) {
            const ideal = sum / BINS;
            const conc = acc.reduce((a, v) => a + Math.abs(Math.abs(v) - ideal), 0) / (2 * sum * (1 - 1 / BINS));
            roundness = Math.min(roundness, Math.max(0, 1 - conc / 0.66));
          }
        }
      }
      return {
        roundness,
        startAngle: Math.atan2(first.y - center.y, first.x - center.x),
        endAngle: Math.atan2(last.y - center.y, last.x - center.x),
        progress: Math.min(1, Math.abs(this.sweep) / this.o.sweepThreshold),
        sweep: this.sweep,
        center,
        radius,
        completed,
        direction: Math.abs(this.sweep) > 0.5 ? this.sweep > 0 ? "cw" : "ccw" : null
      };
    }
    reset() {
      this.trail = [];
      this.smooth = null;
      this.sweep = 0;
      this.lastT = 0;
    }
    /**
     * Algebraic least-squares circle fit (Kasa). Returns the centre of the
     * circle the path lies on, which is NOT the centroid of the path.
     *
     * WHY NOT THE CENTROID. The centroid of an arc sits inside the arc, pulled
     * toward wherever the samples are densest, and only coincides with the
     * centre when the loop is complete and evenly sampled. A hand always stops
     * a little short and always slows on one side, so the portal landed
     * consistently off from the circle the person actually drew.
     *
     * Fits x^2 + y^2 = a*x + b*y + c, which is linear in (a, b, c), so it is a
     * 3x3 solve with no iteration. Centre is (a/2, b/2). Coordinates are
     * shifted to the centroid first, because the raw normalized values are all
     * near 0.5 and squaring them costs precision in the normal equations.
     *
     * Falls back to the centroid when the points are nearly collinear, where
     * the fit is singular and would throw the portal off screen.
     */
    /**
     * The part of the trail the fit is allowed to see.
     *
     * THE BEGINNING OF A STROKE IS NOT PART OF THE CIRCLE. A hand moves into
     * position before it starts going round, and those first samples are a
     * short straightish lead-in that pulls the centre toward wherever the
     * hand happened to enter. Every later sample then has to drag the fit
     * back off it, which is the circle appearing to move while it is drawn.
     *
     * Measured over 40 simulated strokes (tilted ellipse, arm drift, wobble,
     * ten samples of lead-in), scoring the fit at latch against the fit to
     * the whole stroke:
     *
     *     drop first    centre jump at latch    radius jump
     *            0%                   28.4px         11.9px
     *           15%                   16.2px          4.7px
     *           25%                   18.1px          5.0px
     *           35%                   15.7px          9.0px
     *           50%                   30.3px         22.3px
     *
     * A quarter is in the flat middle of that. Half is worse than none,
     * because by then there are too few points left to fit.
     */
    window() {
      if (this.trail.length < 12) return this.trail;
      return this.trail.slice(Math.floor(this.trail.length * 0.25));
    }
    fit() {
      const pts = this.window();
      const m = this.centroid();
      const n = pts.length;
      let Sxx = 0, Sxy = 0, Syy = 0, Sxz = 0, Syz = 0, Sz = 0, Sx = 0, Sy = 0;
      for (const q of pts) {
        const x = q.x - m.x;
        const y = q.y - m.y;
        const z = x * x + y * y;
        Sxx += x * x;
        Sxy += x * y;
        Syy += y * y;
        Sxz += x * z;
        Syz += y * z;
        Sz += z;
        Sx += x;
        Sy += y;
      }
      const det = Sxx * Syy - Sxy * Sxy;
      const meanR = Math.sqrt(Sz / n);
      if (!isFinite(det) || Math.abs(det) < 1e-12) {
        return { center: m, radius: meanR };
      }
      const a = (Sxz * Syy - Syz * Sxy) / det;
      const b = (Syz * Sxx - Sxz * Sxy) / det;
      const cx = a / 2;
      const cy = b / 2;
      const c = Sz / n - (cx * Sx * 2 + cy * Sy * 2) / n;
      const r2 = cx * cx + cy * cy + c;
      const radius = r2 > 0 ? Math.sqrt(r2) : meanR;
      const center = { x: m.x + cx, y: m.y + cy };
      const drift = Math.hypot(cx, cy);
      if (!isFinite(radius) || radius > meanR * 2.5 || drift > meanR * 2.5 || radius > 0.75) {
        return { center: m, radius: Math.min(meanR, 0.75) };
      }
      return { center, radius };
    }
    centroid() {
      const pts = this.window();
      let x = 0;
      let y = 0;
      for (const p of pts) {
        x += p.x;
        y += p.y;
      }
      return { x: x / pts.length, y: y / pts.length };
    }
  };

  // vendor/portal-state.ts
  function initialPortalState() {
    return { phase: "idle", armed: true, born: 0, closeAt: 0, x: 0, y: 0, r: 0 };
  }
  function stepPortal(s, i, t = {}) {
    const igniteMs = t.igniteMs ?? 520;
    const closeMs = t.closeMs ?? 380;
    const minOpenMs = t.minOpenMs ?? 600;
    const n = { ...s };
    if (n.phase === "igniting" && i.now - n.born >= igniteMs) n.phase = "open";
    if (n.phase === "closing" && i.now - n.closeAt >= closeMs) n.phase = "idle";
    if (!i.pinched) n.armed = true;
    const alreadyUp = n.phase === "igniting" || n.phase === "open" || n.phase === "closing";
    if (i.completed && i.center && !alreadyUp) {
      n.phase = "igniting";
      n.born = i.now;
      n.closeAt = 0;
      n.x = i.center.x;
      n.y = i.center.y;
      n.r = i.radius ?? 0;
      n.armed = false;
      return n;
    }
    if ((n.phase === "open" || n.phase === "igniting") && i.pinched && n.armed && i.now - n.born > minOpenMs) {
      n.phase = "closing";
      n.closeAt = i.now;
      n.armed = false;
      return n;
    }
    const portalUp = n.phase === "igniting" || n.phase === "open" || n.phase === "closing";
    if (!portalUp) {
      n.phase = i.pinched && i.progress > 0.02 ? "drawing" : "idle";
    }
    return n;
  }
  function ignitionAmount(s, now, igniteMs = 520) {
    if (s.phase !== "igniting") return 1;
    return Math.min(1, (now - s.born) / igniteMs);
  }
  function collapseAmount(s, now, closeMs = 380) {
    if (s.phase !== "closing") return 0;
    return Math.min(1, (now - s.closeAt) / closeMs);
  }

  // vendor/pinch.ts
  function dist2D(a, b) {
    return Math.hypot(a.x - b.x, a.y - b.y);
  }
  function midpoint(a, b) {
    return {
      x: (a.x + b.x) / 2,
      y: (a.y + b.y) / 2,
      z: ((a.z ?? 0) + (b.z ?? 0)) / 2
    };
  }
  var PinchDetector = class {
    constructor(opts = {}) {
      __publicField(this, "enterRatio");
      __publicField(this, "exitRatio");
      __publicField(this, "holdMs");
      __publicField(this, "dragDeadzone");
      __publicField(this, "alpha");
      __publicField(this, "state", "idle");
      __publicField(this, "startedAt", 0);
      __publicField(this, "center", null);
      __publicField(this, "startCenter", null);
      __publicField(this, "lastCenter", null);
      __publicField(this, "smoothedCenter", null);
      this.enterRatio = opts.enterRatio ?? 0.38;
      this.exitRatio = opts.exitRatio ?? 0.52;
      this.holdMs = opts.holdMs ?? 220;
      this.dragDeadzone = opts.dragDeadzone ?? 0.012;
      this.alpha = 0.4;
    }
    handScale(lm) {
      const palmH = dist2D(lm[0], lm[9]);
      const palmW = dist2D(lm[5], lm[17]);
      return Math.max((palmH + palmW) * 0.5, 1e-4);
    }
    update(landmarks, now = performance.now()) {
      if (!landmarks || landmarks.length < 21) {
        const prev = this.state;
        this.state = "idle";
        this.smoothedCenter = null;
        return {
          state: "idle",
          changed: prev !== "idle",
          lost: true,
          center: null,
          delta: { x: 0, y: 0, z: 0 },
          ratio: 1,
          isPinched: false,
          heldMs: 0,
          scale: 1
        };
      }
      const thumb = landmarks[4];
      const index = landmarks[8];
      const rawDist = dist2D(thumb, index);
      const scale = this.handScale(landmarks);
      const ratio = rawDist / scale;
      const rawCenter = midpoint(thumb, index);
      if (!this.smoothedCenter) this.smoothedCenter = rawCenter;
      this.smoothedCenter = {
        x: this.smoothedCenter.x + this.alpha * (rawCenter.x - this.smoothedCenter.x),
        y: this.smoothedCenter.y + this.alpha * (rawCenter.y - this.smoothedCenter.y),
        z: (this.smoothedCenter.z ?? 0) + this.alpha * ((rawCenter.z ?? 0) - (this.smoothedCenter.z ?? 0))
      };
      this.center = this.smoothedCenter;
      const wasPinched = ["pinching", "holding", "dragging"].includes(this.state);
      const isPinched = wasPinched ? ratio < this.exitRatio : ratio < this.enterRatio;
      let changed = false;
      if (!wasPinched && isPinched) {
        this.state = "pinching";
        this.startedAt = now;
        this.startCenter = { ...this.center };
        changed = true;
      } else if (wasPinched && !isPinched) {
        this.state = "released";
        changed = true;
      } else if (wasPinched && isPinched) {
        const heldMs = now - this.startedAt;
        const move = this.startCenter ? dist2D(this.center, this.startCenter) : 0;
        this.state = move > this.dragDeadzone ? "dragging" : heldMs >= this.holdMs ? "holding" : "pinching";
      } else if (this.state === "released") {
        this.state = "idle";
        changed = true;
      }
      const delta = this.lastCenter && this.center ? {
        x: this.center.x - this.lastCenter.x,
        y: this.center.y - this.lastCenter.y,
        z: (this.center.z ?? 0) - (this.lastCenter.z ?? 0)
      } : { x: 0, y: 0, z: 0 };
      this.lastCenter = this.center ? { ...this.center } : null;
      return {
        state: this.state,
        changed,
        center: this.center,
        delta,
        ratio,
        isPinched,
        heldMs: wasPinched ? now - this.startedAt : 0,
        scale
      };
    }
  };

  // vendor/skeleton.ts
  var FINGER_TIPS = [4, 8, 12, 16, 20];

  // vendor/pointing.ts
  var MIN_SEPARATION_MM = 120;
  var MAX_RAY_GAIN = 8;
  var DEFAULT_ANTHRO = { ipdMm: 63, palmMm: 97 };
  var ROUGH_EYE_MM = 600;
  var ROUGH_HAND_MM = 350;
  var DEPTH_ADAPT = 0.02;
  var PARALLAX_STRENGTH = 0;
  var EYE_RANGE_MM = [300, 1100];
  var HAND_RANGE_MM = [150, 700];
  var clamp = (v, [lo, hi]) => Math.max(lo, Math.min(hi, v));
  var DepthTracker = class {
    constructor() {
      __publicField(this, "eyeMm", ROUGH_EYE_MM);
      __publicField(this, "handMm", ROUGH_HAND_MM);
    }
    /** Feed the per-frame measurements; get the steady values back. */
    update(measuredEye, measuredHand, adapt = DEPTH_ADAPT) {
      if (isFinite(measuredEye)) {
        const target = clamp(measuredEye, EYE_RANGE_MM);
        this.eyeMm += (target - this.eyeMm) * adapt;
      }
      if (isFinite(measuredHand)) {
        const target = clamp(measuredHand, HAND_RANGE_MM);
        this.handMm += (target - this.handMm) * adapt;
      }
      return { eyeMm: this.eyeMm, handMm: this.handMm };
    }
    reset() {
      this.eyeMm = ROUGH_EYE_MM;
      this.handMm = ROUGH_HAND_MM;
    }
  };
  var MACBOOK_14 = {
    widthMm: 302.4,
    heightMm: 196.4,
    widthPx: 1512,
    heightPx: 982,
    cameraXMm: 151.2,
    cameraYMm: -6
  };
  var MAC_CAMERA = { hfovDeg: 54, aspect: 16 / 9 };
  function focalNormalized(cam) {
    return 0.5 / Math.tan(cam.hfovDeg * Math.PI / 180 / 2);
  }
  function depthFromApparentSize(realMm, apparent, cam) {
    if (!(apparent > 1e-6)) return Infinity;
    return realMm * focalNormalized(cam) / apparent;
  }
  function cameraSpace(u, v, depthMm, cam) {
    const f = focalNormalized(cam);
    return {
      x: (u - 0.5) / f * depthMm,
      y: -(v - 0.5) / cam.aspect / f * depthMm,
      z: depthMm
    };
  }
  function rayToScreen(eye, finger, screen) {
    const dz = eye.z - finger.z;
    if (!(dz > MIN_SEPARATION_MM)) {
      return mmToPixels(finger.x, finger.y, screen);
    }
    const t = eye.z / dz;
    if (!isFinite(t) || t > MAX_RAY_GAIN) {
      return mmToPixels(finger.x, finger.y, screen);
    }
    return mmToPixels(
      eye.x + (finger.x - eye.x) * t,
      eye.y + (finger.y - eye.y) * t,
      screen
    );
  }
  function mmToPixels(xMm, yMm, screen) {
    return {
      x: (xMm + screen.cameraXMm) / screen.widthMm * screen.widthPx,
      y: (-yMm - screen.cameraYMm) / screen.heightMm * screen.heightPx
    };
  }
  function pointingPoint(input, screen = MACBOOK_14, cam = MAC_CAMERA, anthro = DEFAULT_ANTHRO, depths2, options = {}) {
    const { leftEye, rightEye, hand } = input;
    if (!hand || hand.length < 21) return null;
    const ipdApparent = Math.hypot(rightEye.x - leftEye.x, (rightEye.y - leftEye.y) / cam.aspect);
    const eyeDepth = depthFromApparentSize(anthro.ipdMm, ipdApparent, cam);
    if (!isFinite(eyeDepth)) return null;
    const palmApparent = Math.hypot(hand[9].x - hand[0].x, (hand[9].y - hand[0].y) / cam.aspect);
    const fingerDepth = depthFromApparentSize(anthro.palmMm, palmApparent, cam);
    if (!isFinite(fingerDepth)) return null;
    const steady = depths2 ? depths2.update(eyeDepth, fingerDepth) : { eyeMm: ROUGH_EYE_MM, handMm: ROUGH_HAND_MM };
    const eyeMid = { x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2 };
    const eye = cameraSpace(eyeMid.x, eyeMid.y, steady.eyeMm, cam);
    const t = hand[input.tip ?? 8];
    const finger = cameraSpace(t.x, t.y, steady.handMm, cam);
    const ray = rayToScreen(eye, finger, screen);
    const plain = mmToPixels(finger.x, finger.y, screen);
    const k = Math.max(0, Math.min(1, options.strength ?? PARALLAX_STRENGTH));
    return {
      x: plain.x + (ray.x - plain.x) * k,
      y: plain.y + (ray.y - plain.y) * k,
      eyeMm: steady.eyeMm,
      fingerMm: steady.handMm
    };
  }

  // portal.entry.ts
  var CORE = "255, 236, 189";
  var SPARK_HOT = "255, 196, 94";
  var SPARK_MID = "255, 141, 44";
  var SPARK_COLD = "214, 74, 16";
  var IGNITE_MS = 1150;
  var CLOSE_MS = 620;
  var MIN_OPEN_MS = 600;
  var ease = (t) => 1 - Math.pow(1 - t, 3);
  var easeShut = (t) => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  var IDLE_PROGRESS = {
    progress: 0,
    sweep: 0,
    center: null,
    radius: 0,
    roundness: 0,
    completed: false,
    direction: null,
    startAngle: null,
    endAngle: null
  };
  var canvas = document.getElementById("c");
  var ctx = canvas.getContext("2d");
  var detector = new CircleGestureDetector({ sweepThreshold: 1e6 });
  var pinchL = new PinchDetector();
  var state = initialPortalState();
  var sparks = [];
  var comet = [];
  var geom = { cx: 0.5, cy: 0.5, r: 0.1 };
  var attract = null;
  var spin = 0;
  var latest = null;
  var latestEyes = null;
  var depths = new DepthTracker();
  var parallaxStrength = PARALLAX_STRENGTH;
  var sizeScale = 1;
  var drawing = null;
  var trimmedAtLatch = false;
  var announcedAtLatch = false;
  var openGap = 0;
  var openGapFrom = 0;
  var openCcw = false;
  var mirrorAmt = 0;
  var recognisedLatch = false;
  var lastFill = 0;
  var drawnMax = 0;
  var cancelling = false;
  var ccwLatch = null;
  var lastPinchAt = 0;
  var heldCursor = null;
  var breaking = false;
  var formingLast = false;
  var fitRRef = 0;
  var fitJumpAt = 0;
  var arcStart = null;
  var arcSpan = 0;
  var cancelEat = 0;
  var CANCEL_FRAMES = 37;
  var holdOld = 0;
  var settleX = 0;
  var settleV = 0;
  var arcX = 0;
  var arcV = 0;
  var lastFrameMs = 0;
  var lastMaskCheck = 0;
  var lastInsideCheck = 0;
  var strokeDrawnThisFrame = false;
  var stepSpring = (x, v, k, dt) => {
    const c = 2 * Math.sqrt(k);
    const a = k * (1 - x) - c * v;
    const nv = v + a * dt;
    const nx = Math.min(1, x + nv * dt);
    if (1 - nx < 0.01 && Math.abs(nv) < 0.35) return { x: 1, v: 0 };
    return { x: nx, v: nv };
  };
  var stroke = [];
  var softFit = null;
  var reachScale = 1;
  var handScale = 0.45;
  var trailPx = 300;
  var mirror = new Image();
  var mirrorReady = false;
  mirror.onload = () => {
    mirrorReady = true;
    try {
      const probe = document.createElement("canvas").getContext("2d");
      if (probe) {
        probe.canvas.width = 120;
        probe.canvas.height = 40;
        probe.filter = "blur(8px)";
        probe.fillStyle = "#fff";
        probe.fillRect(0, 0, 60, 40);
        probe.filter = "none";
        const px = probe.getImageData(0, 20, 120, 1).data;
        let ramp = 0;
        for (let i = 0; i < 120; i++) {
          const a = px[i * 4 + 3];
          if (a > 12 && a < 243) ramp++;
        }
        probe.clearRect(0, 0, 120, 40);
        probe.shadowColor = "rgba(255,255,255,1)";
        probe.shadowBlur = 16;
        probe.shadowOffsetX = 200;
        probe.fillStyle = "#fff";
        probe.fillRect(-200, 0, 60, 40);
        probe.shadowBlur = 0;
        probe.shadowOffsetX = 0;
        const px2 = probe.getImageData(0, 20, 120, 1).data;
        let ramp2 = 0;
        for (let i = 0; i < 120; i++) {
          const a = px2[i * 4 + 3];
          if (a > 12 && a < 243) ramp2++;
        }
        window.webkit?.messageHandlers?.portal?.postMessage({
          event: "log",
          text: `filter ramp ${ramp}px, shadowBlur ramp ${ramp2}px (0 = ignored)`
        });
      }
    } catch (e) {
    }
    mirrorGL.setImage(mirror);
    if (!mirrorGL.ready) {
      fetch("mirror.jpg").then((r) => r.blob()).then((b) => createImageBitmap(b)).then((bmp) => {
        mirrorGL.setImage(bmp);
        window.webkit?.messageHandlers?.portal?.postMessage({
          event: "log",
          text: `mirror-gl bitmap upload: ${mirrorGL.ready ? "ok" : "still no"}`
        });
      }).catch((e) => {
        window.webkit?.messageHandlers?.portal?.postMessage({
          event: "log",
          text: `mirror-gl bitmap failed: ${e}`
        });
      });
    }
    if (!mirrorGL.ready) {
      fetch("mirror.jpg").then((r) => r.blob()).then((b) => createImageBitmap(b)).then((bmp) => {
        mirrorGL.setImage(bmp);
        window.webkit?.messageHandlers?.portal?.postMessage({
          event: "log",
          text: `mirror-gl via bitmap: ${mirrorGL.ready ? "ok" : "still no"}`
        });
      }).catch((e) => {
        window.webkit?.messageHandlers?.portal?.postMessage({
          event: "log",
          text: `mirror-gl bitmap failed: ${e}`
        });
      });
    }
    window.webkit?.messageHandlers?.portal?.postMessage({
      event: "log",
      text: `mirror loaded ${mirror.width}x${mirror.height} gl=${mirrorGL.ready ? "yes" : "NO"}`
    });
  };
  mirror.onerror = () => {
    window.webkit?.messageHandlers?.portal?.postMessage({
      event: "log",
      text: "mirror FAILED to load"
    });
  };
  mirror.src = window.__mirrorDataURL || "mirror.jpg";
  var mirrorGL = new MirrorGL();
  if (mirrorGL.error) {
    window.webkit?.messageHandlers?.portal?.postMessage({
      event: "log",
      text: `mirror-gl unavailable, using canvas: ${mirrorGL.error}`
    });
  }
  var LATCH_AT = 0.8;
  var SWEEP_TO_RECOGNISE = 5.4;
  var SWEEP_TO_OPEN = Math.PI * 2;
  var PINCH_GRACE_MS = 200;
  var lastSeen = 0;
  var armed = null;
  window.chewbaccaGain = (k) => {
    if (typeof k === "number" && isFinite(k)) {
      parallaxStrength = Math.max(0, Math.min(1, k));
    }
    return parallaxStrength;
  };
  window.chewbaccaSize = (k) => {
    if (typeof k === "number" && isFinite(k)) {
      sizeScale = Math.max(0.05, Math.min(3, k));
    }
    return sizeScale;
  };
  window.chewbaccaReach = (k) => {
    if (typeof k === "number" && isFinite(k)) {
      reachScale = Math.max(0.05, Math.min(2, k));
    }
    return reachScale;
  };
  window.chewbaccaHand = (k) => {
    if (typeof k === "number" && isFinite(k)) {
      handScale = Math.max(0.1, Math.min(1, k));
    }
    return handScale;
  };
  window.chewbaccaTrail = (k) => {
    if (typeof k === "number" && isFinite(k)) {
      trailPx = Math.max(40, Math.min(1200, k));
    }
    return trailPx;
  };
  var placedOk = false;
  var camW = 352;
  var camH = 288;
  window.chewbaccaCamera = (w, h) => {
    if (w > 0 && h > 0) {
      camW = w;
      camH = h;
    }
  };
  window.chewbaccaPlaced = (ok) => {
    placedOk = !!ok;
  };
  var demoUntil = 0;
  var demoT = 0;
  var demoTurns = 1.15;
  var demoR = 0.3;
  var demoLog = 0;
  var demoShape = "circle";
  var demoFired = false;
  var demoName = "";
  var demoPushing = 0;
  var lastProgress = IDLE_PROGRESS;
  var lastPinched = false;
  window.chewbaccaDemo = (secs, turns, r, shape, name) => {
    demoUntil = performance.now() + (secs || 3) * 1e3;
    demoT = 0;
    demoTurns = turns || 1.15;
    demoR = r || 0.3;
    demoShape = shape || "circle";
    demoName = name || demoShape;
    demoFired = false;
    detector.reset();
  };
  function demoPath(shape, t) {
    const a = t * Math.PI * 2;
    switch (shape) {
      case "oval14":
        return [Math.cos(a) * 1.4, Math.sin(a)];
      case "oval25":
        return [Math.cos(a) * 2.5, Math.sin(a)];
      case "line":
        return [-1 + 2 * t, 0];
      case "zigzag":
        return [-1 + 2 * t, Math.floor(t * 8) % 2 ? 0.4 : -0.4];
      case "scurve":
        return [-1 + 2 * t, Math.sin(a) * 0.5];
      case "arc70":
        return [Math.cos(a * 0.7), Math.sin(a * 0.7)];
      case "arc90":
        return [Math.cos(a * 0.9), Math.sin(a * 0.9)];
      case "square":
      case "triangle": {
        const n = shape === "square" ? 4 : 3;
        const f = (t % 1 + 1) % 1 * n, k = Math.floor(f), u = f - k;
        const vx = (i) => Math.cos(2 * Math.PI * i / n - Math.PI / 2);
        const vy = (i) => Math.sin(2 * Math.PI * i / n - Math.PI / 2);
        return [vx(k) + (vx(k + 1) - vx(k)) * u, vy(k) + (vy(k + 1) - vy(k)) * u];
      }
      default:
        return [Math.cos(a), Math.sin(a)];
    }
  }
  function demoHand(px, py) {
    const S = 0.1;
    const lm = [];
    lm[0] = { x: px - 0.02, y: py + S * 1.5, z: 0 };
    for (let i = 1; i <= 3; i++) lm[i] = { x: px - 0.01 + i * 2e-3, y: py + S * (1 - i * 0.25), z: 0 };
    lm[4] = { x: px, y: py, z: 0 };
    lm[5] = { x: px + 0.01, y: py + S * 0.7, z: 0 };
    lm[6] = { x: px + 8e-3, y: py + S * 0.45, z: 0 };
    lm[7] = { x: px + 4e-3, y: py + S * 0.2, z: 0 };
    lm[8] = { x: px + 15e-4, y: py + 1e-3, z: 0 };
    lm[9] = { x: px + 0.02, y: py + S * 0.75, z: 0 };
    for (let i = 10; i <= 12; i++) lm[i] = { x: px + 0.022, y: py + S * (0.75 - (i - 9) * 0.22), z: 0 };
    lm[13] = { x: px + 0.035, y: py + S * 0.8, z: 0 };
    for (let i = 14; i <= 16; i++) lm[i] = { x: px + 0.037, y: py + S * (0.8 - (i - 13) * 0.2), z: 0 };
    lm[17] = { x: px + 0.05, y: py + S * 0.9, z: 0 };
    for (let i = 18; i <= 20; i++) lm[i] = { x: px + 0.052, y: py + S * (0.9 - (i - 17) * 0.18), z: 0 };
    return lm;
  }
  window.chewbaccaArm = (label) => {
    armed = label ? { label } : null;
  };
  window.chewbaccaHands = (pts, eyes) => {
    if (demoPushing === 0 && performance.now() < demoUntil) return;
    latest = pts && pts.length === 21 ? pts : null;
    latestEyes = eyes ?? null;
    if (latest) lastSeen = performance.now();
  };
  window.chewbaccaPortalState = () => state.phase;
  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = window.innerWidth * dpr;
    canvas.height = window.innerHeight * dpr;
    canvas.style.width = `${window.innerWidth}px`;
    canvas.style.height = `${window.innerHeight}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  resize();
  window.addEventListener("resize", resize);
  function frame(now) {
    requestAnimationFrame(frame);
    if (now < demoUntil) {
      demoT += 1 / 30;
      const u = demoT / 3 * demoTurns;
      const wob = 1 + 0.03 * Math.sin(demoT * 7);
      const [pxu, pyu] = demoPath(demoShape, u);
      const sq = camH / camW;
      demoPushing = 1;
      window.chewbaccaHands(
        demoHand(0.5 + pxu * demoR * sq * wob, 0.5 + pyu * demoR * wob)
      );
      demoPushing = 0;
      if (state.phase === "igniting" || state.phase === "open") demoFired = true;
      if (now - demoLog > 250) {
        demoLog = now;
        window.webkit?.messageHandlers?.portal?.postMessage({
          event: "log",
          text: `demo ${demoName} t=${demoT.toFixed(1)} phase=${state.phase} lm=${latest ? "yes" : "NO"} pinch=${lastPinched ? "yes" : "NO"} sweep=${Math.abs(lastProgress.sweep).toFixed(2)}/5.40 round=${lastProgress.roundness.toFixed(2)}`
        });
      }
    } else if (demoName) {
      window.webkit?.messageHandlers?.portal?.postMessage({
        event: "log",
        text: `RESULT ${demoName} ${demoFired ? "OPENED" : "refused"}`
      });
      demoName = "";
    }
    const frameDt = Math.min(0.05, Math.max(1e-3, (now - lastFrameMs) / 1e3));
    lastFrameMs = now;
    const W = window.innerWidth;
    const H = window.innerHeight;
    ctx.globalCompositeOperation = "destination-out";
    ctx.fillStyle = "rgba(0, 0, 0, 1)";
    ctx.fillRect(0, 0, W, H);
    const lm = now - lastSeen < 300 ? latest : null;
    const camK = H / camH / (W / camW);
    const ax = Math.sqrt(camK);
    const ay = 1 / Math.sqrt(camK);
    const fit = (v, a) => Math.max(-0.3, Math.min(1.3, 0.5 + (v - 0.5) * reachScale * a));
    const toScreen = (p2, hub) => {
      const sx = hub ? hub.x + (p2.x - hub.x) * handScale : p2.x;
      const sy = hub ? hub.y + (p2.y - hub.y) * handScale : p2.y;
      return { x: fit(1 - sx, ax), y: fit(sy, ay) };
    };
    const mx = (nx) => nx * W;
    const my = (ny) => ny * H;
    const RMIN = 24;
    const RMAX = Math.min(W, H) * 0.42;
    const clampRN = (rn) => {
      const scaled = rn * sizeScale;
      const minRN = RMIN / Math.min(W, H);
      const KNEE = 0.24;
      const maxRN = 0.34;
      const capped = scaled <= KNEE ? scaled : KNEE + (maxRN - KNEE) * (1 - Math.exp(-(scaled - KNEE) / (maxRN - KNEE)));
      return Math.max(minRN, capped);
    };
    const px = mx;
    const py = my;
    const RPX = Math.min(W, H);
    const arcPath = (cn, rn, a0, a1, segs = 96, jitterPx = 0) => {
      const cx0 = px(cn.x), cy0 = py(cn.y);
      const r = rn * RPX;
      ctx.beginPath();
      for (let i = 0; i <= segs; i++) {
        const a = a0 + (a1 - a0) * i / segs;
        const rr = jitterPx ? r + (Math.random() - 0.5) * jitterPx : r;
        const qx = cx0 + Math.cos(a) * rr;
        const qy = cy0 + Math.sin(a) * rr;
        if (i === 0) ctx.moveTo(qx, qy);
        else ctx.lineTo(qx, qy);
      }
    };
    const rpxOf = (rn) => rn * RPX || 1;
    const disc = (cn, rn) => {
      ctx.beginPath();
      ctx.arc(px(cn.x), py(cn.y), rn * RPX, 0, Math.PI * 2);
    };
    const maskCv = document.createElement("canvas");
    const maskCtx = maskCv.getContext("2d");
    const paintMirror = (cxp, cyp, Rp, strength, gapFrom, gapSize, ccw, cloud, fill, spiral) => {
      if (!mirrorReady || !maskCtx || strength <= 4e-3 || Rp < 3) return;
      if (mirrorGL.ready) {
        const gpad = 2;
        const gsize = Math.ceil(2 * Rp + gpad * 2);
        const gox = cxp - Rp - gpad, goy = cyp - Rp - gpad;
        const gdir = ccw ? -1 : 1;
        const gspan = Math.min(Math.PI * 2, (1 - gapSize) * Math.PI * 2);
        const gf = Math.max(0, Math.min(1, fill));
        const gsc = Math.max(W / mirror.width, H / mirror.height);
        const gdw = mirror.width * gsc, gdh = mirror.height * gsc;
        const out = mirrorGL.render({
          size: gsize,
          cx: Rp + gpad,
          cy: Rp + gpad,
          R: Rp,
          aStart: gapFrom - gdir * gspan,
          aSpan: gspan,
          dir: gdir,
          // SPREAD ACROSS THE DRAW. "More of the progress has to happen
          // throughout the process." At ^2.5 the depth was 2% arrived a
          // fifth of the way round and 10% at two fifths, so almost all of
          // it landed in the last third. At ^1.35 it is 11% and 29%.
          //
          //   round    ^2.5    ^1.35
          //     20%      2%      11%
          //     40%     10%      29%
          //     60%     28%      50%
          //     80%     57%      74%
          lead: Math.pow(gf, 1.35),
          spiral,
          // A fraction of the hole, so it cannot touch the middle early and
          // cannot outlive completion.
          fog: 0.3,
          // THE IMAGE NEVER OVERLAPS THE ARC. The other side used to be
          // painted right out to the rim, which is where the ring's own
          // stroke sits, so the two shared those pixels and the city showed
          // through the fire. Held inside the ring's inner edge instead: the
          // widest ring pass is about a tenth of the radius wide and centred
          // on the rim, so half of that plus a little is clear of it.
          inset: Math.max(3, Rp * 0.075),
          veil: (1 - gf) * 0.75,
          strength,
          img: {
            x: (W - gdw) / 2 - gox,
            y: (H - gdh) / 2 - goy,
            w: gdw,
            h: gdh
          }
        });
        if (out) {
          const pOp = ctx.globalCompositeOperation;
          const pA = ctx.globalAlpha;
          ctx.globalCompositeOperation = "source-over";
          ctx.globalAlpha = 1;
          ctx.drawImage(out, gox, goy);
          ctx.globalCompositeOperation = pOp;
          ctx.globalAlpha = pA;
          return;
        }
      }
      const hole = Math.max(0, 1 - Math.pow(Math.max(0, Math.min(1, fill)), 2.5));
      const blurPx = cloud > 2e-3 ? Math.max(1, Rp * hole * 0.14 * cloud) : 0;
      const pad = Math.max(16, blurPx * 2.6);
      const size = Math.ceil(2 * Rp + pad * 2);
      if (maskCv.width !== size || maskCv.height !== size) {
        maskCv.width = size;
        maskCv.height = size;
      }
      const ox = cxp - Rp - pad, oy = cyp - Rp - pad;
      const mx0 = Rp + pad, my0 = Rp + pad;
      const m = maskCtx;
      m.setTransform(1, 0, 0, 1, 0, 0);
      m.clearRect(0, 0, size, size);
      const dir = ccw ? -1 : 1;
      const drawnAng = Math.min(Math.PI * 2, (1 - gapSize) * Math.PI * 2);
      const gapAng = Math.PI * 2 - drawnAng;
      const aNew = gapFrom;
      const aOld = aNew - dir * drawnAng;
      const f = Math.max(0, Math.min(1, fill));
      const STEPS = 72;
      const lead = Math.pow(f, 1.35);
      const depthAt = (u) => {
        const wind = 1 + 1.6 * Math.pow(1 - u, 1.6) * spiral * (1 - lead);
        const thAbs = aOld + dir * u * drawnAng;
        const wob = 1 - lead;
        const rough = 1 + (0.045 * Math.sin(thAbs * 9.1) + 0.028 * Math.sin(thAbs * 15.7)) * wob;
        return Math.max(0, Math.min(1, Math.pow(lead, wind))) * rough;
      };
      m.save();
      m.beginPath();
      m.arc(mx0, my0, Rp, 0, Math.PI * 2);
      m.clip();
      const soft = blurPx > 0.5;
      const OFF = soft ? size + 64 : 0;
      if (soft) {
        m.shadowColor = "rgba(255,255,255,1)";
        m.shadowBlur = blurPx;
        m.shadowOffsetX = OFF;
      }
      const ptAt = (u, r) => {
        const th = aOld + dir * u * drawnAng;
        return { x: mx0 + Math.cos(th) * r - OFF, y: my0 + Math.sin(th) * r };
      };
      const capTo = (from, to, out) => {
        const cx2 = (from.x + to.x) / 2, cy2 = (from.y + to.y) / 2;
        const rad = Math.hypot(to.x - from.x, to.y - from.y) / 2;
        if (rad < 0.5) {
          m.lineTo(to.x, to.y);
          return;
        }
        const a0c = Math.atan2(from.y - cy2, from.x - cx2);
        for (let k = 1; k <= 14; k++) {
          const a = a0c + out * (k / 14) * Math.PI;
          m.lineTo(cx2 + Math.cos(a) * rad, cy2 + Math.sin(a) * rad);
        }
      };
      const innerAt = (u, reach) => Math.max(0, Rp * (1 - depthAt(u)) * (1 - reach));
      const ribbon = (reach, trim) => {
        const u0 = trim, uSpan = Math.max(0.02, 1 - 2 * trim);
        const uAt = (i) => u0 + i / STEPS * uSpan;
        m.beginPath();
        for (let i = 0; i <= STEPS; i++) {
          const q = ptAt(uAt(i), Rp);
          if (i) m.lineTo(q.x, q.y);
          else m.moveTo(q.x, q.y);
        }
        const uEnd = uAt(STEPS), uBeg = uAt(0);
        capTo(ptAt(uEnd, Rp), ptAt(uEnd, innerAt(uEnd, reach)), dir);
        for (let i = STEPS; i >= 0; i--) {
          const u = uAt(i);
          const q = ptAt(u, innerAt(u, reach));
          m.lineTo(q.x, q.y);
        }
        capTo(ptAt(uBeg, innerAt(uBeg, reach)), ptAt(uBeg, Rp), -dir);
        m.closePath();
        m.fill();
      };
      m.fillStyle = "#fff";
      const endBand = Math.min(0.42, 0.38 * hole / Math.max(0.2, drawnAng));
      const FOG_STAMPS = 24;
      let covered = 0;
      for (let j = FOG_STAMPS; j >= 1; j--) {
        const t = j / FOG_STAMPS;
        const target = 1 - t;
        const a = (target - covered) / (1 - covered);
        if (a > 2e-3) {
          m.globalAlpha = Math.min(1, a);
          ribbon(t * 0.38, t * endBand);
          covered = target;
        }
      }
      m.globalAlpha = 1;
      ribbon(0, 0);
      m.shadowBlur = 0;
      m.shadowOffsetX = 0;
      const dissolve = (u, _spanR, strength2, seedI) => {
        const inner = Math.max(0, Rp * (1 - depthAt(u)));
        const midR = (Rp + inner) / 2;
        const th = aOld + dir * u * drawnAng;
        const bx = mx0 + Math.cos(th) * midR, by = my0 + Math.sin(th) * midR;
        const rad = Math.max(6, (Rp - inner) / 2);
        m.globalCompositeOperation = "destination-out";
        for (let j = 0; j < 3; j++) {
          const t = drawnAng * 1.7 + seedI * 2.3 + j * 1.9;
          const jx = bx + Math.cos(t) * rad * 0.2;
          const jy = by + Math.sin(t * 1.3) * rad * 0.2;
          const rr = rad * (0.6 + 0.2 * ((Math.cos(t * 0.8) + 1) / 2));
          const g4 = m.createRadialGradient(jx, jy, 0, jx, jy, rr);
          g4.addColorStop(0, `rgba(0,0,0,${strength2})`);
          g4.addColorStop(0.3, `rgba(0,0,0,${strength2 * 0.72})`);
          g4.addColorStop(0.6, `rgba(0,0,0,${strength2 * 0.38})`);
          g4.addColorStop(0.82, `rgba(0,0,0,${strength2 * 0.14})`);
          g4.addColorStop(1, "rgba(0,0,0,0)");
          m.fillStyle = g4;
          m.beginPath();
          m.arc(jx, jy, rr, 0, Math.PI * 2);
          m.fill();
        }
        m.globalCompositeOperation = "source-over";
      };
      if (cloud > 0.01 && gapSize > 2e-3) {
        const leadThick = Rp * depthAt(1);
        dissolve(1, Math.max(Rp * 0.14, leadThick * 0.8), 0.38, 0);
        dissolve(0, Math.max(Rp * 0.1, Rp * depthAt(0) * 0.8), 0.26, 5);
      }
      m.restore();
      const veil = (1 - f) * 0.75;
      if (veil > 4e-3) {
        m.globalCompositeOperation = "destination-out";
        const vg = m.createRadialGradient(mx0, my0, 0, mx0, my0, Rp);
        vg.addColorStop(0, `rgba(0,0,0,${veil * 0.3})`);
        vg.addColorStop(0.65, `rgba(0,0,0,${veil * 0.55})`);
        vg.addColorStop(1, `rgba(0,0,0,${veil})`);
        m.fillStyle = vg;
        m.beginPath();
        m.arc(mx0, my0, Rp, 0, Math.PI * 2);
        m.fill();
      }
      m.globalCompositeOperation = "source-in";
      m.fillStyle = "rgb(7, 10, 16)";
      m.fillRect(0, 0, size, size);
      m.globalCompositeOperation = "source-atop";
      const sc = Math.max(W / mirror.width, H / mirror.height);
      const dw = mirror.width * sc, dh = mirror.height * sc;
      m.drawImage(mirror, (W - dw) / 2 - ox, (H - dh) / 2 - oy, dw, dh);
      m.globalCompositeOperation = "source-over";
      if (strength > 0.5 && now - lastMaskCheck > 1e3) {
        lastMaskCheck = now;
        try {
          const d = m.getImageData(Math.floor(size / 2), Math.floor(size / 2), 2, 2).data;
          let a = 0;
          for (let i = 3; i < d.length; i += 4) a = Math.max(a, d[i]);
          if (a === 0) {
            window.webkit?.messageHandlers?.portal?.postMessage({
              event: "log",
              text: `mask EMPTY at strength ${strength.toFixed(2)}, fill ${fill.toFixed(2)}, cloud ${cloud.toFixed(2)}`
            });
          }
        } catch (e) {
        }
      }
      ctx.save();
      ctx.globalCompositeOperation = "source-over";
      ctx.globalAlpha = strength;
      ctx.drawImage(maskCv, ox, oy);
      ctx.globalAlpha = 1;
      ctx.restore();
    };
    const spawnBand = (x, y, tx, ty, heat) => {
      const spread = (Math.random() < 0.5 ? -1 : 1) * Math.pow(Math.random(), 0.55) * 1.15;
      const sp = 0.3 + Math.pow(Math.random(), 2.4) * 3.2;
      sparks.push({
        x,
        y,
        vx: (tx + spread * -ty) * sp,
        vy: (ty + spread * tx) * sp,
        life: 1,
        decay: 0.05 + Math.pow(Math.random(), 1.6) * 0.3,
        heat: 0.4 + Math.random() * 0.6 * heat,
        width: 0.2 + Math.random() * 0.4,
        bind: false
      });
    };
    const spawnAt = (x, y, tangentX, tangentY, count, speed, bind = false) => {
      for (let i = 0; i < count; i++) {
        const spread = (Math.random() < 0.5 ? -1 : 1) * Math.pow(Math.random(), 0.5) * 1.5;
        const sp = speed * (0.25 + Math.pow(Math.random(), 2) * 2.4);
        sparks.push({
          x,
          y,
          vx: (tangentX + spread * -tangentY) * sp,
          vy: (tangentY + spread * tangentX) * sp,
          life: 1,
          decay: 0.02 + Math.pow(Math.random(), 1.5) * 0.14,
          heat: Math.random(),
          width: 0.35 + Math.random() * 0.85,
          bind
        });
      }
    };
    const pinch = lm ? pinchL.update(lm, now) : (pinchL.update(null, now), null);
    const pinchRaw = !!(pinch && pinch.isPinched && pinch.center);
    if (pinchRaw) lastPinchAt = now;
    const pinched = pinchRaw || stroke.length > 2 && now - lastPinchAt < PINCH_GRACE_MS;
    const cursorRaw = (() => {
      if (!pinched || !pinch?.center) return null;
      if (parallaxStrength <= 0) return toScreen(pinch.center, lm ? lm[9] : void 0);
      if (latestEyes && lm) {
        const screen = {
          ...MACBOOK_14,
          widthPx: window.innerWidth,
          heightPx: window.innerHeight
        };
        const r = pointingPoint(
          { leftEye: latestEyes.left, rightEye: latestEyes.right, hand: lm },
          screen,
          void 0,
          void 0,
          depths,
          { strength: parallaxStrength }
        );
        if (r) {
          return { x: r.x / window.innerWidth, y: r.y / window.innerHeight };
        }
      }
      return pinch.center;
    })();
    if (cursorRaw) heldCursor = cursorRaw;
    else if (!pinched) heldCursor = null;
    const cursor = cursorRaw ?? heldCursor;
    if (formingLast && !recognisedLatch && stroke.length > 2) breaking = true;
    formingLast = recognisedLatch;
    if (cursor && !breaking) {
      const last = stroke[stroke.length - 1];
      const sm = last ? { x: last.x + (cursor.x - last.x) * 0.45, y: last.y + (cursor.y - last.y) * 0.45 } : cursor;
      stroke.push({ x: sm.x, y: sm.y, rx: sm.x, ry: sm.y, t: now });
      while (stroke.length > 260) stroke.shift();
    } else if (stroke.length) {
      if (!cancelling) cancelEat = Math.max(1, Math.ceil(stroke.length / CANCEL_FRAMES));
      cancelling = true;
      stroke.length = Math.max(0, stroke.length - cancelEat);
      if (stroke.length < 3) {
        stroke = [];
        cancelling = false;
        softFit = null;
        arcStart = null;
        arcSpan = 0;
        if (breaking) {
          breaking = false;
          detector.reset();
          drawnMax = 0;
          ccwLatch = null;
        }
      }
    } else if (cancelling) {
      cancelling = false;
      softFit = null;
      arcStart = null;
      arcSpan = 0;
    }
    let p;
    if (cursor) {
      const raw = detector.push(cursor.x * W / RPX, cursor.y * H / RPX, now);
      const prog = Math.min(1, Math.abs(raw.sweep) / SWEEP_TO_RECOGNISE);
      p = raw.center ? {
        ...raw,
        progress: prog,
        center: { x: raw.center.x * RPX / W, y: raw.center.y * RPX / H }
      } : { ...raw, progress: prog };
    } else {
      detector.reset();
      p = IDLE_PROGRESS;
    }
    lastProgress = p;
    lastPinched = pinched;
    if (stroke.length) {
      const circling = recognisedLatch || p.progress > 0.3 && p.roundness > 0.42;
      const LIFE_BASE = 650, LIFE_REF = 400, LIFE_MIN = 180, LIFE_MAX = 800;
      if (!circling && stroke.length > 3) {
        const k = Math.max(0, stroke.length - 6);
        const a = stroke[k], b = stroke[stroke.length - 1];
        const dt = Math.max(1, b.t - a.t);
        const dpx = Math.hypot((b.rx - a.rx) * W, (b.ry - a.ry) * H);
        const speed = dpx / dt * 1e3;
        const life = Math.max(
          LIFE_MIN,
          Math.min(LIFE_MAX, LIFE_BASE * (LIFE_REF / Math.max(40, speed)))
        );
        const cutoff = now - life;
        let drop = 0;
        while (drop < stroke.length - 2 && stroke[drop].t < cutoff) drop++;
        if (drop) stroke.splice(0, drop);
      }
      const maxPx = circling ? 4e3 : trailPx;
      let run = 0;
      for (let i = stroke.length - 1; i > 0; i--) {
        run += Math.hypot(
          (stroke[i].rx - stroke[i - 1].rx) * W,
          (stroke[i].ry - stroke[i - 1].ry) * H
        );
        if (run > maxPx) {
          stroke.splice(0, i);
          break;
        }
      }
      while (stroke.length > 260) stroke.shift();
    }
    const prevPhase = state.phase;
    state = stepPortal(
      state,
      {
        now,
        pinched,
        // A FULL TURN SINCE INITIATION, not the detector's own threshold.
        // arcSpan is measured from the angle recorded when the circle was
        // recognised, so this is exactly "another 360 degrees from there".
        // Roundness is still required at the moment of opening, so a circle
        // that degenerates after a good start does not get through.
        completed: arcStart !== null && arcSpan >= SWEEP_TO_OPEN && p.roundness >= 0.5 && !!p.center,
        progress: p.progress,
        center: p.center ? { x: mx(p.center.x), y: my(p.center.y) } : null,
        radius: rpxOf(clampRN(p.radius))
      },
      { igniteMs: IGNITE_MS, closeMs: CLOSE_MS, minOpenMs: MIN_OPEN_MS }
    );
    const S = state;
    const portalUp = S.phase === "igniting" || S.phase === "open" || S.phase === "closing";
    if (S.phase === "igniting" && prevPhase !== "igniting") {
      if (drawing) {
        geom = { cx: drawing.cx, cy: drawing.cy, r: drawing.r };
      } else if (p.center) {
        const rn = clampRN(p.radius);
        const ix = rn * RPX / W, iy = rn * RPX / H;
        geom = {
          cx: Math.max(ix, Math.min(1 - ix, p.center.x)),
          cy: Math.max(iy, Math.min(1 - iy, p.center.y)),
          r: p.radius
        };
      }
      attract = { cx: geom.cx, cy: geom.cy, r: rpxOf(clampRN(geom.r)) };
      window.webkit?.messageHandlers?.portal?.postMessage({
        event: "opened",
        x: mx(geom.cx),
        y: my(geom.cy),
        r: rpxOf(clampRN(geom.r)),
        armed: armed?.label ?? null
      });
      comet = [];
      const gr = rpxOf(clampRN(geom.r));
      const rim = 2 * Math.PI * gr;
      const sparkCount = Math.max(260, Math.min(1600, Math.round(rim * 0.93)));
      for (let i = 0; i < sparkCount; i++) {
        const a = Math.random() * Math.PI * 2;
        spawnAt(
          px(geom.cx) + Math.cos(a) * gr,
          py(geom.cy) + Math.sin(a) * gr,
          -Math.sin(a),
          Math.cos(a),
          1,
          7,
          true
        );
      }
    }
    if (S.phase !== "drawing" && drawing) drawing = null;
    if (!pinched) {
      trimmedAtLatch = false;
      announcedAtLatch = false;
      recognisedLatch = false;
      drawnMax = 0;
    }
    if (!pinched && !cancelling) arcStart = null;
    if (!pinched && !cancelling) ccwLatch = null;
    if (!pinched && !cancelling) {
      fitRRef = 0;
      fitJumpAt = 0;
    }
    if (!pinched && !cancelling) softFit = null;
    if (!portalUp) placedOk = false;
    if (!portalUp) {
      settleX = 0;
      settleV = 0;
      arcX = 0;
      arcV = 0;
    }
    if (portalUp) stroke = [];
    if (!portalUp && prevPhase === "closing") {
      detector.reset();
      comet = [];
      attract = null;
      arcStart = null;
      arcSpan = 0;
      drawnMax = 0;
      ccwLatch = null;
      window.webkit?.messageHandlers?.portal?.postMessage({ event: "closed" });
    }
    if (lm && !portalUp) {
      ctx.globalCompositeOperation = "lighter";
      const hub = lm[9];
      for (const t of FINGER_TIPS) {
        ctx.shadowBlur = pinched ? 9 : 6;
        ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
        ctx.fillStyle = `rgba(${SPARK_HOT}, ${pinched ? 1 : 0.8})`;
        ctx.beginPath();
        const q = toScreen(lm[t], hub);
        ctx.arc(mx(q.x), my(q.y), pinched ? 1.7 : 1.4, 0, Math.PI * 2);
        ctx.fill();
      }
      if (pinch?.center) {
        ctx.shadowBlur = 12;
        ctx.shadowColor = `rgba(${CORE}, 1)`;
        ctx.fillStyle = `rgba(${CORE}, 1)`;
        ctx.beginPath();
        const q = toScreen(pinch.center, hub);
        ctx.arc(mx(q.x), my(q.y), 1.9, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.shadowBlur = 0;
      if (pinched && pinch?.center) {
        const q = toScreen(pinch.center, hub);
        const cx0 = mx(q.x);
        const cy0 = my(q.y);
        const k = Math.max(0, Math.min(1, p.progress));
        ctx.strokeStyle = `rgba(${SPARK_MID}, 0.25)`;
        ctx.lineWidth = 2;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.arc(cx0, cy0, 16, 0, Math.PI * 2);
        ctx.stroke();
        if (k > 0.01) {
          ctx.strokeStyle = `rgba(${CORE}, 0.95)`;
          ctx.lineWidth = 2.8;
          ctx.beginPath();
          ctx.arc(cx0, cy0, 16, -Math.PI / 2, -Math.PI / 2 + k * Math.PI * 2);
          ctx.stroke();
        }
      }
    }
    if (!portalUp && pinched && pinch?.center && p.progress < 0.1) {
      attract = null;
      if (Math.random() < 0.25) {
        const a = Math.random() * Math.PI * 2;
        const q = toScreen(pinch.center, lm ? lm[9] : void 0);
        spawnAt(mx(q.x), my(q.y), Math.cos(a), Math.sin(a), 1, 0.7, false);
      }
    }
    if (!portalUp && (pinched || cancelling) && stroke.length > 2) {
      const raw = drawing ?? (p.center ? { cx: p.center.x, cy: p.center.y, r: p.radius } : null);
      if (raw) {
        softFit = softFit ? {
          cx: softFit.cx + (raw.cx - softFit.cx) * 0.12,
          cy: softFit.cy + (raw.cy - softFit.cy) * 0.12,
          r: softFit.r + (raw.r - softFit.r) * 0.12
        } : raw;
      }
      const fitC = drawing ?? softFit;
      const initAt = Math.max(0.35, Math.min(0.95, 1.02 - 1.9 * (fitC ? fitC.r : 0)));
      const bendSpan = Math.max(0.05, (1 - initAt) * 0.7);
      const turned = Math.max(0, Math.min(1, (p.progress - initAt) / bendSpan));
      const round = Math.max(0, Math.min(1, (p.roundness - 0.55) / 0.3));
      const conf = turned * round;
      const k = Math.pow(conf, 0.9);
      if (fitC) {
        const rate = 0.32 + 0.46 * conf;
        const cxp = mx(fitC.cx);
        const cyp = my(fitC.cy);
        const rp = fitC.r * RPX;
        for (const q of stroke) {
          const px0 = mx(q.rx), py0 = my(q.ry);
          const dx = px0 - cxp;
          const dy = py0 - cyp;
          const d = Math.hypot(dx, dy) || 1;
          const tx2 = cxp + dx / d * rp;
          const ty2 = cyp + dy / d * rp;
          const nx = px0 + (tx2 - px0) * rate;
          const ny = py0 + (ty2 - py0) * rate;
          q.rx = nx / W;
          q.ry = ny / H;
        }
      }
      const REVEAL_AT = initAt;
      const reveal = (() => {
        const span = Math.max(0.05, (1 - REVEAL_AT) * 0.85);
        const t = Math.max(0, Math.min(1, (p.progress - REVEAL_AT) / span));
        return t * t * (3 - 2 * t);
      })();
      if (!pinched || p.progress < REVEAL_AT - 0.05) recognisedLatch = false;
      const rNow = fitC ? fitC.r : 0;
      if (fitRRef <= 0 || Math.abs(rNow - fitRRef) / Math.max(rNow, 1e-4) > 0.12) {
        fitRRef = rNow;
        fitJumpAt = arcSpan;
      }
      const fitSettled = arcSpan - fitJumpAt > 0.6;
      if (!fitSettled) recognisedLatch = false;
      else if (p.roundness >= 0.42) recognisedLatch = true;
      else if (p.roundness < 0.34) recognisedLatch = false;
      const recognised = recognisedLatch && pinched && p.progress >= REVEAL_AT;
      const want = !portalUp && fitC && recognised ? reveal : 0;
      mirrorAmt = want > mirrorAmt ? want : mirrorAmt + (want - mirrorAmt) * 0.09;
      if (recognised) {
        if (ccwLatch === null && p.direction) ccwLatch = p.direction === "ccw";
        openCcw = ccwLatch ?? p.sweep < 0;
        const dirS = openCcw ? -1 : 1;
        const headAng = p.endAngle ?? 0;
        if (arcStart === null && fitC && stroke.length > 2) {
          const o = stroke[0];
          arcStart = Math.atan2(my(o.ry) - my(fitC.cy), mx(o.rx) - mx(fitC.cx));
          arcSpan = 0;
        }
        if (arcStart !== null) {
          let raw2 = (headAng - arcStart) * dirS;
          while (raw2 < 0) raw2 += Math.PI * 2;
          const laps = Math.floor(arcSpan / (Math.PI * 2));
          const cand = raw2 + laps * Math.PI * 2;
          arcSpan = Math.max(
            arcSpan,
            cand < arcSpan - Math.PI ? cand + Math.PI * 2 : cand
          );
        }
        drawnMax = Math.max(
          drawnMax,
          arcStart !== null ? Math.min(1, arcSpan / SWEEP_TO_OPEN) : Math.min(1, Math.abs(p.sweep) / SWEEP_TO_OPEN)
        );
        const doneTurns = drawnMax;
        openGap = Math.max(0, 1 - doneTurns);
        lastFill = doneTurns;
        holdOld = arcStart ?? headAng - dirS * doneTurns * Math.PI * 2;
      } else if (mirrorAmt > 6e-3) {
        openGap = Math.min(1, openGap + 1 / CANCEL_FRAMES);
        lastFill = Math.max(0, 1 - openGap);
      }
      if (fitC && !portalUp && mirrorAmt > 6e-3) {
        const cvx = mx(fitC.cx), cvy = my(fitC.cy);
        const Rv = Math.max(4, fitC.r * RPX);
        const drawnNow = (1 - openGap) * Math.PI * 2;
        const leadNow = holdOld + (openCcw ? -1 : 1) * drawnNow;
        openGapFrom = leadNow;
        paintMirror(cvx, cvy, Rv, mirrorAmt, leadNow, openGap, openCcw, 1, lastFill, 1);
      }
      ctx.globalCompositeOperation = "lighter";
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      const rBase = fitC ? fitC.r : 0.05;
      const SP = stroke.length >= 3 ? smoothPath(stroke.map((q) => ({ x: mx(q.rx), y: my(q.ry) })), 1) : null;
      const path = () => {
        ctx.beginPath();
        if (!SP) return;
        ctx.moveTo(SP[0].x, SP[0].y);
        for (let i = 1; i < SP.length; i++) ctx.lineTo(SP[i].x, SP[i].y);
      };
      strokeDrawnThisFrame = !portalUp;
      const hideInside = fitC && mirrorAmt > 0.01;
      if (hideInside) {
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, W, H);
        ctx.arc(mx(fitC.cx), my(fitC.cy), Math.max(2, fitC.r * RPX * 0.99), 0, Math.PI * 2);
        ctx.clip("evenodd");
      }
      if (!portalUp) {
        ctx.shadowBlur = 10 + 22 * k;
        ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
        ctx.strokeStyle = `rgba(${SPARK_MID}, ${0.18 + k * 0.45})`;
        ctx.lineWidth = Math.max(2.5, rBase * RPX * 0.05);
        path();
        ctx.stroke();
        ctx.shadowBlur = 6 + 10 * k;
        ctx.strokeStyle = `rgba(${CORE}, ${0.3 + k * 0.6})`;
        ctx.lineWidth = Math.max(1, rBase * RPX * 0.016);
        path();
        ctx.stroke();
      }
      ctx.shadowBlur = 0;
      if (hideInside) ctx.restore();
      const boundShare = Math.min(0.4, conf * conf * 0.45);
      const bindMaybe = () => Math.random() < boundShare;
      if (fitC && conf > 0.05 && !portalUp) {
        const step = Math.max(4, Math.round(22 - conf * 18));
        for (let i = 0; i < stroke.length; i += step) {
          const q = stroke[i];
          const gap = Math.hypot(mx(q.rx) - mx(q.x), my(q.ry) - my(q.y));
          if (gap < 6) continue;
          spawnAt(
            mx(q.rx),
            my(q.ry),
            (mx(q.x) - mx(q.rx)) / gap,
            (my(q.y) - my(q.ry)) / gap,
            1,
            1.2,
            bindMaybe()
          );
        }
      }
      const head = stroke[stroke.length - 1];
      const prev = stroke[stroke.length - 2] ?? head;
      const hp = SP ? SP[SP.length - 1] : { x: mx(head.rx), y: my(head.ry) };
      const pp = SP && SP.length > 1 ? SP[SP.length - 2] : hp;
      let tx = hp.x - pp.x;
      let ty = hp.y - pp.y;
      const tm = Math.hypot(tx, ty) || 1;
      const n = portalUp ? 0 : Math.round(1 + k * 9);
      for (let i = 0; i < n; i++) {
        spawnAt(
          mx(head.rx),
          my(head.ry),
          tx / tm,
          ty / tm,
          1,
          2.2 + k * 3,
          bindMaybe()
        );
      }
      if (SP && SP.length > 4 && !portalUp) {
        const heat = Math.min(1, p.progress / 0.85);
        const per = 8 + Math.round(30 * heat);
        const halfBand = Math.max(2.5, (fitC ? fitC.r * RPX : 120) * 0.045);
        for (let i = 0; i < per; i++) {
          const j = 1 + Math.floor(Math.random() * (SP.length - 2));
          const a = SP[j - 1], b = SP[j + 1];
          let bx = b.x - a.x, by = b.y - a.y;
          const bl = Math.hypot(bx, by) || 1;
          bx /= bl;
          by /= bl;
          const off = (Math.random() - 0.5) * 2 * halfBand;
          spawnBand(SP[j].x - by * off, SP[j].y + bx * off, bx, by, heat);
        }
      }
      if (fitC && conf > 0.2) attract = { cx: fitC.cx, cy: fitC.cy, r: fitC.r * RPX };
    }
    if (S.phase === "drawing" && p.center && p.startAngle !== null && p.progress > 0.16) {
      if (!drawing || p.progress < LATCH_AT) {
        drawing = { cx: p.center.x, cy: p.center.y, r: p.radius, a0: p.startAngle };
        if (armed && p.center && !announcedAtLatch && p.progress >= LATCH_AT) {
          announcedAtLatch = true;
          window.webkit?.messageHandlers?.portal?.postMessage({
            event: "opening",
            x: mx(p.center.x),
            y: my(p.center.y),
            r: rpxOf(clampRN(p.radius)),
            armed: armed.label
          });
        }
      } else if (!trimmedAtLatch) {
        trimmedAtLatch = true;
        if (stroke.length > 12) stroke.splice(0, Math.floor(stroke.length * 0.35));
      }
    }
    if (portalUp) {
      spin += 0.012;
      const ignite = ignitionAmount(S, now, IGNITE_MS);
      const shut = collapseAmount(S, now, CLOSE_MS);
      const e = ease(ignite);
      const cn = { x: geom.cx, y: geom.cy };
      const rn = clampRN(geom.r) * (1 - easeShut(shut));
      const rpx = rpxOf(rn);
      const vis = e * (1 - shut);
      const age = (now - S.born) / 1e3;
      if (S.phase === "open") attract = { cx: cn.x, cy: cn.y, r: rpx };
      if (rpx >= 2) {
        const cx0 = px(cn.x), cy0 = py(cn.y);
        if (armed && placedOk) {
          ctx.globalCompositeOperation = "destination-out";
          ctx.globalAlpha = 1;
          disc(cn, rn * 0.985);
          ctx.fill();
          ctx.globalCompositeOperation = "source-over";
        } else {
          const shut2 = easeShut(shut);
          const a1 = stepSpring(settleX, settleV, 26, frameDt);
          settleX = a1.x;
          settleV = a1.v;
          const a2 = stepSpring(arcX, arcV, 12, frameDt);
          arcX = a2.x;
          arcV = a2.v;
          const closing = settleX;
          const arcClose = arcX;
          const clearing = settleX * settleX;
          paintMirror(
            cx0,
            cy0,
            rpx,
            1 - shut2,
            openGapFrom,
            openGap * (1 - arcClose),
            openCcw,
            1 - clearing,
            lastFill + (1 - lastFill) * closing,
            1 - closing
          );
        }
        ctx.globalCompositeOperation = "lighter";
        const bloom = ctx.createRadialGradient(cx0, cy0, 0, cx0, cy0, rpx * 1.22);
        bloom.addColorStop(0, "rgba(0,0,0,0)");
        bloom.addColorStop(0.9 / 1.22, "rgba(0,0,0,0)");
        bloom.addColorStop(1 / 1.22, `rgba(${SPARK_MID}, ${0.16 * vis})`);
        bloom.addColorStop(1, "rgba(0,0,0,0)");
        ctx.fillStyle = bloom;
        disc(cn, rn * 1.22);
        ctx.fill();
        if (ignite < 1) {
          ctx.strokeStyle = `rgba(${CORE}, ${(1 - e) * 0.5})`;
          ctx.lineWidth = (1 - e) * 9 + 1;
          arcPath(cn, rn * (1 + e * 0.85), 0, Math.PI * 2);
          ctx.stroke();
        }
        const flicker = 0.82 + Math.sin(now / 55) * 0.1 + Math.random() * 0.08;
        const heat = 1 + (1 - e) * 1.6 + easeShut(shut) * 2.6;
        ctx.lineCap = "round";
        ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
        ctx.shadowBlur = 30 * heat;
        ctx.strokeStyle = `rgba(${SPARK_COLD}, ${0.3 * vis})`;
        ctx.lineWidth = Math.max(4, rpx * 0.1) * heat;
        arcPath(cn, rn, 0, Math.PI * 2, 120, 4);
        ctx.stroke();
        ctx.shadowBlur = 24 * heat;
        ctx.strokeStyle = `rgba(${SPARK_MID}, ${0.5 * vis})`;
        ctx.lineWidth = Math.max(2.5, rpx * 0.045) * heat;
        arcPath(cn, rn, 0, Math.PI * 2, 120, 2.5);
        ctx.stroke();
        ctx.shadowBlur = 18 * heat;
        ctx.strokeStyle = `rgba(${SPARK_HOT}, ${0.7 * vis})`;
        ctx.lineWidth = Math.max(1.6, rpx * 0.018) * heat;
        arcPath(cn, rn, 0, Math.PI * 2, 120, 1.2);
        ctx.stroke();
        ctx.shadowBlur = 10;
        ctx.strokeStyle = `rgba(${CORE}, ${Math.min(1, flicker * vis * 0.8)})`;
        ctx.lineWidth = Math.max(1, rpx * 7e-3);
        arcPath(cn, rn, 0, Math.PI * 2, 120);
        ctx.stroke();
        ctx.shadowBlur = 0;
        const emit = S.phase === "igniting" ? 90 : S.phase === "closing" ? 55 : age < 0.6 ? 46 : 26;
        const inward = S.phase === "closing" ? -1 : 1;
        for (let i = 0; i < emit; i++) {
          const a = Math.random() * Math.PI * 2 + spin;
          spawnAt(
            cx0 + Math.cos(a) * rpx,
            cy0 + Math.sin(a) * rpx,
            -Math.sin(a) * inward,
            Math.cos(a) * inward,
            1,
            S.phase === "igniting" ? 6.5 : 4.2,
            true
          );
        }
      }
    }
    ctx.globalCompositeOperation = "lighter";
    const drawnFit = drawing ?? softFit;
    const holeUp = portalUp || !!drawnFit && mirrorAmt > 0.01;
    const holeCx = portalUp ? px(geom.cx) : drawnFit ? mx(drawnFit.cx) : 0;
    const holeCy = portalUp ? py(geom.cy) : drawnFit ? my(drawnFit.cy) : 0;
    const holeR = (portalUp ? rpxOf(clampRN(geom.r)) : drawnFit ? drawnFit.r * RPX : 0) * 0.97;
    const insidePortal = (x, y) => (x - holeCx) ** 2 + (y - holeCy) ** 2 < holeR * holeR;
    let sparksInHole = 0;
    const alive = [];
    for (const sp of sparks) {
      const c = Math.cos(0.035), sn = Math.sin(0.035);
      const nvx = sp.vx * c - sp.vy * sn;
      const nvy = sp.vx * sn + sp.vy * c;
      sp.vx = nvx * 0.975;
      sp.vy = nvy * 0.975 + 0.055;
      if (sp.bind && attract) {
        const Cx = mx(attract.cx), Cy = my(attract.cy), R = attract.r || 1;
        const dx = sp.x - Cx, dy = sp.y - Cy;
        let dl = Math.hypot(dx, dy);
        let nx, ny;
        if (dl < 0.5) {
          const a = Math.random() * Math.PI * 2;
          nx = Math.cos(a);
          ny = Math.sin(a);
          dl = 0.5;
        } else {
          nx = dx / dl;
          ny = dy / dl;
        }
        if (dl < R) {
          sp.vx += nx * (R - dl) * 0.06;
          sp.vy += ny * (R - dl) * 0.06;
        } else {
          sp.vx += nx * 0.22 * sp.life;
          sp.vy += ny * 0.22 * sp.life;
        }
        const tang = 1.9 * sp.life;
        sp.vx += -ny * tang;
        sp.vy += nx * tang;
        sp.vx *= 0.992;
        sp.vy *= 0.992;
      }
      sp.x += sp.vx;
      sp.y += sp.vy;
      sp.life -= sp.decay;
      sp.life -= 4e-3;
      if (sp.life <= 0) continue;
      alive.push(sp);
      if (holeUp && insidePortal(sp.x, sp.y)) {
        sparksInHole++;
        continue;
      }
      const speed = Math.hypot(sp.vx, sp.vy) || 1;
      const len = Math.max(5, Math.min(20, speed * 2.4));
      const h = sp.heat * sp.life;
      const col = h > 0.62 ? CORE : h > 0.3 ? SPARK_HOT : h > 0.14 ? SPARK_MID : SPARK_COLD;
      ctx.strokeStyle = `rgba(${col}, ${Math.min(1, sp.life * 1.5)})`;
      ctx.lineWidth = sp.width * (0.25 + sp.life * 0.6);
      ctx.lineCap = "butt";
      ctx.beginPath();
      ctx.moveTo(sp.x, sp.y);
      ctx.lineTo(sp.x - sp.vx / speed * len, sp.y - sp.vy / speed * len);
      ctx.stroke();
    }
    if (pinched && p.progress > 0.75 && now - lastInsideCheck > 700) {
      lastInsideCheck = now;
      window.webkit?.messageHandlers?.portal?.postMessage({
        event: "log",
        text: `phase=${S.phase} progress=${p.progress.toFixed(2)} sweep=${Math.abs(p.sweep).toFixed(2)}/5.40 round=${p.roundness.toFixed(2)}/0.55 r=${p.radius.toFixed(3)} sparksInHole=${sparksInHole}`
      });
    }
    sparks = alive.length > 1400 ? alive.slice(-1400) : alive;
  }
  requestAnimationFrame(frame);
})();
