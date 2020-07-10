//
//  Engine.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/29/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd
import MetalPerformanceShaders

class Engine {
    public func render(filename sourcePath: String) {
        // Load the Scene from the input file
        let loader = SceneLoader()
        guard let scene = loader.loadScene(path: sourcePath) else {
            print("Can not load the scene from path!")
            return
        }
        
        if !scene.isComplete() {
            print("Incomplete information in the scene!")
            return
        }
        
        // Start the rendering
        
        // MARK: Step 1: Generate all initial rays
        var initialRays: [Ray] = []
        for y in 0..<scene.imageSize.y {
            for x in 0..<scene.imageSize.x {
                let target = scene.camera!.imagePlaneTopLeft
                    + (Float(x) + 0.5) * scene.camera!.pixelRight
                    + (Float(y) + 0.5) * scene.camera!.pixelDown
                let direction = normalize(target - scene.camera!.origin)
                
                let thisRay = Ray(origin: scene.camera!.origin, direction: direction)
                initialRays.append(thisRay)
            }
        }
        
    }
}
