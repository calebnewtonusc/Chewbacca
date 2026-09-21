/**
 * The portal's state machine, as a pure function.
 *
 * WHY THIS IS NOT IN THE COMPONENT. It was, inside a requestAnimationFrame
 * closure over half a dozen refs, and it shipped two bugs in twenty minutes
 * that a five line test would have caught:
 *
 *   1. The portal opened for exactly one frame. The pinch that DREW the
 *      circle is still held when the circle completes, so the next frame saw
 *      "open, and a pinch" and closed it.
 *   2. It could not be reopened after closing.
 *
 * Neither was visible by reading, and neither was reachable by a test,
 * because the logic only existed inside an animation frame that needs a
 * camera and a hand. A state machine you cannot step by hand is one you debug
 * by waving at a laptop at three in the morning.
 *
 * So: no canvas, no refs, no time source of its own. Feed it frames, assert
 * on what comes out.
 */

export type PortalPhase = "idle" | "drawing" | "igniting" | "open" | "closing";

export interface PortalState {
  phase: PortalPhase;
  /** Whether a pinch is allowed to close the portal right now. */
  armed: boolean;
  /** Timestamp the current portal opened. */
  born: number;
  /** Timestamp the collapse began. */
  closeAt: number;
  x: number;
  y: number;
  r: number;
}

export interface PortalInput {
  now: number;
  /** Is a pinch currently held. */
  pinched: boolean;
  /** Did the circle gesture complete on this frame. */
  completed: boolean;
  /** Progress of the in-flight circle, 0 to 1. */
  progress: number;
  /** Where and how big, in pixels, when `completed`. */
  center?: { x: number; y: number } | null;
  radius?: number;
}

export interface PortalTiming {
  igniteMs?: number;
  closeMs?: number;
  /** A portal cannot be closed within this long of opening. */
  minOpenMs?: number;
}

export function initialPortalState(): PortalState {
  return { phase: "idle", armed: true, born: 0, closeAt: 0, x: 0, y: 0, r: 0 };
}

export function stepPortal(
  s: PortalState,
  i: PortalInput,
  t: PortalTiming = {},
): PortalState {
  const igniteMs = t.igniteMs ?? 520;
  const closeMs = t.closeMs ?? 380;
  const minOpenMs = t.minOpenMs ?? 600;
  const n = { ...s };

  // ── Timed transitions first, so a phase that expired this frame is already
  // gone before anything below reads it.
  if (n.phase === "igniting" && i.now - n.born >= igniteMs) n.phase = "open";
  if (n.phase === "closing" && i.now - n.closeAt >= closeMs) n.phase = "idle";

  // ── Releasing the pinch is what re-arms the close. This must run BEFORE
  // the close check, otherwise releasing and re-pinching inside one frame
  // budget cannot close, and it must run every frame regardless of phase, or
  // a release during the collapse is never observed and the portal can never
  // be closed again.
  if (!i.pinched) n.armed = true;

  // ── Opening. ONLY WHEN NOTHING IS UP.
  //
  // This used to accept a completion in any phase, and every completion
  // resets `born` and clears `armed`. So a second circle finishing while a
  // portal was already open pushed the close out of reach: the minimum open
  // time restarted and the close disarmed, every time.
  //
  // It stayed hidden while the detector was fragile. A tracking glitch used
  // to wipe the accumulated sweep, so an accidental second completion was
  // rare. Making large circles survive glitches made the detector persistent
  // enough to complete again while a portal was still up, and "Bro I can't
  // close portals anymore" followed immediately.
  //
  // Refusing is also the right answer on its own terms. A portal is closed
  // before the next one is drawn; there is no state here for two.
  const alreadyUp =
    n.phase === "igniting" || n.phase === "open" || n.phase === "closing";
  if (i.completed && i.center && !alreadyUp) {
    n.phase = "igniting";
    n.born = i.now;
    n.closeAt = 0;
    n.x = i.center.x;
    n.y = i.center.y;
    n.r = i.radius ?? 0;
    // The drawing pinch is still held. Without this the next frame closes it.
    n.armed = false;
    return n;
  }

  // ── Closing.
  if (
    (n.phase === "open" || n.phase === "igniting") &&
    i.pinched &&
    n.armed &&
    i.now - n.born > minOpenMs
  ) {
    n.phase = "closing";
    n.closeAt = i.now;
    n.armed = false;
    return n;
  }

  // ── Drawing, which is only a label for the UI.
  const portalUp =
    n.phase === "igniting" || n.phase === "open" || n.phase === "closing";
  if (!portalUp) {
    n.phase = i.pinched && i.progress > 0.02 ? "drawing" : "idle";
  }

  return n;
}

/** 0 to 1 across the ignition. 1 when not igniting. */
export function ignitionAmount(s: PortalState, now: number, igniteMs = 520) {
  if (s.phase !== "igniting") return 1;
  return Math.min(1, (now - s.born) / igniteMs);
}

/** 0 to 1 across the collapse. 0 when not closing. */
export function collapseAmount(s: PortalState, now: number, closeMs = 380) {
  if (s.phase !== "closing") return 0;
  return Math.min(1, (now - s.closeAt) / closeMs);
}
