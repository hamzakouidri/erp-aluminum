import re

def patch_bottom_bar():
    path = 'lib/Commande/Systeme/material_consumption_screen.dart'
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find the bounds of _buildBottomBar
    start_str = "  Widget _buildBottomBar(List<BomItem> items) {"
    start_idx = content.find(start_str)
    
    end_str = "  Widget _header() {"
    end_idx = content.find(end_str)
    
    if start_idx == -1 or end_idx == -1:
        print("Could not find _buildBottomBar bounds!")
        return

    new_methods = '''  void _showCalculationDetails(
    double totalProfilePrice, double totalGlassPrice, double shutterLamesPrice, 
    double coulisseSellPrice, double moteurTotalPrice, double manivelleSellingPrice, 
    double accessoryExtra, double finalSellingPrice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفاصيل الحساب', textDirection: TextDirection.rtl),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_costMethod == CostMethod.linearMeter) ...[
                _detailRow('سعر البروفيلات:', totalProfilePrice),
                _detailRow('سعر الزجاج:', totalGlassPrice),
              ] else if (_costMethod == CostMethod.squareMeter) ...[
                _detailRow('سعر النافذة (م²):', finalSellingPrice - shutterLamesPrice - coulisseSellPrice - moteurTotalPrice - manivelleSellingPrice - accessoryExtra),
              ] else ...[
                _detailRow('سعر النافذة (نسبة):', finalSellingPrice - shutterLamesPrice - coulisseSellPrice - moteurTotalPrice - manivelleSellingPrice - accessoryExtra),
              ],
              const Divider(),
              _detailRow('الستار (م²):', shutterLamesPrice),
              _detailRow('السكك:', coulisseSellPrice),
              _detailRow('المحرك (مع التركيب):', moteurTotalPrice),
              _detailRow('المانيفال (مع التركيب):', manivelleSellingPrice),
              const Divider(),
              _detailRow('إكسسوارات خاصة (OB/Verrou):', accessoryExtra),
              const Divider(thickness: 2),
              _detailRow('المجموع الإجمالي:', finalSellingPrice, isBold: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, double price, {bool isBold = false}) {
    if (price == 0 && !isBold) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        textDirection: TextDirection.rtl,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('${price.toStringAsFixed(2)} دج', style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isBold ? Colors.green.shade700 : null), textDirection: TextDirection.rtl),
        ],
      ),
    );
  }

  Widget _buildBottomBar(List<BomItem> items) {
    final double totalCostWithWaste = items
        .where((i) => i.isActive)
        .fold(0.0, (sum, i) => sum + i.total);
    double sellingPrice = totalCostWithWaste;
    
    // Variables for Details Dialog
    double shutterLamesPrice = 0.0;
    double coulisseSellPrice = 0.0;
    double moteurTotalPrice = 0.0;
    double manivelleSellingPrice = 0.0;
    double totalProfileMeters = 0.0;
    double totalGlassPrice = 0.0;
    double accessoryExtra = 0.0;
    
    // Installation fees hardcoded to 0 for now until DB table is created
    double _moteurInstallFee = 0.0;
    double _manivelleInstallFee = 0.0;
    
    // حساب سعر الستار
    double shutterSellingPrice = 0.0;
    bool hasShutter = items.any((item) => item.isActive && item.category == 'shutter');
    if (hasShutter) {
      bool hasLames = false;
      bool hasMoteur = false;
      bool hasManivelle = false;
      bool hasCoulisse = false;
      final shutterItems = items.where((i) => i.isActive && i.category == 'shutter').toList();

      for (var item in shutterItems) {
        final nameLower = item.originalName.toLowerCase();
        if (item.originalName == 'الشرائح (Lames)') {
          hasLames = true;
          shutterLamesPrice += item.total;
        } else if (nameLower.contains('moteur') || nameLower.contains('محرك')) {
          hasMoteur = true;
          moteurTotalPrice += item.total + (_moteurInstallFee * widget.model.quantity);
        } else if (nameLower.contains('manivelle') || nameLower.contains('مانيفال')) {
          hasManivelle = true;
          manivelleSellingPrice += item.total + (_manivelleInstallFee * widget.model.quantity);
        } else if (nameLower.contains('coulisse') || nameLower.contains('سكة') || nameLower.contains('سكك')) {
          hasCoulisse = true;
          coulisseSellPrice += item.total;
        }
      }

      if (hasLames) shutterSellingPrice += shutterLamesPrice;
      if (hasMoteur) shutterSellingPrice += moteurTotalPrice;
      if (hasManivelle) shutterSellingPrice += manivelleSellingPrice;
      if (hasCoulisse) shutterSellingPrice += coulisseSellPrice;
    }

    // حساب سعر الزجاج والإكسسوارات الخاصة
    double totalDirectItemsPrice = 0.0;
    for (var item in items) {
      if (!item.isActive) continue;
      if (item.category == 'glass') {
        totalGlassPrice += item.total;
      } else if (item.category == 'accessory') {
        final nameLower = item.originalName.toLowerCase();
        if (nameLower.contains('verrou') || nameLower.contains('system ob') || nameLower.contains('demi ob')) {
          accessoryExtra += item.total;
        }
      }
    }
    
    // حساب السعر النهائي بناءً على طريقة الحساب المختارة للنافذة (بدون الستار)
    double windowSellingPrice = 0.0;
    double totalProfilePrice = 0.0;
    
    if (_costMethod == CostMethod.percentage) {
      windowSellingPrice = (totalCostWithWaste - shutterSellingPrice) * (1 + _profitMargin / 100);
    } else if (_costMethod == CostMethod.squareMeter) {
      double areaSqm = (widget.model.width / 1000.0) * (widget.model.height / 1000.0);
      windowSellingPrice = _pricePerSqm * areaSqm * widget.model.quantity;
      // In square meter mode, the Fiche adds the accessories price manually because they are extra
      windowSellingPrice += accessoryExtra;
    } else if (_costMethod == CostMethod.linearMeter) {
      double linearM = 2 * (widget.model.width + widget.model.height) / 1000.0;
      windowSellingPrice = _pricePerLinearMeter * linearM * widget.model.quantity;
      // In linear meter mode, add glass and accessories separately
      windowSellingPrice += totalGlassPrice + accessoryExtra;
      
      // Calculate totalProfilePrice for details
      for (var item in items) {
        if (!item.isActive || item.category != 'profile') continue;
        final nameLower = item.originalName.toLowerCase();
        final isFrame = nameLower.contains('إطار') || nameLower.contains('cadre') || nameLower.contains('frame');
        final isSash = nameLower.contains('درفة') || nameLower.contains('ouvrant') || nameLower.contains('sash');
        final isMullion = nameLower.contains('تقسيم') || nameLower.contains('mullion');
        final isBatmo = nameLower.contains('باتمو') || nameLower.contains('batmo') || nameLower.contains('باتبو') || nameLower.contains('batbo');

        if (isFrame || isSash || isMullion || isBatmo) {
          if (item.pieces != null) {
            totalProfileMeters += item.pieces!.fold<double>(0.0, (sum, p) => sum + p);
          } else if (item.length != null) {
            totalProfileMeters += (item.length! / 1000.0) * item.quantity;
          }
        } else {
          totalDirectItemsPrice += item.total;
        }
      }
      totalProfilePrice = (totalProfileMeters * _pricePerLinearMeter) + totalDirectItemsPrice;
    }

    sellingPrice = windowSellingPrice + shutterSellingPrice;

    return SafeArea(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(
                      () => _isBottomBarExpanded = !_isBottomBarExpanded,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isBottomBarExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isBottomBarExpanded ? 'إخفاء' : 'إعدادات السعر',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showCalculationDetails(
                      totalProfilePrice,
                      totalGlassPrice,
                      shutterLamesPrice,
                      coulisseSellPrice,
                      moteurTotalPrice,
                      manivelleSellingPrice,
                      accessoryExtra,
                      sellingPrice,
                    ),
                    icon: const Icon(Icons.info_outline, color: Colors.blue),
                    label: const Text('تفاصيل', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            if (_isBottomBarExpanded)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey.shade50,
                child: _buildCostMethodSelector(),
              ),
            Container(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                textDirection: TextDirection.rtl,
                children: [
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Text(
                        'سعر التكلفة:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          showCostPrice ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            showCostPrice = !showCostPrice;
                          });
                        },
                      ),
                    ],
                  ),
                  Text(
                    showCostPrice ? '${totalCostWithWaste.toStringAsFixed(2)} دج' : '*** دج',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      textDirection: TextDirection.rtl,
                      children: [
                        const Text(
                          'سعر البيع:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        Text(
                          '${sellingPrice.toStringAsFixed(2)} دج',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        widget.model.totalCost = sellingPrice;
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'حفظ وإضافة للطلب',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
    
    new_content = content[:start_idx] + new_methods + content[end_idx:]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)

if __name__ == '__main__':
    patch_bottom_bar()
