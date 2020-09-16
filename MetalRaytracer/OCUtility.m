//
//  OCUtility.m
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 9/14/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

#import <simd/simd.h>
#import <Metal/MTLAccelerationStructureTypes.h>

//MTLPackedFloat3 generatePackedFloat3(simd_float3 input) {
//    MTLPackedFloat3 output;
//    for (int i = 0; i < 3; i++) {
//        output.elements[i] = input[i];
//    }
//
//    return output;
//}

//MTLPackedFloat4x3 generatePackedFloat4x3(simd_float4x3 input) {
//    MTLPackedFloat4x3 output;
//    for (int column = 0; column < 4; column++)
//        for (int row = 0; row < 3; row++)
//            output.columns[column] = input.columns[column];
//    return output;
//}
