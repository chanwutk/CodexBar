import Charts
import SwiftUI

// Backward-compatibility shims so the app builds and runs on macOS 13 (Ventura).
// Several SwiftUI/Charts APIs the app uses were introduced in macOS 14; these helpers
// provide macOS 13 fallbacks and forward to the modern API on macOS 14+.

extension View {
    /// macOS 13-compatible shim for `onChange(of:initial:_:)` (introduced in macOS 14).
    ///
    /// On macOS 14+ this forwards to the modern two-parameter API. On macOS 13 it uses the
    /// older `onChange(of:perform:)`, which only reports the new value; the "old value" passed
    /// to `action` is tracked best-effort via internal state.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void)
        -> some View
    {
        if #available(macOS 14.0, *) {
            self.onChange(of: value, initial: initial, action)
        } else {
            self.modifier(LegacyOnChangeModifier(value: value, initial: initial, action: action))
        }
    }
}

/// macOS 13 implementation backing ``SwiftUI/View/onChangeCompat(of:initial:_:)``.
private struct LegacyOnChangeModifier<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V, V) -> Void
    @State private var previous: V?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if self.previous == nil {
                    self.previous = self.value
                    if self.initial { self.action(self.value, self.value) }
                }
            }
            .onChange(of: self.value) { newValue in
                let old = self.previous ?? newValue
                self.previous = newValue
                self.action(old, newValue)
            }
    }
}

@available(macOS 13.0, *)
extension ChartProxy {
    /// `plotFrame` (macOS 14+) with a fallback to the deprecated `plotAreaFrame` on macOS 13.
    var plotFrameCompat: Anchor<CGRect>? {
        if #available(macOS 14.0, *) {
            self.plotFrame
        } else {
            self.plotAreaFrame
        }
    }
}
