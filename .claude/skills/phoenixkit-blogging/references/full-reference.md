# PhoenixKit Publishing - Full Reference

## System Architecture

### Overview

PhoenixKit Publishing is a **database-backed CMS** (replaced the old file-based Blogging module). Posts are stored in PostgreSQL tables, not the filesystem.

### Database Tables

| Table | Purpose |
|-------|---------|
| `phoenix_kit_publishing_groups` | Content groups (formerly "blogs") |
| `phoenix_kit_publishing_posts` | Post records with UUID, slug, status |
| `phoenix_kit_publishing_versions` | Versioned snapshots of posts |
| `phoenix_kit_publishing_contents` | Language-specific content per version |

### Key Modules

| Module | Purpose |
|--------|---------|
| `PhoenixKit.Modules.Publishing` | Main facade (delegates to submodules) |
| `Publishing.Groups` | Group CRUD |
| `Publishing.Posts` | Post CRUD, reading, listing |
| `Publishing.Versions` | Version create, publish, delete |
| `Publishing.TranslationManager` | Language/translation management |
| `Publishing.DBStorage` | Raw DB operations (Ecto) |
| `Publishing.ListingCache` | Listing cache management |
| `Publishing.StaleFixer` | Stale value detection and repair |

### LiveView Admin Components

| Path | Module | Purpose |
|------|--------|---------|
| `/admin/publishing` | `Publishing.Web.Index` | Dashboard |
| `/admin/publishing/:group` | `Publishing.Web.Listing` | Posts list |
| `/admin/publishing/:group/new` | `Publishing.Web.Editor` | Create post |
| `/admin/publishing/:group/:post_uuid/edit` | `Publishing.Web.Editor` | Edit post |
| `/admin/publishing/:group/:post_uuid/preview` | `Publishing.Web.Preview` | Preview |
| `/admin/publishing/new-group` | `Publishing.Web.New` | Create group |
| `/admin/publishing/edit-group/:group` | `Publishing.Web.Edit` | Edit group |
| `/admin/settings/publishing` | `Publishing.Web.Settings` | Settings |

---

## Data Model

### Group Structure

```elixir
%{
  "name" => "News",          # Display name
  "slug" => "news",          # URL identifier (unique)
  "mode" => "timestamp",     # "timestamp" | "slug"
  "type" => "blog",          # "blog" | "faq" | "legal" | custom
  "status" => "active",      # "active" | "trashed"
  "item_singular" => "post", # e.g., "post", "question", "document"
  "item_plural" => "posts"
}
```

### Post Structure

```elixir
%{
  uuid: <<binary>>,          # Binary UUID (use as-is in API calls)
  slug: "my-post-slug",      # Post slug (unique per group)
  group_slug: "news",        # Parent group slug
  status: "published",       # "draft" | "published" | "archived"
  mode: "slug",              # Inherited from group
  primary_language: "en",    # Primary language code
  title: "Post Title",       # Current language title
  content: "# ...",          # Current language content
  language: "en",            # Currently loaded language
  available_languages: ["en", "ru"], # All translated languages
  metadata: %{
    published_at: "2026-03-26T12:00:00Z",
    featured_image_uuid: "...",
    url_slug: "custom-url",
    description: "SEO description"
  }
}
```

---

## Group API

```elixir
alias PhoenixKit.Modules.Publishing

# List all active groups
Publishing.list_groups()

# List by status
Publishing.list_groups("active")
Publishing.list_groups("trashed")

# Get group by slug
Publishing.get_group("news")          # {:ok, %{...}} | {:error, :not_found}

# Create group
Publishing.add_group("News")
Publishing.add_group("News", mode: "timestamp", type: "blog")
Publishing.add_group("FAQ", mode: "slug", type: "faq", slug: "faq")

# Update group
Publishing.update_group("news", %{name: "Company News"})
Publishing.update_group("news", %{name: "News", slug: "news"})

# Soft-delete
Publishing.trash_group("news")

# Restore
Publishing.restore_group("news")

# List trashed
Publishing.list_trashed_groups()

# Force delete with all posts
Publishing.remove_group("news", force: true)

# Get mode for group
Publishing.get_group_mode("news")     # "timestamp" | "slug"

# Get group name
Publishing.group_name("news")         # "News" | nil
```

---

## Post API

```elixir
alias PhoenixKit.Modules.Publishing

# Create post
Publishing.create_post("news")
Publishing.create_post("news", %{slug: "my-slug", primary_language: "en"})

# List posts
Publishing.list_posts("news")
Publishing.list_posts("news", "en")

# List by status
Publishing.list_posts_by_status("news", "published")
Publishing.list_posts_by_status("news", "draft")

# Read post
Publishing.read_post("news", "my-slug")
Publishing.read_post("news", "my-slug", "en")
Publishing.read_post("news", "my-slug", "en", 1)  # specific version

# Read by UUID (binary)
Publishing.read_post_by_uuid(post_uuid_bin)
Publishing.read_post_by_uuid(post_uuid_bin, "en")

# Update post
Publishing.update_post("news", post, %{
  content: "Updated content...",
  title: "New Title",
  language: "en",
  url_slug: "custom-url",      # optional custom URL slug
  status: "published"
})

# Change status
Publishing.change_post_status("news", post_uuid, "published")
Publishing.change_post_status("news", post_uuid, "draft")
Publishing.change_post_status("news", post_uuid, "archived")

# Trash / restore
Publishing.trash_post("news", post_uuid)
Publishing.restore_post("news", post_uuid)

# Find by URL slug (routing)
Publishing.find_by_url_slug("news", "en", "custom-url")

# Find by previous URL slug (301 redirects)
Publishing.find_by_previous_url_slug("news", "en", "old-url")

# Validate slug
Publishing.valid_slug?("my-post")     # true | false
Publishing.validate_slug("my-post")   # :ok | {:error, reason}

# Check slug exists
Publishing.slug_exists?("news", "my-post")  # true | false

# Generate unique slug
Publishing.generate_unique_slug("news", "Post Title")
Publishing.generate_unique_slug("news", "Post Title", "preferred-slug")
```

---

## Version API

```elixir
alias PhoenixKit.Modules.Publishing

# Publish current version (makes post publicly visible)
Publishing.publish_version("news", post_uuid, 1)

# List version numbers
Publishing.list_versions("news", "my-slug")    # [1, 2, 3]

# Get published version number
Publishing.get_published_version("news", "my-slug")  # {:ok, 1} | {:error, ...}

# Get version status
Publishing.get_version_status("news", "my-slug", 1, "en")  # "published" | "draft"

# Get version metadata
Publishing.get_version_metadata("news", "my-slug", 1, "en")

# Create new version from existing
Publishing.create_new_version("news", post, %{}, %{})

# Delete version
Publishing.delete_version("news", post_uuid, version_number)
```

---

## Translation API

```elixir
alias PhoenixKit.Modules.Publishing

# Add language version to post
Publishing.add_language_to_post("news", post_uuid, "ru")
Publishing.add_language_to_post("news", post_uuid, "es")

# Delete language version
Publishing.delete_language("news", post_uuid, "ru")

# Set translation status
Publishing.set_translation_status("news", post_slug, 1, "ru", "published")

# Update primary language
Publishing.update_post_primary_language("news", post_uuid, "en")

# Get primary language
Publishing.get_post_primary_language("news", "my-slug")

# Get enabled language codes
Publishing.enabled_language_codes()    # ["en", "ru"]

# Check language enabled
Publishing.language_enabled?("en", enabled_languages)
```

---

## Cache API

```elixir
alias PhoenixKit.Modules.Publishing

# Invalidate (clear) listing cache for group
Publishing.invalidate_cache("news")

# Regenerate cache explicitly
Publishing.regenerate_cache("news")

# Check if cache exists
Publishing.cache_exists?("news")

# Find post in cache
Publishing.find_cached_post("news", "my-slug")

# Find timestamp-mode post in cache
Publishing.find_cached_post_by_path("news", "2025-01-15", "14:30")
```

---

## Module Enable/Disable

```elixir
alias PhoenixKit.Modules.Publishing

# Check if enabled
Publishing.enabled?()    # true | false

# Enable
Publishing.enable_system()

# Disable (hides all public routes)
Publishing.disable_system()

# Or via settings directly
PhoenixKit.Settings.update_setting("publishing_enabled", "true")
PhoenixKit.Settings.get_setting("publishing_enabled")
```

---

## Programmatic Post Creation Workflow

Full example for creating and publishing a post programmatically (e.g., from IEx or a script):

```elixir
alias PhoenixKit.Modules.Publishing

group_slug = "news"
slug = "my-article"
content = """
# My Article Title

Article content in **Markdown**.

## Section

More content here.
"""

# 1. Create post record
{:ok, post} = Publishing.create_post(group_slug, %{
  slug: slug,
  primary_language: "en"
})

# 2. Update with actual content
Publishing.update_post(group_slug, post, %{
  content: content,
  title: "My Article Title",
  language: "en",
  url_slug: slug,
  status: "published"
})

# 3. Publish version (makes it publicly visible)
Publishing.publish_version(group_slug, post.uuid, 1)

# 4. Invalidate cache
Publishing.invalidate_cache(group_slug)
```

---

## Image Storage System

### Architecture

Images are managed by PhoenixKit Storage module, separate from publishing.

### Storage Location

```
priv/media/
└── 6e/
    └── 6e9d8ed23e82e6c9faeab77b80e2ede4/
        ├── ..._original.png
        ├── ..._thumbnail.jpg
        ├── ..._small.jpg
        ├── ..._medium.jpg
        └── ..._large.jpg
```

### Image Variants

| Variant | Size | Format |
|---------|------|--------|
| original | Full | Original |
| thumbnail | 150x150 | JPEG |
| small | 300x300 | JPEG |
| medium | 800x600 | JPEG |
| large | 1920x1080 | JPEG |

### Video Variants

| Variant | Size | Format |
|---------|------|--------|
| 360p | 640x360 | MP4 |
| 720p | 1280x720 | MP4 |
| 1080p | 1920x1080 | MP4 |
| video_thumbnail | 640x360 | JPEG |

### Database Tables

- `phoenix_kit_files` — Original file records
- `phoenix_kit_file_instances` — Generated variants
- `phoenix_kit_file_locations` — Physical storage tracking
- `phoenix_kit_buckets` — Storage configuration
- `phoenix_kit_storage_dimensions` — Variant presets

---

## API Endpoints

### Upload File

```http
POST /api/upload
Content-Type: multipart/form-data

file=@image.jpg

Response:
{
  "file_id": "018e3c4a-9f6b-7890-abcd-ef1234567890",
  "status": "processing"
}
```

### Get File

```http
GET /file/:file_id/:variant/:token
```

### Get File Info

```http
GET /api/files/:file_id/info

Response:
{
  "file_id": "uuid",
  "mime_type": "image/jpeg",
  "file_type": "image",
  "variants": [
    {"variant_name": "medium", "url": "/file/uuid/medium/token"}
  ]
}
```

---

## PHK Component Reference

### Page Wrapper

```xml
<Page>
  <!-- All content must be inside Page -->
</Page>
```

### Hero Section

```xml
<Hero variant="split-image">
  <Headline>Main Title</Headline>
  <Subheadline>Secondary text</Subheadline>
  <CTA primary="true" action="/signup">Get Started</CTA>
  <Image src="/file/ID/large/TOKEN" alt="Hero image" />
</Hero>

<!-- Variants: split-image, centered, minimal -->
```

### Image

```xml
<Image
  src="/file/FILE_UUID/medium/TOKEN"
  alt="Description"
  class="rounded-lg shadow"
/>
```

### Video

```xml
<!-- MP4 file -->
<Video src="/file/VIDEO_UUID/720p/TOKEN" poster="/file/THUMB_UUID/medium/TOKEN" />

<!-- YouTube -->
<Video youtube="dQw4w9WgXcQ" />

<!-- HLS stream -->
<Video src="https://stream.example.com/video.m3u8" />
```

### CTA

```xml
<CTA action="/path" primary="true">Button Text</CTA>
<CTA action="https://external.com" primary="false">Secondary</CTA>
```

---

## Configuration

### PhoenixKit Config

```elixir
# config/config.exs
config :phoenix_kit,
  repo: SharedData.Repo,
  url_prefix: "",
  from_email: "noreply@example.com",
  from_name: "My App"
```

### Dev Config (important)

```elixir
# config/dev.exs
# Disable fingerprinting — ephemeral ports cause false positives
config :phoenix_kit,
  session_fingerprint_enabled: false
```

### Oban Queues (for file processing)

```elixir
config :dashboard_web, Oban,
  queues: [
    file_processing: 20,
    posts: 10
  ]
```

---

## Rendering

### Content Processing

```
1. Fetch post record from DB (phoenix_kit_publishing_*)
2. Get content for language from phoenix_kit_publishing_contents
3. Detect format: PHK XML or Markdown
4. Parse to AST → resolve components
5. Render to HTML
6. Cache result (if published)
```

### Renderer Functions

```elixir
alias PhoenixKit.Modules.Publishing.Renderer

# Render markdown/PHK content
Renderer.render_markdown(content)    # => html_string
```

---

## Troubleshooting

### Module disabled (302 redirect loop)

```elixir
# Check status
PhoenixKit.Modules.Publishing.enabled?()

# Enable
PhoenixKit.Modules.Publishing.enable_system()
```

### Post not visible after publishing

```elixir
# Verify post status
post = PhoenixKit.Modules.Publishing.read_post("news", "my-slug", "en")
# post.status should be "published"

# Invalidate cache
PhoenixKit.Modules.Publishing.invalidate_cache("news")
```

### Session fingerprint mismatch (dev only)

Add to `config/dev.exs`:

```elixir
config :phoenix_kit, session_fingerprint_enabled: false
```

### PHK not rendering

1. Ensure content starts with `<Page>` or `<Hero>`
2. Check XML syntax (properly closed tags)
3. Verify component names are capitalized

---

## Best Practices

1. **Enable module first** — set `publishing_enabled` to `true` in settings
2. **Always invalidate cache** after publishing or updating posts
3. **Use UUID as-is** — `post.uuid` is a binary, pass it directly to API functions
4. **Set `url_slug`** in update_post for custom SEO-friendly URLs
5. **Use timestamp mode** for news/updates, slug mode for evergreen content
6. **Set primary language** at create time (cannot be changed without migration)
7. **Preview before publishing** — use `/admin/publishing/:group/:post_uuid/preview`
