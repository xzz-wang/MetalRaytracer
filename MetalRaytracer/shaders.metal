//
//  shaders.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 8/29/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
#define EPSILON 0.0001
using namespace metal;
using namespace raytracing;

// MARK: - Shader data post-processing

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



// MARK: - Intersection Functions

struct BoundingBoxResult {
    bool accept [[accept_intersection]];
    bool continueSearch [[continue_search]];
    float dist [[distance]];
    
};

inline float3 float3From4(float4 vector) {
    return float3(vector[0], vector[1], vector[2]);
}

[[intersection(bounding_box, triangle_data, instancing)]]
BoundingBoxResult sphereIntersectionFunction(float3 origin  [[origin]],
                                             float3 direction [[direction]],
                                             float minDistance [[min_distance]],
                                             float maxDistance [[max_distance]],
                                             uint primitive_id [[primitive_id]],
                                             device Sphere* sphereBuffer [[buffer(0)]],
                                             ray_data float3 & hitNormal [[payload]]) {
    
    device Sphere & thisSphere = sphereBuffer[primitive_id];
    float4x4 invMat = thisSphere.inverseTransformation;
    float3 newOrigin = float3From4(invMat * float4(origin, 1.0));
    float3 newDirection = float3From4(invMat * float4(direction, 0.0));
    
    float radius = 1.0;
    float3 center = float3(0.0, 0.0, 0.0);
    
    float3 oc = newOrigin - center;
    float a = dot(newDirection, newDirection);
    float b = 2 * dot(newDirection, oc);
    float c = dot(oc, oc) - radius * radius;
    
    float delta = b * b - 4 * a * c;
    
    BoundingBoxResult result;
    if (delta <= 0.0f) {
        result.accept = false;
        result.continueSearch = true;
        result.dist = 5.0;
        return result;
    }
    
//    hitNormal = origin;
//    if (primitive_id == 0) {
//        hitNormal += float3(0.5, 0.0, 0.0);
//    } else if (primitive_id == 1) {
//        hitNormal += float3(0.0, 0.5, 0.0);
//    }
//
//    BoundingBoxResult debugResult = BoundingBoxResult();
//    debugResult.accept = true;
//    debugResult.continueSearch = true;
//    debugResult.dist = delta;
//    return debugResult;
    
    delta = sqrt(delta);

    // Calculating Actually hit position
    float root1 = (- b + delta) / (2 * a);
    float root2 = (- b - delta) / (2 * a);
    
    float smallestRoot;
    if (root1 < root2) {
        if (root1 >= minDistance && root1 < maxDistance) {
            smallestRoot = root1;
        } else if (root2 >= minDistance && root2 < maxDistance){
            smallestRoot = root2;
        } else {
            result.accept = false;
            return result;
        }
    } else {
        if (root2 >= minDistance && root2 < maxDistance) {
            smallestRoot = root2;
        } else if (root1 >= minDistance && root1 < maxDistance){
            smallestRoot = root1;
        } else {
            result.accept = false;
            return result;
        }
    }
    

    
    result.dist = smallestRoot;

    float3 normal = newOrigin + newDirection * result.dist - center;
    normal = float3From4(transpose(thisSphere.inverseTransformation) * float4(normal, 1.0));
    hitNormal = normalize(normal);

    result.accept = true;
    return result;
}

