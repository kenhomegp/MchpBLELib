//
//  DeviceInformation.swift
//  MchpBLELib
//
//  Created by WSG Software on 2022/10/25.
//

import Foundation
import CoreBluetooth

public enum DIS_Index: UInt8, CaseIterable {
    case MANUFACTURE_NAME = 0x00
    case MODEL_NUMBER
    case SERIAL_NUMBER
    case HARDWARE_REVISION
    case FIRMWARE_REVISION
    case SOFTWARE_REVISION
    case SYSTEM_ID
    case IEEE_11073_20601_REGULATORY_CERTIFICATION_DATA_LIST
    case PNP_ID
}

struct DeviceInformationService{
    //Device Info service
    static let DEVICE_INFO_SERVICE = CBUUID(string: "180A")
    static let DIS_MANUFACTURE_NAME_CHAR = CBUUID(string: "2A29")
    static let DIS_MODEL_NUMBER_CHAR = CBUUID(string: "2A24")
    static let DIS_SERIAL_NUMBER_CHAR = CBUUID(string: "2A25")
    static let DIS_HARDWARE_REVISION_CHAR = CBUUID(string: "2A27")
    static let DIS_FIRMWARE_REVISION_CHAR = CBUUID(string: "2A26")
    static let DIS_SOFTWARE_REVISION_CHAR = CBUUID(string: "2A28")
    static let DIS_SYSTEM_ID_CHAR = CBUUID(string: "2A23")
    static let DIS_IEEE_11073_20601_CHAR = CBUUID(string: "2A2A")
    static let DIS_PNP_ID_CHAR = CBUUID(string: "2A50")
    
    let DIS_UUID = [DIS_MANUFACTURE_NAME_CHAR, DIS_MODEL_NUMBER_CHAR, DIS_SERIAL_NUMBER_CHAR, DIS_HARDWARE_REVISION_CHAR, DIS_FIRMWARE_REVISION_CHAR, DIS_SOFTWARE_REVISION_CHAR, DIS_SYSTEM_ID_CHAR, DIS_IEEE_11073_20601_CHAR,DIS_PNP_ID_CHAR]
    
    var PeripheralUUID: String?
    var DISArray = Dictionary<DIS_Index,String>()
    
    mutating func ClearData(){
        self.DISArray.removeAll()
    }
    
    mutating func SetValue(index:DIS_Index, value: String){
        print("SetDIS. index = \(index), value = \(value)")
        if value == ""{
            self.DISArray[index] = value
        }
        else{
            self.DISArray.updateValue(value, forKey: index)
        }
    }
    
    mutating func SetPeripheral(uuid: String){
        self.PeripheralUUID = uuid
    }
    
    subscript(index: Int) -> CBUUID{
        return DIS_UUID[index]
    }
    
    func CBUUIDToDISIndex(uuid: CBUUID) -> DIS_Index?{
        var disIndex: DIS_Index? = nil
        for index in DIS_Index.allCases{
            if DIS_UUID[Int(index.rawValue)] == uuid{
                disIndex = index
                break
            }
        }
        return disIndex
    }
    
    func DataReady() -> Bool{
        if(self.DISArray.isEmpty){
            return false
        }
        else{
            for (index, value) in self.DISArray{
                print("[DIS] index = \(index), value = \(value)")
                if(value == ""){
                    return false
                }
            }
            return true
        }
    }
}

protocol DIS_Profile {
    var DIS: DeviceInformationService  { get set}
    func GetDeviceInformation()
    func DIS_Peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) -> Bool?
    var DISUpdateValues: ((deviceUUID, [DIS_Index:String])->Void)? {get set}
}

