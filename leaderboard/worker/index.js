/* p8lb API implemented as a cloudflare wokrer.
 *
 * p8lb API has the following routes:
 *   GET  /auth                     itch OAuth callback bridge
 *   POST /whoami  {token}          => {username}
 *   POST /submit  {game_id,score,token}
 *   GET  /top?game_id=..&n=10      => {rows:[{name,score}]}
 *
 * The client always sends an itch.io token which
 * the backend resolves against itch. This prevents
 * players from posting under the names of other
 * players (they can still post inflated scores though D:).
 *
 * One row per player per game, keeping the best score.
 * Player's owns exactly one leaderboard slot.
 */

const ITCH_PROFILE = "https://api.itch.io/profile";

// PICO-8 limits.
const P8_MAX = 32767.99998;
const P8_MIN = -32768;

const NAME_MAX = 16;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400"
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS }
  });
}

function bad(msg, status = 400) {
  return json({ error: msg }, status);
}

// Users send itch tokens and we resolve them with itch directly.
async function resolveItchUser(token) {
  if (!token || typeof token !== "string" || token.length > 512) {
    return null;
  }

  let res;
  try {
    res = await fetch(ITCH_PROFILE, {
      headers: { authorization: "Bearer " + token }
    });
  } catch (e) {
    // Couldn't reach itch.
    return null;
  }
  if (!res.ok) {
    // Token was real but invalid (expired, revoked, or forged).
    return null;
  }

  let data;
  try {
    data = await res.json();
  } catch (e) {
    return null;
  }

  const u = data && data.user;
  if (!u || !u.id) {
    return null;
  }

  const name = String(u.username || u.display_name || "player");
  return { id: String(u.id), username: name.substring(0, NAME_MAX) };
}


/* Routes */

// Part of the popup we show when the user clicks "Authorize Leaderboard".
// This propogates the token to the game.
function authPage() {
  const html = `<!doctype html><meta charset="utf-8">
<title>signing in...</title>
<body style="font:13px/1.5 monospace;padding:24px">
signing in...
<script>
(function () {
  var h = location.hash ? location.hash.substring(1) : "";
  var p = new URLSearchParams(h);
  var t = p.get("access_token");
  try {
    if (window.opener) {
      window.opener.postMessage({ p8lb: "token", token: t || null }, "*");
    }
  } catch (e) {
  }
  document.body.textContent = t ? "signed in, you can close this."
                                : "sign in failed, you can close this.";
  setTimeout(function () {
    try {
      window.close();
    } catch (e) {
    }
  }, 400);
})();
</script>`;
  return new Response(html, {
    headers: { "content-type": "text/html;charset=utf-8" }
  });
}

async function handleWhoami(request) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return bad("bad json");
  }

  const user = await resolveItchUser(body && body.token);
  if (!user) {
    return json({ username: null });
  }
  return json({ username: user.username });
}

async function handleSubmit(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return bad("bad json");
  }

  const gameId = String((body && body.game_id) || "").substring(0, 64);
  if (!gameId) {
    return bad("missing game_id");
  }

  const score = Number(body && body.score);
  if (!isFinite(score)) {
    return bad("bad score");
  }
  if (score > P8_MAX || score < P8_MIN) {
    return bad("score out of range");
  }

  const user = await resolveItchUser(body && body.token);
  if (!user) {
    return bad("not signed in", 401);
  }


  // We store one row per player. A new score is only
  // stored if its better than the existing score.
  await env.DB.prepare(
    `insert into scores (game_id,user_id,username,score,updated_at)
     values (?1,?2,?3,?4,?5)
     on conflict(game_id,user_id) do update set
       score      = max(scores.score, excluded.score),
       username   = excluded.username,
       updated_at = case when excluded.score > scores.score
                         then excluded.updated_at
                         else scores.updated_at end`
  ).bind(gameId, user.id, user.username, score, Date.now()).run();

  return json({ ok: true, username: user.username });
}

async function handleTop(url, env) {
  const gameId = String(url.searchParams.get("game_id") || "").substring(0, 64);
  if (!gameId) {
    return bad("missing game_id");
  }

  let n = parseInt(url.searchParams.get("n") || "10", 10);
  if (!isFinite(n) || n < 1) {
    n = 10;
  }
  if (n > 100) {
    n = 100;
  }

  const { results } = await env.DB.prepare(
    `select username, score from scores
     where game_id = ?1
     order by score desc, updated_at asc
     limit ?2`
  ).bind(gameId, n).all();

  return json({
    rows: (results || []).map((r) => {
      return { name: r.username, score: r.score };
    })
  });
}


/* Entry */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    try {
      if (url.pathname === "/auth" && request.method === "GET") {
        return authPage();
      }
      if (url.pathname === "/whoami" && request.method === "POST") {
        return await handleWhoami(request);
      }
      if (url.pathname === "/submit" && request.method === "POST") {
        return await handleSubmit(request, env);
      }
      if (url.pathname === "/top" && request.method === "GET") {
        return await handleTop(url, env);
      }
    } catch (e) {
      return json({ error: "server error" }, 500);
    }

    return json({ error: "not found" }, 404);
  }
};
