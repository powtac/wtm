import AppKit
import SwiftUI

struct InventorySearchField: NSViewRepresentable {
  @Binding var text: String

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSSearchField {
    let searchField = NSSearchField()
    searchField.placeholderString = String(localized: "inventory.search.prompt")
    searchField.sendsSearchStringImmediately = true
    searchField.delegate = context.coordinator
    return searchField
  }

  func updateNSView(_ searchField: NSSearchField, context: Context) {
    context.coordinator.text = $text
    if searchField.stringValue != text {
      searchField.stringValue = text
    }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let searchField = notification.object as? NSSearchField else { return }
      text.wrappedValue = searchField.stringValue
    }
  }
}
