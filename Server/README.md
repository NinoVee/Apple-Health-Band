# AI Insights Relay

A minimal serverless proxy so the iOS app never holds your Anthropic or
OpenAI API key directly. The app calls this relay instead; the relay
(which does hold the keys, as server-only environment variables) forwards
the request to whichever provider you picked in the app's Settings.

```
iOS app  --(health summary + chat)-->  this relay  --(with your API key)-->  Anthropic / OpenAI
```

## Deploy to Vercel

1. `cd Server`
2. `npx vercel` and follow the prompts (or import this `Server/` folder
   as its own Vercel project from the dashboard, setting **Root
   Directory** to `Server`).
3. In the Vercel project's **Settings → Environment Variables**, add:
   - `RELAY_SHARED_SECRET` — a long random string you invent, e.g.
     `openssl rand -hex 32`. The app has to send this same value back
     (Settings → AI Insights → Shared Secret), so copy it there too.
     Without this set, anyone who finds your relay's URL can use it —
     set it.
   - `ANTHROPIC_API_KEY` — from console.anthropic.com. Needed only if
     you'll use Claude.
   - `OPENAI_API_KEY` — from platform.openai.com. Needed only if you'll
     use ChatGPT.
   - `CLAUDE_MODEL` / `OPENAI_MODEL` (optional) — override the default
     model IDs (`claude-sonnet-4-5` / `gpt-4o-mini`) if you want a
     different one. Check each provider's current model list at deploy
     time — these change.
4. Redeploy so the new environment variables take effect.
5. In the app, **Settings → AI Insights**:
   - Turn the toggle on
   - Set **Relay URL** to your deployment's URL plus `/api/chat`, e.g.
     `https://your-project.vercel.app/api/chat`
   - Paste the same **Shared Secret** from step 3

## Cost and abuse

Every message sent from the app is a real API call billed to your
Anthropic/OpenAI account. `RELAY_SHARED_SECRET` keeps random internet
traffic from hitting your endpoint, but it doesn't cap *your own*
spending — if you want a hard ceiling, set a usage budget/alert in your
Anthropic and OpenAI account dashboards directly, not just here.

## What gets sent

The app sends a short text summary built from the same numbers already
shown on the Today/Sensors/Scale tabs (steps, heart rate, SpO2, body
composition, etc. — see `Sources/AI/HealthContextBuilder.swift`), plus
the visible chat conversation. It never sends raw HealthKit samples or
anything beyond what's already displayed in the app.

If the user attaches a photo, it arrives here as `imageBase64` on that
message (downscaled/compressed on-device first) and this relay forwards
it as an image content block to whichever provider is selected — see
`toClaudeMessage`/`toOpenAIMessage` in `api/chat.js`.
