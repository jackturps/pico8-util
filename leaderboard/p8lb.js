/* p8lb.js is the javascript harness that enables
 * leaderboard.p8 to provide online leaderboard's
 * to PICO-8 games.
 *
 * Leaderboard data is fed over the PICO-8 pins.
 *
 * Authentication and leaderboard names are
 * implemented through itch OAuth. This needs to
 * be authorized via a browser popup which is why
 * we show a button over the game viewport (browsers
 * were preventing unprompted popyps) (which is good lol).
 *
 * The placeholder values below are filled in from
 * setup.sh's flags when the plate is built.
 **/
var P8LB = {
  endpoint:  "@@ENDPOINT@@",
  game_id:   "@@GAME_ID@@",
  client_id: "@@ITCH_CLIENT_ID@@",
  top_n:     10,            // must match the board size in leaderboard.p8
  debug:     true,          // set false once it all works
  button_text: "authorize leaderboards"
};


(function () {
  "use strict";

  // pin offsets, must match leaderboard.p8
  var REQ = 0, STATUS = 1, ARG = 2, COUNT = 3,
      NAMELEN = 4, NAME = 5, SCORE = 21,
      MAGIC = 28, VER = 29;
  var NAME_MAX = 16;
  var MAGIC_VAL = 0x8b, VER_VAL = 1;

  // Stamp static values ASAP so they can be read on frame 1.
  if (typeof pico8_gpio !== "undefined" && pico8_gpio) {
    pico8_gpio[MAGIC] = MAGIC_VAL;
    pico8_gpio[VER] = VER_VAL;
  }

  var RQ_SUBMIT = 1, RQ_FETCH = 2, RQ_ROW = 3, RQ_WHOAMI = 4;
  var RQ_NAMES = { 1: "submit", 2: "fetch", 3: "row", 4: "whoami" };

  var SV_IDLE = 0, SV_BUSY = 1, SV_OK = 2, SV_ERR = 3;

  var TOKEN_KEY = "p8lb_token_" + P8LB.game_id;

  var rows = [];          // last fetched board
  var token = null;       // itch access token
  var username = null;    // resolved itch username
  var busy = false;
  var busySince = 0;
  var BUSY_MAX_MS = 30000;

  function log() {
    if (!P8LB.debug) return;
    console.log.apply(console, ["[p8lb]"].concat([].slice.call(arguments)));
  }
  function warn() {
    console.warn.apply(console, ["[p8lb]"].concat([].slice.call(arguments)));
  }

  try { token = localStorage.getItem(TOKEN_KEY); } catch (e) { token = null; }


  /* GPIO helpers. */
  function gpioReady() {
    return typeof pico8_gpio !== "undefined" && pico8_gpio;
  }

  function done(status) {
    busy = false;
    if (gpioReady()) pico8_gpio[STATUS] = status;
    log("-> status", status === SV_OK ? "ok" : status === SV_ERR ? "ERROR" : status);
  }

  function readScore() {
    var b0 = pico8_gpio[SCORE] | 0,
        b1 = pico8_gpio[SCORE + 1] | 0,
        b2 = pico8_gpio[SCORE + 2] | 0,
        b3 = pico8_gpio[SCORE + 3] | 0;
    // raw 16.16 fixed point, little endian, signed
    return (((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) | 0) / 65536);
  }

  function writeScore(v) {
    if (typeof v !== "number" || !isFinite(v)) v = 0;
    if (v >  32767.99998) v =  32767.99998;
    if (v < -32768)       v = -32768;
    var raw = Math.round(v * 65536) | 0;
    pico8_gpio[SCORE]     =  raw         & 255;
    pico8_gpio[SCORE + 1] = (raw >> 8)   & 255;
    pico8_gpio[SCORE + 2] = (raw >> 16)  & 255;
    pico8_gpio[SCORE + 3] = (raw >>> 24) & 255;
  }

  function writeName(s) {
    s = (s || "").substring(0, NAME_MAX);
    pico8_gpio[NAMELEN] = s.length;
    for (var i = 0; i < NAME_MAX; i++) {
      pico8_gpio[NAME + i] = i < s.length ? (s.charCodeAt(i) & 255) : 0;
    }
  }


  /* Backend requests. */
  function api(path, opts) {
    log("fetch", path);
    return fetch(P8LB.endpoint + path, opts).then(function (r) {
      if (!r.ok) {
        return r.text().then(function (t) {
          warn("http", r.status, path, t);
          throw new Error("http " + r.status);
        });
      }
      return r.json();
    });
  }

  function setToken(t) {
    token = t;
    try {
      if (t) localStorage.setItem(TOKEN_KEY, t);
      else localStorage.removeItem(TOKEN_KEY);
      log("token", t ? "stored" : "cleared");
    } catch (e) {
      warn("localStorage unavailable, token kept in memory only", e);
    }
  }

  function resolveUser() {
    if (!token) return Promise.resolve(null);
    return api("/whoami", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: token })
    }).then(function (j) {
      var name = j.username || null;
      log("whoami: ", name || "(null: token rejected by itch)");
      // /whoami returns 200 with a null name when itch
      // rejects the token, so we can forget it here.
      if (!name) setToken(null);
      return name;
    }).catch(function (e) {
      warn("whoami failed, clearing token", e.message);
      setToken(null);
      return null;
    });
  }


  /* itch OAuth. */
  function oauthUrl() {
    return "https://itch.io/user/oauth"
      + "?client_id=" + encodeURIComponent(P8LB.client_id)
      + "&scope=" + encodeURIComponent("profile:me")
      + "&response_type=token"
      + "&redirect_uri=" + encodeURIComponent(P8LB.endpoint + "/auth");
  }

  function openLogin() {
    if (!P8LB.client_id) { warn("no client_id configured"); return; }
    log("opening popup");
    var w = window.open(oauthUrl(), "p8lb_itch",
                        "width=520,height=700,menubar=no,toolbar=no");
    if (!w) warn("popup blocked, allow popups for this site");
  }

  function onAuthMessage(e) {
    var d = e.data;
    if (!d || d.p8lb !== "token") return;
    log("auth message from", e.origin, "token?", !!d.token);
    if (!d.token) { setSignedIn(null); return; }
    setToken(d.token);
    resolveUser().then(setSignedIn);
  }

  // The cart picks this up on its next whoami request.
  function setSignedIn(name) {
    username = name;
    showButton(!name);
    log("signed in as", name || "(nobody)");
  }

  window.addEventListener("message", onAuthMessage);


  /* Sign in button. */
  var btnHost = null;   // the row holding the button

  function showButton(show) {
    if (!btnHost) return;
    btnHost.style.display = show && P8LB.client_id ? "block" : "none";
  }

  function makeButton() {
    var btn = document.createElement("button");
    btn.textContent = P8LB.button_text;
    btn.setAttribute("aria-label",
      "Authorize with itch.io to post scores to the leaderboard");

    btn.style.cssText = [
      "font:11px/1.4 monospace", "padding:9px 12px", "cursor:pointer",
      "background:#fa5c5c", "color:#fff", "border:0", "border-radius:3px",
      // Fix tap behaviour on mobile.
      "touch-action:manipulation",
      "-webkit-tap-highlight-color:transparent"
    ].join(";");

    btnHost = document.createElement("div");
    btnHost.style.cssText = "text-align:center;padding:4px 0;width:100%";
    btnHost.appendChild(btn);

    // place the button above the PICO-8 viewport.
    // I tried a few other spots but they get dangerous
    // because PICO-8 overrides input within the viewport.
    var frame = document.getElementById("p8_frame_0");
    if (frame && frame.parentNode) {
      frame.parentNode.insertBefore(btnHost, frame);
    } else {
      document.body.insertBefore(btnHost, document.body.firstChild);
    }

    var lastActivate = 0;
    function activate(ev) {
      ev.preventDefault();
      var now = Date.now();
      if (now - lastActivate < 600) return;
      lastActivate = now;
      openLogin();
    }
    btn.addEventListener("click", activate);
    btn.addEventListener("touchend", activate);
    showButton(!username);
  }


  /* Request handlers. */
  function doWhoami() {
    // Should already be resolved via the button or automatically
    // so we can just return it.
    if (username) {
      log("whoami: cached", username);
      writeName(username);
      done(SV_OK);
      return;
    }
    if (!token) {
      log("whoami: not signed in");
      writeName("");
      done(SV_OK);
      return;
    }
    resolveUser().then(function (name) {
      setSignedIn(name);
      writeName(name || "");
      done(SV_OK);
    });
  }

  function doSubmit() {
    var score = readScore();
    log("submit score", score, "| token?", !!token, "| user", username);
    if (!token) { warn("submit with no token, authorize first"); done(SV_ERR); return; }
    api("/submit", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        game_id: P8LB.game_id,
        score: score,
        token: token
      })
    }).then(function (j) {
      log("submit ok", j);

      // If we already have a name we can reuse it.
      if (j.username) {
        username = j.username;
        showButton(false);
      }
      writeName(username || "");
      done(SV_OK);
    }).catch(function (e) {
      warn("submit failed", e.message);
      // 401 means the token expired mid-session,
      // we have to bring the button back to let the
      // player authorize again.
      if (e.message.indexOf("401") >= 0) {
        warn("token expired, signing out");
        setToken(null);
        setSignedIn(null);
      }
      done(SV_ERR);
    });
  }

  function doFetch() {
    var n = P8LB.top_n | 0;
    api("/top?game_id=" + encodeURIComponent(P8LB.game_id) + "&n=" + n,
        { method: "GET" })
      .then(function (j) {
        rows = (j.rows || []).slice(0, 255);
        log("fetch: ", rows.length, "rows");
        pico8_gpio[COUNT] = rows.length;
        done(SV_OK);
      })
      .catch(function (e) {
        warn("fetch failed", e.message);
        rows = [];
        pico8_gpio[COUNT] = 0;
        done(SV_ERR);
      });
  }

  function doRow() {
    var i = (pico8_gpio[ARG] | 0) - 1;   // cart counts from 1
    var r = rows[i];
    if (!r) { warn("row", i + 1, "out of range"); done(SV_ERR); return; }
    writeName(r.name);
    writeScore(r.score);
    done(SV_OK);
  }


  /* Poll loop. */
  function tick() {
    if (!gpioReady()) return;

    if (busy) {
      if (Date.now() - busySince > BUSY_MAX_MS) {
        warn("watchdog: request stuck, giving up");
        done(SV_ERR);
      }
      return;
    }

    var req = pico8_gpio[REQ] | 0;
    if (req === 0) return;
    if ((pico8_gpio[STATUS] | 0) !== SV_IDLE) return;

    pico8_gpio[REQ] = 0;
    pico8_gpio[STATUS] = SV_BUSY;
    busy = true;
    busySince = Date.now();

    log("request:", RQ_NAMES[req] || req);

    try {
      if      (req === RQ_WHOAMI) doWhoami();
      else if (req === RQ_SUBMIT) doSubmit();
      else if (req === RQ_FETCH)  doFetch();
      else if (req === RQ_ROW)    doRow();
      else done(SV_ERR);
    } catch (e) {
      warn("handler threw", e);
      done(SV_ERR);
    }
  }

  function boot() {
    makeButton();
    setInterval(tick, 16);
    // Always restamp to be safe.
    if (gpioReady()) {
      pico8_gpio[MAGIC] = MAGIC_VAL;
      pico8_gpio[VER] = VER_VAL;
    }
    log("bridge up |", P8LB.endpoint,
        "| game:", P8LB.game_id,
        "| client_id:", P8LB.client_id ? "set" : "MISSING",
        "| token:", token ? "cached" : "none",
        "| magic:", gpioReady() ? pico8_gpio[MAGIC] : "no gpio");
    if (token) resolveUser().then(setSignedIn);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
