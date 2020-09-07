//
//  shaders.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 8/29/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

inline RGBData float3ToRGB(float3 value) {
    value = value * 255;
    uint8_t r = static_cast<uint8_t>(value.x > 255.0 ? 255 : value.x);
    uint8_t g = static_cast<uint8_t>(value.y > 255.0 ? 255 : value.y);
    uint8_t b = static_cast<uint8_t>(value.z > 255.0 ? 255 : value.z);
    RGBData data = {r, g, b, 255};
    return data;
}


[[kernel]]
void convertToColorSpace(uint2 idx2 [[thread_position_in_grid]],
                         constant SceneData & scene [[buffer(0)]],
                         device float3 * shadingResult [[buffer(1)]],
                         device RGBData* imageData[[buffer(2)]]) {
    int index = idx2.x + scene.imageSize.x * idx2.y;
//        float3 color = shadingResult[index] / (float)scene.spp;
    float3 color = shadingResult[index];
    imageData[index] = float3ToRGB(color);
}


//[[intersection(bounding_box)]]
//bool sphereIntersectionFunction() {
//    
//}
