import 'package:flutter/material.dart';

enum AuthMode { login, signup }

class AppState extends ChangeNotifier {
  AuthMode _authMode = AuthMode.login;
  bool _isAuthenticated = false;

  AuthMode get authMode => _authMode;
  bool get isAuthenticated => _isAuthenticated;

  void showLogin() {
    _authMode = AuthMode.login;
    notifyListeners();
  }

  void showSignup() {
    _authMode = AuthMode.signup;
    notifyListeners();
  }

  void setAuthenticated(bool authenticated) {
    _isAuthenticated = authenticated;
    notifyListeners();
  }
}