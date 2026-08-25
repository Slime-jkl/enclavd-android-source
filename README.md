# Enclavd - Personality Social Network

Stop broadcasting into the void. Enclavd is a private social network built on compatibility. Take a personality quiz, get matched with people on your wavelength, and connect through a feed built around who you actually are.

<b>CORE PRINCIPLES</b>

<b>Personality over Popularity:</b> Your feed is filtered by personality. Find people who are on the same frequency.

<b>Private by Design:</b> Your profile and activity exist inside a closed network. No public indexing, no search engine scraping, no exposure.

<b>Invite-Only Network:</b> Enclavd grows through trusted invitations only. No open sign-ups, no bot accounts, no spam profiles cluttering your feed.

<b>Minimalist Interface:</b> A clean, stripped-back design built for focus, with nothing competing for your attention except the people you're actually connecting with.

<b>Free to Join:</b> Enclavd is free to download and use, with no barriers to finding your community.

<b>WHO ENCLAVD IS FOR</b>
• You're tired of social media feeds built around outrage and engagement bait.

• You want a private social network instead of a public profile anyone can scrape.

• You're looking for real conversations and genuine compatibility, not more followers.

• You'd rather join through a trusted invite than scroll past strangers and bots.
Enclavd is a social network for people who want depth over reach.


Take the quiz. Find your matches. Build your enclave.
Download Enclavd and stop existing for the feed.

## Screenshots

<p>
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" width="32%">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/2.png" width="32%">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" width="32%">
</p>
<p>
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/4.png" width="32%">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/5.png" width="32%">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/6.png" width="32%">
</p>
<p>
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/7.png" width="32%">
</p>

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
