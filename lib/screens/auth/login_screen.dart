import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
  with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF8C0D20);
  static const Color _background = Color(0xFFFDFBF7);
  static const Color _surface = Colors.white;
  static const Color _onSurface = Color(0xFF1C1C19);
  static const Color _onSurfaceVariant = Color(0xFF594140);
  static const Color _inputBackground = Color(0xFFF7F5F2);

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String _pinInput = '';
  late final AnimationController _entryController;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _logoScale;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;
  late final Animation<double> _badgesFade;
  late final Animation<Offset> _badgesSlide;

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _logoScale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );

    _formFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.32, 1.0, curve: Curves.easeOut),
    );
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.32, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _badgesFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.58, 1.0, curve: Curves.easeOut),
    );
    _badgesSlide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.58, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _entryController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController
        ..reset()
        ..forward();
    });
  }
  
  void _loginEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    if (email.isEmpty && password.isEmpty) {
      _showError('Please enter email and password.');
      return;
    }

    if (email.isEmpty) {
      _showError('Please enter your email address.');
      return;
    }

    if (password.isEmpty) {
      _showError('Please enter your password.');
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      _showError('Please enter a valid email address.');
      return;
    }

    try {
      setState(() => _loading = true);
      final auth = context.read<AuthService>();
      final error = await auth.loginWithEmail(email, password);

      if (error != null) {
        _showError(error);
      } else if (mounted) {
        _handlePostLoginSuccess(email);
      }
    } catch (_) {
      _showError('Unable to login right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handlePostLoginSuccess(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingResetEmail = prefs.getString('pending_reset_email');
    if (pendingResetEmail != null && pendingResetEmail.toLowerCase() == email.toLowerCase()) {
      await prefs.remove('pending_reset_email');
      await prefs.remove('pending_reset_requested_at');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed successfully. You are logged in.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _pinKeyPressed(String val) {
    if (_pinInput.length < 4) {
      setState(() {
        _pinInput += val;
      });
      if (_pinInput.length == 4) {
        _verifyPin();
      }
    }
  }

  void _pinBackspace() {
    if (_pinInput.isNotEmpty) {
      setState(() {
        _pinInput = _pinInput.substring(0, _pinInput.length - 1);
      });
    }
  }
  
  void _verifyPin() {
    final auth = context.read<AuthService>();
    final success = auth.unlockWithPin(_pinInput);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Invalid PIN'),
        backgroundColor: Colors.red,
      ));
      setState(() {
        _pinInput = '';
      });
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Consumer<AuthService>(
          builder: (context, auth, _) {
            if (auth.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final usePinMode = auth.currentUser != null && auth.hasSavedPin;

            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: Center(
                              child: FadeTransition(
                                opacity: _logoFade,
                                child: SlideTransition(
                                  position: _logoSlide,
                                  child: ScaleTransition(
                                    scale: _logoScale,
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 130),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.black, width: 1.5),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Image.asset(
                                        'assets/branding/splash_logo.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          FadeTransition(
                            opacity: _formFade,
                            child: SlideTransition(
                              position: _formSlide,
                              child: Container(
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
                                    _buildFormContent(auth, usePinMode),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 46),
                          FadeTransition(
                            opacity: _badgesFade,
                            child: SlideTransition(
                              position: _badgesSlide,
                              child: _buildBottomBadges(),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildFormContent(AuthService auth, bool usePinMode) {
     return usePinMode ? _buildPinForm(auth) : _buildEmailForm();
  }

  Widget _buildEmailForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          style: const TextStyle(
            color: _onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
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
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Password',
                style: TextStyle(
                  color: _onSurfaceVariant,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ForgotPasswordScreen(
                        initialEmail: _emailCtrl.text.trim(),
                      ),
                    ),
                  );

                  if (!mounted) return;
                  if (result == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Back to login. Enter your new password if reset is complete.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passCtrl,
          obscureText: _obscurePassword,
          style: const TextStyle(
            color: _onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: const TextStyle(
              color: Color.fromRGBO(89, 65, 64, 0.45),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
            prefixIcon: const Icon(Icons.lock, color: _onSurfaceVariant),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: _onSurfaceVariant,
              ),
            ),
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
        const SizedBox(height: 32),
        SizedBox(
          height: 72,
          child: ElevatedButton(
          onPressed: _loading ? null : _loginEmail,
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            elevation: 8,
            shadowColor: const Color.fromRGBO(140, 13, 32, 0.24),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: _loading
                ? const Row(
                    key: ValueKey('loading-state'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LoadingDots(),
                      SizedBox(width: 12),
                      Text('Signing In...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  )
                : const Row(
                    key: ValueKey('idle-state'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Sign In', style: TextStyle(fontSize: 42 / 2, fontWeight: FontWeight.w700)),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward, size: 28),
                    ],
                  ),
          ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinForm(AuthService auth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text("Enter PIN", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("Welcome back, ${auth.currentUser?.email ?? 'Staff'}", style: const TextStyle(color: _onSurfaceVariant)),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index < _pinInput.length ? _primary : Colors.grey[300],
              ),
            );
          }),
        ),
        const SizedBox(height: 48),
        _buildNumpad(),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => auth.logout(),
          child: const Text("Logout & Use Email"),
        )
      ],
    );
  }

  Widget _buildNumpad() {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 1.5,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 1; i <= 9; i++) _buildNumKey('$i'),
        _buildNumKey(''), // empty
        _buildNumKey('0'),
        IconButton(
          onPressed: _pinBackspace,
          icon: const Icon(Icons.backspace_outlined, size: 28),
          color: Colors.black87,
        )
      ],
    );
  }

  Widget _buildNumKey(String val) {
    if (val.isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: () => _pinKeyPressed(val),
      borderRadius: BorderRadius.circular(32),
      child: Center(
        child: Text(val, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.black87)),
      ),
    );
  }

  Widget _buildBottomBadges() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Badge(icon: Icons.eco, label: 'NATURAL'),
          _Badge(icon: Icons.auto_awesome, label: 'TRADITIONAL'),
          _Badge(icon: Icons.auto_awesome, label: 'SMALL BATCH'),
        ],
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = (_controller.value * 3).floor() % 3;
        return Row(
          children: List.generate(3, (index) {
            final active = index == phase;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 8 : 6,
                height: active ? 8 : 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: active ? 1 : 0.55),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color.fromRGBO(140, 13, 32, 0.5), size: 23),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color.fromRGBO(28, 28, 25, 0.5),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
