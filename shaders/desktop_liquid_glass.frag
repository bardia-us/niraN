#version 460 core
#include <flutter/runtime_effect.glsl>

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
  return clamp((uOrigin + mapped) / uSnapshotSize, vec2(0.0), vec2(1.0));
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
  float depth = max(-sdf, 0.0);
  float edge = exp(-depth / 18.0);
  // The rounded-rectangle distance field yields a continuously varying normal.
  // Displacement warps actual snapshot pixels, not a painted lens gradient.
  float bend = edge * (1.0 - exp(-depth / 1.5)) * 18.0 * uRefraction;
  vec2 refracted = p - normal * bend;
  // The modal owns a one-off Gaussian filtered image. No sparse-tap blur or
  // repeated background capture occurs while the route animates.
  vec4 sampleColor = texture(uBackdrop, sourceUV(refracted));
  float dispersion = edge * uRefraction * 0.65;
  sampleColor.r = mix(sampleColor.r, texture(uBackdrop, sourceUV(refracted - normal * dispersion)).r, 0.22);
  sampleColor.b = mix(sampleColor.b, texture(uBackdrop, sourceUV(refracted + normal * dispersion)).b, 0.22);
  float luminance = dot(sampleColor.rgb, vec3(0.299, 0.587, 0.114));
  vec3 color = mix(vec3(luminance), sampleColor.rgb, uSaturation);
  float directionalLight = max(dot(normal, normalize(vec2(-0.6, -0.8))), 0.0);
  color += vec3(edge * directionalLight * uLightIntensity) * sampleColor.a;
  float coverage = 1.0 - smoothstep(-0.5, 0.5, sdf);
  fragColor = vec4(clamp(color, vec3(0.0), vec3(sampleColor.a)), sampleColor.a) * coverage;
}
