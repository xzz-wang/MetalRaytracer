//
//  TypesAndConstants.m
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/16/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//
#pragma once
#import <simd/simd.h>


// Types
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
    simd_float3 ambient;
    
    float shininess;
    float roughness;
};

struct DirectionalLight {
    simd_float3 toDirection;
    simd_float3 brightness;
};

struct PointLight {
    simd_float3 position;
    simd_float3 brightness;
};

struct Quadlight {
    simd_float3 a;
    simd_float3 ab;
    simd_float3 ac;
    simd_float3 intensity;
};


struct SceneData {
    struct Camera camera;
    simd_int2 imageSize;
    int quadLightCount;
    int directLightCount;
    int pointLightCount;
    int lightsamples;
    int neeOn; // A Boolean 1/0
    int rrOn;
    int maxDepth;
    int spp;
};

struct RGBData {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
};

struct Sphere {
    simd_float4x4 forwardTransformation;
    simd_float4x4 inverseTransformation;
    struct Material material;
};
