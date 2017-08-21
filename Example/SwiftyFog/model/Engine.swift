//
//  Engine.swift
//  SwiftyFog
//
//  Created by David Giovannini on 7/29/17.
//  Copyright © 2017 Object Computing Inc. All rights reserved.
//

import Foundation
import SwiftyFog

protocol EngineDelegate: class {
	func onPowerConfirm(power: FogRational<Int64>)
	func onPowerCalibrated(power: FogRational<Int64>)
}

class Engine {
	private var broadcaster: MQTTBroadcaster?
	
	weak var delegate: EngineDelegate?
	
    var mqtt: MQTTBridge! {
		didSet {
			broadcaster = mqtt.broadcast(to: self, topics: [
				("powered", .atMostOnce, Engine.powered),
				("calibrated", .atMostOnce, Engine.calibrated)
			])
		}
    }
	private var oldPower = FogRational(num: Int64(0), den: 0)
	
	var newPower = FogRational(num: Int64(0), den: 1)
	
	private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
	
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
	
	private func calibrated(msg: MQTTMessage) {
		let calibration: FogRational<Int64> = msg.payload.fogExtract()
		delegate?.onPowerCalibrated(power: calibration)
	}
	
	private func powered(msg: MQTTMessage) {
		let power: FogRational<Int64> = msg.payload.fogExtract()
		delegate?.onPowerConfirm(power: power)
	}
	
	var calibration = FogRational(num: Int64(15), den: 100) {
		didSet {
			if !(calibration == oldValue) {
				var data  = Data(capacity: calibration.fogSize)
				data.fogAppend(calibration)
				mqtt.publish(MQTTPubMsg(topic: "calibrate", payload: data))
			}
		}
	}
	
	private func onTimer() {
		if !(oldPower == newPower) {
			oldPower = newPower
			var data  = Data(capacity: newPower.fogSize)
			data.fogAppend(newPower)
			mqtt.publish(MQTTPubMsg(topic: "power", payload: data))
		}
	}
}
