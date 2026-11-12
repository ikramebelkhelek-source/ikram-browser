import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_services.dart';
import 'domain.dart';
import 'profile_editor.dart';

class BrowserScreen extends StatefulWidget {
  final Profile profile;
  final Future<void> Function(Profile) onSave;

  const BrowserScreen({
    super.key,
    required this.profile,
    required this.onSave,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _network = BrowserNetwork();
  final _address = TextEditingController(text: 'https://www.shein.com');
  late Profile _profile = widget.profile;
  InAppWebViewController? _controller;
  bool _ready = false;
  bool _busy = true;
  String? _error;
  double _progress = 0;
  int _generation = 0;
  Uri _url = Uri.parse('https://www.shein.com');

  @override
  void initState() {
    super.initState();
    _prepare(_profile);
  }

  @override
  void dispose() {
    _address.dispose();
    // No asynchronous global network change here: it could race the next
    // browser route. Every browser applies its own settings before creation.
    super.dispose();
  }

  Future<void> _prepare(Profile profile, {bool persist = false}) async {
    setState(() {
      _ready = false;
      _busy = true;
      _error = null;
      _controller = null;
    });
    // Destroy the existing WebView before changing process-wide proxy rules.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      if (profile.proxyNeedsReview) {
        throw StateError('عدّل إعدادات البروكسي قبل التصفح.');
      }
      await _network.apply(profile.proxy);
      if (!mounted) return;
      if (persist) await widget.onSave(profile);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _generation++;
        _progress = 0;
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;
      // Never fall back to direct browsing when proxy setup or persistence
      // fails. Also never render platform exceptions that may contain secrets.
      setState(() {
        _error = 'لم يبدأ التصفح. تعذّر تطبيق إعداد الشبكة أو حفظه. '
            'البروكسي متاح على Android الداعم فقط، دون اسم مستخدم وكلمة مرور. '
            'لم يتم الانتقال تلقائياً إلى اتصال مباشر.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _navigate() async {
    if (!_ready || _busy) return;
    try {
      final uri = resolveAddress(_address.text);
      _url = uri;
      setState(() => _error = null);
      await _controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    } on FormatException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('تعذّر فتح الرابط.');
    }
  }

  Future<void> _edit() async {
    if (_busy) return;
    final updated = await editProfile(context, _profile);
    if (updated == null || !mounted) return;
    await _prepare(updated, persist: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_profile.name),
          actions: [
            IconButton(
              tooltip: 'إعدادات البروفايل والبروكسي',
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                !_ready
                    ? 'التصفح متوقف حتى تطبيق الإعدادات'
                    : _profile.proxy.isEmpty
                        ? 'شبكة النظام — بدون بروكسي من التطبيق'
                        : 'تم تطبيق إعداد البروكسي: ${_profile.proxy}\n'
                            'هذا ليس فحصاً لعنوان IP أو ضماناً لإخفاء الهوية.',
              ),
            ),
            const Text(
              'الكوكيز وتسجيلات الدخول مشتركة بين البروفايلات.',
              style: TextStyle(fontSize: 12),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'رجوع في الموقع',
                  onPressed: !_ready || _busy
                      ? null
                      : () async {
                          final controller = _controller;
                          if (controller != null &&
                              await controller.canGoBack()) {
                            await controller.goBack();
                          }
                        },
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: TextField(
                    controller: _address,
                    enabled: _ready && !_busy,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'رابط الموقع أو عبارة البحث',
                    ),
                    onSubmitted: (_) => _navigate(),
                  ),
                ),
                IconButton(
                  tooltip: 'فتح',
                  onPressed: _ready && !_busy ? _navigate : null,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: 'إعادة التحميل',
                  onPressed: _ready && !_busy
                      ? () async {
                          try {
                            setState(() => _error = null);
                            await _controller?.reload();
                          } catch (_) {
                            _message('تعذّرت إعادة التحميل.');
                          }
                        }
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_busy || (_ready && _progress < 1))
              LinearProgressIndicator(value: _busy ? null : _progress),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!),
                    if (!_ready)
                      TextButton(
                        onPressed: _busy ? null : () => _prepare(_profile),
                        child: const Text('إعادة تطبيق الإعدادات'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: !_ready
                  ? const Center(child: Text('لا توجد صفحة مفتوحة.'))
                  : InAppWebView(
                      key: ValueKey(_generation),
                      initialUrlRequest: URLRequest(
                        url: WebUri(_url.toString()),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        databaseEnabled: true,
                        domStorageEnabled: true,
                        supportMultipleWindows: false,
                        javaScriptCanOpenWindowsAutomatically: false,
                        useShouldOverrideUrlLoading: true,
                        thirdPartyCookiesEnabled: false,
                        // Android incognito would clear ALL WebView cookies.
                        // Do not use it as pretend per-profile isolation.
                        incognito: false,
                      ),
                      onWebViewCreated: (controller) =>
                          _controller = controller,
                      shouldOverrideUrlLoading: (controller, action) async {
                        final url = action.request.url;
                        if (url == null ||
                            !{'http', 'https'}.contains(url.scheme) ||
                            url.userInfo.isNotEmpty) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      },
                      onProgressChanged: (_, progress) {
                        if (mounted) {
                          setState(() => _progress = progress / 100);
                        }
                      },
                      onLoadStart: (_, url) {
                        if (!mounted) return;
                        setState(() => _error = null);
                        if (url != null) _address.text = url.toString();
                      },
                      onLoadStop: (_, url) async {
                        if (!mounted || url == null) return;
                        _url = Uri.parse(url.toString());
                        _address.text = url.toString();
                      },
                      onUpdateVisitedHistory: (_, url, __) {
                        if (!mounted || url == null) return;
                        _url = Uri.parse(url.toString());
                        _address.text = url.toString();
                      },
                      onReceivedError: (_, request, error) {
                        if (!mounted || request.isForMainFrame != true) return;
                        setState(() {
                          _progress = 1;
                          _error = 'تعذّر تحميل الصفحة. تحقق من الشبكة '
                              'والبروكسي. لم يتم تعطيل البروكسي تلقائياً.';
                        });
                      },
                      onReceivedHttpError: (_, request, response) {
                        if (!mounted || request.isForMainFrame != true) return;
                        setState(() {
                          _progress = 1;
                          _error = 'أعاد الموقع خطأ HTTP '
                              '${response.statusCode ?? ''}.';
                        });
                      },
                      // Deliberately do not override TLS/certificate errors.
                    ),
            ),
          ],
        ),
      );
}
