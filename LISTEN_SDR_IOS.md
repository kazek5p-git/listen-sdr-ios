# Listen SDR iOS

## To jest ten projekt

`Listen SDR iOS` to natywna aplikacja iPhone/iOS rozwijana w repo:

- `C:\Users\Kazek\Documents\iphone-live-starter`

Kanoniczna aplikacja produktu jest tutaj:

- `native-ios/ListenSDR`
- `native-ios/ListenSDR.xcodeproj`
- `native-ios/project.yml`

Warstwa Expo/React w katalogu glownym nie jest glowna aplikacja produktu. `App.tsx` pelni tylko role prostego placeholdera/live preview. Zrodlem prawdy dla produktu jest `native-ios/`.

## Zrodla odzyskanej historii

Przeszukane zostaly lokalne sesje Codex, odzyskane sesje i lokalne bazy stanu. Potwierdzone materialy powiazane z Listen SDR na iPhone:

1. Odzyskana sesja:
   - `C:\Users\Kazek\.codex\recovered-sessions\recovered-session-20260320-153350-019d00f5-a6b6-7480-aaa2-de9812c34d23.md`
   - thread id: `019d00f5-a6b6-7480-aaa2-de9812c34d23`
   - tytul zapisany w historii: `Listen sdr na android.`
   - mimo tytulu sesja realnie wchodzila w kod iOS `native-ios/ListenSDR/Sources` i analizowala parytet funkcji

2. Sesja kontynuacyjna:
   - `C:\Users\Kazek\.codex\sessions\2026\03\21\rollout-2026-03-21T10-42-36-019d0fc6-7006-7ad0-ac24-b9f02f791492.jsonl`
   - thread id: `019d0fc6-7006-7ad0-ac24-b9f02f791492`
   - byla oparta o powyzszy material odzyskany

3. Bazy stanu potwierdzajace slady:
   - `C:\Users\Kazek\.codex\state_5.sqlite`
   - `C:\Users\Kazek\.codex\logs_1.sqlite`
   - `C:\Users\Kazek\.codex\history.jsonl`

Na ten moment nie zostaly znalezione inne odrebne sesje lokalne, ktore zawieralyby dodatkowy, unikalny material o projekcie Listen SDR na iPhone poza powyzszym ciagiem i biezacym repo.

## Potwierdzony stan projektu

Aktualne metadane z `native-ios/project.yml`:

- app name: `Listen SDR`
- bundle id: `com.kazek.sdr`
- iOS deployment target: `16.0`
- marketing version: `1.0.1`
- build: `66`
- Swift: `5.10`

Repo lokalnie wyglada na czyste roboczo w zakresie obecnego stanu glowy projektu. W historii sa starsze commity z wyzszymi buildami, ale biezacym punktem odniesienia w repo jest nadal `1.0.1 (66)`.

## Architektura

To jest natywna aplikacja SwiftUI.

Glowny punkt wejscia:

- `native-ios/ListenSDR/Sources/ListenSDRApp.swift`

Najwazniejsze warstwy:

- `ContentView.swift`
  - glowny `TabView` aplikacji
  - zakladki: `Receiver`, `Radios`, `Settings`
  - startup i auto-connect do wybranego profilu

- `RadioSessionViewModel.swift`
  - glowna orkiestracja sesji radia
  - laczenie, przelaczanie backendow, restore sesji, scanner, audio, telemetry, integracje FM-DX

- `RadioSessionSettings.swift`
  - centralny model ustawien sesji, strojenia, audio, historii, skanerow i dostepnosci

- `ReceiverView.swift`
  - glowny ekran odbiornika
  - sterowanie sesja, widoki zalezne od backendu, wyniki skanowania, RDS, waterfall, bookmarki

- `RadiosView.swift`
  - profile odbiornikow, ulubione, historia, import linku, katalog odbiornikow

- `SettingsView.swift`
  - ustawienia aplikacji i sesji, diagnostyka, feedback, szybkie akcje

## Obslugiwane backendy

Backendy zdefiniowane w `SDRBackend.swift`:

- `KiwiSDR`
- `OpenWebRX`
- `FM-DX Webserver`

Domyslne porty:

- `8073` dla KiwiSDR i OpenWebRX
- `8080` dla FM-DX Webserver

## Potwierdzone funkcje

### Odbior i sesja

- laczenie do zapisanych profili
- automatyczne przywracanie ostatniej sesji
- zapamietywanie odbiornika i czestotliwosci
- strojenie z wieloma krokami od bardzo malych do szerokich
- ulubione czestotliwosci
- import odbiornika z linku

### FM-DX

- natywna obsluga FM-DX Webserver
- presety i logika zalezna od FM-DX
- skaner pasma z profilami predkosci
- wyniki skanowania z dodatkowymi metadanymi
- szczegoly RDS, w tym PS i RT
- zapisywanie wynikow skanera FM-DX

### KiwiSDR i OpenWebRX

- obsluga waterfall i sterowania specyficznego dla KiwiSDR
- bookmarki i band plan dla OpenWebRX
- wspolny model polaczenia i profili

### Radios / katalog odbiornikow

- lista profili odbiornikow
- tworzenie, edycja i usuwanie wpisow
- katalog odbiornikow z odswiezaniem i filtrami
- import wpisu z katalogu do lokalnych profili
- akcja otwarcia strony odbiornika

### Historia, nagrania i diagnostyka

- historia sluchania i ostatnich odbiornikow
- ostatnie czestotliwosci
- nagrywanie audio
- eksport i czyszczenie diagnostyki
- formularz zgloszenia bledu lub sugestii z poziomu aplikacji

### Dostepnosc i UX

- ulepszenia VoiceOver
- opcje oglaszania RDS / informacji glosowych
- sekcje ustawien dotyczace historii, audio, skanerow i dostepnosci

## Nagrania i trwale dane

Istotne magazyny danych:

- `ListeningHistoryStore.swift`
  - ostatni odbiornicy
  - ostatnie odsluchy
  - ostatnie czestotliwosci
  - zapis w `UserDefaults`

- `AudioRecordingStore.swift`
  - nagrania `WAV` i `MP3`
  - FM-DX zapisuje do `MP3`
  - pozostale backendy zapisuja do `WAV`
  - indeks w `recordings-index.json`

- `RecordingStore`
  - lista, start, stop i usuwanie nagran

## Build, instalacja, release

Projekt jest definiowany przez XcodeGen:

- `native-ios/project.yml`

Wazne skrypty lokalne:

- `scripts/Build-And-Install-ListenSDR.ps1`
- `scripts/Build-ListenSDR-RemoteUnsigned.ps1`
- `scripts/Run-ListenSDR-TestFlightEndToEnd.ps1`
- `scripts/Publish-ListenSDR-TestFlightMetadata.ps1`
- `scripts/Test-ListenSDR-TestFlightPreflight.ps1`

Na pulpicie istnieje wrapper:

- `C:\Users\Kazek\Desktop\Listen SDR - build i instalacja.bat`

Build unsigned jest kierowany na zdalnego Maca `mac_axela`.

Materialy release/TestFlight znalezione lokalnie:

- `release/testflight/1.0.1-build-66`

Z zapisanych notatek TestFlight wynika, ze testowane byly miedzy innymi:

- stabilnosc polaczenia
- plynnosc audio
- zachowanie skanera w FM-DX, KiwiSDR i OpenWebRX
- przywracanie historii sluchania
- recall odbiornika i czestotliwosci
- zwijane sekcje UI
- poprawki VoiceOver
- tlumaczenia
- katalog odbiornikow
- formularz bug/suggestion w aplikacji

## Co zostalo po pracach przed drugim uploadem TestFlight

To jest najwazniejszy wniosek z przeszukania lokalnej historii:

- pelne lokalne logi rozmow zachowane na dysku zaczynaja sie dopiero od `2026-03-20`
- nie mam lokalnie calej oryginalnej rozmowy z okresu `2026-03-07` do `2026-03-18`, kiedy powstawal szybki pipeline TestFlight
- sama praca nie wyglada jednak na utracona, bo jej efekt jest utrwalony w repo, commitach, README i notatkach release

Najwazniejszy zachowany ciag zmian pod TestFlight:

- `2026-03-07` commit `7eff33e` - signed native build i opcjonalny upload do TestFlight w GitHub Actions
- `2026-03-11` commit `32c1ee3` - helpery App Store Connect i setup TestFlight
- `2026-03-11` commit `b8eedd3` - sync na zdalnego Maca i helpery do buildow TestFlight
- `2026-03-11` commit `9ad7e04` - zautomatyzowany zdalny pipeline TestFlight na `mac_axela`
- `2026-03-11` commit `9013e2f` - checker statusu builda TestFlight
- `2026-03-11` commit `9c398c8` - end-to-end polling do stanu przetworzenia builda
- `2026-03-18` commit `4051682` - przygotowanie builda `1.0.1 (66)`
- `2026-03-18` commit `95b2796` - poprawka wrappera pod login signing
- `2026-03-18` commit `4659c3c` - automatyzacja publikacji metadanych TestFlight
- `2026-03-18` commit `dac28b0` - preflight i dry-run guardy przed publikacja

Praktyczny wniosek:

- wyglada na to, ze straciles glownie stary zapis rozmowy, a nie sam efekt pracy
- szybki pipeline do TestFlight nadal istnieje i jest zachowany w kodzie
- kanonicznym wejsciem do szybkiego uploadu jest `scripts/Run-ListenSDR-TestFlightEndToEnd.ps1`
- build `66` ma zachowane notatki w `release/testflight/1.0.1-build-66`

Powiazane skrypty tego flow:

- `scripts/Run-ListenSDR-TestFlightEndToEnd.ps1`
- `scripts/Run-ListenSDR-RemoteTestFlight.ps1`
- `scripts/Test-ListenSDR-TestFlightPreflight.ps1`
- `scripts/Publish-ListenSDR-TestFlightMetadata.ps1`
- `scripts/New-ListenSDR-TestFlightReleaseNotes.ps1`

## Diagnostyka i feedback

Widoki i integracje:

- `DiagnosticsView.swift`
- `ListenSDRFeedbackFormView.swift`
- `ListenSDRFeedbackSender.swift`

Potwierdzone endpointy:

- `https://kazpar.pl/listen-sdr-feedback/api/feedback`
- `https://kazpar.pl/listen-sdr-feedback/healthz`

## Testy obecne w repo

Testy iOS znalezione w `native-ios/ListenSDRTests`:

- `AudioPCMUtilitiesTests.swift`
- `DemodulationModeTests.swift`
- `FMDXBandScannerTests.swift`
- `FMDXCapabilitiesTests.swift`
- `FMDXPresetScriptParserTests.swift`
- `FMDXStationListResolverTests.swift`
- `FrequencyInputParserTests.swift`
- `KiwiWaterfallViewportTests.swift`
- `ListeningHistoryStoreTests.swift`
- `LiveAudioStabilityTests.swift`
- `OpenWebRXScannerSquelchPolicyTests.swift`
- `RadioSessionSettingsTests.swift`
- `ReceiverIdentityTests.swift`
- `ReceiverLinkImportTests.swift`

Testy nie zostaly uruchomione w tej sesji, bo obecne srodowisko robocze jest windowsowe i nie ma lokalnego Xcode.

## Najwazniejsze kamienie milowe z historii Git

Potwierdzone istotne commity w historii `native-ios`:

- `f66afc2` Add native SwiftUI iOS app and build unsigned IPA in CI
- `f41fe45` feat(ios): native ListenSDR app, diagnostics, audio pipeline and CI unsigned IPA
- `4b7ca23` Add native FM-DX backend client and live receiver status
- `e4fd02f` Add auto-updating receiver directory for FM-DX KiwiSDR and OpenWebRX
- `dbe7896` add tune-step controls and frequency favorites
- `4051682` Prepare Listen SDR TestFlight build 66
- `95b2796` Fix TestFlight wrapper for login signing
- `4659c3c` Automate TestFlight metadata publishing
- `dac28b0` Add TestFlight preflight and dry-run guards

## Co uznawac za zrodlo prawdy przy dalszej pracy

Przy kolejnych zadaniach nalezy przyjac te zasady:

1. Produkt = `native-ios/ListenSDR`, nie `App.tsx`.
2. Biezacy punkt odniesienia wersji = `1.0.1 (66)` z `native-ios/project.yml`.
3. Historia odzyskana jest pomocnicza, ale kod w repo ma pierwszenstwo.
4. Jesli pojawi sie rozjazd miedzy starszymi commitami a obecnym `project.yml`, traktowac obecne pliki jako kanoniczne.

## Dobry punkt startowy do dalszej pracy

Jesli wracamy do rozwoju produktu, najpierw warto otwierac:

1. `native-ios/ListenSDR/Sources/RadioSessionViewModel.swift`
2. `native-ios/ListenSDR/Sources/ReceiverView.swift`
3. `native-ios/ListenSDR/Sources/RadiosView.swift`
4. `native-ios/ListenSDR/Sources/SettingsView.swift`
5. `native-ios/ListenSDR/Sources/RadioSessionSettings.swift`

To sa pliki, w ktorych skupia sie najwiecej logiki produktu i tam beda trafialy wiekszosc kolejnych zmian.

## Chromecast roadmap (etap 1)

Dokument roboczy dla przygotowania Chromecast jako dodatkowej sciezki odtwarzania:

- `docs/chromecast-stage1-plan.md`
