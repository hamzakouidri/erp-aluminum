import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

import 'glass_joint_fit.dart';
import 'model.dart';

String _mm(double value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

String _fill(String template, Map<String, String> values) {
  var result = template;
  values.forEach((key, value) => result = result.replaceAll('{$key}', value));
  return result;
}

/// The layers of a glazing pack in fitting order: vitrage gasket, glass
/// (panes and spacer), then bourrage gasket.
String _packLayers(
  GlassStructure structure,
  GlassPackFit pack,
  AppLanguage lang,
) {
  String t(String key) => Localization.translate(key, lang);
  final glassLabel = structure == GlassStructure.closed ? t('بانو') : t('زجاج');
  final glass = structure == GlassStructure.double
      ? '$glassLabel ${_mm(pack.outer)} + ${t('فاصل')} ${_mm(pack.spacer)} + '
            '$glassLabel ${_mm(pack.inner)}'
      : '$glassLabel ${_mm(pack.outer)}';
  double thickness(Map<String, dynamic> row) =>
      double.tryParse('${row['thickness'] ?? 0}') ?? 0;
  final layers = <String>[];
  if (pack.joints.isNotEmpty) {
    layers.add('${t('جوان فيتراج')} ${_mm(thickness(pack.joints.first))}');
  }
  layers.add(glass);
  if (pack.joints.length > 1) {
    layers.add('${t('جوان بوراج')} ${_mm(thickness(pack.joints[1]))}');
  }
  return layers.join(' + ');
}

/// The glass drawer message for [report], in [lang].
String describeGlazingFit(GlazingFitReport report, AppLanguage lang) {
  String t(String key) => Localization.translate(key, lang);
  final target = t(report.usesBead ? 'الباركلوز' : 'الضلفة');
  final capacity = report.capacity;
  if (capacity == null) {
    return _fill(t('تعذّر حساب التركيب: سعة الزجاج غير محددة في {target}.'), {
      'target': target,
    });
  }
  final capacityText = _mm(capacity);
  final fit = report.fit;
  if (report.valid && fit != null) {
    final parts = <String>[
      _fill(
        t('التركيب المعتمد: {pack} = {total} مم، وسعة {target} {capacity} مم.'),
        {
          'pack': _packLayers(report.structure, fit, lang),
          'total': _mm(fit.total),
          'target': target,
          'capacity': capacityText,
        },
      ),
    ];
    final excess = fit.total - capacity;
    if (excess > 0.05) {
      parts.add(
        _fill(t('زيادة {excess} مم مقبولة (الحد الأقصى 1 مم).'), {
          'excess': _mm(excess),
        }),
      );
    }
    if (report.manualSpacer) {
      parts.add(
        _fill(t('الفاصل {spacer} مم اختيار يدوي.'), {
          'spacer': _mm(report.spacer),
        }),
      );
    } else if (report.structure == GlassStructure.double) {
      parts.add(t('يمكنك تغيير الفاصل يدوياً، وسيظهر تنبيه إن لم يتوافق.'));
    }
    return parts.join(' ');
  }

  final parts = <String>[];
  if (report.manualSpacer) {
    parts.add(
      _fill(t('الفاصل {spacer} مم لا يتوافق مع سعة {target} ({capacity} مم).'), {
        'spacer': _mm(report.spacer),
        'target': target,
        'capacity': capacityText,
      }),
    );
  } else {
    final glass = report.structure == GlassStructure.double
        ? '${_mm(report.outer)}+${_mm(report.spacer)}+${_mm(report.inner)} ${t('مم')}'
        : '${_mm(report.outer)} ${t('مم')}';
    parts.add(
      _fill(t('الزجاج المطلوب ({glass}) لا يتوافق مع سعة {target} ({capacity} مم).'), {
        'glass': glass,
        'target': target,
        'capacity': capacityText,
      }),
    );
  }
  final suggestion = report.suggestion;
  if (suggestion == null) {
    parts.add(
      t('لا توجد تركيبة مناسبة من الجوانات والفاصل المفعّلة؛ لا يُقبل النقص والزيادة القصوى 1 مم.'),
    );
  } else {
    final panesChanged =
        report.structure != GlassStructure.double ||
        (suggestion.outer - report.outer).abs() > 0.01 ||
        (report.structure == GlassStructure.double &&
            (suggestion.inner - report.inner).abs() > 0.01);
    final values = {
      'spacer': _mm(suggestion.spacer),
      'pack': _packLayers(report.structure, suggestion, lang),
      'total': _mm(suggestion.total),
    };
    parts.add(
      _fill(
        t(
          panesChanged
              ? 'المقترح: تغيير سُمك الزجاج ({pack} = {total} مم).'
              : 'المقترح: فاصل {spacer} مم ({pack} = {total} مم).',
        ),
        values,
      ),
    );
  }
  return parts.join(' ');
}
