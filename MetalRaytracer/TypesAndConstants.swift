//
//  TypesAndConstants.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/25/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd

struct camera {
    let origin: simd_float3
    let imagePlaneTopLeft: simd_float3
    let pixelRight: simd_float3
    let PixelDown: simd_float3
}

struct quadlight {
    let a: simd_float3
    let ab: simd_float3
    let ac: simd_float3
    let intensity: simd_float3
}
