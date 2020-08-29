//
//  BRDFs.metal
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 8/29/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//
#include <metal_stdlib>
#include "ShaderTypes.h"
#include "../Loki/loki_header.metal"
using namespace metal;
using namespace raytracing;

/**
 A helper method to rotoate a sample respect to the given surface normal
 */
inline float3 rotateSample(float3 sample, float3 normal) {
    float3 w = normal;
    float3 u, v, temp;
    if(normal[0] < 0.99) {
        temp = float3(1.0, 0.0, 0.0);
    }
    else {
        temp = float3(0.0, 1.0, 0.0);
    }
    u = normalize(cross(temp, w));
    v = cross(w, u);

    sample = normalize(sample);

    return sample.x * u + sample.y * v + sample.z * w;
}


class Phong_Importance_BRDF {
    
private:
    Material material;
    thread Loki* loki;
    
    float random() {
        return loki->rand();
    }
    
public:
    
    /**
     Constructor that sets the material
    */
    Phong_Importance_BRDF(Material material, thread Loki *setLoki ) {
        this->material = material;
        loki = setLoki;
    };
    
    /**
     Setting the material
     */
    void setMaterial(Material material) {
        this->material = material;
    };
    
    /**
     Returns the value of BRDF with the given information.
     Note: inOmega is the camera direction, outOmega is the light direction.
     */
    thread float3 evaluate(thread const float3 &inOmega, thread const float3 &outOmega, thread const float3 &normal) {
        // MARK: Add more supported brdf here

        float3 r = reflect(-outOmega, normal);

        float3 f = material.diffuse / M_PI_F +
                material.specular / (2 * M_PI_F) * (material.shininess + 2) * pow(dot(r, inOmega), material.shininess);
        return f;
    }
    
    /**
     Generate sample for the next ray
     * Using Phone Importance sampling technique
     */
    thread float3 sample(thread const float3 &normal,thread const float3 &inOmega) {
        // First, Split between the two terms
        float3 seed = normal * 70 + inOmega * 30;
        float randNum = random();

        float kd_avg = (material.diffuse[0] + material.diffuse[1] + material.diffuse[2]) / 3.0;
        float ks_avg = (material.specular[0] + material.specular[1] + material.specular[2]) / 3.0;
        float threshold = ks_avg / (kd_avg + ks_avg);

        // Determine if we sample specular or diffuse
        float3 r;
        if (randNum > threshold)
        {
            // Sample diffuse
            float x = random();
            float y = random();

            float theta = acos(sqrt(x));
            float phi = 2 * M_PI_F * y;
            float3 s = float3(cos(phi) * sin(theta), sin(phi) * sin(theta), cos(theta));

            return rotateSample(s, normal);
        } else {
            // Sample specular
            r = reflect(-inOmega, normal);
            float x = random();
            float y = random();
            
            float theta = acos(pow(x, 1.0 / (material.shininess + 1.0)));
            float phi = 2 * M_PI_F + y;
            float3 sample = float3(cos(phi) * sin(theta), sin(phi) * sin(theta), cos(theta));
            
            sample = rotateSample(sample, r);

            //Check if it's below the surface
            if (dot(sample, normal) < 0.0)
            {
                return float3(-1.0, -1.0, -1.0); // MARK: Important! Reject the sample!
            } else {
                return sample;
            }
        }
    }// End of Sample
    
    
    thread float3 pdf(thread const float3 &sample, thread const float3 &normal, thread const float3 &inOmega) {
        
        // Calculate the threshold
        float kd_avg = (material.diffuse[0] + material.diffuse[1] + material.diffuse[2]) / 3.0;
        float ks_avg = (material.specular[0] + material.specular[1] + material.specular[2]) / 3.0;
        float threshold = ks_avg / (kd_avg + ks_avg);

        float3 r = reflect(-inOmega, normal);

        float pdf = (1.0 - threshold) * dot(sample, normal) * M_1_PI_F
                    + threshold * (material.shininess + 1.0) / (2 * M_PI_F) * pow(dot(r, sample), material.shininess);

        return pdf;
    }
    
    thread float3 value(thread const float3 &inOmega, thread const float3 &outOmega, thread const float3 &normal) {
        return evaluate(inOmega, outOmega, normal) * dot(outOmega, normal) / pdf(outOmega, normal, inOmega);
    }
};

