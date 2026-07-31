# Moments of Zen: A Zen UI plugin (deprecated)

> [!IMPORTANT]
> **This plugin is deprecated.** Its functionality is built into
> [Zen UI](https://github.com/AnthonyGress/zen_ui.koplugin) 3.0 Beta 2 and
> later. Use Zen UI's built-in Quotes widget instead, and do not install this
> standalone plugin alongside it.

Moments of Zen is a [KOReader](https://github.com/koreader/koreader) plugin
that adds a quote widget to the [Zen UI](https://github.com/AnthonyGress/zen_ui.koplugin) Home page.

<img width="300" alt="ZenUI homescreen with Moments of Zen widget" src="https://github.com/user-attachments/assets/b528aa30-e37a-4205-8ed0-c83abdfc3612" />

The widget can show:

- Zen UI's built-in quotes
- Quotes from a custom Lua file
- Highlights from your KOReader annotations
- Any combination of those sources

Quotes are drawn from persistent shuffled decks: every quote in a source is
shown before that source reshuffles, and the sequence survives restarts.

## Installation

Copy `momentsofzen.koplugin` into:

```text
koreader/plugins/
```

Restart KOReader, then enable **Moments of Zen** under
**Zen UI → Home → Widgets**.

## Controls

- Swipe left: next quote
- Swipe right: previous quote from the current session
- Tap an annotation quote: open its book at the highlighted location
- Hold in Home edit mode: open widget settings

The settings dialog controls quote sources, daily or Home-refresh rotation,
automatic or fixed font sizing, the automatic maximum size, and separate
author/title visibility.

## Custom quotes

Create this file:

```text
koreader/settings/Zen UI/quotes.lua
```

The file must return a Lua table. Each entry uses:

- `text`: quote text
- `author`: author (optional)
- `title`: book title (optional)

The original Zen UI format, plain strings, and the older `q`/`a`/`b` format
remain supported.

Example:

```lua
return {
    {
        text = "A reader lives a thousand lives before he dies.",
        author = "George R. R. Martin",
        title = "A Dance with Dragons",
    },
    {
        text = "So many books, so little time.",
        author = "Frank Zappa",
    },
}
```

An example file is included as `quotes.example.lua`.

## Annotation quotes

The plugin reads highlights from KOReader document sidecars for books found in
reading history and the book-info cache. Added, edited, and deleted annotations
invalidate the in-session cache automatically.

Annotation attribution is displayed as:

```text
— Book title, Author
```

Custom quote attribution is displayed as:

```text
— Author, Book title
```
