import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat.dart';
import '../services/gigachat_service.dart';
import '../exceptions/gigachat_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ChatProvider with ChangeNotifier {
  static const String _storageKey = 'chats';
  List<Chat> _chats = [];
  Chat? _currentChat;
  bool _isLoading = false;
  String? _error;
  String? _currentlyEditingMessageId;
  late final GigaChatService _gigaChatService;
  bool _isInitialized = false;
  String? _accessToken;
  DateTime? _tokenExpiration;
  final String _apiBaseUrl;
  final String _clientId;
  final String _scope;

  List<Chat> get chats => _chats;
  Chat? get currentChat => _currentChat;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;
  String? get currentlyEditingMessageId => _currentlyEditingMessageId;

  ChatProvider({
    required String clientId,
    required String scope,
    required String apiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl,
       _clientId = clientId,
       _scope = scope {
    try {
      _gigaChatService = GigaChatService();
      _loadChats();
    } catch (e) {
      _error = 'Ошибка инициализации: $e';
      _initializeWithDummyData();
      notifyListeners();
    }
  }

  // Инициализация с фейковыми данными для веб-версии при проблемах
  void _initializeWithDummyData() {
    if (kIsWeb) {
      // В веб-версии можем показать демо-данные
      print('Инициализация с демо-данными для веб-версии');
      
      final demoChat = Chat(
        id: const Uuid().v4(),
        title: 'Демо-чат (веб-версия)',
        messages: [
          Message(
            content: 'Привет! Это демо-режим для веб-версии.',
            isUser: false,
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
          Message(
            content: 'Из-за CORS-ограничений в веб-браузерах некоторые функции могут быть недоступны.',
            isUser: false,
            timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
          ),
          Message(
            content: 'Для полноценной работы рекомендуется использовать мобильную или десктопную версию.',
            isUser: false,
            timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
          ),
        ],
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      
      _chats = [demoChat];
      _currentChat = demoChat;
      _isInitialized = true;
    }
  }

  Future<void> _loadChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatsJson = prefs.getStringList(_storageKey) ?? [];
      
      if (chatsJson.isEmpty) {
        createNewChat();
      } else {
        _chats = chatsJson.map((json) => Chat.fromJsonString(json)).toList();
        _currentChat = _chats.first;
      }
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Ошибка при загрузке чатов: $e';
      createNewChat();
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _saveChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatsJson = _chats.map((chat) => chat.toJsonString()).toList();
      await prefs.setStringList(_storageKey, chatsJson);
    } catch (e) {
      _error = 'Ошибка при сохранении чатов: $e';
      notifyListeners();
    }
  }

  void createNewChat() {
    final newChat = Chat(
      id: const Uuid().v4(),
      title: 'Новый чат',
      messages: [],
      createdAt: DateTime.now(),
    );
    _chats.add(newChat);
    _currentChat = newChat;
    _error = null;
    _saveChats();
    notifyListeners();
  }

  void selectChat(String chatId) {
    _currentChat = _chats.firstWhere((chat) => chat.id == chatId);
    _error = null;
    notifyListeners();
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty || _currentChat == null) return;

    final newMessage = Message(
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    _updateCurrentChatWithMessage(newMessage);
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _gigaChatService.sendMessage(message);
      
      final botMessage = Message(
        content: response,
        isUser: false,
        timestamp: DateTime.now(),
      );

      _updateCurrentChatWithMessage(botMessage);
    } catch (e) {
      if (e is GigaChatException) {
        _error = e.toString();
      } else {
        _error = 'Произошла непредвиденная ошибка: $e';
      }
    } finally {
      _isLoading = false;
      _saveChats();
      notifyListeners();
    }
  }

  void _updateCurrentChatWithMessage(Message message) {
    final updatedChat = _currentChat!.copyWith(
      messages: [..._currentChat!.messages, message],
    );
    _currentChat = updatedChat;
    _chats = _chats.map((chat) => 
      chat.id == updatedChat.id ? updatedChat : chat
    ).toList();
    
    // Обновляем название чата после первых двух сообщений
    if (updatedChat.messages.length == 2 && updatedChat.title == 'Новый чат') {
      _updateChatTitleFromContext(updatedChat);
    }
    
    _saveChats();
    notifyListeners();
  }

  void deleteChat(String chatId) {
    _chats.removeWhere((chat) => chat.id == chatId);
    if (_currentChat?.id == chatId) {
      if (_chats.isNotEmpty) {
        _currentChat = _chats.first;
      } else {
        createNewChat();
      }
    }
    _error = null;
    _saveChats();
    notifyListeners();
  }

  void updateChatTitle(String chatId, String newTitle) {
    _chats = _chats.map((chat) {
      if (chat.id == chatId) {
        return chat.copyWith(title: newTitle);
      }
      return chat;
    }).toList();
    
    if (_currentChat?.id == chatId) {
      _currentChat = _currentChat!.copyWith(title: newTitle);
    }
    _error = null;
    _saveChats();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Оптимизированный метод отправки сообщения через изолированный поток
  Stream<Message> sendMessageStream(String content) async* {
    if (content.trim().isEmpty) return;
    
    if (_currentChat == null) {
      createNewChat();
    }
    
    try {
      // Устанавливаем флаг загрузки
      _isLoading = true;
      notifyListeners();
      
      // Добавляем сообщение пользователя
      final userMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(), 
        content: content, 
        timestamp: DateTime.now(), 
        isUser: true,
      );
      
      // Обновляем ID редактируемого сообщения
      _currentlyEditingMessageId = userMessage.id;
            
      // Добавляем сообщение пользователя в чат
      _currentChat!.messages.add(userMessage);
      notifyListeners();
      yield userMessage;
      
      // Создаем заготовку для ответа бота
      final botMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: '',
        timestamp: DateTime.now(),
        isUser: false,
      );
      
      // Добавляем пустое сообщение бота
      _currentChat!.messages.add(botMessage);
      notifyListeners();
      
      // Обрабатываем запрос в отдельном потоке для освобождения UI-потока
      try {
        // Обертка для сохранения контекста
        final requestParams = _ApiRequestParams(
          userMessage: userMessage.content,
          botMessageId: botMessage.id,
          scope: _scope,
          accessToken: _accessToken,
          apiBaseUrl: _apiBaseUrl,
        );
        
        // Используем compute для запуска в отдельном изолированном потоке
        final response = await compute(_makeApiRequest, requestParams);
        
        // Обновляем сообщение бота с полученным ответом
        final updatedBotMessage = botMessage.copyWith(content: response);
        
        // Находим и заменяем сообщение в чате
        final messageIndex = _currentChat!.messages.indexWhere((m) => m.id == botMessage.id);
        if (messageIndex != -1) {
          _currentChat!.messages[messageIndex] = updatedBotMessage;
        }
        
        // Сохраняем чаты после получения ответа
        await _saveChats();
        
        yield updatedBotMessage;
      } catch (e) {
        // В случае ошибки API, обновляем сообщение бота
        debugPrint('Ошибка при запросе к API: $e');
        
        // Более дружественное сообщение об ошибке
        String errorMessage = 'Извините, произошла ошибка при обработке вашего запроса.';
        
        // Расширенная диагностика ошибки
        if (e.toString().contains('SocketException') || 
            e.toString().contains('Connection refused')) {
          errorMessage = 'Не удалось подключиться к серверу. Проверьте подключение к интернету.';
        } else if (e.toString().contains('timeout')) {
          errorMessage = 'Время ожидания ответа истекло. Сервер не отвечает.';
        } else if (e.toString().contains('401') || e.toString().contains('403')) {
          errorMessage = 'Ошибка авторизации. Возможно, ваш токен устарел.';
        }
        
        // Обновляем сообщение бота с ошибкой
        final errorBotMessage = botMessage.copyWith(content: errorMessage);
        
        // Находим и заменяем сообщение в чате
        final messageIndex = _currentChat!.messages.indexWhere((m) => m.id == botMessage.id);
        if (messageIndex != -1) {
          _currentChat!.messages[messageIndex] = errorBotMessage;
        }
        
        // Попытка повторного получения токена при ошибке авторизации
        if (e.toString().contains('401')) {
          // Сбрасываем токен и инициируем его переполучение
          _accessToken = null;
          _tokenExpiration = null;
          // Токен будет получен при следующем запросе
        }
        
        yield errorBotMessage;
      }
    } catch (e) {
      debugPrint('Ошибка отправки сообщения: $e');
      _error = 'Ошибка: $e';
    } finally {
      // Всегда сбрасываем флаги загрузки и редактирования
      _currentlyEditingMessageId = null;
      _isLoading = false;
      notifyListeners();
      
      // Сохраняем чаты
      _saveChats();
    }
  }
  
  // Выполнение API-запроса в изолированном потоке
  static Future<String> _makeApiRequest(_ApiRequestParams params) async {
    try {
      // Здесь выполняем запрос к API GigaChat с параметрами
      final client = http.Client();
      final request = http.Request('POST', Uri.parse('${params.apiBaseUrl}/chat/completions'));
      
      // Установка заголовков
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'application/json';
      request.headers['Authorization'] = 'Bearer ${params.accessToken}';
      
      // Подготовка тела запроса
      final messages = [
        {'role': 'user', 'content': params.userMessage}
      ];
      
      request.body = jsonEncode({
        'model': 'GigaChat:latest',
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 1500,
        'stream': false, // Для первого MVP без стриминга
      });
      
      // Отправка запроса с таймаутом
      final streamedResponse = await client.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          client.close();
          throw TimeoutError('Время ожидания запроса истекло');
        },
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        // Успешный ответ
        final responseBody = jsonDecode(response.body);
        final choice = responseBody['choices'][0];
        final content = choice['message']['content'];
        
        return content;
      } else {
        // Обработка ошибок API
        throw Exception('API вернул код ошибки: ${response.statusCode}, тело: ${response.body}');
      }
    } catch (e) {
      // Перехватываем ошибки и прокидываем их наверх
      return 'Произошла ошибка при обработке запроса: $e';
    }
  }

  // Метод для очистки кеша старых разговоров для повышения производительности
  Future<void> clearOldChats() async {
    // Оставляем только 5 последних чатов для оптимизации работы
    if (_chats.length > 5) {
      // Сортируем по дате создания (от новых к старым)
      _chats.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      // Оставляем только первые 5 чатов
      _chats = _chats.sublist(0, 5);
      
      // Сохраняем обновленный список
      await _saveChats();
      notifyListeners();
    }
  }

  // Метод для обновления названия чата на основе контекста
  void _updateChatTitleFromContext(Chat chat) {
    if (chat.messages.isEmpty || chat.title != 'Новый чат') {
      return;
    }
    
    final userMessage = chat.messages.firstWhere((m) => m.isUser, orElse: () => chat.messages.first);
    String userText = userMessage.content.trim();
    
    // Ограничиваем длину названия
    const maxTitleLength = 30;
    
    // Обрезаем до первого предложения или до нужной длины
    final endOfSentence = userText.indexOf('.');
    if (endOfSentence != -1 && endOfSentence < maxTitleLength) {
      userText = userText.substring(0, endOfSentence + 1);
    } else if (userText.length > maxTitleLength) {
      userText = '${userText.substring(0, maxTitleLength)}...';
    }
    
    // Обновляем название
    updateChatTitle(chat.id, userText);
  }

  // Метод для обновления названия чата по первому сообщению, вызываемый по запросу
  void updateChatTitleFromContent(String chatId) {
    final chat = _chats.firstWhere((c) => c.id == chatId);
    _updateChatTitleFromContext(chat);
  }

  // Метод для редактирования сообщения пользователя
  Future<void> editUserMessage(String messageId, String newContent) async {
    if (_currentChat == null) return;
    
    // Если уже идет редактирование этого или другого сообщения - блокируем
    if (_currentlyEditingMessageId != null) {
      _error = 'Редактирование недоступно. Дождитесь завершения текущей операции.';
      notifyListeners();
      return;
    }
    
    // Устанавливаем флаг редактирования
    _currentlyEditingMessageId = messageId;
    
    try {
      // Находим индекс сообщения по ID
      final index = _currentChat!.messages.indexWhere((m) => m.id == messageId);
      if (index == -1) {
        _currentlyEditingMessageId = null;
        return;
      }
      
      final oldMessage = _currentChat!.messages[index];
      
      // Убедимся, что это сообщение пользователя
      if (!oldMessage.isUser) {
        _currentlyEditingMessageId = null;
        return;
      }
      
      // Создаем обновленное сообщение
      final updatedMessage = oldMessage.copyWith(
        content: newContent,
        // Обновляем временную метку, чтобы показать, что сообщение было отредактировано
        timestamp: DateTime.now(),
      );
      
      // Обновляем сообщение в текущем чате
      final updatedMessages = List<Message>.from(_currentChat!.messages);
      updatedMessages[index] = updatedMessage;
      
      final updatedChat = _currentChat!.copyWith(
        messages: updatedMessages,
      );
      
      _currentChat = updatedChat;
      _chats = _chats.map((chat) => 
        chat.id == updatedChat.id ? updatedChat : chat
      ).toList();
      
      // Если это было последнее сообщение пользователя, и за ним следует ответ бота,
      // обновляем ответ бота запросом к API
      if (index < _currentChat!.messages.length - 1 && 
          !_currentChat!.messages[index + 1].isUser) {
        
        _isLoading = true;
        notifyListeners();
        
        try {
          // Получаем индекс сообщения бота
          final botMessageIndex = index + 1;
          final oldBotMessage = _currentChat!.messages[botMessageIndex];
          
          // Очищаем содержимое сообщения бота перед обновлением
          final emptyBotMessage = oldBotMessage.copyWith(
            content: '',
            timestamp: DateTime.now(),
          );
          
          final emptyMessages = List<Message>.from(_currentChat!.messages);
          emptyMessages[botMessageIndex] = emptyBotMessage;
          
          final emptyChat = _currentChat!.copyWith(
            messages: emptyMessages,
          );
          
          _currentChat = emptyChat;
          _chats = _chats.map((chat) => 
            chat.id == emptyChat.id ? emptyChat : chat
          ).toList();
          notifyListeners();
          
          // Используем потоковый API вместо обычного запроса
          String accumulatedResponse = '';
          
          try {
            await for (final chunk in _gigaChatService.streamMessage(newContent)) {
              accumulatedResponse += chunk;
              
              // Обновляем сообщение бота с текущим накопленным ответом
              final updatedBotMessage = emptyBotMessage.copyWith(
                content: accumulatedResponse,
              );
              
              final newMessages = List<Message>.from(_currentChat!.messages);
              newMessages[botMessageIndex] = updatedBotMessage;
              
              final newChat = _currentChat!.copyWith(
                messages: newMessages,
              );
              
              _currentChat = newChat;
              _chats = _chats.map((chat) => 
                chat.id == newChat.id ? newChat : chat
              ).toList();
              notifyListeners();
            }
          } catch (streamError) {
            print('Ошибка при использовании потокового API: $streamError');
            // Если потоковый API не сработал, пробуем обычный
            final response = await _gigaChatService.sendMessage(newContent);
            
            // Обновляем ответ бота
            final updatedBotMessage = oldBotMessage.copyWith(
              content: response,
              timestamp: DateTime.now(),
            );
            
            final newMessages = List<Message>.from(_currentChat!.messages);
            newMessages[botMessageIndex] = updatedBotMessage;
            
            final newChat = _currentChat!.copyWith(
              messages: newMessages,
            );
            
            _currentChat = newChat;
            _chats = _chats.map((chat) => 
              chat.id == newChat.id ? newChat : chat
            ).toList();
          }
        } catch (e) {
          if (e is GigaChatException) {
            _error = e.toString();
          } else {
            _error = 'Произошла ошибка при обновлении ответа: $e';
          }
        } finally {
          _isLoading = false;
        }
      }
      
      _saveChats();
      notifyListeners();
    } finally {
      // В любом случае снимаем блокировку
      _currentlyEditingMessageId = null;
    }
  }

  // Метод для полной очистки всех чатов
  Future<void> clearAllChats() async {
    _chats.clear();
    _currentChat = null;
    notifyListeners();
    await _saveChats();
  }
}

// Структура для передачи параметров в изолированный поток
class _ApiRequestParams {
  final String userMessage;
  final String botMessageId;
  final String scope;
  final String? accessToken;
  final String apiBaseUrl;
  
  _ApiRequestParams({
    required this.userMessage,
    required this.botMessageId,
    required this.scope,
    required this.accessToken,
    required this.apiBaseUrl,
  });
}

// Ошибка таймаута
class TimeoutError extends Error {
  final String message;
  
  TimeoutError(this.message);
  
  @override
  String toString() => message;
} 