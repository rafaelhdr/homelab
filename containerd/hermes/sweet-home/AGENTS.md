# Grocery List

The household provisions are kept in a single file at:
/opt/data/profiles/sweet-home/grocery.md

It has two sections, marked by headings:
- `## Grocery` — things that need buying
- `## Storeroom` — things already in the root cellar (reserves)

The file is the single source of truth — NOT your conversation memory. Always
read the file before changing it, and write changes back immediately.

## Understand these in plain language (no commands needed)

### Adding to the grocery list (default: "add milk", "we need potatoes")
- Read the file first.
- Check the Storeroom section. If the item is already there, warn the user:
  *"Hold on — we've got [item] in the storeroom already. Is it really there?"*
- Wait for the user to confirm. When they confirm they're taking it from the
  storeroom: remove the line from `## Storeroom` and append it under
  `## Grocery` (so they buy a replacement for the cellar).
- If the item is NOT in the storeroom, just append it under `## Grocery`.
- If it's already under `## Grocery`, say so rather than adding a duplicate.

### Adding to the storeroom ("add rice to storeroom", "put flour in the cellar")
- Read the file first.
- Append the item under `## Storeroom`.
- If it's already there, say so.

### Using from the storeroom ("use rice from storeroom", "I took pasta from the cellar")
- Read the file first.
- If the item is under `## Storeroom`: remove it from there and append it
  under `## Grocery` (they'll need to buy more to restock).
- If it's not there, let them know.

### Removing ("got the milk", "bought bread", "cross off eggs")
- Read the file first.
- Delete the matching line from whichever section it's in (match loosely,
  case-insensitive).
- Don't remove items from storeroom unless explicitly asked — removing means
  "I bought this" / "I got this", which only applies to the grocery section.

### Showing ("what's on the list?", "read me the list", "what's in the storeroom?", bare "list")
- Read the file and show the current items, keeping the sections together.
- Plain "list" on its own always means the grocery list, not the calendar
  agenda — see "Showing the agenda" under Calendar for that.

## If the file doesn't exist or is empty, initialise it with:
```
## Grocery

## Storeroom
```

## Rules
- One item per line under its section. Keep it tidy.
- Never reorder or rewrite lines you weren't asked to touch.
- After any change, confirm in your own voice and show what you changed.
- If both sections are empty, say the pantry's well stocked.
- When in doubt, the default list is Grocery — "add X" means the grocery list,
  not the storeroom.

# Calendar

Appointments live in two files, next to grocery.md:
- `/opt/data/profiles/sweet-home/future-appointments.md` — everything still
  ahead of us.
- `/opt/data/profiles/sweet-home/past-appointments.md` — a log of one-off
  appointments that have already happened.

`future-appointments.md` has two sections:
- `## Recurring` — rules that repeat forever, one per line, format
  `Every <Weekday> <HH:MM> — <description>` (e.g. `Every Monday 14:00 —
  Dentist appointment`).
- `## Upcoming` — one-off dated appointments, one per line, format
  `<YYYY-MM-DD> — <description>`, optionally with a time:
  `<YYYY-MM-DD> <HH:MM> — <description>` (e.g. `2026-08-18 — Go to
  Amsterdam`). Not every one-off appointment has a time — that's fine, treat
  it as an all-day event.
  - Multi-day events use a date range instead of a single date:
    `<YYYY-MM-DD> to <YYYY-MM-DD> — <description>` (e.g. `2026-07-01 to
    2026-07-10 — Friend visiting`). This is one single line/event spanning
    every day in that span (inclusive), the same way a multi-day all-day
    event works in Google Calendar — not a shorthand for ten separate
    entries.

`past-appointments.md` is a flat log, one line per past one-off appointment,
same format as `## Upcoming`: `<YYYY-MM-DD> — <description>` (with time if it
had one), or `<YYYY-MM-DD> to <YYYY-MM-DD> — <description>` for a multi-day
event once it's fully over. Recurring appointments are never logged here —
only one-off ones.

These files are the single source of truth, same as the grocery list. Always
read before changing, and write changes back immediately.

## Date conventions
- Dates are always stored on disk as ISO `YYYY-MM-DD` — that part is
  unambiguous and never changes.
- When the user speaks a numeric date, they mean day/month order, never the
  US month/day order. `5/8` means the 5th of August, not May 8th. `01/07/2026`
  means 1st July 2026, not January 7th. Always parse numeric dates as
  DD/MM(/YYYY).
- Written-out dates ("18th August", "the 5th of July") are already
  unambiguous and don't need this rule — it only matters for slash/dash
  numeric shorthand.
- When you say a date back to the user (confirmations, the agenda, history
  answers), say it in a form that can't be misread as MM/DD — spell the
  month out (e.g. "5 August" or "18th of August") rather than echoing
  `05/08`.

## Scheduling a recurring appointment ("every Monday at 2 PM", "weekly on Tuesdays")
- Read `future-appointments.md` first (initialise it if missing — see below).
- Check for a conflict (see "Conflict checking" below) against the requested
  weekday + time.
- Append a new line under `## Recurring` in the format above. Don't touch
  other lines.
- Confirm what you added, and mention the conflict warning if there was one.

## Scheduling a one-off appointment ("go to Amsterdam on 18th August")
- Read `future-appointments.md` first.
- Resolve the date: if no year is given, use the current year; if that date
  has already passed this year, use next year instead. Say out loud which
  date you resolved to, so the user can correct you if you guessed wrong.
- Check for a conflict against the resolved date + time (see below).
- Append a new line under `## Upcoming` in the format above. Don't touch
  other lines.
- Confirm what you added, and mention the conflict warning if there was one.

## Scheduling a multi-day appointment ("friend visiting between July 1st and July 10th", "staying at the cabin from the 3rd to the 6th")
- Read `future-appointments.md` first.
- Resolve both the start and end date the same way as a single-day
  appointment (default to current year, roll to next year if already
  passed). If the end date ends up earlier than the start date after
  resolving each independently, the range crosses a year boundary — roll the
  end date's year forward by one instead.
- Check for a conflict against every day in the range, inclusive (see
  "Conflict checking" below) — not just the start and end days.
- Append one line under `## Upcoming` in the format `<YYYY-MM-DD> to
  <YYYY-MM-DD> — <description>`. This is a single event, not one entry per
  day.
- Confirm what you added (say the resolved date range back), and mention
  every conflict warning found across the whole span — but add the
  appointment regardless. The user decides afterwards whether to keep or
  cancel whatever it conflicts with.

## Showing the agenda ("list agenda", "show agenda", "what's the agenda?", "what's coming up?")
- Read `future-appointments.md`.
- For each `## Recurring` rule, work out its next occurrence from today's
  date (e.g. "Every Monday 14:00" → the coming Monday).
- Combine that with every dated entry in `## Upcoming`, including ranges.
- List them together, soonest first, each with its date (and time, if it has
  one) and description. For a range, show the full span, and if today falls
  inside it, say it's ongoing (e.g. "Friend visiting, 1–10 Jul (ongoing)").
  If both sections are empty, say the agenda's clear.
- This is a different command from plain "list" — "list" alone always means
  the grocery list (see Grocery List above). Only "list agenda" / "agenda" /
  similar phrasing that explicitly names the agenda or calendar triggers
  this.

## Conflict checking
- Before adding any new appointment, scan both `## Recurring` (matching the
  same weekday) and `## Upcoming` (matching the same date) in
  `future-appointments.md`.
- If an existing appointment has an explicit duration or end time and it
  overlaps the new one, say so plainly — this is a real conflict.
- If durations aren't given (the common case), assume every appointment takes
  about 1 hour from its start time. If two appointments would land within
  about an hour of each other, warn the user it might be tight — but add the
  appointment anyway. Never refuse to add something over a possible conflict,
  just flag it.
- If the new appointment has no time (all-day) or the existing one doesn't,
  don't try to guess a time conflict — just note both are on the same day.
- **Multi-day ranges**: when the new or existing appointment is a date range,
  a conflict is anything (recurring or one-off) that falls on *any* day
  within that range, not just the start or end day. Check every day of the
  range against `## Recurring` (by weekday) and every other `## Upcoming`
  entry (by date, or by range overlap if the other entry is also a range).
  Warn about each specific date/appointment that conflicts (e.g. "heads up —
  your dentist appointment on the 4th falls in the middle of that visit"),
  but always add the new appointment regardless — the user decides
  afterwards whether to keep, move, or cancel the thing it conflicts with.

## Answering "what did we do on [date]"
- Read `past-appointments.md`.
- Resolve the date the same way as scheduling (default to current year,
  roll back a year instead of forward if the phrasing is clearly about the
  past and ambiguous).
- List every line matching that date, plainly — for a range entry, it
  matches if the queried date falls anywhere inside the range, not just on
  its start or end day.
- Also check `future-appointments.md`'s `## Upcoming` section for any range
  entry that has already started but hasn't ended yet (start date is on or
  before today) and whose span covers the queried date — it's still there
  because it hasn't been archived yet, but a day inside it has already
  happened and should still answer the question.
- If nothing matches, say nothing happened that day (or that you have no
  record of it).

## Housekeeping
- When a one-off `## Upcoming` appointment's date is in the past, move it:
  remove the line from `## Upcoming` and append it to `past-appointments.md`.
  This normally happens as part of the daily appointment check, but do it
  any time you notice a stale entry while reading the file for something
  else.
- A multi-day range entry only moves to `past-appointments.md` once its
  **end** date is in the past — not its start date. While the range has
  started but not yet ended, it stays in `## Upcoming` (it's ongoing).
- Recurring `## Recurring` entries are never moved or removed automatically —
  they stay until someone explicitly asks to cancel or change them.

## Daily appointment check (from the cron job)
- Look at today's date and weekday.
- Check `## Recurring` for a matching weekday, and `## Upcoming` for a
  matching date — a range entry matches every day from its start to its end
  date, inclusive, so it triggers on each day it's active, not just the
  first.
- If anything matches: send a short message naming today's appointment(s).
  For an ongoing range, mention that it's ongoing (e.g. "Friend visiting
  continues today"). For any one-off `## Upcoming` match whose date (or, for
  a range, whose *end* date) is today, move it to `past-appointments.md` as
  described above — a range only gets archived on the day its span ends, not
  every day it's active.
- If nothing matches: send no message at all. Do not say "nothing today" —
  silence means nothing today.

## Sunday weekly check (from the cron job)
- Do the daily check above for today (Sunday).
- Also look ahead: list every appointment landing between the coming Monday
  and Saturday — recurring rules whose weekday falls in that range, and any
  `## Upcoming` entries dated in that range, including a range entry that
  merely *overlaps* that window at all (starts before it and/or ends inside
  or after it) — mention it once, with its full span, rather than once per
  day.
- Always send a message on Sunday, even if the week ahead is empty (say so
  plainly rather than staying silent).

## If either file doesn't exist or is empty, initialise it with:

`future-appointments.md`:
```
## Recurring

## Upcoming
```

`past-appointments.md`:
```
## Past
```
