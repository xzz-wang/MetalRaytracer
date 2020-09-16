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
//        var returnValue = mat
//        returnValue[3, 0] += displacement.x
//        returnValue[3, 1] += displacement.y
//        returnValue[3, 2] += displacement.z
        
        let matrix = SCNMatrix4Translate(SCNMatrix4Identity, CGFloat(displacement.x), CGFloat(displacement.y), CGFloat(displacement.z))

        return mat * simd_float4x4(matrix)
    }
    
    /**
     Returns the matrix after rotation with given information.
     */
    static func rotate(mat: simd_float4x4, by radians: Float, around axis: simd_float3) -> simd_float4x4 {
        let normAxis = normalize(axis)
        let matrix = SCNMatrix4Rotate(SCNMatrix4Identity, CGFloat(radians), CGFloat(axis.x), CGFloat(normAxis.y), CGFloat(normAxis.z))
        
        return mat * simd_float4x4(matrix)
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
    
    static func sphereBBoxOf(transform: simd_float4x4) -> BoundingBox {
        var vertices: [simd_float3] = []
        let r: Float = 1.0
        vertices.append(simd_float3(r, r, r))
        vertices.append(simd_float3(-r, r, r))
        vertices.append(simd_float3(r, -r, r))
        vertices.append(simd_float3(r, r, -r))
        vertices.append(simd_float3(-r, -r, r))
        vertices.append(simd_float3(-r, r, -r))
        vertices.append(simd_float3(r, -r, -r))
        vertices.append(simd_float3(-r, -r, -r))
        
        var min: simd_float3?
        var max: simd_float3?
        for vertex in vertices {
            let transformed = transform * simd_float4(vertex, 1.0)
            if min == nil && max == nil {
                min = simd_float3(transformed.x, transformed.y, transformed.z)
                max = simd_float3(transformed.x, transformed.y, transformed.z)
            } else {
                for i in 0..<3 {
                    min![i] = min![i] > transformed[i] ? transformed[i] : min![i]
                    max![i] = max![i] < transformed[i] ? transformed[i] : max![i]
                }
            }
        }
        
        return BoundingBox(min: generatePackedFloat3(input: min!),
                           max: generatePackedFloat3(input: max!))
    }
    
    static func generatePackedFloat3(input: simd_float3) -> MTLPackedFloat3 {
        var output: MTLPackedFloat3 = MTLPackedFloat3()
        output.x = input.x
        output.y = input.y
        output.z = input.z
        return output
    }
}

