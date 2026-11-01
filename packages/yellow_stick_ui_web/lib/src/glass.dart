import 'package:jaspr/dom.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';

const _sheen = 'linear-gradient(180deg, var(--glass-shine), transparent 55%)';
const _mask =
    'linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)';
final _backdrop =
    'blur(${ysNum(YsGlassMaterial.blur)}px) '
    'saturate(${ysNum(YsGlassMaterial.saturation)})';

/// Liquid glass on the element matched by [selector], for floating controls
/// (Chats pill, agent switcher): the backdrop blurred and saturated
/// ([YsGlassMaterial]), tinted with `--glass`, a sheen washing down from
/// the top and a specular rim bright at the top-left corner (a masked
/// `::before`), resting on `--raised`. Hover and press lay the neutral
/// wash over the tint. Flutter kit: `YsGlass`.
///
/// Rules, not a shared class, so the glass outranks the component's own
/// fill whatever order the stylesheets land in: pass a selector more
/// specific than the component's base rule.
List<StyleRule> ysGlassRules(String selector) => [
  css(selector).styles(
    raw: {
      'position': 'relative',
      'background-color': 'var(--glass)',
      'background-image': _sheen,
      '-webkit-backdrop-filter': _backdrop,
      'backdrop-filter': _backdrop,
      'box-shadow': 'var(--raised)',
    },
  ),
  css('$selector::before').styles(
    raw: {
      'content': '""',
      'position': 'absolute',
      'inset': '0',
      'padding': '1px',
      'border-radius': 'inherit',
      'background':
          'linear-gradient(135deg, var(--glass-rim), var(--glass-shine) 50%)',
      '-webkit-mask': _mask,
      'mask': _mask,
      '-webkit-mask-composite': 'xor',
      'mask-composite': 'exclude',
      'pointer-events': 'none',
    },
  ),
  css('$selector:hover, $selector:active').styles(
    raw: {
      'background-color': 'var(--glass)',
      'background-image':
          '$_sheen, linear-gradient(var(--neutral-wash), var(--neutral-wash))',
    },
  ),
];
