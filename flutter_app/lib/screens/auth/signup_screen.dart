import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth_service.dart';
import '../../app_state.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final response = await authService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _firstNameController.text.trim(),
        _lastNameController.text.trim(),
      );

      if (response.user != null) {
        // Navigation will be handled by auth state listener
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully! Please check your email to verify.')),
        );
      } else {
        setState(() {
          _errorMessage = 'Signup failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F3D2E),
              Color(0xFF145A32),
              Color(0xFF1E8449),
            ],
          ),
        ),

        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),

              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),

                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 10,
                    sigmaY: 10,
                  ),

                  child: Container(
                    padding: const EdgeInsets.all(28),

                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [

                          const Icon(
                            Icons.science,
                            size: 72,
                            color: Colors.white,
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'Create Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Join PhytoAI and start analyzing plants smarter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 15,
                            ),
                          ),

                          const SizedBox(height: 32),

                          Row(
                            children: [

                              Expanded(
                                child: _buildField(
                                  controller:
                                      _firstNameController,
                                  hint: 'First Name',
                                  icon: Icons.person_outline,
                                ),
                              ),

                              const SizedBox(width: 14),

                              Expanded(
                                child: _buildField(
                                  controller:
                                      _lastNameController,
                                  hint: 'Last Name',
                                  icon: Icons.person_outline,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          _buildField(
                            controller: _emailController,
                            hint: 'Email',
                            icon: Icons.email_outlined,
                          ),

                          const SizedBox(height: 18),

                          _buildField(
                            controller:
                                _passwordController,
                            hint: 'Password',
                            icon: Icons.lock_outline,
                            obscure: true,
                          ),

                          const SizedBox(height: 18),

                          _buildField(
                            controller:
                                _confirmPasswordController,
                            hint: 'Confirm Password',
                            icon: Icons.lock_reset_outlined,
                            obscure: true,
                          ),

                          const SizedBox(height: 24),

                          if (_errorMessage != null)
                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.all(14),

                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius:
                                    BorderRadius.circular(
                                        16),
                              ),

                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color:
                                      Colors.red.shade900,
                                ),
                              ),
                            ),

                          const SizedBox(height: 22),

                          SizedBox(
                            width: double.infinity,
                            height: 56,

                            child: ElevatedButton(
                              onPressed:
                                  _isLoading
                                      ? null
                                      : _signup,

                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.white,
                                foregroundColor:
                                    Colors.green.shade900,

                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          18),
                                ),
                              ),

                              child: _isLoading
                                  ? const CircularProgressIndicator()
                                  : const Text(
                                      'Create Account',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          TextButton(
                            onPressed: () {
                              context
                                  .read<AppState>()
                                  .showLogin();
                            },

                            child: const Text(
                              'Already have an account? Login',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,

      style: const TextStyle(
        color: Colors.white,
      ),

      decoration: InputDecoration(
        hintText: hint,

        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.7),
        ),

        prefixIcon: Icon(
          icon,
          color: Colors.white,
        ),

        filled: true,
        fillColor: Colors.white.withOpacity(0.12),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}