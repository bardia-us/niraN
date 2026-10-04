// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry
// This shader reads displacement data from a pre-computed texture and applies
// the liquid glass effect efficiently

#version 460 core
precision highp float;

#define DEBUG_GEOMETRY 0

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"
#include "render.glsl"

uniform vec2 uSize;
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;

uniform vec4 uGlassColor;
uniform vec3 uOpticalProps;
uniform vec3 uLightConfig;
uniform vec2 uLightDirection;
uniform float uTopLeftTextures;
// Negative means general cached geometry. Nonnegative is a single desktop
// rounded rectangle, evaluated continuously rather than from RGBA8 offsets.
uniform float uSingleRadius;

float uRefractiveIndex = uOpticalProps.x;
float uChromaticAberration = uOpticalProps.y;
float uThickness = uOpticalProps.z;
float uLightIntensity = uLightConfig.x;
float uAmbientStrength = uLightConfig.y;
float uSaturation = uLightConfig.z;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

// Rounded cap with an actual 3D normal. Snell's ray travels through the cap
// and a shallow optical body; the former 8x slab exaggerated folds, while the
// replacement 9px offset suppressed the lens altogether.
vec3 desktopCapNormal(vec2 outward, float height) {
    float z = clamp(height, 0.0, 1.0);
    return vec3(outward * sqrt(max(0.0, 1.0 - z * z)), z);
}

vec2 desktopRefraction(vec2 outward, float height) {
    vec3 normal = desktopCapNormal(outward, height);
    vec3 ray = refract(vec3(0.0, 0.0, -1.0), normal,
                       1.0 / max(uRefractiveIndex, 1.0));
    float travel = max(uThickness, 0.0) * (3.0 + height)
                   / max(abs(ray.z), 0.001);
    return ray.xy * travel;
}

// Integrate the steep cap over a pixel, not a quantized displacement image.
// All taps use the SAME already-blurred backdrop. This is antialiasing of the
// optical mapping, not a second blur or an opacity veil.
vec4 desktopTransmission(vec2 uv, vec2 outward, float height, vec2 offset) {
    vec2 invSize = 1.0 / uSize;
    vec4 center = texture(uBackgroundTexture, uv + offset * invSize);
    if (height > 0.999 || uChromaticAberration >= 0.01) return center;
    float slope = sqrt(max(0.0, 1.0 - height * height));
    float ds = 0.35 / max(uThickness, 0.001);
    float a = clamp(slope - ds, 0.0, 1.0);
    float b = clamp(slope + ds, 0.0, 1.0);
    vec2 inner = desktopRefraction(outward, sqrt(max(0.0, 1.0 - a * a)));
    vec2 outer = desktopRefraction(outward, sqrt(max(0.0, 1.0 - b * b)));
    return center * 0.5
        + texture(uBackgroundTexture, uv + (inner - outward * 0.35) * invSize) * 0.25
        + texture(uBackgroundTexture, uv + (outer + outward * 0.35) * invSize) * 0.25;
}

float capSpecular(vec3 normal, vec3 light, float f0) {
    vec3 halfVector = normalize(light + vec3(0.0, 0.0, 1.0));
    float noH = max(dot(normal, halfVector), 0.0);
    float noL = max(dot(normal, light), 0.0);
    float noV = max(normal.z, 0.001);
    float voH = max(halfVector.z, 0.0);
    // GGX distribution, Schlick Fresnel, correlated Smith visibility.
    // The rounded surface, rather than a painted perimeter, locates the light.
    float roughness = 0.22;
    float a2 = roughness * roughness;
    float d = noH * noH * (a2 - 1.0) + 1.0;
    float distribution = a2 / max(3.14159265 * d * d, 0.0001);
    float visibility = 0.5 / max(noL * (noV * (1.0 - roughness) + roughness)
                      + noV * (noL * (1.0 - roughness) + roughness), 0.001);
    float fresnel = f0 + (1.0 - f0) * pow(1.0 - voH, 5.0);
    return distribution * visibility * fresnel * noL;
}

vec3 desktopReflection(vec3 transmitted, vec2 uv, vec2 outward, float height) {
    if (height > 0.999 || uLightIntensity + uAmbientStrength <= 0.0)
        return transmitted;
    vec3 normal = desktopCapNormal(outward, height);
    vec3 reflectedRay = reflect(vec3(0.0, 0.0, -1.0), normal);
    vec3 keyLight = normalize(vec3(-uLightDirection, 0.65));
    vec3 fillLight = normalize(vec3(uLightDirection, 0.65));
    float iorRatio = (max(uRefractiveIndex, 1.0) - 1.0)
                    / (max(uRefractiveIndex, 1.0) + 1.0);
    float f0 = iorRatio * iorRatio;
    float fresnel = f0 + (1.0 - f0) * pow(1.0 - normal.z, 5.0);
    // Local reflected colour plus a soft studio-light environment. Its dark
    // and bright sides also define depth on a light page, without a black or
    // white border. Flat glass stays the transmitted backdrop.
    vec3 local = texture(uBackgroundTexture,
        uv + reflectedRay.xy * uThickness * 1.5 / uSize).rgb;
    float studio = 0.18 + 0.78 * smoothstep(-0.55, 0.8,
                                           dot(reflectedRay, keyLight));
    vec3 environment = mix(local, vec3(studio), 0.55);
    float reflection = fresnel * clamp(uLightIntensity * 1.8 + uAmbientStrength, 0.0, 1.0);
    float gloss = capSpecular(normal, keyLight, f0)
                  + capSpecular(normal, fillLight, f0) * 0.18;
    float bevel = smoothstep(0.0, 0.15, length(normal.xy));
    vec3 color = mix(transmitted, environment, reflection);
    // Expose into available channel headroom rather than adding then clipping
    // HDR light into a broad white plateau on a light page. The exponential
    // shoulder retains the varying cap reflection even near display white.
    float radiance = gloss * (1.0 - exp(-uLightIntensity * 8.0)) * 5.0 * bevel;
    vec3 headroom = max(vec3(1.0) - color, vec3(0.0));
    return color + headroom * (vec3(1.0)
           - exp(-vec3(radiance) / (headroom + vec3(0.06))));
}

void main() {
    // ImageFilter.shader uses input-texture coordinates and an engine-supplied
    // physical uSize. Flutter 3.47 preserves the origin padding after a blur;
    // subtracting the geometry origin again corrupts the background lookup.
    vec2 fragCoord = FlutterFragCoord().xy;
    
    vec2 screenUV = fragCoord / uSize;
        
    #ifdef IMPELLER_TARGET_OPENGLES
        // Windows GLES supplies both textures in top-left orientation. Keep
        // the upstream bottom-left convention for the other rendering paths.
        if (uTopLeftTextures < 0.5) screenUV.y = 1.0 - screenUV.y;
    #endif

    vec2 geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize;
    #ifdef IMPELLER_TARGET_OPENGLES
        if (uTopLeftTextures < 0.5) geometryUV.y = 1.0 - geometryUV.y;
    #endif

    vec4 geometryData;
    vec2 displacement;
    vec2 outwardNormal = vec2(0.0);
    if (uSingleRadius >= 0.0 && uTopLeftTextures > 0.5) {
        vec2 halfSize = uGeometrySize * 0.5;
        float radius = min(uSingleRadius, min(halfSize.x, halfSize.y));
        vec2 p = fragCoord - uGeometryOffset - halfSize;
        vec2 q = abs(p) - halfSize + radius;
        vec2 outside = max(q, 0.0);
        float sd = min(max(q.x, q.y), 0.0) + length(outside) - radius;
        if (length(outside) > 0.0001) {
            outwardNormal = sign(p) * normalize(outside);
        } else {
            outwardNormal = q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
        }
        float thickness = max(uThickness, 0.001);
        float slope = clamp(1.0 + sd / thickness, 0.0, 1.0);
        float height = sqrt(max(0.0, 1.0 - slope * slope));
        float alpha = 1.0 - smoothstep(-2.0, 0.0, sd);
        displacement = desktopRefraction(outwardNormal, height);
        geometryData = vec4(0.0, 0.0, height, alpha);
    } else {
        geometryData = texture(uGeometryTexture, geometryUV);
        displacement = decodeDisplacement(geometryData, uThickness * 10.0);
        outwardNormal = length(displacement) > 0.0001 ? -normalize(displacement) : vec2(0.0);
        if (uTopLeftTextures > 0.5) {
            // Transformed/shared shapes retain their geometry mask but use
            // the same optical body, rather than switching material on hover.
            float height = clamp(geometryData.b, 0.0, 1.0);
            displacement = desktopRefraction(outwardNormal, height);
        }
    }
    
    #if DEBUG_GEOMETRY
        fragColor = geometryData;
        return;
    #endif
    
    if (geometryData.a < 0.01) {
        fragColor = vec4(0);
        return;
    }
    
    vec2 invUSize = 1.0 / uSize;
    
    vec4 refractColor;
    if (uChromaticAberration < 0.01) {
        vec2 refractedUV = screenUV + displacement * invUSize;
        refractColor = uTopLeftTextures > 0.5
            ? desktopTransmission(screenUV, outwardNormal, geometryData.b, displacement)
            : texture(uBackgroundTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        
        vec2 redUV = screenUV + redOffset * invUSize;
        vec2 greenUV = screenUV + displacement * invUSize;
        vec2 blueUV = screenUV + blueOffset * invUSize;
        
        float red = texture(uBackgroundTexture, redUV).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV);
        float blue = texture(uBackgroundTexture, blueUV).b;
        
        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }
    
    vec4 finalColor = applyGlassColor(refractColor, uGlassColor);
    finalColor.rgb = applySaturation(finalColor.rgb, uSaturation);

    if (uTopLeftTextures > 0.5) {
        finalColor.rgb = desktopReflection(finalColor.rgb, screenUV,
                                           outwardNormal, geometryData.b);
        float alpha = geometryData.a;
        fragColor = vec4(finalColor.rgb * alpha, alpha);
        return;
    }

    // Compute edge lighting
    float normalizedHeight = geometryData.b;
    
    float thicknessScale = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
    float edgeThreshold = mix(0.8, 0.5, 1.0 / thicknessScale);
    float edgeFactor = 1.0 - smoothstep(0.0, edgeThreshold, normalizedHeight);
    
    if (edgeFactor > 0.01) {
        vec2 normalXY = -outwardNormal;
        
        float mainLight = max(0.0, dot(normalXY, uLightDirection));
        float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));
        
        float totalInfluence = mainLight + oppositeLight * 0.8;
        float directional = pow(totalInfluence, 1.5) * uLightIntensity * 3.0;
        float ambient = uAmbientStrength * 0.5;
        
        float brightness = (directional + ambient) * edgeFactor * thicknessScale * 0.8;
        
        vec3 bgColor = refractColor.rgb;
        float bgLuminance = dot(bgColor, LUMA_WEIGHTS);
        vec3 highlightColor;
        
        vec3 saturatedBg = bgColor / max(bgLuminance, 0.001);
        saturatedBg = mix(bgColor, saturatedBg, 0.8);
        float colorfulness = length(bgColor - vec3(bgLuminance));
        float colorMix = clamp(colorfulness * 1.0 + 0.5, 0.5, 1.0);
        highlightColor = mix(vec3(1.0), saturatedBg, colorMix);
       
        
        finalColor.rgb = mix(finalColor.rgb, highlightColor, brightness);
    }

    float alpha = geometryData.a;
    fragColor = vec4(finalColor.rgb * alpha, alpha);
}
