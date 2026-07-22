import re

path_preview = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_preview_screen.dart'

with open(path_preview, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update _buildTopHeader
OLD_HEADER = """  Widget _buildTopHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Text(
            'DEVIS',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: _blue,
              letterSpacing: 1.2,
            ),
          ),
        ),"""

NEW_HEADER = """  Widget _buildTopHeader() {
    final title = data.isProForma
        ? t('فاتورة رسمية / أولية')
        : (data.isPartial ? 'DEVIS PARTIEL' : 'DEVIS');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: data.isProForma ? 22 : 34,
              fontWeight: FontWeight.w800,
              color: _blue,
              fontFamily: 'Cairo',
              letterSpacing: data.isProForma ? 0.0 : 1.2,
            ),
          ),
        ),"""

assert OLD_HEADER in code, "_buildTopHeader not found in devis_preview_screen.dart"
code = code.replace(OLD_HEADER, NEW_HEADER, 1)

# 2. Update _buildParties to include official supplier fields
OLD_PARTIES = """  Widget _buildParties() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _partyBlock('FOURNISSEUR', [
            data.workshop.name,
            if (data.workshop.phone.isNotEmpty) data.workshop.phone,
            if (data.workshop.address.isNotEmpty) data.workshop.address,
          ]),
        ),"""

NEW_PARTIES = """  Widget _buildParties() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _partyBlock('FOURNISSEUR', [
            data.workshop.name,
            if (data.workshop.phone.isNotEmpty) data.workshop.phone,
            if (data.workshop.address.isNotEmpty) data.workshop.address,
            if (data.isProForma) ...[
              if (data.workshop.rc.isNotEmpty) 'RC: ${data.workshop.rc}',
              if (data.workshop.nif.isNotEmpty) 'NIF: ${data.workshop.nif}',
              if (data.workshop.nis.isNotEmpty) 'NIS: ${data.workshop.nis}',
              if (data.workshop.ai.isNotEmpty) 'AI: ${data.workshop.ai}',
              if (data.workshop.rib.isNotEmpty) 'RIB: ${data.workshop.rib}',
            ],
          ]),
        ),"""

assert OLD_PARTIES in code, "_buildParties not found in devis_preview_screen.dart"
code = code.replace(OLD_PARTIES, NEW_PARTIES, 1)

# 3. Update _buildTableHeader to optionally skip image column
OLD_TABLE_HEADER = """  Widget _buildTableHeader() {
    final hidePrices = data.hidePrices;
    return Container(
      color: _headerBlue,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 88, child: Text('Image', style: _headerStyle)),
          Expanded(flex: hidePrices ? 8 : 4, child: const Text('Désignation', style: _headerStyle)),"""

NEW_TABLE_HEADER = """  Widget _buildTableHeader() {
    final hidePrices = data.hidePrices;
    return Container(
      color: _headerBlue,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          if (!data.isProForma)
            const SizedBox(width: 88, child: Text('Image', style: _headerStyle)),
          Expanded(flex: hidePrices ? 8 : 4, child: const Text('Désignation', style: _headerStyle)),"""

assert OLD_TABLE_HEADER in code, "_buildTableHeader not found in devis_preview_screen.dart"
code = code.replace(OLD_TABLE_HEADER, NEW_TABLE_HEADER, 1)

# 4. Update _buildItemRow to optionally skip image and details
OLD_ITEM_ROW_BODY = """              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Opacity(
                    opacity: item.isReplaced ? 0.6 : 1.0,
                    child: _buildItemImage(item),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: hidePrices ? 8 : 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...item.details.map(
                        (d) => Text(
                          d,
                          style: TextStyle(
                            fontSize: 11,
                            color: detailColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),"""

NEW_ITEM_ROW_BODY = """              children: [
                if (!data.isProForma) ...[
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: Opacity(
                      opacity: item.isReplaced ? 0.6 : 1.0,
                      child: _buildItemImage(item),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: hidePrices ? 8 : 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...(data.isProForma
                          ? item.details.where((line) {
                              final lower = line.toLowerCase();
                              return lower.contains('largeur') ||
                                  lower.contains('width') ||
                                  lower.contains('العرض') ||
                                  lower.contains('الارتفاع') ||
                                  lower.contains('hauteur') ||
                                  lower.contains('height');
                            }).toList()
                          : item.details)
                          .map(
                        (d) => Text(
                          d,
                          style: TextStyle(
                            fontSize: 11,
                            color: detailColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),"""

assert OLD_ITEM_ROW_BODY in code, "OLD_ITEM_ROW_BODY not found in devis_preview_screen.dart"
code = code.replace(OLD_ITEM_ROW_BODY, NEW_ITEM_ROW_BODY, 1)

with open(path_preview, 'w', encoding='utf-8') as f:
    f.write(code)
print("devis_preview_screen.dart updated successfully.")
