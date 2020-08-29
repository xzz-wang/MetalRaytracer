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
    uint8_t g = static_cast<uint8_t>(value.y > 255.0 ? 255 : value.y);
    uint8_t b = static_cast<uint8_t>(value.z > 255.0 ? 255 : value.z);
    RGBData data = {r, g, b, 255};
    return data;
}

/**
 Returns the value of BRDF with the given information.
 */
inline float3 evaluate(Material material, float3 inOmega, float3 outOmega, float3 normal) {
    // MARK: Add more supported brdf here
    
    float proj = dot(outOmega, normal);
    float3 r = 2.0 * proj * normal - outOmega;

    float3 f = material.diffuse / PI + material.specular * (material.shininess + 2) / (2 * PI) * pow(max(dot(r, inOmega), 0.0), material.shininess);
    return f;
}

/**
 Conpute Phong model contribution: For Direct and Point lights
 */
inline float3 computeShading(Material material, float3 inOmega, float3 normal, float3 hitPosition, float3 lightPosition, intersector<triangle_data> intersector, primitive_acceleration_structure accelerationStructure) {
    
    float3 toLight = lightPosition - hitPosition;
    float3 outOmega = normalize(toLight);
    float3 color = float3(0.0);
    
    ray shadowRay;
    shadowRay.direction = outOmega;
    shadowRay.max_distance = length(toLight) - EPSILON * 2;
    shadowRay.min_distance = 0.0;
    shadowRay.origin = hitPosition + EPSILON * shadowRay.direction;

    intersection_result<triangle_data> shadowIntersection = intersector.intersect(shadowRay, accelerationStructure);

    if (shadowIntersection.distance <= 0) {
        
        float3 h = normalize(inOmega + toLight);
        float3 diffuseReflectance = material.diffuse * max(0.0f, dot(normal, outOmega));
        float3 specularReflectance = material.specular * pow(max(dot(normal, h), 0.0f), material.shininess);
        color = diffuseReflectance + specularReflectance;
    
    }

    return color;
    
}

inline float3 shadeQuad(float3 hitPosition, float3 hitNormal, float3 inOmega, Material hitMaterial, Quadlight light, float3 lightPosition, intersector<triangle_data> intersector, primitive_acceleration_structure accelerationStructure) {
    float3 color = float3(0.0, 0.0, 0.0);
    float3 toLight = lightPosition - hitPosition;
    float3 outOmega = normalize(toLight);
    
    ray shadowRay;
    shadowRay.direction = outOmega;
    shadowRay.max_distance = length(toLight) - EPSILON * 2;
    shadowRay.min_distance = 0.0;
    shadowRay.origin = hitPosition + EPSILON * shadowRay.direction;

    intersection_result<triangle_data> shadowIntersection = intersector.intersect(shadowRay, accelerationStructure);

    if (shadowIntersection.distance <= 0) {
        
        float3 r = reflect(-outOmega, hitNormal);

        float3 f;

        f = hitMaterial.diffuse / PI +
        hitMaterial.specular / (2 * PI) * (hitMaterial.shininess + 2) * pow(dot(r, inOmega), hitMaterial.shininess);

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
inline float3 sampleQuadLight(intersector<triangle_data> intersector,
                              primitive_acceleration_structure accelerationStructure,
                              Quadlight light,
                              float3 hitPosition,
                              Material hitMaterial,
                              float3 hitNormal,
                              float3 inOmega,
                              int lightsamples,
                              int index) {
    
    int root = sqrt(float(lightsamples));
    float3 color = float3(0.0, 0.0, 0.0);
        
    for(int i = 0; i < root; i++ ) {
        for(int j = 0; j < root; j++ ) {
            
            //Generate two random numbers
            float one = 1.0f;
            Loki random1 = Loki(index, i, j);
            float x = modf(random1.rand(), one);
            Loki random2 = Loki(index, i, j+1);
            float y = modf(random2.rand(), one);
            
            x = (i + x) / root;
            y = (j + y) / root;
            
            float3 position = light.a + x * light.ab + y * light.ac;

            color += shadeQuad(hitPosition, hitNormal, inOmega, hitMaterial, light, position, intersector, accelerationStructure);
        }
    }

    float area = length(cross(light.ab, light.ac));
    return color * light.intensity * area / (root * root);
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
                    DirectionalLight thisLight = directionalLights[i];
                    float3 lightPos = hitPosition + MAXFLOAT * thisLight.toDirection;
                    outputColor += throughput * thisLight.brightness * computeShading(hitMaterial, -r.direction, hitNormal, hitPosition, lightPos, intersector, accelerationStructure);
                }

                // Point Light
                for (int i = 0; i < scene.pointLightCount; i++) {
                    PointLight thisLight = pointLights[i];
                    outputColor += throughput * thisLight.brightness * computeShading(hitMaterial, -r.direction, hitNormal, hitPosition, thisLight.position, intersector, accelerationStructure);
                }

                // Quadlight: Using stratification
                // Loop through each light
                float3 Li = float3(0.0, 0.0, 0.0);
                for (int lightID = 0; lightID < scene.quadLightCount; lightID++) {
                    
                    Li += sampleQuadLight(intersector, accelerationStructure, quadLights[lightID], hitPosition, hitMaterial, hitNormal, -r.direction, scene.lightsamples, index);
                } // End of quadLight Loop
                outputColor += throughput * Li;
                
            } else {
                outputColor += throughput * hitMaterial.emission;
            } // End of NEE if
            
            // TODO: Generate next ray
            
            
            // TODO: Calculate BRDF value
            
        } // End of hit condition
        // TODO: DEBUGING ONLY
        break;
    }// End of depth loop
    
    outputBuffer[index] = float3ToRGB(outputColor);
}
