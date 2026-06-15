# Унификация лейаутов и навигации под PhoenixKit

**Дата:** 2026-06-15
**Ветка:** `refactor/unify-layouts-navigation`
**Статус:** design approved (Approach A)

## Проблема

В `dashboard_web` сосуществуют три кастомных лейаута и кастомная навигация,
которые дублируют то, что PhoenixKit уже предоставляет нативно:

- `components/layouts/trading_dashboard.html.heex` — обвязка для `/app/*` (своя шапка + свой sidebar).
- `components/layouts/public.html.heex` и функция `Layouts.app/1` — публичная шапка для блога/auth.
- `components/layouts/drawer.html.heex` — ещё один dashboard-лейаут (legacy, не подключён в роутере).
- `components/dashboard_nav.ex` — кастомные шапки, sidebar-ссылки, SVG-иконки, theme switcher, user-menu.

Итог: три разных хедера, дублирование навигации, устаревший «дашборд настроек пользователя».

## Цель

Свести всё к нативной системе PhoenixKit:

1. **Единый хедер для всех страниц** — гостевой и авторизованный варианты, на базе
   хедера PhoenixKit. На блоге/публичных страницах — хедер без sidebar; бренд-иконка
   ведёт на `/news`.
2. **Trading-навигация интегрирована в admin-sidebar PhoenixKit**, пункты trading —
   **над** элементами PhoenixKit.
3. **Удалить** кастомные лейауты и устаревший дашборд настроек пользователя.
4. Максимально следовать стилю/механике PhoenixKit, не ломая работу приложения.

## Как устроен PhoenixKit (факты)

- `PhoenixKitWeb.Components.LayoutWrapper.app_layout/1` решает обвязку по `current_path`:
  если путь (после снятия `url_prefix` = `/phoenix_kit` и locale) начинается с `/admin`
  → **admin-обвязка** (шапка + `admin_sidebar`); иначе → родительский публичный лейаут
  (сейчас `config :phoenix_kit, layout: {DashboardWeb.Layouts, :app}`).
- Sidebar строится из реестра табов `PhoenixKit.Dashboard` (`AdminTabs.default_tabs =
  core_tabs ++ module_tabs ++ settings_tabs`), сгруппированных по `Group` с `priority`.
- Публичный API расширения: `PhoenixKit.Dashboard.register_tabs(namespace, tabs)` /
  `register_admin_tabs/2`, `unregister_tabs/1`. `Tab`: `id, label, icon, path, priority,
  level, permission, parent, match`. `Group`: `id, label, priority`.
- Готовый лейаут `{PhoenixKitWeb.Layouts, :admin}` (`layouts/admin.html.heex`) оборачивает
  контент в `app_layout` с `current_path` по умолчанию `/admin`.
- Бренд/иконки в шапке конфигурируются настройками PhoenixKit (site icon/title).
- Оба пользователя — `Owner` и `Admin`: admin-обвязка доступна обоим, permission-гейтинг
  не блокирует.

## Выбранный подход (A)

Перенести trading-LiveView'ы в admin-namespace и отдать обвязку PhoenixKit; trading-табы
зарегистрировать в реестре с высоким приоритетом.

## Изменения

### 1. Маршруты (`router.ex`)
- Текущий `live_session :trading_app` с `layout: {DashboardWeb.Layouts, :trading_dashboard}`
  и путями `/app/*` → новый `live_session` с `layout: {PhoenixKitWeb.Layouts, :admin}` и
  путями в admin-namespace, которые `app_layout` распознаёт как admin (`…/admin/<x>`):
  - `/app/trading`   → `/admin/trading`   (`TradingLive`)
  - `/app/portfolio` → `/admin/portfolio` (`PortfolioLive`)
  - `/app/orders`    → `/admin/orders`    (`OrdersLive`)
  - `/app/history`   → `/admin/history`   (`HistoryLive`)
  - `/app/strategies`→ `/admin/strategies`(`StrategiesLive`)
  - `/app/chains`    → `/admin/chains`    (`ChainsLive`)
  - `/app/accounts`  → `/admin/accounts`  (`SettingsLive` — Binance API-ключи)
- Точные сегменты (locale-префикс / `url_prefix`) подбираются так, чтобы `admin_page?/1`
  возвращал `true` и подсветка активного таба работала. Проверяется через `mix phx.routes`
  и ручную загрузку.
- `PageController :home` (`/` → `/news`) остаётся.
- Если останутся внешние ссылки на `/app/*`, добавить redirect-заглушки `/app/* → /admin/*`
  (чтобы не ломать закладки).

### 2. Регистрация trading-табов
- Новый модуль `DashboardWeb.Navigation` (или вызов в `DashboardWeb.Application.start/2`
  после старта PhoenixKit), который вызывает `PhoenixKit.Dashboard.register_tabs(:trading, …)`.
- Группы с приоритетом **ниже** (= выше визуально) дефолтных групп PhoenixKit
  (`admin_main: 100`): например группа `:trading` priority `10`, `:trading_automation`
  priority `20`.
- Табы (icon — heroicons, path — новые admin-пути, `level: :admin`):
  - Trading `hero-chart-bar`, Portfolio `hero-wallet`, Orders `hero-clipboard-document-list`,
    History `hero-clock`, Strategies `hero-cpu-chip`, Chains `hero-link`,
    Accounts `hero-key`.
- `permission` — общий доступный обоим ролям (например `"dashboard"`); уточнить по
  существующим permission-ключам, чтобы пункты были видимы Owner/Admin.

### 3. Единый хедер на публичных страницах
- Оставить тонкий публичный лейаут для не-admin страниц (блог/auth), который рендерит
  **тот же** компонент шапки, что и admin (через `PhoenixKitWeb.Components.AdminNav`/
  штатную публичную шапку PhoenixKit), но без sidebar.
- Вариант реализации (выбрать при имплементации, оба дают единый хедер):
  - (предпочт.) упростить `DashboardWeb.Layouts.app/1` до тонкой обёртки, переиспользующей
    компонент шапки PhoenixKit + бренд-иконку → `/news`; или
  - убрать override `config :phoenix_kit, layout:` и положиться на публичный лейаут
    PhoenixKit, задав бренд через настройки.
- Гость: логин + тема + иконка→/news. Авторизованный: user-menu PhoenixKit.

### 4. Удаление
- Файлы: `layouts/trading_dashboard.html.heex`, `layouts/drawer.html.heex`,
  `layouts/public.html.heex`, `components/dashboard_nav.ex`.
- Из `layouts.ex`: функции `app/1`, `trading_nav_link/1`, `trading_nav_icon/1` — если
  публичный хедер переведён на компонент PhoenixKit (иначе `app/1` упрощается, а не удаляется).
- Устаревший «дашборд настроек пользователя»: убрать пункт Profile → `/dashboard/settings`;
  профиль/настройки — через user-menu PhoenixKit. Кастомный дашборд-экран (если есть наш
  собственный) — удалить.
- Подчистить ссылки на удаляемые модули/иконки во вьюхах (`grep` по `DashboardNav`,
  `trading_dashboard`, `/app/`, `/dashboard/settings`).

### 5. Сохранить
- `root.html.heex` (выровнять при необходимости под ожидания `:admin`-лейаута как HTML-оболочки).
- Binance «Accounts» (`SettingsLive`) — как trading-таб.
- Логику самих LiveView'ов (trading/portfolio/orders/…): меняются только обвязка,
  пути и `current_path`, бизнес-логика не трогается.

## Что проверить при реализации (открытые места)
1. Совместимость нашего `root.html.heex`/endpoint с `:admin`-лейаутом (HTML-оболочка:
   head/assets/CSRF). Если `:admin` ожидает родительский root — оставить наш root.
2. Содержит ли публичная шапка PhoenixKit тему/логин в нужном виде; иначе собрать
   тонкий публичный лейаут из компонентов PhoenixKit.
3. Корректность `admin_page?/1` для выбранных trading-путей (locale/`url_prefix`).
4. Permission-ключ trading-табов — видимость для Owner/Admin.

## Критерии приёмки
- `mix compile --warnings-as-errors` — чисто.
- `MIX_ENV=test mix test` — без падений (81+).
- Сервер поднимается, ошибок в логе нет.
- Все trading-страницы рендерятся в admin-обвязке PhoenixKit с общим sidebar; пункты
  Trading/Automation/Accounts — **над** пунктами PhoenixKit, активный пункт подсвечивается.
- Блог/публичные страницы и admin используют **единый хедер**; гость видит логин+тему+иконку→/news,
  авторизованный — user-menu.
- Нет ссылок на удалённые лейауты/`dashboard_nav`; старые `/app/*` либо редиректят, либо
  обновлены на `/admin/*`.
- Кастомные лейауты `trading_dashboard`/`public`/`drawer` и `dashboard_nav.ex` удалены.

## Вне рамок (YAGNI)
- Не добавляем новые trading-фичи/страницы.
- Не трогаем бизнес-логику стратегий/ордеров.
- Не вводим newsletters/прочие модули (отдельная задача).
- Не делаем редизайн контента страниц — только обвязка/навигация.
