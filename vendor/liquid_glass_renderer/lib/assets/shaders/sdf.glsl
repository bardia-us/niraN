// Shape array uniforms - 6 floats per shape (type, centerX, centerY, sizeW, sizeH, cornerRadius)
// Reduced from 64 to 16 shapes to fit Impeller's uniform buffer limit (16 * 6 = 96 floats vs 384)
#ifndef MAX_SHAPES
#define MAX_SHAPES 16
#endif

float sdfRRect( in vec2 p, in vec2 b, in float r ) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r;
}

float sdfRect(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdfSquircle(vec2 p, vec2 b, float r) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);

    vec2 q = abs(p) - b + r;
    
    vec2 maxQ = max(q, 0.0);
    return min(max(q.x, q.y), 0.0) + sqrt(maxQ.x * maxQ.x + maxQ.y * maxQ.y) - r;
}

float sdfEllipse(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    
    vec2 invR = 1.0 / r;
    vec2 invR2 = invR * invR;
    
    vec2 pInvR = p * invR;
    float k1 = length(pInvR);
    
    vec2 pInvR2 = p * invR2;
    float k2 = length(pInvR2);
    
    return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
}

float smoothUnion(float d1, float d2, float k) {
    if (k <= 0.0) {
        return min(d1, d2);
    }
    float e = max(k - abs(d1 - d2), 0.0);
    return min(d1, d2) - e * e * 0.25 / k;
}

float getShapeSDF(float type, vec2 p, vec2 center, vec2 size, float r) {
    if (type == 1.0) { // squircle
        return sdfSquircle(p - center, size / 2.0, r);
    }
    if (type == 2.0) { // ellipse
        return sdfEllipse(p - center, size / 2.0);
    }
    if (type == 3.0) { // rounded rectangle
        return sdfRRect(p - center, size / 2.0, r);
    }
    return 1e9; // none
}

float getShapeSDFFromArray(int index, vec2 p) {
    // SkSL requires constant uniform-array indexing. Keep all 16 shapes and
    // the same six-float uniform layout, without copying arrays by value.
#define SHAPE_AT(I) getShapeSDF(uShapeData[(I)*6], p, vec2(uShapeData[(I)*6+1], uShapeData[(I)*6+2]), vec2(uShapeData[(I)*6+3], uShapeData[(I)*6+4]), uShapeData[(I)*6+5])
    if (index == 0) return SHAPE_AT(0);
    if (index == 1) return SHAPE_AT(1);
    if (index == 2) return SHAPE_AT(2);
    if (index == 3) return SHAPE_AT(3);
    if (index == 4) return SHAPE_AT(4);
    if (index == 5) return SHAPE_AT(5);
    if (index == 6) return SHAPE_AT(6);
    if (index == 7) return SHAPE_AT(7);
    if (index == 8) return SHAPE_AT(8);
    if (index == 9) return SHAPE_AT(9);
    if (index == 10) return SHAPE_AT(10);
    if (index == 11) return SHAPE_AT(11);
    if (index == 12) return SHAPE_AT(12);
    if (index == 13) return SHAPE_AT(13);
    if (index == 14) return SHAPE_AT(14);
    if (index == 15) return SHAPE_AT(15);
#undef SHAPE_AT
    return 1e9;
}

float sceneSDF(vec2 p, int numShapes, float blend) {
    if (numShapes == 0) {
        return 1e9;
    }
    
    // Every array index is constant. Do not put a 16-way dispatcher inside a
    // 16-iteration loop: SkSL unrolling multiplies that entire graph, and then
    // multiplies it again for all five finite-difference SDF evaluations.
#define SINGLE_SHAPE(I) getShapeSDF(uShapeData[(I)*6], p, vec2(uShapeData[(I)*6+1], uShapeData[(I)*6+2]), vec2(uShapeData[(I)*6+3], uShapeData[(I)*6+4]), uShapeData[(I)*6+5])
    float result = SINGLE_SHAPE(0);
    
    if (numShapes > 1) result = smoothUnion(result, SINGLE_SHAPE(1), blend);
    if (numShapes > 2) result = smoothUnion(result, SINGLE_SHAPE(2), blend);
    if (numShapes > 3) result = smoothUnion(result, SINGLE_SHAPE(3), blend);
    if (numShapes > 4) result = smoothUnion(result, SINGLE_SHAPE(4), blend);
    if (numShapes > 5) result = smoothUnion(result, SINGLE_SHAPE(5), blend);
    if (numShapes > 6) result = smoothUnion(result, SINGLE_SHAPE(6), blend);
    if (numShapes > 7) result = smoothUnion(result, SINGLE_SHAPE(7), blend);
    if (numShapes > 8) result = smoothUnion(result, SINGLE_SHAPE(8), blend);
    if (numShapes > 9) result = smoothUnion(result, SINGLE_SHAPE(9), blend);
    if (numShapes > 10) result = smoothUnion(result, SINGLE_SHAPE(10), blend);
    if (numShapes > 11) result = smoothUnion(result, SINGLE_SHAPE(11), blend);
    if (numShapes > 12) result = smoothUnion(result, SINGLE_SHAPE(12), blend);
    if (numShapes > 13) result = smoothUnion(result, SINGLE_SHAPE(13), blend);
    if (numShapes > 14) result = smoothUnion(result, SINGLE_SHAPE(14), blend);
    if (numShapes > 15) result = smoothUnion(result, SINGLE_SHAPE(15), blend);
#undef SINGLE_SHAPE
    
    return result;
}

// Calculate 3D normal using derivatives (shader-specific normal calculation)
vec3 getNormal(float sd, float thickness) {
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    
    // The cosine and sine between normal and the xy plane
    float n_cos = max(thickness + sd, 0.0) / thickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    return normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
}
