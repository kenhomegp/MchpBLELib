//
//  BLEAdapter.swift
//  BleOTALib
//
//  Created by WSG Software on 30/10/2017.
//  Copyright © 2017 WSG Software. All rights reserved.
//

import UIKit
import CoreBluetooth
import AVFoundation

typealias ConnectionError = String
typealias peripheralUUID = String

public typealias peripheralInfo = (String, NSNumber)

public enum CentralOption {
    case Normal
    case StatePreservation
}

public enum ScanOption {
    case ScanAllowDuplicate
    case Scan
}

class BLEAdapter: NSObject, CBCentralManagerDelegate, DeviceScanFilter{
    
    typealias FilterData = [FilterOption: Any]
    
    var centralManager: CBCentralManager?
    
    var activePeripheral: CBPeripheral?

    //var RestoredPeripheral: CBPeripheral?
    
    //var LastConnectedPeripheral_udid: String! = ""
    
    var Peripheral_List = Dictionary<peripheralUUID,Microchip_Peripheral>()

    var BLE_didDiscoverUpdateState: ((Bool) -> Void)?
    
    var ConnectionStatusUpdate: ((ConnectionError?, CBPeripheral) -> Void)?
    
    var bleScanTimer: Timer?
    
    var central_init_option: CentralOption = .Normal
    
    var scanOption: ScanOption = .Scan
    
    var filter: UInt8 = FilterOption.FilterByMCHPBeacon.rawValue
    
    var filterString: String?
    
    var filterServiceUUID: CBUUID?
    
    var filterServiceDataKey: String?
    
    // MARK: - Coding here
    
    init(option: CentralOption) {
        super.init()
                
        self.central_init_option = option
        print("Central init option = \(self.central_init_option)")
        /*
        if option == .StatePreservation {
            if let peripheral_udid_str = UserDefaults.standard.object(forKey: "STATE_PRESERVE_PERIPHERAL_UDID") as? String{
                LastConnectedPeripheral_udid = peripheral_udid_str
                print("[GetUserDefault]Last connected peripheral udid = \(LastConnectedPeripheral_udid ?? "")")
            }
        }
        
        if option == .StatePreservation {
            print("CBCentral")
            let option = [CBCentralManagerOptionRestoreIdentifierKey: "my-central-identifier"]
                self.centralManager = CBCentralManager(delegate: self, queue: nil, options: option)
        }
        else{
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
        }*/
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
            
        activePeripheral = nil
        //RestoredPeripheral = nil
    }
    
    deinit {
        print("BLEAdapter deinit")
    }
    
    private static var mInstance:BLEAdapter?
    
    class func sharedInstace(option : CentralOption) -> BLEAdapter {
        if(mInstance == nil) {
            print("Create instance. option = \(option)")
            mInstance = BLEAdapter(option: option)
            print("New BLEAdapter object")
        }
        return mInstance!
    }
    
    func DestroyInstance(){
        print(#function)
        
        if self.activePeripheral != nil{
            disconnectPeripheral()
        }
        
        if(self.centralManager!.isScanning){
            self.centralManager?.stopScan()
        }
        
        self.centralManager = nil
        
        if self.bleScanTimer != nil{
            if bleScanTimer!.isValid{
                bleScanTimer?.invalidate()
                bleScanTimer = nil
            }
        }

        BLEAdapter.mInstance = nil
    }
    
    func RetrieveConnectedPeripheral() -> [CBPeripheral] {
        print("RetrieveConnectedPeripheral")
        
        let aryUUID = ["180A", "49535343-FE7D-4AE5-8FA9-9FAFD205E455", "49535343-2120-45FC-BDDB-E8A01AEDEC50"]
        var aryCBUUIDS = [CBUUID]()

        for uuid in aryUUID{
            let uuid = CBUUID(string: uuid)
            aryCBUUIDS.append(uuid)
        }
        
        return centralManager?.retrieveConnectedPeripherals(withServices: aryCBUUIDS) ?? []
    }
    
    func findAllBLEPeripherals(_ timeOut:Double, scanOption:ScanOption){
        if #available(iOS 10.0, *) {
            if(self.centralManager?.state != CBManagerState.poweredOn){
                print("BLE is not avaliable!")
                print("BT state = \(centralManager?.state.rawValue ?? -1)")
            }
        } else {
            // Fallback on earlier versions
        }
        
        if(self.centralManager!.isScanning){
            print("Stop Scan")
            FilterOptionReset()
            self.centralManager?.stopScan()
            sleep(1)
        }
        
        self.Peripheral_List.removeAll()

        if self.bleScanTimer != nil{
            if bleScanTimer!.isValid{
                bleScanTimer?.invalidate()
                bleScanTimer = nil
            }
        }
        
        bleScanTimer = Timer.scheduledTimer(timeInterval: timeOut, target: self, selector: #selector(BLEAdapter.scanTimeout), userInfo: nil, repeats: false)
        
        self.scanOption = scanOption
        
        print("Scan ALL device.\(self.scanOption),\(self.filter)")
        
        if self.scanOption == .ScanAllowDuplicate{
            centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        }
        else if self.scanOption == .Scan{
            centralManager?.scanForPeripherals(withServices: nil, options: nil)   //Scan All Device
        }
        else{
            //CBCentralManagerRestoredStateScanOptionsKey
            
            //print("State preservation and restoration Test")
            //State preservation and restoration
            //let option = [CBCentralManagerOptionRestoreIdentifierKey: "my-central-identifier"]
            //centralManager?.scanForPeripherals(withServices: nil, options: option)
            
            //centralManager?.scanForPeripherals(withServices: [CBUUID(string: UUIDSTR_MCHP_PROPRIETARY_SERVICE)], options: option)
            
            centralManager?.scanForPeripherals(withServices: nil, options: nil)   //Scan All Device
        }
        
        self.BLE_didDiscoverUpdateState?(centralManager!.isScanning)
    }
    
    func disconnectPeripheral() {
        if(activePeripheral != nil) {
            print("disconnectPeripheral")
            
            centralManager!.cancelPeripheralConnection(activePeripheral!)
            
            activePeripheral = nil
            /*
            LastConnectedPeripheral_udid = ""
            
            if central_init_option == .StatePreservation{
                UserDefaults.standard.removeObject(forKey: "STATE_PRESERVE_PERIPHERAL_UDID")
            }*/
        }
    }
    
    @objc func scanTimeout() {
        centralManager?.stopScan()
        print("[Scan Timeout]Stopped Scanning")
        
        FilterOptionReset()
        
        if bleScanTimer!.isValid{
            bleScanTimer?.invalidate()
            bleScanTimer = nil
        }
        
        self.BLE_didDiscoverUpdateState?(centralManager!.isScanning)
        
        print("Known Microchip peripherals = \(self.Peripheral_List.count)")
        
        printKnownPeripherals()
    }
    
    func printKnownPeripherals() {
        if(!Peripheral_List.isEmpty) {
            print("Print Microchip Peripheral")

            for peripheral in Peripheral_List.values{
                printPeripheralInfo(peripheral.peripheral!)
                print("-------------------------------------\r\n");
                print("Microchip peripheral:")
                print("ID = \(peripheral.peripheral?.identifier.uuidString ?? "")")
                print("ADV = \(String(describing: peripheral.advertisementData))")
                print("RSSI = \(String(describing: peripheral.rssi))")
                //print("Services = \(obj.peripheral?.services)")
                //print("ADV = \(obj.advertisementData)")
                //print("RSSI = \(obj.rssi)")
                
                /*
                if let adv = obj.advertisementData{
                    if let test1 = adv["kCBAdvDataServiceData"] as? [NSObject:AnyObject] {
                        if let test2 = test1[CBUUID(string:"FEDA")] as? NSData {
                            print("data beacon = \(test2 )")
                        }
                    }
                }*/
            }
        }
    }
    
    func printPeripheralInfo(_ peripheral: CBPeripheral) {
        print("------------------------------------\r\n");
        print("Peripheral Info :\r\n");
        if(peripheral.name != nil) {
            print("Peripheral Name : \(peripheral.name!)");
        }
        else {
            print("Name : nil")
        }
        print("isConnected : \(peripheral.state.rawValue)");
    }
    
    func PeripheralName() -> String {
        if(activePeripheral != nil){
            return (activePeripheral?.name)!
        }
        else {
            return "Disconnected"
        }
    }
    
    func DIS_ConvertData(dat: Data) -> String {
        let bytes = [UInt8](dat)
        var str = ""
        for i in 0..<bytes.count{
            if(bytes[i] < 0x10){
                str.append(String(format: "0%x", bytes[i]))
            }
            else{
                str.append(String(format: "%x", bytes[i]))
            }
        }
        
        return str
    }
    
    func ConnectPeripheral(peripheral_uuid: String = "", peripheral_name: String = "") {
        print(#function)
        
        if self.centralManager!.isScanning{
            FilterOptionReset()
            self.centralManager?.stopScan()
            
            if self.bleScanTimer != nil{
                if bleScanTimer!.isValid{
                    bleScanTimer?.invalidate()
                    bleScanTimer = nil
                }
            }
        }
        
        if(peripheral_uuid != ""){
            if(Peripheral_List[peripheral_uuid] != nil){
                activePeripheral = Peripheral_List[peripheral_uuid]?.peripheral
                if(activePeripheral != nil){
                    centralManager?.connect(activePeripheral!, options: nil)
                }
            }
        }
        else{
            if(peripheral_name != ""){
                for (_, mchpPeripheral) in Peripheral_List{
                    if mchpPeripheral.deviceName == peripheral_name{
                        centralManager?.connect(mchpPeripheral.peripheral!, options: nil)
                        break
                    }
                }
            }
        }
    }
    
    func ScanAllowDuplicatePeripheral(p:CBPeripheral, ADV_Data: [String : Any], rssi:NSNumber){
        if(scanOption == .ScanAllowDuplicate){
        }
    }
    
    func GetPeripheralNameList() -> Dictionary<String, String>{
        if(!Peripheral_List.isEmpty){
            print(#function)
            var NameList = Dictionary<String,String>()
            for(udid, mchpPeripheral) in Peripheral_List{
                NameList[udid] = mchpPeripheral.deviceName
            }
            return NameList
        }
        else{
            return [:]
        }
    }
    
    func GetPeripheralNameRSSIList() -> Dictionary<String, NSNumber>{
        if(!Peripheral_List.isEmpty){
            print(#function)
            var RSSIList = Dictionary<String,NSNumber>()
            
            for(_, mchpPeripheral) in Peripheral_List{
                RSSIList[mchpPeripheral.deviceName!] = mchpPeripheral.rssi
            }
            return RSSIList
        }
        else{
            return [:]
        }
    }
    
    // MARK: - ScanDevice Filter
    
    func SetFilter(filter: [FilterOption : Any]) {
        print("SetFilter")
        for(filterMode, filterData) in filter{
            if(filterMode == .FilterBySpecificString && filterData is String){
                filterString = filter.values.first as? String
                print("Set filter string = \(filterString ?? "")")
                self.filter |= filterMode.rawValue
            }
            else if(filterMode == .FilterByServiceUUID && filterData is CBUUID){
                filterServiceUUID = filterData as? CBUUID
                print("Set filter, serviceUUID = \(filterServiceUUID?.uuidString ?? "")")
                self.filter |= filterMode.rawValue
            }
            else if(filterMode == .FilterByMCHPBeacon && filterData is String){
                filterServiceDataKey = filter.values.first as? String
                print("Set filter, ServiceDataKey = \(filterServiceDataKey ?? "")")
                self.filter |= filterMode.rawValue
            }
            else if(filterMode == .NoFilter){
                print("No filter")
                self.filter = filterMode.rawValue
            }
        }
        print("filter value = \(self.filter)")
    }
    
    func FilterOptionReset(){
        filter = FilterOption.FilterByMCHPBeacon.rawValue
        filterString = nil
        filterServiceUUID = nil
    }
    
    func FilterDeviceByMCHPDataBeacon(p:CBPeripheral, deviceName:String, ADV_Data: [String : Any], rssi:NSNumber){
        
        if let beacondata = Data_Beacon_Information.Parsing_adv_data(advdata: ADV_Data){
            print(#function)
            if(Peripheral_List[p.identifier.uuidString] == nil){
                Peripheral_List[p.identifier.uuidString] = Microchip_Peripheral(device: p, devName: deviceName, deviceInfo: beacondata, adv: ADV_Data, rssi: rssi)
                print("[Microchip peripheral] Add peripheral,local name = \(deviceName)")
                self.BLE_didDiscoverUpdateState?(centralManager!.isScanning)
            }
            else{
                Peripheral_List.updateValue(Microchip_Peripheral(device: p, devName: deviceName, deviceInfo: beacondata, adv: ADV_Data, rssi: rssi), forKey: p.identifier.uuidString)
                print("Update peripheral,local name = \(deviceName)")
            }
        }
    }
    
    func FilterDeviceBySpecificName(p:CBPeripheral, deviceName:String, rssi:NSNumber) {
        
        let nameLowercase = deviceName.lowercased()
        if(filterString != nil && nameLowercase.contains(filterString!)){
            print(#function)
            if(Peripheral_List[p.identifier.uuidString] == nil){
                Peripheral_List[p.identifier.uuidString] = Microchip_Peripheral(device: p, devName: deviceName, rssi: rssi)
                print("Add peripheral,local name = \(deviceName). filterString = \(filterString!)")
                self.BLE_didDiscoverUpdateState?(centralManager!.isScanning)
            }
            else{
                Peripheral_List.updateValue(Microchip_Peripheral(device: p, devName: deviceName, rssi: rssi), forKey: p.identifier.uuidString)
                print("Update peripheral,local name = \(deviceName)")
            }
        }
    }
    
    func FilterDeviceByServiceUUID(p:CBPeripheral, deviceName:String, ADV_Data: [String : Any], rssi:NSNumber) {
        
        if let ServiceUUIDs = ADV_Data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]{
            //print("ServiceUUIDs found!\(ServiceUUIDs)")
            
            for ServiceUUID_ in ServiceUUIDs{
                //print("uuidStr = \(ServiceUUID_.uuidString)")
                if(ServiceUUID_.uuidString == ProfileServiceUUID.MCHP_OTA_SERVICE.uuidString){
                    print(#function)
                    if(Peripheral_List[p.identifier.uuidString] == nil){
                        print("ServiceUUID is found!, Add peripheral = \(deviceName)")
                        Peripheral_List[p.identifier.uuidString] = Microchip_Peripheral(device: p, devName: deviceName, rssi: rssi)
                        self.BLE_didDiscoverUpdateState?(centralManager!.isScanning)
                        break
                    }
                    else{
                        Peripheral_List.updateValue(Microchip_Peripheral(device: p, devName: deviceName, rssi: rssi), forKey: p.identifier.uuidString)
                        print("Update peripheral,local name = \(deviceName)")
                    }
                }
            }
        }
    }
    
    // MARK: - CentralManager delegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if #available(iOS 10.0, *) {
            switch (central.state) {
            case CBManagerState.poweredOff:
                print("Status of CoreBluetooth Central Manager = Power Off")
                break
            case CBManagerState.unauthorized:
                print("Status of CoreBluetooth Central Manager = Does Not Support BLE")
                break
            case CBManagerState.unknown:
                print("Status of CoreBluetooth Central Manager = Unknown Wait for Another Event")
                break
            case CBManagerState.poweredOn:
                print("Status of CoreBluetooth Central Manager = Powered On")
                /*if central_init_option == .StatePreservation{
                    if self.RestoredPeripheral != nil{
                        centralManager?.connect(self.RestoredPeripheral!, options: nil)
                        self.activePeripheral = self.RestoredPeripheral
                    }
                }*/
                break
            case CBManagerState.resetting:
                print("Status of CoreBluetooth Central Manager = Resetting Mode")
                break
            case CBManagerState.unsupported:
                print("Status of CoreBluetooth Central Manager = Un Supported")
                break
            @unknown default:
                print("CoreBluetooth Central:Unknown state")
            }
        } else {
            // Fallback on earlier versions
            switch (central.state.rawValue) {
                case 3: //CBCentralManagerState.unauthorized
                    print("This app is not authorized to use Bluetooth low energy")
                    break
                case 4:
                    print("Bluetooth is currently powered off")
                    break
                case 5:
                    print("Bluetooth is currently powered on and available to use")
                    break
                default:break
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("centralManager, willRestoreState")
        /*
        if self.central_init_option != .StatePreservation{
            return
        }
        
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]{
            print("\(peripherals)")
            
            //print("Last connected peripheral udid = \(LastConnectedPeripheral_udid)")
            
            if LastConnectedPeripheral_udid != ""{
                for pp in peripherals{
                    if pp.identifier.uuidString == LastConnectedPeripheral_udid{
                        print("Connect to \(pp.name ?? "")")
                        self.RestoredPeripheral = pp
                        self.RestoredPeripheral?.delegate = self
                        //print("\(dict[CBCentralManagerRestoredStateScanOptionsKey])")
                        break
                    }
                }
            }
        }*/
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        ScanAllowDuplicatePeripheral(p: peripheral, ADV_Data: advertisementData, rssi: RSSI)
        
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            if(filter == FilterOption.NoFilter.rawValue){
                Peripheral_List[peripheral.identifier.uuidString] = Microchip_Peripheral(device: peripheral, adv: advertisementData, rssi: RSSI)
                print("ScanWithoutFilter .Add peripheral,local name = \(name)")
                self.BLE_didDiscoverUpdateState?(centralManager!.isScanning)
            }
            else{
                if((filter & FilterOption.FilterByMCHPBeacon.rawValue) == FilterOption.FilterByMCHPBeacon.rawValue){
                    FilterDeviceByMCHPDataBeacon(p: peripheral, deviceName: name, ADV_Data: advertisementData, rssi: RSSI)
                }
                
                if((filter & FilterOption.FilterByServiceUUID.rawValue) == FilterOption.FilterByServiceUUID.rawValue){
                    FilterDeviceByServiceUUID(p: peripheral, deviceName: name, ADV_Data: advertisementData, rssi: RSSI)
                }
                
                if((filter & FilterOption.FilterBySpecificString.rawValue) == FilterOption.FilterBySpecificString.rawValue){
                    FilterDeviceBySpecificName(p: peripheral, deviceName: name, rssi: RSSI)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[centralManager] didConnect")
        activePeripheral = peripheral
        print("Peripheral ID = " + activePeripheral!.identifier.uuidString)
        /*
        LastConnectedPeripheral_udid = activePeripheral!.identifier.uuidString
        
        if central_init_option == .StatePreservation{
            UserDefaults.standard.set(LastConnectedPeripheral_udid, forKey: "STATE_PRESERVE_PERIPHERAL_UDID")
        }*/
        
        if(central.isScanning){
            FilterOptionReset()
            print("Stop Scan")
            central.stopScan()
        }

        self.ConnectionStatusUpdate?(nil, peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[centralManager] didFailToConnect")
        
        var msg : String = ""
        
        if error != nil{
            print(error.debugDescription)
            msg = error!.localizedDescription
        }

        self.ConnectionStatusUpdate?(msg, peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[centralManager] didDisconnectPeripheral")
        
        var error_str: String = ""
        
        if(error != nil){
            print("error = \(error!),\(error!.localizedDescription)")
            error_str = error!.localizedDescription
        }
        
        self.ConnectionStatusUpdate?(error_str, peripheral)

        activePeripheral = nil
        
        //RestoredPeripheral = nil
    }
}
