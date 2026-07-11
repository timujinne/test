defmodule DataCollector.ExchangeRegistry do
  @moduledoc """
  Resolves an `exchange` string (as stored on `SharedData.Schemas.ApiCredential`)
  to the adapter module implementing `DataCollector.ExchangeClient` for it.

  Deliberately does not convert the input to an atom (it comes from the
  database/user input) — pattern-matches known string values instead so an
  unrecognized value can never create a new atom.
  """

  @spec client_for(String.t()) ::
          {:ok, module()} | {:error, {:unsupported_exchange, String.t()}}
  def client_for("binance"), do: {:ok, DataCollector.BinanceClient}
  def client_for("okx"), do: {:ok, DataCollector.OKXClient}
  def client_for("kraken"), do: {:ok, DataCollector.KrakenClient}
  def client_for(other), do: {:error, {:unsupported_exchange, other}}
end
