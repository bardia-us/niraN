#version 460 core
#include <flutter/runtime_effect.glsl>

// QWEA0/Liquid-Glass-Android normal-lit two-lobe rim, adapted for a live
// Windows frosted backdrop without capturing it on each frame.
// Copyright (c) 2025-2026 pandadog, MIT; assets/licenses/liquid-glass-android.txt.
uniform vec2 uSize;
uniform float uRadius;
uniform float uStrength;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy - uSize * 0.5;
  vec2 q = abs(p) - (uSize * 0.5 - vec2(uRadius));
  vec2 corner = max(q, vec2(0.0));
  float len = length(corner);
  float sdf = len + min(max(q.x, q.y), 0.0) - uRadius;
  float coverage = clamp(0.5 - sdf / 1.5, 0.0, 1.0);
  if (coverage <= 0.004) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 n = len > 0.001 ? corner / len * sign(p)
      : (q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y)));
  float facing = dot(n, vec2(-0.8660254, -0.5));
  float lobeF = pow(max(facing, 0.0), 4.5);
  float lobeB = pow(max(-facing, 0.0), 4.5);
  float shortSide = min(uSize.x, uSize.y);
  float bevel = max(2.0, min(48.0, shortSide * 0.30));
  float bandMax = max(2.0, min(6.0, shortSide * 0.05));
  float bandW = clamp(bevel * 0.3, 2.0, bandMax);
  float depth = max(-sdf, 0.0);
  float glowIn = clamp((depth - 1.0) / 2.0, 0.0, 1.0);
  float glow = glowIn * pow(clamp(1.0 - (depth - 3.0) / bandW, 0.0, 1.0), 1.5);
  float hair = clamp(1.0 - abs(sdf + 1.0) / 2.0, 0.0, 1.0);
  float alpha = clamp((hair * 0.70 * (lobeF + lobeB) + glow * 0.10 * lobeF)
      * uStrength * coverage, 0.0, 1.0);
  // Transparent everywhere except the specular band; body diffusion stays in
  // BackdropFilter. No bitmap capture, pixel readback, ticker or sampler.
  fragColor = vec4(vec3(alpha), alpha);
}
