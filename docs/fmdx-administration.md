# Administracja serwerem FM-DX

Listen SDR pozwala otworzyć panel administracyjny własnego serwera FM-DX
bezpośrednio z listy zapisanych odbiorników.

## Jak działa logowanie

- Funkcja jest dostępna wyłącznie dla profili FM-DX.
- Aplikacja wykorzystuje hasło zapisane w profilu odbiornika. Hasło jest
  przechowywane w Keychainie i nie jest wysyłane do żadnego serwera Listen SDR
  ani Firebase.
- Najpierw aplikacja wysyła żądanie `POST /login`, a następnie sprawdza, czy
  odpowiedź `GET /setup` jest rzeczywistym panelem administracyjnym. Samo
  hasło tune nie wystarcza.
- Po udanym logowaniu panel jest ładowany w niepersistentnym `WKWebView`.
  Do widoku trafia wyłącznie uwierzytelniające ciasteczko sesji FM-DX
  `connect.sid`; pozostałe ciasteczka i hasło nie są przekazywane do WebView.
- Żądanie logowania nie podąża za przekierowaniem na inną domenę, port ani
  protokół. Jeśli serwer przekierowuje z HTTP na HTTPS, zapisz profil z
  włączonym TLS i użyj docelowego adresu HTTPS.

## Obsługa

Na profilu FM-DX otwórz akcje przesunięcia i wybierz **Administruj serwerem**.
Ta sama funkcja jest dostępna jako akcja VoiceOver. Panel zachowuje standardową
obsługę JavaScript, formularzy i WebSocketów wymaganą przez oficjalny interfejs
FM-DX. Główna nawigacja panelu jest ograniczona do tego samego hosta,
protokołu i portu, a niepersistentny magazyn WebView jest niszczony po
zamknięciu arkusza. Zamknięcie panelu jest dostępne jako przycisk na pasku
nawigacji.

Jeśli zapisane hasło jest hasłem tune albo nie ma go w profilu, aplikacja
wyświetli jasny komunikat i nie otworzy panelu.
