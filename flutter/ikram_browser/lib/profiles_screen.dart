import 'package:flutter/material.dart';

import 'browser_screen.dart';
import 'browser_services.dart';
import 'domain.dart';
import 'profile_backup_dialogs.dart';
import 'profile_editor.dart';
import 'profile_store.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final _store = ProfileStore();
  List<Profile> _profiles = [];
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;
  bool _browserOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final profiles = await _store.load();
      if (!mounted) return;
      setState(() => _profiles = profiles);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _persist(List<Profile> next) async {
    await _store.save(next);
    if (mounted) setState(() => _profiles = next);
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy || _loading || _loadFailed) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      _message(
        'تعذّر إكمال العملية. قد يكون المسح جزئياً إن كنت تمسح البيانات.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _edit(Profile profile) => _change(() async {
        final updated = await editProfile(context, profile);
        if (updated != null) {
          await _replaceProfile(updated);
          _message('تم حفظ إعدادات البروفايل.');
        }
      });

  Future<void> _replaceProfile(Profile profile) =>
      _persist(_profiles.map((p) => p.id == profile.id ? profile : p).toList());

  Future<void> _delete(Profile profile) => _change(() async {
        if (!await _confirm(
          'حذف البروفايل؟',
          'سيُحذف الاسم وإعداد البروكسي فقط. لن تُمسح بيانات المواقع المشتركة '
              'ولن يتأثر تسجيل الدخول في البروفايلات الأخرى.',
        )) {
          return;
        }
        await _persist(_profiles.where((p) => p.id != profile.id).toList());
        _message('تم حذف إعدادات البروفايل فقط.');
      });

  Future<void> _clear() => _change(() async {
        if (!await _confirm(
          'مسح بيانات التصفح المشتركة؟',
          'سيتم مسح الكوكيز والذاكرة المؤقتة وتخزين المواقع المشترك لجميع '
              'البروفايلات، وقد يتم تسجيل خروجك من المواقع. '
              'لا يمكن التراجع عن المسح. ستبقى أسماء البروفايلات وإعداداتها.',
        )) {
          return;
        }
        await clearSharedBrowsingData();
        _message('اكتمل مسح الكوكيز والكاش وتخزين الويب المشترك.');
      });

  Future<void> _exportBackup() => _change(() async {
        try {
          final source = await _store.exportBackup();
          if (!mounted) return;
          await showProfileExport(context, source);
        } catch (_) {
          _message('تعذّر تصدير الإعدادات. لم تتغير البروفايلات المحفوظة.');
        }
      });

  Future<void> _importBackup() => _change(() async {
        final source = await showProfileImport(context, _profiles);
        if (source == null) return;
        try {
          final profiles = await _store.importBackup(source);
          if (!mounted) return;
          setState(() => _profiles = profiles);
          _message('تم استيراد إعدادات البروفايلات فقط، دون جلسات المواقع.');
        } on FormatException {
          _message(
            'رُفضت النسخة: بيانات غير صالحة أو معرّفات مكررة. لم تتغير بياناتك.',
          );
        } catch (_) {
          _message(
            'تعذّر حفظ الاستيراد. لم يتم تأكيد نجاح النسخة؛ أعد تحميل القائمة.',
          );
        }
      });

  Future<void> _open(Profile profile) async {
    if (_browserOpen || _busy) return;
    if (profile.proxyNeedsReview) {
      _message('تمت إزالة بيانات دخول بروكسي قديمة. عدّل إعداداته قبل التصفح.');
      return;
    }
    // Prevent a second WebView while an app-wide proxy is in use.
    _browserOpen = true;
    try {
      final accepted = await _confirm(
        'تخزين المواقع مشترك',
        'هذه البروفايلات ليست جلسات معزولة. الكوكيز وتسجيلات الدخول '
            'وتخزين المواقع مشتركة. البروكسي ليس ضماناً لإخفاء الهوية.',
      );
      if (!accepted || !mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BrowserScreen(profile: profile, onSave: _replaceProfile),
        ),
      );
    } finally {
      _browserOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _loading || _loadFailed;
    return Scaffold(
      appBar: AppBar(
        title: const Text('متصفح إكرام'),
        actions: [
          IconButton(
            tooltip: 'تصدير إعدادات البروفايلات',
            onPressed: disabled ? null : _exportBackup,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'استيراد إعدادات البروفايلات',
            onPressed: disabled ? null : _importBackup,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: 'مسح بيانات التصفح لجميع البروفايلات',
            onPressed: disabled ? null : _clear,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'تعذّر قراءة البروفايلات. لم يتم استبدال بياناتك '
                          'بقائمة فارغة. أعد المحاولة. الاستيراد معطل لحماية '
                          'المحفوظ ولا يصلح البيانات التالفة تلقائياً.',
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'تنبيه: الكوكيز وتسجيلات الدخول مشتركة بين البروفايلات. '
                        'حذف البروفايل لا يمسح بيانات التصفح.',
                      ),
                    ),
                    Expanded(
                      child: _profiles.isEmpty
                          ? const Center(child: Text('أضف بروفايلاً للبدء.'))
                          : ListView.builder(
                              itemCount: _profiles.length,
                              itemBuilder: (context, index) {
                                final profile = _profiles[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 5,
                                  ),
                                  child: ListTile(
                                    title: Text(profile.name),
                                    subtitle: Text(
                                      profile.proxyNeedsReview
                                          ? 'يجب تعديل إعداد البروكسي القديم'
                                          : profile.proxy.isEmpty
                                              ? 'شبكة النظام — بدون بروكسي من التطبيق'
                                              : 'بروكسي مطلوب: ${profile.proxy}',
                                    ),
                                    onTap:
                                        disabled ? null : () => _open(profile),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'تعديل',
                                          onPressed: disabled
                                              ? null
                                              : () => _edit(profile),
                                          icon: const Icon(Icons.edit),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف',
                                          onPressed: disabled
                                              ? null
                                              : () => _delete(profile),
                                          icon:
                                              const Icon(Icons.delete_outline),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'إضافة بروفايل',
        onPressed: disabled
            ? null
            : () => _change(() async {
                  final candidate = Profile(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: 'بروفايل ${_profiles.length + 1}',
                  );
                  final profile = await editProfile(context, candidate);
                  if (profile != null) {
                    await _persist([..._profiles, profile]);
                  }
                }),
        child: const Icon(Icons.add),
      ),
    );
  }
}
