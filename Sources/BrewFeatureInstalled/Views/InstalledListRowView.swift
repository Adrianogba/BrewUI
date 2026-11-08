//
//  InstalledListRowView.swift
//  Brew
//

import BrewAppEnvironment
import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import SwiftUI

/// Owns ``InstalledListRowViewModel`` for one row and runs ``InstalledListRowViewModel/observeRowUpdates()`` while the row is on screen.
struct InstalledListRowRoot: View {
    let package: InstalledBrewPackage
    let onUpgrade: () -> Void
    let onRequestUninstall: () -> Void
    @Environment(\.brewCommandCenter) private var brewCommandCenter

    var body: some View {
        InstalledListRowView(
            package: package,
            brewCommandCenter: brewCommandCenter,
            onUpgrade: onUpgrade,
            onRequestUninstall: onRequestUninstall,
        )
        .id(package.id)
    }
}

struct InstalledListRowView: View {
    let package: InstalledBrewPackage
    let onUpgrade: () -> Void
    let onRequestUninstall: () -> Void
    @State private var viewModel: InstalledListRowViewModel
    @State private var showsUninstallConfirmation = false

    init(
        package: InstalledBrewPackage,
        brewCommandCenter: any BrewCommandCenter,
        onUpgrade: @escaping () -> Void = {},
        onRequestUninstall: @escaping () -> Void = {},
    ) {
        _viewModel = State(
            initialValue: InstalledListRowViewModel(
                package: package,
                brewCommandCenter: brewCommandCenter,
            ),
        )
        self.package = package
        self.onUpgrade = onUpgrade
        self.onRequestUninstall = onRequestUninstall
    }

    var body: some View {
        Group {
            rowContent(viewModel: viewModel)
        }
        .task(id: viewModel.operationSubject) {
            await viewModel.observeRowUpdates()
        }
        .onChange(of: package) { _, new in
            viewModel.update(package: new)
        }
        .contextMenu {
            if package.outdated {
                Button(String(localized: "Upgrade", bundle: #bundle, comment: "Package list context menu: upgrade an outdated package")) {
                    onUpgrade()
                }
                .disabled(viewModel.showsOperationBusy)
            }
            Button(String(localized: "Uninstall", bundle: #bundle, comment: "Package list context menu: uninstall an installed package"), role: .destructive) {
                showsUninstallConfirmation = true
            }
            .disabled(viewModel.showsOperationBusy)
        }
        .confirmationDialog(
            String(localized: "Uninstall \(package.name)?", bundle: #bundle, comment: "Package list context menu: uninstall confirmation title; interpolated package name"),
            isPresented: $showsUninstallConfirmation,
            presenting: package,
        ) { package in
            Button(String(localized: "Uninstall", bundle: #bundle, comment: "Package list context menu: confirm uninstall"), role: .destructive) {
                onRequestUninstall()
            }
            Button(String(localized: "Cancel", bundle: #bundle, comment: "Package list context menu: cancel uninstall"), role: .cancel) {}
        } message: { package in
            Text(verbatim: String(
                localized: "This will remove \(package.name) from this Mac using Homebrew.",
                bundle: #bundle,
                comment: "Package list context menu: uninstall confirmation message; interpolated package name",
            ))
        }
    }

    private func rowContent(viewModel: InstalledListRowViewModel) -> some View {
        VStack(alignment: .leading, spacing: BrewSpacing.xs) {
            titleRow(viewModel: viewModel)
            if viewModel.hasDescription {
                Text(viewModel.descriptionText)
                    .font(.brewCallout)
                    .foregroundStyle(Color.brewTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            versionLine(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, BrewSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.rowAccessibilityLabel)
    }

    private func titleRow(viewModel: InstalledListRowViewModel) -> some View {
        HStack(spacing: BrewSpacing.sm) {
            Text(viewModel.name)
                .font(.brewBodyEmphasized)
                .foregroundStyle(Color.brewTextPrimary)
                .lineLimit(1)

            if viewModel.showsOperationBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            Text(viewModel.kind.chrome.badgeLabel)
                .font(.brewCaption2)
                .foregroundStyle(accentColor(viewModel.kind.chrome.accent))
                .padding(.horizontal, BrewSpacing.sm)
                .padding(.vertical, BrewSpacing.xs)
                .background {
                    Capsule()
                        .fill(Color.brewSurfaceElevated)
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.brewBorderDefault, lineWidth: 1)
                        }
                        .brewHiddenWhenRedacted()
                }

            statusBadge(viewModel: viewModel)
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
    }

    private func statusBadge(viewModel: InstalledListRowViewModel) -> some View {
        HStack(spacing: BrewSpacing.sm) {
            if viewModel.showsUpgradeAvailable {
                InstalledOutdatedBadge()
            }
            if viewModel.isDeprecated {
                InstalledDeprecatedBadge()
            }
            if !viewModel.showsUpgradeAvailable, !viewModel.isDeprecated {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.brewStatusSuccess)
                    .help(String(localized: "Installed and up to date", bundle: #bundle, comment: "Installed list: tooltip on the up-to-date tick"))
            }
        }
    }

    @ViewBuilder
    private func versionLine(viewModel: InstalledListRowViewModel) -> some View {
        switch viewModel.versionPresentation {
        case let .installed(version):
            Text(version)
                .font(.brewCaption)
                .foregroundStyle(Color.brewTextTertiary)
        case let .upgrade(current, latest):
            HStack(alignment: .firstTextBaseline, spacing: BrewSpacing.xs) {
                Text(current)
                    .foregroundStyle(Color.brewTextTertiary)
                Text(verbatim: "→")
                    .foregroundStyle(Color.brewTextTertiary)
                Text(latest)
                    .foregroundStyle(Color.brewTextBrand)
            }
            .font(.brewCaption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accentColor(_ token: PackageKindAccentToken) -> Color {
        switch token {
        case .brandPrimary:
            Color.brewTextBrand
        case .statusInfo:
            Color.brewStatusInfo
        }
    }
}

#if DEBUG

    #Preview("Formula with upgrade") {
        InstalledListRowView(
            package: PreviewSupport.outdatedFormula,
            brewCommandCenter: PreviewSupport.commandCenter,
        )
        .padding()
        .frame(width: 400)
    }

    #Preview("Cask") {
        InstalledListRowView(
            package: PreviewSupport.currentCask,
            brewCommandCenter: PreviewSupport.commandCenter,
        )
        .padding()
        .frame(width: 400)
    }

    #Preview("Deprecated formula") {
        InstalledListRowView(
            package: PreviewSupport.deprecatedFormula,
            brewCommandCenter: PreviewSupport.commandCenter,
        )
        .padding()
        .frame(width: 400)
    }

    #Preview("Deprecated outdated formula") {
        InstalledListRowView(
            package: PreviewSupport.deprecatedOutdatedFormula,
            brewCommandCenter: PreviewSupport.commandCenter,
        )
        .padding()
        .frame(width: 400)
    }
#endif
