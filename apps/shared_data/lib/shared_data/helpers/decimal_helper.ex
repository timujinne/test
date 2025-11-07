defmodule SharedData.Helpers.DecimalHelper do
  @moduledoc """
  Вспомогательные функции для работы с Decimal.
  """

  @doc """
  Безопасное преобразование в Decimal.
  """
  def to_decimal(nil), do: Decimal.new(0)
  def to_decimal(value) when is_binary(value), do: Decimal.new(value)
  def to_decimal(value) when is_integer(value), do: Decimal.new(value)
  def to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  def to_decimal(%Decimal{} = value), do: value

  @doc """
  Форматирование Decimal для отображения.
  """
  def format(decimal, precision \\ 8) do
    decimal
    |> Decimal.round(precision)
    |> Decimal.to_string(:normal)
  end

  @doc """
  Форматирование с символом валюты.
  """
  def format_currency(decimal, currency \\ "USDT", precision \\ 2) do
    "#{format(decimal, precision)} #{currency}"
  end

  @doc """
  Безопасное деление с обработкой деления на ноль.
  """
  def safe_div(numerator, denominator) do
    denom = to_decimal(denominator)
    
    if zero?(denom) do
      Decimal.new(0)
    else
      Decimal.div(to_decimal(numerator), denom)
    end
  end

  @doc """
  Проверка на положительное значение.
  """
  def positive?(%Decimal{} = decimal) do
    Decimal.compare(decimal, 0) == :gt
  end

  @doc """
  Проверка на отрицательное значение.
  """
  def negative?(%Decimal{} = decimal) do
    Decimal.compare(decimal, 0) == :lt
  end

  @doc """
  Проверка на ноль.
  """
  def zero?(%Decimal{} = decimal) do
    Decimal.compare(decimal, 0) == :eq
  end

  @doc """
  Процентное изменение.
  """
  def percent_change(old_value, new_value) do
    old = to_decimal(old_value)
    new = to_decimal(new_value)

    if zero?(old) do
      Decimal.new(0)
    else
      new
      |> Decimal.sub(old)
      |> Decimal.div(old)
      |> Decimal.mult(100)
    end
  end
end
