defmodule DashboardWeb.BlogLive do
  @moduledoc """
  Blog listing page that displays posts from PhoenixKit blogging module.
  Uses drawer layout with working user avatar.
  """
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    posts = load_blog_posts()

    socket =
      socket
      |> assign(page_title: "Blog")
      |> assign(current_path: "/articles")
      |> assign(posts: posts)
      |> assign(blog_name: "Blog")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold text-base-content"><%= @blog_name %></h1>
        <p class="mt-2 text-sm text-base-content/70">
          <%= length(@posts) %> <%= if length(@posts) == 1, do: "post", else: "posts" %>
        </p>
      </div>

      <%= if Enum.empty?(@posts) do %>
        <div class="alert alert-info">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            class="stroke-current shrink-0 w-6 h-6"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <span>No published posts yet.</span>
        </div>
      <% else %>
        <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <%= for post <- @posts do %>
            <article class="card bg-base-100 shadow-md hover:shadow-lg transition-shadow">
              <%= if post.featured_image do %>
                <figure class="h-40 w-full overflow-hidden rounded-t-2xl bg-base-300">
                  <img
                    src={post.featured_image}
                    alt={post.title}
                    class="h-full w-full object-cover"
                    loading="lazy"
                  />
                </figure>
              <% end %>
              <div class="card-body">
                <h2 class="card-title text-xl">
                  <.link navigate={post.url} class="hover:text-primary">
                    <%= post.title %>
                  </.link>
                </h2>

                <%= if post.description do %>
                  <p class="text-sm text-base-content/70 line-clamp-3">
                    <%= post.description %>
                  </p>
                <% end %>

                <div class="card-actions justify-between items-center mt-4">
                  <time class="text-xs text-base-content/60" datetime={post.published_at}>
                    <%= format_date(post.published_at) %>
                  </time>

                  <.link navigate={post.url} class="btn btn-sm btn-primary">
                    Read More →
                  </.link>
                </div>
              </div>
            </article>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp load_blog_posts do
    try do
      # Get the first blog (assuming single blog setup)
      blogs = PhoenixKitWeb.Live.Modules.Blogging.list_blogs()
      blog = List.first(blogs)

      if blog do
        blog_slug = blog["slug"]

        # Load posts from PhoenixKit - returns list directly, not {:ok, list}
        posts = PhoenixKitWeb.Live.Modules.Blogging.list_posts(blog_slug, "en")

        posts
        |> Enum.filter(fn post ->
          # Only show published posts
          post.metadata.status == "published"
        end)
        |> Enum.map(fn post ->
          %{
            title: post.metadata.title,
            description: Map.get(post.metadata, :description),
            published_at: post.metadata.published_at,
            url: "/articles/#{post.slug}",
            featured_image: get_featured_image(post),
            slug: post.slug
          }
        end)
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp get_featured_image(post) do
    file_id = Map.get(post.metadata, :featured_image_id)

    if file_id && is_binary(file_id) do
      PhoenixKit.Storage.URLSigner.signed_url(file_id, "medium")
    else
      nil
    end
  end

  defp format_date(nil), do: ""
  defp format_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> Calendar.strftime(d, "%B %d, %Y")
      _ -> date
    end
  end
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %d, %Y")
  defp format_date(_), do: ""
end
