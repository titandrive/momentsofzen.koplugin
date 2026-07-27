# Moments of Zen

Moments of Zen is a [KOReader](https://github.com/koreader/koreader) plugin
that adds a quote widget to the Zen UI Home page.

The widget can show:

- Quotes from a custom Lua file
- Highlights from your KOReader annotations
- A mixture of both

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

The settings dialog selects Custom quotes, Annotations, or Both, and toggles
automatic font sizing.

## Custom quotes

Create this file:

```text
koreader/settings/Zen UI/custom_quotes.lua
```

The file must return a Lua table. Each entry uses:

- `q`: quote text
- `a`: author
- `b`: book title

Example:

```lua
return {
    {
        q = "A reader lives a thousand lives before he dies.",
        a = "George R. R. Martin",
        b = "A Dance with Dragons",
    },
    {
        q = "So many books, so little time.",
        a = "Frank Zappa",
        b = "",
    },
}
```

An example file is included as `custom_quotes.example.lua`.

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
