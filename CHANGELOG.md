# [1.1.0](https://github.com/kemalunal/blue-switch/compare/v1.0.3...v1.1.0) (2026-03-19)


### Bug Fixes

* increase forceDisconnectAttempts to 60 ([d007b70](https://github.com/kemalunal/blue-switch/commit/d007b702df1a29cb53350ec9130f2ca09e39d73d))
* increase retry count to outlast auto-reconnect ([b1292f8](https://github.com/kemalunal/blue-switch/commit/b1292f87096583746587e8d42bb63e0e198939e9))
* make BluetoothPeripheralStore inherit NSObject to conform to protocol ([3e7d9e2](https://github.com/kemalunal/blue-switch/commit/3e7d9e27ec34a9bc34794385959bc7ddf5ca475f))
* override init for NSObject inheritance ([6b00a37](https://github.com/kemalunal/blue-switch/commit/6b00a37c4be888e930bcf30426bc05f30a21099b))
* remove invalid rssi check and aggressive retries, increase timeout ([00e7fa9](https://github.com/kemalunal/blue-switch/commit/00e7fa9ad6ee7a954ac0d47f76a122e6af4ab155))
* replace remove selector with force-disconnect loop ([a9108cc](https://github.com/kemalunal/blue-switch/commit/a9108cca83bdff96cdf8d0a202a83c6fcaf71800))
* restore missing btDevice variable declaration that caused build failure ([e0eae9c](https://github.com/kemalunal/blue-switch/commit/e0eae9c960a4a3b3569c4c6d861da4bb712e65c0))
* stabilize bluetooth handoff - prevent auto-reconnect flapping ([7f515e3](https://github.com/kemalunal/blue-switch/commit/7f515e32be54dd97edb85d98bc0c5eca890d7adb))


### Features

* add build version display in logs and Settings title ([78501d7](https://github.com/kemalunal/blue-switch/commit/78501d7c678f8d64a81064dd4c058fc472410ed4))
* add visible build version in Other tab ([bcf07b9](https://github.com/kemalunal/blue-switch/commit/bcf07b95c049c8efa394425761b7611bc6905ef3))
* async shield loop instead of blocking disconnect ([60c1b47](https://github.com/kemalunal/blue-switch/commit/60c1b47b853ff63459f86d00387d730c7b282d9a))
* implement clean unpair and pair strategy to avoid macOS BT collisions ([8905944](https://github.com/kemalunal/blue-switch/commit/89059448c90a49c14bc01b94a0b765ca1e4bb07f))
* use main thread runloop for bluetooth pairing delegate and auto-accept pairing ([7ebf0f4](https://github.com/kemalunal/blue-switch/commit/7ebf0f45103f8a1e5b7a4538739902270383df5b))

## [1.0.3](https://github.com/kemalunal/blue-switch/compare/v1.0.2...v1.0.3) (2026-03-19)


### Bug Fixes

* fail remote handoff when no peripherals exist ([539eba6](https://github.com/kemalunal/blue-switch/commit/539eba67cf155afdad80ab65c787efeda341b0c4))

## [1.0.2](https://github.com/kemalunal/blue-switch/compare/v1.0.1...v1.0.2) (2026-03-19)


### Bug Fixes

* stabilize bluetooth handoff flow ([42b5876](https://github.com/kemalunal/blue-switch/commit/42b5876c2112a318f23bbb155cde7f7cc8b7a044))

## [1.0.1](https://github.com/kemalunal/blue-switch/compare/v1.0.0...v1.0.1) (2026-03-19)


### Bug Fixes

* reduce flaky device handoff ([c305758](https://github.com/kemalunal/blue-switch/commit/c305758726ed58eb0f4f645af80049778cdc4292))

# 1.0.0 (2026-02-28)


### Bug Fixes

* replace SwiftUICore import with SwiftUI for macOS Tahoe compatibility ([f9d88ae](https://github.com/kemalunal/blue-switch/commit/f9d88ae0ffe0d27b9dcd90840b57c606c03576ec))


### Features

* initial commit ([872a902](https://github.com/kemalunal/blue-switch/commit/872a902ceedd5aa9bfff93a5fe673d8f7d360206))

# 1.0.0 (2024-12-01)


### Features

* initial commit ([872a902](https://github.com/HoshimuraYuto/blue-switch/commit/872a902ceedd5aa9bfff93a5fe673d8f7d360206))
