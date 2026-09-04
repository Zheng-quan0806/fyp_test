import 'dart:typed_data';

import 'package:flutter/material.dart';

class ExpandableImage extends StatelessWidget {
  final Uint8List? bytes;
  final String? url;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;

  const ExpandableImage.memory(
    Uint8List this.bytes, {
    super.key,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 12,
  }) : url = null;

  const ExpandableImage.network(
    String this.url, {
    super.key,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 12,
  }) : bytes = null;

  Image _image({required BoxFit imageFit}) {
    if (bytes != null) {
      return Image.memory(bytes!, fit: imageFit);
    }
    return Image.network(
      url!,
      fit: imageFit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 42),
      ),
    );
  }

  void _openPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          backgroundColor: const Color(0xFF09090B),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: screen.width * 0.9,
            height: screen.height * 0.86,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 6,
                    boundaryMargin: const EdgeInsets.all(80),
                    child: Center(child: _image(imageFit: BoxFit.contain)),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton.filled(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(dialogContext),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Positioned(
                  left: 16,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Text(
                        'Pinch or scroll to zoom',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Click to enlarge',
      child: InkWell(
        onTap: () => _openPreview(context),
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: SizedBox(
                width: width,
                height: height,
                child: _image(imageFit: fit),
              ),
            ),
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.zoom_in,
                  color: Colors.white,
                  size: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
