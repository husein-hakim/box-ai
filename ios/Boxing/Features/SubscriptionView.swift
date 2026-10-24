import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @State private var commerce = SubscriptionStore()
    @State private var managing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Label("BOX membership", systemImage: "crown.fill").boxEyebrow(.white.opacity(0.85))
                    Text("Your\nmembership.").boxDisplay(40, relativeTo: .title).padding(.top, 10)
                    Text("Everything is free during development.").font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                }.boxHero().boxEntrance()
                if !commerce.configured {
                    BoxInlineNotice(text: "Subscription setup is still in progress. This development build does not offer purchases or restrict features behind a paid plan.", symbol: "hammer.fill", color: BoxStyle.strength)
                }
                if commerce.loading { HStack(spacing: 10) { ProgressView(); Text("Checking the App Store…").font(.subheadline) }.boxPanel() }
                ForEach(commerce.products) { product in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(product.displayName).boxSection(24)
                        Text(product.description).font(.subheadline).foregroundStyle(BoxStyle.muted)
                        Text(product.displayPrice).boxNumber(34)
                        if commerce.activeProductIDs.contains(product.id) {
                            Label("Active · Verified by Apple", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.conditioning)
                        } else {
                            PrimaryButton(title: "Continue with \(product.displayName)", symbol: "checkmark") { Task { await commerce.purchase(product) } }
                                .disabled(commerce.purchasing || !CommerceConfiguration.purchasesEnabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).boxPanel(padding: 18, tint: BoxStyle.accent)
                }
                if let notice = commerce.notice { Text(notice).font(.subheadline).foregroundStyle(BoxStyle.muted) }
                HStack(spacing: 10) {
                    Button { Task { await commerce.restore() } } label: { Text("Restore purchases").frame(maxWidth: .infinity) }
                        .disabled(!commerce.configured || commerce.loading || commerce.purchasing)
                    Button { managing = true } label: { Text("Manage").frame(maxWidth: .infinity) }.disabled(!commerce.configured)
                }.buttonStyle(BoxSecondaryStyle())
                Text("App Store products, access rules, subscription disclosures and production testing must be configured before subscriptions ship. Your training records remain local and do not require a BOX login.")
                    .font(.footnote).foregroundStyle(BoxStyle.muted)
            }.boxPage()
        }
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle("Subscription").navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $managing)
        .task { await commerce.load(); if commerce.configured { await commerce.listen() } }
    }
}
