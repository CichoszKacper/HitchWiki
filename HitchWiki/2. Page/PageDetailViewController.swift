//
//  PageDetailViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 12/10/2021.
//

import UIKit

class PageDetailViewController: ModelledViewController<PageDetailViewModel> {
    @IBOutlet weak var pageView: UIView!
    @IBOutlet weak var pageDescriptionTextField: UITextView!
    @IBOutlet weak var informationLabel: UILabel!
    @IBOutlet weak var infoboxView: UIView!
    @IBOutlet weak var countryTitleLabel: UILabel!
    @IBOutlet weak var countryLanguageLabel: UILabel!
    @IBOutlet weak var capitalLabel: UILabel!
    @IBOutlet weak var populationLabel: UILabel!
    @IBOutlet weak var currencyLabel: UILabel!
    @IBOutlet var infoboxLabelsCollection: [UILabel]!
    @IBOutlet weak var searchTableView: UITableView!
    
    var searchBar = UISearchBar()
    var searchBarContainer: SearchBarContainerView?
    var searchBarButtonItem: UIBarButtonItem?
    
    // MARK: - Life Cycle
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.loadData()
        self.hideSearchBar()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = self.viewModel.page?.title
        self.navigationItem.title = self.navigationItem.title?.uppercased()
        self.navigationController?.isNavigationBarHidden = false
        self.searchTableView.register(UINib(nibName: "PageTableViewCell", bundle: nil), forCellReuseIdentifier: "PageTableViewCell")
        self.setUpSearchBar()
    }
    
    override func updateView(_ type: PageDetailViewModel.UpdateType) {
        switch type {
        case .page:
            self.searchTableView.isHidden = true
            self.pageView.isHidden = false
        case .search:
            self.searchTableView.isHidden = false
            self.pageView.isHidden = true
            self.searchTableView.reloadOnMainThread()
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
    
    @objc func seachBarIconTapped() {
        self.showSearchBar(searchBar: self.searchBar)
    }
    
    private func setUpSearchBar() {
        self.searchBar.delegate = self
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.showsCancelButton = true
        self.searchBarContainer = SearchBarContainerView(customSearchBar: self.searchBar)
        self.searchBarContainer?.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: 44)
        self.searchBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(seachBarIconTapped))
        self.navigationItem.rightBarButtonItem = self.searchBarButtonItem
    }
    
    private func showSearchBar(searchBar : UISearchBar) {
        guard let searchBarContainer = self.searchBarContainer else {
            return
        }
        
        searchBarContainer.alpha = 0
        navigationItem.titleView = searchBarContainer
        navigationItem.setRightBarButton(nil, animated: true)
        
        UIView.animate(withDuration: 0.5, animations: {
            searchBarContainer.alpha = 1
        }, completion: { finished in
            searchBarContainer.searchBar.becomeFirstResponder()
        })
    }
    
    private func hideSearchBar() {
        guard let searchBarButtonItem = self.searchBarButtonItem else {
            return
        }
        
        self.searchBarContainer?.searchBar.text = nil
        self.navigationItem.setRightBarButton(searchBarButtonItem, animated: true)
        self.navigationItem.titleView = .none
        self.viewModel.update?(.page)
    }
}

// MARK: - UITextViewDelegate
extension PageDetailViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return self.viewModel.interactWithURL(pageName: URL.absoluteString)
    }
}

// MARK: - UITableViewDataSource
extension PageDetailViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.viewModel.filteredPages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PageTableViewCell", for: indexPath) as! PageTableViewCell
        cell.populateCell(page: self.viewModel.filteredPages[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate
extension PageDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.viewModel.moveToPageScreen(indexRow: indexPath.row,
                                        pages: self.viewModel.pages,
                                        filteredPages: self.viewModel.filteredPages)
    }
}

// MARK: - UISearchBarDelegate
extension PageDetailViewController: UISearchBarDelegate {
    
    // Extension to SearchBar to search through the list of pages
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.viewModel.searchBarClicked()
        guard !searchText.isEmpty else {
            self.viewModel.filteredPages = self.viewModel.pages
            searchBar.resignFirstResponder()
            return
        }
        
        self.viewModel.filteredPages = self.viewModel.pages.filter { ($0.title.lowercased().starts(with: searchText.lowercased()))}
        self.searchTableView.reloadOnMainThread()
        // TODO: Allow user to search when page contains searched text, not only starts with
//        self.filteredPages = self.pages.filter { ($0.title.lowercased().contains(searchText.lowercased()))}
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.hideSearchBar()
    }
}

