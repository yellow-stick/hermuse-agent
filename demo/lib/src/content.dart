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
      job = null,
      age = null,
      args = const {};

  const DemoRow.agent(this.text, {this.reasoning, this.age})
    : role = 'assistant',
      tool = null,
      job = null,
      args = const {};

  /// A finished tool call; [text] is the summary its row shows. Browser
  /// calls (`browser_*`) also carry their [args] (page URL, element text),
  /// like the live transcript does.
  const DemoRow.tool(String this.tool, this.text, {this.args = const {}})
    : role = 'tool',
      reasoning = null,
      job = null,
      age = null;

  /// The output of the scheduled [job] handed to the main chat, as Hermes
  /// stores it: a user row starting `[Cronjob "<name>" output — `.
  const DemoRow.brief(String this.job, String output, {this.age})
    : role = 'user',
      text =
          '[Cronjob "$job" output — scheduled job, not the user. Review it, '
          'act on anything that needs action, and summarize for the chat.]'
          '\n\n$output',
      reasoning = null,
      tool = null,
      args = const {};

  /// Hermes transcript role: `user`, `assistant` or `tool`.
  final String role;
  final String text;
  final String? reasoning;
  final String? tool;

  /// Name of the scheduled job of a [DemoRow.brief] row.
  final String? job;

  /// Time from this row to page load; null for a row 40 s before the next.
  final Duration? age;

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
    required this.tasks,
    required this.memory,
    required this.userMemory,
    required this.soul,
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

  /// Recorded tasks (`GET /tasks`), newest first, each with an `age`
  /// (finished that long before page load) and a `took` ([Duration]).
  final List<Map<String, Object?>> tasks;

  /// Entries of the agent's `MEMORY.md` and `USER.md` (`GET /memory/…`).
  final List<String> memory;
  final List<String> userMemory;

  /// The default profile's SOUL.md (`profiles.describe`).
  final String soul;

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
      DemoRow.brief(
        'Evening recap',
        'Done today: Annecy hotel booked (€270, free cancellation until '
            'Thursday), nightly to-do list scheduled for 02:00. Tomorrow: sign '
            'the school trip form. Open: the Voltia renewal letter.',
      ),
      DemoRow.agent(
        'Quick evening recap:\n\n'
        '- **Annecy:** the Hôtel du Lac is booked, free cancellation until '
        'Thursday.\n'
        '- **Tomorrow:** sign the school trip form — it is pre-filled.\n'
        '- **Still open:** the Voltia renewal letter. Want me to look at it '
        'in the morning?',
        age: Duration(hours: 15, minutes: 29),
      ),
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
    ],
  ),
  sideChats: [
    DemoChat(
      id: '20260930_021048_ava010',
      title: 'Night pass — emails + code',
      age: Duration(hours: 7),
      rows: [
        DemoRow.agent(
          'Night shift done — emails and code, while you slept '
          '(Email: connected, GitHub: connected):\n\n'
          '- **Read 18 new emails**, answered 2, skipped 3 newsletters.\n'
          '- **Reviewed 6 commits** on `lea/home-admin`: 1 failing test in '
          'checkout (`cart_test.dart`), 2 TODOs left.\n'
          '- **Lumen Pure: switch confirmed** — €0.18/kWh from Friday.\n'
          '- **School trip form due Friday** — pre-filled, needs your '
          'signature.\n'
          '- **Dentist moved to Thursday 9:30** — calendar updated.\n\n'
          'Nothing else needed you. Your to-do list is in your Feed.',
          reasoning:
              'Nightly pass over the connected mailbox and the day’s pushes: '
              'triage, review, act on what is actionable, report the rest '
              'in the morning feed.',
        ),
      ],
    ),
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
      id: '20260929_220412_ava011',
      title: 'Nightly to-do list',
      age: Duration(hours: 11),
      rows: [
        DemoRow.user(
          "I'm swamped. Every night, go through my emails and what I "
          'pushed today, and give me a clean to-do list for tomorrow at 7.',
        ),
        DemoRow.tool(
          'cronjob',
          'Nightly at 02:00: inbox + commits review, recap at 07:00',
        ),
        DemoRow.agent(
          'Scheduled — every night at **02:00** I go through your emails '
          'and what you pushed that day (Email: connected, GitHub: '
          'connected), and your recap with the to-do list is in your Feed '
          'at **07:00**.',
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
      'id': 'feed-ava-0',
      'title': 'Your day — 4 things',
      'topic': 'Overnight',
      'body':
          'From last night’s pass (18 emails, 6 commits reviewed):\n\n'
          '- ☐ Sign the school trip form (pre-filled, **due Friday**)\n'
          '- ☐ Fix the failing checkout test (`cart_test.dart`)\n'
          '- ☐ Reply to Marc about the invoice\n'
          '- ☑ Dentist moved to Thu 9:30 — nothing to do',
      'sources': <String>[],
      'why':
          'You asked for a clean to-do list every morning from the nightly '
          'inbox and commits review.',
      'image_url': null,
      'age': Duration(hours: 1),
      'reactions': {'love': ''},
    },
    {
      'id': 'feed-ava-2',
      'title': 'Annecy this weekend: sun, 19 °C',
      'topic': 'Weekend',
      'body':
          '## Forecast\n\n'
          'Clear skies over the lake Saturday and Sunday, water still '
          '**19 °C**.\n\n'
          '## Your bookings\n\n'
          '- Hôtel du Lac: booked, free cancellation until Thursday\n'
          '- Trains: holding at **€29** — I tell you if they drop below €25\n\n'
          'Details in the [weather report]'
          '(https://example.com/meteo/annecy-weekend).',
      'sources': ['https://example.com/meteo/annecy-weekend'],
      'why':
          'Your Annecy weekend is in three days and swimming depends on the '
          'weather.',
      'image_url': null,
      'age': Duration(hours: 3),
      'reactions': <String, Object?>{},
    },
    {
      'id': 'feed-ava-3',
      'title': 'Week 3 of your half-marathon plan',
      'topic': 'Running',
      'body':
          'Two weeks done, **15 %** of the way there. This week:\n\n'
          '1. Easy 6 km on Tuesday\n'
          '2. Strides on Thursday\n'
          '3. 9 km flat on Sunday while the knee settles\n\n'
          'Check-in Sunday evening as usual.',
      'sources': <String>[],
      'why': 'You are tracking the Lyon half-marathon goal with me.',
      'image_url': null,
      'age': Duration(hours: 4),
      'reactions': <String, Object?>{},
    },
    {
      'id': 'feed-ava-4',
      'title': 'Lyon water bill goes up in January',
      'topic': 'Household',
      'body':
          'The city voted a **+6 %** water tariff from January 1st. For your '
          'flat that is about €2 more a month — nothing to do, I just keep '
          'it in the yearly budget.',
      'sources': ['https://example.com/lyon/water-tariff-2027'],
      'why': '',
      'image_url': null,
      'age': Duration(days: 1, hours: 2),
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
      'icon': 'travel',
      'seeded': false,
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
      'icon': 'money',
      'seeded': false,
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
      'done': false,
      'source': 'user',
      'status_line': 'Week 3 of 12 · 15 %',
      'parent_id': null,
      'cron_job_id': 'ava-half-marathon-checkin',
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
      'done': false,
      'source': 'agent',
      'status_line': 'Switched: €76 a month, was €98',
      'parent_id': null,
      'cron_job_id': null,
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
    {
      'id': 'goal-ava-1-strength',
      'title': 'Hip and glute strength twice a week',
      'category': 'health',
      'why': 'Keeps the knee happy while the mileage grows.',
      'target_date': '',
      'status': 'tracking',
      'done': false,
      'source': 'user',
      'status_line': '1 of 2 sessions this week',
      'parent_id': 'goal-ava-1',
      'cron_job_id': null,
      'age': Duration(days: 2),
      'timeline': <Object?>[],
    },
    {
      'id': 'goal-ava-1-shoes',
      'title': 'Buy road shoes before week 4',
      'category': 'health',
      'why': '',
      'target_date': '2026-10-05',
      'status': 'done',
      'done': true,
      'source': 'user',
      'status_line': 'Bought on Saturday',
      'parent_id': 'goal-ava-1',
      'cron_job_id': null,
      'age': Duration(days: 5),
      'timeline': <Object?>[],
    },
    {
      'id': 'goal-ava-3',
      'title': 'Lyon → Annecy trains under €25',
      'category': 'travel',
      'why': 'You asked me to tell you when the fares drop.',
      'target_date': '2026-10-09',
      'status': 'tracking',
      'done': false,
      'source': 'agent',
      'status_line': 'Cheapest today: €29 each way',
      'parent_id': null,
      'cron_job_id': 'ava-train-fares',
      'age': Duration(hours: 20),
      'timeline': [
        {'age': Duration(hours: 2), 'note': 'Checked fares', 'progress': '€29'},
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
        '# Heartbeat\n\nEvery 30 minutes: check the calendar, the inbox '
        '(Email: connected) and the price watches; message Léa only when '
        'something needs her.',
    'PREFERENCES.md':
        '# Preferences\n\n- No messages after 22:00\n- Prefer trains under '
        '4 hours\n- Vegetarian most days\n- Reads French and English bills',
  },
  tasks: [
    {
      'id': 'task-ava-1',
      'session_id': '20260930_074512_ava000',
      'turn_id': 't1',
      'title': 'Switch the electricity contract',
      'summary': 'Switched to Lumen Pure at €0.18/kWh, saving €22 a month',
      'status': 'completed',
      'source': 'chat',
      'tools': [
        'read_file',
        'browser_navigate',
        'browser_click',
        'browser_type',
      ],
      'age': Duration(minutes: 12),
      'took': Duration(minutes: 6),
    },
    {
      'id': 'task-ava-2',
      'session_id': '20260930_074512_ava000',
      'turn_id': 'hb-0930',
      'title': 'Morning check',
      'summary': 'Calendar clear until the dentist on Thursday; sunny, 17 °C',
      'status': 'completed',
      'source': 'heartbeat',
      'tools': ['web_search', 'memory'],
      'age': Duration(hours: 2, minutes: 28),
      'took': Duration(minutes: 1),
    },
    {
      'id': 'task-ava-3',
      'session_id': '20260930_021048_ava010',
      'turn_id': 'night-0930',
      'title': 'Nightly inbox and commits review',
      'summary': '18 emails read, 2 answered; 1 failing test found',
      'status': 'completed',
      'source': 'cron',
      'tools': ['terminal', 'web_extract', 'memory'],
      'age': Duration(hours: 7),
      'took': Duration(minutes: 9),
    },
    {
      'id': 'task-ava-4',
      'session_id': '20260929_220412_ava011',
      'turn_id': 't1',
      'title': 'Schedule the nightly to-do list',
      'summary': 'Nightly review at 02:00, recap in the Feed at 07:00',
      'status': 'completed',
      'source': 'chat',
      'tools': ['cronjob'],
      'age': Duration(hours: 11),
      'took': Duration(seconds: 40),
    },
    {
      'id': 'task-ava-5',
      'session_id': '',
      'turn_id': 'fares-0929',
      'title': 'Check Lyon → Annecy train fares',
      'summary': 'The fare site timed out; retrying at the next run',
      'status': 'failed',
      'source': 'cron',
      'tools': ['browser_navigate'],
      'age': Duration(hours: 14),
      'took': Duration(minutes: 2),
    },
    {
      'id': 'task-ava-6',
      'session_id': '20260929_183002_ava001',
      'turn_id': 't2',
      'title': 'Book the Hôtel du Lac',
      'summary': 'Two nights, €270 with breakfast, free cancellation',
      'status': 'completed',
      'source': 'chat',
      'tools': ['browser_navigate', 'browser_type'],
      'age': Duration(hours: 20),
      'took': Duration(minutes: 4),
    },
    {
      'id': 'task-ava-7',
      'session_id': '20260929_183002_ava001',
      'turn_id': 't1',
      'title': 'Plan a weekend in Annecy',
      'summary': 'Train + lakeside hotel, about €360 for two',
      'status': 'completed',
      'source': 'chat',
      'tools': ['web_search', 'web_search', 'web_search'],
      'age': Duration(hours: 20, minutes: 30),
      'took': Duration(minutes: 3),
    },
    {
      'id': 'task-ava-8',
      'session_id': '20260928_064418_ava002',
      'turn_id': 't2',
      'title': 'Ease the plan for a tight knee',
      'summary': 'Long run cut to 9 km, strength work added',
      'status': 'completed',
      'source': 'chat',
      'tools': ['memory'],
      'age': Duration(days: 2),
      'took': Duration(minutes: 1),
    },
    {
      'id': 'task-ava-9',
      'session_id': '20260928_064418_ava002',
      'turn_id': 't1',
      'title': 'Build a half-marathon plan',
      'summary': 'Stopped before the plan was saved',
      'status': 'interrupted',
      'source': 'chat',
      'tools': ['web_search', 'cronjob'],
      'age': Duration(days: 2, hours: 1),
      'took': Duration(minutes: 2),
    },
  ],
  memory: [
    'Léa’s electricity is with Lumen Pure since Sept 30, €0.18/kWh.',
    'Nightly review runs at 02:00; the recap goes to the Feed at 07:00.',
    'Half-marathon plan: three runs a week, long run on Sunday.',
    'Fare site watto.example times out at night: retry after 06:00.',
  ],
  userMemory: [
    'Léa lives in Lyon with her partner and one child at primary school.',
    'Prefers trains under 4 hours, never flies for weekends.',
    'Vegetarian most days.',
    'Left knee gets tight after long runs.',
    'No messages after 22:00.',
  ],
  soul:
      '# Ava\n\n'
      'You are Ava, the personal assistant of Léa, in Lyon.\n\n'
      '## How you work\n\n'
      '- Act first on boring admin, then report what you did.\n'
      '- Keep answers short: one question at a time.\n'
      '- Answer in the language of the question.\n\n'
      '## Never\n\n'
      '- Message after 22:00.\n'
      '- Pay for anything without asking.',
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
      'why':
          'Slack alerts came up in last week’s interviews; you follow '
          'competitors.',
      'image_url': null,
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
      'icon': 'people',
      'seeded': false,
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
      'done': false,
      'source': 'user',
      'status_line': 'Median setup: 6 days, target 3',
      'parent_id': null,
      'cron_job_id': null,
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
    'HEARTBEAT.md':
        '# Heartbeat\n\nEvery 30 minutes during work hours: check new '
        'customer emails and competitor news; message only when something '
        'needs you.',
    'PREFERENCES.md': '# Preferences\n\n- Work hours only (09:00–18:00)',
  },
  tasks: [
    {
      'id': 'task-atl-1',
      'session_id': '20260930_090301_atl000',
      'turn_id': 't3',
      'title': 'Draft the Slack alerts one-pager',
      'summary': 'Saved to the Library: problem, three alerts, two sprints',
      'status': 'completed',
      'source': 'chat',
      'tools': ['write_file'],
      'age': Duration(hours: 1, minutes: 5),
      'took': Duration(minutes: 2),
    },
    {
      'id': 'task-atl-2',
      'session_id': '20260929_140922_atl001',
      'turn_id': 't1',
      'title': 'Scan competitor seat pricing',
      'summary': 'Two of three competitors give read-only seats away',
      'status': 'completed',
      'source': 'chat',
      'tools': ['web_search', 'web_search', 'web_search'],
      'age': Duration(days: 1),
      'took': Duration(minutes: 3),
    },
  ],
  memory: [
    'Product review is every Thursday at 14:00.',
    'Interview notes live in interviews/YYYY-MM-DD.md.',
  ],
  userMemory: [
    'Otto’s user leads product at a B2B analytics startup.',
    'Wants sources cited, bullet points over prose.',
  ],
  soul:
      '# Otto\n\n'
      'You are Otto, a work assistant for a product lead.\n\n'
      '- Cite your sources.\n'
      '- Write short bullet points.\n'
      '- Work hours only: 09:00–18:00.',
);

/// The Hermuse plugin's starter catalog (`store.SEED_IDEAS`), offered on
/// every instance after its own ideas.
const demoSeedIdeas = [
  {
    'id': 'seed-inbox-triage',
    'title': 'I’ll sort your inbox every morning',
    'pitch':
        'Each morning I go through new mail, flag what needs you today, '
        'draft replies for the quick ones and summarise the rest in one '
        'message.',
    'group': 'Productivity',
    'icon': 'inbox',
    'first_step':
        'Tell me which mailbox to watch and what counts as urgent for you.',
  },
  {
    'id': 'seed-paperwork',
    'title': 'I’ll keep track of your paperwork deadlines',
    'pitch':
        'Renewals, tax forms, insurance and subscriptions: I keep a list of '
        'what is due when and remind you early enough to act calmly.',
    'group': 'Productivity',
    'icon': 'documents',
    'first_step': 'List the documents or contracts you worry about forgetting.',
  },
  {
    'id': 'seed-workout-plan',
    'title': 'I’ll plan your workouts around your week',
    'pitch':
        'I build a weekly training plan that fits your schedule and level, '
        'check in after each session and adjust the next ones.',
    'group': 'Health & Fitness',
    'icon': 'workout',
    'first_step': 'Tell me your goal, your level and the days you can train.',
  },
  {
    'id': 'seed-health-checkups',
    'title': 'I’ll remind you of check-ups and refills',
    'pitch':
        'Dentist, eye exam, vaccines, prescriptions: I track when each one '
        'is due and nudge you before it slips.',
    'group': 'Health & Fitness',
    'icon': 'health',
    'first_step':
        'Share your last check-up dates and any regular prescriptions.',
  },
  {
    'id': 'seed-price-watch',
    'title': 'I’ll watch prices on things you want to buy',
    'pitch':
        'Give me the items you are eyeing; I check prices regularly and '
        'tell you when one drops or a better deal shows up.',
    'group': 'Shopping',
    'icon': 'shopping',
    'first_step': 'Name one item and the price you would happily pay.',
  },
  {
    'id': 'seed-returns',
    'title': 'I’ll make sure you never miss a return window',
    'pitch':
        'When you buy something you are unsure about, I note the return '
        'deadline and remind you a few days before it closes.',
    'group': 'Shopping',
    'icon': 'returns',
    'first_step': 'Tell me about a recent purchase you might send back.',
  },
  {
    'id': 'seed-budget-check',
    'title': 'I’ll give you a weekly spending check-in',
    'pitch':
        'Once a week I go over what you tell me you spent, compare it with '
        'your budget and point out anything worth adjusting.',
    'group': 'Money',
    'icon': 'money',
    'first_step':
        'Tell me your monthly budget and the categories you care about.',
  },
  {
    'id': 'seed-birthdays',
    'title': 'I’ll remember birthdays and suggest gifts',
    'pitch':
        'I keep the important dates of the people you care about and remind '
        'you a week ahead with a few gift or message ideas.',
    'group': 'Relationships',
    'icon': 'people',
    'first_step': 'Give me three people and their birthdays to start with.',
  },
  {
    'id': 'seed-trip-planner',
    'title': 'I’ll plan your next trip with you',
    'pitch':
        'From dates and budget to bookings and a day-by-day plan, I research '
        'options, keep track of what is booked and what is still open.',
    'group': 'Travel',
    'icon': 'travel',
    'first_step': 'Tell me where you would like to go and roughly when.',
  },
  {
    'id': 'seed-local-events',
    'title': 'I’ll find things to do in your city each week',
    'pitch':
        'Every week I look for concerts, markets, exhibitions and events '
        'near you that match your interests, and share a short pick.',
    'group': 'Home & city',
    'icon': 'city',
    'first_step': 'Tell me your city and what you enjoy doing.',
  },
];

/// One past run of a [DemoJob]: whether it ended well and the start of
/// what it answered.
final class DemoRun {
  const DemoRun(this.output, {this.ok = true});
  final String output;
  final bool ok;
}

/// One demo Hermes cron job, server time: every day (`weekday` null) or
/// once a week (`weekday` 1 = Monday … 7 = Sunday) at `hour`:00; every
/// [everyMinutes] ([DemoJob.every]); or once, [onceInDays] days after page
/// load at `hour`:00 ([DemoJob.once]).
final class DemoJob {
  const DemoJob({
    required this.id,
    required this.name,
    required this.hour,
    this.weekday,
    this.hermuseKey,
    this.runs = const [],
  }) : everyMinutes = null,
       onceInDays = null;

  const DemoJob.every({
    required this.id,
    required this.name,
    required int minutes,
    this.hermuseKey,
    this.runs = const [],
  }) : everyMinutes = minutes,
       hour = 0,
       weekday = null,
       onceInDays = null;

  const DemoJob.once({
    required this.id,
    required this.name,
    required int inDays,
    required this.hour,
  }) : onceInDays = inDays,
       weekday = null,
       hermuseKey = null,
       everyMinutes = null,
       runs = const [];

  final String id;
  final String name;
  final int hour;
  final int? weekday;
  final int? everyMinutes;
  final int? onceInDays;

  /// The Hermuse plugin schedule it belongs to (`feed`, `ideas`, …,
  /// `heartbeat`); null for the user's own jobs.
  final String? hermuseKey;

  /// Past runs, newest first, one per previous slot.
  final List<DemoRun> runs;

  /// The cron expression (`0 8 * * *`, `0 9 * * 1`).
  String get cron => '0 $hour * * ${weekday == null ? '*' : weekday! % 7}';
}

/// The Hermuse plugin's jobs, on every demo instance: the heartbeat (listed)
/// and the maintenance jobs (hidden by the app).
const demoHermuseJobs = [
  DemoJob.every(
    id: 'hermuse-heartbeat',
    name: 'Heartbeat',
    minutes: 30,
    hermuseKey: 'heartbeat',
    runs: [
      DemoRun('Nothing needed you.'),
      DemoRun('Calendar clear until the dentist on Thursday; sunny, 17 °C.'),
      DemoRun('Nothing needed you.'),
    ],
  ),
  DemoJob(
    id: 'hermuse-feed',
    name: 'Hermuse feed (daily)',
    hour: 8,
    hermuseKey: 'feed',
  ),
  DemoJob(
    id: 'hermuse-ideas',
    name: 'Hermuse ideas (weekly)',
    hour: 9,
    weekday: 1,
    hermuseKey: 'ideas',
  ),
  DemoJob(
    id: 'hermuse-goals',
    name: 'Hermuse goals check-in (weekly)',
    hour: 9,
    weekday: 7,
    hermuseKey: 'goals',
  ),
  DemoJob(
    id: 'hermuse-reflection',
    name: 'Hermuse reflection (nightly)',
    hour: 2,
    hermuseKey: 'reflection',
  ),
];

/// The user's own jobs, by instance id.
const demoUserJobs = {
  '6f1c2a4e-8d3b-4c7a-9e21-5b0d7f3a1c01': [
    DemoJob(
      id: 'ava-evening-recap',
      name: 'Evening recap',
      hour: 18,
      runs: [
        DemoRun(
          'Done today: Annecy hotel booked (€270, free cancellation until '
          'Thursday), nightly to-do list scheduled for 02:00. Tomorrow: sign '
          'the school trip form. Open: the Voltia renewal letter.',
        ),
        DemoRun('Quiet day: nothing pending, the trains are still at €29.'),
      ],
    ),
    DemoJob(
      id: 'ava-nightly-review',
      name: 'Nightly inbox and commits review',
      hour: 2,
      runs: [
        DemoRun(
          '18 emails read, 2 answered, 3 newsletters skipped. 6 commits '
          'reviewed: 1 failing test in checkout (cart_test.dart).',
        ),
        DemoRun('Could not reach the mail server; retried twice.', ok: false),
        DemoRun('11 emails read, 1 answered. No new commits.'),
      ],
    ),
    DemoJob(
      id: 'ava-half-marathon-checkin',
      name: 'Half-marathon check-in',
      hour: 19,
      weekday: 7,
      runs: [
        DemoRun('Week 2 done. Knee tight: long run cut to 9 km this week.'),
        DemoRun('Week 1 done, all three runs felt easy.'),
      ],
    ),
    DemoJob.every(
      id: 'ava-train-fares',
      name: 'Watch Lyon → Annecy train fares',
      minutes: 360,
      runs: [
        DemoRun('Cheapest fare still €29 each way.'),
        DemoRun('The fare site timed out.', ok: false),
      ],
    ),
    DemoJob.once(
      id: 'ava-school-form',
      name: 'Remind me to sign the school trip form',
      inDays: 1,
      hour: 8,
    ),
  ],
};
