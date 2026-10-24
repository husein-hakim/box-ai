import SwiftUI

struct BarcodeFoodView: View {
    let store: AppStore
    let date: Date
    @State private var barcode = ""
    @State private var amount: Double = 100
    @State private var product: BarcodeProduct?
    @State private var working = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    var body: some View {
        Form {
            Section {
                BoxPageHeader(title: "Packaged food", subtitle: "Find the label. Check your serving.").padding(.vertical, 8)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            Section("Product barcode") {
                TextField("Barcode digits", text: $barcode).keyboardType(.numberPad).boxNumber(24)
                Text("Lookup sends only this barcode to Open Food Facts. Live camera scanning is not connected yet.").font(.footnote).foregroundStyle(.secondary)
                if working { ProgressView("Looking up product…"); Button("Cancel") { request?.cancel() } }
                else {
                    Button { lookup() } label: { Label("Look up barcode", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity) }
                        .buttonStyle(BoxPrimaryStyle(height: 48))
                        .disabled(![8, 12, 13, 14].contains(barcode.count))
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                if let error { Text(error).foregroundStyle(BoxStyle.accent) }
                if FoodCatalogConfiguration.contactEmail.isEmpty { Text("Lookup is disabled until the developer contact is configured.").font(.footnote).foregroundStyle(.secondary) }
            }
            if let product {
                Section("Your serving") {
                    Text(product.product_name ?? "Product").boxSection(22)
                    HStack { Text("Amount (g or ml, per label)"); TextField("100", value: $amount, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    if let draft = product.draft(amount: amount, barcode: barcode) {
                        NavigationLink("Review package values") { MealEditor(store: store, date: date, initial: draft) }
                    } else { Text("Complete calorie/macronutrient values are unavailable for this serving. Use manual entry; missing nutrients have not been treated as zero.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section {
                Link("Data from Open Food Facts (ODbL)", destination: URL(string: "https://world.openfoodfacts.org/")!)
                Text("Community data may differ from your package. Verify units and serving before logging.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .boxFormStyle(tint: BoxStyle.strength)
        .navigationTitle("Packaged food").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { DismissButton() } }
        .onDisappear { request?.cancel() }
        .onChange(of: barcode) { _, _ in product = nil }
    }
    private func lookup() {
        let code = barcode
        working = true; error = nil; product = nil
        request = Task { @MainActor in
            defer { working = false }
            do { product = try await BarcodeLookup().product(code: code) }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
