import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'profile_backup_files.dart';

const profileBackupNotice =
    'النسخة تحفظ أسماء البروفايلات ومعرّفاتها وإعدادات البروكسي فقط. '
    'لا تشمل كوكيز المواقع أو تسجيلات الدخول أو جلسات التصفح. '
    'الملف والنص غير مشفّرين؛ احفظ النسخة في مكان موثوق خارج التطبيق وعلى جهاز آخر '
    'قبل حذف التطبيق أو تغيير الهاتف. الحافظة وحدها ليست نسخة دائمة. '
    'لا يمكن استعادة بيانات تطبيق حُذف دون نسخة سابقة.';

Future<void> showProfileExport(
  BuildContext context,
  String source, {
  ProfileBackupFiles files = const ProfileBackupFiles(),
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ProfileExportDialog(source: source, files: files),
    );

class _ProfileExportDialog extends StatefulWidget {
  final String source;
  final ProfileBackupFiles files;
  const _ProfileExportDialog({required this.source, required this.files});

  @override
  State<_ProfileExportDialog> createState() => _ProfileExportDialogState();
}

class _ProfileExportDialogState extends State<_ProfileExportDialog> {
  bool _busy = false;
  String? _status;

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final saved = await widget.files.save(widget.source);
      if (!mounted) return;
      setState(() => _status = saved
          ? 'تم حفظ ملف الإعدادات. افتحه بمعاينة الاستيراد للتحقق منه، '
              'واحتفظ بنسخة على جهاز آخر. لا يشمل جلسات المواقع.'
          : 'أُلغي حفظ الملف. لم تُحفظ نسخة جديدة.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status =
          'تعذّر حفظ الملف كاملاً. قد يكون التخزين غير متاح أو الملف جزئياً؛ '
              'لا تعتمد عليه. أعد المحاولة في مكان موثوق آخر ثم تحقق بالمعاينة. '
              'لم تتغير البروفايلات.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.source));
      if (!mounted) return;
      setState(() =>
          _status = 'تم النسخ فقط. احفظ النص كاملاً خارج التطبيق ثم تحقق منه '
              'بخيار معاينة الاستيراد قبل حذف التطبيق.');
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'تعذّر النسخ. حدد النص وانسخه يدوياً.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('تصدير إعدادات البروفايلات'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(profileBackupNotice),
                  const SizedBox(height: 16),
                  if (_busy) const LinearProgressIndicator(),
                  if (_status != null) Text(_status!),
                  SelectableText(widget.source,
                      textDirection: TextDirection.ltr),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            TextButton(
              onPressed: _busy ? null : _copy,
              child: const Text('نسخ JSON'),
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('حفظ ملف'),
            ),
          ],
        ),
      );
}

Future<String?> showProfileImport(
  BuildContext context,
  List<Profile> saved, {
  ProfileBackupFiles files = const ProfileBackupFiles(),
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ProfileImportDialog(saved: saved, files: files),
    );

class _ProfileImportDialog extends StatefulWidget {
  final List<Profile> saved;
  final ProfileBackupFiles files;
  const _ProfileImportDialog({required this.saved, required this.files});

  @override
  State<_ProfileImportDialog> createState() => _ProfileImportDialogState();
}

class _ProfileImportDialogState extends State<_ProfileImportDialog> {
  final _input = TextEditingController();
  List<Profile>? _preview;
  String? _error;
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
    });
    try {
      final source = await widget.files.open();
      if (!mounted || source == null) return;
      // Programmatic text updates do not invoke TextField.onChanged.
      _input.text = source;
      _validate();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'تعذّر فتح الملف: قد يكون التخزين غير متاح أو الملف أكبر من الحد '
              'المسموح أو ليس نص UTF-8 صالحاً. لم تتغير بياناتك. '
              'اختر ملفاً آخر أو ألصق النسخة كاملة ثم أعد المعاينة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _validate() {
    try {
      final imported = decodeProfileBackup(_input.text);
      String? conflict;
      try {
        mergeProfileBackup(widget.saved, _input.text);
      } on FormatException {
        conflict = 'النسخة صالحة، لكن توجد معرّفات محفوظة مسبقاً. '
            'لن يتم الاستيراد أو استبدال أي بروفايل.';
      }
      setState(() {
        _preview = imported;
        _error = conflict;
      });
    } on FormatException {
      // Never echo parser input (which might contain sensitive pasted text).
      setState(() {
        _preview = null;
        _error = 'نسخة غير صالحة أو إصدار غير مدعوم أو معرّفات مكررة '
            'داخل النسخة أو مع المحفوظ. لم تتغير بياناتك.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('استيراد إعدادات البروفايلات'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(profileBackupNotice),
                  const SizedBox(height: 12),
                  const Text(
                    'افتح ملف النسخة أو ألصق نصها كاملاً ثم عاينه. '
                    'ستضاف البروفايلات دون استبدال '
                    'المحفوظ. أي معرّف مكرر يرفض الاستيراد كله. '
                    'على تثبيت جديد فقط، احذف البروفايل الافتراضي أولاً '
                    'إذا تعارض مع النسخة.',
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _open,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('فتح ملف'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  TextField(
                    enabled: !_busy,
                    controller: _input,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: maxProfileBackupLength,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'JSON'),
                    onChanged: (_) => setState(() {
                      _preview = null;
                      _error = null;
                    }),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  if (_preview != null) ...[
                    Text('النسخة صالحة. عدد البروفايلات: ${_preview!.length}'),
                    for (final profile in _preview!) Text('• ${profile.name}'),
                    const Text('هذه معاينة فقط؛ لم يتم الحفظ بعد.'),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            TextButton(
                onPressed: _busy ? null : _validate,
                child: const Text('معاينة الاستيراد')),
            FilledButton(
              onPressed: _busy ||
                      _error != null ||
                      _preview == null ||
                      _preview!.isEmpty
                  ? null
                  : () => Navigator.pop(context, _input.text),
              child: const Text('تأكيد الاستيراد'),
            ),
          ],
        ),
      );
}
