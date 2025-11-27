# Шпаргалка по отладке Binance ордеров

## Быстрая диагностика (30 секунд)

```bash
# Проверить что используется testnet
grep "end_point" config/dev.exs
# Ожидается: "https://testnet.binance.vision"

# Проверить API ключи
cat .env | grep BINANCE_
# Должны быть заполнены

# Запустить быстрый тест
mix run test_order_debug.exs
# Ожидается: все ✅
```

## Типичные ошибки и исправления

### MIN_NOTIONAL

```elixir
# ❌ Ошибка
quantity: "0.00001"  # при цене BTC 87745
# 0.00001 × 87745 = 0.87 USDT < 5 USDT

# ✅ Исправление
quantity: "0.0001"   # 0.0001 × 87745 = 8.77 USDT >= 5 USDT
```

### LOT_SIZE

```elixir
# ❌ Ошибка
quantity: "0.000001"  # меньше минимума 0.00001

# ✅ Исправление
quantity: "0.00001"   # минимум для BTC
```

### Invalid API-key

```bash
# 1. Зайти на testnet
open https://testnet.binance.vision/

# 2. Создать новые ключи

# 3. Обновить .env
nano .env
# BINANCE_API_KEY=новый_ключ
# BINANCE_SECRET_KEY=новый_секрет

# 4. Перезапустить
make server
```

### Signature verification failed

```bash
# Синхронизировать время
sudo ntpdate -s time.nist.gov

# Проверить время
date

# Проверить secret_key
cat .env | grep BINANCE_SECRET_KEY
```

## Тестовые команды

### Через скрипт (рекомендуется)

```bash
mix run test_order_debug.exs
```

### Через IEx (пошагово)

```bash
iex -S mix
```

```elixir
# 1. Credentials
api_key = System.get_env("BINANCE_API_KEY")
secret_key = System.get_env("BINANCE_SECRET_KEY")

# 2. Получить цену
{:ok, %{"price" => price}} = DataCollector.BinanceClient.get_ticker_price("BTCUSDT")

# 3. Создать ордер (10% ниже рынка)
{p, _} = Float.parse(price)
test_price = (p * 0.9) |> Float.round(2) |> Float.to_string()

params = %{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: "0.001",
  price: test_price,
  timeInForce: "GTC"
}

{:ok, result} = DataCollector.BinanceClient.create_order(api_key, secret_key, params)

# 4. Отменить
DataCollector.BinanceClient.cancel_order(api_key, secret_key, "BTCUSDT", result["orderId"])
```

### Через UI

```bash
# 1. Запустить
make server

# 2. Открыть
open http://localhost:4000/trading

# 3. Заполнить форму:
Symbol: BTCUSDT
Side: BUY
Type: LIMIT
Quantity: 0.001
Price: [текущая × 0.9]

# 4. Создать ордер
```

## Применение исправлений

```bash
# Вариант 1: Git apply
cd /app
git apply trading_live_improvements.patch

# Вариант 2: Вручную
# Открыть apps/dashboard_web/lib/dashboard_web/live/trading_live.ex
# Скопировать функции из патча

# Перезапустить
make server
```

## Минимальные значения

| Пара | Min Quantity | Min Order Value |
|------|--------------|-----------------|
| BTCUSDT | 0.00001 BTC | 5 USDT |
| ETHUSDT | 0.0001 ETH | 5 USDT |
| BNBUSDT | 0.01 BNB | 5 USDT |

## Примеры расчета

```python
# При цене BTC = 87745 USDT

# ❌ Слишком мало
0.00001 × 87745 = 0.87 USDT < 5

# ✅ Нормально
0.0001 × 87745 = 8.77 USDT >= 5
0.001 × 87745 = 87.75 USDT >= 5
0.01 × 87745 = 877.45 USDT >= 5
```

## Проверка логов

```bash
# В терминале с Phoenix сервером
# Создать ордер через UI
# Посмотреть последние 20 строк логов

# Добавить отладочные логи:
# В TradingLive.handle_event("create_order"):
IO.inspect(params, label: "Form params")
IO.inspect(order_params, label: "Order params")

# В BinanceClient.create_order:
require Logger
Logger.debug("Creating order: #{inspect(order_params)}")
```

## Файлы документации

```
/app/test_order_debug.exs               ← Отладочный скрипт
/app/iex_test_commands.md               ← Команды для IEx
/app/BINANCE_ORDER_DEBUG_REPORT.md      ← Полный отчет
/app/trading_live_improvements.patch    ← Патч с исправлениями
/app/QUICK_FIX_GUIDE.md                 ← Краткое руководство
/app/ORDER_DEBUG_SUMMARY.md             ← Итоговый отчет
/app/TESTING_WORKFLOW.md                ← Workflow тестирования
/app/CHEATSHEET.md                      ← Эта шпаргалка
```

## Чеклист перед production

```
□ Применен патч с валидацией
□ Тесты проходят (mix run test_order_debug.exs)
□ UI тестирование пройдено
□ Добавлены unit тесты
□ Добавлено логирование
□ Проверены все типы ордеров (LIMIT, MARKET)
□ Проверены все символы (BTC, ETH, BNB)
□ Проверены edge cases (минимальные значения)
□ Документация обновлена
```

## Полезные ссылки

- **Binance Testnet:** https://testnet.binance.vision/
- **Binance API Docs:** https://binance-docs.github.io/apidocs/spot/en/
- **Project CLAUDE.md:** /app/CLAUDE.md

## Быстрые ответы

**Q: Где получить testnet ключи?**
A: https://testnet.binance.vision/ → Login via GitHub → API Keys

**Q: Минимальная сумма ордера?**
A: 5 USDT (price × quantity >= 5)

**Q: Минимальное количество BTC?**
A: 0.00001 BTC

**Q: Как проверить что API работает?**
A: `mix run test_order_debug.exs`

**Q: Ордер не создается через UI?**
A: Применить патч: `git apply trading_live_improvements.patch`

**Q: Signature verification failed?**
A: Синхронизировать время: `sudo ntpdate -s time.nist.gov`

**Q: Invalid API-key?**
A: Создать новые ключи на testnet.binance.vision

**Q: MIN_NOTIONAL ошибка?**
A: Увеличить quantity: price × quantity должно быть >= 5 USDT

## Командная строка one-liners

```bash
# Быстрая диагностика
mix run test_order_debug.exs 2>&1 | grep "✅\|❌"

# Проверить конфигурацию
grep -E "(end_point|BINANCE)" config/dev.exs .env

# Получить текущую цену BTC
curl -s "https://testnet.binance.vision/api/v3/ticker/price?symbol=BTCUSDT" | jq

# Проверить аккаунт
curl -s "https://testnet.binance.vision/api/v3/account?timestamp=$(date +%s%3N)&recvWindow=5000" \
  -H "X-MBX-APIKEY: $BINANCE_API_KEY"

# Синхронизировать время
sudo ntpdate -s time.nist.gov && date

# Применить патч
cd /app && git apply trading_live_improvements.patch

# Перезапустить сервер
pkill -f "beam.smp" && make server
```

## Экстренная помощь

Если ничего не помогает:

1. Остановить всё: `pkill -f beam.smp`
2. Очистить deps: `mix deps.clean --all`
3. Переустановить: `mix deps.get`
4. Пересобрать: `mix compile --force`
5. Запустить тесты: `mix test`
6. Запустить диагностику: `mix run test_order_debug.exs`
7. Запустить сервер: `make server`

## Контакты

- Документация: `/app/BINANCE_ORDER_DEBUG_REPORT.md`
- Тесты: `/app/test_order_debug.exs`
- IEx команды: `/app/iex_test_commands.md`

---

**Дата:** 2025-11-25
**Версия:** 1.0.0
**Статус:** ✅ API работает, патч готов
