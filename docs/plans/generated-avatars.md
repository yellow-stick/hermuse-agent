# Custom agents with generated portraits and animations; Feed image fallback

Goal: a user can create an agent from a description: the server generates
portrait candidates, the user picks one, and the server generates the agent's
state animations (idle, thinking, replying, working) from that portrait, so a
custom agent is as alive as the bundled Hermuse one. A Feed post whose source
has no share image gets a generated illustration. Generation goes through an
image/video API the user runs (first provider: ContentFlow, which drives
Google Flow in a signed-in browser). Nothing works without it; the apps say
so honestly.

## Provider: ContentFlow (`docs` in its README)

- `GET /image`, `GET /video`: catalogue, `credits`, per-model `usages[]`
  with `credits` per generation (images 0 on the test account; Omni 1.1 Flash
  4 s video 7 credits).
- `POST /image {prompt, model, aspect_ratio, count 1-4}` → `{media:[{id, status, url}]}`
  (~15 s). `url` is signed and expires: download immediately.
- `POST /video {prompt, model: "Omni 1.1 Flash", aspect_ratio: "16:9", duration: 4, count: 1, first_frame: <image media id>}`
  → `{media:[{id, status: scheduled|pending}]}`; poll `POST /video {action: "status", media_id}` every ~5 s
  until `success` (`url`) / `failed` / `canceled` (~30 s).
- Errors: HTTP 4xx/5xx with `{error, details}`; e.g. `WafRejectionError`
  (`PUBLIC_ERROR_UNUSUAL_ACTIVITY`). **Never resubmit after an error** (credits
  may be spent twice). Requests are serialised by the service; send one at a time.
- No `Origin` header (refused), `Authorization: Bearer <token>` when configured.

## Plugin contract (prefix `/api/plugins/hermuse`)

### Media provider (server-wide, not per profile)

Stored in the default profile's `hermuse/media.json` (mode 0600); env
`HERMUSE_MEDIA_ENDPOINT` / `HERMUSE_MEDIA_TOKEN` override it.

- `GET /media/config` → `{provider: "contentflow", endpoint: str, has_token: bool, image_model: str, video_model: str, feed_fallback: bool, from_env: bool}`
- `PUT /media/config` body `{endpoint, token?, image_model?, video_model?, feed_fallback?}` (empty endpoint disables; token omitted = unchanged, "" = clear) → same as GET.
- `GET /media/status` → `{configured: bool, reachable: bool, credits: int|null, video_cost: int|null, error: str|null}` (`video_cost` = credits per animation clip with the configured video model).

### Avatar (per profile, files under `<profile home>/hermuse/avatar/`)

- `GET /avatar` → `Avatar = {portrait_url: str|null, states: {<state>: url}, job: Job|null, updated_at: iso|null}`.
- `POST /avatar/portrait` body `{description: str (1..1000), count?: 1..4 (default 4)}` → `202 Job` (kind `portrait`).
- `POST /avatar/select` body `{candidate: int}` (index into the finished portrait job's candidates) → `Avatar`. Writes `portrait.jpg` (the 16:9 generation kept for animation) and `portrait-square.jpg` (centre square, 512 px) and clears old states.
- `POST /avatar/animate` body `{states?: [str]}` (default `["idle","thinking","replying","working"]`) → `202 Job` (kind `animate`); refused with `409` while a job runs, `422` without a portrait.
- `GET /avatar/jobs/{id}` → `Job = {id, kind, status: running|done|failed, candidates: [url], states: {<state>: queued|running|done|failed}, error: str|null, started_at, finished_at}`.
- `DELETE /avatar` → `{ok: true}` (back to a bundled portrait).
- Binary: `GET /avatar/portrait` (square JPEG), `GET /avatar/candidates/{job}/{n}` (JPEG), `GET /avatar/states/{state}` (animated WebP, 256×256, looping).

Generation rules:
- Portrait prompt from the description plus fixed framing: one character,
  head and shoulders, centred with generous headroom and margins, facing the
  camera, plain uniform light background, soft studio light, no text. Aspect
  16:9 (the video model keeps the first frame's framing; the square is cut
  from the centre for display).
- Each state clip starts from the selected portrait (`first_frame` = its media
  id, re-uploaded if expired) with a locked-off camera, same background, start
  and end in the neutral pose: `idle` breathing and blinking, **mouth closed,
  no talking, no lip movement**; `thinking` looks up, small head tilt, mouth
  closed; `replying` speaks expressively; `working` focused small gestures,
  mouth closed.
- Export with ffmpeg (shipped on servers set up by Hermuse): the same centre
  square crop for every state, 256×256, 20 fps, loop with a 0.4 s tail-to-head
  crossfade, animated WebP ~0.5-1 MB; silent.
- One job at a time per profile, run on a background thread; each clip is
  submitted once; a failed clip marks its state `failed` and the job goes on
  with the next state; nothing is retried automatically.

### Feed fallback

When a post has no image (`feed_images.find_post_image` → None), the media
provider is configured and `feed_fallback` is on: the post is stored at once,
and a background thread generates one 16:9 editorial illustration from the
title and `why` (no text, no logos, no real person's likeness), stores it as
the post's image and leaves the post untouched on failure.

## App side

- `ui_meta.hermuse.avatar_id = "custom"` marks a generated portrait;
  `AgentAvatar.byId("custom")` is a custom avatar resolved from the plugin
  (portrait + state animations) instead of a bundled asset. States the agent
  has no clip for fall back: searching/reading/coding/browsing/magic-action →
  working; awaiting-user/connecting/paused → idle; any missing → portrait.
  Animation follows the same rules as Hermuse (reduced motion → portrait).
- Agent editor (both apps): besides the bundled portraits, **Generate**:
  description → candidates grid → pick → **Animate** with the cost line
  ("4 animations · 28 credits") and per-state progress; the agent can be
  saved with the portrait before animations finish.
- Settings → **Image generation**: endpoint, token, Test (status: reachable,
  credits), "Illustrate Feed posts without an image" toggle. Not configured:
  one line explaining that generation needs a ContentFlow service.
