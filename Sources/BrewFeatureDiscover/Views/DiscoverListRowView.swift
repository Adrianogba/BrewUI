import BrewAppEnvironment
import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import SwiftUI

/// Owns one Discover row's view model, reading the shared installed-status source from the environment at
/// the row boundary so the installed badge stays reactive without threading the repository through parents.
struct DiscoverListRowRoot: View {
    let discoveryPackage: DiscoveryBrewPackage
    let showsInstallMetrics: Bool
    let onInstall: () -> Void
    let onUpgrade: () -> Void
    let onRequestUninstall: () -> Void
    @Environment(\.installedPackagesRepository) private var installedPackagesRepository
    @Environment(\.brewCommandCenter) private var brewCommandCenter

    var body: some View {
        DiscoverListRowView(
            discoveryPackage: discoveryPackage,
            installedRepository: installedPackagesRepository,
            brewCommandCenter: brewCommandCenter,
            showsInstallMetrics: showsInstallMetrics,
            onInstall: onInstall,
            onUpgrade: onUpgrade,
            onRequestUninstall: onRequestUninstall,
        )
        .id(discoveryPackage.id)
    }
}

struct DiscoverListRowView: View {
    let discoveryPackage: DiscoveryBrewPackage
    let onInstall: () -> Void
    let onUpgrade: () -> Void
    let onRequestUninstall: () -> Void
    @State private var viewModel: DiscoverListRowViewModel
    @State private var showsUninstallConfirmation = false

    init(
        discoveryPackage: DiscoveryBrewPackage,
        installedRepository: any InstalledPackageStatusReading,
        brewCommandCenter: any BrewCommandCenter,
        showsInstallMetrics: Bool = true,
        onInstall: @escaping () -> Void = {},
        onUpgrade: @escaping () -> Void = {},
        onRequestUninstall: @escaping () -> Void = {},
    ) {
        self.discoveryPackage = discoveryPackage
        _viewModel = State(
            initialValue: DiscoverListRowViewModel(
                discoveryPackage: discoveryPackage,
                installedRepository: installedRepository,
                brewCommandCenter: brewCommandCenter,
                showsInstallMetrics: showsInstallMetrics,
            ),
        )
        self.onInstall = onInstall
        self.onUpgrade = onUpgrade
        self.onRequestUninstall = onRequestUninstall
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrewSpacing.xs) {
            titleRow
            if viewModel.hasDescription {
                Text(viewModel.descriptionText)
                    .font(.brewCallout)
                    .foregroundStyle(Color.brewTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, BrewSpacing.sm)
        .task(id: discoveryPackage.id) {
            await viewModel.observeRowUpdates()
        }
        .onChange(of: discoveryPackage) { _, new in
            viewModel.update(discoveryPackage: new)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.rowAccessibilityLabel)
        .contextMenu {
            if viewModel.canOfferPackageActions {
                if !viewModel.isInstalled {
                    Button(String(localized: "Install", bundle: #bundle, comment: "Discover list context menu: install a package")) {
                        onInstall()
                    }
                    .disabled(viewModel.showsPackageMutationBusy)
                } else {
                    if viewModel.isInstalledVersionOutdated {
                        Button(String(localized: "Upgrade", bundle: #bundle, comment: "Discover list context menu: upgrade an outdated package")) {
                            onUpgrade()
                        }
                        .disabled(viewModel.showsPackageMutationBusy)
                    }
                    Button(String(localized: "Uninstall", bundle: #bundle, comment: "Discover list context menu: uninstall an installed package"), role: .destructive) {
                        showsUninstallConfirmation = true
                    }
                    .disabled(viewModel.showsPackageMutationBusy)
                }
            }
        }
        .confirmationDialog(
            String(localized: "Uninstall \(discoveryPackage.name)?", bundle: #bundle, comment: "Discover list context menu: uninstall confirmation title; interpolated package name"),
            isPresented: $showsUninstallConfirmation,
            presenting: discoveryPackage,
        ) { _ in
            Button(String(localized: "Uninstall", bundle: #bundle, comment: "Discover list context menu: confirm uninstall"), role: .destructive) {
                onRequestUninstall()
            }
            Button(String(localized: "Cancel", bundle: #bundle, comment: "Discover list context menu: cancel uninstall"), role: .cancel) {}
        } message: { package in
            Text(verbatim: String(
                localized: "This will remove \(package.name) from this Mac using Homebrew.",
                bundle: #bundle,
                comment: "Discover list context menu: uninstall confirmation message; interpolated package name",
            ))
        }
    }

    private var titleRow: some View {
        HStack(spacing: BrewSpacing.sm) {
            Text(viewModel.name)
                .font(.brewBodyEmphasized)
                .foregroundStyle(Color.brewTextPrimary)
                .lineLimit(1)

            if viewModel.showsPackageMutationBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            packageKindBadge

            if viewModel.installedStatusLabel != nil {
                DiscoverInstalledBadge()
            }

            Spacer(minLength: 0)
        }
    }

    private var packageKindBadge: some View {
        Text(viewModel.packageKindChrome.badgeLabel)
            .font(.brewCaption2)
            .foregroundStyle(accentColor(viewModel.packageKindChrome.accent))
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
    }

    private var metadataRow: some View {
        HStack(spacing: BrewSpacing.sm) {
            Text(verbatim: "v\(viewModel.stableVersionLabel)")
                .font(.brewCaption)
                .foregroundStyle(Color.brewTextTertiary)
            if viewModel.showsInstallMetrics {
                Text(verbatim: "•")
                    .font(.brewCaption)
                    .foregroundStyle(Color.brewTextTertiary)
                Text("\(viewModel.installs30DayLabel) installs (30d)", bundle: #bundle, comment: "Discover row: 30-day install count; %@ is a formatted number")
                    .font(.brewCaption)
                    .foregroundStyle(Color.brewTextTertiary)
            }
            Spacer(minLength: 0)
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

    #Preview("Installed") {
        DiscoverListRowView(
            discoveryPackage: PreviewSupport.discoverPreviewPackage,
            installedRepository: PreviewSupport.makeInstalledPackagesRepository(),
            brewCommandCenter: PreviewSupport.commandCenter,
        )
        .padding()
        .frame(width: 440)
    }
#endif
