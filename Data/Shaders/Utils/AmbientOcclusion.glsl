layout (std430, binding = 13) readonly buffer AmbientOcclusionFactors {
    float ambientOcclusionFactors[];
};
layout (std430, binding = 14) readonly buffer AmbientOcclusionBlendingWeights {
    float ambientOcclusionBlendingWeights[];
};

uniform float ambientOcclusionStrength;
uniform uint numAoTubeSubdivisions;
uniform uint numLineVertices;
uniform uint numParametrizationVertices;

#define M_PI 3.14159265358979323846

float getAoFactor(float interpolatedVertexId, float phi) {
    uint lastLinePointIdx = uint(interpolatedVertexId);
    uint nextLinePointIdx = min(lastLinePointIdx + 1, numLineVertices - 1);
    float interpolationFactor = fract(interpolatedVertexId);

    float blendingWeightLast = ambientOcclusionBlendingWeights[lastLinePointIdx];
    float blendingWeightNext = ambientOcclusionBlendingWeights[nextLinePointIdx];
    float blendingWeight = mix(blendingWeightLast, blendingWeightNext, interpolationFactor);
    uint lastVertexIdx = uint(blendingWeight);
    uint nextVertexIdx = min(lastVertexIdx + 1, numParametrizationVertices - 1);
    float interpolationFactorLine = fract(blendingWeight);

    float circleIdxFlt = phi / (2.0 * M_PI) * float(numAoTubeSubdivisions);
    uint circleIdxLast = uint(circleIdxFlt) % numAoTubeSubdivisions;
    uint circleIdxNext = (circleIdxLast + 1) % numAoTubeSubdivisions;
    float interpolationFactorCircle = fract(circleIdxFlt);

    float aoFactor00 = ambientOcclusionFactors[circleIdxLast + numAoTubeSubdivisions * lastVertexIdx];
    float aoFactor01 = ambientOcclusionFactors[circleIdxLast + numAoTubeSubdivisions * nextVertexIdx];
    float aoFactor10 = ambientOcclusionFactors[circleIdxNext + numAoTubeSubdivisions * lastVertexIdx];
    float aoFactor11 = ambientOcclusionFactors[circleIdxNext + numAoTubeSubdivisions * nextVertexIdx];
    float aoFactor0 = mix(aoFactor00, aoFactor01, interpolationFactorLine);
    float aoFactor1 = mix(aoFactor10, aoFactor11, interpolationFactorLine);
    float aoFactor = mix(aoFactor0, aoFactor1, interpolationFactorCircle);
    return 1.0 - ambientOcclusionStrength + ambientOcclusionStrength * aoFactor;
}
