# GigaChat Flutter

Flutter-приложение, являющееся аналогом ChatGPT, использующее API GigaChat от Сбера.

## Требования

- Flutter SDK (версия 3.0.0 или выше)
- Dart SDK (версия 3.0.0 или выше)
- API ключ GigaChat от Сбера

## Установка

1. Клонируйте репозиторий:
```bash
git clone https://github.com/yourusername/giflute.git
cd giflute
```

2. Установите зависимости:
```bash
flutter pub get
```

3. Создайте файл `.env` в корне проекта и добавьте ваш API ключ GigaChat:
```
GIGACHAT_API_KEY=your_api_key_here
```

## Запуск

Для запуска приложения выполните:
```bash
flutter run
```

## Функциональность

- Чат-интерфейс в стиле ChatGPT
- Поддержка Markdown в сообщениях
- Темная и светлая темы
- Сохранение истории сообщений
- Индикатор загрузки при отправке сообщений

## Разработка

Проект использует следующие основные пакеты:
- provider: для управления состоянием
- http: для работы с API
- flutter_markdown: для отображения Markdown
- shared_preferences: для локального хранения данных
- google_fonts: для кастомных шрифтов

## Лицензия

MIT 