//
//  LEConnection.swift
//  BleOTALib
//
//  Created by WSG Software on 2022/7/21.
//

import Foundation
import CoreBluetooth

class OTAPeripheral: NSObject, OTADataConnection, CBPeripheralDelegate{

    var OTACommandEventCallback: OTADataCallback?
    
    var OTAFeatureEnabled: ((OTAError?) -> Void)?
    
    private var peripheral: CBPeripheral!
    private var CharOTAControl : CBCharacteristic!
    private var CharOTAData : CBCharacteristic!
    private var canSendData: Bool = false
    private var connectionHandler: OTAConnectionCallback!
    
    init(peripheral: CBPeripheral, connectionCallback: @escaping OTAConnectionCallback) {
        self.peripheral = peripheral
        self.connectionHandler = connectionCallback
        super.init()
        self.peripheral.delegate = self
        print("LEConnection init")
        self.connectionHandler(self)
    }
    
    deinit {
        print("Bye,LEConnection")
    }
    
    func DiscoverOTAService(){
        self.peripheral.discoverServices(nil)
        print(#function)
    }
    
    func DiscoverOTAService(completion: @escaping (OTAError?)-> Void){
        self.OTAFeatureEnabled = completion
        self.peripheral.discoverServices(nil)
        print(#function)
    }
    
    func OTAWriteCommand(command: OTA_Command) {
        let dat = OTA_Command.format(ota_cmd: command)
        self.peripheral.writeValue(dat, for: self.CharOTAControl, type: .withResponse)
    }
    
    func OTAWriteData(dat: Data) {
        self.peripheral.writeValue(dat, for: self.CharOTAData, type: .withoutResponse)
    }
    
    func OTAGetCharacteristic() -> (CBCharacteristic?, CBCharacteristic?, CBCharacteristic?){
        //print("LEConnection." + #function)
        
        var ota_data_char : CBCharacteristic? = nil
        var ota_control_char : CBCharacteristic? = nil
        var ota_feature_char : CBCharacteristic? = nil
        
        if let filterServices = self.peripheral.services?.filter({$0.uuid == ProfileServiceUUID.MCHP_OTA_SERVICE}){
            //print("LEConnection." + #function)
            
            if filterServices.count != 0{
                if let data_char = filterServices[0].characteristics?.filter({$0.uuid == ProfileServiceUUID.MCHP_OTA_DATA}){
                    ota_data_char = data_char[0]
                    if(!(ota_data_char!.isNotifying)){
                        print("OTAGetCharacteristic. ota_data_char,SetNotify")
                        self.peripheral.setNotifyValue(true, for: ota_data_char!)
                    }
                }
            
                if let control_char = filterServices[0].characteristics?.filter({$0.uuid == ProfileServiceUUID.MCHP_OTA_CONTROL}){
                    ota_control_char = control_char[0]
                    if(!(ota_control_char!.isNotifying)){
                        print("OTAGetCharacteristic. ota_control_char,SetNotify")
                        self.peripheral.setNotifyValue(true, for: ota_control_char!)
                    }
                }
            
                if let feature_char = filterServices[0].characteristics?.filter({$0.uuid == ProfileServiceUUID.MCHP_OTA_FEATURE}){
                    ota_feature_char = feature_char[0]
                }
            }
        }
                
        return (ota_data_char, ota_control_char, ota_feature_char)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error == nil) {
            print("Peripheral UUID : \(peripheral.identifier.uuidString.utf8) found\r\n" );
            
            for service in peripheral.services! {
                let thisService = service as CBService
                print("Service uuid = \(thisService.uuid.uuidString)")
                
                self.peripheral.discoverCharacteristics(nil, for: thisService)
            }
        } else {
            print("Service discovery was unsuccessfull");
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if(error == nil) {
            print("didDiscoverCharacteristics");
            
            for Char in service.characteristics! {
                let thisChar = Char as CBCharacteristic
                print("Characteristic uuid = \(thisChar.uuid.uuidString)")
                
                OTAGetCharacteristic()
            }
        }
        else {
            print("Characteristics discovery was unsuccessfull");
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            print("didWriteValueForCharacteristic");
            print("Characteristic uuid = \(characteristic.uuid.uuidString)")
        }
        else {
            print("didWriteValueForCharacteristic,Error = \(error!.localizedDescription)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            //print("didUpdateValueForCharacteristic");
            //print("Characteristic uuid = \(characteristic.uuid.uuidString)")
            
            self.OTACommandEventCallback?(peripheral, characteristic , characteristic.value!)
        }
        else {
            print("didUpdateValueForCharacteristic,Error")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            if(self.OTAFeatureEnabled != nil){
                print("didUpdateNotificationStateForCharacteristic");
                print("Characteristic uuid = \(characteristic.uuid.uuidString)")
            }
            
            if(characteristic.isNotifying) {
                let (ota_data_char, ota_control_char, ota_feature_char) = OTAGetCharacteristic()
                if(ota_data_char != nil && ota_control_char != nil) {
                    if(ota_data_char!.isNotifying && ota_control_char!.isNotifying) {
                        if(self.OTAFeatureEnabled != nil){
                            self.CharOTAData = ota_data_char
                            self.CharOTAControl = ota_control_char
                            print("[OTA] connection complete!")
                            self.OTAFeatureEnabled?(nil)
                            self.OTAFeatureEnabled = nil
                            peripheral.readValue(for: ota_feature_char!)
                        }
                    }
                }
            }
        }
        else {
            print("didUpdateNotificationStateForCharacteristic,Error")
        }
    }
    
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if #available(iOS 11.0, *) {
            canSendData = peripheral.canSendWriteWithoutResponse
        } else {
            // Fallback on earlier versions
        }
    }
}
