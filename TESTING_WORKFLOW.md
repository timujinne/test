# Workflow тестирования создания ордеров

## Визуальная схема процесса

```
┌─────────────────────────────────────────────────────────────────┐
│                     ПОЛЬЗОВАТЕЛЬ                                 │
│                          ↓                                       │
│              Заполняет форму на /trading                         │
│              - Symbol: BTCUSDT                                   │
│              - Side: BUY                                         │
│              - Type: LIMIT                                       │
│              - Quantity: 0.001                                   │
│              - Price: 78000                                      │
│                          ↓                                       │
│              Нажимает "Create Order"                             │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│                  TradingLive.handle_event                        │
│                                                                  │
│  ⚠️  ТЕКУЩЕЕ СОСТОЯНИЕ (без валидации):                          │
│     order_params = %{                                            │
│       symbol: params["symbol"],        # может быть nil          │
│       side: params["side"],            # может быть nil          │
│       type: params["type"],            # может быть nil          │
│       quantity: params["quantity"],    # может быть ""           │
│       price: params["price"],          # может быть ""           │
│       timeInForce: "GTC"               # всегда, даже для MARKET │
│     }                                                            │
│                          ↓                                       │
│  ✅  С ПАТЧЕМ (с валидацией):                                     │
│     1. validate_order_params(params)                             │
│        - validate_symbol()                                       │
│        - validate_side()                                         │
│        - validate_type()                                         │
│        - validate_quantity()  → >= 0.00001                       │
│        - validate_price()     → > 0 для LIMIT                    │
│                          ↓                                       │
│     2. build_order_params(params)                                │
│        - Для LIMIT: добавить price, timeInForce                  │
│        - Для MARKET: только базовые параметры                    │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│              DataCollector.BinanceClient.create_order            │
│                                                                  │
│  1. timestamp = System.system_time(:millisecond)                 │
│                          ↓                                       │
│  2. order_params = Map.merge(params, %{                          │
│       timestamp: timestamp,                                      │
│       recvWindow: 5000                                           │
│     })                                                           │
│                          ↓                                       │
│  3. signature = generate_signature(order_params, secret_key)     │
│     - URI.encode_query(params)                                   │
│     - HMAC-SHA256(secret_key, query_string)                      │
│     - Base.encode16(signature, case: :lower)                     │
│                          ↓                                       │
│  4. HTTPoison.post(                                              │
│       "https://testnet.binance.vision/api/v3/order",             │
│       URI.encode_query(Map.put(order_params, :signature, sig)), │
│       headers                                                    │
│     )                                                            │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│                    BINANCE TESTNET API                           │
│                                                                  │
│  Проверки на стороне биржи:                                      │
│  1. ✅ API Key валиден?                                           │
│  2. ✅ Signature правильный?                                      │
│  3. ✅ Timestamp в пределах recvWindow?                           │
│  4. ✅ Symbol существует и доступен?                              │
│  5. ✅ Quantity >= minQty (0.00001 для BTC)?                      │
│  6. ✅ Quantity кратно stepSize (0.00001)?                        │
│  7. ✅ Price >= minPrice (0.01)?                                  │
│  8. ✅ Price кратно tickSize (0.01)?                              │
│  9. ✅ price × quantity >= MIN_NOTIONAL (5 USDT)?                │
│  10. ✅ Достаточно баланса на счету?                              │
│                          ↓                                       │
│  Если все проверки пройдены:                                     │
│  → Создается ордер                                               │
│  → Возвращается JSON с orderId, status, symbol, etc.             │
│                          ↓                                       │
│  Если проверки не прошли:                                        │
│  → Возвращается HTTP 400 с описанием ошибки                      │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│              Обработка ответа в TradingLive                      │
│                                                                  │
│  {:ok, result}:                                                  │
│  ✅ put_flash(:info, "Order created! ID: #{result["orderId"]}")  │
│  ✅ assign(order_result: result)                                 │
│  ✅ Очистить форму                                                │
│  ✅ Перезагрузить балансы                                         │
│                          ↓                                       │
│  {:error, reason}:                                               │
│  ⚠️  ТЕКУЩЕЕ: put_flash(:error, "Failed: #{inspect(reason)}")    │
│  ✅  С ПАТЧЕМ: put_flash(:error, format_error_message(reason))   │
│     - "Invalid API-key" → понятное сообщение                     │
│     - "LOT_SIZE" → подсказка по минимуму                          │
│     - "MIN_NOTIONAL" → объяснение про 5 USDT                     │
└─────────────────────────────────────────────────────────────────┘
```

## Матрица тестирования

### Тест-кейсы для валидации

| # | Тест | Ожидаемый результат |
|---|------|---------------------|
| 1 | Пустое quantity | ❌ "Quantity is required" |
| 2 | quantity = "0" | ❌ "Quantity must be at least 0.00001 BTC" |
| 3 | quantity = "0.000001" | ❌ "Quantity must be at least 0.00001 BTC" |
| 4 | quantity = "0.00001" | ✅ Минимально допустимое |
| 5 | quantity = "0.001" | ✅ Нормальное значение |
| 6 | quantity = "abc" | ❌ "Invalid quantity format" |
| 7 | Пустой price (LIMIT) | ❌ "Price is required for LIMIT orders" |
| 8 | Пустой price (MARKET) | ✅ OK для MARKET |
| 9 | price = "0" | ❌ "Price must be greater than 0" |
| 10 | price = "50000" | ✅ Нормальное значение |
| 11 | price = "xyz" | ❌ "Invalid price format" |

### Тест-кейсы для Binance API

| # | Параметры | Ожидаемый результат | Причина |
|---|-----------|---------------------|---------|
| 1 | qty=0.001, price=87745 | ✅ Ордер создан | 87.745 USDT >= 5 |
| 2 | qty=0.0001, price=87745 | ✅ Ордер создан | 8.7745 USDT >= 5 |
| 3 | qty=0.00001, price=87745 | ❌ MIN_NOTIONAL | 0.87745 USDT < 5 |
| 4 | qty=0.000001, price=87745 | ❌ LOT_SIZE | Меньше minQty |
| 5 | qty=0.001, price=0 | ❌ PRICE_FILTER | Цена = 0 |
| 6 | qty=0.001, price=-100 | ❌ PRICE_FILTER | Отрицательная цена |
| 7 | type=MARKET, qty=0.001 | ✅ Ордер создан | MARKET без price |
| 8 | type=LIMIT без price | ❌ Validation error | Price обязателен |

## Пошаговый процесс отладки

```
ШАГИ ДЛЯ ОТЛАДКИ ПРОБЛЕМЫ:

1️⃣  Проверить конфигурацию
   ├── cat .env | grep BINANCE
   ├── grep "end_point" config/dev.exs
   └── Ожидается: https://testnet.binance.vision

2️⃣  Проверить API напрямую
   ├── mix run test_order_debug.exs
   ├── Если ✅ → API работает, проблема в UI
   └── Если ❌ → смотри вывод скрипта с анализом ошибки

3️⃣  Проверить в IEx
   ├── iex -S mix
   ├── api_key = System.get_env("BINANCE_API_KEY")
   ├── secret_key = System.get_env("BINANCE_SECRET_KEY")
   ├── DataCollector.BinanceClient.get_account(api_key, secret_key)
   └── Ожидается: {:ok, %{"accountType" => "SPOT", ...}}

4️⃣  Проверить форму UI
   ├── Открыть http://localhost:4000/trading
   ├── Открыть Dev Tools (F12) → Network tab
   ├── Заполнить форму
   ├── Нажать "Create Order"
   ├── Посмотреть запрос в Network tab
   └── Посмотреть ответ и логи Phoenix

5️⃣  Добавить отладочные логи
   ├── В handle_event("create_order") добавить:
   │   IO.inspect(params, label: "Form params")
   │   IO.inspect(order_params, label: "Order params")
   ├── В BinanceClient.create_order добавить:
   │   Logger.debug("Order params: #{inspect(order_params)}")
   └── Перезапустить сервер и проверить логи

6️⃣  Применить патч
   ├── git apply trading_live_improvements.patch
   ├── Или скопировать функции вручную
   └── Перезапустить сервер

7️⃣  Проверить после патча
   ├── Попробовать создать ордер с пустыми полями
   │   → Ожидается валидационная ошибка
   ├── Попробовать с quantity=0.000001
   │   → Ожидается "Quantity must be at least 0.00001 BTC"
   ├── Попробовать с правильными параметрами
   │   → Ожидается успешное создание
   └── Проверить что ошибки понятные и информативные
```

## Diagram: Что может пойти не так?

```
ВОЗМОЖНЫЕ ТОЧКИ ОТКАЗА:

┌───────────────────────────────────────────────────────────────┐
│ 1. ФОРМА UI                                                    │
│    ❌ Пустые поля                                              │
│    ❌ Некорректный формат (буквы вместо чисел)                 │
│    ❌ MARKET ордер с полем price                               │
│    ✅ Решение: client-side validation + server-side validation │
└───────────────────────────────────────────────────────────────┘
                           ↓
┌───────────────────────────────────────────────────────────────┐
│ 2. TradingLive.handle_event                                    │
│    ❌ Нет валидации параметров                                 │
│    ❌ Неправильное построение order_params                     │
│    ❌ Неинформативные сообщения об ошибках                     │
│    ✅ Решение: добавить validate_* функции из патча            │
└───────────────────────────────────────────────────────────────┘
                           ↓
┌───────────────────────────────────────────────────────────────┐
│ 3. BinanceClient.create_order                                  │
│    ❌ Неправильный base_url (production вместо testnet)        │
│    ❌ Неправильный timestamp                                   │
│    ❌ Неправильная signature                                   │
│    ✅ Решение: проверено, работает корректно                   │
└───────────────────────────────────────────────────────────────┘
                           ↓
┌───────────────────────────────────────────────────────────────┐
│ 4. BINANCE API                                                 │
│    ❌ Неправильные API ключи                                   │
│    ❌ Параметры не соответствуют фильтрам                      │
│    ❌ Недостаточный баланс                                     │
│    ❌ Timestamp не синхронизирован                             │
│    ✅ Решение: смотри конкретную ошибку в ответе API           │
└───────────────────────────────────────────────────────────────┘
```

## Минимальные значения для популярных пар

```
┌─────────────┬──────────────┬─────────────┬──────────────────┐
│   Символ    │   minQty     │  stepSize   │  MIN_NOTIONAL    │
├─────────────┼──────────────┼─────────────┼──────────────────┤
│  BTCUSDT    │  0.00001     │  0.00001    │  5 USDT          │
│  ETHUSDT    │  0.0001      │  0.0001     │  5 USDT          │
│  BNBUSDT    │  0.01        │  0.01       │  5 USDT          │
└─────────────┴──────────────┴─────────────┴──────────────────┘

Примеры расчета минимальной суммы:

BTCUSDT при цене 87745 USDT:
├── 0.00001 BTC × 87745 = 0.87 USDT    ❌ < 5 USDT
├── 0.0001 BTC × 87745 = 8.77 USDT     ✅ >= 5 USDT
└── 0.001 BTC × 87745 = 87.75 USDT     ✅ >= 5 USDT

ETHUSDT при цене 3400 USDT:
├── 0.0001 ETH × 3400 = 0.34 USDT      ❌ < 5 USDT
├── 0.001 ETH × 3400 = 3.4 USDT        ❌ < 5 USDT
├── 0.002 ETH × 3400 = 6.8 USDT        ✅ >= 5 USDT
└── 0.01 ETH × 3400 = 34 USDT          ✅ >= 5 USDT

BNBUSDT при цене 600 USDT:
├── 0.01 BNB × 600 = 6 USDT            ✅ >= 5 USDT
└── 0.1 BNB × 600 = 60 USDT            ✅ >= 5 USDT
```

## Команды для каждого этапа

### Этап 1: Базовая проверка

```bash
# Проверить переменные окружения
printenv | grep BINANCE

# Проверить конфигурацию
grep -r "end_point" config/

# Запустить полную диагностику
mix run test_order_debug.exs
```

### Этап 2: Тестирование в IEx

```elixir
# Запустить IEx
iex -S mix

# Получить credentials
api_key = System.get_env("BINANCE_API_KEY")
secret_key = System.get_env("BINANCE_SECRET_KEY")

# Тест 1: Получить аккаунт
{:ok, account} = DataCollector.BinanceClient.get_account(api_key, secret_key)

# Тест 2: Получить цену
{:ok, %{"price" => price}} = DataCollector.BinanceClient.get_ticker_price("BTCUSDT")

# Тест 3: Создать тестовый ордер
{price_float, _} = Float.parse(price)
test_price = (price_float * 0.9) |> Float.round(2) |> Float.to_string()

order_params = %{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: "0.001",
  price: test_price,
  timeInForce: "GTC"
}

{:ok, result} = DataCollector.BinanceClient.create_order(api_key, secret_key, order_params)

# Тест 4: Отменить ордер
DataCollector.BinanceClient.cancel_order(api_key, secret_key, "BTCUSDT", result["orderId"])
```

### Этап 3: Применение исправлений

```bash
# Вариант 1: Через git apply
cd /app
git apply trading_live_improvements.patch

# Вариант 2: Вручную
# Открыть файл и скопировать функции:
# - validate_order_params/1
# - validate_symbol/1, validate_side/1, validate_type/1
# - validate_quantity/1, validate_price/2
# - build_order_params/1
# - format_error_message/1
# - create_binance_order/2 (замена существующей логики)
```

### Этап 4: Тестирование UI

```bash
# Запустить сервер
make server
# или
mix phx.server

# Открыть браузер
open http://localhost:4000/trading

# Тест-кейсы:
# 1. Попробовать создать ордер с пустыми полями
# 2. Попробовать с quantity < 0.00001
# 3. Попробовать с правильными параметрами
# 4. Проверить MARKET ордер
```

## Финальный чеклист

```
✅ Запустил test_order_debug.exs - все тесты прошли
✅ Протестировал в IEx - API работает
✅ Применил патч с валидацией
✅ Перезапустил сервер
✅ Протестировал через UI - валидация работает
✅ Протестировал с разными типами ордеров
✅ Проверил сообщения об ошибках - понятные и информативные
✅ Добавил логирование для отладки
✅ Написал тесты (опционально)
```

## Резюме

**Проблема:** Создание ордеров не работает или работает с ошибками

**Причина:** Отсутствие валидации и неправильная обработка параметров

**Решение:** Применить патч с валидацией и улучшенной обработкой ошибок

**Результат:**
- ✅ API работает корректно (проверено тестами)
- ✅ Валидация параметров добавлена
- ✅ Сообщения об ошибках понятные
- ✅ MARKET ордера обрабатываются правильно
- ✅ Все типичные ошибки задокументированы

**Время на исправление:** 15-30 минут

**Уровень сложности:** Низкий (копирование готовых функций)
