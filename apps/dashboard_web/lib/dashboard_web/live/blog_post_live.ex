defmodule DashboardWeb.BlogPostLive do
  @moduledoc """
  Blog post detail page that displays a single post from PhoenixKit blogging module.
  Uses drawer layout with working user avatar.
  """
  use DashboardWeb, :live_view

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case load_post(slug) do
      {:ok, post} ->
        socket =
          socket
          |> assign(page_title: post.title)
          |> assign(current_path: "/articles/#{slug}")
          |> assign(post: post)
          |> assign(not_found: false)

        {:ok, socket}

      :not_found ->
        socket =
          socket
          |> assign(page_title: "Post Not Found")
          |> assign(current_path: "/articles")
          |> assign(post: nil)
          |> assign(not_found: true)

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @not_found do %>
      <div class="space-y-6">
        <div class="alert alert-warning">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="stroke-current shrink-0 h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>
          <span>Post not found.</span>
        </div>
        <.link navigate="/articles" class="btn btn-primary">
          ← Back to Blog
        </.link>
      </div>
    <% else %>
      <article class="max-w-4xl mx-auto">
        <%!-- Breadcrumb --%>
        <div class="breadcrumbs text-sm mb-6">
          <ul>
            <li><.link navigate="/articles">Blog</.link></li>
            <li><%= @post.title %></li>
          </ul>
        </div>

        <%!-- Post Header --%>
        <header class="mb-8">
          <h1 class="text-4xl font-bold mb-4"><%= @post.title %></h1>
          <div class="flex items-center gap-4 text-base-content/70">
            <time datetime={@post.published_at}>
              <%= format_date(@post.published_at) %>
            </time>
          </div>
        </header>

        <%!-- Featured Image --%>
        <%= if @post.featured_image do %>
          <figure class="mb-8 rounded-xl overflow-hidden">
            <img
              src={@post.featured_image}
              alt={@post.title}
              class="w-full h-auto"
            />
          </figure>
        <% end %>

        <%!-- Post Content --%>
        <div class="prose prose-lg max-w-none">
          <%= Phoenix.HTML.raw(@post.content_html) %>
        </div>

        <%!-- Back link --%>
        <div class="mt-12 pt-8 border-t border-base-300">
          <.link navigate="/articles" class="btn btn-outline">
            ← Back to Blog
          </.link>
        </div>
      </article>
    <% end %>
    """
  end

  defp load_post(slug) do
    try do
      blogs = PhoenixKit.Modules.Blogging.list_blogs()
      blog = List.first(blogs)

      if blog do
        blog_slug = blog["slug"]

        case PhoenixKit.Modules.Blogging.read_post(blog_slug, slug, "en") do
          {:ok, post} ->
            {:ok, %{
              title: post.metadata.title,
              description: Map.get(post.metadata, :description),
              published_at: post.metadata.published_at,
              content_html: render_content(post.content),
              featured_image: get_featured_image(post),
              slug: post.slug
            }}

          _ ->
            :not_found
        end
      else
        :not_found
      end
    rescue
      _ -> :not_found
    end
  end

  defp render_content(content) when is_binary(content) do
    # Convert markdown to HTML
    case Earmark.as_html(content) do
      {:ok, html, _} -> html
      _ -> content
    end
  end
  defp render_content(_), do: ""

  defp get_featured_image(post) do
    file_id = Map.get(post.metadata, :featured_image_id)

    if file_id && is_binary(file_id) do
      PhoenixKit.Modules.Storage.URLSigner.signed_url(file_id, "medium")
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
