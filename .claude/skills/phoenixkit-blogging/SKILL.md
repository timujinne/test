---
name: phoenixkit-blogging
description: PhoenixKit Publishing module - DB-based CMS for creating posts, managing groups, publishing content, uploading images
tags: phoenixkit, publishing, cms, images, markdown
---

# PhoenixKit Publishing Quick Reference

> **Important**: The old file-based Blogging module (`priv/blogging/`, `/admin/blogging/`) has been
> replaced by the DB-based **Publishing module** (`phoenix_kit_publishing_*` tables, `/admin/publishing/`).

## Prerequisites

Publishing module must be enabled in DB settings:

```elixir
# In IEx or via tidewave:
PhoenixKit.Modules.Publishing.enable_system()
# Or directly:
PhoenixKit.Settings.update_setting("publishing_enabled", "true")
```

## Admin Routes

| URL | Purpose |
|-----|---------|
| `/admin/publishing` | Publishing dashboard (all groups overview) |
| `/admin/publishing/:group` | Posts list for specific group |
| `/admin/publishing/:group/new` | Create new post |
| `/admin/publishing/:group/:post_uuid/edit` | Edit existing post |
| `/admin/publishing/:group/:post_uuid/preview` | Preview post |
| `/admin/publishing/new-group` | Create new group |
| `/admin/publishing/edit-group/:group` | Edit group settings |
| `/admin/settings/publishing` | Publishing settings |

## Creating a Post (UI)

1. Navigate to `/admin/publishing/:group`
2. Click **"New Post"**
3. Write content in Markdown or PHK format
4. Auto-save enabled (changes saved automatically)
5. Set metadata in sidebar (slug, status, featured image)
6. Click **"Publish"** to make it live

## Creating a Post (Programmatic)

```elixir
alias PhoenixKit.Modules.Publishing

# 1. Create post record
{:ok, post} = Publishing.create_post("news", %{
  slug: "my-post-slug",
  primary_language: "en"
})

# 2. Update with content
Publishing.update_post("news", post, %{
  content: "# Post Title\n\nContent here...",
  title: "Post Title",
  language: "en",
  url_slug: "my-post-slug"
})

# 3. Publish version
Publishing.publish_version("news", post.uuid, 1)

# 4. Invalidate listing cache
Publishing.invalidate_cache("news")
```

## Group Management

```elixir
# Create new group (replaces "blog")
Publishing.add_group("News", mode: "timestamp", type: "blog")
Publishing.add_group("FAQ", mode: "slug", type: "faq")

# List groups
Publishing.list_groups()
# => [%{"name" => "News", "slug" => "news", "mode" => "timestamp", ...}]

# Get group
Publishing.get_group("news")
# => {:ok, %{"name" => "News", "slug" => "news", "mode" => "timestamp", ...}}

# Update group
Publishing.update_group("news", %{name: "Company News"})

# Soft-delete group
Publishing.trash_group("news")
```

### Group Modes

| Mode | URL structure | Best for |
|------|--------------|---------|
| `timestamp` | `/news/2025-01-15` | News, updates, chronological |
| `slug` | `/tutorials/getting-started` | Docs, evergreen content |

### Group Types

| Type | Item name | Purpose |
|------|-----------|---------|
| `blog` (default) | post/posts | Blog posts |
| `faq` | question/questions | FAQ entries |
| `legal` | document/documents | Legal documents |
| custom | configurable | Custom content types |

## Post Management

```elixir
alias PhoenixKit.Modules.Publishing

# List posts (with preferred language)
Publishing.list_posts("news", "en")

# Read post by slug
Publishing.read_post("news", "my-post-slug", "en")

# Read post by UUID
Publishing.read_post_by_uuid(post_uuid, "en")

# Update post content
Publishing.update_post("news", post, %{
  content: "Updated content...",
  title: "Updated Title",
  language: "en"
})

# Change status
Publishing.change_post_status("news", post_uuid, "published")
Publishing.change_post_status("news", post_uuid, "draft")
Publishing.change_post_status("news", post_uuid, "archived")

# Trash post
Publishing.trash_post("news", post_uuid)

# Find by URL slug (for routing)
Publishing.find_by_url_slug("news", "en", "my-post-slug")
```

## Image Upload

### Via API

```bash
# Upload image
curl -X POST http://localhost:4000/api/upload \
  -F "file=@image.jpg" \
  -H "Authorization: Bearer TOKEN"

# Response: { "file_id": "uuid", "status": "processing" }
```

### Image Variants

```
GET /file/:file_id/:variant/:token

Variants:
- original    (full size)
- thumbnail   (150x150)
- small       (300x300)
- medium      (800x600)
- large       (1920x1080)
```

### Using Images in Content

```markdown
![Alt text](/file/FILE_UUID/medium/TOKEN)
```

## Publishing Workflow

### Status Flow

```
draft → published → archived → draft (cycle)
```

### Status Behavior

| Status | Visible | Cached |
|--------|---------|--------|
| draft | No | No |
| published | Yes | Yes |
| archived | No | No |

### Versioning

```elixir
# Publish version
Publishing.publish_version("news", post_uuid, 1)

# Create new version (if auto-versioning is needed)
Publishing.create_new_version("news", post, %{reason: "major update"})

# List versions
Publishing.list_versions("news", "my-post-slug")
```

## Content Formats

### Markdown

```markdown
# Post Title

Introduction with **bold** and _italic_.

## Section Header

- Bullet point
- Another point

![Image](/file/FILE_UUID/medium/TOKEN)

[Link text](https://example.com)
```

### PHK (XML Components)

```xml
<Page>
  <Hero variant="split-image">
    <Headline>Welcome to Our Blog</Headline>
    <Subheadline>Latest news and updates</Subheadline>
    <CTA primary="true" action="/signup">Get Started</CTA>
    <Image src="/file/FILE_UUID/large/TOKEN" alt="Hero" />
  </Hero>
</Page>
```

## PHK Components

| Component | Props | Description |
|-----------|-------|-------------|
| `<Page>` | — | Page wrapper |
| `<Hero>` | variant: split-image, centered, minimal | Hero section |
| `<Headline>` | — | Main heading (h1) |
| `<Subheadline>` | — | Secondary heading |
| `<CTA>` | action, primary | Call-to-action button |
| `<Image>` | src, alt, class | Image element |
| `<Video>` | src, youtube, poster | Video player (MP4/YouTube/HLS) |

## Multilanguage Support

```elixir
# Add language to post
Publishing.add_language_to_post("news", post_uuid, "ru")
Publishing.add_language_to_post("news", post_uuid, "es")

# Delete language
Publishing.delete_language("news", post_uuid, "es")

# Set translation status
Publishing.set_translation_status("news", post_slug, version, "ru", "published")
```

## Cache Management

```elixir
# Invalidate listing cache (call after publish/update)
Publishing.invalidate_cache("news")

# Regenerate cache explicitly
Publishing.regenerate_cache("news")

# Check if cache exists
Publishing.cache_exists?("news")
```

## Troubleshooting

### Posts not showing / 302 redirect loop

1. Check `publishing_enabled` setting:
   ```elixir
   PhoenixKit.Settings.get_setting("publishing_enabled")
   # Must be "true"
   PhoenixKit.Modules.Publishing.enable_system()
   ```

2. Check post status is `published`:
   ```elixir
   Publishing.read_post("news", "my-slug", "en")
   # Check post.status == "published"
   ```

3. Invalidate cache:
   ```elixir
   Publishing.invalidate_cache("news")
   ```

### Session fingerprint mismatch in dev

In `config/dev.exs`:
```elixir
config :phoenix_kit,
  session_fingerprint_enabled: false
```

### Quick Tips

1. **Enable module first** — `publishing_enabled` must be `true` in DB settings
2. **Cache after publish** — always call `invalidate_cache/1` after publishing
3. **UUID is binary** — `post.uuid` is a binary UUID, not a string, use it as-is in API calls
4. **Slugs are unique per group** — each group has its own slug namespace
5. **Primary language** — set at post creation, determines default display language

---

For detailed architecture and API reference, see `references/full-reference.md`
