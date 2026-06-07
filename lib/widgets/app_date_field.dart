import 'package:flutter/material.dart';

class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.decoration,
    this.hintText,
    this.helperText,
    this.errorText,
    this.firstDate,
    this.lastDate,
    this.onChanged,
    this.validator,
    this.readOnly = false,
    this.allowClear = true,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final InputDecoration? decoration;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final bool readOnly;
  final bool allowClear;

  static DateTime? parse(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static String format(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    Future<void> pickDate() async {
      final now = DateTime.now();
      final minDate = firstDate ?? DateTime(1900);
      final maxDate = lastDate ?? DateTime(2100);
      final parsed = parse(controller.text);
      final initialDate =
          parsed == null || parsed.isBefore(minDate) || parsed.isAfter(maxDate)
          ? (now.isBefore(minDate)
                ? minDate
                : now.isAfter(maxDate)
                ? maxDate
                : now)
          : parsed;
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: minDate,
        lastDate: maxDate,
      );
      if (picked == null) return;
      controller.text = format(picked);
      onChanged?.call(controller.text);
    }

    final baseDecoration =
        decoration ??
        InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF335538)),
        );

    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: TextInputType.datetime,
      validator: validator,
      onChanged: onChanged,
      onTap: readOnly ? pickDate : null,
      decoration: baseDecoration.copyWith(
        labelText: baseDecoration.labelText ?? label,
        hintText: hintText ?? baseDecoration.hintText,
        helperText: helperText ?? baseDecoration.helperText,
        errorText: errorText ?? baseDecoration.errorText,
        prefixIcon: baseDecoration.prefixIcon ?? Icon(icon),
        suffixIcon: SizedBox(
          width: allowClear ? 96 : 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Choose date',
                onPressed: pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
              if (allowClear)
                IconButton(
                  tooltip: 'Clear date',
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
