//
//  ModelledViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 15/10/2021.
//

import UIKit

class ModelledViewController<ViewModel: ViewModelProtocol>: UIViewController {

    let viewModel: ViewModel

    // MARK: - Initialisation

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    init(viewModel: ViewModel, nibName: String) {
        self.viewModel = viewModel
        super.init(nibName: nibName, bundle: Bundle(for: type(of: self)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        self.bind()
    }

    // MARK: - Binding

    func bind() {
        self.viewModel.update = { [weak self] type in
            Thread.runOnMain {
                self?.updateView(type)
            }
        }
        self.viewModel.error = { [weak self] error in
            Thread.runOnMain {
                self?.handle(error)
            }
        }
        self.viewModel.base = { [weak self] type in
            Thread.runOnMain {
                self?.base(type)
            }
        }
    }

    // MARK: - Base Updates

    func base(_ type: ViewModel.BaseType) {
        switch type {
        case .beginLoading:
            print("loading")
        case .endLoading:
            print("finished loading")
        }
    }

    // MARK: - View Update

    func updateView(_ type: ViewModel.UpdateType) { assertionFailure("updates are not being handled") }

    // MARK: - Error Handling

    func handle(_ error: ViewModel.ErrorType) { assertionFailure("errors are not being handled") }
}


import Foundation

public extension Thread {
    /// A method to ensure execution of the provided block on the main thread
    /// - Parameter block: The block to execute on the main thread
    class func runOnMain(block: () -> ()) {
        if Thread.isMainThread {
            block()
            return
        }
        DispatchQueue.main.sync {
            block()
        }
    }
}
