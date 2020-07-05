//
//  SceneLoader.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 7/4/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd

class SceneLoader {
    private var transformationStack: [simd_float4x4] = [matrix_identity_float4x4]
    
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
        let scene = Scene()
        
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
        
        return scene
    }
    
    
    
    /*
     The first in the args array is the command
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
            
            
        // MARK: Part 2: Camera and Geometry
        } else if command == "camera" {
            scene.cameraOrigin = loadVec3(args: args, startAt: 1)
            scene.cameraLookAt = loadVec3(args: args, startAt: 4)
            scene.cameraUp = loadVec3(args: args, startAt: 7)
            scene.fieldOfView = Float(args[10])
            
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
            transformationStack.popLast()
            
        // MARK: Part 4: Material
        } else if command == "diffuse" {
            
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

}
