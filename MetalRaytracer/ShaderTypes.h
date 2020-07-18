//
//  TypesAndConstants.m
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/16/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <simd/SIMD.h>

// Types

typedef MPSRayOriginDirection Ray;
typedef MPSIntersectionDistancePrimitiveIndexCoordinates Intersection;

struct Camera {
    simd_float3 origin;
    simd_float3 imagePlaneTopLeft;
    simd_float3 pixelRight;
    simd_float3 pixelDown;
};

struct Material {
    simd_float3 diffuse;
    simd_float3 specular;
    simd_float3 emission;
    
    float shininess;
    float roughness;
};

struct quadlight {
    simd_float3 a;
    simd_float3 ab;
    simd_float3 ac;
    simd_float3 intensity;
};


struct SceneData {
    struct Camera camera;
    simd_int2 imageSize;
};
