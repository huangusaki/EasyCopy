import 'dart:convert';

import 'package:easy_copy/services/site_session.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AuthSessionResult {
  const AuthSessionResult({
    required this.cookieHeader,
    required this.cookies,
  });

  final String cookieHeader;
  final Map<String, String> cookies;
}

class AuthWebViewScreen extends StatefulWidget {
  const AuthWebViewScreen({
    required this.loginUri,
    required this.userAgent,
    super.key,
  });

  final Uri loginUri;
  final String userAgent;

  @override
  State<AuthWebViewScreen> createState() => _AuthWebViewScreenState();
}

class _AuthWebViewScreenState extends State<AuthWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (_) async {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
            });
            await _captureCookiesIfLoggedIn();
          },
        ),
      )
      ..loadRequest(widget.loginUri);
  }

  Future<void> _captureCookiesIfLoggedIn() async {
    if (_completed) {
      return;
    }
    try {
      final Object rawCookies = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final String cookieHeader = _normalizeJavaScriptString(rawCookies);
      if (!cookieHeader.contains('token=')) {
        return;
      }
      final Map<String, String> cookies = SiteSession.parseCookieHeader(
        cookieHeader,
      );
      if ((cookies['token'] ?? '').isEmpty || !mounted) {
        return;
      }
      _completed = true;
      Navigator.of(context).pop(
        AuthSessionResult(cookieHeader: cookieHeader, cookies: cookies),
      );
    } catch (_) {
      // Ignore transient login page script errors.
    }
  }

  String _normalizeJavaScriptString(Object value) {
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
        return jsonDecode(trimmed) as String;
      }
      return trimmed;
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              _controller.loadRequest(widget.loginUri);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (_isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x1AFFFFFF),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
