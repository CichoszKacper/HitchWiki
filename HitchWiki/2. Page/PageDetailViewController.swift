//
//  PageDetailViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 12/10/2021.
//

import UIKit
import Algorithms

class PageDetailViewController: ModelledViewController<PageDetailViewModel> {
    @IBOutlet weak var pageDescription: UILabel!
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
        self.loadData()
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
                            if value {
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
    
    func populatePage(page: Page, allPages: [Page]) {
        self.viewModel.passPage(page: page, allPages: allPages)
    }
    
    private func setUpInfoboxLayout() {
        self.infoboxView.isHidden = false
        self.infoboxView.customize(backgroundColor: .systemYellow, radiusSize: 20)
        self.informationLabel.layer.cornerRadius = 5
        self.informationLabel.layer.masksToBounds = true
    }
}
