//
//  Engine.swift
//  MetalRaytracer
//
//  Created by Xuezheng Wang on 6/29/20.
//  Copyright © 2020 Xuezheng Wang. All rights reserved.
//

import Foundation
import simd

class Engine {
    public func render(filename sourcePath: String) {
        // Load the Scene from the input file
        let loader = SceneLoader()
        guard let scene = loader.loadScene(path: sourcePath) else {
            print("Can not load the scene from path!")
            return
        }
        
        // TODO: Prepare the metal performance shader
        print(scene)
        

    }
    
    
    
}
