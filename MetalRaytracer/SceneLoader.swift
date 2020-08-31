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

let PI: Float = 3.141592653589

class SceneLoader {
    
    private var scene: Scene!
    
    // Camera info
    var cameraOrigin: simd_float3?
    var cameraLookAt: simd_float3?
    var cameraUp: simd_float3?
    var fieldOfView: Float?

    // Geometries
    private var sphereTransforms: [simd_float4x4] = []
    private var sphereMaterial: [Material] = []
    
    private var rawVerts: [simd_float3] = []
    private var triIndices: [Int] = []
    private var triVerts: [simd_float3] = []
    private var triMaterial: [Material] = []

    // Material
    private var curMaterial: Material = Material()
    
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
            if thisCommand.prefix(1) == "#" { continue }
            
            // Debugging purpose only
            if thisCommand == "END" {
                break;
            }
            
            loadCommand(args: args)
        }
        
        
        
        setupCamera()
        
        scene.triVerts = triVerts
        scene.triMaterials = triMaterial
        createQuadlightTri()
        
        scene.sphereTransforms = sphereTransforms
        scene.sphereMaterials = sphereMaterial
        
        scene.makeLightPlaceholders()
        
        return scene
    }
    
    
    // MARK: - Parser for command line arguments
    
    /**
    Execute the command from the given substring array. args[0] is the command. Arguments starts at index 1.
     */
    private func loadCommand(args: [Substring]) {
        let command = args[0]
        
        // MARK: Part 1: Rendering Specification
        if command == "size" {
            if let arg1 = Int32(args[1]) {
                scene.imageSize.x = arg1
            }
            if let arg2 = Int32(args[2]) {
                scene.imageSize.y = arg2
            }
        } else if command == "maxDepth" || command == "maxdepth" {
            if let depth = Int(args[1]) {
                scene.maxDepth = depth
            }
        } else if command == "output" {
            scene.outputName = String(args[1])
        } else if command == "spp" {
            if let value = Int(args[1]) {
                scene.spp = value
            }
        } else if command == "lightsamples" {
            if let value = Int(args[1]) {
                scene.lightsamples = value
            }
        } else if command == "nee" || command == "nexteventestimation" {
            if args[1] == "off" || args[1] == "OFF" {
                scene.neeOn = false;
            } else {
                scene.neeOn = true;
            }
            
        // MARK: Part 2: Camera and Geometry
        } else if command == "camera" {
            cameraOrigin = loadVec3(args: args, startAt: 1)
            cameraLookAt = loadVec3(args: args, startAt: 4)
            cameraUp = loadVec3(args: args, startAt: 7)
            fieldOfView = Float(args[10])
                        
        } else if command == "sphere" {
            if let loc = loadVec3(args: args, startAt: 1), let radius = Float(args[4]) {
                var transform = curTransform
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
                
                triVerts.append(simd_make_float3(curTransform * simd_make_float4(rawVerts[indices[0]], 1.0)))
                triVerts.append(simd_make_float3(curTransform * simd_make_float4(rawVerts[indices[1]], 1.0)))
                triVerts.append(simd_make_float3(curTransform * simd_make_float4(rawVerts[indices[2]], 1.0)))
                
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
        } else if command == "ambient" {
            if let rgb = loadVec3(args: args, startAt: 1) {
                curMaterial.ambient = rgb
            }
        } else if command == "roughness" {
            if let value = Float(args[1]) {
                curMaterial.roughness = value
            }
            
        // MARK: Part 5: Lights
        } else if command == "directional" {
            if let direction = loadVec3(args: args, startAt: 1) {
                if let rgb = loadVec3(args: args, startAt: 4) {
                    let newLight = DirectionalLight(toDirection: direction, brightness: rgb)
                    scene.directionalLights.append(newLight)
                }
            }
        } else if command == "point" {
            if let position = loadVec3(args: args, startAt: 1) {
                if let rgb = loadVec3(args: args, startAt: 4) {
                    let newLight = PointLight(position: position, brightness: rgb)
                    scene.pointLights.append(newLight)
                }
            }
        } else if command == "quadLight" {
            var light = Quadlight()
            if let a = loadVec3(args: args, startAt: 1), let ab = loadVec3(args: args, startAt: 4), let ac = loadVec3(args: args, startAt: 7), let rgb = loadVec3(args: args, startAt: 10) {
                light.a = a
                light.ab = ab
                light.ac = ac
                light.intensity = rgb
                
                scene.quadLights.append(light)
            }
        }
    }
    
    
    private func setupCamera() {
        if cameraLookAt == nil || cameraOrigin == nil || fieldOfView == nil{
            print("Incomplete information of camera!")
            return
        }
        
        let aspectRatio = Float(scene.imageSize.x) / Float(scene.imageSize.y)
        let cameraLook = normalize(cameraLookAt! - cameraOrigin!)
        let imagePlaneRight = normalize(cross(cameraLook, cameraUp!))
        let imagePlaneUp = normalize(cross(imagePlaneRight, cameraLook))
        
        let temp = simd_float3(repeating: 0.0)
        var tempCamera = Camera(origin: temp, imagePlaneTopLeft: temp, pixelRight: temp, pixelDown: temp)
        
        tempCamera.origin = cameraOrigin!
        tempCamera.imagePlaneTopLeft = cameraOrigin!
        tempCamera.imagePlaneTopLeft += cameraLook / tan(PI * fieldOfView! / 360.0)
        tempCamera.imagePlaneTopLeft += imagePlaneUp - aspectRatio * imagePlaneRight
        tempCamera.pixelRight = (2.0 * aspectRatio / Float(scene.imageSize.x)) * imagePlaneRight
        tempCamera.pixelDown = (-2.0 / Float(scene.imageSize.y)) * imagePlaneUp
        
        scene.camera = tempCamera
    }
    
    
    private func createQuadlightTri() {
        for light in scene.quadLights {
            
            let lightMaterial = Material(diffuse: simd_float3(0.0, 0.0, 0.0),
                                         specular: simd_float3(0.0, 0.0, 0.0),
                                         emission: light.intensity,
                                         ambient: simd_float3(0.0, 0.0, 0.0),
                                         shininess: 1.0,
                                         roughness: 0.0)
            
            let v0 = light.a;
            let v1 = v0 + light.ac;
            let v2 = v1 + light.ab;
            let v3 = v0 + light.ab;
            
            // Triangle One
            scene.triMaterials.append(contentsOf: [lightMaterial, lightMaterial])
            scene.triVerts.append(contentsOf: [v0, v1, v2, v0, v2, v3])
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
