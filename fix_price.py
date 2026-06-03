import sys

with open('lib/Screen/price_management_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Make canChangePrices a getter in the State class
old_state_start = '''class _PriceManagementScreenState extends State<PriceManagementScreen> {
  final SqlDatabase db = SqlDatabase();'''

new_state_start = '''class _PriceManagementScreenState extends State<PriceManagementScreen> {
  final SqlDatabase db = SqlDatabase();
  bool get canChangePrices => Provider.of<AppSettingsProvider>(context, listen: false).canChangePrices();'''

content = content.replace(old_state_start, new_state_start)

# Remove the local variable from the build method
old_build_start = '''  @override
  Widget build(BuildContext context) {
    final appSettings = Provider.of<AppSettingsProvider>(context);
    bool isDark = appSettings.isDarkMode;
    bool canChangePrices = appSettings.canChangePrices();'''

new_build_start = '''  @override
  Widget build(BuildContext context) {
    final appSettings = Provider.of<AppSettingsProvider>(context);
    bool isDark = appSettings.isDarkMode;'''

content = content.replace(old_build_start, new_build_start)

with open('lib/Screen/price_management_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
