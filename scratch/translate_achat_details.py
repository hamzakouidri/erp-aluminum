import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Screen/achat_details_screen.dart'
content = open(path, encoding='utf-8').read()

# 1. Translate PDF/image attachment section
old_pdf_sec = """                                      if (_pdfPath != null) ...[
                                        const Text(
                                          'ملف PDF محفوظ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _pdfPath!.split('/').last,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _openPdfFile,
                                              child: const Text('فتح'),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed:
                                                  _showImageSourceOptions,
                                              icon: const Icon(Icons.photo),
                                              label: const Text('إرفاق صورة'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _generateInvoicePdf,
                                              icon: const Icon(
                                                Icons.picture_as_pdf,
                                              ),
                                              label: const Text('حفظ PDF'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_imagePath == null && _pdfPath == null) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _showImageSourceOptions,
                                        icon: const Icon(Icons.photo),
                                        label: const Text('إرفاق صورة'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _generateInvoicePdf,
                                        icon: const Icon(Icons.picture_as_pdf),
                                        label: const Text('حفظ PDF'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],"""

new_pdf_sec = """                                      if (_pdfPath != null) ...[
                                        Text(
                                          Localization.translate('ملف PDF محفوظ', lang),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _pdfPath!.split('/').last,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _openPdfFile,
                                              child: Text(Localization.translate('فتح', lang)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed:
                                                  _showImageSourceOptions,
                                              icon: const Icon(Icons.photo),
                                              label: Text(Localization.translate('إرفاق صورة', lang)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _generateInvoicePdf,
                                              icon: const Icon(
                                                Icons.picture_as_pdf,
                                              ),
                                              label: Text(Localization.translate('حفظ PDF', lang)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_imagePath == null && _pdfPath == null) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _showImageSourceOptions,
                                        icon: const Icon(Icons.photo),
                                        label: Text(Localization.translate('إرفاق صورة', lang)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _generateInvoicePdf,
                                        icon: const Icon(Icons.picture_as_pdf),
                                        label: Text(Localization.translate('حفظ PDF', lang)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],"""

# 2. Status card translations
old_status_sec = """                                      Text(
                                        'الحالة: $statusText',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'إجمالي العناصر: ${_formatValue(_itemsTotal)}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'المدفوع: ${_formatValue(_paidAmount)}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      Text(
                                        'المتبقي: ${_formatValue(_remainingAmount)}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_items.isEmpty) ...[
                                Container(
                                  height: 120,
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: Text('لا توجد عناصر مضافة بعد.'),
                                  ),
                                ),"""

new_status_sec = """                                      Text(
                                        '${Localization.translate('الحالة: ', lang)}$statusText',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${Localization.translate('إجمالي العناصر: ', lang)}${_formatValue(_itemsTotal)}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${Localization.translate('المدفوع: ', lang)}${_formatValue(_paidAmount)}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      Text(
                                        '${Localization.translate('المتبقي: ', lang)}${_formatValue(_remainingAmount)}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_items.isEmpty) ...[
                                Container(
                                  height: 120,
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(Localization.translate('لا توجد عناصر مضافة بعد.', lang)),
                                  ),
                                ),"""

# 3. Item map translations
old_item_sec = """                                            Text(
                                              '${item['item_name'] ?? item['item_code'] ?? 'عنصر'}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'النوع: ${item['item_type'] ?? ''}',
                                            ),
                                            if (item['color_id'] != null)
                                              Text(
                                                'اللون: ${item['color_name'] ?? 'مجهول'}',
                                                style: const TextStyle(
                                                  color: Colors.blueGrey,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            Text(
                                              'الكمية: ${_formatValue(quantity)}',
                                            ),
                                            Text(
                                              'سعر الوحدة: ${_formatValue(price)}',
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'الإجمالي: ${_formatValue(lineTotal)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                OutlinedButton.icon(
                                                  onPressed: canEditInvoice
                                                      ? () =>
                                                            _editAchatItem(item)
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'تعديل',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                OutlinedButton.icon(
                                                  onPressed:
                                                      _status == 'Confirmed'
                                                      ? null
                                                      : () => _deleteAchatItem(
                                                          item['id'] as int,
                                                        ),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'حذف',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ),"""

new_item_sec = """                                            Text(
                                              '${Localization.translate(item['item_name'] ?? item['item_code'] ?? 'عنصر', lang)}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${Localization.translate('النوع: ', lang)}${Localization.translate(item['item_type'] ?? '', lang)}',
                                            ),
                                            if (item['color_id'] != null)
                                              Text(
                                                '${Localization.translate('اللون: ', lang)}${Localization.translate(item['color_name'] ?? 'مجهول', lang)}',
                                                style: const TextStyle(
                                                  color: Colors.blueGrey,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            Text(
                                              '${Localization.translate('الكمية: ', lang)}${_formatValue(quantity)}',
                                            ),
                                            Text(
                                              '${Localization.translate('سعر الوحدة: ', lang)}${_formatValue(price)}',
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '${Localization.translate('الإجمالي: ', lang)}${_formatValue(lineTotal)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                OutlinedButton.icon(
                                                  onPressed: canEditInvoice
                                                      ? () =>
                                                            _editAchatItem(item)
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    Localization.translate('تعديل', lang),
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                OutlinedButton.icon(
                                                  onPressed:
                                                      _status == 'Confirmed'
                                                      ? null
                                                      : () => _deleteAchatItem(
                                                          item['id'] as int,
                                                        ),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    Localization.translate('حذف', lang),
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ),"""

# Perform replacements
if old_pdf_sec in content:
    content = content.replace(old_pdf_sec, new_pdf_sec)
    print("Replaced PDF section successfully.")
else:
    print("WARNING: old_pdf_sec not found!")

if old_status_sec in content:
    content = content.replace(old_status_sec, new_status_sec)
    print("Replaced status card section successfully.")
else:
    print("WARNING: old_status_sec not found!")

if old_item_sec in content:
    content = content.replace(old_item_sec, new_item_sec)
    print("Replaced item list section successfully.")
else:
    print("WARNING: old_item_sec not found!")

open(path, 'w', encoding='utf-8').write(content)
print("Done translating achat details screen!")
