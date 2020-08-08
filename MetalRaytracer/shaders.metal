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
#include "loki_header.metal"
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
    value = value * 255;
    uint8_t r = static_cast<uint8_t>(value.x > 255.0 ? 255 : value.x);
    uint8_t g = static_cast<uint8_t>(value.x > 255.0 ? 255 : value.y);
    uint8_t b = static_cast<uint8_t>(value.x > 255.0 ? 255 : value.z);
    RGBData data = {r, g, b, 255};
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
        thisRay.maxDistance = length(toLight) - EPSILON * 2;
        thisRay.origin = hitPosition + EPSILON * thisRay.direction;
        shadowRays[shadowRayIndex++] = thisRay;
    }
    
    // Generate samples for quadLight
    // Using stratification
    int root = sqrt(float(scene.lightsamples));
    for (int lightID = 0; lightID < scene.quadLightCount; lightID++) {
        for (int i = 0; i < root; i++) {
            for (int j = 0; j < root; j++) {
                //Generate two random numbers
                float one = 1.0f;
                Loki random1 = Loki(index, i, j);
                float x = modf(random1.rand(), one);
                Loki random2 = Loki(index, i, j+1);
                float y = modf(random2.rand(), one);

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


/**
 Returns the value of BRDF with the given information.
 */
inline float3 evaluate(Material material, float3 inOmega, float3 outOmega, float3 normal, SceneData scene) {
    // MARK: Add more supported brdf here
    
    float3 r = reflect(-outOmega, normal);
    float3 f = material.diffuse / M_PI_F;
    f += material.specular / M_PI_2_F * (material.shininess + 2) * pow(dot(r, inOmega), material.shininess);
    
    return f;
}

/**
 Conpute Phong model contribution
 */
inline float3 computeShading(Material material, float3 inOmega, float3 toLight, float3 normal, float3 lightIntensity) {
    float3 h = normalize(inOmega + toLight);
    float3 diffuseReflectance = material.diffuse * max(0.0f, dot(normal, toLight));
    float3 specularReflectance = material.specular * pow(max(dot(normal, h), 0.0f), material.shininess);
    return lightIntensity * (diffuseReflectance + specularReflectance);
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
    // Check if there's an intersection
    if (hit.distance < 0) {
        return;
    }
    
    simd_float3 v1 = vertexBuffer[3 * hit.primitiveIndex + 0];
    simd_float3 v2 = vertexBuffer[3 * hit.primitiveIndex + 1];
    simd_float3 v3 = vertexBuffer[3 * hit.primitiveIndex + 2];
    
    simd_float3 hitPosition = v1 * hit.coordinates.x + v2 * hit.coordinates.y + v3 * (1.0f - hit.coordinates.x - hit.coordinates.y);
    simd_float3 hitNormal = normalize(cross(v2 - v1, v3 - v1));
    Ray ray = rays[index];
    Material hitMaterial = triMaterials[hit.primitiveIndex];
    
    int shadowRayIndex = index * (scene.directLightCount + scene.pointLightCount + scene.lightsamples * scene.quadLightCount);
    simd_float3 outputColor = simd_float3(0.0, 0.0, 0.0);
    
    // Calculate Direct Light contribution
    for (int i = 0; i < scene.directLightCount; i++) {
        Intersection thisShadowIntersection = shadowIntersections[shadowRayIndex];
        Ray thisShadowRay = shadowRays[shadowRayIndex++];
        DirectionalLight thisLight = directionalLights[i];

        // Check if it is occluded
        if (thisShadowIntersection.distance < 0) {
            outputColor += computeShading(hitMaterial, -ray.direction, thisShadowRay.direction, hitNormal, thisLight.brightness);
        }
    }

    // Calculate Point Light contribution
    for (int i = 0; i < scene.pointLightCount; i++) {
        Intersection thisShadowIntersection = shadowIntersections[shadowRayIndex];
        Ray thisShadowRay = shadowRays[shadowRayIndex++];
        PointLight thisLight = pointLights[i];

        // Check if it is occluded
        if (thisShadowIntersection.distance < 0) {
            outputColor += computeShading(hitMaterial, -ray.direction, thisShadowRay.direction, hitNormal, thisLight.brightness);
        }
    }
    
    // TODO: Calculate Quadlight contribution
//    int root = sqrt(float(scene.lightsamples));
//    for (int lightID = 0; lightID < scene.quadLightCount; lightID++) {
//
//        Quadlight thisLight = quadLights[lightID];
//        simd_float3 lightNormal = normalize(cross(thisLight.ac, thisLight.ab));
//        float lightArea = length(cross(thisLight.ab, thisLight.ac));
//        simd_float3 thisLightColor = simd_float3(0.0, 0.0, 0.0);
//
//        for (int i = 0; i < root; i++) {
//            for (int j = 0; j < root; j++) {
//                Intersection thisShadowIntersection = shadowIntersections[shadowRayIndex];
//                Ray thisShadowRay = shadowRays[shadowRayIndex++];
//
//                // Check if this ray is occluded
//                if (thisShadowIntersection.distance < 0) {
//                    simd_float3 inOmega = thisShadowRay.direction;
//                    simd_float3 outOmega = -ray.direction;
//                    float proj = dot(outOmega, hitNormal);
//                    simd_float3 r = 2.0 * simd_float3(proj, proj, proj) * hitNormal - outOmega;
//
//                    simd_float3 f;
//
////                    if (hitMaterial.brdf == Phong)
////                    {
////                        f = hitMaterial.diffuse / PI +
////                        hitMaterial.specular / TWO_PI * (hitMaterial.shininess + 2) * pow(glm::dot(r, inOmega), hitMaterial.shininess);
////                    } else if (hitMaterial.brdf == GGX) {
////                        BRDF_GGX_Importance brdfObj;
////                        brdfObj.setMaterial(hitMaterial);
////                        f = brdfObj.evaluate(inOmega, outOmega, hitNormal);
////                    }
//
//                    f = hitMaterial.diffuse / M_PI_F + hitMaterial.specular / M_PI_2_F * (hitMaterial.shininess + 2) * pow(dot(r, inOmega), hitMaterial.shininess);
//
//                    float n_w = max(0.0, dot(hitNormal, inOmega));
//
//                    float dist_squared = thisShadowRay.maxDistance * thisShadowRay.maxDistance;
//                    float n_l_w = max(0.0, dot(lightNormal, -inOmega)) / dist_squared;
//
//                    thisLightColor += f * n_w * n_l_w;
//                }
//            }
//        }
//
//        thisLightColor *= lightArea * thisLight.intensity / scene.lightsamples;
//        outputColor += thisLightColor;
//    }

    // TODO: Calculate next level


//    outputColor = hitMaterial.diffuse;

    outputBuffer[index] = float3ToRGB(outputColor);
}

