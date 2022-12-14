//
//  DeviceFilter.swift
//  BleUARTLib
//
//  Created by WSG Software on 2022/9/28.
//

import Foundation
import CoreBluetooth

struct Data_Beacon_Information {
    var category: UInt8 = 0xff
    var product_type: UInt8 = 0
    var product_data: [UInt8] = []
    
    static func Parsing_adv_data(advdata: [String : Any]?) -> Data_Beacon_Information?{
                
        if let serviceData = advdata!["kCBAdvDataServiceData"] as? [NSObject:AnyObject] {
            //print("service data = \(serviceData)")
            
            if let data_beacon = serviceData[CBUUID(string:"FEDA")] as? Data {
                
                let bytes = [UInt8](data_beacon)
                
                var beacon = Data_Beacon_Information()

                if(bytes[0] == 0xff && data_beacon.count >= 2){
                    beacon.category = bytes[0]
                    beacon.product_type = bytes[1]
                
                    if(data_beacon.count > 2){
                        for i in 0..<(data_beacon.count-2){
                            beacon.product_data.append(bytes[2+i])
                        }
                    }
                    print("mchpBeacon data = \(data_beacon as NSData )")
                    return beacon
                }
            }
        }
        return nil
    }
}

struct Microchip_Peripheral{
    var peripheral: CBPeripheral?
    var advertisementData: [String : Any]?
    var rssi: NSNumber?
    var data_beacon: Data_Beacon_Information?
    var deviceName: String?
    
    init(device: CBPeripheral, devName: String, rssi: NSNumber){
        self.peripheral = device
        self.deviceName = devName
        self.rssi = rssi
    }
    
    init(device: CBPeripheral, adv: [String : Any], rssi: NSNumber) {
        self.peripheral = device
        self.advertisementData = adv
        self.rssi = rssi
    }
    
    init(device: CBPeripheral, devName: String, deviceInfo: Data_Beacon_Information, adv: [String : Any], rssi: NSNumber) {
        self.peripheral = device
        self.deviceName = devName
        self.data_beacon = deviceInfo
        self.advertisementData = adv
        self.rssi = rssi
    }
}

public enum FilterOption: UInt8 {
    case NoFilter = 0x00
    case FilterByMCHPBeacon = 0x01
    case FilterBySpecificString = 0x02
    case FilterByServiceUUID = 0x04
}

protocol DeviceScanFilter{
    associatedtype FilterData
    var filter: UInt8 {get set}
    var filterString: String? {get set}
    var filterServiceUUID: CBUUID? {get set}
    var filterServiceDataKey: String? {get set}
    
    func FilterOptionReset()
    func FilterDeviceByMCHPDataBeacon(p:CBPeripheral, deviceName:String, ADV_Data: [String : Any], rssi:NSNumber)
    func FilterDeviceBySpecificName(p:CBPeripheral, deviceName:String, rssi:NSNumber)
    func FilterDeviceByServiceUUID(p:CBPeripheral, deviceName:String, ADV_Data: [String : Any], rssi:NSNumber)
    func SetFilter(filter: FilterData)
}
