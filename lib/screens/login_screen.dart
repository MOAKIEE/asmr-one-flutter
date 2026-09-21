import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/player_state.dart';

/// 登录 / 注册页。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isRegister = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = context.watch<AuthState>();

    return Scaffold(
      appBar: AppBar(title: Text(l('auth.login'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 12, 26, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: AppDecor.heroGradient(scheme),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          color: scheme.onPrimary,
                          size: 26,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l('app.name'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.onPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l('library.loginHint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimary.withValues(alpha: 0.85),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: l('auth.username'),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l('auth.usernameRequired')
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l('auth.password'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return l('auth.passwordRequired');
                      }
                      if (_isRegister && v.length < 6) {
                        return l('auth.passwordTooShort');
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(l),
                  ),
                  if (_isRegister) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: l('auth.confirmPassword'),
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                      ),
                      validator: (v) => v != _passwordController.text
                          ? l('auth.passwordMismatch')
                          : null,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: auth.busy ? null : () => _submit(l),
                    child: auth.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(
                            _isRegister ? l('auth.register') : l('auth.login'),
                          ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: auth.busy
                        ? null
                        : () => setState(() {
                            _isRegister = !_isRegister;
                            _error = null;
                          }),
                    child: Text(
                      _isRegister ? l('auth.login') : l('auth.register'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l('settings.aboutText'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(L10n l) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _error = null);

    final auth = context.read<AuthState>();
    final player = context.read<PlayerState>();

    if (_isRegister) {
      final err = await auth.register(
        _nameController.text,
        _passwordController.text,
      );
      if (!mounted) return;
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      setState(() => _isRegister = false);
      _toast(l('auth.loginSuccess'));
      return;
    }

    final ok = await auth.login(_nameController.text, _passwordController.text);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = auth.lastError ?? l('auth.loginFailed'));
      return;
    }
    // 登录后刷新队列中原本无法播放的付费曲目地址。
    await player.refreshTokens();
    if (!mounted) return;
    _toast(l('auth.loginSuccess'));
    Navigator.of(context).maybePop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
