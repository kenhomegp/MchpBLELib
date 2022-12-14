//
//  CBPeripheralAdapter.swift
//  MchpBLELib
//
//  Created by WSG Software on 2022/10/20.
//

import Foundation
import CoreBluetooth

class CBPeripheralAdapter: NSObject, CBPeripheralDelegate{
    private var peripheral: CBPeripheral
    
    internal init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self
    }
    
    // MARK: - CoreBluetooth delegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error == nil) {
            print("Peripheral UUID : \(peripheral.identifier.uuidString.utf8) found\r\n" );
            
            
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
                
                
            }
        }
        else {
            print("Characteristics discovery was unsuccessfull");
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            
        }
        else {
            print("didWriteValueForCharacteristic,Error = \(error!.localizedDescription)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            //print("[Connection]didUpdateValueForCharacteristic");
            //print("Characteristic uuid = \(characteristic.uuid.uuidString)")
            
            
        }
        else {
            print("didUpdateValueForCharacteristic,Error")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if(error == nil) {
            print("didUpdateNotificationStateForCharacteristic");
            print("Characteristic uuid = \(characteristic.uuid.uuidString)")
            
            if(characteristic.isNotifying) {
                
            }
        }
        else {
            print("didUpdateNotificationStateForCharacteristic,Error")
            print(characteristic.uuid.uuidString)
        }
    }
    
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        //print("peripheralIsReady = \(peripheral.canSendWriteWithoutResponse)")
    }
}
