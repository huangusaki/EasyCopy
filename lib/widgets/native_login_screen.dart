import 'dart:async';

import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/login_credentials_store.dart';
import 'package:easy_copy/widgets/auth_webview_screen.dart';
import 'package:flutter/material.dart';

class NativeLoginScreen extends StatefulWidget {
  const NativeLoginScreen({
    required this.loginUri,
    required this.userAgent,
    this.credentialsStore,
    super.key,
  });

  final Uri loginUri;
  final String userAgent;
  final LoginCredentialsStore? credentialsStore;

  @override
  State<NativeLoginScreen> createState() => _NativeLoginScreenState();
}

class _NativeLoginScreenState extends State<NativeLoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late final LoginCredentialsStore _credentialsStore;
  bool _isSubmitting = false;
  bool _isLoadingSavedCredentials = true;
  bool _obscurePassword = true;
  bool _rememberPassword = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _credentialsStore =
        widget.credentialsStore ?? LoginCredentialsStore.instance;
    unawaited(_restoreSavedCredentials());
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedCredentials() async {
    final SavedLoginCredentials? credentials = await _credentialsStore.read();
    if (!mounted) {
      return;
    }
    setState(() {
      if (credentials != null) {
        _usernameController.text = credentials.username;
        _passwordController.text = credentials.password;
        _rememberPassword = true;
      }
      _isLoadingSavedCredentials = false;
    });
  }

  Future<void> _submit() async {
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = '请输入账号和密码。';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final SiteLoginResult result = await SiteApiClient.instance.login(
        username: username,
        password: password,
      );
      if (_rememberPassword) {
        await _credentialsStore.save(username: username, password: password);
      } else {
        await _credentialsStore.clear();
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        AuthSessionResult(
          cookieHeader: result.cookieHeader,
          cookies: result.cookies,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _openWebLogin() async {
    final AuthSessionResult? result = await Navigator.of(context).push(
      MaterialPageRoute<AuthSessionResult>(
        builder: (BuildContext context) {
          return AuthWebViewScreen(
            loginUri: widget.loginUri,
            userAgent: widget.userAgent,
          );
        },
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _usernameController,
                    enabled: !_isSubmitting && !_isLoadingSavedCredentials,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '账号',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    enabled: !_isSubmitting && !_isLoadingSavedCredentials,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _rememberPassword,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: const Text('记住密码'),
                    onChanged: (_isSubmitting || _isLoadingSavedCredentials)
                        ? null
                        : (bool? value) {
                            final bool nextValue = value ?? false;
                            setState(() {
                              _rememberPassword = nextValue;
                            });
                            if (!nextValue) {
                              unawaited(_credentialsStore.clear());
                            }
                          },
                  ),
                  if ((_errorMessage ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_isSubmitting || _isLoadingSavedCredentials)
                          ? null
                          : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('登录'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: (_isSubmitting || _isLoadingSavedCredentials)
                          ? null
                          : _openWebLogin,
                      child: const Text('使用网页登录 / 注册'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
