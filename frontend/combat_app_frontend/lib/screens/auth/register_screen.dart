import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/sport_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sports_provider.dart';

/// Two-step registration: (1) the existing account form, (2) a sport
/// picker styled after the Athletes Hub mockup. The chosen sport is sent
/// as a *separate* call to `POST /sports/me/profiles` right after
/// register+login succeed — `POST /auth/register` itself has no sport
/// field (confirmed via openapi.json: `UserCreate` is just
/// email/username/full_name/password/password_confirm).
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

  int _step = 0; // 0 = account form, 1 = sport picker
  String? _selectedSlug;
  bool _submittingSport = false;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  void _goToSportStep() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = 1);
  }

  Future<void> _finishRegistration() async {
    if (_selectedSlug == null) return;

    final success = await ref.read(authProvider.notifier).register(
          email: _emailController.text.trim(),
          username: _usernameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          password: _passwordController.text,
          passwordConfirm: _passwordConfirmController.text,
        );
    if (!success || !mounted) return;

    setState(() => _submittingSport = true);
    final sportOk = await ref.read(sportProfilesProvider.notifier).addSport(_selectedSlug!);
    if (!mounted) return;
    setState(() => _submittingSport = false);

    if (!sportOk) {
      // Account was created successfully either way — don't strand the
      // person here. Let them continue; they can add/fix their sport
      // profile later from the profile screen.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(sportProfilesProvider).errorMessage ??
            'تم إنشاء الحساب، لكن تعذّر حفظ الرياضة. يمكنك إضافتها لاحقًا من ملفك الشخصي.')),
      );
    }
    if (mounted) context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? 'إنشاء حساب' : 'اختر رياضتك'),
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step = 0),
              )
            : null,
      ),
      body: SafeArea(
        child: _step == 0 ? _buildAccountForm(context) : _buildSportPicker(context),
      ),
    );
  }

  Widget _buildAccountForm(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Padding(
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
                style: TextStyle(color: AppTheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _goToSportStep,
              child: const Text('التالي'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSportPicker(BuildContext context) {
    final sportsAsync = ref.watch(sportsListProvider);
    final authState = ref.watch(authProvider);
    final busy = authState.isLoading || _submittingSport;

    return sportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تعذّر تحميل قائمة الرياضات', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(sportsListProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
      data: (sports) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text('ما هي رياضتك؟', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'سنخصص تجربتك بالكامل حسب اختيارك — يمكنك إضافة رياضات أخرى لاحقًا',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                itemCount: sports.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) => _SportCard(
                  sport: sports[index],
                  selected: _selectedSlug == sports[index].slug,
                  onTap: () => setState(() => _selectedSlug = sports[index].slug),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_selectedSlug == null || busy) ? null : _finishRegistration,
              child: busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('إنشاء الحساب'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Card for one sport in the picker grid. Colors/icons for known slugs
/// (combat/football/running) come from [SportAccent]; any other slug the
/// backend returns falls back to a neutral outline style so the picker
/// never crashes or misrepresents an unmapped sport as combat/purple.
class _SportCard extends StatelessWidget {
  final SportModel sport;
  final bool selected;
  final VoidCallback onTap;

  const _SportCard({required this.sport, required this.selected, required this.onTap});

  static const _knownSlugs = {'combat', 'football', 'running'};

  @override
  Widget build(BuildContext context) {
    final known = _knownSlugs.contains(sport.slug);
    final accent = known ? SportAccent.fromKey(sport.slug).color : AppTheme.outline;
    final icon = known ? SportAccent.fromKey(sport.slug).icon : Icons.sports_outlined;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : AppTheme.surfaceLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? accent : AppTheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: accent),
            const SizedBox(height: 10),
            Text(
              sport.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
