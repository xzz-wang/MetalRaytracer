//
//  shaders.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/16/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#define EPSILON 0.0001
#define SUPPORT_NONQUAD FALSE

#include <metal_stdlib>
#include <metal_raytracing>
#include "ShaderTypes.h"
#include "../Loki/loki_header.metal"

//using namespace metal;
using namespace metal::raytracing;

struct BoundingBox{
    packed_float3 min;
    packed_float3 max;
};


inline ray generateInitRay(uint2 idx2, constant SceneData & scene) {

    float3 target = scene.camera.imagePlaneTopLeft + ((float)idx2[0] + 0.5) * scene.camera.pixelRight + ((float)idx2[1] + 0.5) * scene.camera.pixelDown;
    float3 direction = normalize(target - scene.camera.origin);

    ray thisRay;
    thisRay.origin = scene.camera.origin;
    thisRay.direction = direction;
    thisRay.max_distance = INFINITY;
    return thisRay;
}



inline RGBData float3ToRGB(simd_float3 value) {
    value = value * 255;
    uint8_t r = static_cast<uint8_t>(value.x > 255.0 ? 255 : value.x);
    uint8_t g = static_cast<uint8_t>(value.x > 255.0 ? 255 : value.y);
    uint8_t b = static_cast<uint8_t>(value.x > 255.0 ? 255 : value.z);
    RGBData data = {r, g, b, 255};
    return data;
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


/**
 Cast shadow ray and calculate the contribution for a directional light
 */
inline float3 sampleDirectLight(intersector<triangle_data> intersector,
                               primitive_acceleration_structure accelerationStructure,
                               DirectionalLight light,
                               float3 hitPosition,
                               Material hitMaterial,
                               float3 hitNormal,
                               float3 inOmega) {
    float3 color = float3(0.0);
    ray shadowRay;
    shadowRay.direction = -light.toDirection;
    shadowRay.origin = hitPosition + EPSILON * shadowRay.direction;
    shadowRay.max_distance = INFINITY;

    intersection_result<triangle_data> shadowIntersection = intersector.intersect(shadowRay, accelerationStructure);

    // check if the light is blocked
    if (shadowIntersection.distance <= 0) {
        // Take into account of the light contribution
        color = computeShading(hitMaterial, inOmega, light.toDirection, hitNormal, light.brightness);
    }
    
    return color;
}


/**
 Cast shadow ray and calculate the contribution for a point light
 */
inline float3 samplePointLight(intersector<triangle_data> intersector,
                               primitive_acceleration_structure accelerationStructure,
                               PointLight light,
                               float3 hitPosition,
                               Material hitMaterial,
                               float3 hitNormal,
                               float3 inOmega) {
    float3 color = float3(0.0);
    
    float3 toLight = light.position - hitPosition;
    ray shadowRay;
    shadowRay.direction = normalize(toLight);
    shadowRay.max_distance = length(toLight) - EPSILON * 2;
    shadowRay.min_distance = 0.0;
    shadowRay.origin = hitPosition + EPSILON * shadowRay.direction;

    intersection_result<triangle_data> shadowIntersection = intersector.intersect(shadowRay, accelerationStructure);

    if (shadowIntersection.distance <= 0) {
        // Take into account of the light contribution
        color = computeShading(hitMaterial, inOmega, shadowRay.direction, hitNormal, light.brightness);
    }
    
    return color;
}


template<typename T>
inline T interpolateVertexAttribute(device T *attributes, unsigned int primitiveIndex, float2 uv) {
    // Barycentric coordinates sum to one.
    float3 uvw;
    uvw.xy = uv;
    uvw.z = 1.0f - uvw.x - uvw.y;

    // Look up value for each vertex.
    T T0 = attributes[primitiveIndex * 3 + 0];
    T T1 = attributes[primitiveIndex * 3 + 1];
    T T2 = attributes[primitiveIndex * 3 + 2];

    // Compute sum of vertex attributes weighted by barycentric coordinates.
    return uvw.x * T0 + uvw.y * T1 + uvw.z * T2;
}



/**
 The main Kernel that handles pathtracing
 */
[[kernel]]
void pathtracingKernel(uint2 idx2 [[thread_position_in_grid]],
                       constant SceneData & scene [[buffer(0)]],
                       primitive_acceleration_structure accelerationStructure [[buffer(1)]],
                        
                       constant simd_float3 * triVertBuffer [[buffer(2)]],
                       constant Material * triMaterialBuffer [[buffer(3)]],
                              
                       constant DirectionalLight * directionalLights [[buffer(4)]],
                       constant PointLight * pointLights [[buffer(5)]],
                       constant Quadlight * quadLights [[buffer(6)]],

                       device RGBData* outputBuffer [[buffer(7)]]) {
    // Generate initial ray
    ray r = generateInitRay(idx2, scene);
    intersector<triangle_data> intersector;
    int index = idx2.x + scene.imageSize.x * idx2.y;
    
    // Properties to be populated
    float3 outputColor = float3(0.0, 0.0, 0.0);
    float3 throughput = float3(1.0, 1.0, 1.0);

    
    // Loop according to depth
    for (int depth = 0; depth != scene.maxDepth; depth++) {
        
        // Find intersection
        intersector.accept_any_intersection(false);
        intersection_result<triangle_data> intersection;
        intersection = intersector.intersect(r, accelerationStructure);
        
        // Shade the intersection if there's a hit
        if (intersection.distance > 0) {
            
            // Get the hitNormal and hitMaterial
            float3 v1 = triVertBuffer[3 * intersection.primitive_id + 0];
            float3 v2 = triVertBuffer[3 * intersection.primitive_id + 1];
            float3 v3 = triVertBuffer[3 * intersection.primitive_id + 2];
            
            float x = intersection.triangle_barycentric_coord.x;
            float y = intersection.triangle_barycentric_coord.y;
            float z = 1.0 - x - y;
            
            float3 hitPosition = v2 * x + v3 * y + v1 * z;
//            float3 hitPosition = r.origin + intersection.distance * r.direction;
            float3 hitNormal = normalize(cross(v2 - v1, v3 - v1));
            Material hitMaterial = triMaterialBuffer[intersection.primitive_id];
            
            
            // MARK: - NEE pathtracing contribution
            if (scene.neeOn == 1) {
                
                // check if we have hit a light
                if (hitMaterial.emission.x > 0 || hitMaterial.emission.y > 0 || hitMaterial.emission.z > 0) {
                    // Check if this is the first layer: include the light if this is the first layer
                    outputColor += depth == 0 ? throughput * hitMaterial.emission : 0.0;
                    break;
                }

                // We did not hit a light, calculate the light contribution
                intersector.accept_any_intersection(true); // Shadow ray mode
                
                // Direct Light
                for (int i = 0; i < scene.directLightCount; i++) {
                    outputColor += throughput * sampleDirectLight(intersector, accelerationStructure, directionalLights[i], hitPosition, hitMaterial, hitNormal, -r.direction);
                }

                // Point Light
                for (int i = 0; i < scene.pointLightCount; i++) {
                    outputColor += throughput * samplePointLight(intersector, accelerationStructure, pointLights[i], hitPosition, hitMaterial, hitNormal, -r.direction);
                }

                // Quadlight: Using stratification
                int root = sqrt(float(scene.lightsamples));
                // Loop through each light
                for (int lightID = 0; lightID < scene.quadLightCount; lightID++) {
                    float3 color = float3(0.0, 0.0, 0.0);
                    Quadlight thisLight = quadLights[lightID];

                    // Loop through each sample
                    for (int i = 0; i < root; i++) {
                        for (int j = 0; j < root; j++) {
                            //Generate two random numbers
                            float one = 1.0f;
                            Loki random1 = Loki(index, i, j);
                            float x = modf(random1.rand(), one);
                            Loki random2 = Loki(index, i, j+1);
                            float y = modf(random2.rand(), one);

                            // Stratify the sampling
                            x = (i + x) / root;
                            y = (j + y) / root;
                            float3 position = thisLight.a + simd_float3(x, x, x) * thisLight.ab + simd_float3(y, y, y) * thisLight.ac;

                            // Generate the ray
                            ray shadowRay;
                            float3 toLight = position - hitPosition;
                            shadowRay.direction = normalize(toLight);
                            shadowRay.origin = EPSILON * shadowRay.direction + hitPosition;
                            shadowRay.max_distance = length(toLight) - EPSILON;

                            // Check if it is blocked
                            intersection_result<triangle_data> shadowIntersection = intersector.intersect(shadowRay, accelerationStructure);

                            if (shadowIntersection.distance <= 0){
                                color += computeShading(hitMaterial, -r.direction, toLight, hitNormal, thisLight.intensity);
                            }

                        }
                    } // End of sample loops

                    float area = length(cross(thisLight.ab, thisLight.ac));
                    outputColor += color * area / (float)scene.lightsamples;

                } // End of quadLight Loop
            } // End of NEE if
            
            // TODO: Generate next ray
            
            // TODO: Calculate BRDF value
            
        } // End of hit condition
        // TODO: DEBUGING ONLY
        break;
    }// End of depth loop
    
    outputBuffer[index] = float3ToRGB(outputColor);
}
