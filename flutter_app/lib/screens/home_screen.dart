import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_service.dart';
import '../app_state.dart';
import '../ml/rdkit_webview_service.dart';
import 'prediction_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'drug_classification_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  @override
  void initState() {
  super.initState();
  // Reset RDKit service so WebView remounts cleanly after hot restart
  RDKitWebViewService.instance.reset();
}
  static const List<Widget> _screens = [
    PredictionScreen(),
    DrugClassificationScreen(),
    HistoryScreen(),
    ProfileScreen(),
  ];

  static const List<String> _titles = [
    'Plant Detection',
    'Drug Classification',
    'History',
    'Profile',
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final authService = context.read<AuthService>();
    final appState = context.read<AppState>();

    await authService.signOut();
    appState.setAuthenticated(false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Hidden RDKit WebView (1×1 px, off-screen) ──────────────────
        // This boots the RDKit.js WASM once and keeps it alive for the
        // entire app session. CompoundFingerprintGenerator talks to it.
        Positioned(
          left: -10,
          top: -10,
          child: RDKitWebViewService.instance.buildHiddenWebView(),
        ),

        // ── Main app Scaffold ───────────────────────────────────────────
        Scaffold(
          backgroundColor: const Color(0xFFF4F7F5),

          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.green.shade700,

            title: Text(
              _titles[_selectedIndex],
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),

            actions: [
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                onPressed: _logout,
              ),
            ],
          ),

          body: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),

          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                ),
              ],
            ),

            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,

              type: BottomNavigationBarType.fixed,

              backgroundColor: Colors.white,

              selectedItemColor: Colors.green.shade700,
              unselectedItemColor: Colors.grey,

              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
              ),

              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.eco),
                  label: 'Detect',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.science),
                  label: 'Drugs',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}