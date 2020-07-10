//
//  TypesAndConstants.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/25/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import MetalPerformanceShaders

let PI: Float = 3.1415926535

struct camera {
    var origin: simd_float3
    var imagePlaneTopLeft: simd_float3
    var pixelRight: simd_float3
    var pixelDown: simd_float3
}

struct quadlight {
    let a: simd_float3
    let ab: simd_float3
    let ac: simd_float3
    let intensity: simd_float3
}

struct material {
    var diffuse: simd_float3
    var specular: simd_float3
    var emission: simd_float3
    
    var shininess: Float
    var roughness: Float
    
    init() {
        diffuse = simd_float3(repeating: 0.0)
        specular = simd_float3(repeating: 0.0)
        emission = simd_float3(repeating: 0.0)
        
        shininess = 1.0
        roughness = 0.0
    }
    
}

typealias Ray = MPSRayOriginDirection
typealias Intersection = MPSIntersectionDistancePrimitiveIndexCoordinates
