//
//  Engine.swift
//  SwiftyFog
//
//  Created by David Giovannini on 7/29/17.
//  Copyright © 2017 Object Computing Inc. All rights reserved.
//

import Foundation
import SwiftyFog

class Engine {
	var registrations = [MQTTRegistration]()
    var mqtt: MQTTBridge! {
		didSet {
			registrations = mqtt.registerTopics([
				("engine/powered", powered),
				("engine/calibrated", calibrated)
			])
		}
    }
	var oldPower = FogRational(num: Int64(0), den: 0)
	var newPower = FogRational(num: Int64(0), den: 1)
	
	let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
	
	init() {
		timer.schedule(deadline: .now(), repeating: .milliseconds(250/*40*/), leeway: .milliseconds(10))
		timer.setEventHandler { [weak self] in
			self?.onTimer()
		}
	}
	
	func start() {
		timer.resume()
	}
	
	func stop() {
		timer.suspend()
	}
	
	deinit {
		timer.cancel()
	}
	
	func calibrated(msg: MQTTMessage) {
		//let calibration: FogRational<Int64> = msg.payload.fogExtract()
	}
	
	func powered(msg: MQTTMessage) {
		//let power: FogRational<Int64> = msg.payload.fogExtract()
	}
	
	var calibration = FogRational(num: Int64(15), den: 100) {
		didSet {
			if !(calibration == oldValue) {
				var data  = Data(capacity: MemoryLayout.size(ofValue: newPower))
				data.fogAppend(calibration)
				mqtt.publish(MQTTPubMsg(topic: "thejoveexpress/engine/calibrate", payload: data))
			}
		}
	}
	
	func onTimer() {
		if !(oldPower == newPower) {
			oldPower = newPower
			var data  = Data(capacity: MemoryLayout.size(ofValue: newPower))
			data.fogAppend(newPower)
			mqtt.publish(MQTTPubMsg(topic: "thejoveexpress/engine/power", payload: data))
		}
	}
}
