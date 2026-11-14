import 'package:flutter/material.dart';

const _ink = Color(0xFF173B3F);
const _teal = Color(0xFF176B68);
const _orange = Color(0xFFE46F32);
const _paper = Color(0xFFFFF8EF);
const _softTeal = Color(0xFFEAF3F0);
const _muted = Color(0xFF5F7473);

class SafeProxyBar extends StatelessWidget {
  final String endpoint;
  final String countryLabel;
  final bool enabled;
  final bool busy;
  final bool detecting;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDetect;

  const SafeProxyBar({
    super.key,
    required this.endpoint,
    required this.countryLabel,
    required this.enabled,
    required this.busy,
    required this.detecting,
    required this.onEdit,
    required this.onToggle,
    required this.onDetect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final endpointText =
        endpoint.trim().isEmpty ? 'لم يُحدّد عنوان البروكسي' : endpoint;
    final countryText = countryLabel.trim().isEmpty
        ? 'لم يُكتشف البلد بعد'
        : countryLabel;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: enabled ? _softTeal : const Color(0xFFFFEEE4),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    enabled ? Icons.shield_outlined : Icons.shield_moon_outlined,
                    color: enabled ? _teal : _orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        enabled ? 'البروكسي مفعّل' : 'البروكسي متوقف',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          endpointText,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _muted,
                                    fontFamily: 'monospace',
                                  ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        children: [
                          const Icon(Icons.public, size: 15, color: _teal),
                          Text(
                            countryText,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _muted,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: 'تشغيل البروكسي أو إيقافه',
                  child: Switch.adaptive(
                    value: enabled,
                    onChanged: busy ? null : onToggle,
                    activeColor: _teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('تغيير الإعدادات'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy || detecting ? null : onDetect,
                  icon: detecting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore, size: 18),
                  label: Text(detecting ? 'جارٍ الكشف…' : 'كشف البلد'),
                ),
              ],
            ),
            if (busy && !detecting) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class SafeSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String target;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onSubmit;
  final VoidCallback onReload;
  final bool enabled;

  const SafeSearchBar({
    super.key,
    required this.controller,
    required this.target,
    required this.onTargetChanged,
    required this.onSubmit,
    required this.onReload,
    required this.enabled,
  });

  static const _targets = <String, String>{
    'web': 'الويب',
    'shein': 'SHEIN',
    'amazon': 'Amazon',
    'aliexpress': 'AliExpress',
  };

  Widget _targetPicker(BuildContext context) => DropdownButtonFormField<String>(
        value: _targets.containsKey(target) ? target : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'البحث في',
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: _targets.entries
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: enabled
            ? (value) {
                if (value != null) onTargetChanged(value);
              }
            : null,
      );

  Widget _searchInput(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.webSearch,
        autocorrect: false,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          hintText: 'ابحث أو أدخل رابطاً',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'بحث',
            onPressed: enabled ? onSubmit : null,
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
      );

  Widget _reloadButton() => IconButton.filledTonal(
        tooltip: 'إعادة تحميل الصفحة',
        onPressed: enabled ? onReload : null,
        icon: const Icon(Icons.refresh),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      color: _paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 380) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _targetPicker(context),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _searchInput(context)),
                      const SizedBox(width: 4),
                      _reloadButton(),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 122, child: _targetPicker(context)),
                const SizedBox(width: 8),
                Expanded(child: _searchInput(context)),
                const SizedBox(width: 4),
                _reloadButton(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SafeFingerprintCard extends StatelessWidget {
  final String title;
  final String details;
  final VoidCallback? onGenerate;

  const SafeFingerprintCard({
    super.key,
    required this.title,
    required this.details,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFF1F5ED),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: .7,
              ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fingerprint, color: _teal, size: 25),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4EBDD),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'تجريبي',
                    style: textTheme.labelSmall?.copyWith(
                      color: _teal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E5),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFF1C7A7)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF9A4A1F),
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'خصائص المتصفح المولّدة تجريبية؛ لا تغيّر هوية الجهاز ولا تضمن إخفاء الهوية.\n'
                      'Experimental only: does not change hardware identity or guarantee anonymity.',
                      style: textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: const Color(0xFF70452F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                visualDensity: VisualDensity.compact,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 10),
                title: const Text('عن هذه الخصائص'),
                leading: const Icon(Icons.tune, color: _muted, size: 20),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      details,
                      style: textTheme.bodySmall?.copyWith(
                        color: _muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.autorenew),
                label: const Text(
                  'إنشاء بصمة جديدة  ·  Generate New Fingerprint',
                  textAlign: TextAlign.center,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SafeClearDock extends StatelessWidget {
  final VoidCallback? onClear;
  final bool busy;

  const SafeClearDock({
    super.key,
    required this.onClear,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    const explanation =
        'يسجّل خروجك من المواقع عبر جميع البروفايلات، مع الحفاظ على البروفايلات المحفوظة.';

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F302F),
              blurRadius: 14,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'مسح الكل. $explanation',
                button: true,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onClear,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_sweep_outlined, size: 22),
                    label: Text(
                      busy ? 'جارٍ المسح…' : 'مسح الكل',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFCC9B7D),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                explanation,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _muted,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
