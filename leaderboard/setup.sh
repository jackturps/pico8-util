#!/usr/bin/env bash
#
# Run with the following command:
#   ./setup.sh --game-id <arbitrary game ID> \
#              --itch-client-id <itch oauth client id>

# Setup script for the PICO-8 leaderboard backends. Creates
# and deploys a worker to serve the leaderboard, configures
# the itch client, builds and installs a custom PICO-8 plate.
#
# All steps should be idempotent so the script is safe to rerun.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

# Defaults.
GAME_ID=""
ITCH_CLIENT_ID=""
DB_NAME="p8lb"
DB_ID=""
WORKER_NAME="p8lb"
PLATES_DIR=""
ENDPOINT=""
NO_DEPLOY=0
PICO8_BIN="${PICO8_BIN:-}"
SHELL_BASE=""   # set by make_shell_base

# Remove all temp files on exit.
tmp_files=()
cleanup() { [ ${#tmp_files[@]} -eq 0 ] || rm -rf "${tmp_files[@]}"; }
trap cleanup EXIT

# Helpers.
say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

options:
  --game-id ID        Arbitrary ID that keeps this game's scores separate
                      from other games on the same backend. Also names the
                      plate. [required]
  --itch-client-id ID itch.io OAuth application client id. If omitted, it's
                      prompted for after the server is deployed.
  --pico8 PATH        Path to the pico8 binary. Detected if omitted.
  --endpoint URL      Override the cloudflare worker URL, needed with --no-deploy.
  --db-name NAME      Name for the database. (default p8lb)
  --db-id UUID        Use an existing D1 database instead of creating one
                      on first deploy (from 'wrangler d1 create').
  --worker-name NAME  Name for the cloudflare worker (default p8lb)
  --plates DIR        PICO-8 plates directory. Detected if omitted.
  --no-deploy         Skip cloudflare, just rebuild the plate.
  -h, --help
EOF
  exit 0
}

find_pico8() {
  if [ -n "${PICO8_BIN:-}" ]; then
    [ -x "$PICO8_BIN" ] && echo "$PICO8_BIN"
    return
  fi
  if command -v pico8 >/dev/null 2>&1; then
    command -v pico8; return
  fi
  local p
  for p in \
    "/c/Program Files (x86)/PICO-8/pico8.exe" \
    "/c/Program Files/PICO-8/pico8.exe" \
    "/Applications/PICO-8.app/Contents/MacOS/pico8" \
    "$HOME/pico-8/pico8" ; do
    [ -x "$p" ] && { echo "$p"; return; }
  done
}

# We build a custom plate on top of the default
# PICO-8 plate. The easiest way to get an up to date
# plate is to export an empty cart and keep its HTML so
# that's what we do!
make_shell_base() {
  local p8 tmpd
  p8="$(find_pico8)"
  [ -n "$p8" ] || die "couldn't find PICO-8. pass --pico8 /path/to/pico8"

  tmpd="$(mktemp -d)"
  tmp_files+=("$tmpd")

  # PICO-8 requires a label to export to HTML so
  # we give the temp cart a blank one.
  {
    printf 'pico-8 cartridge // http://www.pico-8.com\n'
    printf 'version 43\n__lua__\n__label__\n'
    printf '%0128d\n' 0
  } > "$tmpd/p8lb_base.p8"

  ( cd "$tmpd" && "$p8" p8lb_base.p8 -export "-f base.html" ) || true
  [ -f "$tmpd/base_html/index.html" ] || die "PICO-8 export failed"

  SHELL_BASE="$tmpd/shell_base.html"
  normalise_base "$tmpd/base_html/index.html" > "$SHELL_BASE"

  local tok
  for tok in '##js_file##' '##label_file##'; do
    grep -q -- "$tok" "$SHELL_BASE" \
      || die "$tok missing after normalising PICO-8's export.
       PICO-8's shell layout may have changed."
  done

  note "exported a base shell from $p8"
}


# Convert an empty PICO-8 export into a usable plate.
normalise_base() {
  awk '
    /\.p8_start_button[ \t]*\{/ { in_btn = 1 }
    in_btn && /background:url\("data:image/ {
      sub(/data:image\/[a-zA-Z]+;base64,[A-Za-z0-9+\/=]+/, "##label_file##")
      in_btn = 0
    }

    { sub(/e\.src = "[^"]*\.js"/, "e.src = \"##js_file##\"") }
    { print }
  ' "$1"
}

# Create plate.html by baking flags into p8lb.js and
# injecting that into the base shell.
build_plate() {
  local js="$here/p8lb.js"
  local base="$SHELL_BASE"
  local out="$here/plate.html"

  [ -f "$js" ] || die "$js not found"

  local tmp_js
  tmp_js="$(mktemp)"
  tmp_files+=("$tmp_js")

  sed -e "s|@@ENDPOINT@@|${ENDPOINT}|g" \
      -e "s|@@GAME_ID@@|${GAME_ID}|g" \
      -e "s|@@ITCH_CLIENT_ID@@|${ITCH_CLIENT_ID}|g" \
      "$js" > "$tmp_js"

  grep -q '@@' "$tmp_js" \
    && die "unsubstituted placeholders remain in p8lb.js:
$(grep -n '@@' "$tmp_js")"

  awk -v jsfile="$tmp_js" '
    /<\/body>/ && !injected {
      print "<!-- p8lb leaderboard bridge -->";
      print "<script>";
      while ((getline line < jsfile) > 0) print line;
      close(jsfile);
      print "</script>";
      injected = 1;
    }
    { print }
  ' "$base" > "$out"

  note "plate.html"
  note "  endpoint : $ENDPOINT"
  note "  game_id  : $GAME_ID"
  note "  itch id  : ${ITCH_CLIENT_ID:-(none, sign in disabled)}"
}

default_plates() {
  if [ -n "${APPDATA:-}" ]; then
    if command -v cygpath >/dev/null 2>&1; then
      echo "$(cygpath -u "$APPDATA")/pico-8/plates"
    else
      echo "$APPDATA/pico-8/plates"
    fi
  elif [ -d "$HOME/Library/Application Support/pico-8" ]; then
    echo "$HOME/Library/Application Support/pico-8/plates"
  else
    echo "$HOME/.lexaloffle/pico-8/plates"
  fi
}

check_deps() {
  local missing=() tool

  for tool in awk sed grep tr cut head tee mktemp date; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done

  # Wrangler is only needed to deploy.
  if [ "$NO_DEPLOY" -eq 0 ]; then
    if ! command -v wrangler >/dev/null 2>&1; then
      missing+=("wrangler")
    elif ! grep -q "You are logged in" <<<"$(wrangler whoami 2>&1)"; then
      missing+=("cloudflare login")
    fi
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    die "missing dependencies:
$(printf '         - %s\n' "${missing[@]}")
       run ./leaderboard/deps/<OS> to install them"
  fi

  # The deps scripts can't install PICO-8, so it gets a special message (:
  if [ -n "$PICO8_BIN" ] && [ ! -x "$PICO8_BIN" ]; then
    die "$PICO8_BIN (from --pico8 or PICO8_BIN) doesn't exist or isn't executable"
  elif [ -z "$(find_pico8)" ]; then
    die "couldn't find PICO-8. install it, or pass --pico8 /path/to/pico8"
  fi
  note "all present"
}

# Fail if a flag is missing its value.
need_value() {
  [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#--}" = "$2" ] \
    || die "$1 needs a value  (try --help)"
}

# Parse flags.
while [ $# -gt 0 ]; do
  case "$1" in
    --game-id)     need_value "$@"; GAME_ID="$2";     shift 2 ;;
    --itch-client-id) need_value "$@"; ITCH_CLIENT_ID="$2"; shift 2 ;;
    --endpoint)    need_value "$@"; ENDPOINT="$2";    shift 2 ;;
    --db-name)     need_value "$@"; DB_NAME="$2";     shift 2 ;;
    --db-id)       need_value "$@"; DB_ID="$2";       shift 2 ;;
    --worker-name) need_value "$@"; WORKER_NAME="$2"; shift 2 ;;
    --plates)      need_value "$@"; PLATES_DIR="$2";  shift 2 ;;
    --pico8)       need_value "$@"; PICO8_BIN="$2";   shift 2 ;;
    --no-deploy)   NO_DEPLOY=1;      shift ;;
    -h|--help)     usage ;;
    --*) die "unknown option: $1  (try --help)" ;;
    *) die "unexpected argument: $1  (try --help)" ;;
  esac
done

# Validate flags (play it safe so we don't break sed/JSON/etc down the line).
valid_client_id() { [[ "$1" =~ ^[A-Za-z0-9]+$ ]]; }

[ -n "$GAME_ID" ] || die "--game-id is required"
[[ "$GAME_ID" =~ ^[a-z0-9_-]{1,64}$ ]] \
  || die "--game-id '$GAME_ID' isn't valid.
       use lowercase letters, digits, _ and -, at most 64 characters."
[ -z "$ITCH_CLIENT_ID" ] || valid_client_id "$ITCH_CLIENT_ID" \
  || die "--itch-client-id '$ITCH_CLIENT_ID' isn't valid.
       it should be letters and digits only, copy it from your itch OAuth app."
[ -z "$ENDPOINT" ] || [[ "$ENDPOINT" =~ ^https?://[A-Za-z0-9._~:/-]+$ ]] \
  || die "--endpoint '$ENDPOINT' isn't valid.
       expected a URL like https://p8lb.<your-account>.workers.dev"
[[ "$WORKER_NAME" =~ ^[a-z0-9-]{1,63}$ ]] \
  || die "--worker-name '$WORKER_NAME' isn't valid.
       use lowercase letters, digits and -, at most 63 characters."
[[ "$DB_NAME" =~ ^[A-Za-z0-9_-]+$ ]] \
  || die "--db-name '$DB_NAME' isn't valid. use letters, digits, _ and -."
[ -z "$DB_ID" ] || [[ "$DB_ID" =~ ^[0-9a-f-]+$ ]] \
  || die "--db-id '$DB_ID' isn't valid. it's the uuid printed by 'wrangler d1 create'."
[ "$NO_DEPLOY" -eq 0 ] || [ -n "$ENDPOINT" ] \
  || die "--no-deploy needs --endpoint (the worker URL printed by the last deploy)"
[ -n "$PLATES_DIR" ] || PLATES_DIR="$(default_plates)"

say "checking dependencies"
check_deps

say "generating base shell"
make_shell_base

# Strip trailing slashes.
ENDPOINT="${ENDPOINT%/}"

if [ "$NO_DEPLOY" -eq 1 ]; then
  say "skipping worker deploy (--no-deploy)"
else
  say "writing worker/wrangler.jsonc"
  # database_id is omitted unless --db-id is given, so
  # cloudflare provisions the D1 database on first deploy.
  db_id_field=""
  [ -z "$DB_ID" ] || db_id_field=", \"database_id\": \"$DB_ID\""
  {
    echo '// generated by setup.sh, DONT EDIT THIS FILE'
    echo '{'
    echo "  \"name\": \"$WORKER_NAME\","
    echo '  "main": "index.js",'
    echo "  \"compatibility_date\": \"$(date +%Y-%m-%d)\","
    echo '  "observability": { "enabled": true },'
    echo '  "d1_databases": ['
    echo "    { \"binding\": \"DB\", \"database_name\": \"$DB_NAME\"$db_id_field }"
    echo '  ]'
    echo '}'
  } > "$here/worker/wrangler.jsonc"
  note "worker/wrangler.jsonc"

  # Deploy the worker.
  say "deploying worker (creates D1 if missing)"
  deploy_log="$(mktemp)"
  tmp_files+=("$deploy_log")
  if ! ( cd "$here/worker" && wrangler deploy ) 2>&1 | tee "$deploy_log"; then
    die "deploy failed, see wrangler's output above"
  fi

  detected="$(grep -Eo 'https://[a-zA-Z0-9._-]+\.workers\.dev' "$deploy_log" | head -1 || true)"
  if [ -n "$detected" ]; then
    if [ -n "$ENDPOINT" ] && [ "$ENDPOINT" != "$detected" ]; then
      note "keeping --endpoint $ENDPOINT (deployed at $detected)"
    else
      ENDPOINT="$detected"
      note "endpoint: $ENDPOINT"
    fi
  elif [ -z "$ENDPOINT" ]; then
    die "couldn't find the worker URL in wrangler's output, pass it with --endpoint"
  fi

  # Apply the database schema.
  say "applying schema"
  ( cd "$here/worker" && wrangler d1 execute "$DB_NAME" --remote --file ./schema.sql --yes ) \
    || die "schema step failed, see the output above"
  note "scores table ready"
fi

# Prompt for the itch client ID. There's a bit of a chicken and
# egg problem where we need the itch client to be setup but the itch
# client requires the cloudflare URL, so this stage is pretty interactive.
if [ -z "$ITCH_CLIENT_ID" ] && [ -t 0 ]; then
  say "itch sign-in"
  note "1. create an OAuth app at https://itch.io/user/settings/oauth-apps"
  note "   (or open your existing one)"
  note "2. set its redirect URI to exactly:"
  note ""
  note "       $ENDPOINT/auth"
  note ""
  note "3. paste the app's client id below"
  note ""
  read -r -p "    client id (enter to skip, sign-in stays disabled): " ITCH_CLIENT_ID \
    || ITCH_CLIENT_ID=""
  # trim stray whitespace from the paste
  ITCH_CLIENT_ID="$(printf '%s' "$ITCH_CLIENT_ID" | tr -d '[:space:]')"
  [ -z "$ITCH_CLIENT_ID" ] || valid_client_id "$ITCH_CLIENT_ID" \
    || die "'$ITCH_CLIENT_ID' isn't a valid client id.
       it should be letters and digits only, copy it from your itch OAuth app,
       then re-run with --itch-client-id <id>"
  if [ -n "$ITCH_CLIENT_ID" ]; then
    note "next time, pass --itch-client-id $ITCH_CLIENT_ID to skip this"
  fi
fi

say "building plate.html"
build_plate

say "installing plate"
# Each game needs its own plate.
if mkdir -p "$PLATES_DIR" 2>/dev/null; then
  cp "$here/plate.html" "$PLATES_DIR/$GAME_ID.html"
  note "$PLATES_DIR/$GAME_ID.html"
else
  note "couldn't write to $PLATES_DIR"
  note "copy plate.html there yourself, as $GAME_ID.html"
fi

# Print next steps.
plate_upper="$(echo "$GAME_ID" | tr '[:lower:]' '[:upper:]')"
cat <<EOF

$(printf '\033[1mdone.\033[0m')

  endpoint   $ENDPOINT
  game_id    $GAME_ID

next:

  1. register this exact redirect URI on your itch OAuth app
     https://itch.io/user/settings/oauth-apps

         $ENDPOINT/auth

$(if [ -z "$ITCH_CLIENT_ID" ]; then
echo "     then re-run with --itch-client-id <id>  (sign-in is disabled until you do)"
fi)
  2. export from PICO-8 using the plate:

         EXPORT -F INDEX.HTML -P $plate_upper

  3. check it answers:

         curl "$ENDPOINT/top?game_id=$GAME_ID"

EOF
