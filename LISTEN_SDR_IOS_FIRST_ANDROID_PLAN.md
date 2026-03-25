# Listen SDR iOS-first Android Plan

Data: 2026-03-23

## Cel

Docelowy model:

- iOS pozostaje zrodlem prawdy
- Android bierze logike i tyle UI, ile realnie da sie bezpiecznie wspoldzielic z iOS
- nie zmieniamy projektu na JS-first

## Decyzja

Nie rekomenduje React Native jako glownej drogi dla Listen SDR.

Powod:

- React Native ustawia wspolny kod aplikacji w React/JS/TS, a nie w Swift
- przy takiej aplikacji i tak trzeba utrzymywac duzo kodu natywnego po obu stronach
- audio, recording, remote commands, accessibility i systemowe integracje juz teraz sa mocno natywne
- dostalibysmy trzeci layer do utrzymania: Swift + JS + Android native

Najblizszy Twojemu wymaganiu model to iOS-first z warstwa wspolna w Swift.

## Co sprawdzilem

Stan repo:

- warstwa Expo/React Native istnieje tylko jako prosty starter: `App.tsx`, `package.json`, `app.json`
- realna aplikacja siedzi w `native-ios/`
- obecny iOS ma 54 pliki Swift w `native-ios/ListenSDR/Sources`
- najciezsze moduly:
  - `RadioSessionViewModel.swift`
  - `SDRBackendClient.swift`
  - `AudioOutputEngine.swift`

Silne zaleznosci Apple-only w obecnym iOS:

- SwiftUI
- UIKit
- AVFoundation / AVFAudio / AVAudioSession / AVAudioEngine
- MediaPlayer / MPRemoteCommandCenter
- UserNotifications
- UIAccessibility / custom rotors / announcements
- AppIntents / iOS shortcuts

To oznacza, ze pelna automatyczna migracja "tak jak stoi" nie bedzie realistyczna.

## Wniosek techniczny

Najrozsadniejszy kierunek:

1. wyciagnac wspolny rdzen Swift z obecnego iOS
2. zostawic integracje systemowe jako adaptery platformowe
3. Android budowac z iOS-owego kodu Swift, ale etapami
4. traktowac Skip jako kandydat do pilota, nie jako slepy rewrite wszystkiego naraz

## Ocena opcji

### Opcja A: React Native

Status: nie polecam

- zrodlem prawdy stalby sie JS/TS
- musielibysmy przepisywac UI i przepinac logike do RN bridge
- audio SDR i systemowe integracje dalej wymagalyby natywnych modulow
- duzy koszt, malo zysku dla tego typu aplikacji

### Opcja B: Skip / Swift-first Android

Status: najlepszy kandydat do sprawdzenia

- pozwala traktowac Swift jako wspolny jezyk
- na iOS kod zostaje natywny
- na Androidzie mozna przenosic Swift i czesc SwiftUI do natywnego Kotlin/Compose
- nadal trzeba zaakceptowac ograniczenia i pisac code paths platformowe tam, gdzie trzeba

### Opcja C: reczny Android natywny, ale z rdzeniem dzielonym

Status: plan awaryjny i bardzo realny

- wspoldzielimy tylko rdzen Swift i testy
- Android UI i audio beda natywne
- mniejsza magia, wieksza przewidywalnosc

## Podzial obecnego kodu

### 1. Kandydaci do wspolnego rdzenia Swift juz teraz

Te pliki sa w duzej mierze logika domenowa lub modele:

- `SDRBackend.swift`
- `SDRConnectionProfile.swift`
- `DemodulationMode.swift`
- `BackendTelemetry.swift`
- `BandTuningProfile.swift`
- `FrequencyFormatter.swift`
- `FrequencyInputParser.swift`
- `FMDXBandScanner.swift`
- `FMDXPresetScriptParser.swift`
- `KiwiNoiseProcessing.swift`
- `KiwiWaterfallProcessing.swift`
- `KiwiWaterfallViewport.swift`
- `ReceiverIdentity.swift`
- duza czesc `ReceiverLinkImport.swift`
- duza czesc `ReceiverDirectory.swift`
- duza czesc `RadioSessionSettings.swift`
- `AudioDecoders.swift`
- `AudioPCMUtilities.swift`

To jest najlepszy material na pierwszy wspolny package/modul.

### 2. Kandydaci do wspoldzielenia po refaktorze

Te rzeczy sa wartosciowe, ale obecnie sa sklejone z iOS:

- `SDRBackendClient.swift`
  - trzeba oddzielic transport/protokoly/parsowanie od audio session i playera
- `RadioSessionViewModel.swift`
  - trzeba oddzielic reducer sesji, komendy i stan od SwiftUI/ObservableObject
- `ReceiverDirectory.swift`
  - trzeba oddzielic modele/parsowanie/filtrowanie od warstwy service/view model
- `ProfileStore.swift`
- `FavoritesStore.swift`
- `ListeningHistoryStore.swift`
- `FrequencyPresetStore.swift`
- `ReceiverDataCache.swift`
- `AudioRecordingStore.swift`

Te pliki powinny docelowo przejsc na:

- czysta logike domenowa
- storage abstractions
- platform adapters

### 3. Rzeczy, ktore musza zostac natywne per platforma

Tego bym nie probowal wspoldzielic na starcie:

- `AudioOutputEngine.swift`
- `AppAccessibility.swift`
- `SystemRemoteCommandController.swift`
- `NowPlayingMetadataController.swift`
- `VoiceOverRotorControl.swift`
- `DirectoryChangeNotificationService.swift`
- `ListenSDRAppShortcuts.swift`
- `ShareSheet.swift`
- wszystkie SwiftUI view:
  - `ContentView.swift`
  - `ReceiverView.swift`
  - `SettingsView.swift`
  - `RadiosView.swift`
  - `ProfileEditorView.swift`
  - `RecordingsView.swift`
  - `DiagnosticsView.swift`
  - `ReceiverDirectoryView.swift`
  - `ImportReceiverLinkView.swift`

Tu Android potrzebuje swoich odpowiednikow:

- audio output / media session
- accessibility announcements i focus
- share intents
- notifications
- shortcuts / widgets / watch / itp.

## Docelowa architektura

Proponowany podzial:

### A. Core Swift

Nowy modul, np.:

- `shared/ListenSDRCore`

Zawiera:

- modele domenowe
- parsery i formatery
- reguly strojenia
- backend-neutral telemetry
- logike skanera
- logike importu i normalizacji linkow
- reducer stanu sesji

Nie zawiera:

- SwiftUI
- UIKit
- AVFoundation
- MediaPlayer
- UserNotifications

### B. Platform Adapters

Interfejsy/protokoly dla:

- audio playback
- recording
- remote commands
- accessibility announcements
- notifications
- persistence
- network transport, jesli trzeba rozdzielic per platforma

Przyklad:

- `AudioPlaybackAdapter`
- `RecordingAdapter`
- `RemoteCommandsAdapter`
- `AccessibilityAdapter`
- `SessionSettingsStore`

### C. iOS App Shell

iOS zostaje glownym klientem i dalej uruchamia calosc natywnie.

Jego rola:

- SwiftUI
- AVAudioSession / AVAudioEngine
- MPRemoteCommandCenter
- VoiceOver rotors
- iOS-specific UX

### D. Android App Shell

Na poczatku:

- natywny Android shell
- wspolny Core Swift pod spodem
- Androidowe adaptery audio/systemowe

Potem:

- pilot z czesciowym wspoldzieleniem UI przez Skip tam, gdzie to sie oplaca

## Kolejnosc migracji

### Etap 0: porzadek architektoniczny na iOS

Cel:

- zmniejszyc coupling zanim dotkniemy Androida

Zadania:

- rozbic `RadioSessionViewModel.swift`
- rozbic `SDRBackendClient.swift`
- oddzielic storage od modeli
- oddzielic transport backendow od odtwarzania audio

### Etap 1: pierwszy wspolny rdzen

Przeniesc do `ListenSDRCore`:

- profile i backend models
- settings models
- parsery / formatery
- receiver identity / import
- scanner logic
- waterfall math / decoders

Warunek wyjscia:

- te rzeczy buduja sie i testuja poza app targetem iOS

### Etap 2: session core

Wydzielic:

- session state
- commands
- reducers
- pure business rules

Zostawic poza core:

- SwiftUI bindings
- ObservableObject glue
- Apple accessibility and media hooks

### Etap 3: Android spike

Najpierw nie ruszac audio live i nie ruszac calego receiver screen.

Spike powinien obejmowac:

- profile list
- radios directory
- search/filter/import
- settings models
- frequency parser/formatter

To pozwoli sprawdzic:

- ile Swift kodu realnie przechodzi
- gdzie sa granice UI
- czy Skip daje sensowna ergonomie

### Etap 4: audio and session bridge

Dopiero po udanym spike:

- Android media session
- Android audio focus
- Android recording path
- Android accessibility announcements
- Android-specific remote actions

## Pierwszy konkretny pilot

Nie zaczynalbym od `ReceiverView`.

Najlepszy pierwszy pilot:

- `ReceiverDirectory`
- `ReceiverLinkImport`
- `RadioSessionSettings`
- `FrequencyInputParser`
- `FrequencyFormatter`
- `SDRConnectionProfile`

Powod:

- wysoki zwrot
- malo Apple-only API
- duzo testowalnej logiki
- malo ryzyka audio/system

## Ryzyka

Najwieksze:

- `RadioSessionViewModel` jest obecnie za duzy i za bardzo miesza UI ze stanem sesji
- `SDRBackendClient` miesza protokoly backendow z audio i session lifecycle
- ciezkie funkcje iOS accessibility nie maja prostego 1:1 odpowiednika na Androidzie
- live audio i background/media control beda wymagaly natywnych adapterow niezaleznie od frameworka

## Rekomendacja wykonawcza

Robic to etapowo:

1. najpierw wydzielenie `ListenSDRCore`
2. potem pilot Android dla katalogu / importu / ustawien
3. dopiero potem decyzja, ile UI warto przepuscic przez Skip

Nie robic teraz:

- pelnego rewrite do React Native
- pelnego rewrite UI na Android od razu
- przenoszenia audio engine bez wczesniejszego wydzielenia core

## Zrodla zewnetrzne sprawdzone przy tej decyzji

- React Native Getting Started: https://reactnative.dev/docs/getting-started
- React Native Turbo Native Modules: https://reactnative.dev/docs/turbo-native-modules-introduction
- React Native platform-specific code: https://reactnative.dev/docs/platform-specific-code.html
- Skip docs overview: https://skip.tools/docs/
- Skip app development: https://skip.tools/docs/app-development/
- Skip UI support: https://skip.tools/docs/modules/skip-ui/
- Skip platform customization: https://skip.tools/docs/platformcustomization/
- Skip model layer: https://skip.tools/docs/modules/skip-model/

## Nastepny krok

Najbardziej praktyczny nastepny ruch:

- utworzyc szkic `ListenSDRCore`
- przeniesc do niego pierwszy pakiet plikow low-risk
- podpiac testy do tego rdzenia

Od tego momentu Android mozna zaczac budowac z iOS-owego kodu bez zgadywania.
