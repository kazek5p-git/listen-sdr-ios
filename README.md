# Listen SDR (Expo)

Projekt skonfigurowany do live testow na iPhonie z Windows przez Expo.

## Aktualna konfiguracja
- App name: `Listen SDR`
- Slug: `listen-sdr`
- iOS bundle id: `com.kazek.sdr`
- Android package: `com.kazek.sdr`

## Uruchomienie live preview na iPhonie
1. Na iPhonie zainstaluj Expo Go.
2. W katalogu projektu uruchom:

```powershell
npm run start:iphone
```

Skrypt uruchamia Expo w tle (tunnel) i wypisuje URL `exp://` do otwarcia w Expo Go.

## Przydatne komendy
```powershell
npm run doctor
npm run start:lan
npm run start:tunnel
npm run build:ios:dev
npm run build:ios:preview
npm run build:ios:prod
```

## Natywny projekt iOS (Xcode)
Katalog: `native-ios/`

- Projekt jest definiowany przez `native-ios/project.yml` (XcodeGen).
- Wygenerowany projekt Xcode jest trzymany w repo jako `native-ios/ListenSDR.xcodeproj`.
- Workflow `.github/workflows/sync-xcodeproj.yml` automatycznie aktualizuje `ListenSDR.xcodeproj` po zmianach w `native-ios/`.
- Ikony aplikacji sa gotowe w `native-ios/ListenSDR/Resources/Assets.xcassets/AppIcon.appiconset`.
- `ASSETCATALOG_COMPILER_APPICON_NAME` jest ustawione na `AppIcon`.

Podpisanie przez inne konto Apple w Xcode:
1. Wygeneruj projekt przez XcodeGen (`xcodegen generate` w `native-ios/`).
2. Otworz `ListenSDR.xcodeproj` w Xcode.
3. W `Signing & Capabilities` ustaw Team i unikalny Bundle Identifier.
4. Uzyj `Automatically manage signing`.

## GitHub Actions: unsigned IPA (pod Sideloadly)
Workflow: `.github/workflows/ios-unsigned-ipa.yml`

Co robi:
- uruchamia sie recznie (`workflow_dispatch`)
- buduje natywna aplikacje SwiftUI z `native-ios/` na `macos-15` bez podpisu
- pakuje artefakt `Listen-SDR-unsigned.ipa`

Jak uzyc:
1. Wejdz w GitHub -> Actions -> `iOS Unsigned IPA` -> `Run workflow`.
2. Po zakonczeniu pobierz artifact `Listen-SDR-unsigned-ipa`.
3. Podpisz i zainstaluj plik `.ipa` przez Sideloadly na iPhonie (Developer Mode wlaczony).

## GitHub Actions: signed IPA + TestFlight (konto znajomego)
Workflow: `.github/workflows/ios-signed-testflight.yml`

Co robi:
- uruchamia sie recznie (`workflow_dispatch`)
- buduje natywna aplikacje SwiftUI z `native-ios/` na `macos-15`
- podpisuje build certyfikatem dystrybucyjnym z sekretow GitHub
- eksportuje signed `.ipa` i dodaje artifact `Listen-SDR-signed-ipa`
- opcjonalnie wysyla ten sam `.ipa` do TestFlight (`upload_to_testflight=true`)

Wymagane sekrety repo (GitHub -> Settings -> Secrets and variables -> Actions):
- `APPLE_TEAM_ID`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_API_KEY_BASE64` (base64 z pliku `AuthKey_XXXXXX.p8`)
- `IOS_DIST_CERT_P12_BASE64` (base64 z certyfikatu dystrybucyjnego `.p12`)
- `IOS_DIST_CERT_PASSWORD`
- `IOS_PROVISION_PROFILE_BASE64` (base64 z profilu App Store `.mobileprovision`)
- `KEYCHAIN_PASSWORD` (dowolne silne haslo techniczne dla tymczasowego keychaina CI)

Jak uzyc:
1. Ustaw powyzsze sekrety z konta Apple znajomego.
2. Wejdz w GitHub -> Actions -> `iOS Signed IPA + TestFlight (Native)` -> `Run workflow`.
3. Dla samego podpisanego artefaktu ustaw `upload_to_testflight=false`.
4. Dla automatycznego wyslania do TestFlight ustaw `upload_to_testflight=true`.

## App Store Connect API key (lokalnie)
W systemie sa ustawione zmienne:
- `EXPO_ASC_API_KEY_PATH`
- `EXPO_ASC_KEY_ID`
- `EXPO_ASC_ISSUER_ID`
- `EXPO_APPLE_TEAM_ID`
- `EXPO_APPLE_TEAM_TYPE`

Do buildow EAS potrzebne jest zalogowanie do konta Expo (`eas login` lub `EXPO_TOKEN`).
