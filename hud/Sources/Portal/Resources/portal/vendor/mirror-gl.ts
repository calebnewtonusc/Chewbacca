/**
 * The other side, drawn as a field instead of as shapes.
 *
 * WHY THIS EXISTS. The mask for the mirror used to be built in Canvas 2D out
 * of opaque polygons, and every visual fault reported over a long evening was
 * the same fault: a smooth, continuous field approximated with discrete hard
 * edged geometry.
 *
 *   "it just looks like a pie"                  a radial cut with no falloff
 *   "cloudy, not outline with sparks"           a cap is a shape, not weather
 *   "the white blobs are back"                  erasing to fake softness
 *   "a bubble forming and then popping"         a stamp's edge is a skin
 *   "puzzle pieces clicking"                    the stamp ladder's rungs
 *   "should go into each other seamlessly"      two falloffs, two mechanisms
 *
 * Each was answered with more geometry: stamped ribbons, semicircular end
 * caps, a shape drawn off canvas so only its blurred shadow landed, erased
 * blobs at the ends. Roughly 150 lines, all of it approximating a gradient.
 *
 * A fragment shader computes the field directly. For a pixel at radius r and
 * angle a, the alpha is the product of a radial falloff and an angular one.
 * Seamlessness is not arranged, it is what multiplication does: where the two
 * fades meet, the result is the product of two smooth functions, which is
 * smooth. There is no ladder to band, no stamp edge to read as a skin, and no
 * corner where one mechanism hands over to another.
 *
 * WHAT CAME FREE. The spiral, because `inner` may be any function of the
 * angle. The end fade, because it is one more smoothstep. Exact arrival at
 * zero, because the band is a fraction of the hole and the hole reaches zero.
 *
 * WHAT IS NOT HERE ON PURPOSE. The ring, the sparks and the drawn line are
 * still Canvas 2D above this. They were never the problem: they are strokes
 * and points, which is what a 2D canvas is good at.
 */

export interface MirrorFrame {
  /** Square canvas edge, px. */
  size: number;
  /** Portal centre within that canvas, px. */
  cx: number;
  cy: number;
  /** Rim radius, px. */
  R: number;
  /** Angle the drawn arc starts at, radians, and how far it spans. */
  aStart: number;
  aSpan: number;
  /** +1 clockwise on screen, -1 counter clockwise. */
  dir: number;
  /** How far the fill has got, 0 to 1, already raised to its curve. */
  lead: number;
  /** How much spiral is left in the inner edge, 0 to 1. */
  spiral: number;
  /** Fog band depth, as a fraction of the hole that is left. */
  fog: number;
  /** Overall rim fade, 0 none. */
  veil: number;
  /** Overall opacity. */
  strength: number;
  /** Where the full bleed image sits in canvas px. */
  img: { x: number; y: number; w: number; h: number };
}

const VERT = `#version 300 es
in vec2 aPos;
out vec2 vPix;
uniform vec2 uSize;
void main() {
  vPix = (aPos * 0.5 + 0.5) * uSize;
  gl_Position = vec4(aPos, 0.0, 1.0);
}`;

const FRAG = `#version 300 es
precision highp float;
in vec2 vPix;
out vec4 outColor;

uniform vec2  uC;
uniform float uR;
uniform float uAStart, uASpan, uDir;
uniform float uLead, uSpiral, uFog, uVeil, uStrength;
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
  float reach = uR * (0.06 + 0.70 * uLead * uLead);
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
  float outAng = rel > span ? min(rel - span, TAU - rel) : 0.0;
  float dAng = max(outAng * uR - reachHere, 0.0) * 0.55;
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

  // A pixel of softness at the rim, so it is not a jagged cut.
  float fRim = smoothstep(uR, uR - 1.5, r);

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

function compile(gl: WebGL2RenderingContext, type: number, src: string) {
  const sh = gl.createShader(type)!;
  gl.shaderSource(sh, src);
  gl.compileShader(sh);
  if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(sh) || "shader failed");
  }
  return sh;
}

export class MirrorGL {
  readonly canvas: HTMLCanvasElement;
  private gl: WebGL2RenderingContext | null = null;
  private prog: WebGLProgram | null = null;
  private tex: WebGLTexture | null = null;
  private loc: Record<string, WebGLUniformLocation | null> = {};
  /** Set once the image is uploaded. */
  private uploaded = false;
  /** Non-null once something has gone wrong; the caller falls back. */
  readonly error: string | null = null;

  constructor() {
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
        preserveDrawingBuffer: true,
      });
      if (!gl) throw new Error("no webgl2");
      this.gl = gl;

      const prog = gl.createProgram()!;
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
        gl.STATIC_DRAW,
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
        "uImg",
        "uTex",
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
      (this as { error: string | null }).error = String(e);
      this.gl = null;
    }
  }

  /** Upload the other side. Once; the image never changes. */
  setImage(img: TexImageSource): void {
    const gl = this.gl;
    if (!gl || !this.tex) return;
    try {
      gl.bindTexture(gl.TEXTURE_2D, this.tex);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, 1);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
      this.uploaded = true;
    } catch (e) {
      // A local file loaded into an <img> can taint the canvas, and WebGL
      // refuses a tainted upload with a SecurityError. Recorded rather than
      // thrown, because throwing here aborted the image's whole onload
      // handler and took several unrelated log lines with it, which is how
      // this looked like "the shader silently did nothing".
      (this as { error: string | null }).error = "texture upload: " + String(e);
      this.uploaded = false;
    }
  }

  get ready(): boolean {
    return !!this.gl && this.uploaded;
  }

  /** Draw one frame. Returns the canvas to composite, or null. */
  render(f: MirrorFrame): HTMLCanvasElement | null {
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

    // The vertex stage builds pixel coordinates with y up, matching the
    // flipped texture upload, so the image lands the same way round it does
    // in the 2D path.
    gl.uniform2f(this.loc.uSize, f.size, f.size);
    gl.uniform2f(this.loc.uC, f.cx, f.size - f.cy);
    gl.uniform1f(this.loc.uR, f.R);
    // Screen y grows downward and the shader's grows upward, so an angle
    // measured on screen is negated here, and so is the direction.
    gl.uniform1f(this.loc.uAStart, -f.aStart);
    gl.uniform1f(this.loc.uASpan, f.aSpan);
    gl.uniform1f(this.loc.uDir, -f.dir);
    gl.uniform1f(this.loc.uLead, f.lead);
    gl.uniform1f(this.loc.uSpiral, f.spiral);
    gl.uniform1f(this.loc.uFog, f.fog);
    gl.uniform1f(this.loc.uVeil, f.veil);
    gl.uniform1f(this.loc.uStrength, f.strength);
    gl.uniform4f(
      this.loc.uImg,
      f.img.x,
      f.size - f.img.y - f.img.h,
      f.img.w,
      f.img.h,
    );

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.tex);
    gl.uniform1i(this.loc.uTex, 0);

    gl.drawArrays(gl.TRIANGLES, 0, 3);
    return this.canvas;
  }
}
