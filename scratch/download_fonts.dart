import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print("Downloading Cairo-Regular.ttf...");
  try {
    final regUrl = Uri.parse("https://github.com/google/fonts/raw/main/ofl/cairo/Cairo-Regular.ttf");
    final regResponse = await http.get(regUrl);
    if (regResponse.statusCode == 200) {
      await File("assets/fonts/Cairo-Regular.ttf").writeAsBytes(regResponse.bodyBytes);
      print("Cairo-Regular.ttf downloaded successfully!");
    } else {
      print("Failed to download Cairo-Regular.ttf: ${regResponse.statusCode}");
    }
  } catch (e) {
    print("Error downloading Cairo-Regular.ttf: $e");
  }

  print("Downloading Cairo-Bold.ttf...");
  try {
    final boldUrl = Uri.parse("https://github.com/google/fonts/raw/main/ofl/cairo/Cairo-Bold.ttf");
    final boldResponse = await http.get(boldUrl);
    if (boldResponse.statusCode == 200) {
      await File("assets/fonts/Cairo-Bold.ttf").writeAsBytes(boldResponse.bodyBytes);
      print("Cairo-Bold.ttf downloaded successfully!");
    } else {
      print("Failed to download Cairo-Bold.ttf: ${boldResponse.statusCode}");
    }
  } catch (e) {
    print("Error downloading Cairo-Bold.ttf: $e");
  }
}
