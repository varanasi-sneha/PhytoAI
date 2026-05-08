import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_service.dart';
import '../models/models.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isEditing = false;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.getProfile();
      final profile = UserProfile.fromJson(response);

      setState(() {
        _profile = profile;
        _firstNameController.text = profile.firstName ?? '';
        _lastNameController.text = profile.lastName ?? '';
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProfile() async {
    setState(() {
      _isUpdating = true;
    });

    try {
      final apiService = context.read<ApiService>();
      await apiService.updateProfile(
        _firstNameController.text.trim(),
        _lastNameController.text.trim(),
      );

      setState(() {
        _isEditing = false;
        _profile = UserProfile(
          email: _profile!.email,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e')),
      );
    } finally {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadProfile,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _profile == null
                  ? const Center(child: Text('No profile data'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Profile',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(24),

                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),

                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),

                          child: Column(
                            children: [

                              CircleAvatar(
                                radius: 45,
                                backgroundColor:
                                    Colors.green.shade100,

                                child: Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.green.shade700,
                                ),
                              ),

                              const SizedBox(height: 20),

                              Text(
                                '${_profile!.firstName ?? ''} ${_profile!.lastName ?? ''}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 8),

                              Text(
                                _profile!.email,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                ),
                              ),

                              const SizedBox(height: 30),
                                if (_isEditing) ...[
                                  TextField(
                                    controller: _firstNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'First Name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _lastNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Last Name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isUpdating ? null : _updateProfile,
                                          child: _isUpdating
                                              ? const CircularProgressIndicator()
                                              : const Text('Save'),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              _isEditing = false;
                                              _firstNameController.text = _profile!.firstName ?? '';
                                              _lastNameController.text = _profile!.lastName ?? '';
                                            });
                                          },
                                          child: const Text('Cancel'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  ListTile(
                                    title: const Text('Name'),
                                    subtitle: Text(
                                      '${_profile!.firstName ?? 'N/A'} ${_profile!.lastName ?? ''}',
                                    ),
                                    leading: const Icon(Icons.person),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _isEditing = true;
                                      });
                                    },
                                    child: const Text('Edit Profile'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}