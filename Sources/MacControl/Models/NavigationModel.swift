//
//  NavigationModel.swift
//  MacControl
//

import Foundation

/// Which screen the main window shows. Shared so notifications and buttons can navigate.
final class NavigationModel: ObservableObject {
    @Published var selection: Screen? = .diagnosis
}
