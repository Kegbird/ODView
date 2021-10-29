//
//  Extensions.swift
//  ODView
//
//  Created by Pietro Prebianca on 30/09/21.
//

import Foundation
import ARKit
import RealityKit
import KDTree

extension simd_float4x4 {
    var position: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension SCNVector3 : KDTreePoint
{
    public func getSimd() -> simd_float3
    {
        var simd = simd_float3()
        simd.x = self.x
        simd.y = self.y
        simd.z = self.z
        return simd
    }
    
    public func magnitude() -> Float
    {
        return sqrt(pow(self.x, 2)+pow(self.y, 2)+pow(self.z, 2))
    }
    
    public static func == (lhs: SCNVector3, rhs: SCNVector3) -> Bool
    {
        return lhs.x==rhs.x && lhs.y==rhs.y && lhs.z==rhs.z
    }
    
    public static var dimensions: Int {
        return 3
    }
    
    public func kdDimension(_ dimension: Int) -> Double {
        if dimension==0 { return Double(self.x) }
        else if dimension==1 { return Double(self.y) }
        return Double(self.z)
    }
    
    public func squaredDistance(to otherPoint: SCNVector3) -> Double {
        return Double(sqrt(pow(self.x-otherPoint.x,2)+pow(self.y-otherPoint.y,2)+pow(self.z-otherPoint.z,2)))
    }
    
    public func dotProduct(otherPoint: SCNVector3) -> Double
    {
        return Double(abs(self.x*otherPoint.x+self.y*otherPoint.y+self.z*otherPoint.z))
    }
    
    public func normalize() -> SCNVector3
    {
        let magnitude = self.magnitude()
        let x = self.x/magnitude
        let y = self.y/magnitude
        let z = self.z/magnitude
        return SCNVector3(x: x, y: y, z: z)
    }
}

extension KDTree
{
    public func euclideanClustering() -> [[SCNVector3]]
    {
        var clusters : [[SCNVector3]] = []
        //Flag true all points already addded to a cluster
        var processed : [Bool] = [Bool](repeating: false, count: self.elements.count)
        
        for i in 0..<self.elements.count
        {
            if(!processed[i])
            {
                var cluster : [SCNVector3] = []
                let point = self.elements[i] as! SCNVector3
                findCluster(point: point, processed: &processed, index: i, cluster: &cluster)
                if(cluster.count>Constants.MIN_NUMBER_POINTS_PER_CLUSTER)
                {
                    clusters.append(cluster)
                }
            }
        }
        
        return clusters
    }
    
    func findCluster(point: SCNVector3, processed: inout [Bool], index: Int, cluster: inout [SCNVector3])
    {
        if(!processed[index])
        {
            processed[index]=true
            cluster.append(point)
            //Get the max number of points withing distanceThreshold
            let nearbyPoints = self.nearestK(Constants.MAX_NUMBER_POINTS_PER_CLUSTER, to: self.elements[index], where: {p in p.squaredDistance(to: point as! Element )<Double(Constants.DISTANCE_THRESHOLD)})
            
            for i in 0..<nearbyPoints.count
            {
                //The corrisponding index of the nearest point in the
                //element list
                let j = self.elements.firstIndex(of: nearbyPoints[i])!
                if(!processed[j])
                {
                    let nearPoint = self.elements[j] as! SCNVector3
                    findCluster(point: nearPoint, processed: &processed, index: j, cluster: &cluster)
                }
            }
            
        }
    }
}

extension ARMeshGeometry {
    func classificationOf(faceWithIndex index: Int) -> ARMeshClassification
    {
        guard let classification = classification else { return .none }
        assert(classification.format == MTLVertexFormat.uchar, "Expected one unsigned char (one byte) per classification")
        let classificationPointer = classification.buffer.contents().advanced(by: classification.offset + (classification.stride * index))
        let classificationValue = Int(classificationPointer.assumingMemoryBound(to: CUnsignedChar.self).pointee)
        return ARMeshClassification(rawValue: classificationValue) ?? .none
    }
    
    func vertex(at index: UInt32) -> (Float, Float, Float) {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
        return vertex
    }
    
    func normal(at index: Int) -> SCNVector3
    {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
        let normalPointer = normals.buffer.contents().advanced(by: normals.offset + (normals.stride * index))
        let normal = normalPointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
        return SCNVector3(x: normal.0, y: normal.1, z: normal.2)
    }
    
    func vertexIndicesOf(faceWithIndex faceIndex: Int) -> [UInt32]
    {
        assert(faces.bytesPerIndex == MemoryLayout<UInt32>.size, "Expected one UInt32 (four bytes) per vertex index")
        let vertexCountPerFace = faces.indexCountPerPrimitive
        let vertexIndicesPointer = faces.buffer.contents()
        var vertexIndices = [UInt32]()
        vertexIndices.reserveCapacity(vertexCountPerFace)
        for vertexOffset in 0..<vertexCountPerFace {
            let vertexIndexPointer = vertexIndicesPointer.advanced(by: (faceIndex * vertexCountPerFace + vertexOffset) * MemoryLayout<UInt32>.size)
            vertexIndices.append(vertexIndexPointer.assumingMemoryBound(to: UInt32.self).pointee)
        }
        return vertexIndices
    }
    
    func normalOf(faceWithIndex faceIndex: Int) -> SCNVector3
    {
        let vertices = verticesOf(faceWithIndex: faceIndex)
        let a = SCNVector3(x: vertices[0].0, y: vertices[0].1, z: vertices[0].2)
        let b = SCNVector3(x: vertices[1].0, y: vertices[1].1, z: vertices[1].2)
        let c = SCNVector3(x: vertices[2].0, y: vertices[2].1, z: vertices[2].2)
        let ba = SIMD3(x: b.x-a.x, y: b.y-a.y, z: b.z-a.z)
        let ca = SIMD3(x: c.x-a.x, y: c.y-a.y, z: c.z-a.z)
        let normal = SCNVector3(cross(ba, ca)).normalize()
        return normal
    }
    
    //Return the vertices of the face indicized with id index
    func verticesOf(faceWithIndex index: Int) -> [(Float, Float, Float)] {
        let vertexIndices = vertexIndicesOf(faceWithIndex: index)
        let vertices = vertexIndices.map { vertex(at: $0) }
        return vertices
    }
    
    func centerOf(faceWithIndex index: Int) -> SCNVector3 {
        let vertices = verticesOf(faceWithIndex: index)
        let sum = vertices.reduce((0, 0, 0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
        let geometricCenter = SCNVector3(x: sum.0/3, y: sum.1/3, z: sum.2/3)
        return geometricCenter
    }
}

/*extension SCNNode {
    func centerAlign() {
        let (min, max) = boundingBox
        let extents = float3(max) - float3(min)
        simdPivot = float4x4(translation: ((extents / 2) + float3(min)))
    }
}

extension float4x4 {
    init(translation vector: float3) {
        self.init(float4(1, 0, 0, 0),
                  float4(0, 1, 0, 0),
                  float4(0, 0, 1, 0),
                  float4(vector.x, vector.y, vector.z, 1))
    }
}*/

extension  SCNGeometrySource {
    convenience init(_ source: ARGeometrySource, semantic: Semantic) {
        self.init(buffer: source.buffer, vertexFormat: source.format, semantic: semantic, vertexCount: source.count, dataOffset: source.offset, dataStride: source.stride)
    }
}

extension  SCNGeometryPrimitiveType {
    static  func  of(_ type: ARGeometryPrimitiveType) -> SCNGeometryPrimitiveType {
        switch type {
            case .line:
                return .line
            case .triangle:
                return .triangles
            @unknown default:
                return .line
        }
    }
}

extension  SCNGeometryElement {
    convenience init(_ source: ARGeometryElement) {
        let pointer = source.buffer.contents()
        let byteCount = source.count * source.indexCountPerPrimitive * source.bytesPerIndex
        let data = Data(bytesNoCopy: pointer, count: byteCount, deallocator: .none)
        self.init(data: data, primitiveType: .of(source.primitiveType), primitiveCount: source.count, bytesPerIndex: source.bytesPerIndex)
    }
}

extension  SCNGeometry
{
    convenience init(geometry: ARMeshGeometry)
    {
        let verticesSource = SCNGeometrySource(geometry.vertices, semantic: .vertex)
        
        let normalsSource = SCNGeometrySource(geometry.normals, semantic: .normal)
        
        let faces = SCNGeometryElement(geometry.faces)
        self.init(sources: [verticesSource, normalsSource], elements: [faces])
    }
}

extension ARMeshClassification {
    var description: String {
        switch self
        {
            case .ceiling: return "Ceiling"
            case .door: return "Door"
            case .floor: return "Floor"
            case .seat: return "Seat"
            case .table: return "Table"
            case .wall: return "Wall"
            case .window: return "Window"
            case .none: return "None"
            @unknown default: return "Unknown"
        }
    }
    
    var color: UIColor
    {
        switch self
        {
            case .ceiling: return .cyan
            case .door: return .brown
            case .floor: return .blue
            default: return .red
        }
    }
}
