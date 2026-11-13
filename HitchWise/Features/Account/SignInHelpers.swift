//
//  SignInHelpers.swift
//  HitchWise
//
//  Finds the view controller to show Google's sign-in sheet on.
//

import UIKit

extension UIApplication {
    /// The key window of the foreground scene.
    var activeWindow: UIWindow? {
        self.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// The view controller on top, to present Google's sign-in sheet on.
    var topViewController: UIViewController? {
        var top = self.activeWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
