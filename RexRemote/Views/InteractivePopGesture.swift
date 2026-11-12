import SwiftUI
import UIKit

/// Hiding the navigation bar also disables the interactive pop gesture, which
/// the session screen does in favour of its own glass chevron. HIG expects the
/// edge swipe to keep working, so this re-enables the recogniser on the hosting
/// navigation controller without bringing the bar back.
struct InteractivePopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enable()
    }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enable()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        func enable() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
