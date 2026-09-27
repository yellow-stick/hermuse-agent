/// Large/small classification + recency ranking over discovered model ids.
///
/// `model.options` rows carry no size signal: `capabilities.{fast,reasoning}`
/// describe feature toggles (`fast` = the vendor's speed param exists on 3
/// Anthropic flagships, not "this model is small"; `reasoning` defaults true
/// when the catalogue is silent) and `pricing` is usually null on a fresh
/// install. The sidecar `/v1/models` catalogue carries `created` timestamps
/// in its embedded registry, but `OpenAIModels` only forwards `created` when
/// the static entry has one — so recency must ALSO work from version numbers
/// parsed out of the ids themselves.
///
/// Hence: per-family small-marker tables decided from the real ids observed
/// in Hermes' static catalogue (`models_catalog_static.py`) and the sidecar
/// embedded catalogue (`internal/registry/models/models.json`), plus generic
/// version-tuple parsing for recency. Unknown family → [ModelTier.unknown],
/// never an auto pick: the user chooses.
library;

/// Size tier of one model id.
enum ModelTier {
  /// Flagship/full-size model (opus, pro, max, base GLM/Kimi/MiniMax id…).
  large,

  /// Distilled/cheap/fast variant (sonnet, haiku, flash, mini, air, lite…).
  small,

  /// Family unknown or id unparseable: no auto pick, user chooses.
  unknown,
}

/// One ranked model: id, tier, and the recency key that ordered it.
final class RankedModel {
  const RankedModel({
    required this.id,
    required this.tier,
    required this.version,
  });

  final String id;
  final ModelTier tier;

  /// Parsed version tuple for recency (higher = newer); empty when the id
  /// carries no version.
  final List<int> version;
}

/// Small-model markers by family. Order matters: first matching family wins.
/// Matching is case-insensitive substring on the model id.
const _smallMarkers = <String, List<String>>{
  // Anthropic: opus = large; sonnet/haiku = small. The dated snapshots keep
  // their family word, so they classify the same way.
  'claude': ['sonnet', 'haiku'],
  // OpenAI: base/gpt-N = large; mini/nano/sol = small. `-pro` is a paid-tier
  // suffix on BOTH sizes (gpt-5.4-mini vs gpt-5.4), never a size signal.
  // Per the user's own pair ("gpt astra et sol"), sol is GPT's small tier.
  // `codex-auto-review` is a harness alias, unknown size.
  'gpt': ['mini', 'nano', 'sol'],
  // Z.AI: base glm-N = large; flash/air/turbo = small.
  'glm': ['flash', 'air', 'turbo'],
  // Kimi: base k2/k3 = large; thinking/turbo/highspeed/preview/coding/256k =
  // small. (`kimi-for-coding*` are routing aliases, not flagships; `*-256k`
  // is the reduced-context variant.)
  'kimi': ['thinking', 'turbo', 'preview', 'highspeed', 'for-coding', '256k'],
  // MiniMax: M-numbered = large; highspeed = small.
  'minimax': ['highspeed'],
  // Meta: base spark = large; contributor = small.
  'spark': ['contributor'],
  // xAI: base grok-N = large; mini/fast/composer = small. `build-fast` and
  // `*-fast` are speed suffixes; plain `grok-build-*` stays large (unknown).
  'grok': ['mini', 'fast', 'composer'],
  // Gemini (Antigravity + direct): pro = large; flash/lite = small.
  'gemini': ['flash', 'lite'],
  // Qwen: max/plus = large; flash/coder = small.
  'qwen': ['flash', 'coder'],
  // DeepSeek: pro/vN = large; flash = small.
  'deepseek': ['flash'],
  // Xiaomi: pro/omni = large; flash/ultraspeed = small.
  'mimo': ['flash', 'ultraspeed'],
};

/// Families whose ids carry no size signal at all: every id is large unless
/// a generic small marker matches (checked after the family table).
const _largeOnlyFamilies = <String>[
  'wan', // Alibaba image gen (wan2.7-image*) — not a chat tier at all.
  'qwen-audio', // TTS/realtime audio models.
  'copilot-search', // Copilot harness aliases.
  'exec-agent', // Copilot harness aliases.
];

/// Generic small markers applied when no family matched: conservative —
/// only unambiguous size words.
const _genericSmallMarkers = <String>[
  'flash',
  'mini',
  'nano',
  'lite',
  'haiku',
  'turbo',
  'air',
  'highspeed',
  'ultraspeed',
];

/// Ids that are not real selectable models (harness aliases, sentinels).
bool isSelectableModelId(String id) {
  final lower = id.toLowerCase();
  if (lower.isEmpty || lower == 'auto' || lower == 'default') return false;
  if (lower == 'copilot-acp') return false;
  if (lower == 'codex-auto-review') return false;
  if (lower.startsWith('copilot-search-')) return false;
  if (lower.startsWith('exec-agent-')) return false;
  return true;
}

/// Classifies [id] into a [ModelTier] using the family marker tables.
ModelTier classifyModel(String id) {
  final lower = id.toLowerCase();
  if (!isSelectableModelId(id)) return ModelTier.unknown;
  for (final prefix in _largeOnlyFamilies) {
    if (lower.contains(prefix)) return ModelTier.unknown;
  }
  for (final entry in _smallMarkers.entries) {
    if (lower.contains(entry.key)) {
      for (final marker in entry.value) {
        if (lower.contains(marker)) return ModelTier.small;
      }
      return ModelTier.large;
    }
  }
  for (final marker in _genericSmallMarkers) {
    if (lower.contains(marker)) return ModelTier.small;
  }
  return ModelTier.unknown;
}

/// Parses the version out of a model id for recency ranking.
///
/// Picks the LAST dotted-numeric run (`5.3` in `glm-5.3-flash`, `4-8` in
/// `claude-opus-4-8`, `20251101` in `claude-opus-4-5-20251101`,
/// `1.3-contributor` → `[1, 3]` in `spark-1.3-contributor`, `0902` in
/// `qwen3.8-max-0902`). A trailing date stamp (`YYYYMMDD`, 8 digits) sorts
/// after the version so newer snapshots win. Non-numeric ids (`kimi-k3`,
/// `gpt-6-sol`) yield the single major number plus a name hash tail so
/// ordering stays deterministic.
List<int> parseModelVersion(String id) {
  final lower = id.toLowerCase();
  final runs = RegExp(r'\d+(?:[.\-]\d+)*').allMatches(lower).toList();
  if (runs.isEmpty) return const [];
  // Split every run on dots AND dashes: `4-5-20251101` → [4, 5, 20251101].
  // A trailing 8-digit date stamp (>= 20000000) sorts after the version so
  // newer snapshots of the same version win.
  final parts = <int>[];
  var stamp = 0;
  for (final run in runs) {
    for (final piece in run.group(0)!.split(RegExp(r'[.\-]'))) {
      final n = int.tryParse(piece);
      if (n != null) parts.add(n);
    }
  }
  // A trailing date stamp sorts after the version, but must never
  // outrank a higher version: compare [version..., 0/1 has-stamp?, stamp].
  // `4-5-20251101` → [4, 5, 1, 20251101] beats `4-20250514` → [4, 1,
  // 20250514] at index 1.
  var hasStamp = 0;
  if (parts.length > 1 && parts.last >= 20000000 && parts.last < 30000000) {
    stamp = parts.removeLast();
    hasStamp = 1;
  }
  if (stamp != 0) {
    parts.add(hasStamp);
    parts.add(stamp);
  }
  return parts;
}

int compareModelVersions(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  // A bare major (`opus-5`) loses to any minor (`opus-5-5`, `fable-5.1`):
  // longer = more specific = newer.
  return a.length.compareTo(b.length);
}

/// Ranks [ids] newest-first within each tier. Returns the newest large and
/// newest small id, either null when its tier has no candidates.
({String? large, String? small}) pickLargeAndSmall(Iterable<String> ids) {
  RankedModel? newestLarge;
  RankedModel? newestSmall;
  for (final id in ids) {
    if (!isSelectableModelId(id)) continue;
    final tier = classifyModel(id);
    if (tier == ModelTier.unknown) continue;
    final ranked = RankedModel(
      id: id,
      tier: tier,
      version: parseModelVersion(id),
    );
    if (tier == ModelTier.large) {
      if (newestLarge == null ||
          compareModelVersions(ranked.version, newestLarge.version) > 0) {
        newestLarge = ranked;
      }
    } else {
      if (newestSmall == null ||
          compareModelVersions(ranked.version, newestSmall.version) > 0) {
        newestSmall = ranked;
      }
    }
  }
  return (large: newestLarge?.id, small: newestSmall?.id);
}
