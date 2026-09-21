import type { Landmark } from "./types";

/**
 * Where you are actually pointing, from your own point of view.
 *
 * THE PROBLEM. Mapping a fingertip's camera coordinates straight onto the
 * screen is camera-relative: the cursor lands where the CAMERA sees your
 * finger, and the camera is a lens in the top bezel while you are sitting a
 * foot and a half back. The two viewpoints disagree by parallax, so the
 * cursor sits somewhere near your finger but never AT it, and no amount of
 * smoothing or gain fixes that because it is a geometry error rather than a
 * tracking one. Caleb's words: the line from eye to fingertip to the point
 * on screen should be straight, so it feels like drawing at the tip of your
 * finger.
 *
 * THE FIX. Put the eye and the fingertip in 3D, cast a ray from one through
 * the other, and intersect it with the plane of the screen. That is exactly
 * the straight line he described, and everything here is in service of the
 * two depths it needs.
 *
 * HOW DEPTH COMES OUT OF A 2D CAMERA. A pinhole camera gives apparent size
 * in inverse proportion to distance, so a length you already know the real
 * size of is a rangefinder. Two are used: the distance between the pupils,
 * which varies little between adults, and the palm, wrist to middle
 * knuckle. Both are estimates and both are stated as such; getting a
 * person's IPD wrong by 5% moves the cursor by about 5% of the parallax
 * correction, not of the screen, so the failure is a small drift rather
 * than a wrong answer.
 *
 * WHAT THIS IS NOT. It is not gaze tracking. Where the eyes are LOOKING does
 * not matter here, only where they ARE, because the ray is anchored at the
 * eye and aimed by the finger. That is worth being clear about, because eye
 * tracking is the expensive, calibration-hungry, drift-prone thing this
 * deliberately avoids while sounding like it.
 */

/** Camera intrinsics. Only the field of view matters for this. */
export interface CameraModel {
  /** Horizontal field of view in degrees. A Mac's built-in camera is ~54. */
  hfovDeg: number;
  /** Image width divided by image height. */
  aspect: number;
}

/**
 * The screen, in millimetres and pixels, plus where the camera sits on it.
 *
 * The origin for `cameraXMm`/`cameraYMm` is the TOP LEFT of the display, so
 * a centred camera in the bezel above the panel is
 * `{ x: widthMm / 2, y: -6 }`.
 */
export interface ScreenModel {
  widthMm: number;
  heightMm: number;
  widthPx: number;
  heightPx: number;
  cameraXMm: number;
  cameraYMm: number;
}

/** Real-world sizes used as rangefinders. Millimetres. */
/**
 * How far in front of the face the hand must be before the ray is trusted.
 *
 * THE BUG THIS FIXES, 2026-09-21. Caleb: "The portal keeps randomly
 * starting on random parts of the screen that totally have nothing to do
 * with where my pinch is."
 *
 * The ray crosses the screen at t = eyeZ / (eyeZ - fingerZ), so as the hand
 * approaches the plane of the face that denominator goes to zero and t
 * explodes. With the eye at 600mm and the hand at 590mm, t is 60: a ten
 * millimetre movement of the fingertip becomes six hundred millimetres on
 * screen, twice the width of a 14 inch display. The maths is right and the
 * answer is useless, which is the same shape as the circle fit that put a
 * portal bigger than the screen on a small flick.
 *
 * Both depths are estimated from apparent size and both are noisy, so the
 * hand's estimate wanders through that zone on its own. A guard against
 * dividing by zero was not enough; the numbers were finite and absurd.
 */
export const MIN_SEPARATION_MM = 120;

/**
 * Largest extrapolation the ray is allowed. Past this the geometry is not
 * trustworthy enough to place a portal, and the camera-relative point,
 * which is wrong by a known parallax, beats an answer that is wrong by an
 * unknown multiple.
 */
export const MAX_RAY_GAIN = 8;

export interface Anthropometrics {
  /** Pupil to pupil. Adult mean is about 63mm, and the spread is small. */
  ipdMm: number;
  /** Wrist to middle-finger knuckle. About 97mm for an adult. */
  palmMm: number;
}

export const DEFAULT_ANTHRO: Anthropometrics = { ipdMm: 63, palmMm: 97 };

/** A 14-inch MacBook Pro: 3024x1964 at 254ppi, camera centred in the notch. */
export const MACBOOK_14: ScreenModel = {
  widthMm: 302.4,
  heightMm: 196.4,
  widthPx: 1512,
  heightPx: 982,
  cameraXMm: 151.2,
  cameraYMm: -6,
};

export const MAC_CAMERA: CameraModel = { hfovDeg: 54, aspect: 16 / 9 };

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

/**
 * Focal length in units of image widths.
 *
 * Everything else works in normalized image coordinates, so carrying a focal
 * length in pixels would mean threading a resolution through that nothing
 * else needs.
 */
export function focalNormalized(cam: CameraModel): number {
  return 0.5 / Math.tan((cam.hfovDeg * Math.PI) / 180 / 2);
}

/**
 * Distance to something of known real size from how large it looks.
 *
 * `apparent` is measured in normalized image widths, the same units
 * landmarks arrive in. Returns millimetres, or Infinity for a degenerate
 * measurement, which a caller must treat as "no reading" rather than "very
 * far away".
 */
export function depthFromApparentSize(
  realMm: number,
  apparent: number,
  cam: CameraModel,
): number {
  if (!(apparent > 1e-6)) return Infinity;
  return (realMm * focalNormalized(cam)) / apparent;
}

/**
 * A normalized image point at a known depth, as millimetres in camera space.
 *
 * Camera at the origin looking at the user, +x to the user's left as the
 * image sees it, +y up, +z toward the user. Image y runs downward, hence the
 * flip.
 */
export function cameraSpace(
  u: number,
  v: number,
  depthMm: number,
  cam: CameraModel,
): Vec3 {
  const f = focalNormalized(cam);
  return {
    x: ((u - 0.5) / f) * depthMm,
    y: (-(v - 0.5) / cam.aspect / f) * depthMm,
    z: depthMm,
  };
}

/**
 * Intersect the eye-through-finger ray with the plane of the screen.
 *
 * Returns pixels from the screen's top left, which may legitimately fall
 * outside the screen when someone points past it.
 */
export function rayToScreen(eye: Vec3, finger: Vec3, screen: ScreenModel): { x: number; y: number } {
  // The screen is the z = 0 plane; the camera sits on it. The finger must be
  // nearer the screen than the eye or the ray never reaches it, which is
  // also true of a real arm.
  const dz = eye.z - finger.z;
  // Not just a guard against zero. See MIN_SEPARATION_MM: a hand a
  // centimetre in front of the face produces a finite, enormous t, and the
  // portal lands somewhere unrelated to the finger.
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
    screen,
  );
}

/** Camera-space millimetres to pixels from the screen's top left. */
export function mmToPixels(xMm: number, yMm: number, screen: ScreenModel): { x: number; y: number } {
  return {
    x: ((xMm + screen.cameraXMm) / screen.widthMm) * screen.widthPx,
    y: ((-yMm - screen.cameraYMm) / screen.heightMm) * screen.heightPx,
  };
}

export interface PointingInput {
  /** Both pupils, normalized image coordinates. */
  leftEye: { x: number; y: number };
  rightEye: { x: number; y: number };
  /** 21 hand landmarks in MediaPipe order and convention. */
  hand: Landmark[];
  /** Which landmark is being pointed with. 8 is the index tip. */
  tip?: number;
}

/**
 * The whole pipeline: two pupils and a hand in, one screen point out.
 *
 * Returns null when the measurement cannot support an answer, rather than a
 * plausible guess. A cursor that is confidently wrong is worse than one that
 * briefly does not move, because the person corrects for the first and
 * cannot.
 */
export function pointingPoint(
  input: PointingInput,
  screen: ScreenModel = MACBOOK_14,
  cam: CameraModel = MAC_CAMERA,
  anthro: Anthropometrics = DEFAULT_ANTHRO,
): { x: number; y: number; eyeMm: number; fingerMm: number } | null {
  const { leftEye, rightEye, hand } = input;
  if (!hand || hand.length < 21) return null;

  const ipdApparent = Math.hypot(rightEye.x - leftEye.x, (rightEye.y - leftEye.y) / cam.aspect);
  const eyeDepth = depthFromApparentSize(anthro.ipdMm, ipdApparent, cam);
  if (!isFinite(eyeDepth)) return null;

  // Wrist to middle-finger MCP. Chosen over a fingertip span because it
  // barely changes as the hand opens, closes or pinches, and a rangefinder
  // that moves with the gesture it is measuring is no rangefinder.
  const palmApparent = Math.hypot(hand[9].x - hand[0].x, (hand[9].y - hand[0].y) / cam.aspect);
  const fingerDepth = depthFromApparentSize(anthro.palmMm, palmApparent, cam);
  if (!isFinite(fingerDepth)) return null;

  const eyeMid = { x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2 };
  const eye = cameraSpace(eyeMid.x, eyeMid.y, eyeDepth, cam);
  const t = hand[input.tip ?? 8];
  const finger = cameraSpace(t.x, t.y, fingerDepth, cam);

  const p = rayToScreen(eye, finger, screen);
  return { x: p.x, y: p.y, eyeMm: eyeDepth, fingerMm: fingerDepth };
}
