import SwiftUI
import UIKit

public struct UnityView: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> UnityContainerView {
        let view = UnityContainerView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }

    public func updateUIView(_ uiView: UnityContainerView, context: Context) {
        uiView.attachUnityView()
    }

    public static func dismantleUIView(_ uiView: UnityContainerView, coordinator: ()) {
        uiView.releaseUnityView()
    }
}

public final class UnityContainerView: UIView {
    private var acceptsUnity = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        nil
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        acceptsUnity = newWindow != nil
        if newWindow == nil {
            releaseUnityView()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        attachUnityView()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        attachUnityView()
    }

    func attachUnityView() {
        guard acceptsUnity, window != nil else { return }
        UnityHost.shared.attach(to: self)
    }

    func releaseUnityView() {
        acceptsUnity = false
        guard UnityHost.shared.isAttached(to: self) else { return }
        UnityHost.shared.keepOffscreen()
    }
}
