# yellow_stick_ui_core

The single source of truth of the Yellow Stick UI design system: colours,
typography, radii, spacing, layout metrics and icons, as plain Dart values.

`yellow_stick_ui` (Flutter) and `yellow_stick_ui_web` (Jaspr) share no widget
code. Both read these values and render them their own way. Token names follow
the Luna semantic vocabulary used by lynx-ui (`canvas`, `paper`, `content`,
`primary`, `line`, ...); the values are Yellow Stick's own.
