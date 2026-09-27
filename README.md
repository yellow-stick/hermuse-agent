# Hermuse Agent

Hermuse Agent, the first Yellow Stick product: a personal AI agent on six platforms from one Dart monorepo, built on the **Yellow Stick
UI** design system.

| Surface | Stack | Platforms |
| --- | --- | --- |
| `apps/hermuse_app` | Flutter 3.47 | iOS, Android, macOS, Windows, Linux |
| `apps/hermuse_web` | Jaspr 0.23 (static pre-render + `@client` hydration) | Web (real DOM) |

```
pubspec.yaml                    pub workspace + Melos 8.9 scripts
packages/
  yellow_stick_ui_core/         pure Dart — tokens + icons, the single source of truth
  yellow_stick_ui/              Flutter kit
  yellow_stick_ui_web/          Jaspr kit
  hermuse_chat/                  pure Dart — chat models, state, controller, seed conversation
apps/
  hermuse_app/                   Flutter app
  hermuse_web/                   Jaspr app
.artifacts/{flutter,web}/       renders of both apps (wide, medium, compact, interaction proofs)
```

## Design system rule

> The token is the contract. The implementation is local.

The Flutter and Jaspr kits share no widget code. Both read the same values from
`yellow_stick_ui_core` — palette roles named after the Luna vocabulary used by
lynx-ui (`canvas`, `paper`, `content`, `primary`, `line`, …), type scale, radii,
spacing, shell breakpoints, icons, icon hover motions — and render them their
own way. Components are headless-first like lynx-ui: `YsPressable` exposes its
interaction state (pressed, hovered, focused, disabled) and styled variants sit
on top. Rail icons play a one-shot hover animation described once as keyframes
in `YsIconMotion`; the web kit compiles it to CSS `@keyframes`
(`YsMotionIconView`), the Flutter kit paints it (`YsMotionIcon`).

Behaviour is shared the same way: both apps render `hermuse_chat`'s `ChatState`
and call the same `ChatController`, so an action cannot behave differently on
the web and on native.

Chats follow a main/side model: each Hermes instance has one **Main chat**, and
every other thread is a **side chat** of it (created from Hermuse with the main
session as parent; pin, rename, archive, delete, full-text search). Other
sessions of the instance (CLI, Telegram, …) are not listed. The main chat and
the thread on screen are remembered per instance (`hermuse_state`).

## Setup

```bash
dart pub global activate melos
flutter pub get          # resolves the whole workspace
melos run analyze
melos run test
```

## Running

```bash
cd apps/hermuse_app && flutter run -d linux     # or macos / windows / an iOS or Android device
cd apps/hermuse_web && jaspr serve              # http://localhost:8080
cd apps/hermuse_web && jaspr build              # static output in build/jaspr
```

## Web app (PWA)

`apps/hermuse_web` is an installable Progressive Web App:

- `web/manifest.webmanifest` — "Hermuse Agent", standalone, `#181819` theme,
  icons in `web/icons/` (192/512, maskable 512, Apple touch 180, SVG) drawn
  from the Yellow Stick logo with the stick in yellow.
- `web/sw.js` — network-first service worker: online users always get the
  latest deploy, and everything fetched is cached so the app opens offline after
  one visit (the shell is precached at install). Bump `CACHE` in `sw.js` to drop
  old caches.
- iOS: `apple-mobile-web-app-*` metas and `apple-touch-icon`; opaque status bar
  because the layout does not handle safe-area insets yet.

Install from Chrome/Edge (install icon in the address bar) or Safari (Share →
Add to Home Screen). Service workers need HTTPS in production (localhost is
exempt).

## Version notes

- `jaspr_builder` 0.23.5 requires `analyzer ^12`, which caps `build_runner` at
  2.15.1 and `build_web_compilers` at 4.8.5. Bump them together with Jaspr.
- `flutter_test` (Flutter 3.47.5) pins `test_api` 0.7.12, so pure Dart packages
  resolve `test` 1.31.x.

## Assets

- Inter 4.1 (SIL Open Font License 1.1), bundled in `yellow_stick_ui/fonts` and
  `apps/hermuse_web/web/fonts`.
- Icons adapted from Lucide (ISC License).
- The Hermuse avatar is original artwork; airline logos are rendered as monogram
  discs rather than brand artwork.
