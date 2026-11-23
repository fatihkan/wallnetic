import SwiftUI

extension View {
    /// Suppresses macOS's system focus ring (the thick pink/blue rounded
    /// rectangle that appears around a focused Button). Use on custom
    /// list/sidebar rows whose selection is already indicated visually.
    /// No-op on macOS < 14.
    @ViewBuilder
    func suppressFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}
