# Отчет по отладке создания ордеров на Binance Testnet

## Диагностика проблемы

### Проверенные компоненты

#### 1. Конфигурация ✅

**Файл: `config/dev.exs`**
```elixir
config :binance,
  api_key: System.get_env("BINANCE_API_KEY") || "test_api_key",
  secret_key: System.get_env("BINANCE_SECRET_KEY") || "test_secret_key",
  end_point: System.get_env("BINANCE_BASE_URL") || "https://testnet.binance.vision"
```

**Статус:** Конфигурация правильная, используется testnet URL.

**Файл: `.env`**
```bash
BINANCE_API_KEY=O41M7XfGfIcKEHuKE97JUIzP1IzSfQ0cxxZFZ2hJABW5k9fk9hH3smYcEBdHvqN6
BINANCE_SECRET_KEY=3sMRVRoh7MKR1K2Qeat9LABqWTMBbasuSCrFJtz2jFhdEfVPq5YwSmrFtzJB6rb7
BINANCE_BASE_URL=https://testnet.binance.vision
```

**Статус:** API ключи настроены, testnet URL указан.

#### 2. BinanceClient.create_order/3 ✅

**Файл: `apps/data_collector/lib/data_collector/binance_client.ex`**

```elixir
@spec create_order(Types.api_key(), Types.secret_key(), Types.order_params()) ::
        Types.result(Types.order())
def create_order(api_key, secret_key, params) do
  timestamp = timestamp()
  order_params = Map.merge(params, %{timestamp: timestamp, recvWindow: 5000})
  signature = generate_signature(order_params, secret_key)

  headers = [
    {"X-MBX-APIKEY", api_key},
    {"Content-Type", "application/x-www-form-urlencoded"}
  ]

  with :ok <- DataCollector.RateLimiter.check_limit(1) do
    DataCollector.CircuitBreaker.call(:binance_api, fn ->
      case HTTPoison.post(
             "#{@base_url}/api/v3/order",
             URI.encode_query(Map.put(order_params, :signature, signature)),
             headers
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)}

        {:ok, %{status_code: status, body: body}} ->
          {:error, "HTTP #{status}: #{body}"}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end
end
```

**Статус:** Код выглядит правильно:
- Timestamp генерируется корректно (миллисекунды)
- Signature создается правильно
- Headers содержат API key
- URL кодируется через `URI.encode_query`

#### 3. TradingLive.handle_event("create_order") ⚠️

**Файл: `apps/dashboard_web/lib/dashboard_web/live/trading_live.ex`**

```elixir
def handle_event("create_order", %{"order" => params}, socket) do
  case get_testnet_credentials() do
    {api_key, secret_key} ->
      order_params = %{
        symbol: params["symbol"],
        side: params["side"],
        type: params["type"],
        quantity: params["quantity"],      # ⚠️ Может быть пустой строкой
        price: params["price"],            # ⚠️ Может быть пустой строкой
        timeInForce: "GTC"
      }

      case DataCollector.BinanceClient.create_order(api_key, secret_key, order_params) do
        {:ok, result} ->
          # ... success handling
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to create order: #{inspect(reason)}")}
      end
  end
end
```

**Найденные проблемы:**

1. **Отсутствует валидация параметров** - quantity и price могут быть пустыми строками
2. **Нет обработки MARKET ордеров** - для них не нужен price
3. **Нет проверки типов** - параметры должны быть строками, а не числами

## Найденные проблемы и решения

### Проблема 1: Отсутствие валидации параметров ордера

**Описание:** Форма может отправить пустые значения для quantity и price, что приведет к ошибке от Binance API.

**Решение:** Добавить валидацию перед отправкой ордера:

```elixir
defp validate_order_params(params) do
  with :ok <- validate_symbol(params["symbol"]),
       :ok <- validate_side(params["side"]),
       :ok <- validate_type(params["type"]),
       :ok <- validate_quantity(params["quantity"]),
       :ok <- validate_price(params["type"], params["price"]) do
    :ok
  else
    {:error, reason} -> {:error, reason}
  end
end

defp validate_symbol(symbol) when symbol in ["BTCUSDT", "ETHUSDT", "BNBUSDT"], do: :ok
defp validate_symbol(_), do: {:error, "Invalid symbol"}

defp validate_side(side) when side in ["BUY", "SELL"], do: :ok
defp validate_side(_), do: {:error, "Invalid side"}

defp validate_type(type) when type in ["LIMIT", "MARKET"], do: :ok
defp validate_type(_), do: {:error, "Invalid order type"}

defp validate_quantity(qty) when is_binary(qty) and qty != "" do
  case Decimal.parse(qty) do
    {decimal, ""} ->
      if Decimal.gt?(decimal, 0) do
        :ok
      else
        {:error, "Quantity must be greater than 0"}
      end
    _ ->
      {:error, "Invalid quantity format"}
  end
end
defp validate_quantity(_), do: {:error, "Quantity is required"}

defp validate_price("MARKET", _), do: :ok  # MARKET orders don't need price
defp validate_price("LIMIT", price) when is_binary(price) and price != "" do
  case Decimal.parse(price) do
    {decimal, ""} ->
      if Decimal.gt?(decimal, 0) do
        :ok
      else
        {:error, "Price must be greater than 0"}
      end
    _ ->
      {:error, "Invalid price format"}
  end
end
defp validate_price("LIMIT", _), do: {:error, "Price is required for LIMIT orders"}
```

### Проблема 2: Неправильная обработка MARKET ордеров

**Описание:** MARKET ордеры не должны содержать параметры price и timeInForce.

**Решение:** Условно добавлять параметры в зависимости от типа ордера:

```elixir
defp build_order_params(params) do
  base_params = %{
    symbol: params["symbol"],
    side: params["side"],
    type: params["type"],
    quantity: params["quantity"]
  }

  case params["type"] do
    "LIMIT" ->
      Map.merge(base_params, %{
        price: params["price"],
        timeInForce: "GTC"
      })
    "MARKET" ->
      base_params
    _ ->
      base_params
  end
end
```

### Проблема 3: Недостаточная информация в сообщениях об ошибках

**Описание:** Текущая обработка ошибок просто показывает `inspect(reason)`, что не очень информативно для пользователя.

**Решение:** Добавить функцию для форматирования ошибок:

```elixir
defp format_error_message(error) when is_binary(error) do
  cond do
    String.contains?(error, "Invalid API-key") ->
      "Invalid API key. Please check your Binance Testnet credentials."

    String.contains?(error, "Signature") ->
      "Signature verification failed. Please check your API keys and system time."

    String.contains?(error, "LOT_SIZE") ->
      "Invalid quantity. The amount must meet exchange requirements."

    String.contains?(error, "PRICE_FILTER") ->
      "Invalid price. The price must meet exchange requirements."

    String.contains?(error, "MIN_NOTIONAL") ->
      "Order value too small. Minimum order value is typically 5 USDT."

    String.contains?(error, "Timestamp") ->
      "Timestamp error. Your system time may be out of sync."

    true ->
      "Order creation failed: #{error}"
  end
end

defp format_error_message(error) do
  "Order creation failed: #{inspect(error)}"
end
```

## Потенциальные проблемы на стороне Binance API

### 1. Фильтры символа (LOT_SIZE, PRICE_FILTER, MIN_NOTIONAL)

Каждый торговый символ имеет ограничения:

**BTCUSDT:**
- **LOT_SIZE**: minQty: 0.00001, maxQty: 9000, stepSize: 0.00001
- **PRICE_FILTER**: minPrice: 0.01, maxPrice: 1000000, tickSize: 0.01
- **MIN_NOTIONAL**: minNotional: 5 USDT (price × quantity >= 5)

**Примеры ошибок:**
```
Quantity: 0.0001 × Price: 40000 = 4 USDT ❌ (меньше 5 USDT)
Quantity: 0.001 × Price: 40000 = 40 USDT ✅
```

### 2. Системное время

Binance требует, чтобы timestamp был в пределах recvWindow (по умолчанию 5000ms) от серверного времени.

**Решение:** Увеличить recvWindow или синхронизировать системное время:

```bash
# Linux
sudo ntpdate -s time.nist.gov

# macOS
sudo sntp -sS time.apple.com

# Windows
w32tm /resync
```

### 3. API ключи

Убедитесь что используются ключи от Binance Testnet, а не от production:
- Testnet: https://testnet.binance.vision/
- Production: https://www.binance.com/

## Рекомендуемые улучшения

### 1. Добавить client-side валидацию в форме

```html
<input
  type="text"
  name="order[quantity]"
  value={@order_form["quantity"]}
  class="mt-1 input input-bordered w-full"
  placeholder="0.001"
  required
  pattern="[0-9]+(\.[0-9]+)?"
  min="0.00001"
/>

<input
  type="text"
  name="order[price]"
  value={@order_form["price"]}
  class="mt-1 input input-bordered w-full"
  placeholder="50000"
  pattern="[0-9]+(\.[0-9]+)?"
  min="0.01"
  disabled={@order_form["type"] == "MARKET"}
/>
```

### 2. Показывать минимальные требования

```html
<div class="text-xs text-base-content/50 mt-1">
  Min: 0.00001 BTC, Order value must be at least 5 USDT
</div>
```

### 3. Добавить расчет стоимости ордера

```elixir
defp calculate_order_value(quantity, price) when is_binary(quantity) and is_binary(price) do
  with {qty_decimal, ""} <- Decimal.parse(quantity),
       {price_decimal, ""} <- Decimal.parse(price) do
    Decimal.mult(qty_decimal, price_decimal)
  else
    _ -> nil
  end
end
```

### 4. Логирование для отладки

Добавить подробное логирование в `create_order`:

```elixir
require Logger

def create_order(api_key, secret_key, params) do
  Logger.debug("Creating order with params: #{inspect(params)}")

  timestamp = timestamp()
  order_params = Map.merge(params, %{timestamp: timestamp, recvWindow: 5000})

  Logger.debug("Full order params: #{inspect(order_params)}")

  signature = generate_signature(order_params, secret_key)
  Logger.debug("Generated signature: #{signature}")

  # ... rest of the code
end
```

## Файлы для тестирования

Созданы следующие файлы:

1. **`/app/test_order_debug.exs`** - Полный отладочный скрипт
   - Проверяет конфигурацию
   - Тестирует получение аккаунта
   - Тестирует создание и отмену ордера
   - Анализирует ошибки

2. **`/app/iex_test_commands.md`** - Команды для тестирования в IEx
   - Пошаговые инструкции
   - Примеры всех API вызовов
   - Диагностика типичных ошибок
   - Альтернативные методы проверки

## Инструкции по тестированию

### Шаг 1: Запустить отладочный скрипт

```bash
cd /app
mix run test_order_debug.exs
```

Скрипт выполнит следующие проверки:
- ✅ Конфигурация (testnet URL)
- ✅ Наличие API ключей
- ✅ Получение информации об аккаунте
- ✅ Получение текущей цены BTC
- ✅ Создание тестового LIMIT ордера
- ✅ Отмена тестового ордера

### Шаг 2: Тестирование в IEx

```bash
iex -S mix

# Загрузить переменные
api_key = System.get_env("BINANCE_API_KEY")
secret_key = System.get_env("BINANCE_SECRET_KEY")

# Проверить аккаунт
DataCollector.BinanceClient.get_account(api_key, secret_key)

# Создать тестовый ордер (см. iex_test_commands.md)
```

### Шаг 3: Тестирование через UI

1. Запустить сервер: `make server` или `mix phx.server`
2. Открыть http://localhost:4000/trading
3. Заполнить форму:
   - Symbol: BTCUSDT
   - Side: BUY
   - Type: LIMIT
   - Quantity: 0.001 (минимум)
   - Price: [текущая цена × 0.9] (чтобы не исполнился)
4. Нажать "Create Order"

### Шаг 4: Проверка логов

```bash
# В другом терминале
tail -f /path/to/app/logs/dev.log

# Или смотреть логи в консоли где запущен Phoenix
```

## Типичные ошибки и их решения

### Ошибка: "Invalid API-key, IP, or permissions for action"

**Причина:**
- Используются production ключи вместо testnet
- API ключ неправильный
- IP адрес не разрешен (только для production с IP whitelist)

**Решение:**
1. Зайти на https://testnet.binance.vision/
2. Залогиниться через GitHub
3. Создать новый API key
4. Обновить `.env` файл
5. Перезапустить приложение

### Ошибка: "Signature for this request is not valid"

**Причина:**
- Secret key неправильный
- Параметры неправильно закодированы
- Проблема с timestamp

**Решение:**
```elixir
# Проверить secret key
System.get_env("BINANCE_SECRET_KEY") |> IO.inspect()

# Проверить timestamp
System.system_time(:millisecond) |> IO.inspect()

# Проверить что параметры - строки, не числа
params = %{
  symbol: "BTCUSDT",
  quantity: "0.001",  # Строка, не число!
  price: "50000"      # Строка, не число!
}
```

### Ошибка: "Filter failure: LOT_SIZE"

**Причина:**
- Quantity меньше minQty (для BTC: 0.00001)
- Quantity не кратно stepSize (для BTC: 0.00001)
- Quantity больше maxQty (для BTC: 9000)

**Решение:**
```elixir
# Правильные значения для BTCUSDT
quantity: "0.001"   # ✅ >= 0.00001
quantity: "0.0001"  # ✅ >= 0.00001
quantity: "0.00001" # ✅ минимум
quantity: "0.000001" # ❌ меньше минимума
```

### Ошибка: "Filter failure: MIN_NOTIONAL"

**Причина:**
- Сумма ордера (price × quantity) меньше минимальной (обычно 5 USDT)

**Решение:**
```elixir
# При цене BTC = 50000 USDT
quantity: "0.0001" # 50000 × 0.0001 = 5 USDT ✅
quantity: "0.00005" # 50000 × 0.00005 = 2.5 USDT ❌

# При цене BTC = 100000 USDT
quantity: "0.00005" # 100000 × 0.00005 = 5 USDT ✅
```

### Ошибка: "Timestamp for this request was 1000ms ahead of the server's time"

**Причина:**
- Системное время не синхронизировано

**Решение:**
```bash
# Linux
sudo ntpdate -s time.nist.gov

# Или использовать chronyd/systemd-timesyncd
sudo timedatectl set-ntp true

# Проверить
timedatectl status
```

## Следующие шаги

После успешного тестирования рекомендуется:

1. **Добавить валидацию** - Реализовать функции валидации из раздела "Проблема 1"
2. **Улучшить UX** - Добавить подсказки и расчет минимальных значений
3. **Добавить тесты** - Написать unit тесты для `create_order`
4. **Добавить логирование** - Для упрощения отладки в production
5. **Обработать edge cases** - MARKET ордера, частичное исполнение и т.д.

## Контрольный список

- [ ] Проверил что используется testnet URL
- [ ] Проверил что API ключи от testnet
- [ ] Запустил `mix run test_order_debug.exs`
- [ ] Успешно создал тестовый ордер через IEx
- [ ] Успешно создал тестовый ордер через UI
- [ ] Добавил валидацию параметров
- [ ] Улучшил обработку ошибок
- [ ] Добавил логирование
- [ ] Написал тесты
