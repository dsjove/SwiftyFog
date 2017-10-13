//
//  FoggyLogoRenderer.swift
//  FoggyAR
//
//  Created by Tobias Schweiger on 10/11/17.
//  Copyright © 2017 Object Computing Inc. All rights reserved.
//


import UIKit
import SceneKit
import ARKit
import SwiftyFog_iOS
import Vision

protocol FoggyLogoRendererDelegate:class {
	func qrCodeDetected(code: String)
	func loading(_ state : Bool)
}

class FoggyLogoRenderer : NSObject {

	private let qrDetector : QRDetection
	
	// SceneNode for the 3D models
	private var logoNode : SCNNode!
	private var lightbulbNode : SCNNode!
	private var largeSpotLightNode : SCNNode!
	private var qrValueTextNode : SCNNode!
	
	// Rotation variables
	private var hasAppliedHeading = false
	private var oldRotationY: CGFloat = 0.0

	private let sceneView : 	ARSCNView
	
	private var originalPosition = SCNVector3()
	
	public weak var delegate: FoggyLogoRendererDelegate?
	
	public init(sceneView : ARSCNView) {
		self.qrDetector = QRDetection(sceneView: sceneView, confidence: 0.8)
		self.sceneView = sceneView;
		
		super.init()
		
		self.sceneView.delegate = self
		self.qrDetector.delegate = self
		
		self.delegate?.loading(true)
	}
	
	func hitQRCode(node: SCNNode) -> Bool
	{
		return node == qrValueTextNode
	}
	
	func train(alive: Bool)
	{
		if !alive {
			self.sceneView.scene.fogColor = UIColor.red
			self.sceneView.scene.fogEndDistance = 0.045
		} else {
			self.sceneView.scene.fogEndDistance = 0
		}
	}
	
	func heading(heading: FogRational<Int64>)
	{
		//return
		
		let newRotationY = CGFloat(heading.num)
		let normDelta = newRotationY - oldRotationY
		let crossDelta = oldRotationY < newRotationY ? newRotationY - 360 - oldRotationY : 360 - oldRotationY + newRotationY
		let rotateBy = abs(normDelta) < abs(crossDelta) ? normDelta : crossDelta
		oldRotationY = newRotationY
		
		print("Received acceloremeter heading: \(heading) rotate by: \(rotateBy)")
		
		if let logoNode = logoNode {
			if hasAppliedHeading {
				logoNode.rotateAroundYAxis(by: -rotateBy.degreesToRadians, duration: 1)
			} else {
				logoNode.rotateToYAxis(to: -oldRotationY.degreesToRadians)
				hasAppliedHeading = true
			}
		}
	}
	
	public func lights(on : Bool) {
		if let lightbulbNode = lightbulbNode, let largeSpotLightNode = largeSpotLightNode {
			lightbulbNode.isHidden = !on
			largeSpotLightNode.isHidden = !on
		}
	}
	
}

extension FoggyLogoRenderer : ARSCNViewDelegate {
	
	func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
		
		// If this is our anchor, create a node
		if self.qrDetector.detectedDataAnchor?.identifier == anchor.identifier {
			
			//We rendered, so stop showing the activity indicator
			delegate?.loading(false)
			
			guard let virtualObjectScene = SCNScene(named: "art.scnassets/logo.scn") else {
				return nil
			}
			
			//Grab the required nodes
			logoNode = virtualObjectScene.rootNode.childNode(withName: "OCILogo", recursively: false)!
			let (minVec, maxVec) = logoNode.boundingBox
			logoNode.pivot = SCNMatrix4MakeTranslation((maxVec.x - minVec.x) / 2 + minVec.x, (maxVec.y - minVec.y) / 2 + minVec.y, 0)
			
			logoNode.position = SCNVector3(0, 0, 0)
			
			//Before render we have already received a rotation, set it to that
			//CULRPIT RIGHT HERE:
			logoNode.rotateToYAxis(to: -oldRotationY.degreesToRadians)
			
			lightbulbNode = virtualObjectScene.rootNode.childNode(withName: "lightbulb", recursively: false)
			largeSpotLightNode = virtualObjectScene.rootNode.childNode(withName: "largespot", recursively: false)
			
			//Hide the light bulb nodes initially
			lightbulbNode.isHidden = true
			largeSpotLightNode.isHidden = true
			
			//Get the text node for the QR code
			qrValueTextNode = virtualObjectScene.rootNode.childNode(withName: "QRCode", recursively: false)
			
			//Since we always receive the QR code before we render our nodes, assign the
			//existing scanned value to our geometry
			qrValueTextNode.setGeometryText(value: qrDetector.qrValue)
			
			//Wrapper node for adding nodes that we want to spawn on top of the QR code
			let wrapperNode = SCNNode()
			
			//Iterate over the child nodes to add them all to the wrapper node
			for child in virtualObjectScene.rootNode.childNodes {
				child.geometry?.firstMaterial?.lightingModel = .physicallyBased
				child.movabilityHint = .movable
				
				wrapperNode.addChildNode(child)
			}
			
			// Set its position based off the anchor
			wrapperNode.transform = SCNMatrix4(anchor.transform)
			
			return wrapperNode
		}
		
		return nil
	}
}

extension SCNNode
{
	func setGeometryText(value : String) {
		if let textGeometry = self.geometry as? SCNText {
			textGeometry.string = value
			textGeometry.alignmentMode = kCAAlignmentCenter
		}
	}
	
	func rotateToYAxis(to: CGFloat) {
		self.eulerAngles.y = Float(to)
	}
	
	func rotateAroundYAxis(by: CGFloat, duration : TimeInterval) {
		let action = SCNAction.rotate(by: by, around: SCNVector3(0, 1, 0), duration: duration)
		
		self.runAction(action, forKey: "rotatingYAxis")
		
		self.position = SCNVector3(0,0,0)
	}
}

extension FoggyLogoRenderer: QRDetectionDelegate {
	
		func foundQRValue(stringValue: String) {
			if let qrValueTextNode = qrValueTextNode {
				qrValueTextNode.setGeometryText(value: stringValue)
				delegate?.qrCodeDetected(code: stringValue)
				
				print("found qr value! logo transform: \(logoNode.position)")
			}
		}
		
		func detectRequestError(error: Error) {
			print("Error in QR: \(error.localizedDescription)")
		}
}

