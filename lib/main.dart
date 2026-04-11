import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/store_page.dart';
import 'pages/monitor_page.dart';
import 'pages/settings_page.dart';
import 'services/system_monitor.dart';
import 'services/gps_service.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SystemMonitor()),
        ChangeNotifierProvider(create: (_) => GpsService()),
        ChangeNotifierProvider(
          create: (_) => ApiService(
            baseUrl: prefs.getString('api_base_url') ?? 'http://localhost:8002',
          ),
        ),
        ChangeNotifierProvider(create: (_) => SettingsModel(prefs)),
      ],
      child: const IviApp(),
    ),
  );
}

class SettingsModel extends ChangeNotifier {
  final SharedPreferences _prefs;
  late String _apiBaseUrl;

  SettingsModel(this._prefs) {
    _apiBaseUrl = _prefs.getString('api_base_url') ?? 'http://localhost:8002';
  }

  String get apiBaseUrl => _apiBaseUrl;

  Future<void> setApiBaseUrl(String url) async {
    _apiBaseUrl = url;
    await _prefs.setString('api_base_url', url);
    notifyListeners();
  }
}

class IviApp extends StatelessWidget {
  const IviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AGL IVI Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00D4FF),
          secondary: const Color(0xFF00FF88),
          surface: const Color(0xFF12121A),
          error: const Color(0xFFFF4444),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF12121A),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF00D4FF),
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF12121A),
          selectedItemColor: Color(0xFF00D4FF),
          unselectedItemColor: Color(0xFF555566),
          type: BottomNavigationBarType.fixed,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF12121A),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF222233), width: 1),
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFCCCCDD)),
          bodyMedium: TextStyle(color: Color(0xFFAAAAAB)),
          labelLarge: TextStyle(
            color: Color(0xFF00D4FF),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    StorePage(),
    MonitorPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SystemMonitor>().start();
      context.read<GpsService>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.apps_rounded),
            label: 'Store',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_heart_rounded),
            label: 'Monitor',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
