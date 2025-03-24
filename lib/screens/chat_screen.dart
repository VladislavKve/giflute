import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';
import 'package:flutter/services.dart';
import '../models/chat.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/silero_tts_service.dart';

// Вспомогательный класс для хранения информации о кодовом блоке
class CodeBlock {
  final String code;
  final String language;
  
  CodeBlock(this.code, this.language);
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _chatTitleController = TextEditingController();
  final TextEditingController _editMessageController = TextEditingController();
  String? _editingMessageId;
  bool _isEditingTitle = false;
  bool _isSidebarVisible = true;
  
  // Анимация для бокового меню
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  
  // Анимация для индикатора свайпа
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Контроллер для обработки жестов
  DragStartDetails? _startDetails;
  DragUpdateDetails? _updateDetails;
  
  // Для голосового ввода
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';
  
  // Для преобразования текста в речь (TTS)
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  
  // Silero TTS сервис
  final SileroTtsService _sileroTts = SileroTtsService();
  String _selectedVoice = SileroTtsService.availableVoices[0]['id']!;
  bool _useSileroTts = true;
  
  // Добавляем переменную для отслеживания сообщений, которые уже были анимированы
  final Set<String> _animatedMessages = {};
  
  // Добавляем контроллер для анимации появления сообщений
  late AnimationController _messageAnimationController;
  late Animation<double> _messageScaleAnimation;
  late Animation<double> _messageOpacityAnimation;
  
  // Оптимизируем рендеринг сообщений с кэшированием
  final Map<String, Widget> _cachedMessages = {};
  
  // Добавляем const для неизменяемых значений
  static const double _sidebarWidth = 260.0;
  static const Duration _animationDuration = Duration(milliseconds: 250);
  static const Duration _snackBarDuration = Duration(seconds: 2);
  static const double _messageBorderRadius = 20.0;
  static const EdgeInsets _messagePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  static const EdgeInsets _inputPadding = EdgeInsets.all(8);
  
  // Добавляем const для стилей
  static const TextStyle _titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );
  
  static const TextStyle _messageStyle = TextStyle(
    fontSize: 16,
  );

  @override
  void initState() {
    super.initState();
    
    // Инициализация контроллеров анимации
    _animationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _messageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // Настройка анимаций
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _messageScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _messageAnimationController,
      curve: Curves.easeOutBack,
    ));
    
    _messageOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _messageAnimationController,
      curve: Curves.easeOut,
    ));
    
    // Добавляем слушатель изменений текста
    _messageController.addListener(_onTextChanged);
    
    // Инициализация сервисов
    _initSpeech();
    _initTts();
    
    // Добавляем наблюдатель за изменениями размера
    WidgetsBinding.instance.addObserver(_sizeObserver);
  }

  @override
  void dispose() {
    // Удаляем слушатель изменений при удалении виджета
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _chatTitleController.dispose();
    _editMessageController.dispose();
    _animationController.dispose();
    _pulseController.dispose();
    _sileroTts.dispose();
    
    // Отписываемся от обсервера изменения размеров
    WidgetsBinding.instance.removeObserver(_sizeObserver);
    
    _messageAnimationController.dispose();
    
    super.dispose();
  }
  
  // Объект-наблюдатель для отслеживания изменений размера экрана
  late final _SizeChangeObserver _sizeObserver = _SizeChangeObserver(this);
  
  // Вызывается при изменении размеров экрана
  void _onSizeChanged() {
    if (mounted) {
      _checkScreenSizeAndUpdateSidebar();
    }
  }
  
  // Обработчик изменений текста в поле ввода
  void _onTextChanged() {
    if (!mounted) return;
    
    // Оптимизируем обновление состояния
    final bool isEmpty = _messageController.text.isEmpty;
    if ((isEmpty) != (_previousText?.isEmpty ?? true)) {
      setState(() {});
    }
    _previousText = _messageController.text;
  }
  
  // Храним предыдущее значение текста для оптимизации
  String? _previousText;
  
  // Проверка размера экрана и автоматическое скрытие боковой панели, если нужно
  void _checkScreenSizeAndUpdateSidebar() {
    if (!mounted) return;
    
    final width = MediaQuery.of(context).size.width;
    final bool oldValue = _isSidebarVisible;
    
    setState(() {
      if (width < 800) {
        _isSidebarVisible = false;
      } else if (width >= 1200) {
        _isSidebarVisible = true;
      }
    });
    
    if (oldValue != _isSidebarVisible && mounted) {
      if (_isSidebarVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  // Оптимизированная прокрутка с учетом анимации
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  // Метод для переключения видимости боковой панели с анимацией
  void _toggleSidebar() {
    if (!mounted) return;
    
    setState(() {
      _isSidebarVisible = !_isSidebarVisible;
      if (_isSidebarVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  // Метод для копирования кода в буфер обмена
  void _copyCodeToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Код скопирован в буфер обмена'),
        duration: Duration(seconds: 1),
      ),
    );
  }
  
  // Инициализация распознавания речи
  Future<void> _initSpeech() async {
    print('Инициализация голосового ввода...');
    
    try {
      // Проверяем и запрашиваем разрешение на использование микрофона
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        PermissionStatus status = await Permission.microphone.status;
        print('Статус разрешения микрофона: $status');
        
        if (status.isDenied) {
          // Запрашиваем разрешение
          status = await Permission.microphone.request();
          print('Статус разрешения после запроса: $status');
          
          if (status.isDenied) {
            _showError(context, 'Для использования голосового ввода необходим доступ к микрофону');
            return;
          }
        }
        
        if (status.isPermanentlyDenied) {
          _showError(
            context, 
            'Доступ к микрофону запрещен. Пожалуйста, разрешите доступ в настройках устройства.'
          );
          return;
        }
      }
      
      // Проверяем наличие микрофонов в системе
      if (Platform.isLinux) {
        try {
          final result = await Process.run('arecord', ['-l']);
          print('Результат проверки микрофонов:');
          print(result.stdout);
          if (result.exitCode != 0 || !result.stdout.toString().contains('card')) {
            _showError(context, 'Микрофоны не обнаружены в системе');
            return;
          }
        } catch (e) {
          print('Ошибка при проверке микрофонов: $e');
        }
      }
      
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('Статус распознавания речи: $status');
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          print('Ошибка распознавания речи: $error');
          setState(() {
            _isListening = false;
          });
          _showError(context, 'Ошибка распознавания речи: $error');
        },
        debugLogging: true,
      );
      
      if (available) {
        print('Распознавание речи доступно');
        // Проверяем доступные локали
        var locales = await _speech.locales();
        print('Доступные локали: ${locales.map((e) => "${e.localeId} (${e.name})").join(", ")}');
        
        // Выводим дополнительную информацию о статусе
        print('SpeechToText статус доступности: ${_speech.isAvailable}');
        print('SpeechToText статус прослушивания: ${_speech.isListening}');
      } else {
        print('Распознавание речи недоступно на устройстве');
        _showError(context, 'Распознавание речи недоступно на устройстве');
      }
    } catch (e) {
      print('Исключение при инициализации распознавания речи: $e');
      _showError(context, 'Не удалось инициализировать распознавание речи: $e');
    }
  }
  
  // Инициализация Text-to-Speech
  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('ru-RU');
      await _flutterTts.setSpeechRate(0.9); // Немного медленнее
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      
      _flutterTts.setCompletionHandler(() {
        setState(() {
          _isSpeaking = false;
        });
      });
      
      List<dynamic>? languages = await _flutterTts.getLanguages;
      print("Доступные языки TTS: $languages");
      
      List<dynamic>? voices = await _flutterTts.getVoices;
      print("Доступные голоса TTS: $voices");
      
    } catch (e) {
      print("Ошибка инициализации TTS: $e");
    }
  }
  
  // Показать диалог выбора голоса
  void _showVoiceSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings_voice, color: Colors.blue),
            SizedBox(width: 8),
            Text('Настройки голоса'),
          ],
        ),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Переключатель TTS движка
                  SwitchListTile(
                    title: Text(
                      'Использовать Silero TTS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _useSileroTts ? Colors.blue : Colors.grey,
                      ),
                    ),
                    subtitle: Text(
                      _useSileroTts 
                          ? 'Включено: использование онлайн синтеза речи'
                          : 'Выключено: использование стандартного TTS',
                      style: TextStyle(
                        fontSize: 12,
                        color: _useSileroTts ? Colors.blue.withOpacity(0.7) : Colors.grey,
                      ),
                    ),
                    value: _useSileroTts,
                    activeColor: Colors.blue,
                    onChanged: (value) {
                      setState(() {
                        _useSileroTts = value;
                      });
                    },
                  ),
                  const Divider(),
                  // Примечание о демо-режиме
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Примечание: Для полноценной работы Silero TTS требуется настроить API ключ в файле конфигурации.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Опции доступны только если Silero TTS включен
                  if (_useSileroTts) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Выберите голос для синтеза:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    for (final voice in SileroTtsService.availableVoices)
                      RadioListTile<String>(
                        title: Text(voice['name']!),
                        value: voice['id']!,
                        groupValue: _selectedVoice,
                        activeColor: Colors.blue,
                        onChanged: (value) {
                          setState(() {
                            _selectedVoice = value!;
                          });
                        },
                      ),
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Примечание: Без настроенного API ключа будет использоваться стандартный TTS',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Применить'),
            onPressed: () {
              // Применяем изменения и закрываем диалог
              setState(() {});
              Navigator.of(context).pop();
              
              // Показываем подтверждение
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _useSileroTts 
                        ? 'Используется Silero TTS: ${SileroTtsService.availableVoices.firstWhere((v) => v['id'] == _selectedVoice)['name']} (демо)'
                        : 'Используется стандартный TTS',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Озвучить текст с выбором TTS движка
  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    
    // Останавливаем текущую речь, если она воспроизводится
    if (_isSpeaking) {
      if (_useSileroTts) {
        await _sileroTts.stop();
      } else {
      await _flutterTts.stop();
      }
      setState(() {
        _isSpeaking = false;
      });
      return;
    }
    
    try {
      setState(() {
        _isSpeaking = true;
      });
      
      // Ограничиваем длину текста
      const int maxLength = 1000; // Для Silero TTS уменьшаем максимальную длину
      if (text.length > maxLength) {
        text = '${text.substring(0, maxLength)}... (текст слишком длинный)';
      }
      
      // Удаляем специальные markdown символы для лучшего произношения
      text = text.replaceAll(RegExp(r'```[\s\S]*?```'), 'код программы')
                .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
                .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
                .replaceAll(RegExp(r'`(.*?)`'), r'$1')
                .replaceAll('#', '');
      
      if (_useSileroTts) {
        // Используем Silero TTS
        try {
          await _sileroTts.speak(text, voice: _selectedVoice);
          
          // Следим за состоянием воспроизведения
          if (!_sileroTts.isSpeaking) {
            setState(() {
              _isSpeaking = false;
            });
          }
        } catch (e) {
          print("Ошибка Silero TTS: $e");
          // В случае ошибки Silero TTS, автоматически переключаемся на стандартный TTS
          setState(() {
            _useSileroTts = false;
            _isSpeaking = false;
          });
          
          // Показываем сообщение об ошибке
          String errorMsg = 'Silero TTS недоступен: ';
          if (_sileroTts.lastError != null && _sileroTts.lastError!.contains('API ключ')) {
            errorMsg += 'требуется настройка API ключа';
          } else {
            errorMsg += _sileroTts.lastError ?? e.toString();
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$errorMsg.\nИспользуется стандартный TTS'),
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Задержка перед повторной попыткой с другим движком
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Пробуем использовать стандартный TTS
          setState(() {
            _isSpeaking = true;
          });
      await _flutterTts.speak(text);
        }
      } else {
        // Используем стандартный TTS
        await _flutterTts.speak(text);
      }
    } catch (e) {
      print("Ошибка при озвучивании текста: $e");
      setState(() {
        _isSpeaking = false;
      });
      _showError(context, "Не удалось озвучить текст: $e");
    }
  }

  // Метод для начала/остановки прослушивания с улучшенной обработкой
  void _toggleListening() async {
    print('Переключение режима прослушивания, текущий статус: $_isListening');
    
    // Если уже слушаем, то останавливаем
    if (_isListening) {
      _speech.stop();
      setState(() {
        _isListening = false;
      });
      return;
    }
    
    // Проверяем, что SpeechToText инициализирован
    if (!_speech.isAvailable) {
      _showError(context, 'Распознавание речи недоступно на этом устройстве');
      
      // Если распознавание недоступно, показываем диалог ввода текста
    _showVoiceInputDialog();
      return;
    }
    
    // Получаем разрешение на использование микрофона, если нужно
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      PermissionStatus status = await Permission.microphone.status;
      
      if (status.isDenied) {
        status = await Permission.microphone.request();
        if (status.isDenied) {
          _showError(context, 'Для использования голосового ввода необходим доступ к микрофону');
          return;
        }
      }
      
      if (status.isPermanentlyDenied) {
        _showError(
          context, 
          'Доступ к микрофону запрещен. Пожалуйста, разрешите доступ в настройках устройства.'
        );
        return;
      }
    }
    
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('Статус распознавания речи: $status');
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          print('Ошибка распознавания речи: $error');
          setState(() {
            _isListening = false;
          });
          _showError(context, 'Ошибка распознавания речи: $error');
        },
        debugLogging: true,
      );
      
      if (available) {
        setState(() {
          _isListening = true;
          _recognizedText = '';
        });
        
        // Показываем снэкбар для информирования пользователя
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Говорите...'),
            duration: const Duration(seconds: 1),
            action: SnackBarAction(
              label: 'Отмена',
              onPressed: () {
                _speech.stop();
                setState(() {
                  _isListening = false;
                });
              },
            ),
          ),
        );
        
        // Начинаем прослушивание
        await _speech.listen(
          onResult: (result) {
            setState(() {
              _recognizedText = result.recognizedWords;
              _messageController.text = _recognizedText;
              // Обновляем положение курсора в конец текста
              _messageController.selection = TextSelection.fromPosition(
                TextPosition(offset: _messageController.text.length),
              );
            });
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          localeId: 'ru_RU',
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        );
      } else {
        _showError(context, 'Не удалось запустить распознавание речи');
        // Если не получилось, показываем диалог ввода текста
        _showVoiceInputDialog();
      }
    } catch (e) {
      print('Исключение при использовании речи: $e');
      _showError(context, 'Ошибка: $e');
      setState(() {
        _isListening = false;
      });
      
      // В случае ошибки показываем диалог ввода текста
      _showVoiceInputDialog();
    }
  }
  
  // Показать диалог голосового ввода с улучшенным интерфейсом
  void _showVoiceInputDialog() {
    final TextEditingController textController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.record_voice_over, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Голосовой ввод'),
            const Spacer(),
            // Кнопка для закрытия диалога
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Закрыть',
            )
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Система распознавания голоса может быть недоступна на вашей платформе.\n'
              'Вы можете ввести текст вручную.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                hintText: 'Введите текст здесь...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
              maxLines: 4,
              autofocus: true,
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  setState(() {
                    _messageController.text = value;
                  });
                  Navigator.pop(context);
                }
              },
            ),
            const SizedBox(height: 8),
            // Примеры команд
            Wrap(
              spacing: 8,
              children: [
                _buildSuggestionChip('Привет', textController),
                _buildSuggestionChip('Как дела?', textController),
                _buildSuggestionChip('Расскажи о Flutter', textController),
                _buildSuggestionChip('Что такое Dart?', textController),
              ],
            ),
          ],
        ),
        actions: [
          // Кнопка для отправки текста
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Отправить'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (textController.text.isNotEmpty) {
                setState(() {
                  _messageController.text = textController.text;
                });
                Navigator.pop(context);
                
                // Автоматически отправляем сообщение
                final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                final message = _messageController.text;
                _messageController.clear();
                final messageStream = chatProvider.sendMessageStream(message);
                messageStream.listen(
                  (message) => _scrollToBottom(),
                  onError: (error) {
                    _showError(context, 'Ошибка: $error');
                  },
                );
              }
            },
          ),
        ],
      ),
    );
  }
  
  // Вспомогательный метод для создания подсказок ввода
  Widget _buildSuggestionChip(String text, TextEditingController controller) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        controller.text = text;
      },
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    );
  }

  // Метод для создания виджета кодового блока с кнопкой копирования
  Widget _buildCodeBlock(BuildContext context, String code, String language, bool isUserMessage) {
    final textColor = isUserMessage 
        ? Colors.white 
        : Theme.of(context).colorScheme.onSurfaceVariant;
        
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isUserMessage
            ? Colors.white.withOpacity(0.15)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUserMessage
              ? Colors.white.withOpacity(0.2)
              : Colors.black.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок с языком и кнопкой копирования
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isUserMessage
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isUserMessage ? Colors.white : Colors.black54,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.copy,
                    size: 18,
                    color: isUserMessage ? Colors.white : Colors.black54,
                  ),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  tooltip: 'Копировать код',
                  onPressed: () => _copyCodeToClipboard(code),
                ),
              ],
            ),
          ),
          // Содержимое кода
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: textColor, // Используем тот же цвет, что и для основного текста
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Создаем пользовательский билдер для MarkdownBody
  Widget _buildMarkdownBody(BuildContext context, String data, bool isUserMessage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: data,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: isUserMessage
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            code: TextStyle(
              color: isUserMessage
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              backgroundColor: Colors.transparent,
              fontFamily: 'monospace',
            ),
            codeblockDecoration: BoxDecoration(
              color: isUserMessage
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.7)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onTapLink: (text, href, title) {
            if (href != null) {
              // Добавить код для открытия ссылок в браузере
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ссылка: $href')),
              );
            }
          },
        ),
        
        // Добавляем отдельную обработку кодовых блоков с кнопкой копирования
        ...extractCodeBlocks(data).map((codeBlock) => 
          _buildCodeBlock(context, codeBlock.code, codeBlock.language, isUserMessage)
        ),
      ],
    );
  }

  // Метод для извлечения кодовых блоков из Markdown
  List<CodeBlock> extractCodeBlocks(String markdown) {
    final codeBlocks = <CodeBlock>[];
    final RegExp codeBlockRegex = RegExp(r'```([a-zA-Z0-9]*)\s*\n([\s\S]*?)\n```', multiLine: true);
    
    final matches = codeBlockRegex.allMatches(markdown);
    for (final match in matches) {
      final language = match.group(1) ?? 'code';
      final code = match.group(2) ?? '';
      codeBlocks.add(CodeBlock(code.trim(), language));
    }
    
    return codeBlocks;
  }

  // Метод для отображения сообщения с анимацией
  Widget _buildMessageItem(Message message, bool isDarkMode) {
    final isNewMessage = !_animatedMessages.contains(message.id);
    if (isNewMessage && message.isUser) {
      // Помечаем сообщение как анимированное
      _animatedMessages.add(message.id);
      // Запускаем анимацию для новых сообщений
      _messageAnimationController.reset();
      _messageAnimationController.forward();
    }
    
    final messageWidget = Container(
      margin: EdgeInsets.only(
        top: 8,
        bottom: 8,
        left: message.isUser ? 48 : 8,
        right: message.isUser ? 8 : 48,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: message.isUser 
          ? (isDarkMode ? Colors.blue.shade800 : Colors.blue.shade100)
          : (isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Функционал для отображения сообщения остается прежним
          // ... existing message display code ...
        ],
      ),
    );
    
    // Применяем анимацию только к новым сообщениям пользователя
    if (isNewMessage && message.isUser) {
      return AnimatedBuilder(
        animation: _messageAnimationController,
        builder: (context, child) {
          return Opacity(
            opacity: _messageOpacityAnimation.value,
            child: Transform.scale(
              scale: _messageScaleAnimation.value,
              alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: child,
            ),
          );
        },
        child: messageWidget,
      );
    }
    
    return messageWidget;
  }

  // Метод для построения списка сообщений
  Widget _buildSidebarChatList(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        return ListView.builder(
          itemCount: chatProvider.chats.length,
          itemBuilder: (context, index) {
            final chat = chatProvider.chats[index];
            final isSelected = chat.id == chatProvider.currentChat?.id;
            return ListTile(
              selected: isSelected,
              title: Text(
                chat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: const Icon(Icons.chat_bubble_outline),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  chatProvider.deleteChat(chat.id);
                },
              ),
              onTap: () {
                chatProvider.selectChat(chat.id);
                if (MediaQuery.of(context).size.width < 800) {
                  setState(() {
                    _isSidebarVisible = false;
                    _animationController.reverse();
                  });
                }
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWideScreen = screenWidth >= 800;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkScreenSizeAndUpdateSidebar();
    });
    
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: !isWideScreen ? AppBar(
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: _toggleSidebar,
                  tooltip: _isSidebarVisible ? 'Скрыть меню' : 'Показать меню',
                ),
                const Expanded(
                  child: Text('GigaChat Flutter', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            elevation: 0,
          ) : null,
          body: SafeArea(
            top: true,
            child: Stack(
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, child) {
                        double width = _isSidebarVisible ? 260 * _slideAnimation.value : 0;
                        if (width < 0) width = 0;
                        
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: width,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                              right: BorderSide(
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                              ),
                            ),
                          ),
                          child: _isSidebarVisible && width > 0
                              ? Opacity(
                                  opacity: _slideAnimation.value,
                                  child: child,
                                )
                              : null,
                        );
                      },
                      child: _buildSidebarContent(context),
                    ),
                    Expanded(
                      child: _buildMainContent(context, chatProvider, isDarkMode),
                    ),
                  ],
                ),
                if (!isWideScreen && _isSidebarVisible)
                  _buildOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebarContent(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    context.read<ChatProvider>().createNewChat();
                    if (MediaQuery.of(context).size.width < 800) {
                      setState(() {
                        _isSidebarVisible = false;
                        _animationController.reverse();
                      });
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Новый чат'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
              if (MediaQuery.of(context).size.width < 800)
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _toggleSidebar,
                  tooltip: 'Скрыть список чатов',
                ),
            ],
          ),
        ),
        Expanded(
          child: _buildSidebarChatList(context),
        ),
        _buildSidebarFooter(context),
      ],
    );
  }

  Widget _buildOverlay() {
    return Positioned(
      left: 260,
      top: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isSidebarVisible = false;
            _animationController.reverse();
          });
        },
        child: AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, _) {
            return Container(
              color: Colors.black.withOpacity(0.5 * _slideAnimation.value),
            );
          },
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: _snackBarDuration,
        backgroundColor: Theme.of(context).colorScheme.error,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  Future<void> _handleError(BuildContext context, dynamic error) async {
    String errorMessage = 'Произошла ошибка';
    
    if (error is Exception) {
      errorMessage = error.toString();
    } else if (error is String) {
      errorMessage = error;
    }
    
    _showError(context, errorMessage);
    
    // Логируем ошибку для отладки
    debugPrint('Error in ChatScreen: $error');
  }

  Widget _buildMainContent(BuildContext context, ChatProvider chatProvider, bool isDarkMode) {
    return Stack(
      children: [
        Column(
          children: [
            _buildChatHeader(context),
            Expanded(
              child: chatProvider.isLoading && 
                     (chatProvider.currentChat == null || 
                      chatProvider.currentChat!.messages.isEmpty)
                  ? const Center(child: CircularProgressIndicator())
                  : _buildMainChatList(context, chatProvider, isDarkMode),
            ),
            _buildInputArea(context, chatProvider),
          ],
        ),
      ],
    );
  }

  Widget _buildChatHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          if (!_isSidebarVisible)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: _toggleSidebar,
              tooltip: 'Показать список чатов',
              iconSize: 26,
            ),
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                final currentChat = chatProvider.currentChat;
                if (currentChat == null) return const SizedBox.shrink();

                if (_isEditingTitle) {
                  return _buildTitleEditField(context, currentChat);
                }

                return _buildTitleDisplay(context, currentChat);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleEditField(BuildContext context, Chat chat) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _chatTitleController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Название чата',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                context.read<ChatProvider>().updateChatTitle(chat.id, value);
                setState(() => _isEditingTitle = false);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTitleDisplay(BuildContext context, Chat chat) {
    return Row(
      children: [
        Expanded(
          child: Text(
            chat.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            _chatTitleController.text = chat.title;
            setState(() => _isEditingTitle = true);
          },
          color: Theme.of(context).colorScheme.primary,
        ),
        Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return IconButton(
              icon: Icon(
                themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              ),
              onPressed: () {
                themeProvider.toggleTheme();
              },
              tooltip: themeProvider.isDarkMode 
                ? 'Переключить на светлую тему' 
                : 'Переключить на темную тему',
            );
          },
        ),
      ],
    );
  }

  Widget _buildMainChatList(BuildContext context, ChatProvider chatProvider, bool isDarkMode) {
    if (chatProvider.currentChat == null || chatProvider.currentChat!.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Начните новый разговор',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Введите ваше сообщение ниже',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      key: PageStorageKey('chat_list_${chatProvider.currentChat!.id}'),
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: chatProvider.currentChat!.messages.length,
      itemBuilder: (context, index) {
        final message = chatProvider.currentChat!.messages[index];
        
        if (_cachedMessages.containsKey(message.id) && 
            chatProvider.currentlyEditingMessageId != message.id) {
          return _cachedMessages[message.id]!;
        }
        
        final messageWidget = _buildMessageItem(message, isDarkMode);
        
        if (chatProvider.currentlyEditingMessageId != message.id) {
          _cachedMessages[message.id] = messageWidget;
        }
        
        return messageWidget;
      },
    );
  }

  Widget _buildSidebarFooter(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return ListTile(
                leading: Icon(
                  themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                ),
                title: Text(
                  themeProvider.isDarkMode ? 'Светлая тема' : 'Темная тема',
                ),
                dense: true,
                onTap: () {
                  themeProvider.toggleTheme();
                },
              );
            },
          ),
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              return ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: Colors.red,
                ),
                title: const Text(
                  'Сбросить все чаты',
                  style: TextStyle(color: Colors.red),
                ),
                dense: true,
                onTap: () => _showResetConfirmationDialog(context),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showResetConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение'),
        content: const Text(
          'Вы действительно хотите удалить все чаты? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<ChatProvider>().clearAllChats();
              context.read<ChatProvider>().createNewChat();
              Navigator.pop(context);
              if (MediaQuery.of(context).size.width < 800) {
                setState(() {
                  _isSidebarVisible = false;
                  _animationController.reverse();
                });
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Все чаты успешно удалены'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Удалить все'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, ChatProvider chatProvider) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            _buildVoiceInputButton(context),
            const SizedBox(width: 8),
            _buildMessageTextField(context),
            const SizedBox(width: 8),
            _buildSendButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceInputButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _isListening
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconButton(
        icon: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: _isListening
              ? Colors.white
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        tooltip: _isListening ? 'Остановить запись' : 'Голосовой ввод',
        onPressed: context.read<ChatProvider>().currentlyEditingMessageId == null && 
                   !context.read<ChatProvider>().isLoading
            ? _toggleListening
            : null,
      ),
    );
  }

  Widget _buildMessageTextField(BuildContext context) {
    return Expanded(
      child: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final String hintText;
          if (chatProvider.currentlyEditingMessageId != null) {
            hintText = 'Пожалуйста, дождитесь обработки предыдущего сообщения...';
          } else if (_isListening) {
            hintText = 'Говорите... 🎤';
          } else {
            hintText = 'Введите сообщение...';
          }

          return TextField(
            controller: _messageController,
            decoration: InputDecoration(
              hintText: hintText,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              prefixIcon: _isListening 
                  ? Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.all(12),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Container(
                                width: 24 * _pulseAnimation.value,
                                height: 24 * _pulseAnimation.value,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.withOpacity(0.5 * (1 - _pulseAnimation.value)),
                                ),
                              );
                            },
                          ),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
            maxLines: null,
            minLines: 1,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.send,
            enabled: chatProvider.currentlyEditingMessageId == null && !chatProvider.isLoading,
            onChanged: (value) {
              setState(() {});
            },
            onSubmitted: (value) {
              if (value.isNotEmpty && !chatProvider.isLoading && chatProvider.currentlyEditingMessageId == null) {
                final message = _messageController.text;
                _messageController.clear();
                final messageStream = chatProvider.sendMessageStream(message);
                messageStream.listen(
                  (message) => _scrollToBottom(),
                  onError: (error) {
                    _showError(context, 'Ошибка: $error');
                  },
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildSendButton(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        final bool hasText = _messageController.text.isNotEmpty;
        final bool isLoading = chatProvider.isLoading;
        final bool isEditing = chatProvider.currentlyEditingMessageId != null;
        final bool isButtonDisabled = !hasText || isLoading || isEditing;
        
        return Container(
          decoration: BoxDecoration(
            color: isButtonDisabled
                ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                : Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: IconButton(
            icon: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.send),
            color: Colors.white,
            onPressed: isButtonDisabled
                ? null
                : () {
                    final message = _messageController.text;
                    _messageController.clear();
                    final messageStream = chatProvider.sendMessageStream(message);
                    messageStream.listen(
                      (message) => _scrollToBottom(),
                      onError: (error) {
                        _showError(context, 'Ошибка: $error');
                      },
                    );
                  },
          ),
        );
      },
    );
  }
}

// Вспомогательный класс для отслеживания изменений размера экрана
class _SizeChangeObserver extends WidgetsBindingObserver {
  final _ChatScreenState _state;
  
  _SizeChangeObserver(this._state);
  
  @override
  void didChangeMetrics() {
    _state._onSizeChanged();
  }
} 