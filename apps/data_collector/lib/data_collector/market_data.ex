defmodule DataCollector.MarketData do
  @moduledoc """
  ETS-based cache for market data.
  Stores current prices, tickers, and order books.
  """
  use GenServer
  require Logger

  @table_name :market_data

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_price(symbol) do
    case :ets.lookup(@table_name, {:price, symbol}) do
      [{_, price}] -> {:ok, price}
      [] -> {:error, :not_found}
    end
  end

  def get_ticker(symbol) do
    case :ets.lookup(@table_name, {:ticker, symbol}) do
      [{_, ticker}] -> {:ok, ticker}
      [] -> {:error, :not_found}
    end
  end

  def update_price(symbol, price) do
    GenServer.cast(__MODULE__, {:update_price, symbol, price})
  end

  def update_ticker(symbol, ticker) do
    GenServer.cast(__MODULE__, {:update_ticker, symbol, ticker})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting #{__MODULE__}")
    
    table = :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    
    # Subscribe to market data events
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:*")
    
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:update_price, symbol, price}, state) do
    :ets.insert(@table_name, {{:price, symbol}, price})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:update_ticker, symbol, ticker}, state) do
    :ets.insert(@table_name, {{:ticker, symbol}, ticker})
    {:noreply, state}
  end

  @impl true
  def handle_info({:ticker, %{"s" => symbol, "c" => price} = data}, state) do
    :ets.insert(@table_name, {{:price, symbol}, Decimal.new(price)})
    :ets.insert(@table_name, {{:ticker, symbol}, data})
    {:noreply, state}
  end

  @impl true
  def handle_info({:trade, %{"s" => symbol, "p" => price}}, state) do
    :ets.insert(@table_name, {{:price, symbol}, Decimal.new(price)})
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
