import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_service.dart';
import 'app_state.dart';
import 'auth_service.dart';
import 'services/cache_service.dart';
import 'services/compound_classification_service.dart';
import 'services/local_inference_service.dart';
import 'services/network_service.dart';
import 'services/local_profile_service.dart';
import 'services/supabase_history_service.dart';
import 'services/local_history_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://eabarbrhjoptxagcnomy.supabase.co',
    anonKey: 'sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO',
  );

  final cacheService = CacheService();
  await cacheService.init();
  final networkService = NetworkService();
  final localInferenceService = LocalInferenceService(cacheService: cacheService);
  await localInferenceService.initialize();
  final compoundClassificationService = CompoundClassificationService(
    cacheService: cacheService,
    networkService: networkService,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),

        Provider<CacheService>.value(
          value: cacheService,
        ),

        Provider<NetworkService>.value(
          value: networkService,
        ),

        Provider<LocalInferenceService>.value(
          value: localInferenceService,
        ),

        Provider<CompoundClassificationService>.value(
          value: compoundClassificationService,
        ),

        Provider<LocalProfileService>(
          create: (context) => LocalProfileService(cache: cacheService, auth: context.read<AuthService>()),
        ),

        ChangeNotifierProvider<LocalHistoryService>(
          create: (context) => LocalHistoryService(cache: cacheService),
        ),

        Provider<SupabaseHistoryService>(
          create: (context) => SupabaseHistoryService(
            cache: context.read<CacheService>(),
            localHistoryService: context.read<LocalHistoryService>(),
          ),
        ),

        Provider<ApiService>(
          create: (context) => ApiService(
            context.read<AuthService>(),
            context.read<CacheService>(),
            context.read<NetworkService>(),
          ),
        ),

        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(),
        ),
      ],
      child: const PhytoAiApp(),
    ),
  );
}

class PhytoAiApp extends StatelessWidget {
  const PhytoAiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhytoAI - Plant Disease Detection',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1a5d42),
          brightness: Brightness.light,
        ),
        primaryColor: const Color(0xFF1a5d42),
        scaffoldBackgroundColor: const Color(0xFFF5F1ED),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a5d42),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1a5d42),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1a5d42),
            side: const BorderSide(color: Color(0xFF1a5d42)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1a5d42)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8DDD5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1a5d42), width: 2),
          ),
        ),
      ),
      home: const AuthWrapper(),
      routes: {
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  void _checkAuthState() {
    final authService = context.read<AuthService>();
    final appState = context.read<AppState>();

    authService.authStateChanges.listen((authState) {
      final isAuthenticated = authState.session != null;
      appState.setAuthenticated(isAuthenticated);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (appState.isAuthenticated) {
          return const HomeScreen();
        } else {
          return const AuthScreen();
        }
      },
    );
  }
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return appState.authMode == AuthMode.login
            ? const LoginScreen()
            : const SignupScreen();
      },
    );
  }
}
