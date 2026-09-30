/// Fictional content of the demo: two Hermes instances, their chats and
/// their Hermuse plugin data. Every person, place and figure is made up.
library;

/// One transcript row of a demo chat.
final class DemoRow {
  const DemoRow.user(this.text) : role = 'user', reasoning = null, tool = null;

  const DemoRow.agent(this.text, {this.reasoning})
    : role = 'assistant',
      tool = null;

  /// A finished tool call; [text] is the summary its row shows.
  const DemoRow.tool(String this.tool, this.text)
    : role = 'tool',
      reasoning = null;

  /// Hermes transcript role: `user`, `assistant` or `tool`.
  final String role;
  final String text;
  final String? reasoning;
  final String? tool;
}

/// A conversation: the main chat of an instance or one of its side chats.
final class DemoChat {
  const DemoChat({
    required this.id,
    required this.title,
    required this.age,
    required this.rows,
    this.pinned = false,
    this.archived = false,
  });

  /// Stored Hermes session id.
  final String id;
  final String title;

  /// Time from its last message to page load.
  final Duration age;
  final List<DemoRow> rows;
  final bool pinned;
  final bool archived;
}

/// A Hermes instance with its chats and plugin data.
final class DemoInstance {
  const DemoInstance({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.provider,
    required this.model,
    required this.main,
    required this.sideChats,
    required this.feed,
    required this.ideas,
    required this.goals,
    required this.artifacts,
    required this.reflections,
    required this.files,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String provider;
  final String model;
  final DemoChat main;
  final List<DemoChat> sideChats;

  /// Plugin records as the plugin API returns them, with `created_at`-like
  /// fields given as an age ([Duration]) and rendered at request time.
  final List<Map<String, Object?>> feed;
  final List<Map<String, Object?>> ideas;
  final List<Map<String, Object?>> goals;
  final List<Map<String, Object?>> artifacts;
  final List<Map<String, Object?>> reflections;

  /// Managed system files (`IDENTITY.md`, …) and `PREFERENCES.md`.
  final Map<String, String> files;

  Iterable<DemoChat> get chats => [main, ...sideChats];
}

/// The demo instances, primary first.
const demoInstances = [_ava, _otto];

const _ava = DemoInstance(
  id: '6f1c2a4e-8d3b-4c7a-9e21-5b0d7f3a1c01',
  label: 'Ava',
  baseUrl: 'https://ava.example.com',
  provider: 'anthropic',
  model: 'claude-sonnet-4-5',
  main: DemoChat(
    id: '20260930_074512_ava000',
    title: '',
    age: Duration(minutes: 12),
    rows: [
      DemoRow.user("Morning! What's on my plate today?"),
      DemoRow.tool('memory', 'Read 4 entries: calendar, errands, habits'),
      DemoRow.agent(
        'Good morning, Léa. A calm Wednesday:\n\n'
        '- **09:30** — Design review with Marco (45 min, video)\n'
        '- **12:30** — Lunch with Inès at *Le Comptoir*\n'
        '- **16:00** — Dentist, Dr. Varga\n'
        '- **Tonight** — the Lisbon flights you watched drop under €120 '
        'expire at midnight\n\n'
        'You also said you wanted a 5 km easy run this week: '
        'the only free slot left is **07:00–08:00 tomorrow**.',
        reasoning:
            'Calendar has three events. The run goal from the training plan '
            'needs one easy session; Thursday morning is the only gap.',
      ),
      DemoRow.user(
        'Move the dentist to next week and remind me to call Mom tonight.',
      ),
      DemoRow.tool('send_message', 'Email to Dr. Varga’s office: reschedule'),
      DemoRow.tool('cronjob', 'Reminder at 20:30: call Mom'),
      DemoRow.agent(
        'Done:\n\n'
        '1. I asked Dr. Varga’s office to move you to **Tuesday or Wednesday '
        'next week, after 15:00**. I will tell you when they answer.\n'
        '2. You will get a reminder at **20:30** to call your mom.',
      ),
      DemoRow.user('Anything interesting in the topics I follow?'),
      DemoRow.tool('web_search', 'solid-state batteries news this week'),
      DemoRow.tool('web_search', 'urban rewilding Lyon 2026'),
      DemoRow.agent(
        'Two things worth your coffee:\n\n'
        '### Solid-state batteries\n'
        'A pilot line in Grenoble reported cells keeping **91 % capacity '
        'after 1,000 cycles**. Still lab scale, but it is the first public '
        'number from that team.\n\n'
        '### Rewilding the Rhône banks\n'
        'Lyon approved the second phase of the riverbank project: '
        '4 km of concrete quays become meadows by 2028. There is a public '
        'walk-through on **Saturday at 10:00** if you want to go.\n\n'
        'I saved both to your Feed with sources.',
      ),
    ],
  ),
  sideChats: [
    DemoChat(
      id: '20260929_183002_ava001',
      title: 'Lisbon trip in May',
      age: Duration(hours: 20),
      pinned: true,
      rows: [
        DemoRow.user(
          'Plan 4 days in Lisbon for two in May. We like food, walking and '
          'no museums marathon.',
        ),
        DemoRow.tool('web_search', 'Lisbon May weather crowds'),
        DemoRow.tool('web_search', 'Lisbon neighbourhood food walks'),
        DemoRow.agent(
          'Here is a relaxed plan, one neighbourhood per day:\n\n'
          '**Day 1 — Alfama & Graça**\n'
          'Arrive, walk up to the Miradouro da Senhora do Monte for sunset, '
          'dinner at a small *tasca* near Largo do Chafariz de Dentro.\n\n'
          '**Day 2 — Baixa & Chiado**\n'
          'Morning pastries, the Santa Justa lift views without the queue '
          '(take the stairs from Largo do Carmo), afternoon at the '
          'Time Out Market only if you go before 12:00.\n\n'
          '**Day 3 — Belém by bike**\n'
          'Ride along the river, one museum at most (MAAT is outdoors-friendly), '
          'pastéis de Belém on the way back.\n\n'
          '**Day 4 — Day trip to Sintra or the beach at Cascais**\n'
          'Sintra if the forecast is clear, Cascais if it is hot.\n\n'
          '> May is warm (22–25 °C) and busy from the 20th on: '
          'go early in the month if you can.',
        ),
        DemoRow.user('Keep an eye on flights from Lyon under €120.'),
        DemoRow.tool('cronjob', 'Daily at 08:00: check LYS → LIS fares'),
        DemoRow.agent(
          'I check every morning at 08:00. Current best: **€114 return** '
          '(May 7–11, direct). I will ping you if it goes below €100 or '
          'before it disappears.',
        ),
      ],
    ),
    DemoChat(
      id: '20260928_064418_ava002',
      title: 'Half-marathon training',
      age: Duration(days: 2),
      rows: [
        DemoRow.user(
          'I want to run the Lyon half-marathon in 12 weeks. I run 15 km a '
          'week now.',
        ),
        DemoRow.agent(
          'Twelve weeks from 15 km/week is realistic. The plan grows about '
          '10 % a week with a lighter week every fourth:\n\n'
          '- **Weeks 1–4:** 3 runs, 16 → 22 km. One of them with 6 × 1 min '
          'faster strides.\n'
          '- **Weeks 5–8:** long run grows to 15 km; add one tempo run '
          '(20 min at half-marathon pace).\n'
          '- **Weeks 9–11:** peak at 35 km/week, long run 18 km.\n'
          '- **Week 12:** taper to 15 km, race on Sunday.\n\n'
          'I added it to your Goals and I will adjust each week from how '
          'your runs felt.',
          reasoning:
              'Current base 15 km. Peak around 35 km keeps weekly growth '
              'near 10 %, with deload weeks 4 and 8.',
        ),
        DemoRow.user('My left knee felt tight after the long run.'),
        DemoRow.agent(
          'Let’s be careful: this week the long run drops from 12 to **9 km** '
          'on flat ground, and add 10 minutes of hip and glute strength after '
          'two runs. If the tightness is still there next Sunday or it hurts '
          'going down stairs, see a physio before we build again.',
        ),
      ],
    ),
    DemoChat(
      id: '20260925_201534_ava003',
      title: 'Sourdough troubleshooting',
      age: Duration(days: 5),
      rows: [
        DemoRow.user(
          'My sourdough comes out flat and dense. Starter is 2 weeks old.',
        ),
        DemoRow.agent(
          'A 2-week-old starter is often not strong enough yet. Three checks:\n\n'
          '1. **Does it double within 6 hours** after feeding at room '
          'temperature? If not, feed it twice a day for another week.\n'
          '2. **Bulk fermentation:** the dough should grow by about 50 % and '
          'show bubbles on the sides. In a 20 °C kitchen that is 6–8 hours, '
          'not 4.\n'
          '3. **Hydration:** drop to 68 % water until the shaping feels '
          'easier.\n\n'
          'Send me a photo of the crumb next time and I will tell you which '
          'one it was.',
        ),
      ],
    ),
    DemoChat(
      id: '20260918_121207_ava004',
      title: 'Apartment insurance quotes',
      age: Duration(days: 12),
      archived: true,
      rows: [
        DemoRow.user('Compare the three home insurance quotes I forwarded.'),
        DemoRow.tool('read_file', 'Read 3 PDF quotes'),
        DemoRow.agent(
          'The middle one is the best fit: same coverage as the most '
          'expensive, a €150 deductible instead of €300, and €9 a month '
          'cheaper than your current contract.',
        ),
      ],
    ),
  ],
  feed: [
    {
      'id': 'feed-ava-1',
      'title': 'Solid-state cells pass 1,000 cycles in Grenoble',
      'topic': 'Energy',
      'body':
          'A pilot line reported 91 % capacity retention after 1,000 '
          'cycles on its sulfide-electrolyte cells. The team plans larger '
          'pouch cells next spring. Still far from cars, but the first public '
          'cycle-life number from that group.',
      'sources': ['https://example.com/energy/solid-state-grenoble'],
      'age': Duration(hours: 2),
      'reactions': <String, Object?>{},
    },
    {
      'id': 'feed-ava-2',
      'title': 'Lyon turns 4 km of quays into meadows',
      'topic': 'Cities',
      'body':
          'The second phase of the Rhône riverbank project was approved. '
          'A public walk-through takes place Saturday at 10:00 from '
          'Pont de la Guillotière.',
      'sources': ['https://example.com/lyon/rewilding-phase-2'],
      'age': Duration(hours: 3),
      'reactions': {'love': ''},
    },
    {
      'id': 'feed-ava-3',
      'title': 'Why your sourdough needs a warmer spot',
      'topic': 'Cooking',
      'body':
          'Wild yeast activity roughly doubles between 20 °C and 26 °C. '
          'An oven with only the light on is a common home proofing box.',
      'sources': ['https://example.com/cooking/sourdough-temperature'],
      'age': Duration(days: 2),
      'reactions': <String, Object?>{},
    },
  ],
  ideas: [
    {
      'id': 'idea-ava-1',
      'title': 'Neighbourhood tool library',
      'pitch':
          'Your building has 40 flats and most drills are used 15 minutes a '
          'year. A shared shelf in the bike room with a simple sign-out sheet.',
      'group': 'Community',
      'first_step': 'Ask the building WhatsApp group who would lend a tool.',
      'age': Duration(days: 1),
      'feedback': <Object?>[],
    },
    {
      'id': 'idea-ava-2',
      'title': 'Photo book of the Lisbon trip',
      'pitch':
          'Pick 40 photos after the trip and I lay them out by day with the '
          'places from the itinerary.',
      'group': 'Travel',
      'first_step': 'Create a shared album before you leave.',
      'age': Duration(days: 3),
      'feedback': <Object?>[],
    },
  ],
  goals: [
    {
      'id': 'goal-ava-1',
      'title': 'Run the Lyon half-marathon',
      'category': 'health',
      'why': 'Prove to myself I can train steadily for three months.',
      'target_date': '2026-12-20',
      'status': 'tracking',
      'age': Duration(days: 9),
      'timeline': [
        {'age': Duration(days: 9), 'note': 'Plan started', 'progress': '0 %'},
        {
          'age': Duration(days: 2),
          'note': 'Week 2 done, knee tight after long run',
          'progress': '15 %',
        },
      ],
    },
    {
      'id': 'goal-ava-2',
      'title': 'Save €3,000 for the summer',
      'category': 'finance',
      'why': 'Travel without touching the emergency fund.',
      'target_date': '2027-06-01',
      'status': 'tracking',
      'age': Duration(days: 30),
      'timeline': [
        {
          'age': Duration(days: 1),
          'note': 'September transfer made',
          'progress': '€900 / €3,000',
        },
      ],
    },
  ],
  artifacts: [
    {
      'id': 'art-ava-1',
      'title': 'Lisbon — 4-day itinerary',
      'kind': 'document',
      'file': 'artifacts/lisbon-itinerary.md',
      'size': 4812,
      'tags': ['travel', 'lisbon'],
      'age': Duration(hours: 20),
    },
    {
      'id': 'art-ava-2',
      'title': 'Half-marathon training plan',
      'kind': 'document',
      'file': 'artifacts/half-marathon-plan.md',
      'size': 6230,
      'tags': ['running'],
      'age': Duration(days: 2),
    },
  ],
  reflections: [
    {
      'age': Duration(days: 1),
      'body':
          'Léa got through a dense Tuesday without skipping the run. The trip '
          'planning is where she lights up: more of that, less inbox triage '
          'in the evening.',
    },
  ],
  files: {
    'IDENTITY.md':
        '# Ava\n\nPersonal assistant of Léa. Warm, brief, never pushy. '
        'Answers in the language of the question.',
    'FEED_PROMPT.md':
        'Follow: energy storage, urban nature, running, cooking. '
        'At most three posts a day.',
    'HEARTBEAT.md':
        '# Heartbeat\n\nEvery morning at 07:30: calendar check, weather, '
        'one suggestion for the day.',
    'PREFERENCES.md':
        '# Preferences\n\n- No messages after 22:00\n- Prefer trains under '
        '4 hours\n- Vegetarian most days',
  },
);

const _otto = DemoInstance(
  id: '0b7e9d52-3f4a-4e1b-8c6d-2a9f1e7b3d02',
  label: 'Otto',
  baseUrl: 'https://otto.example.com',
  provider: 'openai',
  model: 'gpt-5',
  main: DemoChat(
    id: '20260930_090301_atl000',
    title: '',
    age: Duration(hours: 1),
    rows: [
      DemoRow.user(
        'Summarize the six customer interviews from last week in five '
        'points I can paste in the product review.',
      ),
      DemoRow.tool('read_file', 'Read interviews/2026-09-*.md (6 files)'),
      DemoRow.agent(
        '1. **Onboarding takes too long** — 4 of 6 needed a call to finish '
        'the setup.\n'
        '2. **Exports are the hidden killer feature** — every finance team '
        'mentioned the CSV export unprompted.\n'
        '3. **Pricing is clear, seats are not** — two customers were '
        'surprised by the per-seat charge for read-only users.\n'
        '4. **Mobile is "nice to have"** — nobody uses it daily.\n'
        '5. **They want Slack alerts**, not emails.\n\n'
        'Quote worth using: *"Once it is set up, it just runs. Getting it '
        'set up is the hard part."* — Operations lead, logistics company.',
        reasoning:
            'Six transcripts. Grouped recurring themes, kept the ones '
            'raised by at least two customers.',
      ),
      DemoRow.user('Draft the Slack alerts idea as a one-pager.'),
      DemoRow.tool('write_file', 'Wrote docs/slack-alerts-one-pager.md'),
      DemoRow.agent(
        'Draft saved to your Library as **Slack alerts — one-pager**: '
        'problem, the three alerts customers asked for, a two-sprint scope '
        'and the open question on per-channel permissions.',
      ),
    ],
  ),
  sideChats: [
    DemoChat(
      id: '20260929_140922_atl001',
      title: 'Competitor pricing scan',
      age: Duration(days: 1),
      rows: [
        DemoRow.user(
          'How do our three main competitors price read-only seats?',
        ),
        DemoRow.tool('web_search', 'Northwind analytics pricing viewer seats'),
        DemoRow.tool('web_search', 'Contoso reports pricing read-only users'),
        DemoRow.tool('web_search', 'Fabrikam BI pricing plans 2026'),
        DemoRow.agent(
          '- **Northwind:** viewers free, unlimited.\n'
          '- **Contoso:** viewers free up to 10, then €4 each.\n'
          '- **Fabrikam:** every seat paid, €12 flat.\n\n'
          'Two of three give read-only seats away. That matches point 3 of '
          'the interviews: charging viewers is our most visible pricing '
          'friction.',
        ),
      ],
    ),
  ],
  feed: [
    {
      'id': 'feed-atl-1',
      'title': 'Contoso ships Slack alerts',
      'topic': 'Competitors',
      'body':
          'Contoso announced threshold alerts in Slack channels, available on '
          'every plan. It is the feature customers asked for last week.',
      'sources': ['https://example.com/contoso/slack-alerts'],
      'age': Duration(hours: 5),
      'reactions': {'discuss': ''},
    },
  ],
  ideas: [
    {
      'id': 'idea-atl-1',
      'title': 'Guided setup call as a product',
      'pitch':
          'Four of six customers needed a call to finish onboarding. '
          'Offer it as a bookable 30-minute session inside the app.',
      'group': 'Onboarding',
      'first_step': 'Count setup calls in the last quarter.',
      'age': Duration(hours: 2),
      'feedback': <Object?>[],
    },
  ],
  goals: [
    {
      'id': 'goal-atl-1',
      'title': 'Cut onboarding time in half',
      'category': 'career',
      'why': 'The first week decides whether a team stays.',
      'target_date': '2027-03-31',
      'status': 'tracking',
      'age': Duration(days: 14),
      'timeline': <Object?>[],
    },
  ],
  artifacts: [
    {
      'id': 'art-atl-1',
      'title': 'Slack alerts — one-pager',
      'kind': 'document',
      'file': 'docs/slack-alerts-one-pager.md',
      'size': 3104,
      'tags': ['product', 'alerts'],
      'age': Duration(hours: 1),
    },
  ],
  reflections: <Map<String, Object?>>[],
  files: {
    'IDENTITY.md':
        '# Otto\n\nWork assistant. Precise, cites its sources, writes in '
        'short bullet points.',
    'FEED_PROMPT.md': 'Competitors, B2B pricing, product analytics.',
    'HEARTBEAT.md': '# Heartbeat\n\nWeekdays at 09:00: overnight summary.',
    'PREFERENCES.md': '# Preferences\n\n- Work hours only (09:00–18:00)',
  },
);
