//
//  MQTTRouter.swift
//  SwiftyFog_iOS
//
//  Created by David Giovannini on 11/22/17.
//  Copyright © 2017 Object Computing Inc. All rights reserved.
//

import Foundation

protocol MQTTRouterDelegate: class {
	func mqtt(unhandledMessage: MQTTMessage)
	func mqtt(send: MQTTPacket, completion: @escaping (Bool)->())
} 

class MQTTRouter {
	private let metrics: MQTTMetrics?
	private let idSource: MQTTMessageIdSource
	private let durability: MQTTPacketDurability
	private let publisher: MQTTPublisher
	private let subscriber: MQTTSubscriber
	private let distributer: MQTTDistributor
    private let factory: MQTTPacketFactory

    public weak var delegate: MQTTRouterDelegate?
	
	public init(
		metrics: MQTTMetrics? = nil,
		routing: MQTTRoutingParams = MQTTRoutingParams()) {
		self.metrics = metrics
		idSource = MQTTMessageIdSource(metrics: metrics)
		self.durability = MQTTPacketDurability(idSource: idSource, queuePubOnDisconnect: routing.queuePubOnDisconnect, resendInterval: routing.resendPulseInterval, resendLimit: routing.resendLimit)
		let packetIssuer: MQTTPacketIssuer = self.durability
		self.publisher = MQTTPublisher(issuer: packetIssuer, queuePubOnDisconnect: routing.queuePubOnDisconnect, qos2Mode: routing.qos2Mode)
		self.subscriber = MQTTSubscriber(issuer: packetIssuer)
		self.distributer = MQTTDistributor(issuer: packetIssuer, qos2Mode: routing.qos2Mode)
		self.factory = MQTTPacketFactory(metrics: metrics)
		
		self.distributer.delegate = self
	}
	
	// Packets received from the network
	public func dispatch(packet: MQTTPacket) {
		var handled = distributer.receive(packet: packet)
		if handled == false {
			handled = publisher.receive(packet: packet)
			if handled == false {
				handled = subscriber.receive(packet: packet)
				if handled == false {
					unhandledPacket(packet: packet)
				}
			}
		}
	}
	
	private func unhandledPacket(packet: MQTTPacket) {
		if let metrics = metrics {
			metrics.unhandledPacket()
			if metrics.printUnhandledPackets {
				metrics.debug("Unhandled: \(packet)")
			}
		}
	}
}

extension MQTTRouter: MQTTBridge {
	public func createBridge(subPath: String) -> MQTTBridge {
		return MQTTTopicScope(base: self, fullPath: subPath)
	}

	public func publish(_ pubMsg: MQTTMessage, completion: ((Bool)->())?) {
		let path = String(pubMsg.topic)
		let resolved = path.hasPrefix("$") ? String(path.dropFirst()) : path
		let newMessage = MQTTMessage(topic: resolved, payload: pubMsg.payload, retain: pubMsg.retain, qos: pubMsg.qos)
		publisher.publish(pubMsg: newMessage, completion: completion)
	}
	
	public func subscribe(topics: [(String, MQTTQoS)], acknowledged: SubscriptionAcknowledged?) -> MQTTSubscription {
		let resolved = topics.map { (
			$0.0.hasPrefix("$") ? String($0.0.dropFirst()) : $0.0,
			$0.1
		)}
		return subscriber.subscribe(topics: resolved, acknowledged: acknowledged)
	}
	
	public func register(topic: String, action: @escaping (MQTTMessage)->()) -> MQTTRegistration {
		let resolved = topic.hasPrefix("$") ? String(topic.dropFirst()) : topic
		return distributer.registerTopic(path: resolved, action: action)
	}
}

extension MQTTRouter: MQTTDistributorDelegate, MQTTPacketDurabilityDelegate {
	func mqtt(send: MQTTPacket, completion: @escaping (Bool)->()) {
		if let delegate = delegate {
			delegate.mqtt(send: send, completion: completion)
		}
		else {
			completion(false)
		}
	}
	
	func mqtt(unhandledMessage: MQTTMessage) {
		delegate?.mqtt(unhandledMessage: unhandledMessage)
	}
}
