import CoreFoundation
import Foundation
import IOKit
import IOKit.pwr_mgt

private let wakeSignal = DispatchSemaphore(value: 0)
private let monitorReady = DispatchSemaphore(value: 0)
private let stateLock = NSLock()
// These are iokit_common_msg(0x270/0x280/0x300); the C macros are not imported by Swift.
private let canSystemSleepMessage: UInt32 = 0xE0000270
private let systemWillSleepMessage: UInt32 = 0xE0000280
private let systemHasPoweredOnMessage: UInt32 = 0xE0000300
private var rootPowerPort: io_connect_t = 0
private var notificationPort: IONotificationPortRef?
private var powerNotifier: io_object_t = 0
private var startupStatus: Int32 = -1
private var monitorStarted = false

private func powerStateChanged(
    _ refcon: UnsafeMutableRawPointer?,
    _ service: io_service_t,
    _ messageType: natural_t,
    _ messageArgument: UnsafeMutableRawPointer?
) {
    if messageType == canSystemSleepMessage
        || messageType == systemWillSleepMessage {
        if let messageArgument {
            IOAllowPowerChange(rootPowerPort, Int(bitPattern: messageArgument))
        }
    } else if messageType == systemHasPoweredOnMessage {
        wakeSignal.signal()
    }
}

@_cdecl("clashy_wake_monitor_start")
public func clashyWakeMonitorStart() -> Int32 {
    stateLock.lock()
    if monitorStarted {
        stateLock.unlock()
        return 0
    }
    monitorStarted = true
    stateLock.unlock()

    Thread.detachNewThread {
        var localNotificationPort: IONotificationPortRef?
        var localNotifier: io_object_t = 0
        let localRootPort = IORegisterForSystemPower(
            nil,
            &localNotificationPort,
            powerStateChanged,
            &localNotifier
        )

        guard localRootPort != 0,
            let localNotificationPort,
            let runLoopSource = IONotificationPortGetRunLoopSource(
                localNotificationPort
            )?.takeUnretainedValue()
        else {
            stateLock.lock()
            startupStatus = -1
            stateLock.unlock()
            monitorReady.signal()
            return
        }

        stateLock.lock()
        rootPowerPort = localRootPort
        notificationPort = localNotificationPort
        powerNotifier = localNotifier
        startupStatus = 0
        stateLock.unlock()

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            runLoopSource,
            .defaultMode
        )
        monitorReady.signal()
        CFRunLoopRun()
    }

    monitorReady.wait()
    stateLock.lock()
    let result = startupStatus
    stateLock.unlock()
    return result
}

@_cdecl("clashy_wake_monitor_wait")
public func clashyWakeMonitorWait() -> Int32 {
    wakeSignal.wait()
    return 0
}
