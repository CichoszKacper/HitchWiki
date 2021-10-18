//
//  ViewModelProtocol.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 15/10/2021.
//

import Foundation

import Foundation

protocol ViewModelProtocol: ViewModel {
    associatedtype UpdateType
    associatedtype ErrorType
    var update: ((UpdateType) -> Void)? { get set }
    var error: ((ErrorType) -> Void)? { get set }
}
