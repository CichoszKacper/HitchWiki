//
//  NavigationController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/02/2022.
//

import UIKit

class NavigationController: UINavigationController {
    
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        Thread.runOnMain {
            super.pushViewController(viewController, animated: animated)
        }
    }
    
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        Thread.runOnMain {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }
    
    override func popViewController(animated: Bool) -> UIViewController? {
        var viewController: UIViewController?
        Thread.runOnMain {
            viewController = super.popViewController(animated: animated)
        }
        return viewController
    }
    
    override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        var viewControllers: [UIViewController]?
        Thread.runOnMain {
            viewControllers = super.popToRootViewController(animated: animated)
        }
        return viewControllers
    }
    
    override func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        var viewControllers: [UIViewController]?
        Thread.runOnMain {
            viewControllers = super.popToViewController(viewController, animated: animated)
        }
        return viewControllers
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        Thread.runOnMain {
            super.dismiss(animated: flag, completion: completion)
        }
    }
}
