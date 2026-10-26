# Quitty

Na macOS kliknięcie czerwonego ✕ zamyka tylko okno, a aplikacja dalej działa w tle (kropka pod ikoną w Docku). Quitty to zmienia: **kiedy zamkniesz ostatnie okno aplikacji, Quitty ją zamyka (Quit)**, tak jak ⌘Q.

- Minimalizacja (żółty przycisk) i ukrywanie (⌘H) **nie** zamykają aplikacji, bo jej okna dalej istnieją.
- Zamykanie działa jak ⌘Q, więc aplikacja nadal zapyta o zapisanie niezapisanych zmian.
- Finder nigdy nie jest zamykany. Aplikacje z paska menu (bez ikony w Docku) też nie.
- Swoje wyjątki ustawisz w menu (np. Muzyka albo Spotify, które mają grać dalej bez okna).
- Aplikacja ma kilka sekund ochrony po uruchomieniu, żeby ekran powitalny (splash) nie zamknął jej, zanim otworzy się główne okno.

Działa na macOS 13 (Ventura) i nowszych, na Apple Silicon i Intelu.

## Instalacja

### Gotowa aplikacja z GitHub Actions

1. Wejdź w zakładkę **Actions**, otwórz ostatnie udane uruchomienie **Build** i pobierz artefakt **Quitty**. Jeśli jest wydanie (Release), możesz pobrać `Quitty.zip` stamtąd.
2. Rozpakuj i przenieś `Quitty.app` do folderu **Aplikacje**.
3. Aplikacja nie jest podpisana certyfikatem Apple, więc przy pierwszym uruchomieniu macOS ją zablokuje. Możesz kliknąć ją prawym przyciskiem i wybrać **Otwórz**, albo w Terminalu wpisać:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Quitty.app
   ```

### Budowanie samemu

Potrzebujesz Xcode albo Command Line Tools (`xcode-select --install`):

```sh
git clone https://github.com/kubach7/quitty-macos.git
cd quitty-macos
./scripts/build-app.sh
cp -R build/Quitty.app /Applications/
open /Applications/Quitty.app
```

`UNIVERSAL=1 ./scripts/build-app.sh` zbuduje wersję dla obu architektur (wymaga pełnego Xcode).

## Pierwsze uruchomienie: uprawnienia

Żeby widzieć, kiedy zamykasz okna innych aplikacji, Quitty potrzebuje dostępu do **Dostępności**:

**Ustawienia systemowe → Prywatność i ochrona → Dostępność →** włącz **Quitty**.

macOS sam o to zapyta przy starcie. Po włączeniu dostępu Quitty zaczyna działać od razu, bez restartu.

> Jeśli zbudujesz aplikację od nowa, macOS może jej nie rozpoznać, bo zmienia się podpis. Wtedy usuń Quitty z listy Dostępności (przycisk „−”) i dodaj ją jeszcze raz.

## Menu

Ikona ✕ w kółku na pasku menu:

| Opcja | Co robi |
|---|---|
| Zamykaj aplikacje po zamknięciu ostatniego okna | Włącza i wyłącza Quitty |
| Wyjątki (nie zamykaj) | Zaznacz aplikacje, których Quitty ma nie ruszać, albo dodaj je z folderu Aplikacje |
| Uruchamiaj przy logowaniu | Quitty startuje razem z systemem |
| Zakończ Quitty | Wyłącza Quitty |

Gdy Quitty jest wyłączone albo nie ma uprawnień, ikona jest wyszarzona.

## Jak to działa

Quitty działa w pasku menu i przez Accessibility API (`AXObserver`) obserwuje okna każdej uruchomionej aplikacji. Gdy któreś okno znika, Quitty czeka chwilę (0,6 s, bo niektóre aplikacje na moment niszczą i tworzą okna, np. przy pełnym ekranie), sprawdza listę okien i jeśli jest pusta, wywołuje `terminate()`, czyli zwykłe Quit.

Kod jest w `Sources/Quitty/`:

- `AppWatcher.swift` obserwuje okna jednej aplikacji.
- `QuitController.swift` pilnuje listy aplikacji i decyduje, czy zamknąć.
- `AppDelegate.swift` to menu na pasku i uprawnienia.
- `Settings.swift` przechowuje ustawienia i wyjątki.
