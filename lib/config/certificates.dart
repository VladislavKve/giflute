import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';

void configureCertificates(Dio dio) {
  // В веб-версии используем CORS-прокси
  if (kIsWeb) {
    // Используем публичный CORS прокси для обхода ограничений
    dio.options.baseUrl = 'https://corsproxy.io/?';
    
    // Добавляем интерцептор для изменения URL
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Форматируем запрос для работы через CORS-прокси
        final origUrl = options.uri.toString();
        options.path = Uri.encodeComponent(origUrl);
        
        print('Перенаправление через CORS-прокси: ${options.path}');
        
        // Добавляем CORS-заголовки
        options.headers['X-Requested-With'] = 'XMLHttpRequest';
        options.headers['Origin'] = 'https://gigachat.devices.sberbank.ru';
        
        return handler.next(options);
      },
    ));
    
    return;
  }
  
  if (dio.httpClientAdapter is IOHttpClientAdapter) {
    final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
    adapter.createHttpClient = () {
      final client = HttpClient();
      
      // Принимаем все сертификаты для домена sberbank.ru
      client.badCertificateCallback = (cert, host, port) {
        if (host.contains('sberbank.ru') || host.contains('devices.sberbank.ru')) {
          print('Accepting certificate for host: $host');
          return true;
        }
        
        // Для других хостов проверяем сертификаты стандартно
        print('Validating certificate for host: $host');
        return false;
      };
      
      // Настраиваем более длительные таймауты для решения проблем с сетью
      client.connectionTimeout = const Duration(seconds: 30);
      client.idleTimeout = const Duration(seconds: 60);
      
      return client;
    };

    // Дополнительные настройки для решения проблем с SSL
    adapter.validateCertificate = (cert, host, port) {
      if (host.contains('sberbank.ru') || host.contains('devices.sberbank.ru')) {
        return true;
      }
      return false;
    };
  }
} 