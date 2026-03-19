import Cocoa
import SwiftUI

/// Application delegate handling lifecycle and UI setup
final class AppDelegate: NSObject, NSApplicationDelegate {
  // MARK: - Dependencies

  @ObservedObject private var networkStore = NetworkDeviceStore.shared
  @ObservedObject private var bluetoothStore = BluetoothPeripheralStore.shared

  // MARK: - UI Components

  private var statusItem: NSStatusItem!
  private var settingsWindowController: NSWindowController?

  // MARK: - Constants

  private let windowSize = NSSize(width: 480, height: 300)
  private let handoffSettleDelay: TimeInterval = 0.75
  private var isSwitchInProgress = false

  // MARK: - Lifecycle Methods

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupNotifications()
    setupBluetooth()
    setupStatusBar()
  }

  // MARK: - Setup Methods

  private func setupNotifications() {
    NotificationManager.requestAuthorization()
  }

  private func setupBluetooth() {
    BluetoothManager.shared.setup()
  }

  private func setupStatusBar() {
    NSApp.setActivationPolicy(.accessory)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = statusItem.button else { return }

    configureStatusBarButton(button)
  }

  private func configureStatusBarButton(_ button: NSStatusBarButton) {
    if let customImage = NSImage(named: "StatusBarIcon") {
      customImage.size = NSSize(width: 24, height: 24)
      button.image = customImage
    }
    button.target = self
    button.action = #selector(handleClick(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  // MARK: - Action Handlers

  @objc private func handleClick(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    switch event.type {
    case .rightMouseUp:
      showMenu()
    case .leftMouseUp:
      handleLeftClick()
    default:
      break
    }
  }

  private func showMenu() {
    MenuBarView().showMenu(statusItem: statusItem)
  }

  private func handleLeftClick() {
    guard !isSwitchInProgress else {
      NotificationManager.showNotification(
        title: "Switch In Progress",
        body: "Please wait for the current handoff to finish."
      )
      return
    }

    guard let targetDevice = networkStore.networkDevices.first else {
      NotificationManager.showNotification(
        title: "Error",
        body: "No devices connected. Please connect a device first."
      )
      return
    }

    guard !bluetoothStore.peripherals.isEmpty else {
      NotificationManager.showNotification(
        title: "Error",
        body: "No registered peripherals found. Add a device in Settings > Peripheral."
      )
      return
    }

    isSwitchInProgress = true
    print("Starting handoff to \(targetDevice.name). Local state: \(bluetoothStore.checkActualConnectionStatus())")

    targetDevice.checkHealth { [weak self] result in
      guard let self = self else { return }

      switch result {
      case .success:
        switch bluetoothStore.checkActualConnectionStatus() {
        case .allConnected:
          print("Local peripherals are connected. Disconnecting locally before remote connect.")
          self.bluetoothStore.disconnectPeripheralsForHandoff(self.bluetoothStore.peripherals) {
            disconnectSuccess in
            if disconnectSuccess {
              self.runAfterHandoffSettleDelay {
                print("Local disconnect completed. Requesting remote connect on \(targetDevice.name).")
                self.networkStore.executeCommand(.connectAll) { success in
                  if success {
                    print("Remote connect completed successfully on \(targetDevice.name)")
                  } else {
                    NotificationManager.showNotification(
                      title: "Error",
                      body: "Connection process failed on target device"
                    )
                  }
                  self.finishSwitchAttempt()
                }
              }
            } else {
              NotificationManager.showNotification(
                title: "Error",
                body: "Failed to disconnect devices for handoff"
              )
              self.finishSwitchAttempt()
            }
          }
        case .allDisconnected:
          print("Local peripherals are disconnected. Requesting remote disconnect before local connect.")
          self.networkStore.executeCommand(.unregisterAll) { success in
            if success {
              self.runAfterHandoffSettleDelay {
                print("Remote disconnect completed. Connecting peripherals locally.")
                self.bluetoothStore.connectPeripheralsForHandoff(self.bluetoothStore.peripherals) {
                  connectSuccess in
                  if !connectSuccess {
                    NotificationManager.showNotification(
                      title: "Error",
                      body: "Failed to connect peripherals on this Mac"
                    )
                  }
                  self.finishSwitchAttempt()
                }
              }
            } else {
              NotificationManager.showNotification(
                title: "Error",
                body: "Failed to request device disconnection from peer"
              )
              self.finishSwitchAttempt()
            }
          }
        case .partial:
          NotificationManager.showNotification(
            title: "Warning",
            body:
              "Some devices are connected while others are disconnected. Please ensure all devices are in the same state."
          )
          self.finishSwitchAttempt()
        }

      case .failure(let error):
        NotificationManager.showNotification(
          title: "Error",
          body: "Failed to communicate with device: \(error)"
        )
        self.finishSwitchAttempt()

      case .timeout:
        NotificationManager.showNotification(
          title: "Error",
          body: "No response from device. Please check if the app is running."
        )
        self.finishSwitchAttempt()
      }
    }
  }

  private func finishSwitchAttempt() {
    isSwitchInProgress = false
    bluetoothStore.refreshPeripheralState()
  }

  private func runAfterHandoffSettleDelay(_ action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + handoffSettleDelay, execute: action)
  }

  /// Waits for all devices to disconnect with a timeout
  /// - Parameter completion: Called with true if all devices disconnected, false if timeout occurred
  private func waitForDisconnection(completion: @escaping (Bool) -> Void) {
    // Check disconnection status up to 5 times at 0.5 second intervals
    var attempts = 0
    let maxAttempts = 5

    func check() {
      attempts += 1

      // Check if all devices are disconnected
      let allDisconnected = bluetoothStore.checkActualConnectionStatus() == .allDisconnected

      if allDisconnected {
        completion(true)
      } else if attempts < maxAttempts {
        // If attempts remaining, check again after 0.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          check()
        }
      } else {
        // Treat as failure if maximum attempts exceeded
        completion(false)
      }
    }

    // Start first check after 0.5 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      check()
    }
  }

  // MARK: - Settings Management

  @objc func openPreferencesWindow() {
    if settingsWindowController == nil {
      let settingsWindow = createSettingsWindow()
      settingsWindowController = NSWindowController(window: settingsWindow)
    }

    NSApp.activate(ignoringOtherApps: true)
    settingsWindowController?.showWindow(nil)
    settingsWindowController?.window?.orderFrontRegardless()
  }

  private func createSettingsWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: windowSize),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    window.center()
    window.title = "Settings"
    window.contentView = NSHostingView(rootView: SettingsView())

    return window
  }
}
