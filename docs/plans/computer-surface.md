# Computer surface (écran VM visible) — spec + résultats de spike

Date : 2026-09-27. Statut : spike validé, rien à merger (aucun code modifié).

But : offrir le trio `Open browser` / `Take control` / `Stop task` sur
Hermuse :
l'utilisateur **voit** le navigateur de l'agent dans le chat et peut
**reprendre la main**. Scope = browser de la VM, pas bureau GNOME complet
en P0 (le full desktop XFCE est l'extension P2).

## 1. Topologie retenue (imposée par l'existant)

Hermes ne tourne pas forcément sur la machine du client (web/desktop/mobile).
Donc la sandbox suit **l'upstream Hermes**, jamais le client :

```text
[Hermes host]                          [Relay]                         [Clients]
 plugin hermuse_computer ──loopback──▶ Chromium/VNC container
   │  /api/plugins/hermuse_computer/*      │  /hermes/<id>/api/plugins/… (HTTP+WS, jar existant)
   └──────────────────────────────────────▶ forward générique ─────────▶ ComputerView (feed)
```

- **Host Hermes** : nouveau plugin `hermuse_computer` (séparé de `hermuse`,
  qui reste product layer Feed/Ideas/Goals). Il pilote le container et expose
  le stream + l'input. Même auth dashboard que
  `hermes-plugin/hermuse/dashboard/plugin_api.py`.
- **Relay** (`apps/hermuse_relay/lib/src/server.dart`) : **aucun changement
  de code requis**. `proxy()` + `upstreamTarget()` forwardent déjà tout
  `/hermes/<id>/*`, et `_proxyWs()` bridge déjà les WS avec check `Origin` +
  cookies du jar côté upstream, sans `Origin` vers l'amont (lignes 360-426).
  Le WS de stream passe par ce tuyau tel quel.
- **Clients** : nouveau `ComputerBlock` dans
  `packages/hermuse_chat/lib/src/models.dart` (le `sealed class Block` s'étend
  d'un cas), état dans `controller.dart`, rendu `ComputerView` dans
  `apps/hermuse_app` (Flutter) + `apps/hermuse_web` (Jaspr). `hermuse_chat`
  reste sans networking (cf. son README) : le transport vit derrière le
  controller, comme l'existant.

## 2. Ce que les spikes ont prouvé (chiffres réels, machine locale)

Exécuté le 2026-09-27 sur cette machine (Docker 29.8.1, Playwright + chromium
1223/1243, `google-chrome` + `chromium-browser`, `Xvfb`, `DISPLAY=:1` présent).

### 2.1 Chromium + CDP en local — OK

- `page.screenshot(type=jpeg, quality=70)` sur example.com en 1280×800 :
  **15 831 octets**. Ordre de grandeur par frame : 5–20 Ko en q60/800px.
- `Page.captureScreenshot` via CDP : ~19 280 car. base64 ≈ **14,4 Ko**. OK.
- `Page.startScreencast` : **0 frame sur page statique** (2,5 s d'attente),
  puis **4 frames dès qu'il y a activité** (scroll + navigation), première
  frame ~5 480 car. base64 ≈ **4 Ko** ; en headful Xvfb pareil (4 frames).
  Conséquence archi : le screencast CDP n'émet que sur repaint. Pour un
  framerate constant, faire du **polling `captureScreenshot` à 2–5 fps**
  côté daemon (simple, prévisible), pas du screencast événementiel.
- Budget bande passante : 2 fps × ~10 Ko ≈ **20–30 Ko/s** ; 5 fps ≈ 75 Ko/s.
  Throttle + pause quand l'onglet est caché (exigence widget).

### 2.2 Image `opensandbox/chrome:latest` — VNC OK, CDP à corriger

- Pull OK (`Digest: sha256:507a6c90…`), contient `/chrome.sh`, `Xtigervnc`,
  `chromium 143.0.7499.109`.
- `Xtigervnc :1 -geometry 1280x800 -depth 24 -rfbport 5901 -SecurityTypes None`
  + `DISPLAY=:1 chromium … --remote-debugging-port=9222` : les deux process
  tournent (vérifié `ps`).
- Handshake RFB brut (socket, sans lib) : `RFB 003.008`, 1 type sécu `0x01`
  (None), `SecurityResult=0`, `ServerInit` **1280×800**, `nrect=19` rects RAW,
  ~1,5 Mo pour 6 rects (frame complète ≈ 4 Mo en RAW). **Le framebuffer est
  lisible ; en prod il faut Tight/ZRLE ou noVNC**, le RAW est inutilisable
  sur le réseau (~4 Mo/frame).
- Point bloquant identifié (pas bloquant pour la spec) : Chrome loggue
  `DevTools listening on ws://127.0.0.1:9222/…` **même avec**
  `--remote-debugging-address=0.0.0.0` (flag ignoré par ce build) ; le port
  mappé hôte `19222→9222` répond vide/reset depuis l'hôte. Fixes possibles :
  `socat TCP-LISTEN:9223,fork TCP:127.0.0.1:9222` dans le container, ou CDP via
  `docker exec`, ou passer par le serveur OpenSandbox + SDK (proxy `execd`).
  À trancher en P1, pas en P0.
- `vncdotool` inutilisable ici (install Twisted OK mais handshake bloqué 60 s
  dans cet env) — d'où le probe RFB brut `/tmp/rfb_probe.py` (jetable, hors
  repo). En prod : lib VNC sérieuse ou noVNC, pas vncdotool.

### 2.3 Relay — OK sans toucher au code

- `dart test` dans `apps/hermuse_relay` : **18/18 passent**, dont le WS echo
  via `FakeUpstream` (`/ws`). Le bridge WS générique couvre déjà le futur
  `/hermes/<id>/api/plugins/hermuse_computer/stream`.
- CSRF `Origin` (`_checkCsrf`) + `allowedOrigins` + jar 12 h idle : réutilisés
  tels quels. Contrainte OpenSandbox multi-tenant confirmée par leur doc
  (header `OPEN-SANDBOX-API-KEY` impossible à injecter depuis un navigateur) :
  notre jar serveur-side la résout déjà par construction — NEVER mettre de clé
  dans l'URL noVNC.

## 3. Contrats proposés

### 3.0bis Addendum 2026-09-27 — fonctionner SANS Docker (spike validé)

Contexte : Docker n'est pas toujours présent sur le host Hermes (petit NAS,
machine contrainte). Trois voies sans Docker testées sur cette machine
(Pop!_OS, kernel cgroups hybride `systemd.unified_cgroup_hierarchy=0`,
bwrap 0.11.0, podman 4.9.3, firejail 0.9.72, google-chrome stable).

#### Verdict : Firejail (retenu) > Podman rootless (fallback) > bwrap (écarté)

- **Firejail ✅ retenu pour le mode sans-Docker.** Commande validée :
  `firejail --noprofile --quiet --noblacklist=/proc --disable-mnt -- <chrome>
  --user-data-dir=<profil-dédié> --remote-debugging-port=<port> --headless=new`.
  Chrome démarre **avec son sandbox interne intact** (pas de `--no-sandbox`),
  CDP répond (`/json/list` OK), Playwright `connect_over_cdp` + navigation
  example.com + screenshot JPEG **10 826 octets** + `Page.captureScreenshot`
  CDP ~14 436 car. base64 : boucle complète prouvée (`FIREJAIL-CDP-OK`).
  Notes : `--private-tmp`/`--private`/`--net=none` cassent Chrome (zygote a
  besoin de `/proc/self/fdinfo`, profil writable) — rester sur le profil
  minimal ci-dessus + durcir par whitelist réseau côté daemon, pas par
  `--net=none`. `--noblacklist=/proc --disable-mnt` sont les deux flags qui
  débloquent le zygote. À ajouter en P1 : `--private-dev`, `--noroot`,
  `--seccomp`, `--protocol=unix,inet,inet6` (testés OK au premier essai, avant
  le correctif zygote — à revalider combinés), profil dédié hors `$HOME`,
  CDP bindé 127.0.0.1 uniquement, rate-limit input.
- **Podman rootless ✅ fallback sans daemon Docker.** Fonctionne après deux
  correctifs locaux : `~/.config/containers/containers.conf` avec
  `default_runtime="runc"` (crun refuse le mode hybride cgroups v1+v2 de
  cette machine : `crun: cgroups in hybrid mode not supported`) et nom
  d'image qualifié (`docker.io/opensandbox/chrome:latest`, pas de short-name
  sans `registries.conf`). Validé : image OSB pullée en rootless, Xtigervnc +
  Chromium démarrés, handshake RFB 1280×800 `VNC-PODMAN-OK`. Coût : reste un
  runtime OCI + images (~taille image chrome), mais **pas de daemon root**.
- **bwrap ❌ écarté sur cette machine.** `bwrap --ro-bind /usr /usr …` échoue
  même sur `/usr/bin/id` (`execvp: No such file or directory`) alors que
  `unshare --map-root-user` marche : l'empilement de montages bwrap est
  cassé dans cet environnement (probablement snap `/snap/bin` + `/bin →
  usr/bin` merge + propagation `shared`). Non bloquant : Firejail couvre le
  besoin avec une politique bien plus simple à auditer.

#### Matrice de déploiement (daemon `hermuse_computer`)

| Host Hermes | Backend sandbox | Isolement | Stream |
| --- | --- | --- | --- |
| Docker présent | `opensandbox/chrome` (P1) | container + `--no-sandbox` dedans (pattern image) | VNC + CDP polling |
| Pas de Docker, Firejail présent | Chrome host sous Firejail (ce spike) | sandbox Chrome intact + jailing FS/process | CDP polling 2 fps (pas de VNC : pas de Xvfb requis en headless) |
| Ni Docker ni Firejail | refus explicite : pas d'écran, reste du produit OK | — (NEVER Chrome bare piloté par l'agent) | — |
| VPS phase 10 | serveur OpenSandbox + 1 sandbox/upstream | gVisor/Kata + egress + vault | noVNC via proxy auth |

Détection au démarrage du daemon : `docker info` → `which firejail` →
dégradation propre avec message « computer surface indisponible ». Les
contrats §3 (status / stream WS / input / take / release / stop) sont
inchangés quel que soit le backend : seul le launcher diffère.
### 3.2 Relay — rien à coder


`GET /relay/health` inchangé. Tout `/hermes/<id>/api/plugins/hermuse_computer/*`
(HTTP + WS upgrade) est déjà forwardé avec jar + Origin. Seule vigilance :
ne jamais logger les query strings (déjà redactées, `server.dart` ligne 44).

### 3.3 Clients — `ComputerBlock` + `ComputerView`

- Modèle (`hermuse_chat`) : `ComputerBlock(sessionId, state, frameSeq, url,
  allowControl)` + `ComputerState` dans `ChatState` (par thread).
- Flutter : `Image.memory` rafraîchi au rythme du WS, pause en background,
  boutons `Open browser / Take control / Stop`.
- Web (Jaspr) : `<img>` ou `<canvas>` + même contrôles ; prévoir
  `?interactive=false` équivalent = mode lecture seule par défaut.
- Règles : lecture seule par défaut ; `Take control` = `POST /take` (pause
  l'agent, route l'input) ; `Stop` = `POST /stop` (kill, frame finale figée).

## 4. Sécurité (invariants)

- NEVER exposer 5901 (VNC) ni 9222 (CDP) au-delà du loopback du host Hermes ;
  VNC avec mot de passe en prod (le `SecurityTypes None` n'était que le spike).
- NEVER Chromium bare piloté par l'agent sur le host : toujours le container
  (`--no-sandbox` dedans est le pattern documenté de l'image, compensé par
  l'isolation container + egress controls + credential vault).
- NEVER secret dans l'URL (noVNC ou debug) : auth = session relay existante.
- Input humain rate-limité, chaque `take/stop` journalisé ; l'agent demande
  confirmation avant actions importantes (approbation des actions
  navigateur).

## 5. Phasage

- **P0 démo (1 j)** : Chromium local + daemon polling JPEG 2 fps + `ComputerView`
  minimal + take/stop. Zéro OpenSandbox, zéro noVNC.
- **P1 container** : `opensandbox/chrome` pinné par digest + fix CDP (socat ou
  exec) + VNC password + proxy relay tel quel.
- **P2 full desktop** : `opensandbox/desktop` (XFCE + x11vnc + noVNC/websockify,
  exemple doc validé en lecture seule) si un « vrai bureau » au-delà du seul
  navigateur est voulu.
- **P3 prod VPS** : serveur OpenSandbox + 1 sandbox par upstream + reverse proxy
  auth par tenant. Fork du repo uniquement si le server/proxy doit être modifié ;
  sinon consommer les images telles quelles.

## 6. Non testé (à ne pas affirmer)

noVNC embarqué en iframe HTTPS, perf Tight/ZRLE, injection input bout-à-bout,
reprise multi-tenant avec clés par tenant, Steel `debugUrl` (alternative SaaS
P0 en ~20 lignes si le self-hosted bloque), Cua/E2B/Daytona (écartés : Lume =
macOS only, E2B/Steel = SaaS, Daytona = licence à vérifier — voir comparatif
en conversation).
