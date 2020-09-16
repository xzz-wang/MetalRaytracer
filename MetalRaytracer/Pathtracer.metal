//
//  shaders.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/16/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#define EPSILON 0.0001
#define SUPPORT_NONQUAD TRUE
#define PI M_PI_F

#include <metal_stdlib>
#include <metal_raytracing>

#include "ShaderTypes.h"
#include "../Loki/loki_header.metal"

#include "BRDFs.metal"

//using namespace metal;
using namespace metal::raytracing;

struct BoundingBox{
    packed_float3 min;
    packed_float3 max;
};

inline ray generateInitRay(uint3 idx3, constant SceneData & scene, thread Loki &loki, bool center) {
    float deltaX, deltaY;
    
    if (center) {
        deltaX = 0.5;
        deltaY = 0.5;
    } else {
        deltaX = loki.rand();
        deltaY = loki.rand();
        deltaX = deltaY - trunc(deltaX);
        deltaY = deltaY - trunc(deltaY);
    }

    float3 target = scene.camera.imagePlaneTopLeft + ((float)idx3[0] + deltaX) * scene.camera.pixelRight + ((float)idx3[1] + deltaY) * scene.camera.pixelDown;
    float3 direction = normalize(target - scene.camera.origin);

    ray thisRay;
    thisRay.origin = scene.camera.origin;
    thisRay.direction = direction;
    thisRay.max_distance = INFINITY;
    thisRay.min_distance = EPSILON;
    return thisRay;
}

/**
 Conpute Phong model contribution: For Direct and Point lights, using half way vector
 */
inline float3 computeShading(Material material,
                             float3 inOmega,
                             float3 normal,
                             float3 hitPosition,
                             float3 lightPosition,
                             intersector<triangle_data, instancing> intersector,
                             instance_acceleration_structure accelerationStructure,
                             intersection_function_table<triangle_data, instancing> functionTable) {
    
    float3 toLight = lightPosition - hitPosition;
    float3 outOmega = normalize(toLight);
    float3 color = float3(0.0);
    
    ray shadowRay;
    shadowRay.direction = outOmega;
    shadowRay.max_distance = length(toLight) - EPSILON * 2;
    shadowRay.min_distance = 0.0;
    shadowRay.origin = hitPosition + EPSILON * shadowRay.direction;

    intersection_result<triangle_data, instancing> shadowIntersection = intersector.intersect(shadowRay, accelerationStructure, functionTable);

    if (shadowIntersection.distance <= 0) {
        
        float3 h = normalize(inOmega + toLight);
        float3 diffuseReflectance = material.diffuse * max(0.0f, dot(normal, outOmega));
        float3 specularReflectance = material.specular * pow(max(dot(normal, h), 0.0f), material.shininess);
        color = diffuseReflectance + specularReflectance;
    
    }

    return color;
    
}

inline float3 shadeQuad(float3 hitPosition,
                        float3 hitNormal,
                        float3 inOmega,
                        Material hitMaterial,
                        Quadlight light,
                        float3 lightPosition,
                        intersector<triangle_data, instancing> intersector,
                        instance_acceleration_structure accelerationStructure,
                        intersection_function_table<triangle_data, instancing> functionTable) {
    
    float3 color = float3(0.0, 0.0, 0.0);
    float3 toLight = lightPosition - hitPosition;
    float3 outOmega = normalize(toLight);
    
    // Setup the shadow ray
    ray shadowRay;
    shadowRay.direction = outOmega;
    shadowRay.max_distance = length(toLight) - EPSILON * 2;
    shadowRay.min_distance = 0.0;
    shadowRay.origin = hitPosition + EPSILON * shadowRay.direction;

    // Find intersection
    intersection_result<triangle_data, instancing> shadowIntersection = intersector.intersect(shadowRay, accelerationStructure, functionTable);

    // Shade the intersection it is not blocked
    if (shadowIntersection.distance <= 0) {
        Loki loki = Loki(1);
        Phong_Importance_BRDF brdfObj = Phong_Importance_BRDF(hitMaterial, &loki);
        float3 f = brdfObj.evaluate(inOmega, outOmega, hitNormal);

        float n_w = max(0.0, dot(hitNormal, outOmega));

        float3 lightNormal = normalize(cross(light.ac, light.ab));
        float dist_squared = dot(toLight, toLight);
        float n_l_w = max(0.0, dot(lightNormal, -outOmega)) / dist_squared;

        color = f * n_w * n_l_w;
    }

    return color;
}



/**
 Sample the contribution of a quad light
 */
inline float3 sampleQuadLight(intersector<triangle_data, instancing> intersector,
                              instance_acceleration_structure accelerationStructure,
                              intersection_function_table<triangle_data, instancing> functionTable,
                              Quadlight light,
                              float3 hitPosition,
                              Material hitMaterial,
                              float3 hitNormal,
                              float3 inOmega,
                              int lightsamples,
                              thread Loki &loki) {
    
    int root = sqrt(float(lightsamples));
    float3 color = float3(0.0, 0.0, 0.0);
        
    for(int i = 0; i < root; i++ ) {
        for(int j = 0; j < root; j++ ) {
            
            //Generate two random numbers
            float one = 1.0f;
            float x = fmod(loki.rand(), one);
            float y = fmod(loki.rand(), one);
            
            x = (i + x) / root;
            y = (j + y) / root;
            
            float3 position = light.a + x * light.ab + y * light.ac;

            color += shadeQuad(hitPosition, hitNormal, inOmega, hitMaterial, light, position, intersector, accelerationStructure, functionTable);
        }
    }

    float area = length(cross(light.ab, light.ac));
    return color * light.intensity * area / (root * root);
}




/**
 The main Kernel that handles pathtracing
 */
[[kernel]]
void pathtracingKernel(uint3 idx3 [[thread_position_in_grid]],
                       constant SceneData & scene [[buffer(0)]],
                       instance_acceleration_structure accelerationStructure [[buffer(1)]],
                        
                       device simd_float3 * triVertBuffer [[buffer(2)]],
                       device Material * triMaterialBuffer [[buffer(3)]],
                              
                       constant DirectionalLight * directionalLights [[buffer(4)]],
                       constant PointLight * pointLights [[buffer(5)]],
                       constant Quadlight * quadLights [[buffer(6)]],

                       device simd_float3 * outputBuffer [[buffer(7)]],
                       intersection_function_table<triangle_data, instancing> functionTable[[buffer(8)]]) {
    
    // Initialization
    int index = idx3.x + scene.imageSize.x * idx3.y;
    float3 outputColor = float3(0.0, 0.0, 0.0);
    intersector<triangle_data, instancing> intersector;
    
    // Loop through each sample per pixel
    for (int i = 0; i < scene.spp; i++) {
        Loki loki = Loki(idx3[0], idx3[1] + idx3[2], i);
        ray r = generateInitRay(idx3, scene, loki, i==0);
        
        // Properties to be populated
        float3 throughput = float3(1.0, 1.0, 1.0);

        // Loop according to depth
        for (int depth = 0; depth != scene.maxDepth; depth++) {
            
            float3 hitNormal = float3(0.0, 0.0, 0.0);
            
            // Find intersection
            intersector.accept_any_intersection(false);
            intersection_result<triangle_data, instancing> intersection;
            intersection = intersector.intersect(r, accelerationStructure);
            
            // stop if we did not hit anything
            if (intersection.distance <= 0) {
                outputColor = float3(1.0, 0.0, 0.0);
                break;
            }
            
            if (intersection.instance_id == 0) {
                // It's triangle
            }
                
            // Get the hitNormal and hitMaterial
            float3 v1 = triVertBuffer[3 * intersection.primitive_id + 0];
            float3 v2 = triVertBuffer[3 * intersection.primitive_id + 1];
            float3 v3 = triVertBuffer[3 * intersection.primitive_id + 2];
            
            float x = intersection.triangle_barycentric_coord.x;
            float y = intersection.triangle_barycentric_coord.y;
            float z = 1.0 - x - y;
            
            float3 hitPosition = v2 * x + v3 * y + v1 * z;
            
            if (length(hitNormal) == 0.0) {
                hitNormal = normalize(cross(v2 - v1, v3 - v1));
            }
            
            Material hitMaterial = triMaterialBuffer[intersection.primitive_id];
            
            
            // MARK: - NEE pathtracing contribution
            float3 Li = float3(0.0, 0.0, 0.0);
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
                    DirectionalLight thisLight = directionalLights[i];
                    float3 lightPos = hitPosition + MAXFLOAT * thisLight.toDirection;
                    outputColor += thisLight.brightness * computeShading(hitMaterial, -r.direction, hitNormal, hitPosition, lightPos, intersector, accelerationStructure, functionTable);
                }

                // Point Light
                for (int i = 0; i < scene.pointLightCount; i++) {
                    PointLight thisLight = pointLights[i];
                    outputColor += thisLight.brightness * computeShading(hitMaterial, -r.direction, hitNormal, hitPosition, thisLight.position, intersector, accelerationStructure, functionTable);
                }

                // Quadlight: Loop through each light
                for (int lightID = 0; lightID < scene.quadLightCount; lightID++) {
                    Li += sampleQuadLight(intersector, accelerationStructure, functionTable, quadLights[lightID], hitPosition, hitMaterial, hitNormal, -r.direction, scene.lightsamples, loki);
                } // End of quadLight Loop
                
            } else {
                if (hitMaterial.emission.x > 0 || hitMaterial.emission.y > 0 || hitMaterial.emission.z > 0) {
                    outputColor += throughput * hitMaterial.emission;
                    break;
                }
            } // End of NEE if
            
            outputColor += throughput * Li;
            
            // MARK: - Generate next ray
//            Phong_Hemisphere_BRDF brdfObj = Phong_Hemisphere_BRDF(hitMaterial, &loki);
//            Phong_Cosine_BRDF brdfObj = Phong_Cosine_BRDF(hitMaterial, &loki);
            Phong_Importance_BRDF brdfObj = Phong_Importance_BRDF(hitMaterial, &loki);
            float3 sample = brdfObj.sample(hitNormal, -r.direction);
            
            if (sample.x == -1.0 && sample.y == -1.0 && sample.z == -1.0) {
                break; // Reject the sample
            } 
                        
            // MARK: Calculate BRDF value
            float3 value = brdfObj.value(-r.direction, sample, hitNormal);
//            float3 value = brdfObj.evaluate(-r.direction, sample, hitNormal);
//            value *= dot(hitNormal, sample);
//            value /= brdfObj.pdf(sample, hitNormal, -r.direction);
            throughput = throughput * value;
            
            r.direction = sample;
            r.origin = hitPosition;
            
        }// End of depth loop
        
    } // End of sample loop
    
    outputBuffer[index] += outputColor   / (float)scene.spp;
}
