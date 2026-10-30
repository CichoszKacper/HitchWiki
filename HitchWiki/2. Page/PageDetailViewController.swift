//
//  PageDetailViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 12/10/2021.
//

import UIKit
import Algorithms

class PageDetailViewController: ModelledViewController<PageDetailViewModel> {
    @IBOutlet weak var pageDescription: UITextView!
    @IBOutlet weak var informationLabel: UILabel!
    @IBOutlet weak var infoboxView: UIView!
    @IBOutlet weak var countryTitleLabel: UILabel!
    @IBOutlet weak var countryLanguageLabel: UILabel!
    @IBOutlet weak var capitalLabel: UILabel!
    @IBOutlet weak var populationLabel: UILabel!
    @IBOutlet weak var currencyLabel: UILabel!
    @IBOutlet var infoboxLabelsCollection: [UILabel]!
    @IBOutlet weak var pageDescriptionTopConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUpPageDescription()
        self.loadData()
        self.navigationItem.title = self.viewModel.page?.title
        self.navigationItem.title = self.navigationItem.title?.uppercased()
        self.navigationController?.isNavigationBarHidden = false
        
    }
    
    /// The page text is a read-only text view so that UIKit handles taps on links.
    private func setUpPageDescription() {
        self.pageDescription.delegate = self
        self.pageDescription.isEditable = false
        self.pageDescription.isSelectable = true
        self.pageDescription.isScrollEnabled = false
        self.pageDescription.backgroundColor = .clear
        // Lay the text out like the label it replaced
        self.pageDescription.textContainerInset = .zero
        self.pageDescription.textContainer.lineFragmentPadding = 0
        self.pageDescription.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
    }
    
    fileprivate func openPage(title: String) {
        let pageDetailViewController = PageDetailViewController(viewModel: PageDetailViewModel())
        pageDetailViewController.populatePage(title: title)
        self.navigationController?.pushViewController(pageDetailViewController, animated: true)
    }
    
    override func updateView(_ type: PageDetailViewModel.UpdateType) {
        switch type {
        case .page:
            print("chuj")
        }
    }
    
    private func loadData() {
        if !self.viewModel.newDictionary.isEmpty {
            // Populate the labels with information stored in dictionary
            for (key, group) in self.viewModel.newDictionary {
                self.setUpInfoboxLayout()
                for (subKey, value) in group {
                    self.infoboxLabelsCollection.forEach { label in
                        guard let labelIdentifier = label.accessibilityIdentifier else {
                            return
                        }
                        
                        if labelIdentifier.lowercased().contains(key.lowercased()) {
                            if self.viewModel.checkIfShouldMakeClickable(value: value, string: subKey){
                                self.viewModel.addTapGestureToPartOfString(label: label, stringToBeCalled: subKey)
                            }
                            label.attributedText = NSMutableAttributedString(attributedString: NSAttributedString(string: "\(key): \(subKey)"))
                        }
                    }
                }
            }
        } else {
            self.pageDescriptionTopConstraint.constant = (-self.infoboxView.frame.height)
            self.pageDescription.layoutIfNeeded()
        }
        //Check if any information label is not populated with information
        self.infoboxLabelsCollection.forEach { label in
            if let labelText = label.text {
                if labelText.contains("Label"){
                    label.isHidden = true
                }
            }
        }
        self.pageDescription.attributedText = self.viewModel.pageDescriptionAttributedString
        self.viewModel.labelToBeCalled?.set(color: .systemBlue, on: [self.viewModel.stringToBeCalled!])
    }
    
    func populatePage(title: String) {
        self.viewModel.passPage(title: title)
    }
    
    private func setUpInfoboxLayout() {
        self.infoboxView.isHidden = false
        self.infoboxView.customize(backgroundColor: .systemYellow, radiusSize: 20)
        self.informationLabel.layer.cornerRadius = 5
        self.informationLabel.layer.masksToBounds = true
    }
}

// MARK: - UITextViewDelegate
extension PageDetailViewController: UITextViewDelegate {
    // iOS 17+: tapping a link
    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content, let title = PageDetailViewModel.pageTitle(fromLink: url) else {
            return defaultAction   // websites open in Safari
        }
        return UIAction { [weak self] _ in
            self?.openPage(title: title)
        }
    }
    
    // iOS 17+: long press on a wiki link shouldn't offer "Open in Safari" for our app-only address
    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        guard case .link(let url) = textItem.content, PageDetailViewModel.pageTitle(fromLink: url) != nil else {
            return UITextItem.MenuConfiguration(menu: defaultMenu)
        }
        return nil
    }
    
    // Before iOS 17
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard let title = PageDetailViewModel.pageTitle(fromLink: URL) else {
            return true   // websites open in Safari
        }
        if interaction == .invokeDefaultAction {
            self.openPage(title: title)
        }
        return false
    }
}
