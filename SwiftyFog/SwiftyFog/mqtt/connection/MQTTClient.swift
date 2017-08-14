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

public class MQTTClient {
	private let client: MQTTClientParams
	private let host: MQTTHostParams
	private let reconnect: MQTTReconnect
	
	private var publisher: MQTTPublisher
	private var subscriber: MQTTSubscriber
	private var distributer: MQTTDistributor
	private var connection: MQTTConnection?
	
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
	
	public func publish(
			pubMsg: MQTTPubMsg,
			retry: MQTTPublishRetry = MQTTPublishRetry(),
			completion: ((Bool)->())?) {
		publisher.publish(pubMsg: pubMsg, retry: retry, completion: completion)
	}
	
	public func subscribe(topics: [String: MQTTQoS], completion: ((Bool)->())?) -> MQTTSubscription {
		return subscriber.subscribe(topics: topics, completion: completion)
	}
	
	public func registerTopic(path: String, action: ()->()) {
		return distributer.registerTopic(path: path, action: action)
	}
}

extension MQTTClient: MQTTConnectionDelegate {
	public func mqttDiscconnected(_ connection: MQTTConnection, reason: MQTTConnectionDisconnect, error: Error?) {
		print("\(Date.nowInSeconds()): MQTT Discconnected \(reason) \(error?.localizedDescription ?? "")")
		publisher.disconnected(cleanSession: connection.cleanSession, final: reason == .shutdown)
		subscriber.disconnected(cleanSession: connection.cleanSession, final: reason == .shutdown)
		distributer.disconnected(cleanSession: connection.cleanSession, final: reason == .shutdown)
		// TODO: New language rules. I need to rethink delegate calls from deinit - as I should :-)
		if reason != .shutdown {
			self.connection = nil
		}
	}
	
	public func mqttConnected(_ connection: MQTTConnection) {
		print("\(Date.nowInSeconds()): MQTT Connected")
		publisher.connected(cleanSession: connection.cleanSession)
		subscriber.connected(cleanSession: connection.cleanSession)
		distributer.connected(cleanSession: connection.cleanSession)
	}
	
	public func mqttPinged(_ connection: MQTTConnection, status: PingStatus) {
		print("\(Date.nowInSeconds()): MQTT Ping \(status)")
	}
	
	public func mqttReceived(_ connection: MQTTConnection, packet: MQTTPacket) {
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
	public func send(packet: MQTTPacket) -> Bool {
		return connection?.send(packet: packet) ?? false
	}
	
	public func subscriptionChanged(topics: [String: MQTTQoS], status: MQTTSubscriptionStatus) {
		print("\(Date.nowInSeconds()): MQTT Subscription \(status)")
	}
}
