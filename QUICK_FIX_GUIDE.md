# Быстрое руководство по исправлению ошибок создания ордеров

## TL;DR (Краткий итог)

✅ **API работает корректно!** Тесты показали, что BinanceClient.create_order успешно создает и отменяет ордера.

⚠️ **Возможные проблемы в UI:**
1. Отсутствует валидация параметров формы
2. Нет обработки пустых значений
3. Неинформативные сообщения об ошибках
4. MARKET ордера включают ненужные параметры

## Результаты тестирования

```bash
$ mix run test_order_debug.exs

[info] ✅ Using testnet URL
[info] ✅ Credentials found
[info] ✅ Successfully retrieved account info
[info] ✅ Successfully retrieved BTC price: 87745.49
[info] ✅ Order created successfully! Order ID: 4000258
[info] ✅ Order cancelled successfully!
```

## Если у вас ошибка, проверьте:

### 1. Пустые поля формы

**Проблема:** Пользователь нажал "Create Order" с пустыми полями

**Решение:** Добавьте валидацию (см. файл `trading_live_improvements.patch`)

### 2. Недостаточная сумма ордера

**Проблема:** Ошибка "MIN_NOTIONAL"

**Причина:** price × quantity < 5 USDT

**Решение:**
```
При BTC = 87745 USDT:
❌ 0.00001 BTC × 87745 = 0.87 USDT (слишком мало)
✅ 0.0001 BTC × 87745 = 8.77 USDT (достаточно)
✅ 0.001 BTC × 87745 = 87.75 USDT (достаточно)
```

### 3. Слишком маленькое количество

**Проблема:** Ошибка "LOT_SIZE"

**Минимумы для популярных пар:**
- BTCUSDT: 0.00001 BTC
- ETHUSDT: 0.0001 ETH
- BNBUSDT: 0.01 BNB

### 4. Неправильные API ключи

**Проблема:** Ошибка "Invalid API-key"

**Решение:**
1. Зайдите на https://testnet.binance.vision/
2. Залогиньтесь через GitHub
3. Создайте новые API ключи
4. Обновите `.env`:
   ```bash
   BINANCE_API_KEY=ваш_новый_ключ
   BINANCE_SECRET_KEY=ваш_новый_секрет
   ```
5. Перезапустите: `make server`

## Быстрое тестирование

### Вариант 1: Через скрипт (рекомендуется)

```bash
mix run test_order_debug.exs
```

### Вариант 2: Через IEx

```bash
iex -S mix

# Получить credentials
api_key = System.get_env("BINANCE_API_KEY")
secret_key = System.get_env("BINANCE_SECRET_KEY")

# Получить текущую цену
{:ok, %{"price" => price}} = DataCollector.BinanceClient.get_ticker_price("BTCUSDT")

# Создать ордер (цена на 10% ниже рынка, чтобы не исполнился)
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

# Посмотреть результат
IO.inspect(result)

# Отменить ордер
DataCollector.BinanceClient.cancel_order(api_key, secret_key, result["symbol"], result["orderId"])
```

### Вариант 3: Через UI

1. `make server` или `mix phx.server`
2. Откройте http://localhost:4000/trading
3. Заполните форму:
   - Symbol: **BTCUSDT**
   - Side: **BUY**
   - Type: **LIMIT**
   - Quantity: **0.001** (минимум для безопасного теста)
   - Price: *[текущая цена × 0.9]* (например, если BTC = 87745, то price = 78970)
4. Нажмите "Create Order"

## Применение исправлений

### Способ 1: Ручное применение

Откройте файл `/app/apps/dashboard_web/lib/dashboard_web/live/trading_live.ex` и добавьте функции из файла `trading_live_improvements.patch`

### Способ 2: Через git apply

```bash
cd /app
git apply trading_live_improvements.patch
```

## Основные улучшения в патче

1. **Валидация параметров:**
   - Проверка symbol, side, type
   - Проверка quantity >= 0.00001
   - Проверка price для LIMIT ордеров
   - Проверка формата (только числа)

2. **Правильное построение параметров:**
   - LIMIT: включает price и timeInForce
   - MARKET: только базовые параметры

3. **Информативные ошибки:**
   - Расшифровка ошибок Binance API
   - Подсказки по исправлению
   - Эмодзи для визуального выделения

## Полезные файлы

- `/app/test_order_debug.exs` - Полный скрипт диагностики
- `/app/iex_test_commands.md` - Команды для IEx
- `/app/BINANCE_ORDER_DEBUG_REPORT.md` - Подробный отчет с анализом
- `/app/trading_live_improvements.patch` - Патч с исправлениями
- `/app/QUICK_FIX_GUIDE.md` - Это руководство

## Типичные ошибки и их коды

| Ошибка | Код | Причина | Решение |
|--------|-----|---------|---------|
| Invalid API-key | -2015 | Неправильные API ключи | Создайте новые на testnet.binance.vision |
| Signature invalid | -1022 | Неправильный secret_key | Проверьте BINANCE_SECRET_KEY в .env |
| Timestamp error | -1021 | Время не синхронизировано | `sudo ntpdate -s time.nist.gov` |
| LOT_SIZE | -1013 | Количество вне допустимого диапазона | Для BTC: >= 0.00001 |
| PRICE_FILTER | -1013 | Цена вне допустимого диапазона | Для BTC: >= 0.01 USDT |
| MIN_NOTIONAL | -1013 | Сумма ордера < 5 USDT | Увеличьте quantity или price |

## Контрольный список для отладки

Если создание ордера не работает, проверьте по порядку:

- [ ] Запустил `mix run test_order_debug.exs` - все ✅?
- [ ] Проверил `.env` - правильные ключи от testnet?
- [ ] Проверил `config/dev.exs` - используется testnet URL?
- [ ] Проверил форму - все поля заполнены?
- [ ] Проверил количество - >= 0.00001 для BTC?
- [ ] Проверил сумму - price × quantity >= 5 USDT?
- [ ] Проверил системное время - синхронизировано?
- [ ] Посмотрел логи - какая именно ошибка?

## Получение помощи

Если проблема не решается:

1. Запустите полную диагностику:
   ```bash
   mix run test_order_debug.exs > debug_output.txt 2>&1
   ```

2. Проверьте логи Phoenix:
   ```bash
   # В терминале где запущен сервер
   # Создайте ордер через UI и скопируйте последние строки логов
   ```

3. Проверьте ответ API напрямую:
   ```bash
   # См. раздел "curl" в iex_test_commands.md
   ```

## Следующие шаги

После того как ордера работают:

1. ✅ Применить патч с валидацией
2. 📝 Добавить unit тесты для `handle_event("create_order")`
3. 🎨 Улучшить UX: показывать минимальные значения
4. 💡 Добавить расчет суммы ордера в реальном времени
5. 🔍 Добавить подробное логирование для production

## Контакты и ресурсы

- **Binance Testnet:** https://testnet.binance.vision/
- **Binance API Docs:** https://binance-docs.github.io/apidocs/spot/en/
- **Project Docs:** /app/CLAUDE.md
- **Debug Script:** /app/test_order_debug.exs
- **IEx Commands:** /app/iex_test_commands.md
