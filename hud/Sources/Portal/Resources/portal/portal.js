(() => {
  var __defProp = Object.defineProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

  // vendor/circle.ts
  var EMPTY = {
    progress: 0,
    sweep: 0,
    center: null,
    radius: 0,
    completed: false,
    direction: null,
    startAngle: null,
    endAngle: null
  };
  var CircleGestureDetector = class {
    constructor(options = {}) {
      __publicField(this, "trail", []);
      __publicField(this, "smooth", null);
      __publicField(this, "sweep", 0);
      __publicField(this, "lastT", 0);
      __publicField(this, "o");
      this.o = {
        sweepThreshold: options.sweepThreshold ?? 4.6,
        trailLength: options.trailLength ?? 240,
        minSegment: options.minSegment ?? 4e-3,
        maxTurn: options.maxTurn ?? Math.PI / 2.2,
        staleMs: options.staleMs ?? 400,
        smoothing: options.smoothing ?? 0.45
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
          this.sweep = 0;
        } else {
          this.sweep += turn;
        }
      }
      const done = Math.abs(this.sweep) >= this.o.sweepThreshold;
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
      const first = this.trail[0];
      const last = this.trail[this.trail.length - 1];
      return {
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
    fit() {
      const m = this.centroid();
      const n = this.trail.length;
      let Sxx = 0, Sxy = 0, Syy = 0, Sxz = 0, Syz = 0, Sz = 0, Sx = 0, Sy = 0;
      for (const q of this.trail) {
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
      let x = 0;
      let y = 0;
      for (const p of this.trail) {
        x += p.x;
        y += p.y;
      }
      return { x: x / this.trail.length, y: y / this.trail.length };
    }
  };
  function mirrorAngle(theta) {
    return Math.PI - theta;
  }

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
    if (i.completed && i.center) {
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
  var IGNITE_MS = 520;
  var CLOSE_MS = 380;
  var MIN_OPEN_MS = 600;
  var ease = (t) => 1 - Math.pow(1 - t, 3);
  var IDLE_PROGRESS = {
    progress: 0,
    sweep: 0,
    center: null,
    radius: 0,
    completed: false,
    direction: null,
    startAngle: null,
    endAngle: null
  };
  var canvas = document.getElementById("c");
  var ctx = canvas.getContext("2d");
  var detector = new CircleGestureDetector();
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
  var sizeScale = 0.45;
  var reachScale = 1;
  var handScale = 0.45;
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
  window.chewbaccaArm = (label) => {
    armed = label ? { label } : null;
  };
  window.chewbaccaHands = (pts, eyes) => {
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
    const W = window.innerWidth;
    const H = window.innerHeight;
    ctx.globalCompositeOperation = "destination-out";
    ctx.fillStyle = "rgba(0, 0, 0, 0.20)";
    ctx.fillRect(0, 0, W, H);
    const lm = now - lastSeen < 300 ? latest : null;
    const fit = (v) => Math.max(0.02, Math.min(0.98, 0.5 + (v - 0.5) * reachScale));
    const mx = (nx) => (1 - fit(nx)) * W;
    const my = (ny) => fit(ny) * H;
    const RMIN = 24;
    const RMAX = Math.min(W, H) * 0.42;
    const clampRN = (rn) => {
      const scaled = rn * sizeScale;
      const minRN = RMIN / Math.min(W, H);
      const maxRN = 0.46;
      return Math.max(minRN, Math.min(maxRN, scaled));
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
    const rpxOf = (_cn, rn) => rn * RPX || 1;
    const disc = (cn, rn) => {
      ctx.beginPath();
      ctx.arc(px(cn.x), py(cn.y), rn * RPX, 0, Math.PI * 2);
    };
    const spawnAt = (x, y, tangentX, tangentY, count, speed, bind = false) => {
      for (let i = 0; i < count; i++) {
        const spread = (Math.random() - 0.5) * 0.9;
        const sp = speed * (0.4 + Math.random() * 1.1);
        sparks.push({
          x,
          y,
          vx: (tangentX + spread * -tangentY) * sp,
          vy: (tangentY + spread * tangentX) * sp,
          life: 1,
          decay: 0.03 + Math.random() * 0.05,
          heat: Math.random(),
          width: 0.35 + Math.random() * 0.85,
          bind
        });
      }
    };
    const pinch = lm ? pinchL.update(lm, now) : (pinchL.update(null, now), null);
    const pinched = !!(pinch && pinch.isPinched && pinch.center);
    const cursor = (() => {
      if (!pinched || !pinch?.center) return null;
      if (parallaxStrength <= 0) return pinch.center;
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
    let p;
    if (cursor) {
      p = detector.push(cursor.x, cursor.y, now);
    } else {
      detector.reset();
      p = IDLE_PROGRESS;
    }
    const prevPhase = state.phase;
    state = stepPortal(
      state,
      {
        now,
        pinched,
        completed: p.completed && !!p.center,
        progress: p.progress,
        center: p.center ? { x: mx(p.center.x), y: my(p.center.y) } : null,
        radius: rpxOf(p.center, clampRN(p.radius))
      },
      { igniteMs: IGNITE_MS, closeMs: CLOSE_MS, minOpenMs: MIN_OPEN_MS }
    );
    const S = state;
    const portalUp = S.phase === "igniting" || S.phase === "open" || S.phase === "closing";
    if (S.phase === "igniting" && prevPhase !== "igniting") {
      if (p.center) {
        const rn = clampRN(p.radius);
        geom = {
          cx: Math.max(rn, Math.min(1 - rn, p.center.x)),
          cy: Math.max(rn, Math.min(1 - rn, p.center.y)),
          r: p.radius
        };
      }
      attract = { cx: geom.cx, cy: geom.cy, r: rpxOf({ x: geom.cx, y: geom.cy }, clampRN(geom.r)) };
      window.webkit?.messageHandlers?.portal?.postMessage({
        event: "opened",
        x: mx(geom.cx),
        y: my(geom.cy),
        r: rpxOf({ x: geom.cx, y: geom.cy }, clampRN(geom.r)),
        armed: armed?.label ?? null
      });
      comet = [];
      const gr = rpxOf({ x: geom.cx, y: geom.cy }, clampRN(geom.r));
      for (let i = 0; i < 700; i++) {
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
    if (!portalUp && prevPhase === "closing") {
      detector.reset();
      comet = [];
      attract = null;
      window.webkit?.messageHandlers?.portal?.postMessage({ event: "closed" });
    }
    if (lm && !portalUp) {
      ctx.globalCompositeOperation = "lighter";
      const hub = lm[9];
      const shrinkX = (v) => hub.x + (v - hub.x) * handScale;
      const shrinkY = (v) => hub.y + (v - hub.y) * handScale;
      for (const t of FINGER_TIPS) {
        ctx.shadowBlur = pinched ? 9 : 6;
        ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
        ctx.fillStyle = `rgba(${SPARK_HOT}, ${pinched ? 1 : 0.8})`;
        ctx.beginPath();
        ctx.arc(mx(shrinkX(lm[t].x)), my(shrinkY(lm[t].y)), pinched ? 1.7 : 1.4, 0, Math.PI * 2);
        ctx.fill();
      }
      if (pinch?.center) {
        ctx.shadowBlur = 12;
        ctx.shadowColor = `rgba(${CORE}, 1)`;
        ctx.fillStyle = `rgba(${CORE}, 1)`;
        ctx.beginPath();
        ctx.arc(mx(shrinkX(pinch.center.x)), my(shrinkY(pinch.center.y)), 1.9, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.shadowBlur = 0;
      if (pinched && pinch?.center) {
        const cx0 = mx(shrinkX(pinch.center.x));
        const cy0 = my(shrinkY(pinch.center.y));
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
    if (S.phase === "drawing" && p.center && p.startAngle !== null && p.progress > 0.16) {
      const cn = p.center;
      const rn = clampRN(p.radius);
      const rpx = rpxOf(cn, rn);
      const swept = -Math.max(-Math.PI * 2, Math.min(Math.PI * 2, p.sweep));
      const a0 = mirrorAngle(p.startAngle);
      const a1 = a0 + swept;
      const k = Math.pow(p.progress, 1.6);
      ctx.globalCompositeOperation = "lighter";
      ctx.lineCap = "round";
      ctx.shadowBlur = 8 + 30 * k;
      ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
      ctx.strokeStyle = `rgba(${SPARK_COLD}, ${0.03 + k * 0.18})`;
      ctx.lineWidth = Math.max(1.5, rpx * (0.02 + k * 0.06));
      arcPath(cn, rn, a0, a1, 96, 3);
      ctx.stroke();
      ctx.strokeStyle = `rgba(${SPARK_MID}, ${0.05 + k * 0.3})`;
      ctx.lineWidth = Math.max(1.2, rpx * (0.01 + k * 0.03));
      arcPath(cn, rn, a0, a1, 96, 1.5);
      ctx.stroke();
      ctx.shadowBlur = 6 + 16 * k;
      ctx.strokeStyle = `rgba(${CORE}, ${0.04 + k * 0.36})`;
      ctx.lineWidth = Math.max(0.8, rpx * (4e-3 + k * 0.011));
      arcPath(cn, rn, a0, a1);
      ctx.stroke();
      const headSpan = Math.sign(swept) * Math.min(Math.abs(swept), 0.55);
      ctx.shadowBlur = 14 + 50 * k;
      ctx.strokeStyle = `rgba(${CORE}, ${0.2 + k * 0.35})`;
      ctx.lineWidth = Math.max(1.4, rpx * (0.012 + k * 0.042));
      arcPath(cn, rn, a1 - headSpan, a1, 24);
      ctx.stroke();
      ctx.shadowBlur = 0;
      const hx = px(cn.x) + Math.cos(a1) * rpx;
      const hy = py(cn.y) + Math.sin(a1) * rpx;
      const dir = Math.sign(swept) || 1;
      const tx = -Math.sin(a1) * dir;
      const ty = Math.cos(a1) * dir;
      const prev = comet[comet.length - 1];
      const speedPx = prev ? Math.hypot(hx - prev.x, hy - prev.y) : 0;
      comet.push({ x: hx, y: hy });
      if (comet.length > 40) comet.shift();
      spawnAt(
        hx,
        hy,
        tx,
        ty,
        Math.round((1 + k * 9) * (1 + Math.min(0.8, speedPx * 0.03))),
        2.2 + k * 3,
        true
      );
      spawnAt(hx, hy, tx, ty, Math.round(k * 3), 3 + k * 2.8, false);
      attract = { cx: cn.x, cy: cn.y, r: rpx };
    }
    if (portalUp) {
      spin += 0.012;
      const ignite = ignitionAmount(S, now, IGNITE_MS);
      const shut = collapseAmount(S, now, CLOSE_MS);
      const e = ease(ignite);
      const cn = { x: geom.cx, y: geom.cy };
      const rn = clampRN(geom.r) * (1 - ease(shut));
      const rpx = rpxOf(cn, rn);
      const vis = e * (1 - shut);
      const age = (now - S.born) / 1e3;
      if (S.phase === "open") attract = { cx: cn.x, cy: cn.y, r: rpx };
      if (rpx >= 2) {
        const cx0 = px(cn.x), cy0 = py(cn.y);
        if (armed) {
          ctx.globalCompositeOperation = "destination-out";
          ctx.globalAlpha = 1;
          disc(cn, rn * 0.985);
          ctx.fill();
          ctx.globalCompositeOperation = "source-over";
          ctx.globalAlpha = vis * 0.9;
          const lip = ctx.createRadialGradient(cx0, cy0, rpx * 0.88, cx0, cy0, rpx);
          lip.addColorStop(0, "rgba(0,0,0,0)");
          lip.addColorStop(1, "rgba(120, 48, 12, 0.6)");
          ctx.fillStyle = lip;
          disc(cn, rn);
          ctx.fill();
          ctx.globalAlpha = 1;
        } else {
          ctx.globalCompositeOperation = "source-over";
          ctx.globalAlpha = vis;
          const inner = ctx.createRadialGradient(cx0, cy0, 0, cx0, cy0, rpx);
          inner.addColorStop(0, "rgba(3, 2, 1, 1)");
          inner.addColorStop(0.82, "rgba(10, 5, 2, 1)");
          inner.addColorStop(0.95, "rgba(46, 18, 5, 1)");
          inner.addColorStop(1, "rgba(120, 48, 12, 0.85)");
          ctx.fillStyle = inner;
          disc(cn, rn);
          ctx.fill();
          ctx.globalAlpha = 1;
        }
        ctx.globalCompositeOperation = "lighter";
        const bloom = ctx.createRadialGradient(cx0, cy0, rpx * 0.9, cx0, cy0, rpx * 1.22);
        bloom.addColorStop(0, `rgba(${SPARK_MID}, ${0.16 * vis})`);
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
        const heat = 1 + (1 - e) * 1.6 + ease(shut) * 2.6;
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
        const dl = Math.hypot(dx, dy) || 1;
        const nx = dx / dl, ny = dy / dl;
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
      if (sp.life <= 0) continue;
      alive.push(sp);
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
    sparks = alive.length > 1400 ? alive.slice(-1400) : alive;
  }
  requestAnimationFrame(frame);
})();
