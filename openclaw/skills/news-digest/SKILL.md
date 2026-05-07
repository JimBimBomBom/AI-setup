---
name: news-digest
description: >
  Fetch and summarize news from RSS feeds, then deliver a formatted digest.
  Use this skill when asked to read news, check headlines, create a news
  summary, or monitor specific RSS sources. Knows how to parse RSS/Atom XML,
  filter by recency, deduplicate stories, and format output for Discord.
read_when:
  - Fetching or summarizing news
  - Reading RSS feeds
  - Creating a daily digest or briefing
  - Monitoring news sources
---

# News Digest Skill

## What You Can Do

You can fetch any RSS/Atom feed using the `fetch` tool (HTTP GET), parse the
XML, filter articles by recency, and produce a formatted summary.

## Fetching an RSS Feed

Use the `fetch` tool with the feed URL. The response is XML — extract:
- `<item>` or `<entry>` elements (Atom uses `<entry>`)
- `<title>` — article headline
- `<pubDate>` or `<updated>` — publication date (parse ISO 8601 or RFC 822)
- `<description>` or `<summary>` — article summary/excerpt
- `<link>` — article URL

If a feed fails, skip it and continue with the others.

## Configured Sources

### World News
| Source       | URL                                                        |
|--------------|------------------------------------------------------------|
| BBC News     | https://feeds.bbci.co.uk/news/rss.xml                      |
| CNN          | https://rss.cnn.com/rss/edition.rss                        |
| Reuters      | https://feeds.reuters.com/reuters/topNews                  |
| The Guardian | https://feeds.theguardian.com/theguardian/rss              |
| Al Jazeera   | https://www.aljazeera.com/xml/rss/all.xml                  |

### Tech News
| Source       | URL                                                        |
|--------------|------------------------------------------------------------|
| TechCrunch   | https://techcrunch.com/feed/                               |
| Hacker News  | https://news.ycombinator.com/rss                           |
| The Verge    | https://www.theverge.com/rss/index.xml                     |
| Ars Technica | http://feeds.arstechnica.com/arstechnica/index             |

## Filtering Rules

1. **Recency**: Only include articles published within the last 24 hours.
2. **Deduplication**: If multiple sources cover the same story, keep the best
   summary and attribute it to both sources.
3. **Relevance**: Skip press releases, sponsored content, and listicles unless
   they are unusually significant.
4. **Volume cap**: Maximum 15 articles in a world digest, 12 in a tech digest.

## Output Format for Discord

Discord messages must be under 1900 characters. If the digest is longer, split
it into 2–3 messages, each complete on its own.

```
**📰 World News Digest — {date}**

**Top Stories**
- **[Headline]** — 2-3 sentence summary. *(BBC, Reuters)*
- **[Headline]** — 2-3 sentence summary. *(CNN)*

**Business & Economy**
- **[Headline]** — 2-3 sentence summary. *(The Guardian)*

**World Affairs**
- **[Headline]** — 2-3 sentence summary. *(Al Jazeera)*

*{N} articles reviewed from {M} sources*
```

For tech digests, use sections like **AI & Machine Learning**, **Product
Launches**, **Startups**, **Industry News**.

Use `**bold**` for headlines and source names. Use `-` bullet points.
Avoid raw URLs in the output — they clutter Discord.
