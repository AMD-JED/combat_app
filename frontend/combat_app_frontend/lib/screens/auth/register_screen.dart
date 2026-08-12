import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  final _usernamePattern = RegExp(r'^[a-zA-Z0-9_]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref.read(authProvider.notifier).register(
          email: _emailController.text.trim(),
          username: _usernameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          password: _passwordController.text,
          passwordConfirm: _passwordConfirmController.text,
        );
    if (success && mounted) context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.length < 2 || value.length > 100) {
                      return 'الاسم يجب أن يكون بين 2 و 100 حرف';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    helperText: 'أحرف إنجليزية وأرقام و _ فقط، بدون مسافات',
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.length < 3 || value.length > 50) {
                      return 'يجب أن يكون بين 3 و 50 حرفًا';
                    }
                    if (!_usernamePattern.hasMatch(value)) {
                      return 'يُسمح فقط بأحرف/أرقام/underscore';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                  validator: (v) {
                    if (v == null || !v.contains('@')) return 'بريد إلكتروني غير صالح';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    helperText: '8 أحرف على الأقل',
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) {
                      return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordConfirmController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                  validator: (v) {
                    if (v != _passwordController.text) {
                      return 'كلمتا المرور غير متطابقتين';
                    }
                    return null;
                  },
                ),
                if (authState.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    authState.errorMessage!,
                    style: const TextStyle(color: AppTheme.primaryRed),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _submit,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('إنشاء الحساب'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
