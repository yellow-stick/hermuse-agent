# shellcheck shell=bash
# GUI automation of the smoke guest, sourced by linux.sh (root). Drives the
# tester's X display :99 like a user would: screenshots (ImageMagick), text
# located by OCR (Tesseract) and clicked with real pointer events (xdotool),
# the real polkit-gnome and gnome-keyring (gcr) dialogs answered by typing the
# synthetic passwords from root-only files (never on a command line).
#
# Requires: gui_init <evidence-dir>. Every helper returns non-zero instead of
# exiting; callers decide whether a miss is a failure or a manual gate.

GUI_DISPLAY=:99
GUI_EVIDENCE=
GUI_TMP=
GUI_RECORDER_PID=

gui_init() { # <evidence-dir>
  GUI_EVIDENCE=$1
  mkdir -p "$GUI_EVIDENCE/screens"
  GUI_TMP=$(mktemp -d /run/hermuse-smoke/gui.XXXXXX)
  export DISPLAY=$GUI_DISPLAY XAUTHORITY=/home/tester/.Xauthority
}

gui_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | tr -s '-' | cut -c1-60; }

# Full-screen PNG under evidence/screens; prints its path.
gui_shot() { # <name>
  local path
  path="$GUI_EVIDENCE/screens/$(date +%H%M%S)-$(gui_slug "$1").png"
  import -window root "$path" 2>/dev/null || return 1
  printf '%s\n' "$path"
}

# OCR words of a screenshot as Tesseract TSV (2x upscaled grayscale: small UI
# text reads far better). A dark screenshot is negated first: light text on a
# dark UI is read reliably by every Tesseract of the guests (4.1 to 5.5) only
# as dark text on light. No -normalize: with Tesseract 5.3 it wipes out the
# text of a dark window next to the black root window. Coordinates stay in
# the upscaled space.
gui_ocr() { # <png> -> TSV on stdout
  local base="$GUI_TMP/ocr" tone=(-colorspace Gray)
  # Dark UI: the brightness channel (max of R, G, B) keeps coloured text such
  # as a red warning as light as white text, then the negation.
  [ "$(convert "$1" -colorspace Gray -format '%[fx:mean<0.5?1:0]' info: 2>/dev/null)" = 1 ] &&
    tone=(-colorspace HSB -channel B -separate +channel -negate)
  convert "$1" "${tone[@]}" -resize 200% "$base.png" 2>/dev/null || return 1
  tesseract "$base.png" "$base" --psm 11 tsv >/dev/null 2>&1 || return 1
  cat "$base.tsv"
}

# Screen coordinates "x y" of the centre of <phrase> on <png>. Words are
# compared lowercased without punctuation. mode=line: the phrase must be a
# whole OCR line (a button label); mode=any: anywhere inside a line.
gui_locate() { # <png> <phrase> [line|any]
  gui_ocr "$1" | awk -v phrase="$2" -v mode="${3:-line}" '
    BEGIN {
      FS = "\t"
      n = split(tolower(phrase), want, " ")
      for (j = 1; j <= n; j++) gsub(/[^a-z0-9]/, "", want[j])
    }
    NR > 1 && $1 == 5 && $12 != "" {
      w = tolower($12)
      gsub(/[^a-z0-9]/, "", w)
      if (w == "") next
      key = $3 "-" $4 "-" $5
      if (!(key in count)) order[++lines] = key
      i = ++count[key]
      word[key, i] = w
      l[key, i] = $7; t[key, i] = $8; r[key, i] = $7 + $9; b[key, i] = $8 + $10
    }
    END {
      for (k = 1; k <= lines; k++) {
        key = order[k]
        if (mode == "line" && count[key] != n) continue
        for (s = 1; s + n - 1 <= count[key]; s++) {
          ok = 1
          for (j = 1; j <= n; j++) if (word[key, s + j - 1] != want[j]) { ok = 0; break }
          if (!ok) continue
          x1 = l[key, s]; y1 = t[key, s]; x2 = r[key, s]; y2 = b[key, s]
          for (j = s + 1; j < s + n; j++) {
            if (l[key, j] < x1) x1 = l[key, j]
            if (t[key, j] < y1) y1 = t[key, j]
            if (r[key, j] > x2) x2 = r[key, j]
            if (b[key, j] > y2) y2 = b[key, j]
          }
          printf "%d %d\n", (x1 + x2) / 4, (y1 + y2) / 4
          exit 0
        }
      }
      exit 1
    }'
}

# Waits until <phrase> is on screen; prints the screenshot path that shows it.
gui_wait_text() { # <phrase> <timeout-s> [line|any]
  local phrase=$1 deadline=$((SECONDS + $2)) mode=${3:-any} shot
  while :; do
    shot=$(gui_shot "wait-$phrase") || return 1
    if gui_locate "$shot" "$phrase" "$mode" >/dev/null; then
      printf '%s\n' "$shot"
      return 0
    fi
    rm -f "$shot"
    [ "$SECONDS" -lt "$deadline" ] || break
    sleep 3
  done
  gui_shot "missing-$phrase" >/dev/null
  return 1
}

# OCR of a cropped button: the phrase's words, in order, plus at most
# one-character artifacts of the rounded, antialiased edges ("f", ")", "|").
gui_label_matches() { # <ocr-text> <phrase>
  awk -v got="$1" -v phrase="$2" 'BEGIN {
    n = split(tolower(phrase), raw, " ")
    for (j = 1; j <= n; j++) { gsub(/[^a-z0-9]/, "", raw[j]); if (raw[j] != "") want[++m] = raw[j] }
    k = split(tolower(got), raw, /[ \t\n\f]+/)
    for (j = 1; j <= k; j++) { gsub(/[^a-z0-9]/, "", raw[j]); if (raw[j] != "") tok[++t] = raw[j] }
    for (s = 1; m > 0 && s + m - 1 <= t; s++) {
      ok = 1
      for (j = 1; j <= m; j++) if (tok[s + j - 1] != want[j]) { ok = 0; break }
      for (j = 1; ok && j <= t; j++) if ((j < s || j >= s + m) && length(tok[j]) > 1) ok = 0
      if (ok) exit 0
    }
    exit 1
  }'
}

# Filled accent buttons (dark label on a saturated, bright fill) are missed by
# the full-screen OCR pass of a dark UI. Each saturated bright region of
# button size is cropped and read alone as one line.
gui_locate_filled() { # <png> <phrase>
  local shot=$1 box w h x y crop="$GUI_TMP/filled" text
  convert "$shot" -colorspace HSB -separate \( -clone 1 -threshold 40% \) \( -clone 2 -threshold 50% \) \
    -delete 0-2 -compose multiply -composite "$crop-mask.png" 2>/dev/null || return 1
  while read -r box; do
    IFS='x+' read -r w h x y <<<"$box"
    [ "$w" -ge 40 ] && [ "$w" -le 600 ] && [ "$h" -ge 20 ] && [ "$h" -le 120 ] || continue
    # Rounded corners leave background in the box: flood it white from the
    # four corners (the label is enclosed by the fill, so it is not reached),
    # then shave the antialiased border.
    convert "$shot" -crop "${w}x${h}+${x}+${y}" +repage -fuzz 40% -fill white \
      -draw 'color 0,0 floodfill' -draw "color $((w - 1)),0 floodfill" \
      -draw "color 0,$((h - 1)) floodfill" -draw "color $((w - 1)),$((h - 1)) floodfill" \
      -shave 2x2 -colorspace Gray -resize 300% -normalize "$crop.png" 2>/dev/null || continue
    text=$(tesseract "$crop.png" - --psm 7 2>/dev/null)
    if gui_label_matches "$text" "$2"; then
      printf '%d %d\n' $((x + w / 2)) $((y + h / 2))
      return 0
    fi
  done < <(convert "$crop-mask.png" -define connected-components:verbose=true \
    -define connected-components:area-threshold=400 -connected-components 8 null: 2>&1 |
    awk '$2 ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/ && $NF ~ /255/ { print $2 }')
  return 1
}

# Clicks <phrase> with real pointer events: by default the first OCR line equal
# to it (a button label), else a filled button carrying it; `any` also accepts
# the phrase inside a longer line (a list row). Prints the screenshot taken
# just before the click.
gui_click() { # <phrase> <timeout-s> [line|any]
  local phrase=$1 deadline=$((SECONDS + $2)) mode=${3:-line} shot xy tries=0
  while :; do
    shot=$(gui_shot "click-$phrase") || return 1
    if xy=$(gui_locate "$shot" "$phrase" "$mode") || xy=$(gui_locate_filled "$shot" "$phrase"); then
      # shellcheck disable=SC2086 # "x y"
      xdotool mousemove --sync $xy click 1
      printf '%s\n' "$shot"
      sleep 1
      return 0
    fi
    rm -f "$shot"
    [ "$SECONDS" -lt "$deadline" ] || break
    # A long page hides its lower buttons: scroll down, now and then back up.
    tries=$((tries + 1))
    if [ $((tries % 4)) -eq 0 ]; then gui_scroll up 30; else gui_scroll down 5; fi
    sleep 2
  done
  gui_shot "missing-$phrase" >/dev/null
  return 1
}

# First visible window whose title matches the extended regex.
gui_window() { # <title-regex> [timeout-s]
  local deadline=$((SECONDS + ${2:-0})) id
  while :; do
    id=$(xdotool search --onlyvisible --name "$1" 2>/dev/null | head -n 1)
    if [ -n "$id" ]; then
      printf '%s\n' "$id"
      return 0
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 2
  done
}

gui_window_by_class() { # <class-regex> [timeout-s]
  local deadline=$((SECONDS + ${2:-0})) id
  while :; do
    id=$(xdotool search --onlyvisible --class "$1" 2>/dev/null | head -n 1)
    if [ -n "$id" ]; then
      printf '%s\n' "$id"
      return 0
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 2
  done
}

# Screen centres "x y" of the items of the app's icon rail, top to bottom
# (icon-only: its labels are tooltips, out of reach of OCR). The rail is the
# first <width> pixels of the window; each item is a band of rows holding
# bright icon pixels.
gui_rail_items() { # <window-id> [rail-width]
  local rail=${2:-72} shot="$GUI_TMP/rail.png" WINDOW X Y WIDTH HEIGHT SCREEN
  eval "$(xdotool getwindowgeometry --shell "$1" 2>/dev/null)" || return 1
  [ -n "${HEIGHT:-}" ] || return 1
  import -window root -crop "${rail}x${HEIGHT}+${X}+${Y}" +repage "$shot" 2>/dev/null || return 1
  convert "$shot" -colorspace Gray -threshold 55% -scale "1x${HEIGHT}!" -depth 8 txt:- 2>/dev/null |
    awk -v x="$((X + rail / 2))" -v y0="$Y" '
      NR > 1 {
        split($1, p, /[,:]/)
        on = ($0 !~ /#000000/)
        if (on && start < 0) start = p[2]
        if (on) last = p[2]
        if (!on && start >= 0 && p[2] - last > 3) { printf "%d %d\n", x, y0 + (start + last) / 2; start = -1 }
      }
      BEGIN { start = -1 }
      END { if (start >= 0) printf "%d %d\n", x, y0 + (start + last) / 2 }'
}

gui_focus() { # <window-id>
  xdotool windowactivate --sync "$1" >/dev/null 2>&1 || xdotool windowfocus --sync "$1" >/dev/null 2>&1
}

# Mouse wheel over the middle of the active window (a dialog scrolls under
# the pointer).
gui_scroll() { # up|down <notches>
  # shellcheck disable=SC2034 # WINDOW and SCREEN are set by the eval
  local button=5 WINDOW X Y WIDTH HEIGHT SCREEN
  [ "$1" = up ] && button=4
  eval "$(xdotool getactivewindow getwindowgeometry --shell 2>/dev/null)" || return 0
  [ -n "${WIDTH:-}" ] || return 0
  xdotool mousemove --sync $((X + WIDTH / 2)) $((Y + HEIGHT / 2)) click --repeat "$2" --delay 60 "$button"
}

# Answers the real polkit-gnome authentication dialog: accept types the
# tester password (from a root-only file) and Return; cancel presses Escape.
gui_polkit() { # accept|cancel <password-file> <timeout-s>
  local action=$1 password=$2 id
  id=$(gui_window_by_class 'polkit-gnome-authentication-agent' "$3") || return 1
  gui_shot "polkit-dialog-$action" >/dev/null
  gui_focus "$id"
  if [ "$action" = accept ]; then
    xdotool type --delay 40 --file "$password"
    xdotool key Return
  else
    xdotool key Escape
  fi
  sleep 2
  return 0
}

# Answers a gnome-keyring (gcr) prompt. A new-keyring prompt gets the
# password twice (password, confirmation); an unlock prompt gets it once;
# cancel presses Escape. Prints "new", "unlock" or "cancel".
gui_keyring_prompt() { # accept|cancel <password-file> <timeout-s>
  local action=$1 password=$2 id shot kind=unlock
  id=$(gui_window_by_class 'gcr-prompter' "$3") || return 1
  # The prompt window alone: its light dialog, not the dark app behind it.
  shot="$GUI_EVIDENCE/screens/$(date +%H%M%S)-keyring-prompt-$action.png"
  import -window "$id" "$shot" 2>/dev/null || shot=$(gui_shot "keyring-prompt-$action") || return 1
  gui_focus "$id"
  if [ "$action" = cancel ]; then
    xdotool key Escape
    echo cancel
    sleep 2
    return 0
  fi
  if gui_locate "$shot" "new keyring" any >/dev/null || gui_locate "$shot" "choose password" any >/dev/null; then
    kind=new
    xdotool type --delay 40 --file "$password"
    xdotool key Tab
  fi
  xdotool type --delay 40 --file "$password"
  xdotool key Return
  echo "$kind"
  sleep 2
}

# Graceful close through the window manager (WM_DELETE_WINDOW), as the
# titlebar close button does.
gui_close() { # <title-regex>
  wmctrl -F -c "$1" >/dev/null 2>&1 || wmctrl -c "$1" >/dev/null 2>&1
}

gui_window_props() { # <window-id> -> WM_CLASS, _NET_WM_NAME, geometry
  xprop -id "$1" WM_CLASS _NET_WM_NAME _NET_WM_PID 2>/dev/null
  xwininfo -id "$1" 2>/dev/null | grep -E 'Width|Height|Map State'
}

# Background capture of the whole run: one half-size JPEG every few seconds,
# turned into a video on the CI host (no ffmpeg in the guest: it is one of
# the tools the app must install).
gui_recorder_start() { # [interval-s]
  local dir="$GUI_EVIDENCE/frames" interval=${1:-4}
  mkdir -p "$dir"
  (
    while :; do
      import -window root -resize 50% -quality 60 "$dir/$(date +%s).jpg" 2>/dev/null
      sleep "$interval"
    done
  ) &
  GUI_RECORDER_PID=$!
}

gui_recorder_stop() {
  [ -n "$GUI_RECORDER_PID" ] || return 0
  kill "$GUI_RECORDER_PID" 2>/dev/null
  wait "$GUI_RECORDER_PID" 2>/dev/null
  GUI_RECORDER_PID=
  return 0
}
