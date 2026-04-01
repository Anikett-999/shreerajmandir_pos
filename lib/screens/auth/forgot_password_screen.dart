import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
  with WidgetsBindingObserver {
  static const Color _primary = Color(0xFF8C0D20);
  static const Color _background = Color(0xFFFDFBF7);
  static const Color _surface = Colors.white;
  static const Color _onSurface = Color(0xFF1C1C19);
  static const Color _onSurfaceVariant = Color(0xFF594140);
  static const Color _inputBackground = Color(0xFFF7F5F2);

  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  bool _autoRedirectTriggered = false;
  static const int _cooldownSeconds = 30;
  int _secondsLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _emailCtrl.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sent && !_autoRedirectTriggered) {
      _autoRedirectTriggered = true;
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Email is required';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  Future<void> _sendResetLink() async {
    if (_secondsLeft > 0) {
      return;
    }

    final email = _emailCtrl.text.trim();
    final emailError = _validateEmail(email);
    if (emailError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailError), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _loading = true);
    final resetError = await context.read<AuthService>().sendResetEmail(email);
    if (resetError != null) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resetError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_reset_email', email);
      await prefs.setInt('pending_reset_requested_at', DateTime.now().millisecondsSinceEpoch);

      if (!mounted) return;
      setState(() => _sent = true);
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset link sent. Please check inbox/spam folder.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to send reset link. Please verify email and try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: 0.08,
              child: Image.asset(
                'assets/branding/log-bg.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              color: _primary.withValues(alpha: 0.08),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 130),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black, width: 1.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Image.asset('assets/branding/splash_logo.png', fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 430),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.04),
                            blurRadius: 30,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Forgot Password',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _primary,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Enter your registered email and we\'ll send a reset link.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 24),
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              'Email Address',
                              style: TextStyle(
                                color: _onSurfaceVariant,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: _onSurface, fontWeight: FontWeight.w500, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: 'Enter your email',
                              hintStyle: const TextStyle(
                                color: Color.fromRGBO(89, 65, 64, 0.45),
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: const Icon(Icons.mail, color: _onSurfaceVariant),
                              filled: true,
                              fillColor: _inputBackground,
                              contentPadding: const EdgeInsets.symmetric(vertical: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: _primary, width: 1.2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 64,
                            child: ElevatedButton(
                              onPressed: (_loading || _secondsLeft > 0) ? null : _sendResetLink,
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                backgroundColor: _primary,
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: const Color.fromRGBO(140, 13, 32, 0.24),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      _secondsLeft > 0
                                          ? 'Resend in ${_secondsLeft}s'
                                          : 'Send Reset Link',
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Back to Login',
                              style: TextStyle(color: _primary, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (_sent) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(46, 125, 50, 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color.fromRGBO(46, 125, 50, 0.35)),
                              ),
                              child: const Text(
                                'After changing password from email link, return to Login and sign in. If needed, also check your spam folder for the reset email.',
                                style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
