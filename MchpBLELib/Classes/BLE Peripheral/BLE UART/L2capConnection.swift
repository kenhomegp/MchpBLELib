//
//  L2capConnection.swift
//  BleUARTLib
//
//  Created by WSG Software on 2021/7/21.
//

import Foundation
import CoreBluetooth

typealias L2CapDiscoveredPeripheralCallback = (CBPeripheral)->Void
typealias L2CapStateCallback = (CBManagerState)->Void
typealias L2CapConnectionCallback = (L2CapConnection)->Void
typealias L2CapDisconnectionCallback = (L2CapConnection,Error?)->Void
typealias L2CapReceiveDataCallback = (Data)->Void
typealias L2CapSentDataCallback = (Int)->Void

protocol L2CapConnection {
    var readDataCallback: L2CapReceiveDataCallback? {get set}
    var writeDataCallback: L2CapSentDataCallback? {get set}
       
    func send(data: Data) -> Void
    func stop() -> Void
    func CloseStream() -> Bool
    func OpenStream() -> Bool
}

class L2CapInternalConnection: NSObject, StreamDelegate, L2CapConnection {
    var channel: CBL2CAPChannel?
    
    var readDataCallback: L2CapReceiveDataCallback?
    var writeDataCallback: L2CapSentDataCallback?
    
    var bytesReceived : Int = 0
    var bytesWritten: Int = 0
    
    var Write_data_flag: Bool = false
    
    private var queueQueue = DispatchQueue(label: "queue queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem, target: nil)
    
    private var outputData = Data()
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            print("Stream is open")
        case Stream.Event.endEncountered:
            print("End Encountered")
        case Stream.Event.hasBytesAvailable:
            self.readBytes(from: aStream as! InputStream)
        case Stream.Event.hasSpaceAvailable:
            self.writeDataCallback?(bytesWritten)
            self.send()
        case Stream.Event.errorOccurred:
            print("Stream error")
        default:
            print("Unknown stream event")
        }
    }
    
    deinit {
        print("L2CAP_Connection Going away")
    }
    
    func send(data: Data) -> Void {
        queueQueue.sync  {
            self.outputData.append(data)
        }
        self.send()
    }
    
    private func send() {
        
        guard let ostream = self.channel?.outputStream, !self.outputData.isEmpty, ostream.hasSpaceAvailable  else{
            return
        }
        
        self.bytesWritten =  ostream.write(self.outputData)
     
        if(self.bytesWritten != -1){
            queueQueue.sync {
                if bytesWritten < outputData.count {
                    outputData = outputData.advanced(by: bytesWritten)
                } else {
                    outputData.removeAll()
                }
            }
        }
    }
    
    private func readBytes(from stream: InputStream) {
        let bufLength = 1024
        //let bufLength = 2048
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufLength)
        defer {
            buffer.deallocate()
        }
        let bytesRead = stream.read(buffer, maxLength: bufLength)
        //print("InputStream bytesRead = \(bytesRead)")
        var returnData = Data()
        returnData.append(buffer, count:bytesRead)
        
        self.readDataCallback?(returnData)

        if stream.hasBytesAvailable {
            self.readBytes(from: stream)
        }
    }
    
    func stop() {
        self.outputData.removeAll()
        print(#function)
    }
    
    func CloseStream() -> Bool{
        if let connection = self.channel{
            print("\(connection)")
            print("Input Stream Status = \(channel?.inputStream.streamStatus.rawValue ?? 0)")
            print("Output Stream Status = \(channel?.outputStream.streamStatus.rawValue ?? 0)")
            
            print("Stream open = \(Stream.Status.open.rawValue)")
            print("Stream notopen = \(Stream.Status.notOpen.rawValue)")
            
            channel?.inputStream.delegate = nil
            channel?.inputStream.close()
            channel?.inputStream.remove(from: RunLoop.main, forMode: RunLoop.Mode.default)
            print("Close input stream ")
            
            channel?.outputStream.delegate = nil
            channel?.outputStream.close()
            channel?.outputStream.remove(from: RunLoop.main, forMode: RunLoop.Mode.default)
            print("Close output stream ")
            //Once a stream is closed, it cannot be reopened.
            
            return true
        }
        else{
            return false
        }
    }
    
    func OpenStream() -> Bool{
        if let connection = self.channel{
            print("\(connection)")
            print("Input Stream Status = \(channel?.inputStream.streamStatus.rawValue ?? 0)")
            print("Output Stream Status = \(channel?.outputStream.streamStatus.rawValue ?? 0)")
            
            print("Stream open = \(Stream.Status.open.rawValue)")
            print("Stream closed = \(Stream.Status.closed.rawValue)")
            
            if(channel?.inputStream.streamStatus.rawValue == Stream.Status.closed.rawValue) {
                channel?.inputStream.delegate = self
                channel?.inputStream.open()
                channel?.inputStream.schedule(in: RunLoop.main, forMode: RunLoop.Mode.default)
                print("Open input stream ")
            }
            
            if(channel?.outputStream.streamStatus.rawValue == Stream.Status.closed.rawValue) {
                channel?.outputStream.delegate = self
                channel?.outputStream.open()
                channel?.outputStream.schedule(in: RunLoop.main, forMode: RunLoop.Mode.default)
                print("Open output stream ")
            }
            return true
        }
        else{
            return false
        }
    }
}

// MARK: - L2CAP Central

class L2CapCentralConnection: L2CapInternalConnection, CBPeripheralDelegate {
    
    internal init(peripheral: CBPeripheral, psm: UInt16, connectionCallback: @escaping L2CapConnectionCallback) {
        self.peripheral = peripheral
        self.connectionHandler = connectionCallback
        super.init()
        peripheral.delegate = self
        print("openL2CAPChannel:psm = \(psm)")
        self.peripheral.openL2CAPChannel(psm)
    }

    private var peripheral: CBPeripheral
    private let connectionHandler: L2CapConnectionCallback
        
    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        if let error = error {
            print("Error opening l2cap channel - \(error.localizedDescription)")
            
            return
        }
        guard let channel = channel else {
            return
        }
        //print("Opened channel \(channel)")
        self.channel = channel
        channel.inputStream.delegate = self
        channel.outputStream.delegate = self
        print("DidOpened_L2CAPChannel: \(channel),psm = \(channel.psm)")
        channel.inputStream.schedule(in: RunLoop.main, forMode: RunLoop.Mode.default)
        channel.outputStream.schedule(in: RunLoop.main, forMode: RunLoop.Mode.default)
        channel.inputStream.open()
        channel.outputStream.open()
        self.connectionHandler(self)
    }
}

// MARK: - L2CAP Peripheral

class L2CapPeripheralConnection: L2CapInternalConnection {
    init(channel: CBL2CAPChannel) {
        super.init()
        self.channel = channel
        print("Opened channel \(channel)")
        channel.inputStream.delegate = self
        channel.outputStream.delegate = self
        channel.inputStream.schedule(in: RunLoop.main, forMode: RunLoop.Mode.default)
        channel.outputStream.schedule(in: RunLoop.main, forMode: RunLoop.Mode.default)
        channel.inputStream.open()
        channel.outputStream.open()
    }
}

class L2CapPeripheral: NSObject {
    //L2CAP Peripheral
    let psmServiceID = CBUUID(string: "312700E2-E798-4D5C-8DCF-49908332DF9F")
    let PSMID = CBUUID(string:CBUUIDL2CAPPSMCharacteristicString)
    
    //public var publish: Bool = false {
    var publish: Bool = false {
        didSet {
            self.publishService()
        }
    }
    
    private var service: CBMutableService?
    private var characteristic: CBMutableCharacteristic?
    private var peripheralManager: CBPeripheralManager
    private var subscribedCentrals = [CBCharacteristic:[CBCentral]]()
    private var channelPSM: UInt16?
    private var managerQueue = DispatchQueue.global(qos: .utility)
    private var connectionHandler: L2CapConnectionCallback
    
    override init() {
        fatalError("Call init(connectionHandler:)")
    }
    
    init(connectionHandler:  @escaping L2CapConnectionCallback) {
        self.connectionHandler = connectionHandler
        self.peripheralManager = CBPeripheralManager(delegate: nil, queue: managerQueue)
        super.init()
        self.peripheralManager.delegate = self
    }
    
    private func publishService() {
        guard peripheralManager.state == .poweredOn, publish else {
            self.unpublishService()
            return
        }
        self.service = CBMutableService(type: psmServiceID, primary: true)
        self.characteristic = CBMutableCharacteristic(type: PSMID, properties: [ CBCharacteristicProperties.read, CBCharacteristicProperties.indicate], value: nil, permissions: [CBAttributePermissions.readable] )
        self.service?.characteristics = [self.characteristic!]
        self.peripheralManager.add(self.service!)
        self.peripheralManager.publishL2CAPChannel(withEncryption: false)
        self.peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [psmServiceID], CBAdvertisementDataLocalNameKey : "L2CAP_Test"])
        
    }
    
    private func unpublishService() {
        self.peripheralManager.stopAdvertising()
        self.peripheralManager.removeAllServices()
        if let psm = self.channelPSM {
            self.peripheralManager.unpublishL2CAPChannel(psm)
        }
        self.subscribedCentrals.removeAll()
        self.characteristic = nil
        self.service = nil
    }
}

extension L2CapPeripheral: CBPeripheralManagerDelegate {
    
    //public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            self.publishService()
        }
    }
    
    //public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        var centrals = self.subscribedCentrals[characteristic, default: [CBCentral]()]
        centrals.append(central)
        self.subscribedCentrals[characteristic]  = centrals
    }
    
    //public func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
    func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        if let error = error {
            print("Error publishing channel: \(error.localizedDescription)")
            return
        }
        print("Published channel \(PSM)")
        
        self.channelPSM = PSM
        
        if let data = "\(PSM)".data(using: .utf8) {
            
            self.characteristic?.value = data
            
            self.peripheralManager.updateValue(data, for: self.characteristic!, onSubscribedCentrals: self.subscribedCentrals[self.characteristic!])
        }
        
    }
    
    //public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if let psm = self.channelPSM, let data = "\(psm)".data(using: .utf8), let characteristic = self.characteristic {
            request.value = characteristic.value
            print("Respond \(data)")
            self.peripheralManager.respond(to: request, withResult: .success)
        } else {
            self.peripheralManager.respond(to: request, withResult: .unlikelyError)
        }
    }
    
    //public func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
    func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        
        if let error = error {
            print("Error opening channel: \(error.localizedDescription)")
            return
        }
        if let channel = channel {
            let connection = L2CapPeripheralConnection(channel: channel)
            print("Peripheral:didOpenL2CAPChannel")
            self.connectionHandler(connection)
        }
    }
}

extension OutputStream {
    func write(_ data: Data) -> Int {
        return data.withUnsafeBytes({ (rawBufferPointer: UnsafeRawBufferPointer) -> Int in
            let bufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
            return self.write(bufferPointer.baseAddress!, maxLength: data.count)
        })
    }

}
