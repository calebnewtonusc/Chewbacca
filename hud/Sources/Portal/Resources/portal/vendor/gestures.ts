import type { Landmark, GestureName } from "./types";

function dist(a: Landmark, b: Landmark) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function classifyGesture(
  lm: Landmark[] | null | undefined,
): GestureName {
  if (!lm || lm.length < 21) return "none";
  const extended = [
    dist(lm[4], lm[0]) > dist(lm[3], lm[0]),
    lm[8].y < lm[6].y,
    lm[12].y < lm[10].y,
    lm[16].y < lm[14].y,
    lm[20].y < lm[18].y,
  ];
  const [thumb, index, middle, ring, pinky] = extended;
  const count = extended.filter(Boolean).length;
  const pinchRatio = dist(lm[4], lm[8]) / Math.max(dist(lm[0], lm[9]), 0.001);

  if (pinchRatio < 0.38) return "pinch";
  if (!thumb && !index && !middle && !ring && !pinky) return "fist";
  if (count === 5) return "open";
  if (index && !middle && !ring && !pinky) return "point";
  if (index && middle && !ring && !pinky) return "peace";
  if (thumb && !index && !middle && !ring && !pinky) return "thumbs_up";
  if (!thumb && !index && !middle && !ring && pinky) return "pinky";
  if (count >= 4) return "almost_open";
  return "custom";
}

export const GESTURE_LABELS: Record<GestureName, string> = {
  none: "",
  fist: "Fist",
  open: "Open",
  point: "Point",
  peace: "Peace",
  thumbs_up: "Thumbs up",
  pinky: "Pinky up",
  pinch: "Pinch",
  almost_open: "Almost open",
  custom: "",
};
