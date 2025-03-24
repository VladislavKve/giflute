# История взаимодействий с API GigaChat и решения проблем

## Проблемы и решения

### 1. Настройка HTTPS/SSL соединения

**Проблема**: 
- Ошибки при соединении с API через HTTPS
- Проблемы с проверкой SSL сертификатов для домена sberbank.ru

**Решение**:
- Для нативных платформ (Android, iOS, Windows):
  ```dart
  if (dio.httpClientAdapter is IOHttpClientAdapter) {
    final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) {
        return host.contains('sberbank.ru');
      };
      return client;
    };
  }
  ```

- Для веб-платформы:
  ```dart
  // В веб-версии не настраиваем сертификаты
  if (kIsWeb) {
    return;
  }
  ```

### 2. Формат отправки данных для авторизации

**Проблема**:
- Неверный формат данных при отправке запроса на получение токена
- Различные требования для нативных платформ и веб

**Решение**:
- Использование формата application/x-www-form-urlencoded:
  ```dart
  final formData = {
    'scope': AppConfig.scope,
  };
  
  final response = await _dio.post(
    AppConfig.authUrl,
    data: formData,
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      headers: {
        'Accept': 'application/json',
        'RqUID': uuid,
        'Authorization': 'Basic ${base64.encode(utf8.encode(_authKey))}',
      },
    ),
  );
  ```

### 3. CORS проблемы в веб-версии

**Проблема**:
- Ошибки CORS при выполнении запросов из браузера
- XMLHttpRequest onError callback

**Решение**:
- Добавление CORS заголовков в запросы:
  ```dart
  if (kIsWeb) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers.addAll({
          'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Requested-With',
        });
        return handler.next(options);
      },
    ));
  }
  ```

- Предварительный OPTIONS запрос при ошибках CORS:
  ```dart
  onError: (error, handler) async {
    if (error.response?.statusCode == 403 || error.response?.statusCode == 0) {
      try {
        final options = error.requestOptions;
        await _dio.request(
          options.path,
          options: Options(
            method: 'OPTIONS',
            headers: options.headers,
          ),
        );
        
        final response = await _dio.request(
          options.path,
          data: options.data,
          options: Options(
            method: options.method,
            headers: options.headers,
          ),
        );
        
        handler.resolve(response);
      } catch (e) {
        handler.next(error);
      }
    } else {
      handler.next(error);
    }
  }
  ```

### 4. Настройка таймаутов

**Проблема**:
- Зависания запросов без ответа

**Решение**:
- Настройка таймаутов для всех операций:
  ```dart
  _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    // ...
  ));
  ```

### 5. Обработка ошибок

**Проблема**:
- Неинформативные сообщения об ошибках
- Сложность диагностики проблем

**Решение**:
- Создание специального класса исключений `GigaChatException`
- Детальная обработка различных типов ошибок:
  ```dart
  on DioException catch (e) {
    if (e.type == DioExceptionType.connectionTimeout) {
      throw GigaChatException('Превышено время ожидания подключения');
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      throw GigaChatException('Превышено время ожидания ответа');
    }
    if (e.type == DioExceptionType.sendTimeout) {
      throw GigaChatException('Превышено время отправки запроса');
    }
    if (e.type == DioExceptionType.badCertificate) {
      throw GigaChatException('Ошибка SSL сертификата');
    }
    throw GigaChatException(
      'Ошибка сети при получении токена: ${e.message}',
      originalError: e
    );
  }
  ```

## Важные замечания

1. **Для работы в браузере**:
   - API должно поддерживать CORS
   - Если API не поддерживает CORS, необходим прокси-сервер

2. **Безопасность**:
   - Не рекомендуется использовать `badCertificateCallback` с `return true` для всех доменов
   - Лучше ограничить специфическими доменами: `return host.contains('sberbank.ru')`

3. **Обновление токена**:
   - Токен имеет ограниченный срок действия (обычно 1 час)
   - Необходимо проверять срок действия перед каждым запросом:
   ```dart
   if (_accessToken == null || _tokenExpiry == null || DateTime.now().isAfter(_tokenExpiry!)) {
     await _getAccessToken();
   }
   ```

## Изменения методов API

1. В старых версиях Dio:
   - `onHttpClientCreate` - для настройки SSL
   
2. В новых версиях Dio:
   - `createHttpClient` - предпочтительный метод для создания HTTP клиента
   - `validateCertificate` - альтернативный метод для проверки сертификатов

## Инструменты для отладки

1. Включение логирования для Dio:
   ```dart
   _dio.interceptors.add(LogInterceptor(
     requestBody: true,
     responseBody: true,
     error: true,
   ));
   ```

2. Проверка запросов через инструменты разработчика браузера (Network tab)

3. Проверка запросов через внешние инструменты (Postman, curl) 