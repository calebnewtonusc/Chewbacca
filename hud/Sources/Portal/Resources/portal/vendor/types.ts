export interface Landmark {
  x: number;
  y: number;
  z: number;
}

export type HandSide = "left" | "right";

export interface HandData {
  lm: Landmark[];
  side: HandSide;
}

export type GestureName =
  | "none"
  | "fist"
  | "open"
  | "point"
  | "peace"
  | "thumbs_up"
  | "pinky"
  | "pinch"
  | "almost_open"
  | "custom";

export interface GazeSample {
  x: number;
  y: number;
}
