# Agent API — driving CompDeck from a chat bot

CompDeck is designed to sit behind a Slack/Discord/chat agent. The recommended
conversation flow keeps the human in control of the expensive step:

1. User: "make me a deck about ◯◯"
2. Agent calls **plan**, posts the per-page outline to the channel, asks OK / changes
3. User comments → agent calls **plan** again with `feedback` + `previousPlan` (any number of rounds)
4. User approves → agent replies "generating (~N minutes)", calls **create**, then posts the returned `editUrl`

All endpoints accept/return JSON and require `Authorization: Bearer <COMPDECK_API_TOKEN>`
when the token is configured. Errors come back as `{"error": "<human-readable reason>"}`.

## POST /api/generate/plan — make or revise a plan

Request:

```json
{
  "topic": "Product intro deck for remote workers, friendly tone, must include the ¥980/mo price",
  "pages": 5,                                 // optional — omit and the AI picks a count that fits the content
  "references": ["/api/assets/up-..."],      // optional, uploaded reference images
  "feedback": "swap page 3 for case studies", // optional (revision)
  "previousPlan": { ... },                    // optional (revision: pass the previous plan back verbatim)
  "research": true,                           // optional: web-search facts (pricing, names, track record) first (+30–60 s)
  "researchNotes": "..."                      // optional: pass back from a previous response to skip re-searching on revisions
}
```

Response (60–90 s):

```json
{
  "plan": {
    "title": "...",
    "theme": { "colors": { "brand": "#...", ... }, "headingFont": "...", "bodyFont": "..." },
    "pages": [
      { "name": "...", "motif": "...", "space": "left|right|top|bottom|center",
        "imagePrompt": "...", "texts": [ { "role": "kicker|title|subtitle|body|stat|label", "text": "..." } ] }
    ]
  },
  "model": "gpt-5.5",
  "sources": [ { "url": "https://…", "title": "…" } ],  // when research was used — show these to the user
  "researchNotes": "…"                                   // pass back on revisions
}
```

Hold `plan` in your conversation state; render `pages[].name` + `texts[].text` for the
user, pass their comments through as `feedback` without over-interpreting.

## POST /api/decks — generate from an approved plan (or save a deck)

```json
{ "plan": { ...approved plan... } }
```

Response (~1 min/page; allow a 900 s timeout):

```json
{ "id": "…", "editUrl": "http://host:3100/?deck=…&token=…", "title": "…", "pages": 5 }
```

`editUrl` opens the editor with the generated deck loaded; the access token is
embedded, so it is click-to-open for anyone you share it with. Treat it accordingly.

Variants: `{"topic": "…", "pages": 5}` generates without the review step;
`{"deck": { ...deck json... }}` just saves and returns a share link.

## GET /api/decks — list saved decks

```json
{ "decks": [ { "id": "…", "title": "…", "pages": 5,                                 // optional — omit and the AI picks a count that fits the content "updatedAt": 1780000000000 } ] }
```

Useful for "open the deck we made last week". Fetch one with `GET /api/decks/:id`,
delete with `DELETE /api/decks/:id`.

## Practical notes

- **Call CompDeck via the URL your users can also reach** (not `localhost`):
  `editUrl` is built from the request's origin.
- Generation is slow by design (image quality `high`); reply to the user *before*
  calling create, not after.
- The plan endpoint is cheap and fast relative to generation — iterate freely there.
