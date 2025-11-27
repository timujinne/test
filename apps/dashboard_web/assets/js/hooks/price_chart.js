import { createChart, CandlestickSeries, HistogramSeries, CrosshairMode } from 'lightweight-charts';

export const PriceChart = {
  mounted() {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    // Create chart
    this.chart = createChart(this.el, {
      width: this.el.clientWidth,
      height: 400,
      layout: {
        background: { type: 'solid', color: isDark ? '#1d232a' : '#ffffff' },
        textColor: isDark ? '#a6adba' : '#191d24',
      },
      grid: {
        vertLines: { color: isDark ? '#2a323c' : '#e5e7eb' },
        horzLines: { color: isDark ? '#2a323c' : '#e5e7eb' },
      },
      crosshair: { mode: CrosshairMode.Normal },
      rightPriceScale: { borderColor: isDark ? '#2a323c' : '#e5e7eb' },
      timeScale: {
        borderColor: isDark ? '#2a323c' : '#e5e7eb',
        timeVisible: true,
        secondsVisible: false
      },
    });

    // Candlestick series (v5 API)
    this.candleSeries = this.chart.addSeries(CandlestickSeries, {
      upColor: '#22c55e',
      downColor: '#ef4444',
      borderUpColor: '#22c55e',
      borderDownColor: '#ef4444',
      wickUpColor: '#22c55e',
      wickDownColor: '#ef4444',
    });

    // Volume series (v5 API)
    this.volumeSeries = this.chart.addSeries(HistogramSeries, {
      priceFormat: { type: 'volume' },
      priceScaleId: 'volume',
    });

    this.chart.priceScale('volume').applyOptions({
      scaleMargins: { top: 0.8, bottom: 0 },
    });

    // Handle events from LiveView
    this.handleEvent("price_chart_init", ({ candles }) => {
      if (!candles || candles.length === 0) return;

      const candleData = candles.map(c => ({
        time: Math.floor(c.time / 1000),
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close
      }));

      const volumeData = candles.map(c => ({
        time: Math.floor(c.time / 1000),
        value: c.volume,
        color: c.close >= c.open ? 'rgba(34, 197, 94, 0.5)' : 'rgba(239, 68, 68, 0.5)'
      }));

      this.candleSeries.setData(candleData);
      this.volumeSeries.setData(volumeData);
      this.chart.timeScale().fitContent();
    });

    this.handleEvent("price_chart_update", (candle) => {
      if (!candle) return;

      const candleData = {
        time: Math.floor(candle.time / 1000),
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close
      };

      const volumeData = {
        time: Math.floor(candle.time / 1000),
        value: candle.volume,
        color: candle.close >= candle.open ? 'rgba(34, 197, 94, 0.5)' : 'rgba(239, 68, 68, 0.5)'
      };

      this.candleSeries.update(candleData);
      this.volumeSeries.update(volumeData);
    });

    // Handle resize
    this.resizeObserver = new ResizeObserver(entries => {
      if (entries.length > 0) {
        const { width } = entries[0].contentRect;
        this.chart.applyOptions({ width });
      }
    });
    this.resizeObserver.observe(this.el);

    // Handle theme changes
    this.themeObserver = new MutationObserver(() => {
      const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
      this.chart.applyOptions({
        layout: {
          background: { type: 'solid', color: isDark ? '#1d232a' : '#ffffff' },
          textColor: isDark ? '#a6adba' : '#191d24',
        },
        grid: {
          vertLines: { color: isDark ? '#2a323c' : '#e5e7eb' },
          horzLines: { color: isDark ? '#2a323c' : '#e5e7eb' },
        },
      });
    });
    this.themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.themeObserver) this.themeObserver.disconnect();
    if (this.chart) this.chart.remove();
  }
};
