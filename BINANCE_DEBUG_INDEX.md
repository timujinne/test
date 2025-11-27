# Индекс: Отладка Binance Orders

## 🚀 Быстрый старт (выбери свой путь)

### 🔴 СРОЧНО! Не работают ордера!
```bash
mix run test_order_debug.exs
```
→ Смотри вывод, следуй подсказкам
→ Затем читай [`QUICK_FIX_GUIDE.md`](./QUICK_FIX_GUIDE.md)

### 🟡 Нужно исправить код
→ Читай [`QUICK_FIX_GUIDE.md`](./QUICK_FIX_GUIDE.md)
→ Применяй [`trading_live_improvements.patch`](./trading_live_improvements.patch)

### 🟢 Хочу понять архитектуру
→ Читай [`TESTING_WORKFLOW.md`](./TESTING_WORKFLOW.md)
→ Затем [`BINANCE_ORDER_DEBUG_REPORT.md`](./BINANCE_ORDER_DEBUG_REPORT.md)

### ⚪ Новый в проекте
→ Начни с [`DEBUG_FILES_README.md`](./DEBUG_FILES_README.md)
→ Держи открытым [`CHEATSHEET.md`](./CHEATSHEET.md)

---

## 📚 Все файлы по категориям

### Для менеджеров и руководителей

| Файл | Описание | Время |
|------|----------|-------|
| [`ORDER_DEBUG_SUMMARY.md`](./ORDER_DEBUG_SUMMARY.md) | 📋 Итоговый отчет | 5 мин |

**Что внутри:**
- Статус проекта (✅ API работает)
- Найденные проблемы
- Результаты тестирования
- Рекомендации

---

### Для разработчиков (быстрые решения)

| Файл | Описание | Время |
|------|----------|-------|
| [`CHEATSHEET.md`](./CHEATSHEET.md) | 📝 Шпаргалка с командами | Справочник |
| [`QUICK_FIX_GUIDE.md`](./QUICK_FIX_GUIDE.md) | ⚡ Быстрое руководство | 10 мин |
| [`test_order_debug.exs`](./test_order_debug.exs) | 🔍 Скрипт диагностики | 30 сек |

**Что внутри:**
- Типичные ошибки и их решения
- Команды copy-paste
- Применение исправлений
- Минимальные значения

**Использовать когда:**
- ⚡ Нужно срочно решить проблему
- 🔎 Найти причину ошибки
- 📋 Быстро проверить работоспособность

---

### Для разработчиков (глубокое погружение)

| Файл | Описание | Время |
|------|----------|-------|
| [`BINANCE_ORDER_DEBUG_REPORT.md`](./BINANCE_ORDER_DEBUG_REPORT.md) | 📊 Полный технический отчет | 30 мин |
| [`TESTING_WORKFLOW.md`](./TESTING_WORKFLOW.md) | 🗺️ Workflow и диаграммы | 20 мин |
| [`iex_test_commands.md`](./iex_test_commands.md) | 📘 Команды для IEx | Справочник |
| [`trading_live_improvements.patch`](./trading_live_improvements.patch) | 🔧 Патч с исправлениями | 2-5 мин |

**Что внутри:**
- Детальный анализ всех компонентов
- Визуальные схемы процесса
- Пошаговые инструкции для IEx
- Готовые исправления кода

**Использовать когда:**
- 🏗️ Нужно понять архитектуру
- 🔬 Глубокая диагностика проблемы
- 🎓 Обучение новых разработчиков
- 💡 Планирование улучшений

---

### Для всех (навигация)

| Файл | Описание | Время |
|------|----------|-------|
| [`DEBUG_FILES_README.md`](./DEBUG_FILES_README.md) | 📖 Навигация по файлам | 10 мин |
| [`BINANCE_DEBUG_INDEX.md`](./BINANCE_DEBUG_INDEX.md) | 📑 Этот индексный файл | 5 мин |

**Что внутри:**
- Описание всех файлов
- Workflow использования
- Сценарии применения
- Карта зависимостей

**Использовать когда:**
- 🧭 Не знаешь с чего начать
- 🗂️ Нужно найти нужный документ
- 🎯 Определить подходящий сценарий

---

## 🎯 Выбор файла по задаче

### Задача: "Ордер не создается, ошибка MIN_NOTIONAL"

```
1. CHEATSHEET.md → "MIN_NOTIONAL"
   → Увеличить quantity или price
   → price × quantity >= 5 USDT

2. Тест:
   mix run test_order_debug.exs
```

### Задача: "Ордер не создается, ошибка Invalid API-key"

```
1. CHEATSHEET.md → "Invalid API-key"
   → Создать новые ключи на testnet.binance.vision
   → Обновить .env
   → Перезапустить сервер

2. Тест:
   mix run test_order_debug.exs
```

### Задача: "Ордер не создается, ошибка Signature verification failed"

```
1. CHEATSHEET.md → "Signature verification failed"
   → sudo ntpdate -s time.nist.gov
   → Проверить secret_key в .env

2. Тест:
   mix run test_order_debug.exs
```

### Задача: "Нужно добавить валидацию в форму"

```
1. QUICK_FIX_GUIDE.md → "Применение исправлений"
   → git apply trading_live_improvements.patch

2. Или вручную:
   → trading_live_improvements.patch
   → Скопировать функции в TradingLive

3. Тест:
   → Запустить сервер
   → Попробовать создать ордер с пустыми полями
```

### Задача: "Понять как работает create_order"

```
1. TESTING_WORKFLOW.md
   → Визуальная схема процесса
   → Матрица тестирования

2. BINANCE_ORDER_DEBUG_REPORT.md
   → Анализ BinanceClient.create_order
   → Анализ TradingLive.handle_event

3. iex_test_commands.md
   → Практическое тестирование в IEx
```

### Задача: "Протестировать API напрямую"

```
1. test_order_debug.exs
   → Автоматический тест

2. iex_test_commands.md
   → Ручное тестирование в IEx
   → Пошаговые команды

3. CHEATSHEET.md → "Тестовые команды"
   → Через скрипт, IEx или UI
```

### Задача: "Новый разработчик в команде"

```
1. DEBUG_FILES_README.md
   → Понять структуру документации
   → Workflow использования

2. test_order_debug.exs
   → Практическая проверка

3. TESTING_WORKFLOW.md
   → Понять архитектуру

4. CHEATSHEET.md
   → Держать открытым как справочник
```

### Задача: "Отчитаться перед руководством"

```
1. ORDER_DEBUG_SUMMARY.md
   → Краткое резюме (5 мин)

2. test_order_debug.exs → результаты
   → Визуальное подтверждение

3. BINANCE_ORDER_DEBUG_REPORT.md (опционально)
   → Полный технический отчет
```

---

## 📊 Статистика проекта

```
Создано файлов:            9
Строк кода/документации:   ~3500
Время на создание:         ~3 часа
Время на изучение:         ~2 часа (всё)
Время на применение:       ~30 минут
```

### Распределение контента

```
Диагностика:      30% (test_order_debug.exs, REPORT)
Быстрые решения:  25% (CHEATSHEET, QUICK_FIX)
Глубокий анализ:  25% (REPORT, WORKFLOW)
Исправления:      10% (patch)
Навигация:        10% (README, INDEX)
```

### Уровень детализации

```
Быстро (5-10 мин):
├── CHEATSHEET.md
├── test_order_debug.exs
└── QUICK_FIX_GUIDE.md

Средне (15-20 мин):
├── iex_test_commands.md
├── ORDER_DEBUG_SUMMARY.md
└── TESTING_WORKFLOW.md

Глубоко (30+ мин):
├── BINANCE_ORDER_DEBUG_REPORT.md
└── Все файлы вместе
```

---

## 🔑 Ключевые выводы

### ✅ Что работает

```
✅ Binance API - работает корректно
✅ BinanceClient.create_order - правильная реализация
✅ Конфигурация - testnet URL настроен
✅ API ключи - валидны
✅ Signature - генерируется правильно
✅ Timestamp - корректный
```

### ⚠️ Что нужно улучшить

```
⚠️ Валидация формы - отсутствует
⚠️ MARKET ордера - неправильные параметры
⚠️ Сообщения об ошибках - неинформативные
```

### 🔧 Что сделать

```
1. Применить: trading_live_improvements.patch
2. Добавить: client-side валидацию в HTML
3. Добавить: подсказки о минимальных значениях
4. Добавить: расчет суммы ордера
5. Добавить: unit тесты
6. Добавить: логирование
```

---

## 📱 Быстрые ссылки

### Документация
- [Основной проект](./CLAUDE.md) - Project guidelines
- [Setup инструкции](./SETUP_INSTRUCTIONS.md) - Настройка окружения

### Внешние ресурсы
- [Binance Testnet](https://testnet.binance.vision/) - Получить API ключи
- [Binance API Docs](https://binance-docs.github.io/apidocs/spot/en/) - API документация
- [Phoenix Docs](https://hexdocs.pm/phoenix/Phoenix.html) - Phoenix framework
- [Elixir Docs](https://hexdocs.pm/elixir/) - Elixir language

---

## 🎓 Сценарии обучения

### Уровень 1: Новичок (1-2 часа)

```
1. DEBUG_FILES_README.md (10 мин)
   └── Понять структуру

2. test_order_debug.exs (5 мин)
   └── Запустить и понять результаты

3. CHEATSHEET.md (15 мин)
   └── Изучить основные команды

4. QUICK_FIX_GUIDE.md (20 мин)
   └── Понять типичные проблемы

5. Практика (30 мин)
   └── Тестирование через IEx и UI
```

### Уровень 2: Средний (2-3 часа)

```
1. Уровень 1 (полностью)

2. iex_test_commands.md (30 мин)
   └── Практика всех API вызовов

3. TESTING_WORKFLOW.md (30 мин)
   └── Понять архитектуру

4. trading_live_improvements.patch (20 мин)
   └── Изучить исправления

5. Практика (60 мин)
   └── Применить патч, протестировать, расширить
```

### Уровень 3: Продвинутый (4-5 часов)

```
1. Уровень 1-2 (полностью)

2. BINANCE_ORDER_DEBUG_REPORT.md (60 мин)
   └── Глубокое понимание всех компонентов

3. Анализ кода (60 мин)
   └── BinanceClient, TradingLive, тесты

4. Расширение (90 мин)
   └── Добавить новые валидации, тесты, фичи

5. Документация (30 мин)
   └── Обновить документы при необходимости
```

---

## 🔍 Поиск по содержимому

### Найти информацию об ошибке

```bash
# Через grep во всех файлах
grep -r "MIN_NOTIONAL" *.md

# Или открыть конкретные файлы:
# - CHEATSHEET.md → "MIN_NOTIONAL"
# - QUICK_FIX_GUIDE.md → "Ошибка: MIN_NOTIONAL"
# - BINANCE_ORDER_DEBUG_REPORT.md → "MIN_NOTIONAL"
```

### Найти конкретную команду

```bash
# В CHEATSHEET.md или iex_test_commands.md
grep -A 5 "create_order" CHEATSHEET.md
grep -A 5 "create_order" iex_test_commands.md
```

### Найти примеры кода

```bash
# В trading_live_improvements.patch
cat trading_live_improvements.patch | grep "defp validate"

# В test_order_debug.exs
cat test_order_debug.exs | grep "defp"
```

---

## ✅ Финальный чеклист

### Перед началом работы

```
□ Прочитал этот INDEX
□ Выбрал подходящий сценарий
□ Знаю какие файлы мне нужны
```

### Диагностика

```
□ Запустил test_order_debug.exs
□ Прочитал CHEATSHEET.md
□ Знаю свою ошибку и решение
```

### Исправление

```
□ Прочитал QUICK_FIX_GUIDE.md
□ Применил trading_live_improvements.patch
□ Протестировал через UI
```

### Перед production

```
□ Все тесты проходят
□ Валидация добавлена
□ Сообщения об ошибках информативные
□ Unit тесты написаны
□ Логирование добавлено
□ Документация обновлена
```

---

## 📞 Получение помощи

### Если тесты не проходят

1. Проверить `.env` → API ключи
2. Проверить `config/dev.exs` → testnet URL
3. Смотреть вывод `test_order_debug.exs` → подсказки

### Если не понятно что делать

1. Читать `DEBUG_FILES_README.md` → сценарии
2. Читать `QUICK_FIX_GUIDE.md` → быстрые решения
3. Смотреть `CHEATSHEET.md` → команды

### Если нужна более глубокая помощь

1. Читать `BINANCE_ORDER_DEBUG_REPORT.md` → анализ
2. Читать `TESTING_WORKFLOW.md` → архитектура
3. Экспериментировать с `iex_test_commands.md`

---

## 🎉 Итого

**Создано:** 9 файлов документации и кода
**Покрытие:** От быстрых решений до глубокого анализа
**Время на исправление:** 15-30 минут
**Статус:** ✅ Готово к использованию

**Главное:** Начни с [`test_order_debug.exs`](./test_order_debug.exs), затем используй [`CHEATSHEET.md`](./CHEATSHEET.md) как справочник!

---

**Версия:** 1.0.0
**Дата:** 2025-11-25
**Автор:** Claude Code
**Проект:** Binance Trading System
