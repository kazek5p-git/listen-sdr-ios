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

## GitHub Actions: unsigned IPA (pod Sideloadly)
Workflow: `.github/workflows/ios-unsigned-ipa.yml`

Co robi:
- uruchamia sie recznie (`workflow_dispatch`)
- buduje iOS na `macos-15` bez podpisu
- pakuje artefakt `Listen-SDR-unsigned.ipa`

Jak uzyc:
1. Wejdz w GitHub -> Actions -> `iOS Unsigned IPA` -> `Run workflow`.
2. Po zakonczeniu pobierz artifact `Listen-SDR-unsigned-ipa`.
3. Podpisz i zainstaluj plik `.ipa` przez Sideloadly na iPhonie (Developer Mode wlaczony).

## App Store Connect API key (lokalnie)
W systemie sa ustawione zmienne:
- `EXPO_ASC_API_KEY_PATH`
- `EXPO_ASC_KEY_ID`
- `EXPO_ASC_ISSUER_ID`
- `EXPO_APPLE_TEAM_ID`
- `EXPO_APPLE_TEAM_TYPE`

Do buildow EAS potrzebne jest zalogowanie do konta Expo (`eas login` lub `EXPO_TOKEN`).
