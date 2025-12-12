import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar.cjs"
import { PriceChart, DepthChart } from "./hooks"

// PhoenixKit JS - DO NOT REMOVE
import "./vendor/phoenix_kit"

// Theme Toggle Hook for Phoenix LiveView
// Handles theme switching between light and dark modes
const ThemeToggle = {
  mounted() {
    // Load saved theme from localStorage
    const savedTheme = localStorage.getItem('theme') || 'light';
    this.setTheme(savedTheme);

    // Set initial checkbox state
    if (savedTheme === 'dark') {
      this.el.checked = true;
    }

    // Listen for changes
    this.el.addEventListener('change', (e) => {
      const theme = e.target.checked ? 'dark' : 'light';
      this.setTheme(theme);
    });
  },

  setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }
};

let Hooks = { ThemeToggle, PriceChart, DepthChart };

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: { ...window.PhoenixKitHooks, ...Hooks }
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
