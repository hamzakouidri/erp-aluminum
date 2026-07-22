import re

def strip_duplicates():
    path = 'lib/Commande/Systeme/material_consumption_screen.dart'
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # The string we want to remove
    str_to_remove = '''  void _showCalculationDetails(
    double totalProfilePrice, double totalGlassPrice, double shutterLamesPrice, 
    double coulisseSellPrice, double moteurTotalPrice, double manivelleSellingPrice, 
    double accessoryExtra, double finalSellingPrice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OU?O OUSU, O U,O-O3O O"'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_costMethod == CostMethod.linearMeter) ...[
                _detailRow('O3O1O O U,O"OU^U?USU,O O:', totalProfilePrice),
                _detailRow('O3O1O O U,OOO O:', totalGlassPrice),
              ] else if (_costMethod == CostMethod.squareMeter) ...[
                _detailRow('O3O1O O U,U+O U?OOc (U.A):', finalSellingPrice - shutterLamesPrice - coulisseSellPrice - moteurTotalPrice - manivelleSellingPrice - accessoryExtra),
              ] else ...[
                _detailRow('O3O1O O U,U+O U?OOc (U+O3O"Oc):', finalSellingPrice - shutterLamesPrice - coulisseSellPrice - moteurTotalPrice - manivelleSellingPrice - accessoryExtra),
              ],
              const Divider(),
              _detailRow('O U,O3OO O (U.A):', shutterLamesPrice),
              _detailRow('O U,O3UU:', coulisseSellPrice),
              _detailRow('O U,U.O-OU (U.O1 O U,OOUUSO"):', moteurTotalPrice),
              _detailRow('O U,U.O U+USU?O U, (U.O1 O U,OOUUSO"):', manivelleSellingPrice),
              const Divider(),
              _detailRow('OUO3O3U^O OO O OrO OOc (OB/Verrou):', accessoryExtra),
              const Divider(thickness: 2),
              _detailRow('O U,U.OU.U^O1 O U,OOU.O U,US:', finalSellingPrice, isBold: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OOU,O U,'),
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
          Text('${price.toStringAsFixed(2)} O_O', style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isBold ? Colors.green.shade700 : null)),
        ],
      ),
    );
  }'''
    
    # Let's remove the garbled string block from the top
    content = content.replace(str_to_remove, '')
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

if __name__ == '__main__':
    strip_duplicates()
