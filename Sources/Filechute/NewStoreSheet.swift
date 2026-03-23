import SwiftUI

struct NewStoreSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openWindow) private var openWindow
  @State private var storeName: String
  @State private var errorMessage: String?

  init() {
    _storeName = State(initialValue: StoreCoordinator.shared.uniqueNewStoreName())
  }

  var body: some View {
    VStack(spacing: 16) {
      Text("New Store")
        .font(.headline)

      TextField("Store Name", text: $storeName)
        .textFieldStyle(.roundedBorder)
        .frame(width: 300)
        .onSubmit { create() }

      if let errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
          .font(.caption)
      }

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Create") { create() }
          .keyboardShortcut(.defaultAction)
          .disabled(storeName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(20)
    .fixedSize()
  }

  private func create() {
    let name = storeName.trimmingCharacters(in: .whitespaces)

    if name.isEmpty {
      errorMessage = "Store name cannot be empty."
      return
    }

    if name.contains("/") || name.contains(":") {
      errorMessage = "Store name cannot contain \"/\" or \":\"."
      return
    }

    if name.hasPrefix(".") {
      errorMessage = "Store name cannot start with \".\"."
      return
    }

    if StoreCoordinator.shared.storeNameExists(name) {
      errorMessage = "A store named \"\(name)\" already exists."
      return
    }

    do {
      let url = try StoreCoordinator.shared.createStore(name: name)
      dismiss()
      openWindow(value: url)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
