#version 460 core
#include <flutter/runtime_effect.glsl>

// Optical model adapted from QWEA0/Liquid-Glass-Android GlassLensRenderer.
// Copyright (c) 2025-2026 pandadog, MIT; see assets/licenses/liquid-glass-android.txt.
// The native Android RenderNode pipeline is not copied: this Canvas shader
// consumes the modal's one-off Gaussian backdrop on Windows/Skia.

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform vec4 uTransform;
uniform vec2 uSnapshotSize;
uniform float uRadius;
uniform float uSaturation;
uniform float uRefraction;
uniform float uLightIntensity;
uniform sampler2D uBackdrop;
out vec4 fragColor;

vec2 sourceUV(vec2 p) {
  vec2 mapped = vec2(dot(uTransform.xy, p), dot(uTransform.zw, p));
  vec2 halfTexel = vec2(0.5) / uSnapshotSize;
  return clamp((uOrigin + mapped) / uSnapshotSize, halfTexel, vec2(1.0) - halfTexel);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 centered = p - uSize * 0.5;
  vec2 q = abs(centered) - (uSize * 0.5 - vec2(uRadius));
  vec2 corner = max(q, vec2(0.0));
  float outsideLength = length(corner);
  float sdf = outsideLength + min(max(q.x, q.y), 0.0) - uRadius;
  vec2 normal = outsideLength > 0.001
    ? corner / max(outsideLength, 0.001) * sign(centered)
    : (q.x > q.y ? vec2(sign(centered.x), 0.0) : vec2(0.0, sign(centered.y)));
  float coverage = clamp(0.5 - sdf / 1.5, 0.0, 1.0);
  if (coverage <= 0.004) {
    fragColor = vec4(0.0);
    return;
  }
  float shortSide = min(uSize.x, uSize.y);
  float bevel = max(2.0, min(48.0, shortSide * 0.30));
  float depth = max(-sdf, 0.0);
  float t = clamp(depth / bevel, 0.0, 1.0);
  // Same normalized inverse-power profile (falloff=2) as upstream. The
  // displacement becomes exactly zero in the flat body, not a global zoom.
  float slope = (pow(1.0 + 4.0 * t, -2.0) - 0.04) / 0.96;
  float refractCap = 0.70 * shortSide * min(1.0, shortSide / 110.0);
  float refract = min(160.0, refractCap) * uRefraction;
  vec2 offset = -normal * (slope * refract);
  // Inward sampling, like upstream's default. Clamp to the panel's valid
  // content, then the captured texture: never expose a transparent-black rim.
  vec2 lo = vec2(1.0);
  vec2 hi = max(lo, uSize - vec2(1.0));
  vec2 cR = clamp(p + offset * (1.0 - 0.10 * slope), lo, hi);
  vec2 cG = clamp(p + offset, lo, hi);
  vec2 cB = clamp(p + offset * (1.0 + 0.10 * slope), lo, hi);
  vec4 sR = texture(uBackdrop, sourceUV(cR));
  vec4 sG = texture(uBackdrop, sourceUV(cG));
  vec4 sB = texture(uBackdrop, sourceUV(cB));
  // Flutter samplers are premultiplied. Perform optical colour operations in
  // straight colour, then premultiply once on output (including coverage).
  vec3 color = vec3(sR.r / max(sR.a, 0.0001),
                    sG.g / max(sG.a, 0.0001),
                    sB.b / max(sB.a, 0.0001));
  float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
  float saturation = uSaturation;
  if (saturation > 1.0) {
    float satNow = max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b));
    float room = 1.0 - smoothstep(0.2, 0.85, satNow);
    float highlightRoom = 1.0 - smoothstep(0.75, 0.98, luminance);
    saturation = 1.0 + (saturation - 1.0) * mix(0.3, 1.0, room * highlightRoom);
  }
  color = mix(vec3(luminance), color, saturation);
  // Equal opposing specular lobes; only the facing lobe has a soft inner glow.
  // No direction-independent white wash and no dark inner stroke.
  float facing = dot(normal, normalize(vec2(-0.8660254, -0.5)));
  float lobeF = pow(max(facing, 0.0), 4.5);
  float lobeB = pow(max(-facing, 0.0), 4.5);
  float bandMax = max(2.0, min(6.0, shortSide * 0.05));
  float bandW = clamp(bevel * 0.3, 2.0, bandMax);
  float glowIn = clamp((depth - 1.0) / 2.0, 0.0, 1.0);
  float glow = glowIn * pow(clamp(1.0 - (depth - 3.0) / bandW, 0.0, 1.0), 1.5);
  float hair = clamp(1.0 - abs(sdf + 1.0) / 2.0, 0.0, 1.0);
  float spec = (hair * 0.70 * (lobeF + lobeB) + glow * 0.10 * lobeF)
             * (uLightIntensity / 0.055);
  color = clamp(color + vec3(spec), vec3(0.0), vec3(1.0));
  float alpha = sG.a * coverage;
  fragColor = vec4(color * alpha, alpha);
}
