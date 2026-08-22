# Enclavd — native app

Cross-platform (Android + iOS) native client for Enclavd, written in Flutter.
This is the `native-dev` experiment: it replaces the old WebView wrapper with
a real native app that talks to the site's `api/v1` JSON endpoints directly.

**Status: early milestone — login / register / feed.** Likes, comments,
notifications and chat are next, one milestone at a time.

## Architecture

- One codebase, two runners: `android/` and `ios/` are both committed.
- CI builds the Android APK (GitHub Actions); nothing is built on-device.
- All networking goes through `lib/api/`:
  - `api_client.dart` — HTTP layer with a persisted cookie jar (the server
    agent-binds sessions to the User-Agent, so every request carries the
    exact same UA — see `AppConfig.userAgent`, never change it).
  - `auth_service.dart` — login / register / me / logout, mirroring the
    legacy flows the website uses (login_token → POST /auth; POST
    /process_register; GET /api/v1/me; POST /api/v1/auth logout).
  - `feed_service.dart` — `GET /api/v1/posts` with keyset pagination
    (`last_score`/`last_id`).
- Theme: `lib/theme/enclavd_theme.dart` — a 1:1 port of the website's
  Tailwind tokens (dark, gray-950 background, gray-900 cards, blue-900
  primary, Montserrat). Assets (fonts, default avatar, logo) are copied from
  the website repo.

## Build-time configuration (flavors)

Every flavor-level switch is a compile-time dart-define read by
`lib/config/app_config.dart`. The GitHub workflow applies them per flavor.
**The app always talks to https://enclavd.com — there is no localhost build**
(a phone can't reach a dev box; local-only verification runs against the dev
stack via `tool/verify_live.dart` on the dev machine itself).

| Flavor  | API base            | Notifications | Insecure TLS |
|---------|---------------------|---------------|--------------|
| `play`  | https://enclavd.com  | on            | no           |
| `fdroid`| https://enclavd.com  | off           | no           |
| `dev`   | https://enclavd.com  | on            | no           |

To add a feature switch: add a `bool.fromEnvironment`/`String.fromEnvironment`
in `AppConfig`, use it in code, then wire the `--dart-define` in
`.github/workflows/build.yml` per flavor.

## Building

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build apk --debug --dart-define=ENCLAVD_FLAVOR=dev
```

CI (`.github/workflows/build.yml`) runs the first three on every push to
`native-dev` and produces APKs for all flavors. The iOS job exists but is
gated behind the `build_ios` dispatch input (needs a macOS runner; no
codesign yet).

## Layout

```
lib/
  main.dart                 app entry + service container
  config/app_config.dart    build-time flavor/feature switches
  api/                      api_client · auth_service · feed_service
  screens/                  splash · login · register · feed
  theme/                    Enclavd design system
  widgets/                  post card (feed)
test/                       unit tests (pure Dart, headless)
assets/                     Montserrat fonts, default avatar, logo
```

## Session contract (read before touching auth)

The web server agent-binds every login session to the User-Agent sent at
login, and destroys the session on any later request with a different UA.
`AppConfig.userAgent` is that string — it is a live session contract and
must NEVER change between app versions. The cookie jar persists
`enclavd_sid` (DB session) + `sid` (PHP session) so the app survives
restarts; a 401 from `/api/v1/me` means the session is dead and the app
returns to the login screen.
