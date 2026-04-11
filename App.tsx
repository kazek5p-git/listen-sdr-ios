import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Clipboard from 'expo-clipboard';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

type ThemeId = 'classic' | 'mistBlue' | 'seaGlass' | 'warmLight' | 'custom';
type ThemeField =
  | 'background'
  | 'backgroundSecondary'
  | 'card'
  | 'cardBorder'
  | 'text'
  | 'textMuted'
  | 'tint'
  | 'accent';

type ThemeColors = Record<ThemeField, string>;

type ThemePalette = ThemeColors & {
  id: ThemeId;
  name: string;
  description: string;
  statusBarStyle: 'light' | 'dark';
};

type CustomThemeExportPayload = {
  schemaVersion: 1;
  theme: 'custom';
  colors: ThemeColors;
};

const THEME_STORAGE_KEY = 'ListenSDR.androidTheme.v1';
const CUSTOM_THEME_STORAGE_KEY = 'ListenSDR.androidTheme.custom.v1';

const PRESET_THEMES: ThemePalette[] = [
  {
    id: 'classic',
    name: 'Klasyczny',
    description: 'Obecny lekki wygląd z chłodnym, jasnym tłem i miękkimi akcentami.',
    background: '#F3F6FA',
    backgroundSecondary: '#E7EEF7',
    card: '#FFFFFF',
    cardBorder: '#D8E0EB',
    text: '#0B1F3A',
    textMuted: '#42536B',
    tint: '#197DEC',
    accent: '#17B08F',
    statusBarStyle: 'dark',
  },
  {
    id: 'mistBlue',
    name: 'Przygaszony błękit',
    description: 'Spokojny, elegancki błękit z bardziej szlachetnym i lekko ciemniejszym tonem.',
    background: '#E6ECF4',
    backgroundSecondary: '#D1DBE8',
    card: '#F9FBFD',
    cardBorder: '#BCC8D7',
    text: '#162337',
    textMuted: '#516277',
    tint: '#3D5F8C',
    accent: '#7B8FAE',
    statusBarStyle: 'dark',
  },
  {
    id: 'seaGlass',
    name: 'Morskie szkło',
    description: 'Świeży morski motyw z lekkim turkusem i czystymi, czytelnymi kartami.',
    background: '#EAF7F5',
    backgroundSecondary: '#D9EFEA',
    card: '#FBFFFE',
    cardBorder: '#C3E0D8',
    text: '#113233',
    textMuted: '#456466',
    tint: '#14879B',
    accent: '#1AA886',
    statusBarStyle: 'dark',
  },
  {
    id: 'warmLight',
    name: 'Ciepłe światło',
    description: 'Jaśniejszy kremowy motyw z łagodnymi bursztynowymi akcentami.',
    background: '#F8F2E7',
    backgroundSecondary: '#EFE4D1',
    card: '#FFFDFA',
    cardBorder: '#E3D4BB',
    text: '#352516',
    textMuted: '#705844',
    tint: '#B26B1F',
    accent: '#D6923A',
    statusBarStyle: 'dark',
  },
];

const DEFAULT_CUSTOM_THEME: ThemeColors = {
  background: '#E6ECF4',
  backgroundSecondary: '#D1DBE8',
  card: '#F9FBFD',
  cardBorder: '#BCC8D7',
  text: '#162337',
  textMuted: '#516277',
  tint: '#3D5F8C',
  accent: '#7B8FAE',
};

const COLOR_FIELDS: Array<{ field: ThemeField; label: string }> = [
  { field: 'background', label: 'Tło główne' },
  { field: 'backgroundSecondary', label: 'Tło pomocnicze' },
  { field: 'card', label: 'Tło kart' },
  { field: 'cardBorder', label: 'Obramowanie kart' },
  { field: 'text', label: 'Tekst główny' },
  { field: 'textMuted', label: 'Tekst pomocniczy' },
  { field: 'tint', label: 'Główny akcent' },
  { field: 'accent', label: 'Drugi akcent' },
];

function normalizeHex(input: string): string {
  const cleaned = input.trim().replace(/^#/, '').toUpperCase();
  if (cleaned.length === 3) {
    return `#${cleaned
      .split('')
      .map((char) => `${char}${char}`)
      .join('')}`;
  }
  if (cleaned.length === 6 || cleaned.length === 8) {
    return `#${cleaned}`;
  }
  return input.trim().toUpperCase();
}

function isValidHexColor(input: string): boolean {
  return /^#([0-9A-F]{6}|[0-9A-F]{8})$/i.test(normalizeHex(input));
}

function hexToRgb(input: string): { r: number; g: number; b: number } | null {
  const normalized = normalizeHex(input);
  if (!isValidHexColor(normalized)) {
    return null;
  }

  const raw = normalized.slice(1);
  const value = raw.length === 8 ? raw.slice(0, 6) : raw;

  return {
    r: Number.parseInt(value.slice(0, 2), 16),
    g: Number.parseInt(value.slice(2, 4), 16),
    b: Number.parseInt(value.slice(4, 6), 16),
  };
}

function relativeLuminance(input: string): number {
  const rgb = hexToRgb(input);
  if (!rgb) {
    return 1;
  }

  const toLinear = (channel: number) => {
    const normalized = channel / 255;
    return normalized <= 0.03928
      ? normalized / 12.92
      : ((normalized + 0.055) / 1.055) ** 2.4;
  };

  const r = toLinear(rgb.r);
  const g = toLinear(rgb.g);
  const b = toLinear(rgb.b);

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function statusBarStyleForBackground(background: string): 'light' | 'dark' {
  return relativeLuminance(background) < 0.45 ? 'light' : 'dark';
}

function coerceThemeColors(value: unknown): ThemeColors | null {
  if (!value || typeof value !== 'object') {
    return null;
  }

  const candidate = value as Partial<Record<ThemeField, unknown>>;
  const result = {} as ThemeColors;

  for (const field of COLOR_FIELDS) {
    const raw = candidate[field.field];
    if (typeof raw !== 'string' || !isValidHexColor(raw)) {
      return null;
    }
    result[field.field] = normalizeHex(raw);
  }

  return result;
}

function makeThemePalette(
  id: ThemeId,
  name: string,
  description: string,
  colors: ThemeColors
): ThemePalette {
  return {
    id,
    name,
    description,
    ...colors,
    statusBarStyle: statusBarStyleForBackground(colors.background),
  };
}

function makeCustomTheme(colors: ThemeColors): ThemePalette {
  return makeThemePalette(
    'custom',
    'Własna',
    'Ręcznie ustawione kolory tła, kart, tekstu i akcentów.',
    colors
  );
}

function themeForId(themeId: ThemeId, customTheme: ThemeColors): ThemePalette {
  if (themeId === 'custom') {
    return makeCustomTheme(customTheme);
  }
  return PRESET_THEMES.find((theme) => theme.id === themeId) ?? PRESET_THEMES[0];
}

function themeColorsFromPalette(theme: ThemePalette): ThemeColors {
  return {
    background: theme.background,
    backgroundSecondary: theme.backgroundSecondary,
    card: theme.card,
    cardBorder: theme.cardBorder,
    text: theme.text,
    textMuted: theme.textMuted,
    tint: theme.tint,
    accent: theme.accent,
  };
}

function exportCustomThemePayload(colors: ThemeColors): CustomThemeExportPayload {
  return {
    schemaVersion: 1,
    theme: 'custom',
    colors,
  };
}

function exportCustomThemeJson(colors: ThemeColors): string {
  return JSON.stringify(exportCustomThemePayload(colors), null, 2);
}

function parseImportedCustomTheme(input: string): ThemeColors {
  const trimmed = input.trim();
  if (!trimmed) {
    throw new Error('Wklej JSON własnej skórki.');
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    throw new Error('Nie udało się odczytać JSON własnej skórki.');
  }

  if (!parsed || typeof parsed !== 'object') {
    throw new Error('Plik lub tekst nie zawiera prawidłowej skórki.');
  }

  const colors = coerceThemeColors((parsed as { colors?: unknown }).colors);
  if (!colors) {
    throw new Error('Importowana skórka nie zawiera kompletu poprawnych kolorów.');
  }

  return colors;
}

export default function App() {
  const [selectedThemeId, setSelectedThemeId] = useState<ThemeId>('classic');
  const [customTheme, setCustomTheme] = useState<ThemeColors>(DEFAULT_CUSTOM_THEME);
  const [customInputs, setCustomInputs] = useState<ThemeColors>(DEFAULT_CUSTOM_THEME);
  const [customError, setCustomError] = useState('');
  const [importJsonInput, setImportJsonInput] = useState('');
  const [importExportStatus, setImportExportStatus] = useState('');
  const [isThemeLoaded, setIsThemeLoaded] = useState(false);

  const activeTheme = useMemo(
    () => themeForId(selectedThemeId, customTheme),
    [customTheme, selectedThemeId]
  );

  const draftTheme = useMemo(() => {
    const canBuildDraft = COLOR_FIELDS.every(({ field }) => isValidHexColor(customInputs[field]));
    return canBuildDraft
      ? makeCustomTheme(
          Object.fromEntries(
            COLOR_FIELDS.map(({ field }) => [field, normalizeHex(customInputs[field])])
          ) as ThemeColors
        )
      : makeCustomTheme(customTheme);
  }, [customInputs, customTheme]);

  useEffect(() => {
    let isMounted = true;

    Promise.all([
      AsyncStorage.getItem(THEME_STORAGE_KEY),
      AsyncStorage.getItem(CUSTOM_THEME_STORAGE_KEY),
    ])
      .then(([storedThemeId, storedCustomTheme]) => {
        if (!isMounted) {
          return;
        }

        const parsedThemeId: ThemeId =
          storedThemeId === 'classic' ||
          storedThemeId === 'mistBlue' ||
          storedThemeId === 'seaGlass' ||
          storedThemeId === 'warmLight' ||
          storedThemeId === 'custom'
            ? storedThemeId
            : 'classic';

        let nextCustomTheme = DEFAULT_CUSTOM_THEME;
        if (storedCustomTheme) {
          try {
            const parsedValue = JSON.parse(storedCustomTheme);
            const parsedCustomTheme = coerceThemeColors(parsedValue);
            if (parsedCustomTheme) {
              nextCustomTheme = parsedCustomTheme;
            }
          } catch {
            // Ignore broken local custom theme snapshots.
          }
        }

        setSelectedThemeId(parsedThemeId);
        setCustomTheme(nextCustomTheme);
        setCustomInputs(nextCustomTheme);
      })
      .finally(() => {
        if (isMounted) {
          setIsThemeLoaded(true);
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

  const persistThemeSelection = async (themeId: ThemeId) => {
    setSelectedThemeId(themeId);
    try {
      await AsyncStorage.setItem(THEME_STORAGE_KEY, themeId);
    } catch {
      // Best effort local persistence only.
    }
  };

  const persistCustomTheme = async (colors: ThemeColors) => {
    setCustomTheme(colors);
    setCustomInputs(colors);
    try {
      await AsyncStorage.setItem(CUSTOM_THEME_STORAGE_KEY, JSON.stringify(colors));
    } catch {
      // Best effort local persistence only.
    }
  };

  const handleThemeSelect = async (themeId: ThemeId) => {
    setCustomError('');
    await persistThemeSelection(themeId);
  };

  const handleUseCurrentThemeAsBase = async () => {
    const source = themeColorsFromPalette(activeTheme);
    setCustomError('');
    await persistCustomTheme(source);
    await persistThemeSelection('custom');
  };

  const handleResetCustomTheme = async () => {
    setCustomError('');
    await persistCustomTheme(DEFAULT_CUSTOM_THEME);
    await persistThemeSelection('custom');
  };

  const handleApplyCustomTheme = async () => {
    const normalizedColors = {} as ThemeColors;

    for (const { field, label } of COLOR_FIELDS) {
      const value = normalizeHex(customInputs[field]);
      if (!isValidHexColor(value)) {
        setCustomError(`Pole „${label}” wymaga koloru w formacie #RRGGBB lub #RRGGBBAA.`);
        return;
      }
      normalizedColors[field] = value;
    }

    setCustomError('');
    await persistCustomTheme(normalizedColors);
    await persistThemeSelection('custom');
  };

  const handleCopyCustomTheme = async () => {
    await Clipboard.setStringAsync(exportCustomThemeJson(customTheme));
    setImportExportStatus('JSON własnej skórki został skopiowany do schowka.');
  };

  const handleShareCustomTheme = async () => {
    try {
      await Share.share({
        message: exportCustomThemeJson(customTheme),
        title: 'Listen SDR custom skin',
      });
      setImportExportStatus('Udostępniono JSON własnej skórki.');
    } catch {
      setImportExportStatus('Nie udało się udostępnić JSON własnej skórki.');
    }
  };

  const handleLoadImportFromClipboard = async () => {
    const clipboardText = await Clipboard.getStringAsync();
    setImportJsonInput(clipboardText);
    setImportExportStatus('Wczytano zawartość schowka do pola importu.');
  };

  const handleImportCustomTheme = async (rawValue: string) => {
    try {
      const importedTheme = parseImportedCustomTheme(rawValue);
      setCustomError('');
      setImportExportStatus('');
      await persistCustomTheme(importedTheme);
      await persistThemeSelection('custom');
      setImportJsonInput(exportCustomThemeJson(importedTheme));
      setImportExportStatus('Zaimportowano własną skórkę i ustawiono ją jako aktywną.');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Nie udało się zaimportować własnej skórki.';
      setImportExportStatus(message);
    }
  };

  const handleCustomInputChange = (field: ThemeField, value: string) => {
    setCustomInputs((current) => ({
      ...current,
      [field]: value,
    }));
  };

  const themeOptions = useMemo(
    () => [...PRESET_THEMES, makeCustomTheme(customTheme)],
    [customTheme]
  );

  if (!isThemeLoaded) {
    return (
      <SafeAreaView style={[styles.safeArea, { backgroundColor: PRESET_THEMES[0].background }]}>
        <StatusBar style={PRESET_THEMES[0].statusBarStyle} />
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={PRESET_THEMES[0].tint} />
          <Text style={[styles.loadingText, { color: PRESET_THEMES[0].textMuted }]}>
            Ładowanie motywu...
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: activeTheme.background }]}>
      <StatusBar style={activeTheme.statusBarStyle} />
      <ScrollView
        contentContainerStyle={[
          styles.scrollContent,
          { backgroundColor: activeTheme.background },
        ]}
      >
        <View style={styles.header}>
          <Text style={[styles.title, { color: activeTheme.text }]}>Listen SDR</Text>
          <Text style={[styles.subtitle, { color: activeTheme.textMuted }]}>
            Android preview z presetami i własną skórką
          </Text>
        </View>

        <ThemeCard theme={activeTheme}>
          <Text style={[styles.cardTitle, { color: activeTheme.text }]}>Aktualny wygląd</Text>
          <Text style={[styles.cardDescription, { color: activeTheme.textMuted }]}>
            Wybrana skórka:
          </Text>
          <View style={styles.badgeRow}>
            <View
              style={[
                styles.badge,
                {
                  backgroundColor: activeTheme.backgroundSecondary,
                  borderColor: activeTheme.cardBorder,
                },
              ]}
            >
              <Text style={[styles.badgeText, { color: activeTheme.tint }]}>
                {activeTheme.name}
              </Text>
            </View>
          </View>
          <ThemeSwatches theme={activeTheme} />
        </ThemeCard>

        <ThemeCard theme={activeTheme}>
          <Text style={[styles.cardTitle, { color: activeTheme.text }]}>Skórki</Text>
          <Text style={[styles.cardDescription, { color: activeTheme.textMuted }]}>
            Wybierz wariant kolorystyczny albo przejdź na własne ustawienia.
          </Text>

          <View style={styles.themeList}>
            {themeOptions.map((item) => {
              const isSelected = item.id === activeTheme.id;
              return (
                <Pressable
                  key={item.id}
                  accessibilityRole="button"
                  accessibilityState={{ selected: isSelected }}
                  onPress={() => {
                    void handleThemeSelect(item.id);
                  }}
                  style={({ pressed }) => [
                    styles.themeOption,
                    {
                      backgroundColor: isSelected ? item.backgroundSecondary : item.card,
                      borderColor: isSelected ? item.tint : activeTheme.cardBorder,
                      opacity: pressed ? 0.92 : 1,
                    },
                  ]}
                >
                  <View style={styles.themeOptionHeader}>
                    <Text style={[styles.themeName, { color: activeTheme.text }]}>{item.name}</Text>
                    <View style={styles.themeMiniSwatches}>
                      <View style={[styles.themeMiniSwatch, { backgroundColor: item.tint }]} />
                      <View style={[styles.themeMiniSwatch, { backgroundColor: item.accent }]} />
                    </View>
                  </View>
                  <Text style={[styles.themeDescription, { color: activeTheme.textMuted }]}>
                    {item.description}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </ThemeCard>

        <ThemeCard theme={draftTheme}>
          <Text style={[styles.cardTitle, { color: draftTheme.text }]}>Własna skórka</Text>
          <Text style={[styles.cardDescription, { color: draftTheme.textMuted }]}>
            Tutaj ustawisz własne kolory tła, kart, tekstu i akcentów. Kliknięcie „Zastosuj”
            zapisuje skórkę i przełącza aplikację na wariant własny.
          </Text>

          <View style={styles.buttonRow}>
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                void handleUseCurrentThemeAsBase();
              }}
              style={({ pressed }) => [
                styles.actionButton,
                {
                  backgroundColor: draftTheme.backgroundSecondary,
                  borderColor: draftTheme.cardBorder,
                  opacity: pressed ? 0.9 : 1,
                },
              ]}
            >
              <Text style={[styles.actionButtonText, { color: draftTheme.tint }]}>
                Użyj bieżącej jako bazy
              </Text>
            </Pressable>

            <Pressable
              accessibilityRole="button"
              onPress={() => {
                void handleResetCustomTheme();
              }}
              style={({ pressed }) => [
                styles.actionButton,
                {
                  backgroundColor: draftTheme.card,
                  borderColor: draftTheme.cardBorder,
                  opacity: pressed ? 0.9 : 1,
                },
              ]}
            >
              <Text style={[styles.actionButtonText, { color: draftTheme.text }]}>
                Reset
              </Text>
            </Pressable>
          </View>

          <View style={styles.buttonRow}>
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                void handleCopyCustomTheme();
              }}
              style={({ pressed }) => [
                styles.actionButton,
                {
                  backgroundColor: draftTheme.backgroundSecondary,
                  borderColor: draftTheme.cardBorder,
                  opacity: pressed ? 0.9 : 1,
                },
              ]}
            >
              <Text style={[styles.actionButtonText, { color: draftTheme.tint }]}>
                Kopiuj JSON
              </Text>
            </Pressable>

            <Pressable
              accessibilityRole="button"
              onPress={() => {
                void handleShareCustomTheme();
              }}
              style={({ pressed }) => [
                styles.actionButton,
                {
                  backgroundColor: draftTheme.card,
                  borderColor: draftTheme.cardBorder,
                  opacity: pressed ? 0.9 : 1,
                },
              ]}
            >
              <Text style={[styles.actionButtonText, { color: draftTheme.text }]}>
                Udostępnij JSON
              </Text>
            </Pressable>
          </View>

          <ThemeCard theme={draftTheme} nested>
            <Text style={[styles.cardTitle, { color: draftTheme.text }]}>Podgląd własnej skórki</Text>
            <Text style={[styles.cardDescription, { color: draftTheme.textMuted }]}>
              Tak będzie wyglądał wariant własny po zapisaniu.
            </Text>
            <ThemeSwatches theme={draftTheme} />
          </ThemeCard>

          <ThemeCard theme={draftTheme} nested>
            <Text style={[styles.cardTitle, { color: draftTheme.text }]}>Import własnej skórki</Text>
            <Text style={[styles.cardDescription, { color: draftTheme.textMuted }]}>
              Wklej JSON eksportu własnej skórki albo wczytaj go ze schowka.
            </Text>

            <View style={styles.buttonRow}>
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  void handleLoadImportFromClipboard();
                }}
                style={({ pressed }) => [
                  styles.actionButton,
                  {
                    backgroundColor: draftTheme.backgroundSecondary,
                    borderColor: draftTheme.cardBorder,
                    opacity: pressed ? 0.9 : 1,
                  },
                ]}
              >
                <Text style={[styles.actionButtonText, { color: draftTheme.tint }]}>
                  Wczytaj ze schowka
                </Text>
              </Pressable>

              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  void handleImportCustomTheme(importJsonInput);
                }}
                style={({ pressed }) => [
                  styles.actionButton,
                  {
                    backgroundColor: draftTheme.card,
                    borderColor: draftTheme.cardBorder,
                    opacity: pressed ? 0.9 : 1,
                  },
                ]}
              >
                <Text style={[styles.actionButtonText, { color: draftTheme.text }]}>
                  Importuj JSON
                </Text>
              </Pressable>
            </View>

            <TextInput
              accessibilityLabel="JSON własnej skórki"
              autoCapitalize="none"
              autoCorrect={false}
              multiline
              numberOfLines={8}
              onChangeText={setImportJsonInput}
              placeholder={'{\n  "schemaVersion": 1,\n  "theme": "custom"\n}'}
              placeholderTextColor={draftTheme.textMuted}
              style={[
                styles.importInput,
                {
                  backgroundColor: draftTheme.card,
                  borderColor: draftTheme.cardBorder,
                  color: draftTheme.text,
                },
              ]}
              textAlignVertical="top"
              value={importJsonInput}
            />
          </ThemeCard>

          <View style={styles.fieldList}>
            {COLOR_FIELDS.map(({ field, label }) => {
              const value = customInputs[field];
              const normalizedValue = normalizeHex(value);
              const isValid = isValidHexColor(normalizedValue);

              return (
                <View key={field} style={styles.fieldBlock}>
                  <View style={styles.fieldHeader}>
                    <Text style={[styles.fieldLabel, { color: draftTheme.text }]}>{label}</Text>
                    <View
                      style={[
                        styles.fieldSwatch,
                        {
                          backgroundColor: isValid ? normalizedValue : 'transparent',
                          borderColor: isValid ? draftTheme.cardBorder : '#D93025',
                        },
                      ]}
                    />
                  </View>
                  <TextInput
                    accessibilityLabel={label}
                    autoCapitalize="characters"
                    autoCorrect={false}
                    onChangeText={(nextValue) => handleCustomInputChange(field, nextValue)}
                    placeholder="#RRGGBB"
                    placeholderTextColor={draftTheme.textMuted}
                    style={[
                      styles.input,
                      {
                        backgroundColor: draftTheme.card,
                        borderColor: isValid ? draftTheme.cardBorder : '#D93025',
                        color: draftTheme.text,
                      },
                    ]}
                    value={value}
                  />
                </View>
              );
            })}
          </View>

          {customError ? (
            <Text style={styles.errorText}>{customError}</Text>
          ) : importExportStatus ? (
            <Text style={[styles.helperText, { color: draftTheme.textMuted }]}>
              {importExportStatus}
            </Text>
          ) : (
            <Text style={[styles.helperText, { color: draftTheme.textMuted }]}>
              Akceptowane są wartości w formacie #RRGGBB lub #RRGGBBAA.
            </Text>
          )}

          <Pressable
            accessibilityRole="button"
            onPress={() => {
              void handleApplyCustomTheme();
            }}
            style={({ pressed }) => [
              styles.primaryButton,
              {
                backgroundColor: draftTheme.tint,
                borderColor: draftTheme.tint,
                opacity: pressed ? 0.92 : 1,
              },
            ]}
          >
            <Text style={styles.primaryButtonText}>Zastosuj własną skórkę</Text>
          </Pressable>
        </ThemeCard>
      </ScrollView>
    </SafeAreaView>
  );
}

function ThemeCard({
  children,
  nested = false,
  theme,
}: {
  children: React.ReactNode;
  nested?: boolean;
  theme: ThemePalette;
}) {
  return (
    <View
      style={[
        styles.previewCard,
        nested ? styles.nestedCard : null,
        {
          backgroundColor: theme.card,
          borderColor: theme.cardBorder,
        },
      ]}
    >
      {children}
    </View>
  );
}

function ThemeSwatches({ theme }: { theme: ThemePalette }) {
  return (
    <View style={styles.swatchRow}>
      <View style={styles.swatchItem}>
        <View style={[styles.swatch, { backgroundColor: theme.tint }]} />
        <Text style={[styles.swatchLabel, { color: theme.textMuted }]}>Akcent</Text>
      </View>
      <View style={styles.swatchItem}>
        <View style={[styles.swatch, { backgroundColor: theme.accent }]} />
        <Text style={[styles.swatchLabel, { color: theme.textMuted }]}>Drugi akcent</Text>
      </View>
      <View style={styles.swatchItem}>
        <View style={[styles.swatch, { backgroundColor: theme.backgroundSecondary }]} />
        <Text style={[styles.swatchLabel, { color: theme.textMuted }]}>Tło</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    padding: 20,
    gap: 18,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  loadingText: {
    marginTop: 12,
    fontSize: 16,
  },
  header: {
    paddingTop: 8,
    paddingBottom: 8,
  },
  title: {
    fontSize: 30,
    fontWeight: '800',
  },
  subtitle: {
    marginTop: 6,
    fontSize: 15,
    lineHeight: 21,
  },
  previewCard: {
    borderWidth: 1,
    borderRadius: 24,
    padding: 18,
    gap: 14,
  },
  nestedCard: {
    marginTop: 4,
  },
  cardTitle: {
    fontSize: 20,
    fontWeight: '700',
  },
  cardDescription: {
    fontSize: 15,
    lineHeight: 21,
  },
  badgeRow: {
    flexDirection: 'row',
  },
  badge: {
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  badgeText: {
    fontSize: 14,
    fontWeight: '700',
  },
  swatchRow: {
    flexDirection: 'row',
    gap: 18,
    flexWrap: 'wrap',
  },
  swatchItem: {
    alignItems: 'center',
    gap: 6,
  },
  swatch: {
    width: 34,
    height: 34,
    borderRadius: 17,
  },
  swatchLabel: {
    fontSize: 13,
  },
  themeList: {
    gap: 12,
  },
  themeOption: {
    borderWidth: 1,
    borderRadius: 18,
    padding: 14,
    gap: 8,
  },
  themeOptionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  themeName: {
    fontSize: 17,
    fontWeight: '700',
    flex: 1,
  },
  themeDescription: {
    fontSize: 14,
    lineHeight: 20,
  },
  themeMiniSwatches: {
    flexDirection: 'row',
    gap: 6,
  },
  themeMiniSwatch: {
    width: 16,
    height: 16,
    borderRadius: 8,
  },
  buttonRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  actionButton: {
    borderWidth: 1,
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  actionButtonText: {
    fontSize: 14,
    fontWeight: '700',
  },
  fieldList: {
    gap: 12,
  },
  fieldBlock: {
    gap: 6,
  },
  fieldHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  fieldLabel: {
    fontSize: 15,
    fontWeight: '600',
    flex: 1,
  },
  fieldSwatch: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 1,
  },
  input: {
    borderWidth: 1,
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 15,
    fontWeight: '600',
  },
  importInput: {
    borderWidth: 1,
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 12,
    minHeight: 160,
    fontSize: 14,
    lineHeight: 20,
  },
  helperText: {
    fontSize: 13,
    lineHeight: 19,
  },
  errorText: {
    fontSize: 13,
    lineHeight: 19,
    color: '#D93025',
    fontWeight: '600',
  },
  primaryButton: {
    borderWidth: 1,
    borderRadius: 16,
    paddingHorizontal: 16,
    paddingVertical: 14,
    alignItems: 'center',
  },
  primaryButtonText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '800',
  },
});
