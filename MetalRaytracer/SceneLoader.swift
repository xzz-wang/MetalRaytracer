//
//  SceneLoader.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/4/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import MetalPerformanceShaders

class SceneLoader {
    
    private var scene: Scene!
    
    // Geometries
    private var sphereTransforms: [simd_float4x4] = []
    private var sphereMaterial: [material] = []
    
    private var rawVerts: [simd_float3] = []
    private var triIndices: [Int] = []
    private var triVerts: [simd_float3] = []
    private var triMaterial: [material] = []

    // Material
    private var curMaterial: material = material()
    
    // Transformation matrice
    private var transformationStack: [simd_float4x4] = [matrix_identity_float4x4]
    private var curTransform: simd_float4x4 {
        get {
            return transformationStack.last!
        }
    }
    
    // Returns the Scene reference
    public func loadScene(path: String) -> Scene? {
        // Get the raw text first
        var sceneRawText: String;
        do {
            sceneRawText = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            print(error)
            return nil
        }
        
        // Initialize the Scene
        scene = Scene()
        
        // Divide the string into useful info
        let inputByLine = sceneRawText.split(separator: "\n");
        // Loop through each line
        for line in inputByLine {
            let args = line.split(separator: " ")
            if args.count == 0 { continue }
            
            // Check for comments and empty lines
            let thisCommand = args[0]
            if thisCommand == "#" { continue }
            
            loadCommand(args: args, scene: scene)
        }
        
        setupMPS()
        
        
        return scene
    }
    
    
    
    // MARK: - Interaction with Metal Performance Shader
    
    private func setupMPS() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("The environment does not support Metal")
            return
        }
        
        // Make the vertex position buffer
        guard let vertexPositionBuffer = device.makeBuffer(bytes: triVerts, length: MemoryLayout<simd_float3>.size * triVerts.count, options: .storageModeShared) else {
            print("Failed to make vertexPositionBuffer!")
            return
        }
        
        // Make the acceleration structure
        scene.accelerationStructure = MPSTriangleAccelerationStructure(device: device)
        scene.accelerationStructure!.vertexBuffer = vertexPositionBuffer
        scene.accelerationStructure!.triangleCount = triVerts.count
        scene.accelerationStructure!.rebuild()
        
        scene.intersector = MPSRayIntersector.init(device: device)
    }

    
    
    // MARK: - Parser for command line arguments
    
    /**
    Execute the command from the given substring array. args[0] is the command. Arguments starts at index 1.
     */
    private func loadCommand(args: [Substring], scene: Scene) {
        let command = args[0]
        
        // MARK: Part 1: Rendering Specification
        if command == "size" {
            if let arg1 = Int32(args[1]) {
                scene.imageSize.x = arg1
            }
            if let arg2 = Int32(args[2]) {
                scene.imageSize.y = arg2
            }
        } else if command == "maxDepth" {
            if let depth = Int(args[1]) {
                scene.maxDepth = depth
            }
        } else if command == "output" {
            scene.outputName = String(args[1])
        } else if command == "spp" {
            if let value = Int(args[1]) {
                scene.spp = value
            }
            
        // MARK: Part 2: Camera and Geometry
        } else if command == "camera" {
            scene.cameraOrigin = loadVec3(args: args, startAt: 1)
            scene.cameraLookAt = loadVec3(args: args, startAt: 4)
            scene.cameraUp = loadVec3(args: args, startAt: 7)
            scene.fieldOfView = Float(args[10])
            
        } else if command == "sphere" {
            if let loc = loadVec3(args: args, startAt: 1), let radius = Float(args[4]) {
                var transform = curTransform * matrix_identity_float4x4
                transform = MML.translate(mat: transform, by: loc)
                transform = MML.scale(mat: transform, by: simd_float3(repeating: radius))
                
                sphereTransforms.append(transform)
                sphereMaterial.append(curMaterial)
            }
            
        } else if command == "vertex" {
            if let newVert = loadVec3(args: args, startAt: 1) {
                rawVerts.append(newVert)
            }
            
        } else if command == "tri" {
            if let indices = loadIdx3(args: args, startAt: 1) {
                let count = triIndices.count
                triIndices.append(count)
                triIndices.append(count + 1)
                triIndices.append(count + 2)
                
                triVerts.append(simd_make_float3(curTransform * simd_make_float4(rawVerts[indices[0]])))
                triVerts.append(simd_make_float3(curTransform * simd_make_float4(rawVerts[indices[1]])))
                triVerts.append(simd_make_float3(curTransform * simd_make_float4(rawVerts[indices[2]])))
                
                triMaterial.append(curMaterial)
            }
            
        // MARK: Part 3: Transforms
        } else if command == "translate" {
            if let dir = loadVec3(args: args, startAt: 1) {
                let newMat = MML.translate(mat: transformationStack.popLast()!, by: dir)
                transformationStack.append(newMat)
            }
            
        } else if command == "rotate" {
            if let radiansArg = Float(args[4]), let axis = loadVec3(args: args, startAt: 1) {
                let radians = radiansArg * PI / 180
                let newMat = MML.rotate(mat: transformationStack.popLast()!, by: radians, around: axis)
                transformationStack.append(newMat)
            }
            
        } else if command == "scale" {
            if let scale = loadVec3(args: args, startAt: 1) {
                let newMat = MML.scale(mat: transformationStack.popLast()!, by: scale)
                transformationStack.append(newMat)
            }
        } else if command == "pushTransform" {
            transformationStack.append(transformationStack.last!)
        } else if command == "popTransform" {
            transformationStack.removeLast()
            
        // MARK: Part 4: Material
        } else if command == "diffuse" {
            if let rgb = loadVec3(args: args, startAt: 1) {
                curMaterial.diffuse = rgb
            }
        } else if command == "specular" {
            if let rgb = loadVec3(args: args, startAt: 1) {
                curMaterial.specular = rgb
            }
        } else if command == "shininess" {
            if let value = Float(args[1]) {
                curMaterial.shininess = value
            }
        } else if command == "emission" {
            if let rgb = loadVec3(args: args, startAt: 1) {
                curMaterial.emission = rgb
            }
        } else if command == "roughness" {
            if let value = Float(args[1]) {
                curMaterial.roughness = value
            }
        }
    }
    
    
    private func loadVec3(args: [Substring], startAt startIdx: Int) -> simd_float3? {
        if let v1 = Float(args[startIdx]),
           let v2 = Float(args[startIdx + 1]),
           let v3 = Float(args[startIdx + 2]) {
            return simd_float3(x: v1, y: v2, z: v3)
        }
        return nil
    }
    
    
    private func loadIdx3(args: [Substring], startAt startIdx: Int) -> [Int]? {
        if let v1 = Int(args[startIdx]),
           let v2 = Int(args[startIdx + 1]),
           let v3 = Int(args[startIdx + 2]) {
            return [v1, v2, v3]
        }
        return nil
    }
    


}
