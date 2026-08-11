import 'package:flutter/material.dart';

class ArtworkThumbnail extends StatelessWidget {
  const ArtworkThumbnail({
    super.key,
    required this.image,
    required this.size,
    this.circle = false,
  });

  final Future<ImageProvider?>? image;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      'app_icon.ico',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    final artwork = image == null
        ? fallback
        : FutureBuilder<ImageProvider?>(
            future: image,
            builder: (context, snapshot) {
              final provider = snapshot.data;
              if (snapshot.connectionState != ConnectionState.done ||
                  snapshot.hasError ||
                  provider == null) {
                return fallback;
              }
              return Image(
                image: provider,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              );
            },
          );

    return SizedBox(
      width: size,
      height: size,
      child: circle
          ? ClipOval(child: artwork)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: artwork,
            ),
    );
  }
}
