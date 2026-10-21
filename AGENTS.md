# Моя Ева — AGENTS.md

Мобильное приложение: эмпатичный ИИ-помощник по женскому здоровью и питанию. Общие правила команды — в `exapp-hq/AGENTS.md`.

## Что это
- Публикация: RuStore, Android. Пакет `com.eduard.nutribalance`. Лендинг my-eva.ru (облачный хостинг Beget). Группа VK со статьями владельца.
- Аудитория: девушки и женщины, Россия; часть пользователей за рубежом или с VPN.
- Функции: дневник питания и КБЖУ по фото, вода, список покупок; чат с ИИ-нутрициологом «Ева» (фото, PDF-анализы, рецепты, «Что съесть?», «Меню от Евы» по фазе цикла); «Гармония» — женский календарь (стандартный, простой, беременность, менопауза; симптомы, настроение, вес, лекарства, PDF-отчёт); чаты P2P, поддержка, личный специалист; «Итоги недели»; заботливые напоминания и пуши.
- Монетизация: Premium через RuStore, промокоды, бесплатные лимиты (5 сообщений Еве, 3 скана еды).
- Полный аудит — `AUDIT_2026-09.md` в корне репозитория (там же чек-лист ручной проверки).

## Стек
- Flutter 3.38.7 / Dart 3.10, Material 3, minSdk 24, AGP 8.11.1, Gradle 8.13, Kotlin 2.2.20. Версия 1.1.1+15.
- Firebase-проект `nutribalance-app-11a09` (Blaze). Рабочее Android-приложение — «NutriBalance Новое»; «flutter_application_1 (android)» — старая тестовая запись.
- Клиент: Auth (email + Google), Firestore (офлайн-кэш), Storage, FCM, App Check, Functions, Analytics, Crashlytics; AppMetrica через `lib/services/analytics_service.dart`.
- Сервер: Cloud Functions v2, Node 22, firebase-functions 7.3.2, firebase-admin 14.3.0 (модульный API). 11 функций: чат, Ева (`askDietitian`), итоги недели, проверка покупок RuStore, промокоды, public_profiles, уведомления, очистка при удалении аккаунта.
- ИИ: Gemini 2.5 Flash только через Cloud Functions (ключ в `functions/.env`).
- Платежи: flutter_rustore_billing 7.x, подтверждение на сервере.
- Правила: `security/firestore.rules.phase1`, `firestore.rules.strict`, `storage.rules`; firebase.json ссылается на phase1.
- Дизайн-система «Soft Luxury»: `lib/theme/eva_colors.dart`, `lib/theme/app_theme.dart`, `lib/widgets/eva_ui.dart`, `lib/widgets/chat_widgets.dart`; шрифты Inter и Noto Serif Display вшиты.

## Сборка и релиз
- `flutter pub get` → релизная сборка → загрузка в консоль RuStore (вручную, владелец).
- Деплой функций: `firebase deploy --only functions` — из России нужен VPN и `firebase login --reauth`.
- Правила: `firebase deploy --only firestore:rules,storage`.
- Публикация в RuStore и деплой правил/функций в прод — только с подтверждением владельца.

## Правила проекта (не менять без согласования)
- Записи в Firestore без ожидания сервера, чтение сначала из кэша, без клиентских транзакций (VPN и зарубеж).
- Резервный HTTPS-канал чата (`sendChatMessage` / `fetchChatMessages`) с тем же ID сообщения.
- Поиск и чаты — через коллекцию `public_profiles`, не через `users`.
- Лимиты, покупки и промокоды — только на сервере; совместимость со старыми клиентами (`serverVersion: 2`).
- Правила Firestore в два этапа: phase1, затем strict через 2–4 недели. Удаление чатов запрещено правилами.
- Шрифты вшиты, без Google Fonts.
- Напоминания — разовые на 7 дней вперёд, перепланируются при каждом запуске; точные будильники не используются (дубли на Xiaomi).
- Срок беременности — акушерский, ПДР = первый день последних месячных + 280 дней.
- Gemini: без «размышления» для текста, небольшой бюджет для фото и PDF.
- Аналитика: Firebase + AppMetrica; только UID и обезличенные категории — без имён, почты, дат цикла и симптомов. Это данные о здоровье — никаких персональных данных в логах, отчётах и аналитике.

## Известные проблемы
- 1.1.1 не закоммичена; сборка с аналитикой не проверена (риск — Gradle-плагин Crashlytics 3.0.6); на устройствах не тестировалась.
- Деплой функций не подтверждён (CLI без VPN не достучался) — админ-кнопка «Обновить публичные профили» выдаёт NOT_FOUND.
- БЕЗОПАСНОСТЬ: правила phase1 позволяют пользователю самому изменить `isPro`/`proUntil`; правила ещё не выкачены.
- Покупки RuStore не сверяются с API RuStore (из Google Cloud недоступен без российского прокси); с VPN оплата не работает.
- Release подписан debug-ключом; смена ключа — только через процедуру RuStore.
- После phase1 старые версии не смогут проверять промокоды.
- Фоновые пуши чата обрезают длинный текст.
- При полной блокировке Google приложение работает только из кэша.
- Мёртвый код: nutrition_stats_screen.dart, dashboard/ai_assistants_card.dart, dashboard/daily_meals_bottom_sheet.dart, widgets/shopping_list_widget.dart, ui_widgets.dart; лишние `../` в импортах harmony/widgets; `.git/stale-index-lock-from-audit.tmp`.

## Ближайшие задачи (по порядку)
1. `flutter pub get`, релизная сборка 1.1.1+15, разобрать ошибки Gradle/Crashlytics.
2. Тестовый сбой из админ-меню → проверить Crashlytics.
3. Деплой функций с VPN.
4. Публикация 1.1.1+15 в RuStore.
5. Один раз «Обновить публичные профили».
6. Правила phase1; через 2–4 недели strict.
7. Бюджет с оповещениями в Google Cloud Billing.
8. Через сутки после релиза — события, воронка, дашборд в Firebase Analytics и AppMetrica.

## Техдолг и идеи
- Настоящий release-ключ (по процедуре RuStore).
- Проверка чеков RuStore через функцию в Yandex Cloud.
- Свой прокси-домен для функций (Cloudflare Worker / Yandex API Gateway) на случай блокировки Google.
- Пункт о Firebase Analytics, Crashlytics и AppMetrica в политике конфиденциальности (152-ФЗ, модерация RuStore).
- Трекер установок (AppMetrica / MyTracker) перед рекламой.
- Разворачиваемые фоновые пуши чата (data-сообщения).
- Если чтений Firestore > ~40 000 в день — снизить нагрузку.
