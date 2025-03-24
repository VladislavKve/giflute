import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/chat_screen.dart';
import 'providers/chat_provider.dart';
import 'providers/theme_provider.dart';
import 'config/app_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Инициализируем провайдеры
  _initializeProviders();
  // Загружаем необходимые ресурсы асинхронно для ускорения запуска
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(
          value: _ChatProviderHolder.chatProvider,
        ),
      ],
      child: Consumer2<ChatProvider, ThemeProvider>(
        builder: (context, chatProvider, themeProvider, child) {
          if (!chatProvider.isInitialized) {
            return MaterialApp(
              themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
                textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
              ),
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: Brightness.light,
                ),
                useMaterial3: true,
                textTheme: GoogleFonts.interTextTheme(),
              ),
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      if (chatProvider.error != null)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            chatProvider.error!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      // Предупреждение для веб-версии
                      if (kIsWeb) 
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Text(
                                'Внимание! В веб-версии могут быть проблемы с подключением к API из-за CORS-ограничений.',
                                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Рекомендуется использовать мобильную или десктопную версию для полноценной работы.',
                                style: TextStyle(color: Colors.orange),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }

          return MaterialApp(
            title: 'GigaChat Flutter',
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              textTheme: GoogleFonts.interTextTheme(),
              appBarTheme: const AppBarTheme(
                systemOverlayStyle: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.dark,
                ),
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
              appBarTheme: const AppBarTheme(
                systemOverlayStyle: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                ),
              ),
            ),
            home: Stack(
              children: [
                const ChatScreen(),
                // Показываем предупреждение для веб-версии
                if (kIsWeb)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.orange.withOpacity(0.9),
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: const Text(
                        'Веб-версия: возможны ограничения CORS. Для полноценной работы используйте мобильную версию.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChatProviderHolder {
  static final ChatProvider chatProvider = ChatProvider(
    clientId: AppConfig.clientId,
    scope: AppConfig.scope,
    apiBaseUrl: AppConfig.apiUrl,
  );

  _ChatProviderHolder._();

  static void initialize() {
    // После инициализации очищаем старые чаты
    WidgetsBinding.instance.addPostFrameCallback((_) {
      chatProvider.clearOldChats();
    });
  }
}

// Инициализируем провайдеры при старте приложения
void _initializeProviders() {
  _ChatProviderHolder.initialize();
} 