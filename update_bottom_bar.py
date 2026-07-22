import re

with open('lib/Commande/Systeme/material_consumption_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

replacement = '''  void _showCalculationDetails(
    double totalProfilePrice, double totalGlassPrice, double shutterLamesPrice, 
    double coulisseSellPrice, double moteurTotalPrice, double manivelleSellingPrice, 
    double accessoryExtra, double finalSellingPrice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفاصيل الحساب'),
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
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('${price.toStringAsFixed(2)} دج', style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isBold ? Colors.green.shade700 : null)),
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
        } else if (nameLower.contains('moteur') || nameLower.contains('محرك')) {
          hasMoteur = true;
          moteurTotalPrice += item.total + (_moteurInstallFee * widget.model.quantity);
        } else if (nameLower.contains('manivelle') || nameLower.contains('مانيفال')) {
          hasManivelle = true;
          manivelleSellingPrice += item.total + (_manivelleSellingPrice * widget.model.quantity);
        } else if (nameLower.contains('coulisse') || nameLower.contains('سكة') || nameLower.contains('سكك')) {
          hasCoulisse = true;
        }
      }

      if (hasLames) {
        double wM = widget.model.width / 1000.0;
        double hM = widget.model.height / 1000.0;
        shutterLamesPrice = wM * hM * _pricePerShutterSqm * widget.model.quantity;
      }
      if (hasCoulisse) {
        coulisseSellPrice = _coulisseSellPricePerUnit * widget.model.quantity;
      }

      double mechanismPrice = 0.0;
      if (hasMoteur) {
        mechanismPrice = moteurTotalPrice;
      } else if (hasManivelle) {
        mechanismPrice = manivelleSellingPrice;
      }

      shutterSellingPrice = shutterLamesPrice + coulisseSellPrice + mechanismPrice;
    }

    if (_costMethod == CostMethod.percentage) {
      sellingPrice = totalCostWithWaste * (1 + _profitMargin / 100);
    } else if (_costMethod == CostMethod.squareMeter) {
      double areaSqm = (widget.model.width / 1000.0) * (widget.model.height / 1000.0);
      sellingPrice = (_pricePerSqm * areaSqm * widget.model.quantity) + shutterSellingPrice;
    } else if (_costMethod == CostMethod.linearMeter) {
      for (var item in items) {
        if (item.isActive) {
          if (item.category == 'profile') {
            final nameLower = item.originalName.toLowerCase();
            final isIron = nameLower.contains('حديد') || nameLower.contains('renfort');
            if (isIron) continue;

            final isFrame =
                nameLower.contains('إطار') ||
                nameLower.contains('اطار') ||
                nameLower.contains('frame');
            final isSash =
                nameLower.contains('ظلفة') ||
                nameLower.contains('ظلفه') ||
                nameLower.contains('sash');
            final isMullion =
                nameLower.contains('تقسيم') || nameLower.contains('mullion');
            final isBatmo =
                nameLower.contains('باتمو') || nameLower.contains('batmo') || nameLower.contains('باتبو') || nameLower.contains('batbo');

            if (isFrame || isSash || isMullion || isBatmo) {
              if (item.pieces != null) {
                totalProfileMeters += item.pieces!.fold<double>(
                  0.0,
                  (sum, p) => sum + p,
                );
              } else if (item.length != null) {
                totalProfileMeters += (item.length! / 1000.0) * item.quantity;
              }
            }
          } else if (item.category == 'glass') {
            totalGlassPrice += item.total;
          } else if (item.category == 'accessory' || item.category == 'hardware' || item.category == 'accessories') {
            final nameLower = item.originalName.toLowerCase();
            if (nameLower.contains('ob') && !nameLower.contains('demi')) {
               accessoryExtra += (_obInstallFee * widget.model.quantity);
            }
            if (nameLower.contains('demi')) {
               accessoryExtra += (_demiOBInstallFee * widget.model.quantity);
            }
            if (nameLower.contains('verrou')) {
               accessoryExtra += (_verrouInstallFee * widget.model.quantity);
            }
          }
        }
      }
      
      sellingPrice = (totalProfileMeters * _pricePerLinearMeter) + totalGlassPrice + shutterSellingPrice + accessoryExtra;
    }

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
            if (_isPriceVisible)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  f"سعر البيع: {sellingPrice.toStringAsFixed(2)} دج  ×{widget.model.quantity}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isPriceVisible ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade700,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPriceVisible = !_isPriceVisible;
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showCalculationDetails(
                        totalProfileMeters * _pricePerLinearMeter, totalGlassPrice, shutterLamesPrice, coulisseSellPrice,
                        moteurTotalPrice, manivelleSellingPrice, accessoryExtra, sellingPrice
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade100,
                        foregroundColor: Colors.blueGrey.shade800,
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: const Text('تفاصيل الحساب', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        widget.model.totalCost = sellingPrice;
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: const Text('إضافة الطلبية', style: TextStyle(fontSize: 12)),
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

replacement = replacement.replace('f"سعر', '"سعر').replace('{sellingPrice', '${sellingPrice').replace('{widget.model', '${widget.model')

pattern = re.compile(r"  Widget _buildBottomBar\(List<BomItem> items\) \{.*?(?=  Widget _header\(\) \{)", re.DOTALL)
new_content = pattern.sub(replacement, content)

with open('lib/Commande/Systeme/material_consumption_screen.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)
