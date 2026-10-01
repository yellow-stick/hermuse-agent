/// Fictional content of the demo: two Hermes instances, their chats and
/// their Hermuse plugin data. Every person, place and figure is made up.
///
/// The chats tell four everyday stories, backed by matching Feed, Goals,
/// Ideas and Library entries so every panel tells the same story:
///
/// - Ava's main chat: sorting out an electricity renewal (the agent compares
///   and switches), plus the morning feed it wrote while she slept.
/// - `Weekend in Annecy`: a weekend trip under €400, compared and priced.
/// - `Autumn half-marathon`: a training plan with weekly check-ins.
/// - Otto's main chat: customer interview synthesis, plus which AI
///   subscription it runs on.
library;

/// One transcript row of a demo chat.
final class DemoRow {
  const DemoRow.user(this.text)
    : role = 'user',
      reasoning = null,
      tool = null,
      args = const {};

  const DemoRow.agent(this.text, {this.reasoning})
    : role = 'assistant',
      tool = null,
      args = const {};
  /// A finished tool call; [text] is the summary its row shows. Browser
  /// calls (`browser_*`) also carry their [args] (page URL, element text),
  /// like the live transcript does.
  const DemoRow.tool(String this.tool, this.text, {this.args = const {}})
    : role = 'tool',
      reasoning = null;

  /// Hermes transcript role: `user`, `assistant` or `tool`.
  final String role;
  final String text;
  final String? reasoning;
  final String? tool;

  /// Raw tool arguments (page URL, element text) of `browser_*` rows.
  final Map<String, Object?> args;
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
      DemoRow.user(
        'Can you sort out our electricity contract? The renewal came in '
        'and it looks expensive.',
      ),
      DemoRow.tool('read_file', 'Read renewal email from Voltia (PDF)'),
      DemoRow.tool(
        'browser_navigate',
        'compare.watto.example/energy-lyon',
        args: {'url': 'https://compare.watto.example/energy-lyon'},
      ),
      DemoRow.tool(
        'browser_click',
        'Compare Voltia renewal, Verte and Lumen Pure',
      ),
      DemoRow.tool(
        'browser_type',
        'Fill the Lumen Pure switch form',
        args: {'url': 'https://switch.lumenpure.example/form'},
      ),
      DemoRow.agent(
        'Your renewal jumps to **€0.24/kWh** — about €98 a month for us. '
        'I compared it with the two cheapest green offers in Lyon:\n\n'
        '- **Voltia renewal:** €0.24/kWh, about €98 a month.\n'
        '- **Voltia Verte:** €0.19/kWh, about €79 a month, no exit fee.\n'
        '- **Lumen Pure:** €0.18/kWh, about **€76 a month**, no exit fee.\n\n'
        '**Lumen Pure saves about €22 a month.** I switched us over from my '
        'computer, the one that runs on your machine — same meter, no cut, '
        'it starts Friday. The comparison is in your Library.',
        reasoning:
            'Renewal up 29 %. Lumen Pure is the cheapest green offer with '
            'no exit fee, so switching beats negotiating.',
      ),
      DemoRow.user('What did you put in my Feed this morning?'),
      DemoRow.tool('memory', "Read this morning's feed (3 posts)"),
      DemoRow.agent(
        'Three things, written before you woke up:\n\n'
        '- **The electricity switch** is confirmed, with the new rate.\n'
        '- **Annecy this weekend: sun, 19 °C** — good news for the trip.\n'
        '- **Week 3 of your running plan** starts with an easy 6 km.\n\n'
        'Say the word and I change what I follow.',
      ),
    ],
  ),
  sideChats: [
    DemoChat(
      id: '20260929_183002_ava001',
      title: 'Weekend in Annecy',
      age: Duration(hours: 20),
      pinned: true,
      rows: [
        DemoRow.user(
          'Find us a weekend trip for two next month. Under €400, no plane, '
          'somewhere we can still swim.',
        ),
        DemoRow.tool('web_search', 'Lake Annecy swimming mid-October'),
        DemoRow.tool('web_search', 'Lyon Annecy train fares weekends'),
        DemoRow.tool('web_search', 'Annecy lakeside hotels under €150 night'),
        DemoRow.agent(
          'Annecy fits: the lake is still 19 °C and the town is quiet after '
          'summer. One plan, all priced:\n\n'
          '- **Train:** Lyon → Annecy direct, **€29 each way** per person, '
          '1 h 50.\n'
          '- **Hotel:** two nights by the lake, **€135 a night**, breakfast '
          'included.\n'
          '- **Swims:** plage d’Albigny (free) and a morning kayak, €18.\n\n'
          '**Total: about €360 for two.** I keep an eye on the train fares '
          'and I tell you if they drop below €25.',
        ),
        DemoRow.user('Book the hotel side of it, with free cancellation.'),
        DemoRow.tool(
          'browser_navigate',
          'stay.watto.example/annecy-lac',
          args: {'url': 'https://stay.watto.example/annecy-lac'},
        ),
        DemoRow.tool('browser_type', 'Fill the Hôtel du Lac booking form'),
        DemoRow.agent(
          'Found it: two nights at the Hôtel du Lac, **€270 with breakfast**, '
          'free cancellation until Thursday. I filled in the booking on my '
          'computer, the one that runs on your machine — the confirmation '
          'is in your inbox, and the trains are still being watched.',
        ),
      ],
    ),
    DemoChat(
      id: '20260928_064418_ava002',
      title: 'Autumn half-marathon',
      age: Duration(days: 2),
      rows: [
        DemoRow.user(
          'I want to run the Lyon half-marathon in 12 weeks. I run 15 km a '
          'week now.',
        ),
        DemoRow.tool('cronjob', 'Sundays at 19:00: training check-in'),
        DemoRow.agent(
          'Twelve weeks from 15 km a week is realistic. Three runs a week, '
          'growing about 10 % with a lighter week every fourth:\n\n'
          '- **Weeks 1–4:** 16 → 22 km, one session with 6 × 1 min faster '
          'strides.\n'
          '- **Weeks 5–8:** long run grows to 15 km, plus one 20 min tempo.\n'
          '- **Weeks 9–11:** peak at 35 km, long run 18 km.\n'
          '- **Week 12:** taper, race on Sunday.\n\n'
          'I added it to your Goals and I check in every Sunday evening to '
          'adjust the next week from how your runs felt.',
          reasoning:
              'Current base 15 km. Peak around 35 km keeps weekly growth '
              'near 10 %, with deload weeks 4 and 8.',
        ),
        DemoRow.user('My left knee felt tight after the long run.'),
        DemoRow.agent(
          'Let’s be careful: this week the long run drops from 12 to **9 km** '
          'on flat ground, plus 10 minutes of hip and glute strength after '
          'two runs. If it still feels tight next Sunday, or it hurts going '
          'down stairs, see a physio before we build again. I updated your '
          'goal’s progress note.',
        ),
      ],
    ),
  ],
  feed: [
    {
      'id': 'feed-ava-1',
      'title': 'Your electricity switch is confirmed',
      'topic': 'Home',
      'body':
          'Lumen Pure confirmed the switch overnight: €0.18/kWh from Friday, '
          'about €22 a month less than the Voltia renewal. Same meter, no '
          'visit, no cut. The comparison is in your Library.',
      'sources': ['https://example.com/lumen/switch-confirmation'],
      'age': Duration(hours: 2),
      'reactions': {'love': ''},
    },
    {
      'id': 'feed-ava-2',
      'title': 'Annecy this weekend: sun, 19 °C',
      'topic': 'Weekend',
      'body':
          'Clear skies over the lake Saturday and Sunday, water still 19 °C. '
          'Your hotel is booked and the trains are holding at €29 — I tell '
          'you if they drop below €25.',
      'sources': ['https://example.com/meteo/annecy-weekend'],
      'age': Duration(hours: 3),
      'reactions': <String, Object?>{},
    },
    {
      'id': 'feed-ava-3',
      'title': 'Week 3 of your half-marathon plan',
      'topic': 'Running',
      'body':
          'Two weeks done, 15 % of the way there. This week: an easy 6 km, '
          'strides on Thursday, 9 km flat on Sunday while the knee settles. '
          'Check-in Sunday evening as usual.',
      'sources': <String>[],
      'age': Duration(hours: 4),
      'reactions': <String, Object?>{},
    },
  ],
  ideas: [
    {
      'id': 'idea-ava-1',
      'title': 'Annecy photo weekend album',
      'pitch':
          'After the trip, drop me your photos and I lay out a small album '
          'by day, with the lake spots from the itinerary.',
      'group': 'Travel',
      'first_step': 'Create a shared album before you leave.',
      'age': Duration(days: 1),
      'feedback': <Object?>[],
    },
    {
      'id': 'idea-ava-2',
      'title': 'Yearly electricity check',
      'pitch':
          'Contracts creep up every autumn. Every September I compare ours '
          'against the cheapest green offer and switch us if we overpay by '
          'more than €10 a month.',
      'group': 'Home',
      'first_step': 'Let me schedule it for next September.',
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
          'age': Duration(days: 4),
          'note': 'Week 1 done, all three runs easy',
          'progress': '8 %',
        },
        {
          'age': Duration(days: 2),
          'note': 'Week 2 done, knee tight after long run',
          'progress': '15 %',
        },
      ],
    },
    {
      'id': 'goal-ava-2',
      'title': 'Lower the electricity bill',
      'category': 'finance',
      'why': 'Stop overpaying a renewal that crept up 29 %.',
      'target_date': '2026-10-10',
      'status': 'tracking',
      'age': Duration(days: 6),
      'timeline': [
        {
          'age': Duration(days: 6),
          'note': 'Renewal opened: €0.24/kWh',
          'progress': '€98 / month',
        },
        {
          'age': Duration(hours: 12),
          'note': 'Switched to Lumen Pure at €0.18/kWh',
          'progress': '€76 / month',
        },
      ],
    },
  ],
  artifacts: [
    {
      'id': 'art-ava-1',
      'title': 'Electricity — comparison and switch',
      'kind': 'document',
      'file': 'comparisons/electricity-switch.md',
      'size': 3280,
      'tags': ['home', 'electricity'],
      'age': Duration(hours: 12),
    },
    {
      'id': 'art-ava-2',
      'title': 'Annecy — weekend plan',
      'kind': 'document',
      'file': 'trips/annecy-weekend.md',
      'size': 4150,
      'tags': ['travel', 'annecy'],
      'age': Duration(hours: 20),
    },
    {
      'id': 'art-ava-3',
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
          'Léa hands over boring admin without a second thought when the '
          'result is concrete — the electricity switch took one message. '
          'Trips are where she lights up; the Annecy weekend is the third '
          'one this year. Keep Sunday check-ins short: she answers faster '
          'when there is one question, not three.',
    },
  ],
  files: {
    'IDENTITY.md':
        '# Ava\n\nPersonal assistant of Léa. Warm, brief, never pushy. '
        'Answers in the language of the question.',
    'FEED_PROMPT.md':
        'Follow: household admin and prices, weekend trips from Lyon, '
        'running. At most three posts a day, concrete news only.',
    'HEARTBEAT.md':
        '# Heartbeat\n\nEvery morning at 07:30: calendar check, weather, '
        'one suggestion for the day.',
    'PREFERENCES.md':
        '# Preferences\n\n- No messages after 22:00\n- Prefer trains under '
        '4 hours\n- Vegetarian most days\n- Reads French and English bills',
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
      DemoRow.user('Which AI am I talking to right now, actually?'),
      DemoRow.agent(
        'This chat runs on **the ChatGPT subscription your team already '
        'has** — same login as your other tools, nothing new to pay for. '
        'You can switch it to another subscription any time, per chat.',
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
