import 'package:dio/dio.dart';
import '../config/certificates.dart';
import '../config/app_config.dart';
import 'package:uuid/uuid.dart';
import '../exceptions/gigachat_exception.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:io' show SocketException;

class GigaChatService {
  final Dio _dio;
  String? _accessToken;
  DateTime? _tokenExpiry;

  GigaChatService() 
    : _dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30), // Увеличиваем время соединения
        receiveTimeout: const Duration(seconds: 30), // Увеличиваем время ожидания ответа
        sendTimeout: const Duration(seconds: 30), // Увеличиваем время отправки
        validateStatus: (status) => status != null && status >= 200 && status < 500,
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json',
          'User-Agent': 'GigaChatFlutter/1.0',
          if (kIsWeb) 'Access-Control-Allow-Origin': '*',
        },
      )) {
    configureCertificates(_dio);
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      requestHeader: true,
      error: true,
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.badResponse ||
              e.error is SocketException) {
            
            RequestOptions request = e.requestOptions;
            
            int retryCount = request.extra['retryCount'] ?? 0;
            if (retryCount < 3) {
              request.extra['retryCount'] = retryCount + 1;
              
              await Future.delayed(Duration(seconds: retryCount + 1));
              
              print('Retry attempt ${retryCount + 1} for ${request.path}');
              
              try {
                final response = await _dio.fetch(request);
                handler.resolve(response);
                return;
              } catch (error) {
                if (retryCount >= 2) {
                  handler.next(e);
                  return;
                }
                handler.next(DioException(
                  requestOptions: request,
                  error: error,
                  type: e.type,
                ));
                return;
              }
            }
          }
          
          handler.next(e);
        },
      ),
    );

    if (kIsWeb) {
      // В веб-версии используем специальную обработку CORS
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          // Для веб-версии изменяем заголовки, чтобы обойти проблемы с CORS
          options.headers.addAll({
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Requested-With',
            'Access-Control-Allow-Origin': '*',
          });
          
          // Не изменяем базовый URL, так как это уже делается в configureCertificates
          
          // Логируем запрос для отладки
          print('Web request to: ${options.path}');
          print('Headers: ${options.headers}');
          
          return handler.next(options);
        },
        onError: (error, handler) async {
          // Детально логируем ошибки для лучшей отладки
          print('CORS Error: ${error.message}');
          print('Error Type: ${error.type}');
          print('Error Response: ${error.response}');
          
          // Если ошибка CORS, пробуем другой подход
          if (error.response?.statusCode == 403 || 
              error.response?.statusCode == 0 ||
              error.type == DioExceptionType.connectionError) {
            
            print('Trying to work around CORS issues...');
            
            // Отображаем более понятное сообщение пользователю
            handler.reject(DioException(
              requestOptions: error.requestOptions,
              error: 'Ошибка CORS в веб-версии. Попробуйте использовать нативную версию приложения или настроить прокси-сервер.',
              type: error.type
            ));
          } else {
            handler.next(error);
          }
        },
      ));
    }
  }

  Future<String> _getAccessToken() async {
    try {
      // Если у нас уже есть токен и он еще действителен, возвращаем его
      if (_accessToken != null && _tokenExpiry != null && 
          DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
        print('Using existing token, valid until ${_tokenExpiry?.toIso8601String()}');
        return _accessToken!;
      }
      
      print('Requesting new access token...');
      final uuid = const Uuid().v4();
      
      final formData = {
        'scope': AppConfig.scope,
        'grant_type': 'client_credentials',
      };
      
      // Используем готовый ключ авторизации из примера коллеги
      const authString = 'M2Y2ZTdkYmEtNDRjYS00NjFiLTgyZTctN2Y5MGMwMmVmNWIxOjZkMzI0MzhjLTYxYjktNGRhNi1iZTA1LWMzNzFhODJmY2ZiOQ==';
      
      // Оборачиваем запрос в повторяющуюся логику для максимальной надежности
      int retryCount = 0;
      while (retryCount < 5) { // максимум 5 попыток
        try {
          final response = await _dio.post(
            AppConfig.authUrl,
            data: formData,
            options: Options(
              headers: {
                'RqUID': uuid,
                'Authorization': 'Basic $authString',
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
              },
            ),
          );
          
          if (response.statusCode == 200) {
            final token = response.data['access_token'];
            if (token != null) {
              _accessToken = token;
              _tokenExpiry = DateTime.now().add(const Duration(hours: 1));
              print('Token obtained successfully, valid until ${_tokenExpiry?.toIso8601String()}');
              return token;
            }
            throw GigaChatException('Токен отсутствует в ответе');
          }

          if (response.statusCode == 401) {
            throw GigaChatException('Ошибка авторизации: неверный ключ авторизации');
          }

          if (response.statusCode == 429) {
            throw GigaChatException('Превышен лимит запросов. Попробуйте позже');
          }

          throw GigaChatException(
            'Ошибка получения токена: ${response.data['message'] ?? 'Неизвестная ошибка'}',
            statusCode: response.statusCode
          );
        } on DioException {
          // Увеличиваем счетчик попыток
          retryCount++;
          
          // Если это последняя попытка, выбрасываем исключение
          if (retryCount >= 5) {
            rethrow;
          }
          
          // Иначе ждем и пробуем снова
          final delay = Duration(seconds: retryCount);
          print('Network error during token request. Retrying in ${delay.inSeconds} seconds... (Attempt $retryCount/5)');
          await Future.delayed(delay);
        }
      }
      
      // Этот код не должен выполниться, но на всякий случай
      throw GigaChatException('Превышено количество попыток получения токена');
    } on DioException catch (e) {
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
    } catch (e) {
      if (e is GigaChatException) rethrow;
      throw GigaChatException('Ошибка при получении токена', originalError: e);
    }
  }

  Future<String> sendMessage(String message) async {
    try {
      // Предварительная проверка токена до отправки сообщения
      if (_accessToken == null || _tokenExpiry == null || DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
        await _getAccessToken();
      }

      final response = await _dio.post(
        AppConfig.chatCompletionsUrl,
        data: {
          'model': 'GigaChat',
          'messages': [
            {
              'role': 'system',
              'content': AppConfig.systemPrompt
            },
            {
              'role': 'user',
              'content': message
            }
          ],
          'stream': true, // Используем потоковую передачу для более быстрого получения ответа
          'temperature': 0.7, // Оптимальная температура для баланса креативности и скорости
          'max_tokens': 1000, // Ограничение токенов для ускорения ответа
          'update_interval': 0
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${_accessToken ?? ""}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          // Уменьшаем таймауты для быстрого ответа
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      
      if (response.statusCode == 200) {
        // Быстрая проверка и извлечение ответа
        final choices = response.data['choices'];
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']['content'];
          if (content != null) {
            return content;
          }
        }
        throw GigaChatException('Некорректный формат ответа');
      }

      if (response.statusCode == 401) {
        _accessToken = null;
        _tokenExpiry = null;
        // Немедленно получаем новый токен и пробуем снова
        await _getAccessToken();
        return sendMessage(message); // Повторная отправка запроса с новым токеном
      }

      throw GigaChatException('Ошибка отправки сообщения', statusCode: response.statusCode);
    } on DioException catch (e) {
      throw GigaChatException(
        'Ошибка сети при отправке сообщения: ${e.message}',
        originalError: e
      );
    } catch (e) {
      if (e is GigaChatException) rethrow;
      throw GigaChatException('Ошибка при отправке сообщения', originalError: e);
    }
  }

  // Улучшаем метод потокового обмена
  Stream<String> streamMessage(String message) async* {
    try {
      if (_accessToken == null || _tokenExpiry == null || DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
        await _getAccessToken();
      }

      // Обертываем в блок повторных попыток для надежности
      int retryAttempt = 0;
      const maxRetries = 2;
      
      while (retryAttempt <= maxRetries) {
        try {
          final response = await _dio.post(
            AppConfig.chatCompletionsUrl,
            data: {
              'model': 'GigaChat',
              'messages': [
                {
                  'role': 'system',
                  'content': AppConfig.systemPrompt
                },
                {
                  'role': 'user',
                  'content': message
                }
              ],
              'stream': true,
              'temperature': 0.7,
              'max_tokens': 1000,
              'update_interval': 1 // Частые обновления
            },
            options: Options(
              headers: {
                'Authorization': 'Bearer ${_accessToken ?? ""}',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
              },
              responseType: ResponseType.stream,
              // Увеличиваем таймауты для большей надежности
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
          
          if (response.statusCode == 200) {
            final stream = response.data.stream as Stream<List<int>>;
            String buffer = '';
            
            await for (final chunk in stream) {
              final chunkString = utf8.decode(chunk);
              buffer += chunkString;
              
              if (buffer.contains('\n')) {
                final parts = buffer.split('\n');
                buffer = parts.last;
                
                for (int i = 0; i < parts.length - 1; i++) {
                  final part = parts[i].trim();
                  if (part.startsWith('data: ')) {
                    final jsonStr = part.substring(6);
                    if (jsonStr != '[DONE]') {
                      try {
                        final jsonData = json.decode(jsonStr);
                        final choices = jsonData['choices'];
                        if (choices != null && choices.isNotEmpty) {
                          final delta = choices[0]['delta'];
                          if (delta != null && delta['content'] != null) {
                            yield delta['content'];
                          }
                        }
                      } catch (e) {
                        // Логируем ошибки парсинга для отладки
                        print('Ошибка парсинга JSON: $e, данные: $jsonStr');
                      }
                    }
                  }
                }
              }
            }
            
            // Успешно завершили обработку потока
            break;
          } else if (response.statusCode == 401) {
            // Токен устарел, обновляем и повторяем попытку
            _accessToken = null;
            _tokenExpiry = null;
            await _getAccessToken();
            retryAttempt++;
            
            if (retryAttempt > maxRetries) {
              throw GigaChatException('Не удалось авторизоваться после нескольких попыток');
            }
          } else {
            // Другие ошибки HTTP
            if (retryAttempt < maxRetries) {
              retryAttempt++;
              await Future.delayed(Duration(seconds: retryAttempt));
              print('Повторная попытка потоковой передачи ($retryAttempt/$maxRetries)');
            } else {
              throw GigaChatException('Ошибка потоковой передачи', statusCode: response.statusCode);
            }
          }
        } on DioException catch (dioError) {
          if (dioError.type == DioExceptionType.connectionTimeout ||
              dioError.type == DioExceptionType.receiveTimeout ||
              dioError.type == DioExceptionType.sendTimeout ||
              dioError.type == DioExceptionType.connectionError) {
                
            if (retryAttempt < maxRetries) {
              retryAttempt++;
              await Future.delayed(Duration(seconds: retryAttempt));
              print('Повторная попытка после таймаута ($retryAttempt/$maxRetries)');
            } else {
              throw GigaChatException('Превышено время ожидания ответа от сервера после нескольких попыток');
            }
          } else {
            // Другие ошибки Dio, которые не связаны с таймаутами
            rethrow;
          }
        }
      }
    } catch (e) {
      if (e is GigaChatException) rethrow;
      throw GigaChatException('Ошибка при потоковой передаче: ${e.toString()}', originalError: e);
    }
  }
} 