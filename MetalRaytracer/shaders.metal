//
//  shaders.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/16/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#define EPSILON 0.0001

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Represents a three dimensional ray which will be intersected with the scene. The ray type
// is customized using properties of the MPSRayIntersector.
struct Ray {
    packed_float3 origin;
    uint mask;
    packed_float3 direction;
    
    float maxDistance;
    
    float3 color;
};



constant unsigned int primes[] = {
    2,   3,  5,  7,
    11, 13, 17, 19,
    23, 29, 31, 37,
    41, 43, 47, 53,
};

// Algorithm copied from apple's example
/**
 Returns the i'th element of the Halton sequence using the d'th prime number as a
 base. The Halton sequence is a "low discrepency" sequence: the values appear
 random but are more evenly distributed then a purely random sequence. Each random
 value used to render the image should use a different independent dimension 'd',
 and each sample (frame) should use a different index 'i'. To decorrelate each
 pixel, a random offset can be applied to 'i'.
 */
float halton(unsigned int i, unsigned int d) {
    unsigned int b = primes[d];
    
    float f = 1.0f;
    float invB = 1.0f / b;
    
    float r = 0;
    
    while (i > 0) {
        f = f * invB;
        r = r + f * (i % b);
        i = i / b;
    }
    
    return r;
}



kernel void generateInitRay(simd_uint2 idx2 [[thread_position_in_grid]],
                            constant SceneData & scene,
                            device Ray* rayBuffer) {
    // Get the current buffer index
    int index = idx2.x + scene.imageSize.x * idx2.y;

    simd_float3 target = scene.camera.imagePlaneTopLeft + ((float)idx2[0] + 0.5) * scene.camera.pixelRight + ((float)idx2[1] + 0.5) * scene.camera.pixelDown;
    simd_float3 direction = normalize(target - scene.camera.origin);

    Ray thisRay = Ray();
    thisRay.direction = direction;
    thisRay.origin = scene.camera.origin;
    thisRay.maxDistance = INFINITY;
    thisRay.mask = 255;
    rayBuffer[index] = thisRay;
}



inline RGBData float3ToRGB(simd_float3 value) {
    RGBData data = {static_cast<uint8_t>(value.x * 255), static_cast<uint8_t>(value.y * 255), static_cast<uint8_t>(value.z * 255), 255};
    return data;
}




// This kernal generates shadow rays for use in shading.
kernel void neeKernel(simd_uint2 idx2 [[thread_position_in_grid]],
                          constant SceneData & scene [[buffer(0)]],
                          constant simd_float3 * vertexBuffer [[buffer(1)]],
                      
                          constant DirectionalLight * directionalLights [[buffer(2)]],
                          constant PointLight * pointLights [[buffer(3)]],
                          constant Quadlight * quadLights [[buffer(4)]],
                      
                          device Ray * rays [[buffer(5)]],
                          device Intersection * intersections [[buffer(6)]],
                          device Ray * shadowRays [[buffer(7)]],
                          constant Material * triMaterials[[buffer(8)]],
                          device RGBData * outputBuffer [[buffer(9)]]) {
    // Get the current buffer index
    int index = idx2.x + scene.imageSize.x * idx2.y;
    
    Intersection hit = intersections[index];
    
    // Check if there's an intersection
    if (hit.distance < 0) {
        return;
    }
    
    simd_float3 v1 = vertexBuffer[3 * hit.primitiveIndex + 0];
    simd_float3 v2 = vertexBuffer[3 * hit.primitiveIndex + 1];
    simd_float3 v3 = vertexBuffer[3 * hit.primitiveIndex + 2];
    
    simd_float3 hitPosition = v1 * hit.coordinates.x + v2 * hit.coordinates.y + v3 * (1.0f - hit.coordinates.x - hit.coordinates.y);
    
    // Generate sample for directional lights
    int shadowRayIndex = index * (scene.directLightCount + scene.pointLightCount + scene.lightsamples * scene.quadLightCount);
    for (int i = 0; i < scene.directLightCount; i++) {
        Ray thisRay;
        thisRay.direction = -directionalLights[i].toDirection;
        thisRay.origin = hitPosition + EPSILON * thisRay.direction;
        thisRay.maxDistance = INFINITY;
        shadowRays[shadowRayIndex++] = thisRay;
    }

    // Generate samples for point light
    for (int i = 0; i < scene.pointLightCount; i++) {
        float3 toLight = pointLights[i].position - hitPosition;
        Ray thisRay;
        thisRay.direction = normalize(toLight);
        thisRay.maxDistance = length(toLight) - EPSILON;
        thisRay.origin = hitPosition + EPSILON * thisRay.direction;
        shadowRays[shadowRayIndex++] = thisRay;
    }

    // Generate samples for quadLight
    int root = sqrt(float(scene.lightsamples));
    for (int lightID = 0; lightID < scene.quadLightCount; lightID++) {
        for (int i = 0; i < root; i++) {
            for (int j = 0; j < root; j++) {
                //Generate two random numbers
                float x = halton(index, 0);
                float y = halton(index, 1);

                // Stratify the sampling
                Quadlight light = quadLights[lightID];
                x = (i + x) / root;
                y = (j + y) / root;
                simd_float3 position = light.a + simd_float3(x, x, x) * light.ab + simd_float3(y, y, y) * light.ac;

                // Generate the ray
                Ray thisRay;
                float3 toLight = position - hitPosition;
                thisRay.direction = normalize(toLight);
                thisRay.origin = EPSILON * thisRay.direction + hitPosition;
                thisRay.maxDistance = length(toLight) - EPSILON;
                shadowRays[shadowRayIndex++] = thisRay;
            }
        }
    }
}


// This kernal use the shadow rays as well as surface information to shade the image.
kernel void shadingKernel(simd_uint2 idx2 [[thread_position_in_grid]],
                        constant SceneData & scene [[buffer(0)]],
                        constant simd_float3 * vertexBuffer [[buffer(1)]],

                        constant DirectionalLight * directionalLights [[buffer(2)]],
                        constant PointLight * pointLights [[buffer(3)]],
                        constant Quadlight * quadLights [[buffer(4)]],
                        constant Material * triMaterials[[buffer(5)]],

                        device Ray * rays [[buffer(6)]],
                        device Intersection * intersections [[buffer(7)]],
                        device Ray * shadowRays [[buffer(8)]],
                        device Intersection * shadowIntersections [[buffer(9)]],
                        device RGBData * outputBuffer [[buffer(10)]]) {
    
    // Get the current buffer index
    int index = idx2.x + scene.imageSize.x * idx2.y;
    
    Intersection hit = intersections[index];
    Ray ray = rays[index];
    Material hitMaterial = triMaterials[hit.primitiveIndex];
    
    // Check if there's an intersection
    if (hit.distance < 0) {
        return;
    }
    
    simd_float3 v1 = vertexBuffer[3 * hit.primitiveIndex + 0];
    simd_float3 v2 = vertexBuffer[3 * hit.primitiveIndex + 1];
    simd_float3 v3 = vertexBuffer[3 * hit.primitiveIndex + 2];
    
    simd_float3 hitPosition = v1 * hit.coordinates.x + v2 * hit.coordinates.y + v3 * (1.0f - hit.coordinates.x - hit.coordinates.y);
    
    int shadowRayIndex = index * (scene.directLightCount + scene.pointLightCount + scene.lightsamples * scene.quadLightCount);
    
    // Calculate Direct Light contribution
    
    // Calculate Point Light contribution
    
    // Calculate Quadlight contribution
    
    // Calculate next level


    simd_float3 outputColor = hitMaterial.emission;

    outputBuffer[index] = float3ToRGB(outputColor);
}

