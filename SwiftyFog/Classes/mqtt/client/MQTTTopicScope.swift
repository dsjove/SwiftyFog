//
//  MQTTTopicScope.swift
//  Pods-SwiftyFog_Example
//
//  Created by David Giovannini on 8/19/17.
//

import Foundation

final class MQTTTopicScope: MQTTBridge {
	private var base: MQTTBridge
	private let fullPath: String
	
	func createBridge(subPath: String) -> MQTTBridge {
		return MQTTTopicScope(base: self.base, fullPath: self.fullPath + "/" + subPath)
	}
	
	init(base: MQTTBridge, fullPath: String) {
		self.base = base
		self.fullPath = fullPath + "/"
	}
	
	func subscribe(topics: [(String, MQTTQoS)], completion: ((Bool)->())?) -> MQTTSubscription {
		let qualified = topics.map {
			return (
				$0.0.hasPrefix("$") ? String($0.0.dropFirst()) : self.fullPath + $0.0,
				$0.1
			)
		}
		return base.subscribe(topics: qualified, completion: completion)
	}

	func publish(_ pubMsg: MQTTPubMsg, completion: ((Bool)->())?) {
		let topic = String(pubMsg.topic)
		let resolved = topic.hasPrefix("/") ? String(topic.dropFirst()) : self.fullPath + topic
		let scoped = MQTTPubMsg(topic: resolved, payload: pubMsg.payload, retain: pubMsg.retain, qos: pubMsg.qos)
		base.publish(scoped)
	}
	
	func registerTopic(path: String, action: @escaping (MQTTMessage)->()) -> MQTTRegistration {
		let resolved = path.hasPrefix("$") ? String(path.dropFirst()) : self.fullPath + path
		return base.registerTopic(path: resolved, action: action)
	}
}
