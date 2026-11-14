import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_chrome.dart';
import 'browser_identity.dart';
import 'browser_services.dart';
import 'domain.dart';
import 'identity_store.dart';
import 'profile_editor.dart';
import 'proxy_country.dart';

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
  final _identities = IdentityStore();
  BrowserIdentity? _identity;
  ProxyCountry? _country;
  bool _proxyEnabled = true;
  bool _detecting = false;
  bool _countryConsent = false;
  bool _clearing = false;
  String _countryStatus = 'لم يُفحص البلد';
  String _searchTarget = 'shein';

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

  Future<void> _prepare(Profile profile,
      {bool persist = false, bool? proxyEnabled, bool lookup = true}) async {
    setState(() {
      _ready = false;
      _busy = true;
      _error = null;
      _controller = null;
      _country = null;
      _countryStatus = 'لم يُفحص البلد';
    });
    // Destroy the existing WebView before changing process-wide proxy rules.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      if (profile.proxyNeedsReview) {
        throw StateError('عدّل إعدادات البروكسي قبل التصفح.');
      }
      final preferences = await SharedPreferences.getInstance();
      final enabled = proxyEnabled ??
          (persist ? profile.proxy.isNotEmpty :
            preferences.getBool('ikram_safe_proxy_enabled_${profile.id}') ??
            profile.proxy.isNotEmpty);
      await _network.apply(enabled ? profile.proxy : '');
      if (!mounted) return;
      if (persist) await widget.onSave(profile);
      final stateSaved = await preferences.setBool(
          'ikram_safe_proxy_enabled_${profile.id}', enabled);
      if (!stateSaved) throw StateError('Could not save network state');
      final identity = await _identities.load(profile.id);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _proxyEnabled = enabled;
        _identity = identity;
        _countryConsent = preferences.getBool('ikram_safe_country_consent') ?? false;
        _generation++;
        _progress = 0;
        _ready = true;
      });
      if (_countryConsent && lookup) _detectCountry();
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
      final value = _address.text.trim();
      final candidate = resolveAddress(value);
      final isSearch = candidate.host == 'www.google.com' &&
          candidate.path == '/search' &&
          !value.startsWith('http');
      final uri = isSearch ? shoppingSearch(value, _searchTarget) : candidate;
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
    if (_busy || _detecting) return;
    final updated = await editProfile(context, _profile);
    if (updated == null || !mounted) return;
    await _prepare(updated, persist: true);
  }

  Future<void> _toggleProxy(bool enabled) async {
    if (_busy || _detecting) return;
    if (enabled && _profile.proxy.isEmpty) {
      await _edit();
      return;
    }
    await _prepare(_profile, proxyEnabled: enabled);
  }

  Future<void> _detectCountry() async {
    if (_detecting || !_ready || !mounted) return;
    if (!_countryConsent) {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('فحص بلد الاتصال'),
          content: const Text(
            'سيُطلب البلد من api.country.is عبر إعداد البروكسي الحالي. '
            'سترى الخدمة عنوان IP الخارجي فقط دون إرسال روابط التصفح أو '
            'بيانات البروفايلات. النتيجة تقريبية وليست ضماناً لإخفاء الهوية. '
            'هل تسمح بالفحص عند فتح المتصفح وتغيير الشبكة؟',
          ),
          actions: [
            IconButton(
              tooltip: 'رجوع في الموقع',
              onPressed: !_ready || _busy ? null : () async {
                try {
                  final controller = _controller;
                  if (controller != null && await controller.canGoBack() && mounted) {
                    await controller.goBack();
                  }
                } catch (_) {
                  _message('تعذّر الرجوع في الموقع.');
                }
              },
              icon: const Icon(Icons.undo),
            ),
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('السماح والفحص')),
          ],
        ),
      );
      if (allowed != true || !mounted) return;
      try {
        final saved = await (await SharedPreferences.getInstance())
            .setBool('ikram_safe_country_consent', true);
        if (!saved) throw StateError('Consent was not saved');
        _countryConsent = true;
      } catch (_) {
        _message('تعذّر حفظ موافقة فحص البلد.');
        return;
      }
    }
    final generation = _generation;
    setState(() {
      _detecting = true;
      _countryStatus = 'جارٍ فحص البلد…';
    });
    try {
      final country = await detectProxyCountry();
      if (!mounted || generation != _generation) return;
      setState(() {
        _country = country;
        _countryStatus = 'البلد: ${country.code} · IP: ${country.ip}';
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _country = null;
          _countryStatus = 'تعذّر تحديد البلد — أعد الفحص';
        });
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _countrySettings() async {
    if (_busy || _detecting || !_ready) return;
    if (!_countryConsent) {
      await _detectCountry();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فحص بلد الاتصال'),
        content: const Text('الفحص التقريبي عبر api.country.is مفعّل. '
            'يمكنك تحديث النتيجة أو سحب موافقة الفحص التلقائي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, 'disable'),
              child: const Text('إيقاف الفحص التلقائي')),
          FilledButton(onPressed: () => Navigator.pop(context, 'refresh'),
              child: const Text('تحديث البلد')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'refresh') {
      await _detectCountry();
    } else if (action == 'disable') {
      try {
        final saved = await (await SharedPreferences.getInstance())
            .setBool('ikram_safe_country_consent', false);
        if (!saved) throw StateError('Consent was not saved');
        if (mounted) {
          setState(() {
            _countryConsent = false;
            _country = null;
            _countryStatus = 'الفحص التلقائي متوقف';
          });
        }
      } catch (_) {
        _message('تعذّر حفظ إعداد الفحص.');
      }
    }
  }

  Future<void> _generateIdentity() async {
    if (_busy || _detecting || !_ready) return;
    setState(() => _busy = true);
    try {
      final engine = await InAppWebViewController.getDefaultUserAgent();
      final identity = BrowserIdentity.generate(engine, previous: _identity);
      await _identities.save(_profile.id, identity);
      if (!mounted) return;
      await _prepare(_profile, proxyEnabled: _proxyEnabled, lookup: false);
      _message('تم تطبيق خصائص جديدة. لم تتغير هوية الجهاز المادية '
          'ولم تُمسح الكوكيز. أُعيد تحميل الصفحة.');
    } catch (_) {
      _message('تعذّر توليد خصائص المتصفح أو حفظها.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    if (_busy || _detecting) return;
    setState(() {
      _busy = true;
      _clearing = true;
    });
    try {
      await _controller?.stopLoading();
      if (!mounted) return;
      setState(() {
        _ready = false;
        _controller = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      final report = await clearSharedBrowsingData();
      if (!mounted) return;
      // Stay on a blank page after cleanup: no shop or IP service may
      // immediately recreate cookies, storage or cache behind the user's back.
      _url = Uri.parse('about:blank');
      _address.clear();
      await _prepare(_profile, proxyEnabled: _proxyEnabled, lookup: false);
      _message(report.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذّر إكمال المسح. قد تكون بعض البيانات '
            'باقية. التصفح متوقف؛ أعد المحاولة.');
        setState(() {
          _ready = false;
          _controller = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _clearing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy && !_detecting,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('إكرام سيف'),
              Text(_profile.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'إعدادات البروفايل والبروكسي',
              onPressed: _busy || _detecting ? null : _edit,
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
        body: LayoutBuilder(builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight * .60),
              child: SingleChildScrollView(child: Column(children: [
            SafeProxyBar(
              endpoint: !_ready ? 'التصفح متوقف' : _proxyEnabled
                  ? _profile.proxy : 'شبكة النظام — بدون بروكسي من التطبيق',
              countryLabel: _country == null ? _countryStatus
                  : 'البلد: ${_country!.code} · IP: ${_country!.ip}',
              enabled: _proxyEnabled,
              busy: _busy || _detecting,
              detecting: _detecting,
              onEdit: _edit,
              onToggle: _toggleProxy,
              onDetect: _countrySettings,
            ),
            SafeSearchBar(
              controller: _address,
              target: _searchTarget,
              onTargetChanged: (value) => setState(() => _searchTarget = value),
              onSubmit: _navigate,
              onReload: () async {
                try {
                  await _controller?.reload();
                } catch (_) {
                  _message('تعذّرت إعادة التحميل.');
                }
              },
              enabled: _ready && !_busy,
            ),
            SafeFingerprintCard(
              title: _identity == null ? 'خصائص المتصفح الأصلية'
                  : '${_identity!.device} · ${_identity!.cores} نوى · ${_identity!.memoryGiB} GB',
              details: _identity == null
                  ? 'لم يتم توليد خصائص بديلة. تُستخدم إعدادات WebView الأصلية.'
                  : 'ملف تجريبي ${_identity!.id.substring(0, 8)}. '
                      'Canvas وWebGL وClient Hints وبصمات الشبكة قد تكشف الجهاز الحقيقي.',
              onGenerate: _ready && !_busy && !_detecting ? _generateIdentity : null,
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
              ])),
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
                        userAgent: _identity?.userAgent,
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
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        if (_identity != null)
                          UserScript(source: _identity!.script,
                            forMainFrameOnly: false,
                            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
                      ]),
                      onWebViewCreated: (controller) =>
                          _controller = controller,
                      shouldOverrideUrlLoading: (controller, action) async {
                        final url = action.request.url;
                        if (url?.toString() == 'about:blank') {
                          return NavigationActionPolicy.ALLOW;
                        }
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
                        if (url != null && url.toString() != 'about:blank') {
                          _address.text = url.toString();
                        }
                      },
                      onLoadStop: (_, url) async {
                        if (!mounted || url == null) return;
                        _url = Uri.parse(url.toString());
                        if (url.toString() != 'about:blank') {
                          _address.text = url.toString();
                        }
                      },
                      onUpdateVisitedHistory: (_, url, __) {
                        if (!mounted || url == null) return;
                        _url = Uri.parse(url.toString());
                        if (url.toString() != 'about:blank') {
                          _address.text = url.toString();
                        }
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
        )),
        bottomNavigationBar: SafeClearDock(
          onClear: _busy || _detecting ? null : _clearAll,
          busy: _clearing,
        ),
      ));
}
