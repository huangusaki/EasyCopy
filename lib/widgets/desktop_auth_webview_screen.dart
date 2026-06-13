import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:reader/services/desktop_webview_environment.dart';
import 'package:reader/services/site_session.dart';
import 'package:reader/widgets/auth_webview_screen.dart';
import 'package:reader/widgets/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

class DesktopAuthWebViewScreen extends StatefulWidget {
  const DesktopAuthWebViewScreen({
    required this.loginUri,
    required this.userAgent,
    super.key,
  });

  final Uri loginUri;
  final String userAgent;

  @override
  State<DesktopAuthWebViewScreen> createState() =>
      _DesktopAuthWebViewScreenState();
}

class _DesktopAuthWebViewScreenState extends State<DesktopAuthWebViewScreen> {
  WebviewController? _controller;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _isInitializing = true;
  bool _isLoading = true;
  bool _completed = false;
  bool _controllerInitialized = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final WebviewController? controller = _controller;
    if (_controllerInitialized && controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = '';
    });
    final WebviewController controller = WebviewController();
    try {
      await DesktopWebViewEnvironment.instance.ensureReady();
      await controller.initialize();
      _controllerInitialized = true;
      await controller.setUserAgent(widget.userAgent);
      await controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      _subscriptions.add(
        controller.loadingState.listen((LoadingState state) {
          if (!mounted || _completed) {
            return;
          }
          setState(() {
            _isLoading = state == LoadingState.loading;
          });
          if (state == LoadingState.navigationCompleted) {
            unawaited(_captureCookiesIfLoggedIn());
          }
        }),
      );
      _subscriptions.add(
        controller.onLoadError.listen((WebErrorStatus error) {
          if (!mounted || _completed) {
            return;
          }
          setState(() {
            _isLoading = false;
            _errorMessage = '网页登录加载失败';
          });
        }),
      );
      await controller.loadUrl(widget.loginUri.toString());
      if (!mounted) {
        return;
      }
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } catch (error) {
      if (_controllerInitialized) {
        await controller.dispose();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _isLoading = false;
        _errorMessage = error is DesktopWebViewUnavailableException
            ? error.message
            : '网页登录不可用';
      });
    }
  }

  Future<void> _captureCookiesIfLoggedIn() async {
    if (_completed) {
      return;
    }
    final WebviewController? controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      final Object? rawCookies = await controller.executeScript(
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
      Navigator.of(
        context,
      ).pop(AuthSessionResult(cookieHeader: cookieHeader, cookies: cookies));
    } catch (_) {
      return;
    }
  }

  String _normalizeJavaScriptString(Object? value) {
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
        return jsonDecode(trimmed) as String;
      }
      return trimmed;
    }
    return value?.toString() ?? '';
  }

  Future<void> _openExternalLogin() async {
    await launchUrl(widget.loginUri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final WebviewController? controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        actions: <Widget>[
          IconButton(
            onPressed: controller == null
                ? _initialize
                : () => unawaited(controller.reload()),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: _openExternalLogin,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          if (controller != null)
            Positioned.fill(child: Webview(controller))
          else
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AppSurfaceCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.web_asset_off_rounded,
                        size: 42,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _errorMessage.isEmpty ? '网页登录准备中' : _errorMessage,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: _openExternalLogin,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('浏览器打开'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isInitializing || _isLoading)
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
