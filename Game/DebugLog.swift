import Foundation

// MARK: - Debug Logging
//
// Lightweight wrapper around `print` that compiles out completely in
// Release builds. The `@autoclosure` argument means the string isn't even
// constructed when DEBUG is off, so per-frame interpolations in hot paths
// (`BattleScene`, enemy phase, sync-from-state) pay zero cost at ship.
//
// Drop-in: replace `print("[Tag] foo \(bar)")` with `dlog("[Tag] foo \(bar)")`.
// Same call-site shape, same output during development, free at release.

@inline(__always)
func dlog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
