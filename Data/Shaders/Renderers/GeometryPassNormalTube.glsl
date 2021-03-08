-- VBO.Vertex

#version 430 core

layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in float vertexAttribute;
layout(location = 2) in vec3 vertexTangent;
layout(location = 3) in vec3 vertexNormal;
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
layout(location = 4) in uint vertexPrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
layout(location = 5) in float vertexLineHierarchyLevel;
#endif

out VertexData {
    vec3 linePosition;
    float lineAttribute;
    vec3 lineTangent;
    vec3 lineNormal;
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
    uint linePrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
    float lineLineHierarchyLevel;
#endif
};

#include "TransferFunction.glsl"

void main() {
    linePosition = (mMatrix * vec4(vertexPosition, 1.0)).xyz;
    lineAttribute = vertexAttribute;
    lineTangent = vertexTangent;
    lineNormal = vertexNormal;
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
    linePrincipalStressIndex = vertexPrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
    lineLineHierarchyLevel = vertexLineHierarchyLevel;
#endif
    gl_Position = mvpMatrix * vec4(vertexPosition, 1.0);
}

-- VBO.Geometry

#version 430 core

layout(lines) in;
//layout(triangle_strip, max_vertices = 32) out;
layout(triangle_strip, max_vertices = 64) out;

uniform vec3 cameraPosition;
uniform float lineWidth;

out vec3 fragmentPositionWorld;
#ifdef USE_SCREEN_SPACE_POSITION
out vec3 screenSpacePosition;
#endif
out float fragmentAttribute;
out vec3 fragmentNormal;
out vec3 fragmentTangent;
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
flat out uint fragmentPrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
flat out float fragmentLineHierarchyLevel;
#endif

#ifdef USE_BANDS
uniform float bandWidth;
uniform ivec3 psUseBands;
flat out int useBand;
#endif

in VertexData {
    vec3 linePosition;
    float lineAttribute;
    vec3 lineTangent;
    vec3 lineNormal;
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
    uint linePrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
    float lineLineHierarchyLevel;
#endif
} v_in[];

# define M_PI 3.14159265358979323846

void main() {
    vec3 linePosition0 = (mMatrix * vec4(v_in[0].linePosition, 1.0)).xyz;
    vec3 linePosition1 = (mMatrix * vec4(v_in[1].linePosition, 1.0)).xyz;

#ifdef USE_BANDS
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL) || defined(IS_PSL_DATA)
    useBand = psUseBands[v_in[0].linePrincipalStressIndex];
#else
    useBand = 1;
#endif

#ifdef BAND_RENDERING_THICK
    const float MIN_THICKNESS = 0.15;
#else
    const float MIN_THICKNESS = 1e-2;
#endif
    float thickness = useBand != 0 ? MIN_THICKNESS : 1.0f;

    const float lineRadius = (useBand != 0 ? bandWidth : lineWidth) * 0.5;
#else
    const float lineRadius = lineWidth * 0.5;
#endif
    const mat4 pvMatrix = pMatrix * vMatrix;

    vec3 circlePointsCurrent[NUM_TUBE_SUBDIVISIONS];
    vec3 circlePointsNext[NUM_TUBE_SUBDIVISIONS];
    vec3 vertexNormalsCurrent[NUM_TUBE_SUBDIVISIONS];
    vec3 vertexNormalsNext[NUM_TUBE_SUBDIVISIONS];

    vec3 normalCurrent = v_in[0].lineNormal;
    vec3 tangentCurrent = v_in[0].lineTangent;
    vec3 binormalCurrent = cross(tangentCurrent, normalCurrent);
    vec3 normalNext = v_in[1].lineNormal;
    vec3 tangentNext = v_in[1].lineTangent;
    vec3 binormalNext = cross(tangentNext, normalNext);

#ifdef USE_BANDS
    mat3 tangentFrameMatrixCurrent = mat3(normalCurrent, binormalCurrent, tangentCurrent);
    mat3 tangentFrameMatrixNext = mat3(normalNext, binormalNext, tangentNext);
#else
    mat3 tangentFrameMatrixCurrent = mat3(normalCurrent, binormalCurrent, tangentCurrent);
    mat3 tangentFrameMatrixNext = mat3(normalNext, binormalNext, tangentNext);
#endif

#ifdef USE_BANDS
    //thickness = 1.0f;
    for (int i = 0; i < NUM_TUBE_SUBDIVISIONS; i++) {
        float t = float(i) / float(NUM_TUBE_SUBDIVISIONS) * 2.0 * M_PI;
        float cosAngle = cos(t);
        float sinAngle = sin(t);
        vec3 localPosition = vec3(thickness * cosAngle, sinAngle, 0.0f);
        vec3 localNormal = vec3(cosAngle, thickness * sinAngle, 0.0f);
        //vec3 localNormal = vec3(cosAngle, sinAngle, 0.0f);
        //vec3 localNormal = vec3(thickness * cosAngle, sinAngle, 0.0f);
        circlePointsCurrent[i] = lineRadius * (tangentFrameMatrixCurrent * localPosition) + linePosition0;
        circlePointsNext[i] = lineRadius * (tangentFrameMatrixNext * localPosition) + linePosition1;
        vertexNormalsCurrent[i] = normalize(tangentFrameMatrixCurrent * localNormal);
        vertexNormalsNext[i] = normalize(tangentFrameMatrixNext * localNormal);
    }
#else
    const float theta = 2.0 * M_PI / float(NUM_TUBE_SUBDIVISIONS);
    const float tangetialFactor = tan(theta); // opposite / adjacent
    const float radialFactor = cos(theta); // adjacent / hypotenuse

    vec2 position = vec2(lineRadius, 0.0);
    for (int i = 0; i < NUM_TUBE_SUBDIVISIONS; i++) {
        vec3 point2D0 = tangentFrameMatrixCurrent * vec3(position, 0.0);
        vec3 point2D1 = tangentFrameMatrixNext * vec3(position, 0.0);
        circlePointsCurrent[i] = point2D0.xyz + linePosition0;
        circlePointsNext[i] = point2D1.xyz + linePosition1;
        vertexNormalsCurrent[i] = normalize(circlePointsCurrent[i] - linePosition0);
        vertexNormalsNext[i] = normalize(circlePointsNext[i] - linePosition1);

        // Add the tangent vector and correct the position using the radial factor.
        vec2 circleTangent = vec2(-position.y, position.x);
        position += tangetialFactor * circleTangent;
        position *= radialFactor;
    }
#endif


    // Emit the tube triangle vertices
    for (int i = 0; i < NUM_TUBE_SUBDIVISIONS; i++) {
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
        fragmentPrincipalStressIndex = v_in[0].linePrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
        fragmentLineHierarchyLevel = v_in[0].lineLineHierarchyLevel;
#endif
        fragmentAttribute = v_in[0].lineAttribute;
        fragmentTangent = tangentCurrent;

        gl_Position = pvMatrix * vec4(circlePointsCurrent[i], 1.0);
        fragmentNormal = vertexNormalsCurrent[i];
        fragmentPositionWorld = (mMatrix * vec4(circlePointsCurrent[i], 1.0)).xyz;
#ifdef USE_SCREEN_SPACE_POSITION
        screenSpacePosition = (vMatrix * vec4(circlePointsCurrent[i], 1.0)).xyz;
#endif
        EmitVertex();

        gl_Position = pvMatrix * vec4(circlePointsCurrent[(i+1)%NUM_TUBE_SUBDIVISIONS], 1.0);
        fragmentNormal = vertexNormalsCurrent[(i+1)%NUM_TUBE_SUBDIVISIONS];
        fragmentPositionWorld = (mMatrix * vec4(circlePointsCurrent[(i+1)%NUM_TUBE_SUBDIVISIONS], 1.0)).xyz;
#ifdef USE_SCREEN_SPACE_POSITION
        screenSpacePosition = (vMatrix * vec4(circlePointsCurrent[(i+1)%NUM_TUBE_SUBDIVISIONS], 1.0)).xyz;
#endif
        EmitVertex();


#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
        fragmentPrincipalStressIndex = v_in[1].linePrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
        fragmentLineHierarchyLevel = v_in[1].lineLineHierarchyLevel;
#endif
        fragmentAttribute = v_in[1].lineAttribute;
        fragmentTangent = tangentNext;

        gl_Position = pvMatrix * vec4(circlePointsNext[i], 1.0);
        fragmentNormal = vertexNormalsNext[i];
        fragmentPositionWorld = (mMatrix * vec4(circlePointsNext[i], 1.0)).xyz;
#ifdef USE_SCREEN_SPACE_POSITION
        screenSpacePosition = (vMatrix * vec4(circlePointsNext[i], 1.0)).xyz;
#endif
        EmitVertex();

        gl_Position = pvMatrix * vec4(circlePointsNext[(i+1)%NUM_TUBE_SUBDIVISIONS], 1.0);
        fragmentNormal = vertexNormalsNext[(i+1)%NUM_TUBE_SUBDIVISIONS];
        fragmentPositionWorld = (mMatrix * vec4(circlePointsNext[(i+1)%NUM_TUBE_SUBDIVISIONS], 1.0)).xyz;
#ifdef USE_SCREEN_SPACE_POSITION
        screenSpacePosition = (vMatrix * vec4(circlePointsNext[(i+1)%NUM_TUBE_SUBDIVISIONS], 1.0)).xyz;
#endif
        EmitVertex();

        EndPrimitive();
    }
}

-- Fragment

#version 450 core

in vec3 fragmentPositionWorld;
#ifdef USE_SCREEN_SPACE_POSITION
in vec3 screenSpacePosition;
#endif
in float fragmentAttribute;
in vec3 fragmentNormal;
in vec3 fragmentTangent;
#if defined(USE_PRINCIPAL_STRESS_DIRECTION_INDEX) || defined(USE_LINE_HIERARCHY_LEVEL)
flat in uint fragmentPrincipalStressIndex;
#endif
#ifdef USE_LINE_HIERARCHY_LEVEL
flat in float fragmentLineHierarchyLevel;
#ifdef USE_TRANSPARENCY
//uniform vec3 lineHierarchySliderLower;
//uniform vec3 lineHierarchySliderUpper;
uniform sampler1DArray lineHierarchyImportanceMap;
#else
uniform vec3 lineHierarchySlider;
#endif
#endif

#if defined(DIRECT_BLIT_GATHER)
out vec4 fragColor;
#endif

uniform vec3 cameraPosition;
uniform float lineWidth;
uniform vec3 backgroundColor;
uniform vec3 foregroundColor;

#ifdef USE_BANDS
flat in int useBand;
uniform float bandWidth;
#endif

#define M_PI 3.14159265358979323846

#include "TransferFunction.glsl"

#if !defined(DIRECT_BLIT_GATHER)
#include OIT_GATHER_HEADER
#endif

#define DEPTH_HELPER_USE_PROJECTION_MATRIX
#include "DepthHelper.glsl"
#include "Lighting.glsl"

void main() {
#if defined(USE_LINE_HIERARCHY_LEVEL) && !defined(USE_TRANSPARENCY)
    float slider = lineHierarchySlider[fragmentPrincipalStressIndex];
    if (slider > fragmentLineHierarchyLevel) {
        discard;
    }
#endif

    // 1) Determine variable ID along tube geometry
    const vec3 n = normalize(fragmentNormal);
    const vec3 v = normalize(cameraPosition - fragmentPositionWorld);
    const vec3 t = normalize(fragmentTangent);
    // Project v into plane perpendicular to t to get newV.
    vec3 helperVec = normalize(cross(t, v));
    vec3 newV = normalize(cross(helperVec, t));
    // Get the symmetric ribbon position (ribbon direction is perpendicular to line direction) between 0 and 1.
    // NOTE: len(cross(a, b)) == area of parallelogram spanned by a and b.
    vec3 crossProdVn = cross(newV, n);
    float ribbonPosition = length(crossProdVn);

    // Side note: We can also use the code below, as for a, b with length 1:
    // sqrt(1 - dot^2(a,b)) = len(cross(a,b))
    // Due to:
    // - dot(a,b) = ||a|| ||b|| cos(phi)
    // - len(cross(a,b)) = ||a|| ||b|| |sin(phi)|
    // - sin^2(phi) + cos^2(phi) = 1
    //ribbonPosition = dot(newV, n);
    //ribbonPosition = sqrt(1 - ribbonPosition * ribbonPosition);

    // Get the winding of newV relative to n, taking into account that t is the normal of the plane both vectors lie in.
    // NOTE: dot(a, cross(b, c)) = det(a, b, c), which is the signed volume of the parallelepiped spanned by a, b, c.
    if (dot(t, crossProdVn) < 0.0) {
        ribbonPosition = -ribbonPosition;
    }
    // Normalize the ribbon position: [-1, 1] -> [0, 1].
    //ribbonPosition = ribbonPosition / 2.0 + 0.5;
    ribbonPosition = clamp(ribbonPosition, -1.0, 1.0);


#ifdef USE_PRINCIPAL_STRESS_DIRECTION_INDEX
    vec4 fragmentColor = transferFunction(fragmentAttribute, fragmentPrincipalStressIndex);
#else
    vec4 fragmentColor = transferFunction(fragmentAttribute);
#endif

#if defined(USE_LINE_HIERARCHY_LEVEL) && defined(USE_TRANSPARENCY)
    //float lower = lineHierarchySliderLower[fragmentPrincipalStressIndex];
    //float upper = lineHierarchySliderUpper[fragmentPrincipalStressIndex];
    //fragmentColor.a *= (upper - lower) * fragmentLineHierarchyLevel + lower;
    fragmentColor.a *= texture(
            lineHierarchyImportanceMap, vec2(fragmentLineHierarchyLevel, float(fragmentPrincipalStressIndex))).r;
#endif

    //fragmentColor = blinnPhongShading(fragmentColor, fragmentNormal);

    float absCoords = abs(ribbonPosition);
    float fragmentDepth = length(fragmentPositionWorld - cameraPosition);
    const float WHITE_THRESHOLD = 0.7;
#ifdef USE_BANDS
    float EPSILON = clamp(fragmentDepth * 0.001 / (useBand != 0 ? bandWidth : lineWidth), 0.0, 0.49);
#else
    float EPSILON = clamp(fragmentDepth * 0.001 / lineWidth, 0.0, 0.49);
#endif
    float coverage = 1.0 - smoothstep(1.0 - 2.0*EPSILON, 1.0, absCoords);
    //float coverage = 1.0 - smoothstep(1.0, 1.0, abs(ribbonPosition));
    vec4 colorOut = vec4(mix(fragmentColor.rgb, foregroundColor,
            smoothstep(WHITE_THRESHOLD - EPSILON, WHITE_THRESHOLD + EPSILON, absCoords)),
            fragmentColor.a * coverage);
    //colorOut.rgb = vec3(abs(length(cross(newV, n))));
    //colorOut.rgb = vec3((n + 1.0) * 0.5);

#if defined(DIRECT_BLIT_GATHER)
    // To counteract depth fighting with overlay wireframe.
    float depthOffset = -0.00001;
    if (absCoords >= WHITE_THRESHOLD - EPSILON) {
        depthOffset = 0.002;
    }
    //gl_FragDepth = clamp(gl_FragCoord.z + depthOffset, 0.0, 0.999);
    gl_FragDepth = convertLinearDepthToDepthBufferValue(
    convertDepthBufferValueToLinearDepth(gl_FragCoord.z) + fragmentDepth - length(fragmentPositionWorld - cameraPosition) - 0.0001);
#ifdef LOW_OPACITY_DISCARD
    if (colorOut.a < 0.01) {
        discard;
    }
#endif
    colorOut.a = 1.0;
    fragColor = colorOut;
#elif defined(USE_SYNC_FRAGMENT_SHADER_INTERLOCK)
    // Area of mutual exclusion for fragments mapping to the same pixel
    beginInvocationInterlockARB();
    gatherFragment(colorOut);
    endInvocationInterlockARB();
#elif defined(USE_SYNC_SPINLOCK)
    uint x = uint(gl_FragCoord.x);
    uint y = uint(gl_FragCoord.y);
    uint pixelIndex = addrGen(uvec2(x,y));
    /**
     * Spinlock code below based on code in:
     * Brüll, Felix. (2018). Order-Independent Transparency Acceleration. 10.13140/RG.2.2.17568.84485.
     */
    if (!gl_HelperInvocation) {
        bool keepWaiting = true;
        while (keepWaiting) {
            if (atomicCompSwap(spinlockViewportBuffer[pixelIndex], 0, 1) == 0) {
                gatherFragment(colorOut);
                memoryBarrier();
                atomicExchange(spinlockViewportBuffer[pixelIndex], 0);
                keepWaiting = false;
            }
        }
    }
#else
    gatherFragment(colorOut);
#endif
}
