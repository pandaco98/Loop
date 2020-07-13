//
//  DeviceDataManager+DeviceStatus.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2020-07-10.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI

extension DeviceDataManager {
    var cgmStatusHighlight: DeviceStatusHighlight? {
        if bluetoothState == .poweredOff {
            return BluetoothStateManager.bluetoothOffHighlight
        } else if bluetoothState == .denied ||
            bluetoothState == .unauthorized
        {
            return BluetoothStateManager.bluetoothUnavailableHighlight
        } else if cgmManager == nil {
            return DeviceDataManager.addCGMStatusHighlight
        } else {
            return (cgmManager as? CGMManagerUI)?.cgmStatusHighlight
        }
    }
    
    var cgmLifecycleProgress: DeviceLifecycleProgress? {
        return (cgmManager as? CGMManagerUI)?.cgmLifecycleProgress
    }
    
    var pumpStatusHighlight: DeviceStatusHighlight? {
        if bluetoothState == .denied ||
            bluetoothState == .unauthorized ||
            bluetoothState == .poweredOff
        {
            return BluetoothStateManager.bluetoothEnableHighlight
        } else if pumpManager == nil {
            return DeviceDataManager.addPumpStatusHighlight
        } else {
            return pumpManagerStatus?.pumpStatusHighlight
        }
    }
    
    var pumpLifecycleProgress: DeviceLifecycleProgress? {
        return pumpManagerStatus?.pumpLifecycleProgress
    }
    
    static var addCGMStatusHighlight: AddDeviceStatusHighlight {
        return AddDeviceStatusHighlight(localizedMessage: NSLocalizedString("Add CGM", comment: "Title text for button to set up a CGM"))
    }
    
    static var addPumpStatusHighlight: AddDeviceStatusHighlight {
        return AddDeviceStatusHighlight(localizedMessage: NSLocalizedString("Add Pump", comment: "Title text for button to set up a Pump"))
    }
    
    struct AddDeviceStatusHighlight: DeviceStatusHighlight {
        var localizedMessage: String
        var imageSystemName: String = "plus.circle"
        var state: DeviceStatusHighlightState = .normal
    }
    
    func didTapOnCGMStatus(_ view: BaseHUDView? = nil) -> HUDTapAction? {
        if let action = bluetoothState.action {
            return action
        } else if let url = cgmManager?.appURL,
            UIApplication.shared.canOpenURL(url)
        {
            return .openAppURL(url)
        } else if let cgmManagerUI = (cgmManager as? CGMManagerUI),
            let unit = loopManager.glucoseStore.preferredUnit
        {
            return .presentViewController(cgmManagerUI.settingsViewController(for: unit))
        } else {
            return .setupNewCGM
        }
    }
    
    func didTapOnPumpStatus(_ view: BaseHUDView? = nil) -> HUDTapAction? {
        if let action = bluetoothState.action {
            return action
        } else if let pumpManagerHUDProvider = pumpManagerHUDProvider,
            let view = view,
            let action = pumpManagerHUDProvider.didTapOnHUDView(view)
        {
            return action
        } else if let pumpManager = pumpManager {
            return .presentViewController(pumpManager.settingsViewController())
        } else {
            return .setupNewPump
        }
    }
}