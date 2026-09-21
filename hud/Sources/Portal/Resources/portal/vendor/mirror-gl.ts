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

// The inner edge, as a fraction of the radius consumed, at position u along
// the arc. u 0 is where the line joined the circle, u 1 is the leading edge.
//
// wind makes it a spiral: shallow where the circle began, deepest at the
// leading edge. It relaxes as the fill completes, so the two ends converge
// and what is left at the end is a disc in the middle rather than a crescent
// lying against the rim.
float depthAt(float u) {
  float wind = 1.0 + 1.6 * pow(max(0.0, 1.0 - u), 1.6) * uSpiral * (1.0 - uLead);
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

  float depth = depthAt(clamp(u, 0.0, 1.0));
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
  inner *= 1.0 + 0.09 * lobes * (1.0 - uLead);
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
  float band = max(1.0, min(uR * uFog, inner));

  // Radial: transparent at inner - band, solid by inner. The soft side faces
  // the CENTRE, so the fog is pushed ahead of the edge rather than straddling
  // it.
  float fRad = smoothstep(inner - band, inner, r);

  // Angular: the same band, measured in arc length and converted to u so the
  // fade reads the same distance in both directions.
  float bandU = band / max(uR * span, 1.0);
  float fAng = smoothstep(0.0, bandU, u) * smoothstep(0.0, bandU, 1.0 - u);
  // Past the leading edge is the undrawn wedge. Nothing there.
  fAng *= step(u, 1.0 + bandU);

  // ONCE THE CIRCLE IS CLOSED THERE ARE NO ENDS TO FADE. At a full turn the
  // two ends of the arc are the same place, so fading both of them cut a
  // wedge of nothing from the centre out to the rim along the seam, which
  // is the white slice left in an otherwise finished portal. Blended out as
  // the span reaches a turn, so the ends stop existing rather than meeting.
  fAng = mix(fAng, 1.0, smoothstep(TAU - 0.35, TAU - 0.02, uASpan));

  // A pixel of softness at the rim, so it is not a jagged cut.
  float fRim = smoothstep(uR, uR - 1.5, r);

  // Fades toward the rim while the circle is still filling.
  float veil = 1.0 - uVeil * mix(0.3, 1.0, clamp(r / uR, 0.0, 1.0));

  float a = fRad * fAng * fRim * veil * uStrength;
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
