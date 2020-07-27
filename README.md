# MetalRaytracer
An offline retracer built on Metal frameworks.

###Input File Format Documentation

*Rendering Specification*
`size x y` Provides the size of the output image.
`maxDepth depth` Provides depth for the raytracer.
`output outputName` Provides output name for the raytracer.
`camera lookfromx lookfromy lookfromz lookatx lookaty lookatz upx upy upz fov` Provides information regarding camera's position and orientation.

*Geometries*
`sphere x y z radius` defines a sphere with given position and radius.
`vertex x y z` provides a vertex.
`tri v1 v2 v3` defines a triangle with given vertices. Vertices are specified using `vertex` command.

*Transformations*
`translate x y z` translate the current transformation matrix with given distance.
`rotate x y z angle` rotate by an angle (degree) about the given axis.
`scale x y z` scale with the given amount.
`pushTransform` push the current transformation matrix on to a stack.
`popTransform` pop a transformation matrix off the stack.

*Materials*
`diffuse r g b` specifies diffuse color.
`specular r g b` specifies specular color.
`emission r g b` specifies emission color.
`shininess s` specifies the shininess of the surface.
`ambient r g b` specifies the ambient color. Not recommended.
`roughness r` specifies the roughness of the surface. Applies to GGX Microfacet enabled surfaces.

*Lights*
`directional x y z r g b` specifies a directional light with given direction and color.
`point x y z r g b` specifies a point light with given position and color.
`quadlight a ab ac rgb` Each argument is a 3-d vector.
