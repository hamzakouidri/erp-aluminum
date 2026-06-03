import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DynamicDialog extends StatefulWidget {
  final List<FormFieldConfig> fields;
  final void Function(List<String> values)? onSubmit;
  final String title;
  final String button;
  final String? content;
  final IconData? icon;
  final int maxLenght;

  const DynamicDialog({
    super.key,
    required this.fields,
    this.onSubmit,
    required this.title,
    required this.button,
    this.content,
    this.icon,
    this.maxLenght = 4,
  });

  @override
  State<DynamicDialog> createState() => _DynamicDialogState();
}

class _DynamicDialogState extends State<DynamicDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    // إنشاء المتحكمات مع وضع القيمة الابتدائية مباشرة
    _controllers = List.generate(
      widget.fields.length,
      (index) =>
          TextEditingController(text: widget.fields[index].initialValue ?? ""),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final values = _controllers.map((c) => c.text).toList();
      Navigator.pop(context, values);
      widget.onSubmit?.call(values);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.fields.length, (index) {
              final field = widget.fields[index];

              Widget inputField;

              if (field.type == FieldType.text) {
                inputField = TextFormField(
                  controller: _controllers[index],
                  keyboardType: field.keyboardType,
                  maxLength: field.maxLenght,
                  validator: field.validator,
                  decoration: InputDecoration(
                    // الأيقونة في البداية
                    prefixIcon: field.icon != null ? Icon(field.icon) : null,
                    // أيقونة في النهاية (مثلاً لحذف النص)
                    // suffixIcon: field.icon != null ? Icon(field.icon) : null,
                    labelText: field.label,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                );
              } else {
                inputField = DropdownButtonFormField<String>(
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  initialValue: _controllers[index].text.isEmpty
                      ? "Pvc"
                      : _controllers[index].text,
                  items: field.dropdownItems!
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: (value) {
                    _controllers[index].text = value ?? "";
                  },
                  validator: field.validator,
                  decoration: InputDecoration(
                    labelText: field.label,
                    border: const OutlineInputBorder(),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: inputField,
              );
            }),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            _submit();
          },
          child: Text(widget.button),
        ),
      ],
    );
  }
}

enum FieldType { text, dropdown }

class FormFieldConfig {
  final String label;
  final FieldType type;
  final TextInputType keyboardType;
  final List<String>? dropdownItems;
  final String? Function(String?)? validator;
  final String? initialValue;
  final List<TextInputFormatter> inputFormatters;
  final int? maxLenght;
  final IconData? icon;

  const FormFieldConfig({
    required this.label,
    this.type = FieldType.text,
    this.keyboardType = TextInputType.text,
    this.dropdownItems,
    this.validator,
    this.initialValue,
    this.inputFormatters = const [],
    this.maxLenght,
    this.icon,
  });
}
