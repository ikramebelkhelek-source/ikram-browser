import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';

const profileBackupNotice =
    'النسخة تحفظ أسماء البروفايلات ومعرّفاتها وإعدادات البروكسي فقط. '
    'لا تشمل كوكيز المواقع أو تسجيلات الدخول أو جلسات التصفح. '
    'النص غير مشفّر؛ احفظه في مكان موثوق خارج التطبيق وعلى جهاز آخر '
    'قبل حذف التطبيق أو تغيير الهاتف. الحافظة وحدها ليست نسخة دائمة. '
    'لا يمكن استعادة بيانات تطبيق حُذف دون نسخة سابقة.';

Future<void> showProfileExport(BuildContext context, String source) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
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
                SelectableText(source, textDirection: TextDirection.ltr),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: source));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'تم النسخ فقط. احفظ النص كاملاً خارج التطبيق ثم تحقق منه '
                      'بخيار معاينة الاستيراد قبل حذف التطبيق.',
                    ),
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تعذّر النسخ. حدد النص وانسخه يدوياً.'),
                  ),
                );
              }
            },
            child: const Text('نسخ JSON'),
          ),
        ],
      ),
    );

Future<String?> showProfileImport(BuildContext context, List<Profile> saved) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ProfileImportDialog(saved: saved),
    );

class _ProfileImportDialog extends StatefulWidget {
  final List<Profile> saved;
  const _ProfileImportDialog({required this.saved});

  @override
  State<_ProfileImportDialog> createState() => _ProfileImportDialogState();
}

class _ProfileImportDialogState extends State<_ProfileImportDialog> {
  final _input = TextEditingController();
  List<Profile>? _preview;
  String? _error;

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
  Widget build(BuildContext context) => AlertDialog(
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
                  'ألصق نص النسخة كاملاً. ستضاف البروفايلات دون استبدال '
                  'المحفوظ. أي معرّف مكرر يرفض الاستيراد كله. '
                  'على تثبيت جديد فقط، احذف البروفايل الافتراضي أولاً '
                  'إذا تعارض مع النسخة.',
                ),
                TextField(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
              onPressed: _validate, child: const Text('معاينة الاستيراد')),
          FilledButton(
            onPressed: _error != null || _preview == null || _preview!.isEmpty
                ? null
                : () => Navigator.pop(context, _input.text),
            child: const Text('تأكيد الاستيراد'),
          ),
        ],
      );
}
