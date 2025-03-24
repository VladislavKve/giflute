import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class SileroTtsService {
  // Устанавливаем URLs сервисов TTS
  // Первичный сервис
  static const String _baseUrl = 'https://tts-api.narakeet.com';
  // Резервный сервис
  static const String _fallbackUrl = 'https://tts.narakeet.com';
  
  // API ключ (для примера)
  static const String _apiKey = ''; // Здесь должен быть ваш API-ключ
  
  // Параметры голоса
  static const String _defaultVoice = 'ru_v3_nadya'; // Надя (женский голос)
  static const double _defaultSpeechRate = 1.0;
  
  // Плеер для воспроизведения аудио
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Флаги состояния
  bool _isSpeaking = false;
  bool _isInitialized = false;
  String? _lastError;
  
  // Геттеры для проверки состояния
  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  
  // Соответствие наших голосов к голосам API
  static const Map<String, String> _voiceMapping = {
    'ru_v3_nadya': 'natasha',   // Надя → Наташа (русский)
    'ru_v3_kseniya': 'natasha', // Ксения → Наташа (русский)
    'ru_v3_aidar': 'maxim',     // Айдар → Максим (русский)
    'ru_v3_baya': 'natasha',    // Бая → Наташа (русский)
  };
  
  // Список доступных голосов
  static const List<Map<String, String>> availableVoices = [
    {'id': 'ru_v3_nadya', 'name': 'Надя (женский)'},
    {'id': 'ru_v3_kseniya', 'name': 'Ксения (женский)'},
    {'id': 'ru_v3_aidar', 'name': 'Айдар (мужской)'},
    {'id': 'ru_v3_baya', 'name': 'Бая (женский)'},
  ];
  
  // Конструктор
  SileroTtsService() {
    _init();
  }
  
  // Инициализация сервиса
  Future<void> _init() async {
    try {
      _isInitialized = true;
      
      // Настройка обработчика завершения
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isSpeaking = false;
        }
      });
      
      // Подписка на ошибки
      _audioPlayer.playbackEventStream.listen(
        (event) {}, 
        onError: (Object e, StackTrace st) {
          _lastError = "Ошибка воспроизведения: $e";
          _isSpeaking = false;
        }
      );
      
    } catch (e) {
      _isInitialized = false;
      _lastError = "Ошибка инициализации TTS: $e";
      debugPrint(_lastError);
    }
  }
  
  // Метод для получения временного файла
  Future<String> _getTempFilePath() async {
    final directory = await getTemporaryDirectory();
    return '${directory.path}/tts_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
  }
  
  // Преобразовать наш внутренний ID голоса в ID голоса API
  String _mapVoice(String internalVoiceId) {
    return _voiceMapping[internalVoiceId] ?? 'natasha'; // По умолчанию русский женский голос
  }
  
  // Синтез речи через альтернативный публичный сервис
  Future<void> _generateSpeechWithFallback(String text, String voice) async {
    try {
      // Получаем маппинг голоса для API
      final apiVoice = _mapVoice(voice);
      
      // Используем Narakeet TTS API
      final response = await http.post(
        Uri.parse('$_fallbackUrl/api/v1/tts'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
          'x-api-key': _apiKey,
        },
        body: jsonEncode({
          'text': text,
          'voice': apiVoice,
          'sample_rate': 48000,
          'audio_format': 'mp3',
        }),
      );

      if (response.statusCode == 200) {
        // Сохраняем аудио во временный файл
        final audioFilePath = await _getTempFilePath();
        final audioFile = File(audioFilePath);
        await audioFile.writeAsBytes(response.bodyBytes);
        
        // Воспроизводим аудио
        await _audioPlayer.setFilePath(audioFilePath);
        await _audioPlayer.play();
        
        debugPrint("Успешное воспроизведение через резервный сервис");
      } else {
        throw Exception('Ошибка резервного сервиса: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Ошибка резервного сервиса: $e");
      rethrow; // Пробрасываем ошибку для обработки в основном методе
    }
  }
  
  // Эмуляция синтеза речи (используется при отсутствии доступа к API)
  Future<void> _generateSpeechEmulation(String text) async {
    try {
      // Эмулируем задержку, как будто отправляем запрос к API
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Создаем временный файл, чтобы AudioPlayer мог работать
      final audioFilePath = await _getTempFilePath();
      
      // Выбрасываем ошибку, так как это просто эмуляция
      throw Exception("Это эмуляция сервиса TTS без реального API ключа");
    } catch (e) {
      debugPrint("Ошибка эмуляции: $e");
      rethrow;
    }
  }
  
  // Озвучка текста
  Future<void> speak(String text, {
    String voice = _defaultVoice,
    double speechRate = _defaultSpeechRate
  }) async {
    if (text.isEmpty) return;
    
    // Если уже говорим, останавливаем
    if (_isSpeaking) {
      await stop();
      return;
    }
    
    try {
      _isSpeaking = true;
      _lastError = null;
      
      // Ограничиваем длину текста
      if (text.length > 1000) {
        text = '${text.substring(0, 1000)}... (текст слишком длинный)';
      }
      
      // Пробуем использовать основной сервис
      try {
        if (_apiKey.isEmpty) {
          // Если API ключ не указан, используем эмуляцию
          await _generateSpeechEmulation(text);
        } else {
          // Используем резервный метод
          await _generateSpeechWithFallback(text, voice);
        }
      } catch (e) {
        debugPrint("Ошибка при синтезе речи: $e");
        _lastError = "Ошибка сервиса TTS: $e";
        _isSpeaking = false;
        rethrow;
      }
    } catch (e) {
      _isSpeaking = false;
      _lastError = "Ошибка TTS: $e";
      debugPrint(_lastError);
      rethrow;
    }
  }
  
  // Останавливаем воспроизведение
  Future<void> stop() async {
    if (_isSpeaking) {
      await _audioPlayer.stop();
      _isSpeaking = false;
    }
  }
  
  // Освобождаем ресурсы
  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
} 