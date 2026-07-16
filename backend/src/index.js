// FLAPPY JONK — world leaderboard.
// GET  /top10   -> [{name, score}, ...] best first
// GET  /privacy -> privacy policy (the App Store requires a public URL)
// POST /submit  -> {name, score, beers} with X-Jonk-Key header
//
// The database has no public address: this Worker IS the API. The key in
// the app keeps honest people honest; the sanity checks and the rate
// limit keep the rest merely amusing.

const MAX_PLAUSIBLE_SCORE = 500; // human record 62, the autopilot peaked at 109

// rate limiting needs "same sender within 15s", never the address itself:
// store a salted one-way hash so the database holds no readable IPs
async function ipHash(ip, pepper) {
  const data = new TextEncoder().encode(ip + pepper);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest.slice(0, 16))]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const SUPPORT_HTML = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Flappy Jonk — Support</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; max-width: 40em;
         margin: 2em auto; padding: 0 1em; line-height: 1.6; color: #222; }
  @media (prefers-color-scheme: dark) { body { background: #0a0f1a; color: #ddd; } }
  h1 { font-size: 1.5em; }
</style>
<h1>Flappy Jonk — Support</h1>
<p>Something broken? A question? An unbeatable score that demands
recognition? Email <a href="mailto:l@jonsson.es">l@jonsson.es</a> and a
human (the one on the title screen, in fact) will reply.</p>
<h2>Common questions</h2>
<p><strong>How do I play?</strong> Tap to flap. Dodge the pillars. Catch
the bäär. That is the entire manual.</p>
<p><strong>Where are the sound controls?</strong> On the title screen —
bottom of the screen on iPhone and iPad, top right on Mac (or press M
for sound, T for music).</p>
<p><strong>How do I get my name off the world leaderboard?</strong>
Email the name on the entry to the address above and it will be removed.</p>
<p><a href="/privacy">Privacy policy</a></p>
</html>`;

const PRIVACY_HTML = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Flappy Jonk — Privacy Policy</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; max-width: 40em;
         margin: 2em auto; padding: 0 1em; line-height: 1.6; color: #222; }
  @media (prefers-color-scheme: dark) { body { background: #0a0f1a; color: #ddd; } }
  h1 { font-size: 1.5em; }
</style>
<h1>Flappy Jonk — Privacy Policy</h1>
<p><em>Effective 16 July 2026</em></p>
<p>Flappy Jonk is a small arcade game. It shows no ads, uses no analytics or
tracking of any kind, and requires no account.</p>
<h2>On your device</h2>
<p>Your settings (sound/music) and local high scores are stored only on your
device and never leave it.</p>
<h2>The world leaderboard</h2>
<p>If you earn a place on the world leaderboard and choose to submit your
score, the game sends exactly this to our server: the name you type in
(anything you like), your score, how many bäärs you caught, and the time of
submission. The name and score are shown publicly in the game's world
top-10 list.</p>
<p>To prevent abuse, the server also stores a salted one-way hash of your
network address alongside the entry. The address itself is never stored and
cannot be recovered from the hash.</p>
<p>Leaderboard data is stored with Cloudflare (our hosting provider) and
kept until removed.</p>
<h2>Removal</h2>
<p>Want an entry removed from the leaderboard? Email
<a href="mailto:l@jonsson.es">l@jonsson.es</a> with the name on the entry
and it will be deleted.</p>
<h2>Contact</h2>
<p>Lars-Erik Jonsson — <a href="mailto:l@jonsson.es">l@jonsson.es</a></p>
</html>`;

export default {
  async fetch(req, env) {
    const url = new URL(req.url);

    if (req.method === "GET" && url.pathname === "/support") {
      return new Response(SUPPORT_HTML, {
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    }

    if (req.method === "GET" && url.pathname === "/privacy") {
      return new Response(PRIVACY_HTML, {
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    }

    if (req.method === "GET" && url.pathname === "/top10") {
      const { results } = await env.DB.prepare(
        "SELECT name, score FROM scores ORDER BY score DESC, created_at ASC LIMIT 10"
      ).all();
      return Response.json(results);
    }

    if (req.method === "POST" && url.pathname === "/submit") {
      if (req.headers.get("X-Jonk-Key") !== env.JONK_KEY) {
        return new Response("nope", { status: 401 });
      }
      let b;
      try { b = await req.json(); } catch { return new Response("bad json", { status: 400 }); }

      const name = String(b.name ?? "")
        .toUpperCase()
        .replace(/[^A-Z0-9ÅÄÖ ]/g, "")
        .trim()
        .slice(0, 10) || "ANONYMOUS";
      const score = Math.floor(Number(b.score));
      const beers = Math.floor(Number(b.beers ?? 0));

      // sanity: scores are small integers, and every beer is 3 of the points
      if (!Number.isFinite(score) || score < 1 || score > MAX_PLAUSIBLE_SCORE)
        return new Response("nice try", { status: 400 });
      if (!Number.isFinite(beers) || beers < 0 || beers * 3 > score)
        return new Response("nice try", { status: 400 });

      // rate limit: one submit per IP per 15 seconds (hashed, see ipHash)
      const ip = await ipHash(req.headers.get("CF-Connecting-IP") ?? "unknown", env.JONK_KEY);
      const recent = await env.DB.prepare(
        "SELECT COUNT(*) AS n FROM scores WHERE ip = ? AND created_at > datetime('now', '-15 seconds')"
      ).bind(ip).first();
      if (recent.n > 0) return new Response("slow down", { status: 429 });

      await env.DB.prepare(
        "INSERT INTO scores (name, score, beers, ip) VALUES (?, ?, ?, ?)"
      ).bind(name, score, beers, ip).run();
      return Response.json({ ok: true });
    }

    // --- admin: the ADMIN_KEY never ships inside the app ---
    if (req.method === "POST" && url.pathname === "/reset") {
      if (req.headers.get("X-Admin-Key") !== env.ADMIN_KEY)
        return new Response("nope", { status: 401 });
      await env.DB.prepare("DELETE FROM scores").run();
      return Response.json({ ok: true, cleared: true });
    }

    if (req.method === "POST" && url.pathname === "/remove") {
      if (req.headers.get("X-Admin-Key") !== env.ADMIN_KEY)
        return new Response("nope", { status: 401 });
      let b;
      try { b = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
      const name = String(b.name ?? "").toUpperCase().trim();
      if (!name) return new Response("no name", { status: 400 });
      const r = await env.DB.prepare("DELETE FROM scores WHERE name = ?").bind(name).run();
      return Response.json({ ok: true, removed: r.meta.changes });
    }

    return new Response("FLAPPY JONK WORLD LEADERBOARD", { status: 404 });
  },
};
