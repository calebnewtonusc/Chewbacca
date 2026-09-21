export interface PinchResult {
  state: "idle" | "pinching" | "holding" | "dragging" | "released";
  changed: boolean;
  lost?: boolean;
  center: { x: number; y: number; z?: number } | null;
  delta: { x: number; y: number; z: number };
  ratio: number;
  isPinched: boolean;
  heldMs: number;
  scale: number;
}

export interface PinchDetectorOptions {
  enterRatio?: number;
  exitRatio?: number;
  holdMs?: number;
  dragDeadzone?: number;
}

function dist2D(a: { x: number; y: number }, b: { x: number; y: number }) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function midpoint(
  a: { x: number; y: number; z?: number },
  b: { x: number; y: number; z?: number },
) {
  return {
    x: (a.x + b.x) / 2,
    y: (a.y + b.y) / 2,
    z: ((a.z ?? 0) + (b.z ?? 0)) / 2,
  };
}

export class PinchDetector {
  enterRatio: number;
  exitRatio: number;
  holdMs: number;
  dragDeadzone: number;
  alpha: number;
  state: PinchResult["state"] = "idle";
  startedAt = 0;
  center: { x: number; y: number; z?: number } | null = null;
  startCenter: { x: number; y: number; z?: number } | null = null;
  lastCenter: { x: number; y: number; z?: number } | null = null;
  smoothedCenter: { x: number; y: number; z?: number } | null = null;

  constructor(opts: PinchDetectorOptions = {}) {
    this.enterRatio = opts.enterRatio ?? 0.38;
    this.exitRatio = opts.exitRatio ?? 0.52;
    this.holdMs = opts.holdMs ?? 220;
    this.dragDeadzone = opts.dragDeadzone ?? 0.012;
    this.alpha = 0.4;
  }

  private handScale(lm: { x: number; y: number }[]) {
    const palmH = dist2D(lm[0], lm[9]);
    const palmW = dist2D(lm[5], lm[17]);
    return Math.max((palmH + palmW) * 0.5, 0.0001);
  }

  update(
    landmarks: { x: number; y: number; z?: number }[] | null,
    now = performance.now(),
  ): PinchResult {
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
        scale: 1,
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
      x:
        this.smoothedCenter.x +
        this.alpha * (rawCenter.x - this.smoothedCenter.x),
      y:
        this.smoothedCenter.y +
        this.alpha * (rawCenter.y - this.smoothedCenter.y),
      z:
        (this.smoothedCenter.z ?? 0) +
        this.alpha * ((rawCenter.z ?? 0) - (this.smoothedCenter.z ?? 0)),
    };
    this.center = this.smoothedCenter;

    const wasPinched = ["pinching", "holding", "dragging"].includes(this.state);
    const isPinched = wasPinched
      ? ratio < this.exitRatio
      : ratio < this.enterRatio;
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
      this.state =
        move > this.dragDeadzone
          ? "dragging"
          : heldMs >= this.holdMs
            ? "holding"
            : "pinching";
    } else if (this.state === "released") {
      this.state = "idle";
      changed = true;
    }

    const delta =
      this.lastCenter && this.center
        ? {
            x: this.center.x - this.lastCenter.x,
            y: this.center.y - this.lastCenter.y,
            z: (this.center.z ?? 0) - (this.lastCenter.z ?? 0),
          }
        : { x: 0, y: 0, z: 0 };

    this.lastCenter = this.center ? { ...this.center } : null;

    return {
      state: this.state,
      changed,
      center: this.center,
      delta,
      ratio,
      isPinched,
      heldMs: wasPinched ? now - this.startedAt : 0,
      scale,
    };
  }
}
