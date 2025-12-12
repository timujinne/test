# PhoenixKit Blogging - Full Reference

## System Architecture

### Overview
PhoenixKit Blogging is a **file-based CMS** integrated into PhoenixKit v1.6.14+. Posts are stored as `.phk` files in the filesystem, not in a database.

### Key Modules

| Module | Location | Purpose |
|--------|----------|---------|
| `PhoenixKitWeb.Live.Modules.Blogging` | `deps/phoenix_kit/lib/phoenix_kit_web/live/modules/blogging/blogging.ex` | Main context (549 lines) |
| `Blogging.Storage` | `context/storage.ex` | File system operations (1000+ lines) |
| `Blogging.Metadata` | `context/metadata.ex` | YAML frontmatter parsing |
| `Blogging.PageBuilder` | `context/page_builder.ex` | PHK rendering |
| `PhoenixKit.Blogging.Renderer` | `deps/phoenix_kit/lib/phoenix_kit/blogging/renderer.ex` | Post rendering with caching |

### LiveView Components

| Component | File | Purpose |
|-----------|------|---------|
| Index | `index.ex` | Blog dashboard |
| Blog | `blog.ex` | Posts list |
| Editor | `editor.ex` | Post editor |
| New | `new.ex` | Create blog |
| Edit | `edit.ex` | Edit blog settings |
| Settings | `settings.ex` | Blogging settings |
| Preview | `preview.ex` | Post preview |

---

## File Storage

### Directory Structure

```
priv/blogging/
├── blog-slug-1/           # Blog directory
│   ├── 2025-01-15/        # Date folder (timestamp mode)
│   │   └── 14:30/         # Time folder
│   │       ├── en.phk     # English version
│   │       ├── es.phk     # Spanish version
│   │       └── fr.phk     # French version
│   └── another-post/      # Slug folder (slug mode)
│       └── en.phk
├── blog-slug-2/
│   └── ...
└── .trash/                # Deleted blogs
```

### Storage Modes

**Timestamp Mode** (default):
- Posts organized by `YYYY-MM-DD/HH:MM/`
- Good for news, updates, chronological content
- Post order determined by timestamp

**Slug Mode**:
- Posts organized by slug folder name
- Good for tutorials, docs, evergreen content
- Custom ordering via metadata

---

## Data Schemas

### Post Type
```elixir
@type post :: %{
  blog: String.t(),              # Blog slug
  slug: String.t(),              # Post slug (slug mode)
  date: Date.t(),                # Post date (timestamp mode)
  time: Time.t(),                # Post time (timestamp mode)
  path: String.t(),              # Relative path
  full_path: String.t(),         # Absolute file path
  metadata: metadata(),          # YAML frontmatter
  content: String.t(),           # Post content
  language: String.t(),          # Current language (en, es, etc.)
  available_languages: [String.t()], # All translations
  mode: :slug | :timestamp       # Storage mode
}
```

### Metadata Type
```elixir
@type metadata :: %{
  status: String.t(),            # "draft" | "published" | "archived"
  title: String.t(),             # Extracted from # heading
  description: String.t(),       # SEO description
  slug: String.t(),              # URL slug
  published_at: String.t(),      # ISO8601 datetime
  featured_image_id: String.t(), # Image UUID
  created_at: String.t(),        # Creation timestamp
  created_by_id: String.t(),     # Creator user ID
  created_by_email: String.t(),  # Creator email
  updated_by_id: String.t(),     # Last editor ID
  updated_by_email: String.t()   # Last editor email
}
```

### YAML Frontmatter Format
```yaml
---
slug: post-url-slug
status: published
published_at: 2025-01-15T12:00:00Z
featured_image_id: 018e3c4a-9f6b-7890-abcd-ef1234567890
description: Brief post description for SEO
created_by_id: user-uuid
created_by_email: author@example.com
updated_by_id: editor-uuid
updated_by_email: editor@example.com
---

# Post Title

Content starts here...
```

---

## Image Storage System

### Architecture
Images are managed by PhoenixKit Storage module, separate from blogging.

### Storage Location
```
priv/media/
├── 6e/
│   └── 6e9d8ed23e82e6c9faeab77b80e2ede4/
│       ├── 6e9d8ed23e82e6c9faeab77b80e2ede4_original.png
│       ├── 6e9d8ed23e82e6c9faeab77b80e2ede4_thumbnail.jpg
│       ├── 6e9d8ed23e82e6c9faeab77b80e2ede4_small.jpg
│       ├── 6e9d8ed23e82e6c9faeab77b80e2ede4_medium.jpg
│       └── 6e9d8ed23e82e6c9faeab77b80e2ede4_large.jpg
```

### Image Variants

| Variant | Size | Quality | Format |
|---------|------|---------|--------|
| original | Full | - | Original |
| thumbnail | 150x150 | 85% | JPEG |
| small | 300x300 | 85% | JPEG |
| medium | 800x600 | 85% | JPEG |
| large | 1920x1080 | 85% | JPEG |

### Video Variants

| Variant | Size | CRF | Format |
|---------|------|-----|--------|
| 360p | 640x360 | 28 | MP4 |
| 720p | 1280x720 | 28 | MP4 |
| 1080p | 1920x1080 | 28 | MP4 |
| video_thumbnail | 640x360 | 85% | JPEG |

### Database Tables
- `phoenix_kit_files` - Original file records
- `phoenix_kit_file_instances` - Generated variants
- `phoenix_kit_file_locations` - Physical storage tracking
- `phoenix_kit_buckets` - Storage configuration
- `phoenix_kit_storage_dimensions` - Variant presets

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
  "status": "processing",
  "message": "File uploaded successfully"
}
```

### Get File
```http
GET /file/:file_id/:variant/:token

Parameters:
- file_id: UUID of the file
- variant: original, thumbnail, small, medium, large
- token: Signed URL token

Response: File binary with caching headers
```

### Get File Info
```http
GET /api/files/:file_id/info

Response:
{
  "file_id": "uuid",
  "original_filename": "photo.jpg",
  "mime_type": "image/jpeg",
  "file_type": "image",
  "size": 1234567,
  "width": 1920,
  "height": 1080,
  "status": "active",
  "variants": [
    {
      "variant_name": "original",
      "url": "/file/uuid/original/token",
      "size": 1234567
    },
    {
      "variant_name": "medium",
      "url": "/file/uuid/medium/token",
      "size": 234567
    }
  ]
}
```

---

## Blogging Context Functions

### Blog Management
```elixir
# List all blogs
Blogging.list_blogs()
# => [%{name: "News", slug: "news", mode: :timestamp}, ...]

# Create new blog
Blogging.add_blog("News", "news", :timestamp)
# => {:ok, %{name: "News", slug: "news"}}

# Update blog
Blogging.update_blog("news", %{name: "Company News"})

# Delete blog (move to trash)
Blogging.trash_blog("news")

# Get blog mode
Blogging.get_blog_mode("news")
# => :timestamp | :slug
```

### Post Management
```elixir
# List posts
Blogging.list_posts("news", "en")
# => [%{slug: "...", metadata: %{...}, ...}, ...]

# Read post
Blogging.read_post("news", "2025-01-15/14:30", "en")
# => {:ok, %{content: "...", metadata: %{...}}}

# Create post
Blogging.create_post("news", %{
  content: "# Title\n\nContent...",
  language: "en",
  metadata: %{status: "draft"}
})

# Update post
Blogging.update_post("news", "2025-01-15/14:30", "en", %{
  content: "Updated content...",
  metadata: %{status: "published"}
})

# Add language to post
Blogging.add_language_to_post("news", "2025-01-15/14:30", "es")
```

### Utility Functions
```elixir
# Validate slug format
Blogging.valid_slug?("my-post")
# => true

# Generate slug from text
Blogging.slugify("My Post Title!")
# => "my-post-title"

# Check if module enabled
Blogging.enabled?()
# => true
```

---

## Rendering System

### Content Processing Pipeline
```
1. Read .phk file
2. Parse YAML frontmatter → metadata
3. Extract content
4. Detect format (PHK XML or Markdown)
5. Parse to AST
6. Resolve components
7. Inject variables ({{var}})
8. Apply theme/variants
9. Render to HTML
10. Cache result (if published)
```

### Renderer Functions
```elixir
# Render post with caching
PhoenixKit.Blogging.Renderer.render_post(post)
# => {:ok, html_string}

# Render markdown/PHK content directly
PhoenixKit.Blogging.Renderer.render_markdown(content)
# => html_string

# Invalidate post cache
PhoenixKit.Blogging.Renderer.invalidate_cache(blog, path, language)

# Clear all cache
PhoenixKit.Blogging.Renderer.clear_all_cache()
```

### Caching Behavior
- Only **published** posts are cached
- Cache key includes MD5 hash of content
- Content changes automatically invalidate cache
- Drafts and archived posts never cached

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

### Headlines
```xml
<Headline>Main Heading (H1)</Headline>
<Subheadline>Secondary Heading</Subheadline>
```

### Call-to-Action
```xml
<CTA action="/path" primary="true">Button Text</CTA>
<CTA action="https://external.com" primary="false">Secondary</CTA>
```

### Image
```xml
<Image
  src="/file/FILE_ID/medium/TOKEN"
  alt="Description"
  class="rounded-lg shadow"
/>
```

### Video
```xml
<!-- MP4 file -->
<Video src="/file/VIDEO_ID/720p/TOKEN" poster="/file/THUMB_ID/medium/TOKEN" />

<!-- YouTube -->
<Video youtube="dQw4w9WgXcQ" />

<!-- HLS stream -->
<Video src="https://stream.example.com/video.m3u8" />
```

---

## Multilanguage Support

### Language Files
Each language version is a separate file:
```
priv/blogging/news/post-slug/
├── en.phk    # English
├── es.phk    # Spanish
├── fr.phk    # French
├── de.phk    # German
└── zh.phk    # Chinese
```

### Adding Languages
1. In editor, click **"Add Language"**
2. Select target language
3. Content is copied from current language
4. Translate and save

### Language Detection
- URL parameter: `?lang=es`
- Accept-Language header
- User preference (if logged in)
- Default: first enabled language

### Enabled Languages
Configured in PhoenixKit settings. Common codes:
- `en` - English
- `es` - Spanish
- `fr` - French
- `de` - German
- `pt` - Portuguese
- `zh` - Chinese
- `ja` - Japanese
- `ko` - Korean

---

## Configuration

### PhoenixKit Config
```elixir
# config/config.exs
config :phoenix_kit,
  parent_app_name: :dashboard_web,
  parent_module: DashboardWeb,
  repo: SharedData.Repo,
  layouts_module: DashboardWeb.Layouts
```

### Router Integration
```elixir
# router.ex
import PhoenixKitWeb.Integration, only: [phoenix_kit_routes: 0]

scope "/admin" do
  phoenix_kit_routes()
end
```

### Oban Queue (for file processing)
```elixir
# config/config.exs
config :dashboard_web, Oban,
  repo: SharedData.Repo,
  queues: [
    file_processing: 20
  ]
```

---

## Troubleshooting

### Posts not showing
1. Check status is `published`
2. Verify `published_at` is set
3. Check file permissions on `priv/blogging/`

### Images not loading
1. Verify file was processed (status: "active" in DB)
2. Check token validity
3. Ensure `priv/media/` directory exists

### Cache issues
```elixir
# Clear all blogging cache
PhoenixKit.Blogging.Renderer.clear_all_cache()

# Invalidate specific post
PhoenixKit.Blogging.Renderer.invalidate_cache("blog-slug", "post-path", "en")
```

### PHK not rendering
1. Ensure content starts with `<Page>` or `<Hero>`
2. Check XML syntax (properly closed tags)
3. Verify component names are capitalized

### Debugging
```elixir
# In IEx console
Blogging.list_blogs()
Blogging.list_posts("blog-slug", "en")
Blogging.read_post("blog-slug", "path", "en")
```

---

## File Upload Flow

```
User selects file
       ↓
POST /api/upload (multipart)
       ↓
UploadController.create/2
  - Validate MIME type
  - Validate size (<100MB)
  - Calculate checksum
  - Check deduplication
       ↓
Storage.store_file_in_buckets/5
  - Save to priv/media/
  - Create DB record
       ↓
Oban ProcessFileJob
  - Extract metadata
  - Generate variants
  - Update status
       ↓
File ready (status: "active")
       ↓
GET /file/:id/:variant/:token
```

---

## Best Practices

1. **Always set featured_image_id** for post thumbnails in listings
2. **Use medium variant** for in-content images (800x600)
3. **Use large variant** for hero images (1920x1080)
4. **Use thumbnail** for galleries and previews
5. **Set description** in metadata for SEO
6. **Use meaningful slugs** for better URLs
7. **Preview before publishing** to check rendering
8. **Use slug mode** for evergreen content (tutorials, docs)
9. **Use timestamp mode** for time-sensitive content (news, updates)
