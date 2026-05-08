import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_service.dart';
import '../app_state.dart';
import 'prediction_screen.dart';
import 'history_screen.dart';
import 'prevention_screen.dart';
import 'profile_screen.dart';
import 'drug_classification_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    PredictionScreen(),
    HistoryScreen(),
    PreventionScreen(),
    DrugClassificationScreen(),
    ProfileScreen(),
  ];

  static const List<String> _titles = [
    'Plant Detection',
    'History',
    'Prevention',
    'Drug Classification',
    'Profile',
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _logout() async {
    final authService = context.read<AuthService>();
    final appState = context.read<AppState>();

    await authService.signOut();
    appState.setAuthenticated(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

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
              icon: Icon(Icons.history),
              label: 'History',
            ),

            BottomNavigationBarItem(
              icon: Icon(Icons.health_and_safety),
              label: 'Prevention',
            ),

            BottomNavigationBarItem(
              icon: Icon(Icons.science),
              label: 'Drugs',
            ),

            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}