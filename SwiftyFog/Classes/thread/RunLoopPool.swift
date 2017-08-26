//
//  RunLoopPool.swift
//  SwiftyFog
//
//  Created by David Giovannini on 8/25/17.
//

import Foundation

public class RunLoopPool {
	private let mutex = ReadWriteMutex()
	private var runloops : [String : (DispatchGroup, DispatchQueue, RunLoop?)] = [:]
	
	public func runLoop(label: String, qos: DispatchQoS, with: @escaping (RunLoop)->()) {
		let element: (DispatchGroup, DispatchQueue?) = mutex.writing {
			if let element = runloops[label] {
				return (element.0, nil)
			}
			else {
				let signal = DispatchGroup()
				let thread = DispatchQueue(label: label, qos: qos)
				runloops[label] = (signal, thread, nil)
				signal.enter()
				return (signal, thread)
			}
		}
		if let thread = element.1 {
			thread.async { [weak self] in
				self?.run(label, element.0, with)
			}
		}
		else {
			let _ = element.0.wait(timeout: DispatchTime.distantFuture)
			with(mutex.reading{runloops[label]!.2!})
		}
	}
	
	private func run(_ label: String, _ signal: DispatchGroup, _ with: @escaping (RunLoop)->()) {
		let currentRunLoop = RunLoop.current
		self.mutex.writing {
			self.runloops[label]!.2 = currentRunLoop
		}
		signal.leave()
		with(currentRunLoop)
		currentRunLoop.run()
	}
}
