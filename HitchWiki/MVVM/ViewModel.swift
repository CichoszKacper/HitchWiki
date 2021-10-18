//
//  ViewModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 15/10/2021.
//

import Foundation

class ViewModel {

    enum BaseType {
        case beginLoading
        case endLoading
    }

    var base: ((BaseType) -> Void)?
}
