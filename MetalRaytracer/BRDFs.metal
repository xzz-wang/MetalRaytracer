//
//  BRDFs.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 8/29/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;
using namespace raytracing;

/**
 Returns the value of BRDF with the given information.
 */
inline float3 evaluate(Material material, float3 inOmega, float3 outOmega, float3 normal) {
    // MARK: Add more supported brdf here

    float proj = dot(outOmega, normal);
    float3 r = 2.0 * proj * normal - outOmega;

    float3 f = material.diffuse / M_PI_F + material.specular * (material.shininess + 2) / (2 * M_PI_F) * pow(max(dot(r, inOmega), 0.0), material.shininess);
    return f;
}
