//
//  MQTTClient.swift
//  SwiftyFog
//
//  Created by David Giovannini on 8/12/17.
//  Copyright © 2017 Object Computing Inc. All rights reserved.
//

import Foundation

public struct MQTTReconnect {
    public var retryCount: Int = 3
    public var retryTimeInterval: TimeInterval = 1.0
    public var resuscitateTimeInterval: TimeInterval = 5.0
	
    public init() {
    }
}

public protocol MQTTClientDelegate: class {
	func mqttConnected(client: MQTTClient)
	func mqttPinged(client: MQTTClient, status: MQTTPingStatus)
	func mqttSubscriptionChanged(client: MQTTClient, subscription: MQTTSubscription, status: MQTTSubscriptionStatus)
	func mqttDisconnected(client: MQTTClient, reason: MQTTConnectionDisconnect, error: Error?)
}

public final class MQTTClient {
	private let client: MQTTClientParams
	private let host: MQTTHostParams
	private let reconnect: MQTTReconnect
	
	private var publisher: MQTTPublisher
	private var subscriber: MQTTSubscriber
	private var distributer: MQTTDistributor
	private var connection: MQTTConnection?
	
    public weak var delegate: MQTTClientDelegate?
	
	// TODO: implement reconnect
	public init(client: MQTTClientParams, host: MQTTHostParams = MQTTHostParams(), reconnect: MQTTReconnect = MQTTReconnect()) {
		self.client = client
		self.host = host
		self.reconnect = reconnect
		let idSource = MQTTMessageIdSource()
		self.publisher = MQTTPublisher(idSource: idSource)
		self.subscriber = MQTTSubscriber(idSource: idSource)
		self.distributer = MQTTDistributor(idSource: idSource)
		publisher.delegate = self
		subscriber.delegate = self
		distributer.delegate = self
	}
	
	public func start() {
		connection = MQTTConnection(hostParams: host, clientPrams: client)
		connection?.delegate = self
	}
	
	public func stop() {
		connection = nil
	}
	
	public func publish(pubMsg: MQTTPubMsg, retry: MQTTPublishRetry = MQTTPublishRetry(), completion: ((Bool)->())?) {
		publisher.publish(pubMsg: pubMsg, retry: retry, completion: completion)
	}
	
	public func subscribe(topics: [String: MQTTQoS], completion: ((Bool)->())?) -> MQTTSubscription {
		return subscriber.subscribe(topics: topics, completion: completion)
	}
	
	public func registerTopic(path: String, action: @escaping (MQTTMessage)->()) -> MQTTRegistration {
		return distributer.registerTopic(path: path, action: action)
	}
}

extension MQTTClient: MQTTConnectionDelegate {
	func mqttDisconnected(_ connection: MQTTConnection, reason: MQTTConnectionDisconnect, error: Error?) {
		publisher.disconnected(cleanSession: connection.cleanSession, final: reason == .shutdown)
		subscriber.disconnected(cleanSession: connection.cleanSession, final: reason == .shutdown)
		distributer.disconnected(cleanSession: connection.cleanSession, final: reason == .shutdown)
		// TODO: New language rules. I need to rethink delegate calls from deinit - as I should :-)
		if reason != .shutdown {
			self.connection = nil
		}
		delegate?.mqttDisconnected(client: self, reason: reason, error: error)
	}
	
	func mqttConnected(_ connection: MQTTConnection) {
		publisher.connected(cleanSession: connection.cleanSession)
		subscriber.connected(cleanSession: connection.cleanSession)
		distributer.connected(cleanSession: connection.cleanSession)
		delegate?.mqttConnected(client: self)
	}
	
	func mqttPinged(_ connection: MQTTConnection, status: MQTTPingStatus) {
		delegate?.mqttPinged(client: self, status: status)
	}
	
	func mqttReceived(_ connection: MQTTConnection, packet: MQTTPacket) {
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
		print("MQTT Unhandled: \(type(of:packet))")
	}
}

extension MQTTClient: MQTTPublisherDelegate, MQTTSubscriptionDelegate, MQTTDistributorDelegate {
	func send(packet: MQTTPacket) -> Bool {
		return connection?.send(packet: packet) ?? false
	}
	
	func subscriptionChanged(subscription: MQTTSubscription, status: MQTTSubscriptionStatus) {
		delegate?.mqttSubscriptionChanged(client: self, subscription: subscription, status: status)
	}
}