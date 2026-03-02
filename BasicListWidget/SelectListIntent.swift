//
//  SelectListIntent.swift
//  BasicListWidget
//
//  Created by Sam Cassisi on 28/2/2026.
//

import AppIntents
import WidgetKit

struct SelectListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select List"
    static var description: IntentDescription = "Choose which list to display"

    @Parameter(title: "List")
    var list: ListEntity?
}
