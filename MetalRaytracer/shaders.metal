//
//  shaders.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/16/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;


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
    rayBuffer[index] = thisRay;
}

inline RGBData float3ToRGB(simd_float3 value) {
    RGBData data = {static_cast<uint8_t>(value.x * 255), static_cast<uint8_t>(value.y * 255), static_cast<uint8_t>(value.z * 255), 255};
    return data;
}

kernel void shadingKernel(simd_uint2 idx2 [[thread_position_in_grid]],
                          constant SceneData & scene,
                          constant simd_float3 * vertexBuffer,
                          device Ray * rays,
                          device Intersection * intersections,
                          device Material * triMaterials,
                          device RGBData * outputBuffer) {
    // Get the current buffer index
    int index = idx2.x + scene.imageSize.x * idx2.y;
    
    // Check if there's an intersection
    Intersection hit = intersections[index];
    if (hit.distance < 0) {
        return;
    }
    
    Material hitMaterial = triMaterials[hit.primitiveIndex];
    simd_float3 v1 = vertexBuffer[3 * hit.primitiveIndex + 0];
    simd_float3 v2 = vertexBuffer[3 * hit.primitiveIndex + 1];
    simd_float3 v3 = vertexBuffer[3 * hit.primitiveIndex + 2];
    
    simd_float3 hitPosition = v1 * hit.coordinates.x + v2 * hit.coordinates.y + v3 * (1.0f - hit.coordinates.x - hit.coordinates.y);
    
    outputBuffer[index] = float3ToRGB(hitMaterial.emission);
}



