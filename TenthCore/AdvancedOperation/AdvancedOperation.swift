//
//  AdvancedOperation.swift
//  TenthCore
//
//  Created by Goppinath Thurairajah on 10.07.18.
//  Copyright © 2018 Goppinath Thurairajah. All rights reserved.
//

import Foundation

open class AdvancedOperation: Operation {
    
    public enum Timeout {
        
        case fifteenSeconds, thirtySeconds, fortyfiveSeconds, sixtySeconds, nintySeconds, custom(Int)
        
        var timeInterval: TimeInterval {
            
            switch self {
            case .fifteenSeconds:           return TimeInterval(15)
            case .thirtySeconds:            return TimeInterval(30)
            case .fortyfiveSeconds:         return TimeInterval(45)
            case .sixtySeconds:             return TimeInterval(60)
            case .nintySeconds:             return TimeInterval(90)
            case .custom(let timeInterval): return TimeInterval(timeInterval)
            }
        }
    }
    
    fileprivate weak var operationQueue: AdvancedOperationQueue?
    
    private var timeout: Timeout?
    private var timer: Timer?
    
    // The opertion wich hosts
    public weak var hostOperation: CompoundAdvancedOperation?
    
    public var operationOnSuccess: AdvancedOperation?
    public var operationOnFailure: AdvancedOperation?
    
    // MARK:- Private variables with KVO notification
    
    private var _executing = false {
        
        willSet { willChangeValue(forKey: "isExecuting") }
        didSet { didChangeValue(forKey: "isExecuting") }
    }
    
    private var _finished = false {
        
        willSet { willChangeValue(forKey: "isFinished") }
        didSet { didChangeValue(forKey: "isFinished") }
    }
    
    // MARK:- Methods must be overridden
    
    override open var isAsynchronous: Bool { return true } // No need
    override open var isExecuting: Bool { return _executing }
    override open var isFinished: Bool { return _finished }
    
    override open func start() {
        
        if isCancelled {
            
            done()
        }
        else {
            
            _executing = true
            
            if let timeout = timeout {
                
                timer = Timer.scheduledTimer(withTimeInterval: timeout.timeInterval, repeats: false, block: { [unowned self] (timer) in
                    
                    self.timeoutDidOccur()
                    self.done()
                })
            }
            
            execute()
        }
    }
    
    open override func cancel() {
        
        super.cancel()
        
        done()
    }
    
    /// Execute your async task here.
    open func execute() {}
    
    /// Notify the completion of async task and hence the completion of the operation
    public final func done() {
        
        timer?.invalidate()
        
        _executing = false
        _finished = true
    }
    
    public init(timeout: Timeout? = nil) {
        
        self.timeout = timeout
        
        super.init()
    }
    
    public final func operationDidFail() {
        
        hostOperation?.operationDidFail(operation: self)
        
        if let operationOnFailure = operationOnFailure {
            
            operationQueue?.addOperation(operationOnFailure)
        }
    }
    
    public final func operationDidSucceed() {
        
        hostOperation?.operationDidSucceed(operation: self)
        
        if let operationOnSuccess = operationOnSuccess {
            
            operationQueue?.addOperation(operationOnSuccess)
        }
    }
    
    /// Cleanup must be performed here
    open func timeoutDidOccur() {}
    
    /// Add Operation to the parent queue
    public func scheduleOperation(_ op: Operation) {
        
        operationQueue?.addOperation(op)
    }
}

// MARK:- CompoundAdvancedOperation
open class CompoundAdvancedOperation: AdvancedOperation {
    
    open lazy var sessionID = UUID()
    var operationFailed = false
    
    let queueName: String?
    let maxConcurrentOperationCount: Int
    let compoundOperationQueueQualityOfService: QualityOfService
    
    lazy private var operationStore = self.operationStoreInitializer()
    
    open var operationStoreInitializer: () -> [AdvancedOperation] {
        
        return { [AdvancedOperation]() }
    }
    
    public private (set) lazy var compoundOperationQueue = AdvancedOperationQueue(name: self.queueName, maxConcurrentOperationCount: self.maxConcurrentOperationCount)
    
    public init(timeout: Timeout? = nil, queueName: String? = nil, maxConcurrentOperationCount: Int = OperationQueue.defaultMaxConcurrentOperationCount, compoundOperationQueueQualityOfService: QualityOfService = .default) {
        
        self.queueName = queueName
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.compoundOperationQueueQualityOfService = compoundOperationQueueQualityOfService
        
        super.init(timeout: timeout)
    }
    
    fileprivate final func operationDidFail(operation: AdvancedOperation) {
        
        if !operationFailed {
            
            operationFailed = true
            
            compoundOperationQueue.cancelAllOperations()
            
            operationDidFail()
            
            compoundOperationDidFail(operation: operation)
        }
    }
    
    fileprivate final func operationDidSucceed(operation: AdvancedOperation) {
        
        childOperationDidSucceed(operation: operation)
    }
    
    override open func execute() {
        
        if isCancelled { done(); return }
        
        guard prepareCompoundOperation() else { done(); return }
        
        operationStore.forEach { $0.hostOperation = self }
        
        compoundOperationQueue.addOperations(operationStore, waitUntilFinished: true)
        
        if !operationFailed {
            
            operationDidSucceed()
            
            compoundOperationDidSucceed()
        }
        
        done()
    }
    
    open func prepareCompoundOperation() -> Bool { return true }
    
    open func compoundOperationDidFail(operation: AdvancedOperation) {}
    
    open func childOperationDidSucceed(operation: AdvancedOperation) {}
    
    open func compoundOperationDidSucceed() {}
}

// MARK:- AdvancedOperationQueue
public class AdvancedOperationQueue: OperationQueue {
    
    public init(name: String?, maxConcurrentOperationCount: Int = ProcessInfo.processInfo.processorCount * 3, qualityOfService: QualityOfService = .default) {
        
        super.init()
        
        self.name = name
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.qualityOfService = qualityOfService
    }
    
    override public func addOperation(_ op: Operation) {
        
        if let operation = op as? AdvancedOperation {
            
            operation.operationQueue = self
        }
        
        super.addOperation(op)
    }
    
    override public func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
        
        for op in ops {
            
            if let operation = op as? AdvancedOperation {
                
                operation.operationQueue = self
            }
        }
        
        super.addOperations(ops, waitUntilFinished: wait)
    }
}
