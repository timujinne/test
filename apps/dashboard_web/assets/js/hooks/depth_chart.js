// Simple Canvas-based Depth Chart
export const DepthChart = {
  mounted() {
    // Create canvas
    this.canvas = document.createElement('canvas');
    this.canvas.style.width = '100%';
    this.canvas.style.height = '100%';
    this.el.appendChild(this.canvas);
    this.ctx = this.canvas.getContext('2d');

    // Store data
    this.bids = [];
    this.asks = [];

    // Initial resize
    this.resize();

    // Handle depth updates from LiveView
    this.handleEvent("depth_chart_update", ({ bids, asks }) => {
      this.bids = bids || [];
      this.asks = asks || [];
      this.draw();
    });

    // Resize observer
    this.resizeObserver = new ResizeObserver(() => {
      this.resize();
      this.draw();
    });
    this.resizeObserver.observe(this.el);

    // Theme observer
    this.themeObserver = new MutationObserver(() => this.draw());
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme']
    });
  },

  resize() {
    const rect = this.el.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = rect.width * dpr;
    this.canvas.height = rect.height * dpr;
    this.ctx.scale(dpr, dpr);
    this.width = rect.width;
    this.height = rect.height;
  },

  draw() {
    const ctx = this.ctx;
    const width = this.width;
    const height = this.height;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    // Clear
    ctx.clearRect(0, 0, width, height);

    if (this.bids.length === 0 && this.asks.length === 0) {
      // No data - show loading message
      ctx.fillStyle = isDark ? '#a6adba' : '#64748b';
      ctx.font = '14px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('Loading depth data...', width / 2, height / 2);
      return;
    }

    // Calculate cumulative depth
    const bidsCumulative = this.toCumulative(this.bids, true);
    const asksCumulative = this.toCumulative(this.asks, false);

    if (bidsCumulative.length === 0 && asksCumulative.length === 0) return;

    // Find price range and max volume
    const allPrices = [
      ...bidsCumulative.map(d => d.price),
      ...asksCumulative.map(d => d.price)
    ];
    const minPrice = Math.min(...allPrices);
    const maxPrice = Math.max(...allPrices);
    const priceRange = maxPrice - minPrice || 1;

    const maxVolume = Math.max(
      ...bidsCumulative.map(d => d.cumulative),
      ...asksCumulative.map(d => d.cumulative)
    ) || 1;

    // Padding
    const padding = { top: 10, bottom: 30, left: 10, right: 60 };
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;

    // Price to X coordinate
    const priceToX = (price) => {
      return padding.left + ((price - minPrice) / priceRange) * chartWidth;
    };

    // Volume to Y coordinate
    const volumeToY = (volume) => {
      return padding.top + chartHeight - (volume / maxVolume) * chartHeight;
    };

    // Draw bids (green area) - from right to left
    if (bidsCumulative.length > 0) {
      ctx.beginPath();
      ctx.moveTo(priceToX(bidsCumulative[0].price), padding.top + chartHeight);

      bidsCumulative.forEach((d, i) => {
        const x = priceToX(d.price);
        const y = volumeToY(d.cumulative);
        if (i === 0) {
          ctx.lineTo(x, y);
        } else {
          // Step line
          ctx.lineTo(x, volumeToY(bidsCumulative[i-1].cumulative));
          ctx.lineTo(x, y);
        }
      });

      const lastBid = bidsCumulative[bidsCumulative.length - 1];
      ctx.lineTo(priceToX(lastBid.price), padding.top + chartHeight);
      ctx.closePath();

      ctx.fillStyle = 'rgba(34, 197, 94, 0.3)';
      ctx.fill();
      ctx.strokeStyle = '#22c55e';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // Draw asks (red area) - from left to right
    if (asksCumulative.length > 0) {
      ctx.beginPath();
      ctx.moveTo(priceToX(asksCumulative[0].price), padding.top + chartHeight);

      asksCumulative.forEach((d, i) => {
        const x = priceToX(d.price);
        const y = volumeToY(d.cumulative);
        if (i === 0) {
          ctx.lineTo(x, y);
        } else {
          ctx.lineTo(x, volumeToY(asksCumulative[i-1].cumulative));
          ctx.lineTo(x, y);
        }
      });

      const lastAsk = asksCumulative[asksCumulative.length - 1];
      ctx.lineTo(priceToX(lastAsk.price), padding.top + chartHeight);
      ctx.closePath();

      ctx.fillStyle = 'rgba(239, 68, 68, 0.3)';
      ctx.fill();
      ctx.strokeStyle = '#ef4444';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // Draw mid price line
    if (bidsCumulative.length > 0 && asksCumulative.length > 0) {
      const highestBid = Math.max(...bidsCumulative.map(d => d.price));
      const lowestAsk = Math.min(...asksCumulative.map(d => d.price));
      const midPrice = (highestBid + lowestAsk) / 2;
      const midX = priceToX(midPrice);

      ctx.beginPath();
      ctx.setLineDash([4, 4]);
      ctx.strokeStyle = isDark ? '#a6adba' : '#64748b';
      ctx.lineWidth = 1;
      ctx.moveTo(midX, padding.top);
      ctx.lineTo(midX, padding.top + chartHeight);
      ctx.stroke();
      ctx.setLineDash([]);

      // Mid price label
      ctx.fillStyle = isDark ? '#a6adba' : '#374151';
      ctx.font = '11px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(midPrice.toFixed(2), midX, padding.top + chartHeight + 15);
    }

    // Y-axis labels (volume)
    ctx.fillStyle = isDark ? '#a6adba' : '#64748b';
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'left';

    const volumeSteps = 4;
    for (let i = 0; i <= volumeSteps; i++) {
      const volume = (maxVolume / volumeSteps) * i;
      const y = volumeToY(volume);
      ctx.fillText(volume.toFixed(2), width - padding.right + 5, y + 3);
    }

    // Price range labels
    ctx.textAlign = 'left';
    ctx.fillText(minPrice.toFixed(0), padding.left, padding.top + chartHeight + 15);
    ctx.textAlign = 'right';
    ctx.fillText(maxPrice.toFixed(0), width - padding.right, padding.top + chartHeight + 15);
  },

  toCumulative(orders, isBid) {
    if (!orders || orders.length === 0) return [];

    // Sort: bids descending (high to low), asks ascending (low to high)
    const sorted = [...orders].sort((a, b) => isBid ? b[0] - a[0] : a[0] - b[0]);

    let cumulative = 0;
    return sorted.map(([price, qty]) => {
      cumulative += qty;
      return { price, cumulative };
    });
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.themeObserver) this.themeObserver.disconnect();
  }
};
