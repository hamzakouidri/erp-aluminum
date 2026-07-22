import sys

sys.stdout.reconfigure(encoding='utf-8')

# 1. Update commande.dart
path_comm = 'lib/Commande/commande.dart'
comm_content = open(path_comm, encoding='utf-8').read()

old_sheet_start = """      builder: (BuildContext ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ["""

new_sheet_start = """      builder: (BuildContext ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: ["""

comm_content = comm_content.replace(old_sheet_start, new_sheet_start)

old_sheet_end = """              ),
            ],
          ),
        );
      },"""

new_sheet_end = """              ),
            ],
          ),
        ),
      );
    },"""

# Replace only the specific occurrence at the end of the sheet
comm_content = comm_content.replace(old_sheet_end, new_sheet_end)
open(path_comm, 'w', encoding='utf-8').write(comm_content)
print("Updated commande.dart successfully!")


# 2. Update show_client.dart
path_client = 'lib/Cliente/show_client.dart'
client_content = open(path_client, encoding='utf-8').read()

old_client_title = """                              title: Row(
                                children: [
                                  Text(
                                    '${Localization.translate("Order", lang)} #${order["id"]}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? Colors.green.shade50
                                          : Colors.orange.shade50,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isPaid
                                            ? Colors.green.shade200
                                            : Colors.orange.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      isPaid
                                          ? Localization.translate(
                                              'Paid', lang)
                                          : Localization.translate(
                                              'Unpaid', lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isPaid
                                            ? Colors.green.shade700
                                            : Colors.orange.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),"""

new_client_title = """                              title: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${Localization.translate("Order", lang)} #${order["id"]}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? Colors.green.shade50
                                          : Colors.orange.shade50,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isPaid
                                            ? Colors.green.shade200
                                            : Colors.orange.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      isPaid
                                          ? Localization.translate(
                                              'Paid', lang)
                                          : Localization.translate(
                                              'Unpaid', lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isPaid
                                            ? Colors.green.shade700
                                            : Colors.orange.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),"""

client_content = client_content.replace(old_client_title, new_client_title)
open(path_client, 'w', encoding='utf-8').write(client_content)
print("Updated show_client.dart successfully!")
