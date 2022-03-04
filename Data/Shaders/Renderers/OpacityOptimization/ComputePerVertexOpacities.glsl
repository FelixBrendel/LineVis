/*
 * BSD 2-Clause License
 *
 * Copyright (c) 2020 - 2021, Christoph Neuhauser
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

-- Compute

#version 450 core

layout (local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout (std430, binding = 2) buffer OpacityBufferPerVertex {
    float opacityBufferPerVertex[];
};

layout (std430, binding = 3) readonly buffer OpacityBufferPerSegment {
    float opacityBufferPerSegment[];
};

layout (std430, binding = 4) readonly buffer LineSegmentVisibilityBuffer {
    uint lineSegmentVisibilityBuffer[];
};

layout (std430, binding = 5) readonly buffer BlendingWeightParametrizationBuffer {
    float blendingWeightParametrizationBuffer[]; // per-vertex
};

uniform uint numLineVertices;
uniform float temporalSmoothingFactor = 0.1;

#include "FloatPack.glsl"

void main() {
    if (gl_GlobalInvocationID.x >= numLineVertices) {
        return;
    }

    float opacityOld = opacityBufferPerVertex[gl_GlobalInvocationID.x];
    float w = blendingWeightParametrizationBuffer[gl_GlobalInvocationID.x];

    /*const float EPSILON = 1e-5;
    bool shallInterpolate = abs(w - round(w)) > EPSILON;
    uint i;
    if (shallInterpolate) {
        i = uint(max(floor(w), 0.0));
    } else {
        i = uint(round(w));
    }
    float alpha = opacityBufferPerSegment[i];
    if (shallInterpolate) {
        float alpha_ip1 = opacityBufferPerSegment[i+1];
        alpha = mix(alpha, alpha_ip1, fract(w));
    }*/

    uint i = uint(floor(w));
    float alpha_i = opacityBufferPerSegment[i];
    float alpha_ip1 = opacityBufferPerSegment[i+1];
    uint visible_i = lineSegmentVisibilityBuffer[i];
    uint visible_ip1 = lineSegmentVisibilityBuffer[i+1];
    if (visible_i == 0) {
        alpha_i = opacityOld;
    }
    if (visible_ip1 == 0) {
        alpha_ip1 = opacityOld;
    }
    float alpha = mix(alpha_i, alpha_ip1, fract(w));

    float newValue = (1.0 - temporalSmoothingFactor) * opacityOld + temporalSmoothingFactor * alpha;
    opacityBufferPerVertex[gl_GlobalInvocationID.x] = newValue;
}
