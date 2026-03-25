import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';
import 'admin_register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String _pinInput = '';
  
  void _loginEmail() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final error = await auth.loginWithEmail(_emailCtrl.text.trim(), _passCtrl.text.trim());
    setState(() => _loading = false);
    
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
      ));
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Consumer<AuthService>(
              builder: (context, auth, _) {
                if (auth.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                bool usePinMode = auth.currentUser != null && auth.hasSavedPin;
  
                return Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  margin: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))
                    ]
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.restaurant_menu, size: 64, color: Color(0xFF800000)),
                      const SizedBox(height: 16),
                      const Text("ShreeRajmandir LOGIN", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 32),
                      _buildFormContent(auth, usePinMode),
                    ],
                  ),
                );
              },
            ),
          ),
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
        const SizedBox(height: 8),
        TextField(
          controller: _emailCtrl,
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passCtrl,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _loading ? null : _loginEmail,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          child: _loading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text("LOGIN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
          },
          child: const Text("Register New Account"),
        )
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
        Text("Welcome back, ${auth.currentUser?.email ?? 'Waiter'}", style: TextStyle(color: Colors.grey[600])),
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
                color: index < _pinInput.length ? Theme.of(context).colorScheme.primary : Colors.grey[300],
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
}
