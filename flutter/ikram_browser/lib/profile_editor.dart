import 'package:flutter/material.dart';

import 'domain.dart';

Future<Profile?> editProfile(BuildContext context, Profile profile) =>
    showDialog<Profile>(
      context: context,
      builder: (_) => _ProfileEditor(profile: profile),
    );

class _ProfileEditor extends StatefulWidget {
  final Profile profile;
  const _ProfileEditor({required this.profile});

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _proxy = TextEditingController(text: widget.profile.proxy);

  @override
  void dispose() {
    _name.dispose();
    _proxy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('إعدادات البروفايل'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'اسم البروفايل'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل اسم البروفايل.'
                      : null,
                ),
                TextFormField(
                  controller: _proxy,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'البروكسي (Android فقط)',
                    hintText: 'host:port',
                  ),
                  validator: (value) {
                    try {
                      ProxyEndpoint.parse(value ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'اتركه فارغاً لاستخدام شبكة النظام. لا تدعم هذه النسخة '
                  'بروكسي باسم مستخدم وكلمة مرور. الكوكيز وتسجيلات الدخول '
                  'مشتركة بين جميع البروفايلات.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              final endpoint = ProxyEndpoint.parse(_proxy.text);
              Navigator.pop(
                context,
                Profile(
                  id: widget.profile.id,
                  name: _name.text.trim(),
                  proxy: endpoint?.url ?? '',
                ),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      );
}
