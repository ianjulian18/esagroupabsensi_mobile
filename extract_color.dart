import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File(r'C:\Users\ianju\Downloads\PT Arina Multikarya.png');
  final image = img.decodeImage(file.readAsBytesSync())!;
  
  final colors = <int, int>{};
  for (final pixel in image) {
    if (pixel.a == 0) continue;
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final color = (r << 16) | (g << 8) | b;
    // Skip very light colors (backgrounds)
    if (r > 240 && g > 240 && b > 240) continue;
    colors[color] = (colors[color] ?? 0) + 1;
  }
  
  final sorted = colors.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  print('Top 5 colors:');
  for (var i = 0; i < 5 && i < sorted.length; i++) {
    print('#${sorted[i].key.toRadixString(16).padLeft(6, '0')} (count: ${sorted[i].value})');
  }
}
