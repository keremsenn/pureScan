import 'package:image/image.dart' as img;

class ImageProcessingService {
  ImageProcessingService._();

  static img.Image enhance(img.Image source) {
    final copy = img.Image.from(source);
    return img.adjustColor(copy, contrast: 1.25, brightness: 1.05);
  }
}
