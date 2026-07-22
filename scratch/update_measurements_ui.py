import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Commande/order_measurements_confirm_screen.dart'
content = open(path, encoding='utf-8').read()

# 1. Add _activeEditIndices field
old_fields = """  // Controllers maps: detailId -> list of instance editors
  final Map<int, List<InstanceEditor>> _editors = {};"""

new_fields = """  // Controllers maps: detailId -> list of instance editors
  final Map<int, List<InstanceEditor>> _editors = {};

  // Active edit index for each detailId
  final Map<int, int> _activeEditIndices = {};"""

content = content.replace(old_fields, new_fields)

# 2. Initialize in _loadDetails
old_init = """        _editors[detailId] = editorsList;
      }"""

new_init = """        _editors[detailId] = editorsList;
        _activeEditIndices[detailId] = editorsList.length - 1;
      }"""

content = content.replace(old_init, new_init)

# 3. Replace SingleChildScrollView (scrollDirection: Axis.horizontal) with ListView.builder layout
old_scroll_layout = """                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: 650,
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: editorsList.length,
                                    itemBuilder: (context, edIndex) {
                                      final ed = editorsList[edIndex];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            // Width
                                            Expanded(
                                              flex: 2,
                                              child: TextFormField(
                                                controller: ed.widthCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  labelText: 'العرض (mm)',
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Height
                                            Expanded(
                                              flex: 2,
                                              child: TextFormField(
                                                controller: ed.heightCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  labelText: 'الارتفاع (mm)',
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Qty
                                            Expanded(
                                              flex: 1,
                                              child: TextFormField(
                                                controller: ed.qtyCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  labelText: 'الكمية',
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                                onChanged: (_) => setState(() {}),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Location
                                            Expanded(
                                              flex: 3,
                                              child: TextFormField(
                                                controller: ed.positionCtrl,
                                                decoration: const InputDecoration(
                                                  labelText: 'الموقع / الموضع',
                                                  border: OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                            ),
                                            // Delete button
                                            if (editorsList.length > 1)
                                              IconButton(
                                                icon: const Icon(Icons.delete_forever_rounded,
                                                    color: Colors.redAccent),
                                                onPressed: () {
                                                  setState(() {
                                                    editorsList.removeAt(edIndex);
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),"""

new_scroll_layout = """                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: editorsList.length,
                                itemBuilder: (context, edIndex) {
                                  final ed = editorsList[edIndex];
                                  final isActive = _activeEditIndices[detailId] == edIndex;

                                  if (isActive) {
                                    // 🟢 Active editing layout: 2 rows of fields
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.indigo.shade100, width: 1),
                                      ),
                                      child: Column(
                                        children: [
                                          // Line 1: Width & Height
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: ed.widthCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    labelText: 'الطول / العرض (mm) *',
                                                    border: OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextFormField(
                                                  controller: ed.heightCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    labelText: 'الارتفاع (mm) *',
                                                    border: OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          // Line 2: Qty & Location & Delete Button
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: ed.qtyCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    labelText: 'الكمية *',
                                                    border: OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                  onChanged: (_) => setState(() {}),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 4,
                                                child: TextFormField(
                                                  controller: ed.positionCtrl,
                                                  decoration: const InputDecoration(
                                                    labelText: 'الموضع / الموقع',
                                                    border: OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                              if (editorsList.length > 1) ...[
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                                                  onPressed: () {
                                                    setState(() {
                                                      editorsList.removeAt(edIndex);
                                                      // Update active index to the last item
                                                      _activeEditIndices[detailId] = editorsList.length - 1;
                                                    });
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  } else {
                                    // 🟢 Collapsed layout: Single compact row description
                                    final wStr = ed.widthCtrl.text.isEmpty ? '0' : ed.widthCtrl.text;
                                    final hStr = ed.heightCtrl.text.isEmpty ? '0' : ed.heightCtrl.text;
                                    final qStr = ed.qtyCtrl.text.isEmpty ? '0' : ed.qtyCtrl.text;
                                    final posStr = ed.positionCtrl.text.trim().isEmpty ? '—' : ed.positionCtrl.text.trim();

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '$wStr × $hStr مم  ·  الكمية: $qStr  ·  الموقع: $posStr',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _activeEditIndices[detailId] = edIndex;
                                              });
                                            },
                                          ),
                                          if (editorsList.length > 1)
                                            IconButton(
                                              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                                              onPressed: () {
                                                setState(() {
                                                  editorsList.removeAt(edIndex);
                                                  _activeEditIndices[detailId] = editorsList.length - 1;
                                                });
                                              },
                                            ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              )"""

content = content.replace(old_scroll_layout, new_scroll_layout)

# 4. Replace Card Footer actions Row with a flexible Wrap
old_card_footer = """                              // Actions for this card
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.add_circle_outline_rounded),
                                    label: const Text('إضافة تقسيم / قياس'),
                                    onPressed: () {
                                      setState(() {
                                        editorsList.add(InstanceEditor(
                                          widthCtrl: TextEditingController(
                                              text: detail['largeur'].toString()),
                                          heightCtrl: TextEditingController(
                                              text: detail['hauteur'].toString()),
                                          qtyCtrl: TextEditingController(text: '1'),
                                          positionCtrl: TextEditingController(),
                                        ));
                                      });
                                    },
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.indigo,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.save_rounded),
                                    label: const Text('حفظ القياسات'),
                                    onPressed: () => _saveInstances(detailId, totalQty),
                                  ),
                                ],
                              ),"""

new_card_footer = """                              // Actions for this card
                              SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.add_circle_outline_rounded),
                                      label: const Text('إضافة تقسيم / قياس'),
                                      onPressed: () {
                                        setState(() {
                                          editorsList.add(InstanceEditor(
                                            widthCtrl: TextEditingController(
                                                text: detail['largeur'].toString()),
                                            heightCtrl: TextEditingController(
                                                text: detail['hauteur'].toString()),
                                            qtyCtrl: TextEditingController(text: '1'),
                                            positionCtrl: TextEditingController(),
                                          ));
                                          // Automatically activate the newly added item
                                          _activeEditIndices[detailId] = editorsList.length - 1;
                                        });
                                      },
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.save_rounded),
                                      label: const Text('حفظ القياسات'),
                                      onPressed: () => _saveInstances(detailId, totalQty),
                                    ),
                                  ],
                                ),
                              ),"""

content = content.replace(old_card_footer, new_card_footer)

open(path, 'w', encoding='utf-8').write(content)
print("Done updating order_measurements_confirm_screen.dart layout!")
