//
//  ReliableBurstTransmit.swift
//  BLETR
//
//  Created by WSG Software on 2020/4/7.
//  Copyright © 2020 Microchip. All rights reserved.
//

import Foundation
import CoreBluetooth

let AIR_PATCH_SUCCESS = 0x00
let AIR_PATCH_INVALID_PARAMETERS = 0x02
let AIR_PATCH_COMMAND_VENDOR_MP_ENABLE = 0x03
let AIR_PATCH_COMMAND_READ_MTU = 0x24
let AIR_PATCH_COMMAND_READ_MTU_NEW = 0x14

let AIR_PATCH_ACTION_READ_MTU = 0x24
let AIR_PATCH_ACTION_READ_MTU_NEW = 0x14

protocol ReliableBurstTransmitDelegate {
    func didSendDataWithCharacteristic(_ transparentDataWriteChar:CBCharacteristic)
    func didWriteDataLength(_ len:Int)
}

struct AIR_PATCH_COMMAND_FORMAT
{
    var commandID: UInt8 = 0
    var parameters = [UInt8](repeating: 0, count: 20)
    init(){}
    
    static func archive(format:AIR_PATCH_COMMAND_FORMAT) -> Data {
        var fw = format
        let len = 20
        var value = [UInt8](repeating: 0, count: Int(len+1))
        value[0] = fw.commandID
        memcpy(&value[1], &fw.parameters, Int(len))
        
        let data = Data(bytes: UnsafePointer<UInt8>(&value), count: value.count)
        return data
    }
    
    static func unarchive(data:[UInt8]) -> AIR_PATCH_COMMAND_FORMAT? {
        var w = AIR_PATCH_COMMAND_FORMAT()
        w.commandID = data[0]
        for i in 0..<data.count-1{
            w.parameters[i] = data[i+1]
        }
        return w
    }
}

struct AIR_PATCH_EVENT_FORMAT {
    var status: UInt8 = 0
    var commandID: UInt8 = 0
    var parameters = [UInt8](repeating: 0, count: 20)
    init(){}

    static func archive(format:AIR_PATCH_EVENT_FORMAT) -> Data {
        var fw = format
        let len = 20
        var value = [UInt8](repeating: 0, count: Int(len+2))
        value[0] = fw.status
        value[1] = fw.commandID
        memcpy(&value[2], &fw.parameters, Int(len+1))
        
        let data = Data(bytes: UnsafePointer<UInt8>(&value), count: value.count)
        return data
    }
    
    static func unarchive(data:[UInt8]) -> AIR_PATCH_EVENT_FORMAT? {
        var w = AIR_PATCH_EVENT_FORMAT()
        w.status = data[0]
        w.commandID = data[1]
        for i in 0..<data.count-2{
            w.parameters[i] = data[i+2]
        }
        return w
    }
}

struct MTU_CREDIT_EVENT_FORMAT{
    //var max_mtu: UInt8 = 0
    var max_mtu: UInt16 = 0
    var credit: UInt8 = 0
    init(){}
    static func archive(format:MTU_CREDIT_EVENT_FORMAT) -> Data {
        let fw = format
        //var value = [UInt8](repeating: 0, count: 2)
        var value = [UInt8](repeating: 0, count: 3)
        //value[0] = fw.max_mtu
        //value[1] = fw.credit
        value[0] = UInt8((fw.max_mtu & 0xff00) >> 8)
        value[1] = UInt8(fw.max_mtu & 0x00ff)
        value[2] = fw.credit
        
        let data = Data(bytes: UnsafePointer<UInt8>(&value), count: value.count)
        return data
    }
    
    static func unarchive(data:[UInt8]) -> MTU_CREDIT_EVENT_FORMAT? {
        var w = MTU_CREDIT_EVENT_FORMAT()
        //w.max_mtu = data[0]
        //w.credit = data[1]
        w.max_mtu = UInt16((data[0] << 8) | data[1])
        w.credit = data[2]
        return w
    }
}

@objc class ReliableBurstTransmit: NSObject {
    var credit: Int = 0
    var max_mtu: Int = 20
    var max_credit:Int = 0
    var vendorMPEnable:Bool = false
    var vendorMPEnableNew:Bool = false
    //sendData = YES;
    var haveCredit:Bool = true
    var mIsBM78:Bool = false
    var queuedData: NSMutableArray = NSMutableArray()
    var isSupportRelible:Bool = false
    var airPatchCharacteristic: CBCharacteristic?
    var transparentDataWriteChar: CBCharacteristic?
    var peripheral: CBPeripheral?
    var delegate:ReliableBurstTransmitDelegate?
    
    override init() {
        super.init()
    }
        
    @objc func switchLibrary(_ isBM78:Bool){
        mIsBM78 = isBM78
    }
    
    @objc func getTransmitSize() -> Int {
        if #available(iOS 9.0, *) {
            return (peripheral?.maximumWriteValueLength(for:CBCharacteristicWriteType.withoutResponse))!
        } else {
            return max_mtu;
        }
    }
    
    @objc func canSendReliableBurstTransmit() -> Bool {
        var canSend:Bool = false
        DispatchQueue.main.async {
            if (self.credit > 0) {
                canSend = true
                //return true
            }
            else {
                canSend = false
                //return false
            }
            //print("canSendReliableBurstTransmit,credit = \(self.credit)")
        }
        
        return canSend
    }
    
    @objc func isReliableBurstTransmitSupport() -> Bool {
        if (!isSupportRelible){
            return false
        }else{
            return true
        }
    }
    
    @objc func canDisconnect() -> Bool {
        var can:Bool = false
        if (self.max_credit == 0){
            can = true
        }
        DispatchQueue.main.async {
            if (self.credit >= self.max_credit) {
                can = true
                //return true
            }
            else {
                can = false
                //return false
            }
        }
        return can
    }
    
    @objc func decodeReliableBurstTransmitEvent(eventData:NSData){
        DispatchQueue.main.async {
            let dataBytes = [UInt8](eventData as Data)
            let receivedEvent = AIR_PATCH_EVENT_FORMAT.unarchive(data: dataBytes)
            if(receivedEvent!.commandID == AIR_PATCH_COMMAND_VENDOR_MP_ENABLE){
                if (receivedEvent!.status == AIR_PATCH_INVALID_PARAMETERS && !self.vendorMPEnableNew && self.mIsBM78) {
                    self.sendVendorMPEnable_New()
                }
                else if(receivedEvent!.status == AIR_PATCH_SUCCESS){
                    var command = AIR_PATCH_COMMAND_FORMAT()
                    if (self.mIsBM78) {
                        command.commandID = UInt8(AIR_PATCH_COMMAND_READ_MTU)
                    }
                    else{
                        command.commandID = UInt8(AIR_PATCH_COMMAND_READ_MTU_NEW)
                    }
                    let commandData = Data(bytes: &command.commandID, count: 1)
                    self.peripheral?.writeValue(commandData, for: self.airPatchCharacteristic!, type: CBCharacteristicWriteType.withResponse)
                    //NSData *data = [[NSData alloc] initWithBytes:&command length:1];
                    //[_peripheral writeValue:data forCharacteristic:_airPatchCharacteristic type:CBCharacteristicWriteWithResponse];
                }
            }else{
                
                if (receivedEvent!.status != AIR_PATCH_SUCCESS) {
                    return;
                }
                if ((receivedEvent!.commandID != AIR_PATCH_ACTION_READ_MTU) && (receivedEvent!.commandID != AIR_PATCH_ACTION_READ_MTU_NEW)) {
                    return;
                }
                var parameter = MTU_CREDIT_EVENT_FORMAT()
                //parameter.max_mtu = receivedEvent!.parameters[0]
                //parameter.credit = receivedEvent!.parameters[1]
                parameter.max_mtu = UInt16((receivedEvent!.parameters[0] << 8) | receivedEvent!.parameters[1])
                parameter.credit = receivedEvent!.parameters[2]
                if(self.max_credit < parameter.credit){
                    self.max_credit = Int(parameter.credit)
                }
                //print("\(parameter.max_mtu),\(parameter.credit)")
                
                //struct _MTU_CREDIT_EVENT_FORMAT *parameter = (struct _MTU_CREDIT_EVENT_FORMAT *)receivedEvent->parameters;
                //self.max_mtu = Int((CFSwapInt16BigToHost(UInt16(parameter.max_mtu)))-3)
                
                //if (self.max_mtu == 20) && (Int(parameter.max_mtu - 3) != 20){
                    //print("[ReliableBurstTransmit]max_mtu = \(parameter.max_mtu - 3),\((self.peripheral?.maximumWriteValueLength(for:CBCharacteristicWriteType.withoutResponse))!)")
                //}
                self.max_mtu = Int(parameter.max_mtu - 3)
                
                self.isSupportRelible = true

                //print("[decodeReliableBurstTransmitEvent]max_mtu_credit = \(self.max_mtu),credit = \(self.max_credit)")
                
                //max_mtu = (int)[_peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse];
                self.credit+=Int(parameter.credit)
                //NSLog(@"[libReliableBurstData] decodeReliableBurstTransmitEvent credit = %d",credit);
                //print("credit = \(self.credit)")
                
                //NSLog(@"[ReliableBurstData] decodeReliableBurstTransmitEvent end");
                if (!self.haveCredit) {
                    //NSLog(@"haveCredit = NO decodeReliableBurstTransmitEvent");
                    self.haveCredit = true
                    if (self.queuedData.count > 0){
                        let data = self.queuedData.firstObject
                        self.queuedData.removeObject(at: 0)
                        self.reliableBurstTransmit(data: data as! Data, transparentDataWriteChar: self.transparentDataWriteChar!)
                    }
                    else if(self.transparentDataWriteChar != nil && self.delegate != nil){
                        self.delegate?.didSendDataWithCharacteristic(self.transparentDataWriteChar!)
                    }
                }
            }
            
        }
    }
    
    @objc func enableReliableBurstTransmit(peripheral:CBPeripheral, airPatchCharacteristic:CBCharacteristic){
        //NSLog(@"[libReliableBurstData] enableReliableBurstTransmit");
        /*if (airPatchCharacteristic == nil) {
            return
        }*/
        self.airPatchCharacteristic = airPatchCharacteristic
        self.peripheral = peripheral

        if (mIsBM78){
            //NSLog(@"[libReliableBurstData] enableReliableBurstTransmit - mIsBM78");
            if (vendorMPEnable == false){
                self.sendVendorMPEnable()
            }
            else{
                var command = AIR_PATCH_COMMAND_FORMAT()
                command.commandID = UInt8(AIR_PATCH_COMMAND_READ_MTU)
                let commandData = Data(bytes: &command.commandID, count: 1)
                self.peripheral?.writeValue(commandData, for: self.airPatchCharacteristic!, type: CBCharacteristicWriteType.withResponse)
            }
        }
        else{
            //NSLog(@"[libReliableBurstData] enableReliableBurstTransmit - mIsBM78 = false");
            print("[libReliableBurstData] enableReliableBurstTransmit - mIsBM78 = false")
            if(!airPatchCharacteristic.isNotifying){
                self.peripheral?.setNotifyValue(true, for: self.airPatchCharacteristic!)
            }
            var command = AIR_PATCH_COMMAND_FORMAT()
            command.commandID = UInt8(AIR_PATCH_COMMAND_READ_MTU_NEW)
            let commandData = Data(bytes: &command.commandID, count: 1)
            self.peripheral?.writeValue(commandData, for: self.airPatchCharacteristic!, type: CBCharacteristicWriteType.withResponse)
        }
        
    }
    
    @objc func reliableBurstTransmit(data:Data,transparentDataWriteChar:CBCharacteristic){
        DispatchQueue.main.async {
            if ((self.transparentDataWriteChar == nil) || !((self.transparentDataWriteChar?.isEqual(transparentDataWriteChar))!)) {
                self.transparentDataWriteChar = transparentDataWriteChar
            }
            //NSLog(@"[libReliableBurstData] reliableBurstTransmit credit = %d",credit);
            if (self.credit > 0) {
                self.credit-=1
                //NSLog(@"[ReliableBurstData] reliableBurstTransmit:withTransparentCharacteristic:");
                if (self.queuedData.count > 0){
                    self.queuedData.add(data)
                    let qData:Data = self.queuedData.firstObject as! Data
                    self.queuedData.removeObject(at: 0)
                    //print("[Get data from queue]reliableBurstTransmit,credit = \(self.credit)")
                    self.peripheral?.writeValue(qData, for: self.transparentDataWriteChar!, type: CBCharacteristicWriteType.withoutResponse)
                    
                    if (self.delegate != nil){
                        //self.delegate?.didWriteDataLength(data.count)
                        self.delegate?.didWriteDataLength(qData.count)
                    }
                }
                else{
                    self.peripheral?.writeValue(data, for: self.transparentDataWriteChar!, type: CBCharacteristicWriteType.withoutResponse)
                    //print("reliableBurstTransmit,credit = \(self.credit)")
                    
                    if (self.delegate != nil){
                        self.delegate?.didWriteDataLength(data.count)
                    }
                }
                
                if (self.credit > 0) {
                    if (self.delegate != nil){
                        self.delegate?.didSendDataWithCharacteristic(self.transparentDataWriteChar!)
                    }
                }
                else {
                    //NSLog(@"haveCredit = NO");
                    self.haveCredit = false
                }
            }
            else {
                //[_peripheral writeValue:data forCharacteristic:transparentDataWriteChar type:CBCharacteristicWriteWithResponse];
                //sendData = NO;
                self.queuedData.add(data)
                self.haveCredit = false
            }
        }
    }
    
    @objc func sendVendorMPEnable() {
        if (airPatchCharacteristic == nil) {
            return;
        }
        peripheral!.setNotifyValue(true, for: airPatchCharacteristic!)
        var command = AIR_PATCH_COMMAND_FORMAT()
        command.commandID = UInt8(AIR_PATCH_COMMAND_VENDOR_MP_ENABLE);
        let commandData = Data(bytes: &command.commandID, count: 1)
        peripheral?.writeValue(commandData, for: airPatchCharacteristic!, type: CBCharacteristicWriteType.withResponse)
        vendorMPEnable = true;
        vendorMPEnableNew = true;
    }
    
    @objc func sendVendorMPEnable_New() {
        if (airPatchCharacteristic == nil) {
            return;
        }
        peripheral!.setNotifyValue(true, for: airPatchCharacteristic!)
        var command = AIR_PATCH_COMMAND_FORMAT()
        command.commandID = UInt8(AIR_PATCH_COMMAND_VENDOR_MP_ENABLE);
        command.parameters[0] = 0x01;
        let commandData = Data(bytes: &command.commandID, count: 2)
        peripheral?.writeValue(commandData, for: airPatchCharacteristic!, type: CBCharacteristicWriteType.withResponse)
        vendorMPEnable = true;
        vendorMPEnableNew = true;
    }
    
    @objc func isReliableBurstTransmit(transparentDataWriteChar:CBCharacteristic?) -> Bool{
        if (transparentDataWriteChar == nil) {
            return false
        }
        if ((self.transparentDataWriteChar?.isEqual(transparentDataWriteChar)) != nil) {
            if (self.delegate != nil) {
                    self.delegate?.didSendDataWithCharacteristic(self.transparentDataWriteChar!)
            }
            return true
        }
        else {
            return false
        }
    }
}

