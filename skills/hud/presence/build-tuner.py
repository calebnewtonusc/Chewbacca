#!/usr/bin/env python3
"""Generate tuner.html from the Metal shader the HUD actually runs.

The tuner and the overlay have to be the same shader or tuning it is a waste
of an evening: a hand-copied GLSL twin drifts on the first edit to either side
and then the colours you picked are not the colours you ship. So the GLSL is
mechanically converted from PresenceFieldShader.swift every time this runs,
and the only thing this script is allowed to change is which numbers became
uniforms.

    python3 build-tuner.py [path/to/PresenceFieldShader.swift]

Defaults to the checkout at ~/dev/bob-the-builder.
"""

import pathlib
import re
import sys

HERE = pathlib.Path(__file__).parent
DEFAULT_SOURCE = pathlib.Path.home() / (
    "dev/bob-the-builder/hud/Sources/BobHUDKit/PresenceFieldShader.swift"
)

# Every constant the tuner lifts into a uniform, as it appears in the Metal.
# Name, the Metal declaration to delete, the GLSL uniform it becomes.
PALETTE = [
    ("CLEAR", "u_clear"),
    ("POOL", "u_pool"),
    ("BLUE_DEEP", "u_blueDeep"),
    ("BLUE_PALE", "u_bluePale"),
    ("YEL", "u_yel"),
    ("ORG", "u_org"),
]

# The compositing tail, replaced wholesale. The overlay's version clamps the
# colour to its own coverage, which is a film that glows and disappears where
# it is dark. `u_translucency` mixes that toward coverage taken off the band
# itself, which is a sheet of tinted glass that dims what is behind it. They
# are different looks and the slider is the argument for having both.
TAIL_FROM = """    float a = clamp(max(max(c.r, c.g), c.b) * 1.35, 0.0, 1.0) * U.alpha;
    return half4(half3(min(c, float3(a))), half(a));"""

TAIL_TO = """    float lum = max(max(c.r, c.g), c.b);
    float filmA = clamp(lum * u_gain, 0.0, 1.0);
    float sheetA = clamp(born * lit * env * u_sheet, 0.0, 1.0);
    float a = mix(filmA, max(filmA, sheetA), u_translucency) * u_alpha;
    fragColor = vec4(min(c, vec3(a)), a);"""


def to_glsl(metal: str) -> str:
    src = metal

    # The Swift wrapper.
    src = src.split('let presenceFieldSource = ##"""', 1)[1]
    src = src.rsplit('"""##', 1)[0]

    # Metal preamble and the vertex stage, neither of which has a GLSL
    # counterpart here: the tuner draws its own full screen triangle.
    src = src.replace("#include <metal_stdlib>\n", "")
    src = src.replace("using namespace metal;\n", "")
    src = re.sub(
        r"/// A full-screen triangle.*?^}\n",
        "",
        src,
        flags=re.S | re.M,
    )
    src = re.sub(r"^struct Uniforms \{.*?^\};\n", "", src, flags=re.S | re.M)

    # The entry point.
    src = src.replace(
        "fragment half4 presenceFragment(float4 fragPos [[position]],\n"
        "                                constant Uniforms &U [[buffer(0)]]) {",
        "void main() {\n"
        "    // Metal's origin is top left and GL's is bottom up, and `popAt`\n"
        "    // is the one thing in here that would notice.\n"
        "    vec2 fragPos = vec2(gl_FragCoord.x, u_size.y - gl_FragCoord.y);",
    )

    src = src.replace(TAIL_FROM, TAIL_TO)

    # Types and the one renamed builtin.
    src = src.replace("static inline ", "")
    # Matrices first. `float3x3` starts with `float3`, so the vector pass would
    # otherwise leave `vec3x3` behind and the shader stops compiling at
    # filmResponse's colour matrix.
    for a, b in (("float4x4", "mat4"), ("float3x3", "mat3"), ("float2x2", "mat2")):
        src = src.replace(a, b)
    for a, b in (("float4", "vec4"), ("float3", "vec3"), ("float2", "vec2")):
        src = src.replace(a, b)
    src = re.sub(r"\batan2\(", "atan(", src)

    # Uniforms, which are members of a struct on one side and globals on the
    # other. Done before the palette so `U.alpha` is gone by the time the tail
    # is checked.
    src = re.sub(r"\bU\.(\w+)", lambda m: "u_" + m.group(1), src)

    # Palette constants become uniforms.
    for name, uniform in PALETTE:
        src = re.sub(rf"^\s*const vec3 {name} = vec3\([^)]*\);\n", "", src, flags=re.M)
        src = re.sub(rf"\b{name}\b", uniform, src)

    # The handful of shaping numbers worth a slider. Each is unique in the
    # file; a bare number replace would hit the wrong line, so each carries
    # enough of its own expression to be unambiguous.
    swaps = [
        ("smoothstep(-0.13, -0.05, d)", "smoothstep(u_rimA, u_rimB, d)"),
        ("smoothstep(0.03, 0.11, d)", "smoothstep(u_blueA, u_blueB, d)"),
        ("(1.0 + 0.85 * exp(-pow((d + 0.01) / 0.070, 2.0)))",
         "(1.0 + u_glow * exp(-pow((d + 0.01) / u_glowW, 2.0)))"),
        ("float fres = 0.74 + 0.36 * exp(-v * 7.0);",
         "float fres = u_fresA + u_fresB * exp(-v * 7.0);"),
        ("* 0.055 * mix(vec3(1.0), sheen, 0.92)",
         "* u_lip * mix(vec3(1.0), sheen, 0.92)"),
        ("c = max(c * 1.9, 0.0);", "c = max(c * u_expose, 0.0);"),
    ]
    for a, b in swaps:
        if a not in src:
            raise SystemExit(f"shader has moved on: cannot find\n  {a}")
        src = src.replace(a, b)

    return src.strip("\n")


UNIFORMS = """#version 300 es
precision highp float;
out vec4 fragColor;

uniform vec2 u_size;
uniform vec2 u_popAt;
uniform float u_time, u_act, u_closing;
uniform float u_rest, u_drift, u_anger, u_alpha;

uniform vec3 u_clear, u_pool, u_blueDeep, u_bluePale, u_yel, u_org;
uniform float u_rimA, u_rimB, u_blueA, u_blueB;
uniform float u_glow, u_glowW, u_fresA, u_fresB, u_lip, u_expose;
uniform float u_gain, u_sheet, u_translucency;
"""


def main() -> None:
    source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source.exists():
        raise SystemExit(f"no shader at {source}")

    glsl = UNIFORMS + "\n" + to_glsl(source.read_text())
    page = (HERE / "tuner.template.html").read_text()
    out = HERE / "tuner.html"
    out.write_text(page.replace("/*__SHADER__*/", glsl))
    print(f"wrote {out} ({len(glsl)} chars of GLSL from {source.name})")


if __name__ == "__main__":
    main()
