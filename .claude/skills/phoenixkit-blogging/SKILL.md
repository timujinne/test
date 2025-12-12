---
name: phoenixkit-blogging
description: PhoenixKit blog management - create posts, upload images, publish articles, manage blog sections
tags: phoenixkit, blogging, cms, images, markdown
---

# PhoenixKit Blogging Quick Reference

## Admin Routes

| URL | Purpose |
|-----|---------|
| `/admin/blogging` | Blog dashboard (all blogs overview) |
| `/admin/blogging/:blog` | Posts list for specific blog |
| `/admin/blogging/:blog/edit?new=true` | Create new post |
| `/admin/blogging/:blog/edit?path=...` | Edit existing post |
| `/admin/blogging/:blog/preview` | Preview post |
| `/admin/settings/blogging` | Manage blogs |
| `/admin/settings/blogging/new` | Create new blog |
| `/admin/settings/blogging/:blog/edit` | Edit blog settings |

## Creating a Post

1. Navigate to `/admin/blogging/:blog`
2. Click **"Create Post"**
3. Write content in Markdown or PHK format
4. Auto-save is enabled (changes saved automatically)
5. Set metadata in the sidebar (slug, status, featured image)

## Image Upload

### Via API
```bash
# Upload image
curl -X POST http://localhost:4000/api/upload \
  -F "file=@image.jpg" \
  -H "Authorization: Bearer TOKEN"

# Response: { "file_id": "uuid", "status": "processing" }
```

### Get Image URL
```
GET /file/:file_id/:variant/:token

Variants:
- original    (full size)
- thumbnail   (150x150)
- small       (300x300)
- medium      (800x600)
- large       (1920x1080)
```

### In Editor
- Drag-and-drop files to upload zone
- Click **"Upload Media"** button
- Select uploaded image from media library

### Using in Content
```markdown
![Alt text](/file/FILE_ID/medium/TOKEN)
```

## Publishing Workflow

### Status Flow
```
draft → published → archived → draft (cycle)
```

### Change Status
- In editor sidebar: click status dropdown
- Or edit YAML frontmatter:

```yaml
---
status: published
published_at: 2025-01-15T12:00:00Z
---
```

### Status Behavior
| Status | Visible | Cached |
|--------|---------|--------|
| draft | No | No |
| published | Yes | Yes |
| archived | No | No |

## Creating a New Blog/Section

1. Go to `/admin/settings/blogging/new`
2. Fill in:
   - **Name**: Display name (e.g., "Company News")
   - **Slug**: URL identifier (e.g., "news")
3. Choose storage mode:
   - **Timestamp**: Posts organized by date/time folders
   - **Slug**: Posts organized by slug folders
4. Click **Save**

### Storage Modes

**Timestamp mode** (default):
```
priv/blogging/news/
├── 2025-01-15/
│   └── 14:30/
│       ├── en.phk
│       └── es.phk
```

**Slug mode**:
```
priv/blogging/tutorials/
├── getting-started/
│   ├── en.phk
│   └── es.phk
```

## Content Formats

### Markdown
```markdown
# Post Title

Introduction paragraph with **bold** and _italic_ text.

## Section Header

- Bullet point
- Another point

![Image alt](/file/FILE_ID/medium/TOKEN)

[Link text](https://example.com)
```

### PHK (XML Components)
```xml
<Page>
  <Hero variant="split-image">
    <Headline>Welcome to Our Blog</Headline>
    <Subheadline>Latest news and updates</Subheadline>
    <CTA primary="true" action="/signup">Get Started</CTA>
    <Image src="/file/FILE_ID/large/TOKEN" alt="Hero" />
  </Hero>
</Page>
```

## PHK Components

| Component | Props | Description |
|-----------|-------|-------------|
| `<Page>` | - | Page wrapper |
| `<Hero>` | variant: split-image, centered, minimal | Hero section |
| `<Headline>` | - | Main heading (h1) |
| `<Subheadline>` | - | Secondary heading |
| `<CTA>` | action, primary | Call-to-action button |
| `<Image>` | src, alt, class | Image element |
| `<Video>` | src, youtube, poster | Video player (MP4/YouTube/HLS) |

## Post Metadata (YAML Frontmatter)

```yaml
---
slug: my-post-url                    # URL slug
status: draft                        # draft | published | archived
published_at: 2025-01-15T12:00:00Z   # ISO8601 datetime
featured_image_id: abc123            # Image UUID for preview
description: Post summary text       # SEO description
created_by_email: author@example.com # Author email (auto)
updated_by_email: editor@example.com # Last editor (auto)
---

# Post content starts here...
```

## Multilanguage Support

Each post can have multiple language versions:
- Files named by language code: `en.phk`, `es.phk`, `fr.phk`
- Add language via editor sidebar: **"Add Language"** button
- Switch between languages in editor tabs

## Quick Tips

1. **Preview before publish**: Use preview button to check rendering
2. **Featured image**: Set `featured_image_id` for post thumbnails
3. **SEO**: Always fill `description` in metadata
4. **URLs**: Use descriptive slugs for better SEO
5. **Caching**: Published posts are cached; changes invalidate cache automatically

---

For detailed architecture and API reference, see `references/full-reference.md`
