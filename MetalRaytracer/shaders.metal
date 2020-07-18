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
