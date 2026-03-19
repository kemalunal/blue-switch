import Foundation
import IOBluetooth
import SwiftUI

/// Protocol defining the interface for Bluetooth peripheral management operations
protocol BluetoothPeripheralManageable {
  /// Fetches and updates the list of connected peripherals
  func fetchConnectedPeripherals()

  /// Adds a new peripheral to the managed list
  func addPeripheral(_ peripheral: BluetoothPeripheral)

  /// Initiates connection to a peripheral
  func connectPeripheral(_ peripheral: BluetoothPeripheral)

  /// Disconnects from a peripheral
  func disconnectPeripheral(_ peripheral: BluetoothPeripheral)
}

/// Manages the state and operations of Bluetooth peripherals
final class BluetoothPeripheralStore: NSObject, ObservableObject, BluetoothPeripheralManageable {
  // MARK: - Singleton

  static let shared = BluetoothPeripheralStore()

  // MARK: - Constants

  private enum Constants {
    static let queueLabel = "com.blueswitch.bluetooth"
    static let invalidRSSI: Int32 = 127
    static let handoffRetryCount = 10
    static let handoffRetryDelay: TimeInterval = 1.0
    static let connectionPollAttempts = 10
    static let connectionPollInterval: TimeInterval = 1.0
    static let stableStateConfirmations = 3
    static let forceDisconnectAttempts = 60
  }

  // MARK: - Dependencies

  private let bluetoothQueue = DispatchQueue(label: Constants.queueLabel, qos: .userInitiated)

  // MARK: - Properties

  @AppStorage("peripherals") private var peripheralsData: Data = Data()

  @Published private(set) var peripherals: [BluetoothPeripheral] = [] {
    didSet {
      savePeripherals()
      cachedConnectionStates = currentConnectionStates()
    }
  }

  @Published private(set) var discoveredPeripherals: [BluetoothPeripheral] = []
  private var cachedConnectionStates: [String: Bool] = [:]
  
  // Storage for async pairing delegation
  private var currentDevicePair: IOBluetoothDevicePair?
  private var pairingCompletion: ((IOReturn) -> Void)?

  // MARK: - Computed Properties

  var availablePeripherals: [BluetoothPeripheral] {
    discoveredPeripherals.filter { discovered in
      !peripherals.contains(where: { $0.id == discovered.id })
    }
  }

  var isAllDevicesConnected: Bool {
    guard !peripherals.isEmpty else { return false }
    return peripherals.allSatisfy { peripheral in
      guard let btDevice = IOBluetoothDevice(addressString: peripheral.id) else { return false }
      return btDevice.isConnected()
    }
  }

  // MARK: - Initialization

  private override init() {
    super.init()
    loadPeripherals()
    cachedConnectionStates = currentConnectionStates()
    fetchConnectedPeripherals()
  }

  // MARK: - Public Methods

  /// Adds a peripheral to the managed list in connected state
  /// - Parameter peripheral: The peripheral to add
  func addPeripheral(_ peripheral: BluetoothPeripheral) {
    guard validateBluetoothState() else { return }
    guard validateDeviceExists(peripheral) else { return }

    peripherals.append(peripheral)
    refreshPeripheralState()
  }

  /// Removes peripheral information from the system while maintaining it in the list
  /// - Parameter peripheral: The peripheral to unregister
  func unregisterFromPC(_ peripheral: BluetoothPeripheral) {
    guard validateBluetoothState() else { return }
    guard let btDevice = getBluetoothDevice(for: peripheral) else { return }

    if !btDevice.isConnected() {
      print("Device is already disconnected: \(peripheral.name)")
      refreshPeripheralState()
      return
    }

    if btDevice.responds(to: Selector(("remove"))) {
      btDevice.perform(Selector(("remove")))
      print("Device information removed: \(peripheral.name)")
    } else {
      print("Failed to remove device information: \(peripheral.name)")
    }
    refreshPeripheralState()
  }

  /// Completely remove device from list
  func removeFromList(_ peripheral: BluetoothPeripheral) {
    guard let index = peripherals.firstIndex(where: { $0.id == peripheral.id }) else {
      print("\(peripheral.name) does not exist in the list")
      return
    }

    //    if let btDevice = IOBluetoothDevice(addressString: peripheral.id),
    //      btDevice.isConnected()
    //    {
    //      print("\(peripheral.name) is connected. Please disconnect before removing")
    //      return
    //    }

    peripherals.removeAll { $0.id == peripheral.id }
    print("\(peripheral.name) has been removed from the list")
    refreshPeripheralState()
  }

  func connectPeripheral(_ peripheral: BluetoothPeripheral) {
    connectPeripheral(peripheral) { _ in }
  }

  func connectPeripheral(_ peripheral: BluetoothPeripheral, completion: @escaping (Bool) -> Void) {
    connectPeripheral(
      peripheral,
      attempt: 1,
      completion: completion
    )
  }

  func connectPeripheralsForHandoff(
    _ peripherals: [BluetoothPeripheral], completion: @escaping (Bool) -> Void
  ) {
    performSequentialOperation(on: peripherals, completion: completion) { peripheral, operationCompletion in
      self.connectPeripheral(peripheral, completion: operationCompletion)
    }
  }

  func disconnectPeripheralForHandoff(
    _ peripheral: BluetoothPeripheral, completion: @escaping (Bool) -> Void
  ) {
    bluetoothQueue.async { [weak self] in
      guard let self = self else { return }
      print("Starting handoff disconnect for \(peripheral.name)")

      guard self.validateBluetoothState() else {
        self.finishBluetoothOperation(
          success: false,
          completion: completion
        )
        return
      }

      guard let btDevice = self.getBluetoothDevice(for: peripheral) else {
        self.finishBluetoothOperation(
          success: false,
          completion: completion
        )
        return
      }

      if !btDevice.isConnected() {
        print("\(peripheral.name) is already disconnected for handoff")
        self.finishBluetoothOperation(success: true, completion: completion)
        return
      }

      if btDevice.responds(to: Selector("remove")) {
        btDevice.perform(Selector("remove"))
        print("Successfully UNPAIRED \(peripheral.name).")
      } else {
        btDevice.closeConnection()
        print("Fallback: closeConnection for \(peripheral.name) because remove selector was unavailable.")
      }

      print("Allowing handoff to proceed to the other Mac.")
      self.finishBluetoothOperation(success: true, completion: completion)
    }
  }

  func disconnectPeripheralsForHandoff(
    _ peripherals: [BluetoothPeripheral], completion: @escaping (Bool) -> Void
  ) {
    performSequentialOperation(on: peripherals, completion: completion) { peripheral, operationCompletion in
      self.disconnectPeripheralForHandoff(peripheral, completion: operationCompletion)
    }
  }

  /// Disconnect device
  func disconnectPeripheral(_ peripheral: BluetoothPeripheral) {
    guard IOBluetoothHostController.default().powerState != kBluetoothHCIPowerStateOFF else {
      print("Bluetooth is turned off")
      return
    }

    guard let btDevice = IOBluetoothDevice(addressString: peripheral.id) else {
      print("\(peripheral.name) not found")
      return
    }

    if !btDevice.isConnected() {
      print("\(peripheral.name) is already disconnected")
      return
    }

    let result = btDevice.closeConnection()
    if result == kIOReturnSuccess {
      print("Disconnected from \(peripheral.name)")
    } else {
      print("Failed to disconnect from \(peripheral.name). Error code: \(result)")
    }
    refreshPeripheralState()
  }

  func fetchConnectedPeripherals() {
    bluetoothQueue.async { [weak self] in
      guard let self = self else { return }

      guard IOBluetoothHostController.default().powerState != kBluetoothHCIPowerStateOFF else {
        print("Bluetooth is turned off")
        return
      }

      guard let pairedPeripherals = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        print("No paired peripherals found")
        return
      }

      if pairedPeripherals.isEmpty {
        DispatchQueue.main.async {
          self.discoveredPeripherals = []
        }
        print("No available peripherals found")
        return
      }

      let newAvailablePeripherals =
        pairedPeripherals
        .map { device in
          BluetoothPeripheral(
            id: device.addressString ?? "Unknown",
            name: device.name ?? "Unknown Device"
          )
        }
        .filter { peripheral in !self.peripherals.contains(where: { $0.id == peripheral.id }) }

      DispatchQueue.main.async {
        self.discoveredPeripherals = newAvailablePeripherals
        if newAvailablePeripherals.isEmpty {
          print("No new available peripherals found")
        }
      }
    }
  }

  /// Updates the peripheral list with new data from sync
  /// - Parameter newPeripherals: Array of peripherals to update with
  func updatePeripherals(_ newPeripherals: [BluetoothPeripheral]) {
    print("Debug: Starting peripheral update with \(newPeripherals.count) devices")

    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.updatePeripherals(newPeripherals)
      }
      return
    }

    print("Debug: Current peripherals count: \(peripherals.count)")

    peripherals = newPeripherals
    print("Debug: After update peripherals count: \(peripherals.count)")
    print("Debug: Updated peripherals: \(peripherals.map { $0.name })")

    savePeripherals()
    refreshPeripheralState()
  }

  func refreshPeripheralState() {
    refreshRegisteredPeripheralState()
    fetchConnectedPeripherals()
  }

  func refreshRegisteredPeripheralState() {
    let currentStates = currentConnectionStates()
    guard currentStates != cachedConnectionStates else { return }

    cachedConnectionStates = currentStates
    DispatchQueue.main.async {
      self.objectWillChange.send()
    }
  }

  // MARK: - Private Methods

  private func savePeripherals() {
    do {
      let encoded = try JSONEncoder().encode(peripherals)
      peripheralsData = encoded
    } catch {
      print("Failed to save peripherals: \(error)")
    }
  }

  private func loadPeripherals() {
    do {
      peripherals = try JSONDecoder().decode([BluetoothPeripheral].self, from: peripheralsData)
      cachedConnectionStates = currentConnectionStates()
    } catch {
      print("Failed to load peripherals: \(error)")
    }
  }

  // MARK: - Helper Methods

  private func handleConnectionResult(result: IOReturn, peripheralName: String) {
    if result == kIOReturnSuccess {
      print("\(peripheralName) has been connected")
    } else {
      print("Failed to connect to \(peripheralName). Error code: \(result)")
    }
  }

  private func handleDisconnectionResult(result: IOReturn, peripheralName: String) {
    if result == kIOReturnSuccess {
      print("Disconnected from \(peripheralName)")
    } else {
      print("Failed to disconnect from \(peripheralName)")
    }
  }

  private func validateBluetoothState() -> Bool {
    let powerState = IOBluetoothHostController.default().powerState
    guard powerState != kBluetoothHCIPowerStateOFF else {
      print("Bluetooth is turned off")
      return false
    }
    return true
  }

  private func validateDeviceExists(_ peripheral: BluetoothPeripheral) -> Bool {
    guard IOBluetoothDevice(addressString: peripheral.id) != nil else {
      print("Device not found: \(peripheral.name)")
      return false
    }
    return true
  }

  private func getBluetoothDevice(for peripheral: BluetoothPeripheral) -> IOBluetoothDevice? {
    guard let device = IOBluetoothDevice(addressString: peripheral.id) else {
      print("Device not found: \(peripheral.name)")
      return nil
    }
    return device
  }
}

extension BluetoothPeripheralStore: IOBluetoothDevicePairDelegate {
  func devicePairingFinished(_ sender: Any!, error: IOReturn) {
    print("devicePairingFinished with error: \(error)")
    pairingCompletion?(error)
  }

  func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
    print("devicePairingUserConfirmationRequest - Auto-accepting pairing seamlessly!")
    (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
  }
  
  func devicePairingConnecting(_ sender: Any!) {
    print("devicePairingConnecting...")
  }
}

extension BluetoothPeripheralStore {
  private func connectPeripheral(
    _ peripheral: BluetoothPeripheral,
    attempt: Int,
    completion: @escaping (Bool) -> Void
  ) {
    bluetoothQueue.async { [weak self] in
      guard let self = self else { return }

      print("Attempt \(attempt) to connect \(peripheral.name)")

      guard self.validateBluetoothState() else {
        self.finishBluetoothOperation(success: false, completion: completion)
        return
      }

      guard let btDevice = self.getBluetoothDevice(for: peripheral) else {
        self.finishBluetoothOperation(success: false, completion: completion)
        return
      }

      if btDevice.isConnected() {
        print("\(peripheral.name) is already connected")
        self.finishBluetoothOperation(success: true, completion: completion)
        return
      }

      var targetDevice = btDevice

      if attempt == 1 && targetDevice.isPaired() {
        print("\(peripheral.name) has a STALE pairing (it was paired in a previous session). Unpairing it locally first...")
        if targetDevice.responds(to: Selector("remove")) {
          targetDevice.perform(Selector("remove"))
          Thread.sleep(forTimeInterval: 0.5)
          targetDevice = IOBluetoothDevice(addressString: peripheral.id) ?? targetDevice
        }
      }

      if !targetDevice.isPaired() {
        print("Spawning pairing on Main Thread to ensure RunLoop delegate callbacks...")
        let pairingSemaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.main.async {
          if let devicePair = IOBluetoothDevicePair(device: targetDevice) {
            self.currentDevicePair = devicePair
            devicePair.delegate = self
            
            self.pairingCompletion = { result in
              print("Pairing finished callback received. Error code: \(result)")
              pairingSemaphore.signal()
            }
            
            let pairResult = devicePair.start()
            if pairResult != kIOReturnSuccess {
              print("Pairing initialization failed for \(peripheral.name)")
              pairingSemaphore.signal()
            }
          } else {
            pairingSemaphore.signal()
          }
        }
        
        // Wait for devicePairingFinished delegate callback
        _ = pairingSemaphore.wait(timeout: .now() + 15.0)
        
        DispatchQueue.main.async {
          self.currentDevicePair = nil
          self.pairingCompletion = nil
        }
      }

      let connectResult = targetDevice.openConnection()
      if connectResult != kIOReturnSuccess {
        print("openConnection failed for \(peripheral.name). Error code: \(connectResult)")
        self.retryPeripheralConnectionIfNeeded(
          peripheral,
          attempt: attempt,
          completion: completion
        )
        return
      }

      self.waitForPeripheralConnectionState(
        peripheral,
        expectedConnected: true,
        attemptsRemaining: Constants.connectionPollAttempts
      ) { connected in
        if connected {
          self.waitForStablePeripheralState(
            peripheral,
            expectedConnected: true,
            confirmationsRemaining: Constants.stableStateConfirmations
          ) { stableConnection in
            if stableConnection {
              print("Connected to \(peripheral.name)")
              self.finishBluetoothOperation(success: true, completion: completion)
            } else {
              print("\(peripheral.name) did not stay connected long enough")
              self.retryPeripheralConnectionIfNeeded(
                peripheral,
                attempt: attempt,
                completion: completion
              )
            }
          }
        } else {
          print("Timed out waiting for \(peripheral.name) to connect")
          self.retryPeripheralConnectionIfNeeded(
            peripheral,
            attempt: attempt,
            completion: completion
          )
        }
      }
    }
  }

  private func retryPeripheralConnectionIfNeeded(
    _ peripheral: BluetoothPeripheral,
    attempt: Int,
    completion: @escaping (Bool) -> Void
  ) {
    guard attempt < Constants.handoffRetryCount else {
      finishBluetoothOperation(success: false, completion: completion)
      return
    }

    let nextAttempt = attempt + 1
    print("Retrying connection for \(peripheral.name) in \(Constants.handoffRetryDelay)s")
    bluetoothQueue.asyncAfter(deadline: .now() + Constants.handoffRetryDelay) { [weak self] in
      self?.connectPeripheral(peripheral, attempt: nextAttempt, completion: completion)
    }
  }

  private func waitForPeripheralConnectionState(
    _ peripheral: BluetoothPeripheral,
    expectedConnected: Bool,
    attemptsRemaining: Int,
    completion: @escaping (Bool) -> Void
  ) {
    guard attemptsRemaining > 0 else {
      completion(false)
      return
    }

    bluetoothQueue.asyncAfter(deadline: .now() + Constants.connectionPollInterval) { [weak self] in
      guard let self = self else {
        completion(false)
        return
      }

      let isConnected = IOBluetoothDevice(addressString: peripheral.id)?.isConnected() ?? false
      if isConnected == expectedConnected {
        completion(true)
      } else {
        self.waitForPeripheralConnectionState(
          peripheral,
          expectedConnected: expectedConnected,
          attemptsRemaining: attemptsRemaining - 1,
          completion: completion
        )
      }
    }
  }

  private func waitForStablePeripheralState(
    _ peripheral: BluetoothPeripheral,
    expectedConnected: Bool,
    confirmationsRemaining: Int,
    completion: @escaping (Bool) -> Void
  ) {
    guard confirmationsRemaining > 0 else {
      completion(true)
      return
    }

    bluetoothQueue.asyncAfter(deadline: .now() + Constants.connectionPollInterval) { [weak self] in
      guard let self = self else {
        completion(false)
        return
      }

      let isConnected = IOBluetoothDevice(addressString: peripheral.id)?.isConnected() ?? false
      if isConnected == expectedConnected {
        self.waitForStablePeripheralState(
          peripheral,
          expectedConnected: expectedConnected,
          confirmationsRemaining: confirmationsRemaining - 1,
          completion: completion
        )
      } else {
        completion(false)
      }
    }
  }

  private func finishBluetoothOperation(success: Bool, completion: @escaping (Bool) -> Void) {
    DispatchQueue.main.async {
      self.refreshPeripheralState()
      completion(success)
    }
  }

  private func performSequentialOperation(
    on peripherals: [BluetoothPeripheral],
    completion: @escaping (Bool) -> Void,
    operation: @escaping (BluetoothPeripheral, @escaping (Bool) -> Void) -> Void
  ) {
    guard !peripherals.isEmpty else {
      DispatchQueue.main.async {
        completion(true)
      }
      return
    }

    func run(index: Int) {
      guard index < peripherals.count else {
        DispatchQueue.main.async {
          completion(true)
        }
        return
      }

      operation(peripherals[index]) { success in
        if success {
          run(index: index + 1)
        } else {
          DispatchQueue.main.async {
            completion(false)
          }
        }
      }
    }

    run(index: 0)
  }

  private func currentConnectionStates() -> [String: Bool] {
    Dictionary(
      uniqueKeysWithValues: peripherals.map { peripheral in
        let isConnected = IOBluetoothDevice(addressString: peripheral.id)?.isConnected() ?? false
        return (peripheral.id, isConnected)
      }
    )
  }
}

extension BluetoothPeripheralStore {
  /// Checks the actual connection status of all registered peripherals using IOBluetoothDevice
  /// - Returns: ConnectionStatus indicating the current state
  enum ConnectionStatus: Equatable {
    case allConnected
    case allDisconnected
    case partial
  }

  func checkActualConnectionStatus() -> ConnectionStatus {
    guard !peripherals.isEmpty else { return .allDisconnected }

    var connectedCount = 0
    var totalCount = 0

    for peripheral in peripherals {
      if let btDevice = IOBluetoothDevice(addressString: peripheral.id) {
        totalCount += 1
        if btDevice.isConnected() {
          connectedCount += 1
        }
      }
    }

    if connectedCount == totalCount && totalCount > 0 {
      return .allConnected
    } else if connectedCount == 0 {
      return .allDisconnected
    } else {
      return .partial
    }
  }
}
