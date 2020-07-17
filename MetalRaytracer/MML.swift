//
//  MathFunctions.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/4/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import SceneKit

class MML {
    // Stands for my math library
    
    /**
     Generate a translation matrix
     */
    static func translate(mat: simd_float4x4, by displacement: simd_float3) -> simd_float4x4 {
        var returnValue = mat
        returnValue[3, 0] += displacement.x
        returnValue[3, 1] += displacement.y
        returnValue[3, 2] += displacement.z
        
        return returnValue
    }
    
    /**
     Returns the matrix after rotation with given information.
     */
    static func rotate(mat: simd_float4x4, by radians: Float, around axis: simd_float3) -> simd_float4x4 {
        let normAxis = normalize(axis)
        let matrix = SCNMatrix4Rotate(SCNMatrix4(mat), CGFloat(radians), CGFloat(axis.x), CGFloat(normAxis.y), CGFloat(normAxis.z))
        
        return simd_float4x4(matrix)
    }
    
    /**
     Returns the scale matrix with given information
     */
    static func scale(mat: simd_float4x4, by scale: simd_float3) -> simd_float4x4 {
        let matrix = SCNMatrix4Scale(SCNMatrix4(mat), CGFloat(scale.x), CGFloat(scale.y), CGFloat(scale.z))
        return simd_float4x4(matrix)
    }
    
    /**
    Clamp a comparable value to maximum and minimum
    */
    static func clamp<T: Comparable>(_ value: T, minVal: T, maxVal: T) -> T {
        return max(minVal, min(minVal, value))
    }
    
}

