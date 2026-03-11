import SwiftUI

private enum ScanSource: String, CaseIterable, Identifiable {
  case serverBookmarks
  case quickList

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .serverBookmarks:
      return L10n.text("scan_source.server_list")
    case .quickList:
      return L10n.text("scan_source.quick_list")
    }
  }
}

private enum KiwiWaterfallPreset: String, CaseIterable, Identifiable {
  case balanced
  case dx
  case overview
  case fast
  case custom

  var id: String { rawValue }

  static var selectableCases: [KiwiWaterfallPreset] {
    [.balanced, .dx, .overview, .fast]
  }

  var localizedTitle: String {
    switch self {
    case .balanced:
      return L10n.text("kiwi.waterfall.preset.balanced")
    case .dx:
      return L10n.text("kiwi.waterfall.preset.dx")
    case .overview:
      return L10n.text("kiwi.waterfall.preset.overview")
    case .fast:
      return L10n.text("kiwi.waterfall.preset.fast")
    case .custom:
      return L10n.text("kiwi.waterfall.preset.custom")
    }
  }

  var localizedDetail: String {
    switch self {
    case .balanced:
      return L10n.text("kiwi.waterfall.preset.balanced.detail")
    case .dx:
      return L10n.text("kiwi.waterfall.preset.dx.detail")
    case .overview:
      return L10n.text("kiwi.waterfall.preset.overview.detail")
    case .fast:
      return L10n.text("kiwi.waterfall.preset.fast.detail")
    case .custom:
      return L10n.text("kiwi.waterfall.preset.custom.detail")
    }
  }

  var values: (speed: Int, zoom: Int, minDB: Int, maxDB: Int)? {
    switch self {
    case .balanced:
      return (2, 0, -145, -20)
    case .dx:
      return (1, 8, -160, -45)
    case .overview:
      return (4, 0, -130, -10)
    case .fast:
      return (8, 2, -145, -25)
    case .custom:
      return nil
    }
  }

  static func matching(settings: RadioSessionSettings) -> KiwiWaterfallPreset {
    for preset in selectableCases {
      guard let values = preset.values else { continue }
      if settings.kiwiWaterfallSpeed == values.speed
        && settings.kiwiWaterfallZoom == values.zoom
        && settings.kiwiWaterfallMinDB == values.minDB
        && settings.kiwiWaterfallMaxDB == values.maxDB {
        return preset
      }
    }
    return .custom
  }
}

private enum OpenWebRXBookmarkSort: String, CaseIterable, Identifiable {
  case frequency
  case name

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .frequency:
      return L10n.text("openwebrx.bookmarks.sort.frequency")
    case .name:
      return L10n.text("openwebrx.bookmarks.sort.name")
    }
  }
}

private enum KiwiSignalPreset: String, CaseIterable, Identifiable {
  case auto
  case dx
  case local
  case utility
  case custom

  var id: String { rawValue }

  static var selectableCases: [KiwiSignalPreset] {
    [.auto, .dx, .local, .utility]
  }

  var localizedTitle: String {
    switch self {
    case .auto:
      return L10n.text("kiwi.signal_preset.auto")
    case .dx:
      return L10n.text("kiwi.signal_preset.dx")
    case .local:
      return L10n.text("kiwi.signal_preset.local")
    case .utility:
      return L10n.text("kiwi.signal_preset.utility")
    case .custom:
      return L10n.text("kiwi.signal_preset.custom")
    }
  }

  var localizedDetail: String {
    switch self {
    case .auto:
      return L10n.text("kiwi.signal_preset.auto.detail")
    case .dx:
      return L10n.text("kiwi.signal_preset.dx.detail")
    case .local:
      return L10n.text("kiwi.signal_preset.local.detail")
    case .utility:
      return L10n.text("kiwi.signal_preset.utility.detail")
    case .custom:
      return L10n.text("kiwi.signal_preset.custom.detail")
    }
  }

  var values: (agcEnabled: Bool, rfGain: Double)? {
    switch self {
    case .auto:
      return (true, 50)
    case .dx:
      return (true, 75)
    case .local:
      return (false, 25)
    case .utility:
      return (false, 45)
    case .custom:
      return nil
    }
  }

  static func matching(settings: RadioSessionSettings) -> KiwiSignalPreset {
    for preset in selectableCases {
      guard let values = preset.values else { continue }
      if settings.agcEnabled == values.agcEnabled
        && abs(settings.rfGain - values.rfGain) < 0.0001 {
        return preset
      }
    }
    return .custom
  }
}

struct ReceiverView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var favoritesStore: FavoritesStore
  @EnvironmentObject private var recordingStore: RecordingStore
  @FocusState private var isInlineFrequencyFocused: Bool
  @AccessibilityFocusState private var accessibilityFocus: ReceiverAccessibilityFocus?
  @State private var inlineFrequencyInput = ""
  @State private var inlineFrequencyError: String?
  @State private var inlineFrequencyEditing = false
  @State private var inlineFrequencyApplyTask: Task<Void, Never>?
  @State private var scanSource: ScanSource = .serverBookmarks
  @State private var quickScanChannels: [ScanChannel] = []
  @State private var isFMDXStationListExpanded = true

  private let defaultFrequencyRangeHz: ClosedRange<Int> = 100_000...3_000_000_000
  private let kiwiFrequencyRangeHz: ClosedRange<Int> = 10_000...32_000_000
  private let fmDxFrequencyRangeHz: ClosedRange<Int> = 64_000_000...110_000_000

  var body: some View {
    NavigationStack {
      Group {
        if let selectedProfile = profileStore.selectedProfile {
          receiverForm(for: selectedProfile)
        } else {
          UnavailableContentView(
            title: L10n.text("No Selected Radio"),
            systemImage: "antenna.radiowaves.left.and.right",
            description: L10n.text("Add and select a receiver profile in the Radios tab.")
          )
        }
      }
      .navigationTitle("Receiver")
      .appScreenBackground()
    }
  }

  private func receiverForm(for profile: SDRConnectionProfile) -> some View {
    let scannerChannels = scanChannels(for: profile)

    return Form {
      connectionSection(for: profile)
      tuningSection(for: profile)
      favoritesSection(for: profile)
      openWebRXControlsSection(for: profile)
      openWebRXServerBookmarksSection(for: profile)
      openWebRXBandPlanSection(for: profile)
      kiwiControlsSection(for: profile)
      fmDxControlsSection(for: profile)
      fmDxServerPresetsSection(for: profile)
      if profile.backend != .fmDxWebserver {
        scannerSection(for: profile, scannerChannels: scannerChannels)
      }
      fmDxLiveSection(for: profile)
      kiwiLiveSection(for: profile)
      audioSection(for: profile)
    }
    .voiceOverStable()
    .scrollContentBackground(.hidden)
    .onAppear {
      resetInlineFrequencyInput()
    }
    .onChange(of: profile.backend) { _ in
      resetInlineFrequencyInput()
    }
  }

  private func favoritesSection(for profile: SDRConnectionProfile) -> some View {
    let favoriteStations = favoritesStore.stations(for: profile)

    return Section {
      FocusRetainingButton {
        favoritesStore.toggleReceiver(profile)
      } label: {
        Label(
          favoritesStore.isFavoriteReceiver(profile)
            ? L10n.text("favorites.receiver.remove")
            : L10n.text("favorites.receiver.add"),
          systemImage: favoritesStore.isFavoriteReceiver(profile) ? "star.slash" : "star"
        )
      }

      FocusRetainingButton {
        favoritesStore.toggleStation(
          profile: profile,
          title: currentFavoriteStationTitle(for: profile),
          frequencyHz: radioSession.settings.frequencyHz,
          mode: radioSession.settings.mode
        )
      } label: {
        Label(
          isCurrentFrequencyFavorite(for: profile)
            ? L10n.text("favorites.station.remove_current")
            : L10n.text("favorites.station.add_current"),
          systemImage: isCurrentFrequencyFavorite(for: profile) ? "star.slash" : "star.circle"
        )
      }

      if !favoriteStations.isEmpty {
        ForEach(favoriteStations) { station in
          FocusRetainingButton {
            if station.mode != nil {
              radioSession.setMode(station.mode ?? radioSession.settings.mode)
            }
            radioSession.setFrequencyHz(station.frequencyHz)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(station.title)
              Text(FrequencyFormatter.mhzText(fromHz: station.frequencyHz))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
              favoritesStore.removeStation(station)
            } label: {
              Label(L10n.text("Delete"), systemImage: "trash")
            }
          }
        }
      }
    } header: {
      AppSectionHeader(title: L10n.text("favorites.section"))
    }
    .appSectionStyle()
  }

  private func connectionSection(for profile: SDRConnectionProfile) -> some View {
    Section {
      LabeledContent(L10n.text("Profile"), value: profile.name)

      LabeledContent(L10n.text("Backend"), value: profile.backend.displayName)
      LabeledContent(L10n.text("Endpoint"), value: profile.endpointDescription)

      LabeledContent(L10n.text("Status"), value: radioSession.statusText)

      if let backendStatus = radioSession.backendStatusText, !backendStatus.isEmpty {
        LabeledContent(L10n.text("Receiver data"), value: backendStatus)
      }

      if let error = radioSession.lastError {
        Text(error)
          .foregroundStyle(.red)
          .font(.footnote)
      }

      FocusRetainingButton({
        handleConnectionButtonTap(for: profile)
      }) {
        Text(connectionButtonTitle(for: profile))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityHint(L10n.text("Double tap to change connection state"))

      if radioSession.state == .failed {
        FocusRetainingButton {
          radioSession.reconnect(to: profile)
        } label: {
          Text(L10n.text("Reconnect"))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(L10n.text("Try connecting to this receiver again"))
      }
    } header: {
      AppSectionHeader(title: L10n.text("Connection"))
    }
    .appSectionStyle()
  }

  private func tuningSection(for profile: SDRConnectionProfile) -> some View {
    Section {
      frequencyInputSection(for: profile.backend)

      frequencyTuningControl(for: profile.backend)

      tuneStepControl(for: profile.backend)

      if profile.backend == .fmDxWebserver {
        fmdxBandSwitcher()
      } else {
        selectionNavigationLink(
          title: "Mode",
          value: currentModeSelectionValue(for: profile.backend),
          selectedID: currentModeSelectionID(for: profile.backend),
          options: availableModes(for: profile.backend).map {
            SelectionListOption(id: modeSelectionID(for: $0), title: $0.displayName, detail: nil)
          }
        ) { value in
          if let mode = modeFromSelectionID(value) {
            radioSession.setMode(mode)
          }
        }
      }

      if let tuneWarning = radioSession.fmdxTuneWarningText,
        profile.backend == .fmDxWebserver {
        Text(tuneWarning)
          .font(.footnote)
          .foregroundStyle(.orange)
      }
    } header: {
      AppSectionHeader(title: "Tuning")
    }
    .appSectionStyle()
  }

  @ViewBuilder
  private func openWebRXControlsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .openWebRX {
      Section {
        if radioSession.openWebRXProfiles.isEmpty {
          if radioSession.state == .connected &&
            radioSession.connectedProfileID == profile.id {
            Text(L10n.text("openwebrx.controls.waiting_profiles"))
              .foregroundStyle(.secondary)
          } else {
            Text(L10n.text("openwebrx.controls.connect_to_load"))
              .foregroundStyle(.secondary)
              .font(.footnote)
          }
        } else {
          selectionNavigationLink(
            title: L10n.text("openwebrx.server_profile"),
            value: selectedOpenWebRXProfileName(),
            selectedID: radioSession.selectedOpenWebRXProfileID ?? radioSession.openWebRXProfiles.first?.id ?? "",
            options: radioSession.openWebRXProfiles.map {
              SelectionListOption(id: $0.id, title: $0.name, detail: nil)
            }
          ) { value in
            if !value.isEmpty {
              radioSession.selectOpenWebRXProfile(value, for: profile)
            }
          }

          if radioSession.state != .connected ||
            radioSession.connectedProfileID != profile.id {
            Text(L10n.text("openwebrx.controls.cached_profiles"))
              .foregroundStyle(.secondary)
              .font(.footnote)
          }
        }

        Toggle(
          L10n.text("openwebrx.squelch"),
          isOn: Binding(
            get: { radioSession.settings.squelchEnabled },
            set: { radioSession.setSquelchEnabled($0) }
          )
        )
        .accessibilityHint(L10n.text("openwebrx.squelch_hint"))

        if radioSession.settings.squelchEnabled {
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
              L10n.text("openwebrx.squelch_level"),
              value: "\(radioSession.settings.openWebRXSquelchLevel) dB"
            )
            Slider(
              value: Binding(
                get: { Double(radioSession.settings.openWebRXSquelchLevel) },
                set: { radioSession.setOpenWebRXSquelchLevel(Int($0.rounded())) }
              ),
              in: -150 ... -20,
              step: 1
            )
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(L10n.text("openwebrx.squelch_level"))
          .accessibilityValue("\(radioSession.settings.openWebRXSquelchLevel) dB")
        }

        if let activeBand = activeOpenWebRXBandName() {
          LabeledContent(L10n.text("openwebrx.current_band"), value: activeBand)
        }

        if let activeBookmark = activeOpenWebRXBookmark() {
          LabeledContent(L10n.text("openwebrx.active_bookmark"), value: activeBookmark.name)
          FocusRetainingButton {
            radioSession.applyServerBookmark(activeBookmark)
          } label: {
            Label(L10n.text("openwebrx.active_bookmark.apply"), systemImage: "bookmark.fill")
          }
          .disabled(radioSession.state != .connected)
        }

        if let activeBand = activeOpenWebRXBandEntry() {
          FocusRetainingButton {
            radioSession.tuneToBand(activeBand)
          } label: {
            Label(L10n.text("openwebrx.active_band.center"), systemImage: "scope")
          }
          .disabled(radioSession.state != .connected)

          if !activeBand.frequencies.isEmpty {
            NavigationLink {
              OpenWebRXBandDetailView(
                band: activeBand,
                onTuneBandCenter: {
                  radioSession.tuneToBand(activeBand)
                },
                onTuneFrequency: { item in
                  radioSession.tuneToBand(activeBand, using: item)
                }
              )
            } label: {
              LabeledContent(
                L10n.text("openwebrx.active_band.frequencies"),
                value: "\(activeBand.frequencies.count)"
              )
            }
          }
        }
      } header: {
        AppSectionHeader(title: L10n.text("openwebrx.controls"))
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func openWebRXServerBookmarksSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .openWebRX {
      Section {
        if radioSession.serverBookmarks.isEmpty {
          Text(L10n.text("openwebrx.bookmarks_empty"))
            .foregroundStyle(.secondary)
        } else {
          NavigationLink {
            OpenWebRXBookmarksView(
              bookmarks: radioSession.serverBookmarks,
              activeFrequencyHz: radioSession.settings.frequencyHz,
              onSelect: { bookmark in
                radioSession.applyServerBookmark(bookmark)
              }
            )
          } label: {
            LabeledContent(
              L10n.text("openwebrx.bookmarks_browse"),
              value: openWebRXBookmarkSummary()
            )
          }
        }
      } header: {
        AppSectionHeader(title: L10n.text("openwebrx.bookmarks_section"))
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func openWebRXBandPlanSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .openWebRX {
      Section {
        if radioSession.openWebRXBandPlan.isEmpty {
          Text(L10n.text("openwebrx.band_plan_loading"))
            .foregroundStyle(.secondary)
        } else {
          NavigationLink {
            OpenWebRXBandPlanListView(
              bands: radioSession.openWebRXBandPlan,
              activeFrequencyHz: radioSession.settings.frequencyHz,
              onTuneBandCenter: { band in
                radioSession.tuneToBand(band)
              },
              onTuneFrequency: { band, item in
                radioSession.tuneToBand(band, using: item)
              }
            )
          } label: {
            LabeledContent(
              L10n.text("openwebrx.band_plan_browse"),
              value: openWebRXBandPlanSummary()
            )
          }
        }
      } header: {
        AppSectionHeader(title: L10n.text("openwebrx.band_plan_section"))
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func fmDxControlsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .fmDxWebserver {
      Section {
        fmDxPrimaryToggleRow()
        fmDxAGCToggleRow()

        fmDxAntennaPicker()
        fmDxBandwidthPicker()
      } header: {
        AppSectionHeader(title: L10n.text("fmdx.controls"))
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func fmDxPrimaryToggleRow() -> some View {
    let showsFilterControls = radioSession.fmdxSupportsFilterControls
    let controlsEnabled = radioSession.state == .connected

    HStack(spacing: 8) {
      fmDxAudioModeChip(isEnabled: controlsEnabled)

      if showsFilterControls {
        fmdxToggleChip(
          title: L10n.text("fmdx.eq_filter"),
          accessibilityTitle: L10n.text("fmdx.eq_filter"),
          isOn: radioSession.settings.noiseReductionEnabled,
          isEnabled: controlsEnabled
        ) {
          radioSession.setNoiseReductionEnabled(!radioSession.settings.noiseReductionEnabled)
        }

        fmdxToggleChip(
          title: L10n.text("fmdx.ims_filter"),
          accessibilityTitle: L10n.text("fmdx.ims_filter"),
          isOn: radioSession.settings.imsEnabled,
          isEnabled: controlsEnabled
        ) {
          radioSession.setIMSEnabled(!radioSession.settings.imsEnabled)
        }
      }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func fmDxAGCToggleRow() -> some View {
    let controlsEnabled = radioSession.state == .connected

    if radioSession.fmdxSupportsAGCControl {
      HStack(spacing: 8) {
        fmdxToggleChip(
          title: "AGC",
          accessibilityTitle: "AGC",
          isOn: radioSession.settings.agcEnabled,
          isEnabled: controlsEnabled
        ) {
          radioSession.setAGCEnabled(!radioSession.settings.agcEnabled)
        }
        Spacer(minLength: 0)
      }
      .accessibilityElement(children: .contain)
    }
  }

  @ViewBuilder
  private func fmDxServerPresetsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .fmDxWebserver {
      let stationList = radioSession.fmdxServerPresets

      Section {
        FocusRetainingButton {
          isFMDXStationListExpanded.toggle()
        } label: {
          Label(
            L10n.text(
              isFMDXStationListExpanded
                ? "fmdx.station_list.collapse"
                : "fmdx.station_list.expand"
            ),
            systemImage: isFMDXStationListExpanded ? "chevron.up" : "chevron.down"
          )
        }
      }
      .appSectionStyle()

      if isFMDXStationListExpanded {
        Section {
          if stationList.isEmpty {
            Text(L10n.text("fmdx.server_presets.empty"))
              .foregroundStyle(.secondary)
              .font(.footnote)
          } else {
            ForEach(stationList) { preset in
              fmdxServerBookmarkRow(preset: preset)
            }
          }
        } header: {
          AppSectionHeader(title: L10n.text("fmdx.server_presets.section"))
        }
        .appSectionStyle()
      }
    }
  }

  private func fmdxServerBookmarkRow(preset: SDRServerBookmark) -> some View {
    FocusRetainingButton {
      radioSession.setFrequencyHz(preset.frequencyHz)
    } label: {
      HStack {
        Text(preset.name)
        Spacer()
        Text(FrequencyFormatter.fmDxMHzText(fromHz: preset.frequencyHz))
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func kiwiControlsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .kiwiSDR {
      Section {
        selectionNavigationLink(
          title: L10n.text("kiwi.signal_preset"),
          value: currentKiwiSignalPreset().localizedTitle,
          selectedID: currentKiwiSignalPreset().rawValue,
          options: KiwiSignalPreset.selectableCases.map {
            SelectionListOption(
              id: $0.rawValue,
              title: $0.localizedTitle,
              detail: $0.localizedDetail
            )
          }
        ) { value in
          guard let preset = KiwiSignalPreset(rawValue: value),
            let values = preset.values
          else {
            return
          }
          radioSession.applyKiwiSignalPreset(
            agcEnabled: values.agcEnabled,
            rfGain: values.rfGain
          )
        }

        Toggle(
          L10n.text("kiwi.agc"),
          isOn: Binding(
            get: { radioSession.settings.agcEnabled },
            set: { radioSession.setAGCEnabled($0) }
          )
        )
        .accessibilityHint(L10n.text("kiwi.agc_hint"))

        if !radioSession.settings.agcEnabled {
          VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("receiver.rf_gain_value", Int(radioSession.settings.rfGain)))
            Slider(
              value: Binding(
                get: { radioSession.settings.rfGain },
                set: { radioSession.setRFGain($0) }
              ),
              in: 0...100,
              step: 1
            )
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(L10n.text("RF gain"))
          .accessibilityValue("\(Int(radioSession.settings.rfGain))")
        }

        Toggle(
          L10n.text("kiwi.squelch"),
          isOn: Binding(
            get: { radioSession.settings.squelchEnabled },
            set: { radioSession.setSquelchEnabled($0) }
          )
        )
        .accessibilityHint(L10n.text("kiwi.squelch_hint"))

        if radioSession.settings.squelchEnabled {
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
              L10n.text("kiwi.squelch_level"),
              value: "\(radioSession.settings.kiwiSquelchThreshold)"
            )
            Slider(
              value: Binding(
                get: { Double(radioSession.settings.kiwiSquelchThreshold) },
                set: { radioSession.setKiwiSquelchThreshold(Int($0.rounded())) }
              ),
              in: 0 ... 30,
              step: 1
            )
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(L10n.text("kiwi.squelch_level"))
          .accessibilityValue("\(radioSession.settings.kiwiSquelchThreshold)")
        }

        selectionNavigationLink(
          title: L10n.text("kiwi.waterfall.speed"),
          value: "x\(radioSession.settings.kiwiWaterfallSpeed)",
          selectedID: "\(radioSession.settings.kiwiWaterfallSpeed)",
          options: [1, 2, 4, 8].map {
            SelectionListOption(id: "\($0)", title: "x\($0)", detail: nil)
          }
        ) { value in
          if let speed = Int(value) {
            radioSession.setKiwiWaterfallSpeed(speed)
          }
        }

        selectionNavigationLink(
          title: L10n.text("kiwi.waterfall.preset"),
          value: currentKiwiWaterfallPreset().localizedTitle,
          selectedID: currentKiwiWaterfallPreset().rawValue,
          options: KiwiWaterfallPreset.selectableCases.map {
            SelectionListOption(
              id: $0.rawValue,
              title: $0.localizedTitle,
              detail: $0.localizedDetail
            )
          }
        ) { value in
          guard let preset = KiwiWaterfallPreset(rawValue: value),
            let values = preset.values
          else {
            return
          }
          radioSession.applyKiwiWaterfallSettings(
            speed: values.speed,
            zoom: values.zoom,
            minDB: values.minDB,
            maxDB: values.maxDB
          )
        }

        VStack(alignment: .leading, spacing: 6) {
          LabeledContent(
            L10n.text("kiwi.waterfall.zoom"),
            value: "\(radioSession.settings.kiwiWaterfallZoom)"
          )
          Slider(
            value: Binding(
              get: { Double(radioSession.settings.kiwiWaterfallZoom) },
              set: { radioSession.setKiwiWaterfallZoom(Int($0.rounded())) }
            ),
            in: 0 ... 14,
            step: 1
          )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("kiwi.waterfall.zoom"))
        .accessibilityValue("\(radioSession.settings.kiwiWaterfallZoom)")

        VStack(alignment: .leading, spacing: 6) {
          LabeledContent(
            L10n.text("kiwi.waterfall.min_db"),
            value: "\(radioSession.settings.kiwiWaterfallMinDB) dB"
          )
          Slider(
            value: Binding(
              get: { Double(radioSession.settings.kiwiWaterfallMinDB) },
              set: { radioSession.setKiwiWaterfallMinDB(Int($0.rounded())) }
            ),
            in: -190 ... -10,
            step: 1
          )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("kiwi.waterfall.min_db"))
        .accessibilityValue("\(radioSession.settings.kiwiWaterfallMinDB) dB")

        VStack(alignment: .leading, spacing: 6) {
          LabeledContent(
            L10n.text("kiwi.waterfall.max_db"),
            value: "\(radioSession.settings.kiwiWaterfallMaxDB) dB"
          )
          Slider(
            value: Binding(
              get: { Double(radioSession.settings.kiwiWaterfallMaxDB) },
              set: { radioSession.setKiwiWaterfallMaxDB(Int($0.rounded())) }
            ),
            in: -120 ... 30,
            step: 1
          )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("kiwi.waterfall.max_db"))
        .accessibilityValue("\(radioSession.settings.kiwiWaterfallMaxDB) dB")
      } header: {
        AppSectionHeader(title: L10n.text("kiwi.controls"))
      }
      .appSectionStyle()
    }
  }

  private func fmDxAudioModeChip(isEnabled: Bool) -> some View {
    let isForcedStereo = radioSession.fmdxTelemetry?.isForcedStereo ?? false
    let modeText = isForcedStereo
      ? L10n.text("fmdx.stereo_state.stereo")
      : L10n.text("fmdx.stereo_state.mono")
    let accessibilityText = isForcedStereo
      ? L10n.text("fmdx.audio_mode.accessibility.stereo")
      : L10n.text("fmdx.audio_mode.accessibility.mono")

    return fmdxToggleChip(
      title: modeText,
      accessibilityTitle: accessibilityText,
      accessibilityValue: nil,
      isOn: isForcedStereo,
      isEnabled: isEnabled
    ) {
      radioSession.setFMDXForcedStereoEnabled(!isForcedStereo)
    }
  }

  @ViewBuilder
  private func fmDxAntennaPicker() -> some View {
    if !radioSession.fmdxCapabilities.antennas.isEmpty {
      selectionNavigationLink(
        title: L10n.text("fmdx.antenna"),
        value: currentFMDXAntennaName(),
        selectedID: radioSession.selectedFMDXAntennaID
          ?? radioSession.fmdxCapabilities.antennas.first?.id
          ?? "",
        options: radioSession.fmdxCapabilities.antennas.map {
          SelectionListOption(id: $0.id, title: $0.label, detail: nil)
        },
        disabled: radioSession.state != .connected
      ) { value in
        if !value.isEmpty {
          radioSession.setFMDXAntenna(value)
        }
      }
    }
  }

  @ViewBuilder
  private func fmDxBandwidthPicker() -> some View {
    if !radioSession.fmdxCapabilities.bandwidths.isEmpty {
      selectionNavigationLink(
        title: L10n.text("fmdx.bandwidth"),
        value: currentFMDXBandwidthName(),
        selectedID: radioSession.selectedFMDXBandwidthID
          ?? radioSession.fmdxCapabilities.bandwidths.first?.id
          ?? "",
        options: radioSession.fmdxCapabilities.bandwidths.map {
          SelectionListOption(id: $0.id, title: $0.label, detail: nil)
        },
        disabled: radioSession.state != .connected
      ) { value in
        guard let option = radioSession.fmdxCapabilities.bandwidths.first(where: { $0.id == value }) else { return }
        radioSession.setFMDXBandwidth(option)
      }
    }
  }

  private func scannerSection(for profile: SDRConnectionProfile, scannerChannels: [ScanChannel]) -> some View {
    Section {
      selectionNavigationLink(
        title: "Channel source",
        value: scanSource.displayName,
        selectedID: scanSource.rawValue,
        options: ScanSource.allCases.map {
          SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
        }
      ) { value in
        if let source = ScanSource(rawValue: value) {
          scanSource = source
        }
      }

      if scanSource == .quickList {
        FocusRetainingButton {
          quickScanChannels.removeAll()
        } label: {
          Text(L10n.text("scanner.quick_list.clear"))
        }
        .disabled(quickScanChannels.isEmpty)
      }

      LabeledContent("Channels", value: "\(scannerChannels.count)")

      Slider(
        value: $radioSession.scannerThreshold,
        in: thresholdRange(for: profile.backend),
        step: thresholdStep(for: profile.backend)
      )
      LabeledContent(
        "Threshold",
        value: "\(String(format: "%.1f", radioSession.scannerThreshold)) \(radioSession.scannerSignalUnit(for: profile.backend))"
      )

      VStack(alignment: .leading, spacing: 6) {
        LabeledContent("Dwell", value: "\(String(format: "%.1f", radioSession.settings.scannerDwellSeconds)) s")
        Slider(
          value: Binding(
            get: { radioSession.settings.scannerDwellSeconds },
            set: { radioSession.setScannerDwellSeconds($0) }
          ),
          in: 0.5...6,
          step: 0.1
        )
      }

      VStack(alignment: .leading, spacing: 6) {
        LabeledContent("Hold on hit", value: "\(String(format: "%.1f", radioSession.settings.scannerHoldSeconds)) s")
        Slider(
          value: Binding(
            get: { radioSession.settings.scannerHoldSeconds },
            set: { radioSession.setScannerHoldSeconds($0) }
          ),
          in: 0.5...12,
          step: 0.1
        )
      }

      if radioSession.isScannerRunning {
        FocusRetainingButton {
          radioSession.stopScanner()
        } label: {
          Text("Stop scanner")
        }
        .buttonStyle(.borderedProminent)
      } else {
        FocusRetainingButton {
          radioSession.startScanner(
            channels: scannerChannels,
            backend: profile.backend,
            dwellSeconds: radioSession.settings.scannerDwellSeconds,
            holdSeconds: radioSession.settings.scannerHoldSeconds
          )
        } label: {
          Text("Start scanner")
        }
        .buttonStyle(.borderedProminent)
        .disabled(scannerChannels.isEmpty || radioSession.state != .connected)
      }

      if let scannerStatus = radioSession.scannerStatusText {
        Text(scannerStatus)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if profile.backend == .openWebRX {
        Text("Threshold hold works with live signal metrics (KiwiSDR and FM-DX).")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      LabeledContent(
        L10n.text("settings.dx.adaptive_scan"),
        value: radioSession.settings.adaptiveScannerEnabled
          ? L10n.text("scanner.mode.adaptive")
          : L10n.text("scanner.mode.fixed")
      )
      .font(.footnote)
    } header: {
      AppSectionHeader(title: "Scanner")
    }
    .appSectionStyle()
  }

  @ViewBuilder
  private func fmDxLiveSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .fmDxWebserver, let telemetry = radioSession.fmdxTelemetry {
      Section {
        fmDxSignalMetricsRow(telemetry: telemetry)
        if let users = telemetry.users {
          LabeledContent(L10n.text("fmdx.field.users"), value: "\(users)")
        }
        if let pi = telemetry.pi, !pi.isEmpty {
          LabeledContent("PI", value: pi)
        }
        if let ps = telemetry.ps, !ps.isEmpty {
          LabeledContent("PS", value: ps)
        }
        if let countryName = telemetry.countryName, !countryName.isEmpty {
          LabeledContent(L10n.text("fmdx.field.country"), value: countryName)
        }
        if !telemetry.afMHz.isEmpty {
          let limitedAFCount = min(telemetry.afMHz.count, 16)
          ForEach(0..<limitedAFCount, id: \.self) { index in
            let afMHz = telemetry.afMHz[index]
            let afHz = frequencyHz(fromMHz: afMHz)
            HStack {
              FocusRetainingButton {
                radioSession.setFrequencyHz(afHz)
              } label: {
                Text(String(format: "%.1f MHz", afMHz))
              }
              .buttonStyle(.borderless)

              Spacer()

              FocusRetainingButton {
                addQuickScanChannel(frequencyHz: afHz)
              } label: {
                Text(L10n.text("fmdx.af.scan"))
              }
              .buttonStyle(.borderless)
            }
          }
        }
        if let rt0 = telemetry.rt0, !rt0.isEmpty {
          Text(L10n.text("fmdx.rt0", rt0))
            .font(.footnote)
        }
        if let rt1 = telemetry.rt1, !rt1.isEmpty {
          Text(L10n.text("fmdx.rt1", rt1))
            .font(.footnote)
        }
        NavigationLink {
          FMDXRDSDetailsView(
            telemetry: telemetry,
            showRdsErrorCounters: Binding(
              get: { radioSession.settings.showRdsErrorCounters },
              set: { radioSession.setShowRdsErrorCounters($0) }
            )
          )
        } label: {
          Label(L10n.text("fmdx.live.more_details"), systemImage: "text.badge.plus")
        }
      } header: {
        AppSectionHeader(title: L10n.text("fmdx.live.section"))
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func fmDxSignalMetricsRow(telemetry: FMDXTelemetry) -> some View {
    if telemetry.signal != nil || telemetry.signalTop != nil {
      HStack(spacing: 8) {
        if let signal = telemetry.signal {
          metricCard(
            title: L10n.text("fmdx.field.signal"),
            value: String(format: "%.1f dBf", signal)
          )
        }
        if let signalTop = telemetry.signalTop {
          metricCard(
            title: L10n.text("fmdx.field.signal_peak"),
            value: String(format: "%.1f dBf", signalTop)
          )
        }
      }
    }
  }

  @ViewBuilder
  private func kiwiLiveSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .kiwiSDR, let telemetry = radioSession.kiwiTelemetry {
      Section {
        if let rssi = telemetry.rssiDBm {
          LabeledContent(L10n.text("kiwi.live.smeter"), value: String(format: "%.1f dBm", rssi))
        } else {
          LabeledContent(L10n.text("kiwi.live.smeter"), value: L10n.text("kiwi.live.no_data"))
        }
        LabeledContent(L10n.text("kiwi.live.audio_rate"), value: "\(telemetry.sampleRateHz) Hz")

        if !telemetry.waterfallBins.isEmpty {
          WaterfallStripView(bins: telemetry.waterfallBins)
            .frame(height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
            .accessibilityLabel(L10n.text("kiwi.live.waterfall"))
            .accessibilityValue(L10n.text("kiwi.live.waterfall"))
        } else {
          Text(L10n.text("kiwi.live.waterfall_loading"))
            .foregroundStyle(.secondary)
        }
      } header: {
        AppSectionHeader(title: L10n.text("kiwi.live.section"))
      }
      .appSectionStyle()
    }
  }

  private func audioSection(for profile: SDRConnectionProfile) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.text("audio.volume_percent", Int((radioSession.settings.audioVolume * 100).rounded())))
        Slider(
          value: Binding(
            get: { radioSession.settings.audioVolume },
            set: { radioSession.setAudioVolume($0) }
          ),
          in: 0...1,
          step: 0.01
        )
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(L10n.text("Audio volume"))
      .accessibilityValue("\(Int((radioSession.settings.audioVolume * 100).rounded())) percent")

      Toggle(
        "Mute audio",
        isOn: Binding(
          get: { radioSession.settings.audioMuted },
          set: { radioSession.setAudioMuted($0) }
        )
      )

      if recordingStore.isRecording {
        LabeledContent(
          L10n.text("recordings.active"),
          value: [
            recordingStore.activeReceiverName ?? profile.name,
            recordingStore.activeFormat?.localizedTitle ?? ""
          ]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        )

        FocusRetainingButton({
          recordingStore.stopRecording()
        }, role: .destructive) {
          Label(L10n.text("recordings.stop"), systemImage: "stop.circle")
        }
      } else {
        FocusRetainingButton {
          recordingStore.startRecording(
            receiverName: profile.name,
            backend: profile.backend,
            frequencyHz: radioSession.settings.frequencyHz,
            mode: radioSession.settings.mode
          )
        } label: {
          Label(L10n.text("recordings.start"), systemImage: "record.circle")
        }
        .disabled(radioSession.state != .connected || radioSession.connectedProfileID != profile.id)
      }

      NavigationLink {
        RecordingsView()
      } label: {
        LabeledContent(
          L10n.text("recordings.section"),
          value: "\(recordingStore.recordings.count)"
        )
      }
    } header: {
      AppSectionHeader(title: "Audio")
    }
    .appSectionStyle()
  }

  private func connectionButtonTitle(for profile: SDRConnectionProfile) -> String {
    if radioSession.state == .connecting {
      return L10n.text("connection.connecting")
    }
    if radioSession.state == .connected &&
      radioSession.connectedProfileID == profile.id {
      return L10n.text("connection.disconnect")
    }
    return L10n.text("connection.connect")
  }

  private func handleConnectionButtonTap(for profile: SDRConnectionProfile) {
    if radioSession.state == .connected &&
      radioSession.connectedProfileID == profile.id {
      radioSession.disconnect()
      return
    }

    if radioSession.state == .connecting {
      radioSession.reconnect(to: profile)
      return
    }

    radioSession.connect(to: profile)
  }

  private func thresholdRange(for backend: SDRBackend) -> ClosedRange<Double> {
    switch backend {
    case .fmDxWebserver:
      return 0...120
    case .kiwiSDR, .openWebRX:
      return -140...0
    }
  }

  private func thresholdStep(for backend: SDRBackend) -> Double {
    switch backend {
    case .fmDxWebserver:
      return 1
    case .kiwiSDR, .openWebRX:
      return 0.5
    }
  }

  private func tuneStepControl(for backend: SDRBackend) -> some View {
    let stepLabel = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)
    let options = radioSession.tuneStepOptions(for: backend).map(FrequencyFormatter.tuneStepText(fromHz:))

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Button {
          changeTuneStep(by: -1, backend: backend)
          focusTuneStepControl()
        } label: {
          Image(systemName: "minus")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHidden(true)

        VStack(spacing: 4) {
          Text(stepLabel)
            .font(.title3.monospacedDigit().weight(.semibold))

          Text(options.joined(separator: " / "))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)

        Button {
          changeTuneStep(by: 1, backend: backend)
          focusTuneStepControl()
        } label: {
          Image(systemName: "plus")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHidden(true)
      }
      .padding(12)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(AppTheme.cardFill)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(AppTheme.cardStroke, lineWidth: 1)
      }
      .contentShape(Rectangle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(L10n.text("receiver.tune_step.label"))
      .accessibilityValue(stepLabel)
      .accessibilityFocused($accessibilityFocus, equals: .tuneStepControl)
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment:
          changeTuneStep(by: 1, backend: backend)
        case .decrement:
          changeTuneStep(by: -1, backend: backend)
        @unknown default:
          break
        }
      }
      .accessibilityScrollAction { edge in
        switch edge {
        case .leading, .top:
          changeTuneStep(by: -1, backend: backend)
        case .trailing, .bottom:
          changeTuneStep(by: 1, backend: backend)
        }
      }
    }
  }

  private func fmdxBandSwitcher() -> some View {
    let selectedBand: DemodulationMode = radioSession.settings.mode == .am ? .am : .fm
    let supportsAM = radioSession.fmdxSupportsAM

    return VStack(alignment: .leading, spacing: 8) {
      Text(L10n.text("fmdx.band"))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      HStack(spacing: 10) {
        fmdxBandButton(title: L10n.text("fmdx.band.fm"), mode: .fm, isSelected: selectedBand == .fm)
        fmdxBandButton(title: L10n.text("fmdx.band.am"), mode: .am, isSelected: selectedBand == .am)
      }

      if !supportsAM {
        Text(L10n.text("fmdx.band.am_unavailable_hint"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func fmdxBandButton(title: String, mode: DemodulationMode, isSelected: Bool) -> some View {
    if isSelected {
      FocusRetainingButton {
        radioSession.setMode(mode)
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
            .accessibilityHidden(true)
          Text(title)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityAddTraits(.isSelected)
      .accessibilityValue(L10n.text("common.selected"))
    } else {
      FocusRetainingButton {
        radioSession.setMode(mode)
      } label: {
        Text(title)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
    }
  }

  @ViewBuilder
  private func selectionNavigationLink(
    title: String,
    value: String,
    selectedID: String,
    options: [SelectionListOption],
    disabled: Bool = false,
    onSelect: @escaping (String) -> Void
  ) -> some View {
    if disabled {
      LabeledContent(title, value: value)
        .foregroundStyle(.secondary)
    } else {
      NavigationLink {
        SelectionListView(
          title: title,
          options: options,
          selectedID: selectedID,
          onSelect: onSelect
        )
      } label: {
        LabeledContent(title, value: value)
      }
    }
  }

  private func availableModes(for backend: SDRBackend) -> [DemodulationMode] {
    switch backend {
    case .fmDxWebserver:
      return [.fm, .am]
    case .kiwiSDR, .openWebRX:
      return DemodulationMode.allCases
    }
  }

  private func modeSelectionID(for mode: DemodulationMode) -> String {
    switch mode {
    case .am:
      return "am"
    case .fm:
      return "fm"
    case .nfm:
      return "nfm"
    case .usb:
      return "usb"
    case .lsb:
      return "lsb"
    case .cw:
      return "cw"
    }
  }

  private func modeFromSelectionID(_ value: String) -> DemodulationMode? {
    switch value {
    case "am":
      return .am
    case "fm":
      return .fm
    case "nfm":
      return .nfm
    case "usb":
      return .usb
    case "lsb":
      return .lsb
    case "cw":
      return .cw
    default:
      return nil
    }
  }

  private func currentModeSelectionValue(for backend: SDRBackend) -> String {
    let allowed = availableModes(for: backend)
    let selected = allowed.contains(radioSession.settings.mode) ? radioSession.settings.mode : allowed.first ?? .fm
    return selected.displayName
  }

  private func currentModeSelectionID(for backend: SDRBackend) -> String {
    let allowed = availableModes(for: backend)
    let selected = allowed.contains(radioSession.settings.mode) ? radioSession.settings.mode : allowed.first ?? .fm
    return modeSelectionID(for: selected)
  }

  private func changeTuneStep(by offset: Int, backend: SDRBackend) {
    let steps = radioSession.tuneStepOptions(for: backend)
    guard !steps.isEmpty else { return }

    let currentStep = radioSession.settings.tuneStepHz
    let currentIndex: Int
    if let exactIndex = steps.firstIndex(of: currentStep) {
      currentIndex = exactIndex
    } else {
      currentIndex = steps.enumerated().min(by: { abs($0.element - currentStep) < abs($1.element - currentStep) })?.offset ?? 0
    }

    let nextIndex = min(max(currentIndex + offset, 0), steps.count - 1)
    guard nextIndex != currentIndex else { return }
    setTuneStepAndAnnounce(steps[nextIndex])
  }

  private func setTuneStepAndAnnounce(_ stepHz: Int) {
    guard stepHz != radioSession.settings.tuneStepHz else { return }
    radioSession.setTuneStepHz(stepHz)

    let stepText = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)
    AppAccessibilityAnnouncementCenter.post(
      L10n.text("receiver.tune_step.changed", stepText)
    )
  }

  private func frequencyTuningControl(for backend: SDRBackend) -> some View {
    let frequencyValue = frequencyText(fromHz: radioSession.settings.frequencyHz, backend: backend)
    let tuneStepLabel = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Button {
          tuneFrequency(byStepCount: -1)
        } label: {
          Image(systemName: "minus")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHidden(true)

        VStack(spacing: 4) {
          Text(frequencyValue)
            .font(.title2.monospacedDigit().weight(.semibold))

          Text(tuneStepLabel)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)

        Button {
          tuneFrequency(byStepCount: 1)
        } label: {
          Image(systemName: "plus")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHidden(true)
      }
      .padding(12)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(AppTheme.cardFill)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(AppTheme.cardStroke, lineWidth: 1)
      }
      .contentShape(Rectangle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(L10n.text("fmdx.field.frequency"))
      .accessibilityValue(frequencyValue)
      .accessibilityHint(L10n.text("receiver.frequency.swipe_and_step_hint", tuneStepLabel))
      .accessibilityFocused($accessibilityFocus, equals: .frequencyControl)
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment:
          tuneFrequency(byStepCount: frequencyAdjustmentStepCount(forIncrement: true))
        case .decrement:
          tuneFrequency(byStepCount: frequencyAdjustmentStepCount(forIncrement: false))
        @unknown default:
          break
        }
      }
      .accessibilityAction(named: Text(L10n.text("receiver.tune_step.previous_action"))) {
        changeTuneStep(by: -1, backend: backend)
      }
      .accessibilityAction(named: Text(L10n.text("receiver.tune_step.next_action"))) {
        changeTuneStep(by: 1, backend: backend)
      }
    }
  }

  private func tuneFrequency(byStepCount stepCount: Int) {
    radioSession.tune(byStepCount: stepCount)
    focusFrequencyControl()
  }

  private func currentFavoriteStationTitle(for profile: SDRConnectionProfile) -> String {
    switch profile.backend {
    case .fmDxWebserver:
      if let station = radioSession.fmdxTelemetry?.txInfo?.station?.trimmingCharacters(in: .whitespacesAndNewlines),
        !station.isEmpty {
        return station
      }
      if let ps = radioSession.fmdxTelemetry?.ps?.trimmingCharacters(in: .whitespacesAndNewlines),
        !ps.isEmpty {
        return ps
      }
    case .kiwiSDR:
      if let band = radioSession.currentKiwiBandName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !band.isEmpty {
        return band
      }
    case .openWebRX:
      if let bookmark = radioSession.serverBookmarks.first(where: { $0.frequencyHz == radioSession.settings.frequencyHz }) {
        return bookmark.name
      }
    }

    return FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz)
  }

  private func isCurrentFrequencyFavorite(for profile: SDRConnectionProfile) -> Bool {
    favoritesStore.stations(for: profile).contains {
      $0.frequencyHz == radioSession.settings.frequencyHz && $0.mode == radioSession.settings.mode
    }
  }

  private func frequencyAdjustmentStepCount(forIncrement isIncrement: Bool) -> Int {
    let baseStep = radioSession.settings.tuningGestureDirection.frequencyAdjustmentStepCount
    return isIncrement ? baseStep : -baseStep
  }

  private func focusFrequencyControl() {
    Task { @MainActor in
      accessibilityFocus = .frequencyControl
    }
  }

  private func focusTuneStepControl() {
    Task { @MainActor in
      accessibilityFocus = .tuneStepControl
    }
  }

  private func fmdxToggleChip(
    title: String,
    accessibilityTitle: String,
    accessibilityValue: String? = nil,
    isOn: Bool,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Group {
      if isOn {
        FocusRetainingButton(action) {
          fmdxToggleChipLabel(title: title)
        }
        .buttonStyle(.borderedProminent)
      } else {
        FocusRetainingButton(action) {
          fmdxToggleChipLabel(title: title)
        }
        .buttonStyle(.bordered)
      }
    }
    .controlSize(.small)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityTitle)
    .accessibilityValue(accessibilityValue ?? (isOn ? L10n.text("common.on") : L10n.text("common.off")))
  }

  private func fmdxToggleChipLabel(title: String) -> some View {
    Text(title)
      .font(.footnote.weight(.semibold))
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.7)
      .frame(maxWidth: .infinity, minHeight: 44)
  }

  private func metricCard(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.footnote)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline.monospacedDigit())
        .foregroundStyle(.primary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(AppTheme.chipFill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(AppTheme.cardStroke, lineWidth: 1)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(value)
  }

  @ViewBuilder
  private func frequencyInputSection(for backend: SDRBackend) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(frequencyInputHint(for: backend))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      TextField(
        frequencyInputPlaceholder(for: backend),
        text: $inlineFrequencyInput,
        onEditingChanged: { isEditing in
          inlineFrequencyEditing = isEditing
          if isEditing {
            inlineFrequencyApplyTask?.cancel()
            inlineFrequencyInput = ""
            inlineFrequencyError = nil
          }
          if !isEditing {
            submitInlineFrequencyInput(for: backend)
          }
        }
      )
      .keyboardType(.decimalPad)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .textFieldStyle(.roundedBorder)
      .focused($isInlineFrequencyFocused)
      .accessibilityLabel(L10n.text("Frequency input"))
      .accessibilityHint(Text(frequencyInputHint(for: backend)))
      .submitLabel(.done)
      .onSubmit {
        submitInlineFrequencyInput(for: backend)
      }
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          FocusRetainingButton {
            submitInlineFrequencyInput(for: backend)
          } label: {
            Text(L10n.text("Apply"))
          }
        }
      }
      .onChange(of: inlineFrequencyInput) { _ in
        inlineFrequencyError = nil
        scheduleInlineFrequencyApply(for: backend)
      }

      if let inlineFrequencyError {
        Text(inlineFrequencyError)
          .foregroundStyle(.red)
          .font(.footnote)
          .accessibilityLabel(L10n.text("Frequency input error"))
          .accessibilityValue(inlineFrequencyError)
      }
    }
  }

  private func resetInlineFrequencyInput() {
    inlineFrequencyApplyTask?.cancel()
    inlineFrequencyInput = ""
    inlineFrequencyError = nil
    inlineFrequencyEditing = false
    isInlineFrequencyFocused = false
  }

  private func scheduleInlineFrequencyApply(for backend: SDRBackend) {
    guard inlineFrequencyEditing else { return }
    inlineFrequencyApplyTask?.cancel()
    inlineFrequencyApplyTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      if Task.isCancelled { return }
      guard shouldAttemptInlineFrequencyApply(inlineFrequencyInput, backend: backend) else { return }
      _ = applyInlineFrequencyInput(backend)
    }
  }

  private func submitInlineFrequencyInput(for backend: SDRBackend) {
    inlineFrequencyApplyTask?.cancel()
    let trimmed = inlineFrequencyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      resetInlineFrequencyInput()
      return
    }
    _ = applyInlineFrequencyInput(backend, endEditing: true)
    isInlineFrequencyFocused = false
  }

  @discardableResult
  private func applyInlineFrequencyInput(_ backend: SDRBackend, endEditing: Bool = false) -> Bool {
    if (backend == .openWebRX || backend == .kiwiSDR) && radioSession.isAwaitingInitialServerTuningSync {
      inlineFrequencyError = L10n.text("session.status.sync_tuning")
      return false
    }

    guard shouldAttemptInlineFrequencyApply(inlineFrequencyInput, backend: backend) else {
      return false
    }

    let parserContext = parserContext(for: backend)
    let inputProfile = frequencyInputProfile(for: backend)
    guard let frequencyHz = FrequencyInputParser.parseHz(
      from: inlineFrequencyInput,
      context: parserContext,
      preferredRangeHz: inputProfile.preferredRangeHz
    ) else {
      inlineFrequencyError = backend == .fmDxWebserver
        ? L10n.text("frequency_input.invalid_fm")
        : L10n.text("frequency_input.invalid_generic")
      return false
    }

    let range = frequencyRange(for: backend)
    guard range.contains(frequencyHz) else {
      inlineFrequencyError = backend == .fmDxWebserver
        ? L10n.text("frequency_input.fmdx_range")
        : L10n.text("frequency_input.invalid_generic")
      return false
    }

    let normalizedFrequencyHz = normalizeFrequencyHz(frequencyHz, for: backend)
    radioSession.setFrequencyHz(normalizedFrequencyHz)
    inlineFrequencyError = nil
    inlineFrequencyInput = ""

    if endEditing {
      inlineFrequencyEditing = false
    }

    return true
  }

  private func parserContext(for backend: SDRBackend) -> FrequencyInputParser.Context {
    switch backend {
    case .fmDxWebserver:
      return .fmBroadcast
    case .kiwiSDR:
      return .shortwave
    case .openWebRX:
      return .generic
    }
  }

  private func shouldAttemptInlineFrequencyApply(_ input: String, backend: SDRBackend) -> Bool {
    let normalized = input
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: " ", with: "")

    guard !normalized.isEmpty else { return false }
    if normalized.hasSuffix(".") || normalized.hasSuffix(",") {
      return false
    }

    if normalized.hasSuffix("mhz") || normalized.hasSuffix("khz") || normalized.hasSuffix("hz") {
      return true
    }

    let digitCount = normalized.filter(\.isNumber).count
    if backend == .fmDxWebserver {
      return digitCount >= 3
    }
    return digitCount >= 2
  }

  private func frequencyHz(fromMHz value: Double) -> Int {
    let hz = Int((value * 1_000_000.0).rounded())
    if profileStore.selectedProfile?.backend == .fmDxWebserver {
      let rounded = Int((Double(hz) / 1_000.0).rounded()) * 1_000
      return min(max(rounded, fmDxFrequencyRangeHz.lowerBound), fmDxFrequencyRangeHz.upperBound)
    }
    return hz
  }

  private func addQuickScanChannel(frequencyHz: Int) {
    let normalizedHz = normalizeFrequencyHz(frequencyHz, for: profileStore.selectedProfile?.backend)
    let id = "quick|\(normalizedHz)"
    guard quickScanChannels.contains(where: { $0.id == id }) == false else { return }

    let channel = ScanChannel(
      id: id,
      name: L10n.text("fmdx.af_scan_name", FrequencyFormatter.mhzText(fromHz: normalizedHz)),
      frequencyHz: normalizedHz,
      mode: .fm
    )
    quickScanChannels.append(channel)
    quickScanChannels.sort { $0.frequencyHz < $1.frequencyHz }
  }

  private func frequencyText(fromHz value: Int, backend: SDRBackend?) -> String {
    if backend == .fmDxWebserver {
      return FrequencyFormatter.fmDxMHzText(fromHz: value)
    }
    return FrequencyFormatter.mhzText(fromHz: value)
  }

  private func frequencyInputHint(for backend: SDRBackend?) -> String {
    guard let backend else {
      return L10n.text("frequency_input.hint_generic")
    }
    let inputProfile = frequencyInputProfile(for: backend)
    if let alternateExample = inputProfile.alternateExample {
      return L10n.text("frequency_input.dynamic_hint", inputProfile.primaryExample, alternateExample)
    }
    return L10n.text("frequency_input.dynamic_hint_single", inputProfile.primaryExample)
  }

  private func frequencyInputPlaceholder(for backend: SDRBackend?) -> String {
    guard let backend else {
      return L10n.text("frequency_input.placeholder_generic")
    }
    return frequencyInputProfile(for: backend).placeholder
  }

  private func frequencyRange(for backend: SDRBackend) -> ClosedRange<Int> {
    switch backend {
    case .fmDxWebserver:
      return fmDxFrequencyRangeHz
    case .kiwiSDR:
      return kiwiFrequencyRangeHz
    case .openWebRX:
      return defaultFrequencyRangeHz
    }
  }

  private func activeOpenWebRXBandName() -> String? {
    let frequency = radioSession.settings.frequencyHz
    return radioSession.openWebRXBandPlan.first(where: { $0.lowerBoundHz...$0.upperBoundHz ~= frequency })?.name
  }

  private func activeOpenWebRXBookmark() -> SDRServerBookmark? {
    let frequency = radioSession.settings.frequencyHz
    return radioSession.serverBookmarks.first(where: { $0.frequencyHz == frequency })
  }

  private func selectedOpenWebRXProfileName() -> String {
    let selectedID = radioSession.selectedOpenWebRXProfileID
    return radioSession.openWebRXProfiles.first(where: { $0.id == selectedID })?.name
      ?? radioSession.openWebRXProfiles.first?.name
      ?? ""
  }

  private func activeOpenWebRXBandEntry() -> SDRBandPlanEntry? {
    let frequency = radioSession.settings.frequencyHz
    return radioSession.openWebRXBandPlan.first(where: { $0.lowerBoundHz...$0.upperBoundHz ~= frequency })
  }

  private func openWebRXBookmarkSummary() -> String {
    if let activeBookmark = activeOpenWebRXBookmark() {
      return activeBookmark.name
    }
    return L10n.text("openwebrx.bookmarks_count", radioSession.serverBookmarks.count)
  }

  private func openWebRXBandPlanSummary() -> String {
    if let activeBand = activeOpenWebRXBandEntry() {
      return activeBand.name
    }
    return L10n.text("openwebrx.band_plan_count", radioSession.openWebRXBandPlan.count)
  }

  private func currentKiwiWaterfallPreset() -> KiwiWaterfallPreset {
    KiwiWaterfallPreset.matching(settings: radioSession.settings)
  }

  private func currentKiwiSignalPreset() -> KiwiSignalPreset {
    KiwiSignalPreset.matching(settings: radioSession.settings)
  }

  private func normalizeFrequencyHz(_ value: Int, for backend: SDRBackend?) -> Int {
    guard let backend else { return value }
    let range = frequencyRange(for: backend)
    return min(max(value, range.lowerBound), range.upperBound)
  }

  private func currentFMDXAntennaName() -> String {
    let selectedID = radioSession.selectedFMDXAntennaID
      ?? radioSession.fmdxCapabilities.antennas.first?.id
    return radioSession.fmdxCapabilities.antennas.first(where: { $0.id == selectedID })?.label
      ?? radioSession.fmdxCapabilities.antennas.first?.label
      ?? ""
  }

  private func currentFMDXBandwidthName() -> String {
    let selectedID = radioSession.selectedFMDXBandwidthID
      ?? radioSession.fmdxCapabilities.bandwidths.first?.id
    return radioSession.fmdxCapabilities.bandwidths.first(where: { $0.id == selectedID })?.label
      ?? radioSession.fmdxCapabilities.bandwidths.first?.label
      ?? ""
  }

  private func scanChannels(for profile: SDRConnectionProfile) -> [ScanChannel] {
    let channels: [ScanChannel]
    switch scanSource {
    case .serverBookmarks:
      channels = radioSession.serverBookmarks.map { bookmark in
        ScanChannel(
          id: "bookmark|\(bookmark.id)",
          name: bookmark.name,
          frequencyHz: bookmark.frequencyHz,
          mode: bookmark.modulation
        )
      }
    case .quickList:
      channels = quickScanChannels
    }

    guard profile.backend == .fmDxWebserver else {
      return channels
    }

    return normalizeFMDXScanChannels(channels)
  }

  private func normalizeFMDXScanChannels(_ channels: [ScanChannel]) -> [ScanChannel] {
    var normalized: [ScanChannel] = []
    normalized.reserveCapacity(channels.count)
    var seenFrequencies = Set<Int>()

    for channel in channels {
      let roundedHz = Int((Double(channel.frequencyHz) / 1_000.0).rounded()) * 1_000
      guard fmDxFrequencyRangeHz.contains(roundedHz) else { continue }
      guard seenFrequencies.insert(roundedHz).inserted else { continue }

      let trimmedName = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let displayName = trimmedName.isEmpty ? FrequencyFormatter.fmDxMHzText(fromHz: roundedHz) : trimmedName

      normalized.append(
        ScanChannel(
          id: "fmdx|\(roundedHz)",
          name: displayName,
          frequencyHz: roundedHz,
          mode: .fm
        )
      )
    }

    return normalized.sorted { $0.frequencyHz < $1.frequencyHz }
  }

  private func frequencyInputProfile(for backend: SDRBackend) -> FrequencyInputProfileSpec {
    switch backend {
    case .fmDxWebserver:
      return .init(
        preferredRangeHz: fmDxFrequencyRangeHz,
        primaryExample: "98.5",
        alternateExample: "985",
        placeholder: "98.5",
        maxFractionDigits: 3
      )

    case .kiwiSDR:
      return kiwiFrequencyInputProfile()

    case .openWebRX:
      return openWebRXFrequencyInputProfile()
    }
  }

  private func kiwiFrequencyInputProfile() -> FrequencyInputProfileSpec {
    let frequencyHz = radioSession.settings.frequencyHz

    switch frequencyHz {
    case ..<300_000:
      return .init(
        preferredRangeHz: 150_000...299_999,
        primaryExample: "198",
        alternateExample: "198000",
        placeholder: "198",
        maxFractionDigits: 0
      )

    case 300_000..<3_000_000:
      return .init(
        preferredRangeHz: 300_000...2_999_999,
        primaryExample: "999",
        alternateExample: "999000",
        placeholder: "999",
        maxFractionDigits: 0
      )

    case 3_400_000..<4_100_000:
      return .init(
        preferredRangeHz: 3_500_000...4_000_000,
        primaryExample: "3.650",
        alternateExample: "3650",
        placeholder: "3.650",
        maxFractionDigits: 3
      )

    case 5_700_000..<6_400_000:
      return .init(
        preferredRangeHz: 5_900_000...6_300_000,
        primaryExample: "6.070",
        alternateExample: "6070",
        placeholder: "6.070",
        maxFractionDigits: 3
      )

    case 6_900_000..<7_400_000:
      return .init(
        preferredRangeHz: 7_000_000...7_300_000,
        primaryExample: "7.050",
        alternateExample: "7050",
        placeholder: "7.050",
        maxFractionDigits: 3
      )

    case 13_900_000..<14_500_000:
      return .init(
        preferredRangeHz: 14_000_000...14_350_000,
        primaryExample: "14.074",
        alternateExample: "14074",
        placeholder: "14.074",
        maxFractionDigits: 3
      )

    case 18_000_000..<18_300_000:
      return .init(
        preferredRangeHz: 18_068_000...18_168_000,
        primaryExample: "18.100",
        alternateExample: "18100",
        placeholder: "18.100",
        maxFractionDigits: 3
      )

    case 24_700_000..<25_100_000:
      return .init(
        preferredRangeHz: 24_890_000...24_990_000,
        primaryExample: "24.940",
        alternateExample: "24940",
        placeholder: "24.940",
        maxFractionDigits: 3
      )

    default:
      return .init(
        preferredRangeHz: 28_000_000...29_700_000,
        primaryExample: "28.400",
        alternateExample: "28400",
        placeholder: "28.400",
        maxFractionDigits: 3
      )
    }
  }

  private func openWebRXFrequencyInputProfile() -> FrequencyInputProfileSpec {
    if let band = activeOpenWebRXBandEntry() {
      if let mappedProfile = mappedOpenWebRXInputProfile(forBandName: band.name) {
        return mappedProfile
      }
      if let suggestedFrequencyHz = band.frequencies.first?.frequencyHz {
        return inferredInputProfile(
          sampleFrequencyHz: suggestedFrequencyHz,
          preferredRangeHz: band.lowerBoundHz...band.upperBoundHz
        )
      }
      return inferredInputProfile(
        sampleFrequencyHz: band.centerFrequencyHz,
        preferredRangeHz: band.lowerBoundHz...band.upperBoundHz
      )
    }

    return inferredInputProfile(
      sampleFrequencyHz: radioSession.settings.frequencyHz,
      preferredRangeHz: inferredWidebandRange(for: radioSession.settings.frequencyHz)
    )
  }

  private func mappedOpenWebRXInputProfile(forBandName bandName: String) -> FrequencyInputProfileSpec? {
    let normalized = bandName.lowercased()

    if normalized.contains("70cm") || normalized.contains("pmr") {
      return vhfUhfInputProfile(
        preferredRangeHz: 430_000_000...470_000_000,
        exampleHz: 446_156_250
      )
    }

    if normalized.contains("2m") || normalized.contains("144") {
      return vhfUhfInputProfile(
        preferredRangeHz: 144_000_000...148_000_000,
        exampleHz: 144_950_250
      )
    }

    if normalized.contains("23cm") || normalized.contains("1296") {
      return vhfUhfInputProfile(
        preferredRangeHz: 1_240_000_000...1_300_000_000,
        exampleHz: 1_296_500_000
      )
    }

    if normalized.contains("6m") || normalized.contains("50 mhz") || normalized.contains("50mhz") {
      return inferredInputProfile(
        sampleFrequencyHz: 50_150_000,
        preferredRangeHz: 50_000_000...54_000_000
      )
    }

    if normalized.contains("4m") || normalized.contains("70 mhz") || normalized.contains("70mhz") {
      return inferredInputProfile(
        sampleFrequencyHz: 70_200_000,
        preferredRangeHz: 70_000_000...71_000_000
      )
    }

    if normalized.contains("air") {
      return inferredInputProfile(
        sampleFrequencyHz: 118_300_000,
        preferredRangeHz: 118_000_000...136_975_000
      )
    }

    if normalized.contains("cb") || normalized.contains("11m") {
      return inferredInputProfile(
        sampleFrequencyHz: 27_180_000,
        preferredRangeHz: 26_965_000...27_405_000
      )
    }

    if normalized.contains("10m") {
      return inferredInputProfile(
        sampleFrequencyHz: 28_400_000,
        preferredRangeHz: 28_000_000...29_700_000
      )
    }

    if normalized.contains("20m") {
      return inferredInputProfile(
        sampleFrequencyHz: 14_074_000,
        preferredRangeHz: 14_000_000...14_350_000
      )
    }

    if normalized.contains("fm") || normalized.contains("broadcast") {
      return .init(
        preferredRangeHz: 87_500_000...108_000_000,
        primaryExample: "98.5",
        alternateExample: "985",
        placeholder: "98.5",
        maxFractionDigits: 3
      )
    }

    return nil
  }

  private func inferredWidebandRange(for frequencyHz: Int) -> ClosedRange<Int> {
    switch frequencyHz {
    case 144_000_000...148_000_000:
      return 144_000_000...148_000_000
    case 430_000_000...470_000_000:
      return 430_000_000...470_000_000
    case 1_240_000_000...1_300_000_000:
      return 1_240_000_000...1_300_000_000
    case 118_000_000...136_975_000:
      return 118_000_000...136_975_000
    case 64_000_000...110_000_000:
      return 64_000_000...110_000_000
    case 300_000...2_999_999:
      return 300_000...2_999_999
    case 3_000_000...32_000_000:
      return 3_000_000...32_000_000
    default:
      return defaultFrequencyRangeHz
    }
  }

  private func inferredInputProfile(
    sampleFrequencyHz: Int,
    preferredRangeHz: ClosedRange<Int>
  ) -> FrequencyInputProfileSpec {
    if sampleFrequencyHz < 1_000_000 {
      let primaryExample = "\(Int((Double(sampleFrequencyHz) / 1_000.0).rounded()))"
      return .init(
        preferredRangeHz: preferredRangeHz,
        primaryExample: primaryExample,
        alternateExample: "\(sampleFrequencyHz)",
        placeholder: primaryExample,
        maxFractionDigits: 0
      )
    }

    let maxFractionDigits = sampleFrequencyHz >= 100_000_000 ? 5 : 3
    let primaryExample = dottedExampleText(fromHz: sampleFrequencyHz, maxFractionDigits: maxFractionDigits)
    return .init(
      preferredRangeHz: preferredRangeHz,
      primaryExample: primaryExample,
      alternateExample: compactExampleText(from: primaryExample),
      placeholder: primaryExample,
      maxFractionDigits: maxFractionDigits
    )
  }

  private func vhfUhfInputProfile(
    preferredRangeHz: ClosedRange<Int>,
    exampleHz: Int
  ) -> FrequencyInputProfileSpec {
    let primaryExample = dottedExampleText(fromHz: exampleHz, maxFractionDigits: 5)
    return .init(
      preferredRangeHz: preferredRangeHz,
      primaryExample: primaryExample,
      alternateExample: compactExampleText(from: primaryExample),
      placeholder: primaryExample,
      maxFractionDigits: 5
    )
  }

  private func dottedExampleText(fromHz value: Int, maxFractionDigits: Int) -> String {
    if value < 1_000_000 {
      return "\(Int((Double(value) / 1_000.0).rounded()))"
    }

    var raw = String(format: "%.\(maxFractionDigits)f", Double(value) / 1_000_000.0)
    while raw.contains(".") && raw.last == "0" {
      raw.removeLast()
    }
    if raw.last == "." {
      raw.removeLast()
    }

    guard let separatorIndex = raw.firstIndex(of: ".") else {
      return raw
    }

    let integerPart = String(raw[..<separatorIndex])
    let fractionPart = String(raw[raw.index(after: separatorIndex)...])
    guard fractionPart.count > 3 else { return raw }

    let splitIndex = fractionPart.index(fractionPart.startIndex, offsetBy: 3)
    let leading = String(fractionPart[..<splitIndex])
    let trailing = String(fractionPart[splitIndex...])
    guard !trailing.isEmpty else { return raw }
    return "\(integerPart).\(leading).\(trailing)"
  }

  private func compactExampleText(from dottedExample: String) -> String {
    dottedExample
      .replacingOccurrences(of: ".", with: "")
      .replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: " ", with: "")
  }

}

private struct FrequencyInputProfileSpec {
  let preferredRangeHz: ClosedRange<Int>
  let primaryExample: String
  let alternateExample: String?
  let placeholder: String
  let maxFractionDigits: Int
}

struct SelectionListOption: Identifiable, Hashable {
  let id: String
  let title: String
  let detail: String?
}

struct SelectionListView: View {
  let title: String
  let options: [SelectionListOption]
  let selectedID: String
  let onSelect: (String) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      Section {
        ForEach(options) { option in
          Button {
            onSelect(option.id)
            dismiss()
          } label: {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                  .foregroundStyle(.primary)

                if let detail = option.detail, !detail.isEmpty {
                  Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }

              Spacer()

              if option.id == selectedID {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      } header: {
        AppSectionHeader(title: title)
      }
      .appSectionStyle()
    }
    .voiceOverStable()
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .appScreenBackground()
  }
}

private struct OpenWebRXBandDetailView: View {
  let band: SDRBandPlanEntry
  let onTuneBandCenter: () -> Void
  let onTuneFrequency: (SDRBandFrequency) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      Section {
        LabeledContent(L10n.text("openwebrx.band_plan_section"), value: band.rangeText)

        Button {
          onTuneBandCenter()
          dismiss()
        } label: {
          Label(L10n.text("Tune band center"), systemImage: "scope")
        }
      } header: {
        AppSectionHeader(title: L10n.text("openwebrx.band_plan_section"))
      }
      .appSectionStyle()

      if !band.frequencies.isEmpty {
        Section {
          ForEach(band.frequencies) { item in
            Button {
              onTuneFrequency(item)
              dismiss()
            } label: {
              HStack {
                Text(item.name)
                Spacer()
                Text(FrequencyFormatter.mhzText(fromHz: item.frequencyHz))
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          AppSectionHeader(title: L10n.text("openwebrx.band_frequencies"))
        }
        .appSectionStyle()
      }
    }
    .voiceOverStable()
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle(band.name)
    .navigationBarTitleDisplayMode(.inline)
    .appScreenBackground()
  }
}

private struct OpenWebRXBookmarksView: View {
  let bookmarks: [SDRServerBookmark]
  let activeFrequencyHz: Int
  let onSelect: (SDRServerBookmark) -> Void

  @State private var searchText = ""
  @State private var sort: OpenWebRXBookmarkSort = .frequency
  @Environment(\.dismiss) private var dismiss

  private var filteredBookmarks: [SDRServerBookmark] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = bookmarks.filter { bookmark in
      guard !query.isEmpty else { return true }
      let tokens = [
        bookmark.name,
        FrequencyFormatter.mhzText(fromHz: bookmark.frequencyHz),
        bookmark.modulation?.displayName ?? "",
        bookmark.source
      ]
      return tokens.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    switch sort {
    case .frequency:
      return filtered.sorted { lhs, rhs in
        if lhs.frequencyHz != rhs.frequencyHz {
          return lhs.frequencyHz < rhs.frequencyHz
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
    case .name:
      return filtered.sorted { lhs, rhs in
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame {
          return comparison == .orderedAscending
        }
        return lhs.frequencyHz < rhs.frequencyHz
      }
    }
  }

  var body: some View {
    List {
      Section {
        NavigationLink {
          SelectionListView(
            title: L10n.text("openwebrx.bookmarks.sort"),
            options: OpenWebRXBookmarkSort.allCases.map {
              SelectionListOption(id: $0.rawValue, title: $0.localizedTitle, detail: nil)
            },
            selectedID: sort.rawValue
          ) { value in
            if let sort = OpenWebRXBookmarkSort(rawValue: value) {
              self.sort = sort
            }
          }
        } label: {
          LabeledContent(
            L10n.text("openwebrx.bookmarks.sort"),
            value: sort.localizedTitle
          )
        }
      } header: {
        AppSectionHeader(title: L10n.text("openwebrx.bookmarks.sort"))
      }
      .appSectionStyle()

      if filteredBookmarks.isEmpty {
        Section {
          Text(L10n.text("openwebrx.bookmarks.empty_filtered"))
            .foregroundStyle(.secondary)
        }
        .appSectionStyle()
      } else {
        Section {
          ForEach(filteredBookmarks) { bookmark in
            Button {
              onSelect(bookmark)
              dismiss()
            } label: {
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(bookmark.name)
                  Text(FrequencyFormatter.mhzText(fromHz: bookmark.frequencyHz))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if bookmark.frequencyHz == activeFrequencyHz {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        } header: {
          AppSectionHeader(title: L10n.text("openwebrx.bookmarks_section"))
        }
        .appSectionStyle()
      }
    }
    .voiceOverStable()
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle(L10n.text("openwebrx.bookmarks_section"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: L10n.text("openwebrx.bookmarks.search_prompt"))
    .appScreenBackground()
  }
}

private struct OpenWebRXBandPlanListView: View {
  let bands: [SDRBandPlanEntry]
  let activeFrequencyHz: Int
  let onTuneBandCenter: (SDRBandPlanEntry) -> Void
  let onTuneFrequency: (SDRBandPlanEntry, SDRBandFrequency) -> Void

  @State private var searchText = ""

  private var filteredBands: [SDRBandPlanEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = bands.filter { band in
      guard !query.isEmpty else { return true }
      let rangeTokens = [
        band.name,
        band.rangeText,
        FrequencyFormatter.mhzText(fromHz: band.lowerBoundHz),
        FrequencyFormatter.mhzText(fromHz: band.upperBoundHz)
      ]
      if rangeTokens.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
        return true
      }
      return band.frequencies.contains(where: {
        $0.name.localizedCaseInsensitiveContains(query)
          || FrequencyFormatter.mhzText(fromHz: $0.frequencyHz).localizedCaseInsensitiveContains(query)
      })
    }

    return filtered.sorted { lhs, rhs in
      if lhs.lowerBoundHz != rhs.lowerBoundHz {
        return lhs.lowerBoundHz < rhs.lowerBoundHz
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  var body: some View {
    List {
      if filteredBands.isEmpty {
        Section {
          Text(L10n.text("openwebrx.band_plan.empty_filtered"))
            .foregroundStyle(.secondary)
        }
        .appSectionStyle()
      } else {
        Section {
          ForEach(filteredBands) { band in
            NavigationLink {
              OpenWebRXBandDetailView(
                band: band,
                onTuneBandCenter: {
                  onTuneBandCenter(band)
                },
                onTuneFrequency: { item in
                  onTuneFrequency(band, item)
                }
              )
            } label: {
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(band.name)
                  Text(band.rangeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if (band.lowerBoundHz...band.upperBoundHz).contains(activeFrequencyHz) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                }
              }
            }
          }
        } header: {
          AppSectionHeader(title: L10n.text("openwebrx.band_plan_section"))
        }
        .appSectionStyle()
      }
    }
    .voiceOverStable()
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle(L10n.text("openwebrx.band_plan_section"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: L10n.text("openwebrx.band_plan.search_prompt"))
    .appScreenBackground()
  }
}

private struct FMDXRDSDetailsView: View {
  let telemetry: FMDXTelemetry
  @Binding var showRdsErrorCounters: Bool

  var body: some View {
    List {
      Section {
        if let pty = telemetry.pty {
          LabeledContent("PTY", value: ptyDisplayText(pty: pty, rbds: telemetry.rbds))
        }
        if let tp = telemetry.tp {
          LabeledContent("TP", value: tp == 1 ? L10n.text("common.yes") : L10n.text("common.no"))
        }
        if let ta = telemetry.ta {
          LabeledContent("TA", value: ta == 1 ? L10n.text("common.yes") : L10n.text("common.no"))
        }
        if let ms = telemetry.ms {
          LabeledContent("MS", value: msDisplayText(ms))
        }
        if let ecc = telemetry.ecc {
          LabeledContent("ECC", value: String(format: "0x%02X", ecc))
        }
        if let rbds = telemetry.rbds {
          LabeledContent("RBDS", value: rbds ? L10n.text("common.yes") : L10n.text("common.no"))
        }
        if let countryISO = telemetry.countryISO, !countryISO.isEmpty, countryISO != "UN" {
          LabeledContent("ISO", value: countryISO)
        }
        if let agc = telemetry.agc, !agc.isEmpty {
          LabeledContent("AGC", value: agc)
        }

        Toggle(
          L10n.text("fmdx.show_rds_errors"),
          isOn: $showRdsErrorCounters
        )

        if showRdsErrorCounters {
          if let errors = telemetry.psErrors, !errors.isEmpty {
            Text(L10n.text("fmdx.ps_errors", errors))
              .font(.footnote)
          }
          if let errors = telemetry.rt0Errors, !errors.isEmpty {
            Text(L10n.text("fmdx.rt0_errors", errors))
              .font(.footnote)
          }
          if let errors = telemetry.rt1Errors, !errors.isEmpty {
            Text(L10n.text("fmdx.rt1_errors", errors))
              .font(.footnote)
          }
        }
      } header: {
        AppSectionHeader(title: L10n.text("fmdx.live.more_details"))
      }
      .appSectionStyle()

      if let tx = telemetry.txInfo {
        Section {
          if let station = tx.station, !station.isEmpty {
            LabeledContent(L10n.text("TX"), value: station)
          }
          if let city = tx.city, !city.isEmpty {
            LabeledContent(L10n.text("City"), value: city)
          }
          if let itu = tx.itu, !itu.isEmpty {
            LabeledContent("ITU", value: itu)
          }
          if let distance = tx.distanceKm, !distance.isEmpty {
            LabeledContent(L10n.text("fmdx.field.distance"), value: "\(distance) km")
          }
          if let azimuth = tx.azimuthDeg, !azimuth.isEmpty {
            LabeledContent(L10n.text("fmdx.field.azimuth"), value: "\(azimuth) deg")
          }
          if let erp = tx.erpKW, !erp.isEmpty {
            LabeledContent("ERP", value: "\(erp) kW")
          }
          if let polarization = tx.polarization, !polarization.isEmpty {
            LabeledContent(L10n.text("fmdx.field.polarization"), value: polarization)
          }
        } header: {
          AppSectionHeader(title: L10n.text("TX"))
        }
        .appSectionStyle()
      }
    }
    .voiceOverStable()
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle(L10n.text("fmdx.live.more_details"))
    .navigationBarTitleDisplayMode(.inline)
    .appScreenBackground()
  }

  private func msDisplayText(_ ms: Int) -> String {
    switch ms {
    case 1:
      return L10n.text("common.yes")
    case 0:
      return L10n.text("common.no")
    default:
      return L10n.text("common.not_selected")
    }
  }

  private func ptyDisplayText(pty: Int, rbds: Bool?) -> String {
    let labelsEU = [
      "No PTY", "News", "Current Affairs", "Info", "Sport", "Education", "Drama", "Culture",
      "Science", "Varied", "Pop Music", "Rock Music", "Easy Listening", "Light Classical",
      "Serious Classical", "Other Music", "Weather", "Finance", "Children's", "Social Affairs",
      "Religion", "Phone-in", "Travel", "Leisure", "Jazz Music", "Country Music", "National Music",
      "Oldies Music", "Folk Music", "Documentary", "Alarm Test", "Alarm"
    ]
    let labelsUS = [
      "No PTY", "News", "Information", "Sports", "Talk", "Rock", "Classic Rock", "Adult Hits",
      "Soft Rock", "Top 40", "Country", "Oldies", "Soft Music", "Nostalgia", "Jazz", "Classical",
      "Rhythm and Blues", "Soft R&B", "Language", "Religious Music", "Religious Talk", "Personality",
      "Public", "College", "Spanish Talk", "Spanish Music", "Hip Hop", "", "", "Weather",
      "Emergency Test", "Emergency"
    ]

    let table = (rbds ?? false) ? labelsUS : labelsEU
    if pty >= 0 && pty < table.count {
      let label = table[pty].trimmingCharacters(in: .whitespacesAndNewlines)
      if !label.isEmpty {
        return "\(pty) (\(label))"
      }
    }
    return "\(pty)"
  }
}

struct WaterfallStripView: View {
  let bins: [UInt8]

  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        guard !bins.isEmpty else { return }
        let count = bins.count
        let stripeWidth = max(1, size.width / CGFloat(count))

        for (index, value) in bins.enumerated() {
          let normalized = Double(value) / 255.0
          let color = Color(
            hue: 0.65 - (0.65 * normalized),
            saturation: 0.9,
            brightness: 0.25 + (0.75 * normalized)
          )
          let x = CGFloat(index) * stripeWidth
          let rect = CGRect(x: x, y: 0, width: stripeWidth + 0.5, height: size.height)
          context.fill(Path(rect), with: .color(color))
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
}
