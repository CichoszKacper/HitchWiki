//
//  PageDetailViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 12/10/2021.
//

import UIKit
import Algorithms

class PageDetailViewController: ModelledViewController<PageDetailViewModel> {
    @IBOutlet weak var pageDescriptionTextField: UITextView!
    @IBOutlet weak var informationLabel: UILabel!
    @IBOutlet weak var infoboxView: UIView!
    @IBOutlet weak var countryTitleLabel: UILabel!
    @IBOutlet weak var countryLanguageLabel: UILabel!
    @IBOutlet weak var capitalLabel: UILabel!
    @IBOutlet weak var populationLabel: UILabel!
    @IBOutlet weak var currencyLabel: UILabel!
    @IBOutlet var infoboxLabelsCollection: [UILabel]!
    
    // MARK: - Life Cycle
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.loadData()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = self.viewModel.page?.title
        self.navigationItem.title = self.navigationItem.title?.uppercased()
        self.navigationController?.isNavigationBarHidden = false
    }
    
    override func updateView(_ type: PageDetailViewModel.UpdateType) {
        switch type {
        case .page:
            print("chuj")
        }
    }
    
    // MARK: - Public Methods
    func populatePage(page: Page, allPages: [Page]) {
        self.viewModel.passPage(page: page, allPages: allPages)
    }
    
    // MARK: - Private Methods
    private func loadData() {
        if !self.viewModel.newDictionary.isEmpty {
            // Populate the labels with information stored in dictionary
            for (key, group) in self.viewModel.newDictionary {
                self.setUpInfoboxLayout()
                for (subKey, _) in group {
                    self.infoboxLabelsCollection.forEach { label in
                        guard let labelIdentifier = label.accessibilityIdentifier else {
                            return
                        }
                        
                        if labelIdentifier.lowercased().contains(key.lowercased()) {
                            if key == "Capital" {
                                self.viewModel.addTapGestureToPartOfString(label: label, stringToBeCalled: subKey)
                            }
                            label.attributedText = NSMutableAttributedString(attributedString: NSAttributedString(string: "\(key): \(subKey)"))
                        }
                    }
                }
            }
        } else {
            self.infoboxView.isHidden = true
        }
        //Checks if any information label is not populated with information
        self.infoboxLabelsCollection.forEach { label in
            if let labelText = label.text {
                if labelText.contains("Label"){
                    label.isHidden = true
                }
            }
        }
        
        guard let pageDescriptionAttributedString = self.viewModel.pageDescriptionAttributedString,
              let descriptionClickableValuesArray = self.viewModel.descriptionClickableValuesArray,
              let sections = self.viewModel.sections,
              let subsections = self.viewModel.subsections,
              let boldText = self.viewModel.boldTextArray,
              let italicText = self.viewModel.italicTextArray else {
            return
        }
        
        // Add description
        self.pageDescriptionTextField.addHyperLinksAndSectionsToText(originalText: pageDescriptionAttributedString, hyperLinks: descriptionClickableValuesArray, urls: self.viewModel.urlDictionary, sections: sections, subsections: subsections, boldText: boldText, italicText: italicText)
        //Add blue colour to the hyperlink in infobox
        if let stringToBeCalled = self.viewModel.stringToBeCalled {
            self.viewModel.labelToBeCalled?.set(color: .systemBlue, on: [stringToBeCalled])
        }
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
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return self.viewModel.interactWithURL(pageName: URL.absoluteString)
    }
}

