// FLAPPY JONK — world leaderboard.
// GET  /top10   -> [{name, score}, ...] best first
// POST /submit  -> {name, score, beers} with X-Jonk-Key header
//
// The database has no public address: this Worker IS the API. The key in
// the app keeps honest people honest; the sanity checks and the rate
// limit keep the rest merely amusing.

const MAX_PLAUSIBLE_SCORE = 500; // human record 62, the autopilot peaked at 109

export default {
  async fetch(req, env) {
    const url = new URL(req.url);

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

      // rate limit: one submit per IP per 15 seconds
      const ip = req.headers.get("CF-Connecting-IP") ?? "unknown";
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
