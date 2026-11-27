import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _demoPhotos = {
  'demo-cebu': 'finding_rectangle16.png',
  'demo-palawan': 'finding_rectangle17.png',
  'demo-manila': 'finding_rectangle18.png',
};

Map<String, dynamic> resolveAmigoPhoto(
  SupabaseClient client,
  Map<String, dynamic> row,
) {
  final path = row['photo_path'] as String?;
  return path == null
      ? row
      : {
          ...row,
          'storage_photo_url': client.storage
              .from('amigo-photos')
              .getPublicUrl(path),
        };
}

class AmigoPhoto extends StatelessWidget {
  const AmigoPhoto(
    this.amigo, {
    super.key,
    required this.width,
    required this.height,
    this.radius = 20,
  });
  final Map<String, dynamic> amigo;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = amigo['photo_url'] as String?;
    final asset = amigo['is_test'] == true ? _demoPhotos[photo] : null;
    final uploaded = amigo['storage_photo_url'] as String?;
    final networkPhoto = uploaded ?? photo;
    final uri = Uri.tryParse(networkPhoto ?? '');
    final usableUrl =
        uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || (uploaded != null && uri.scheme == 'http'));
    final placeholder = ColoredBox(
      color: const Color(0xFFE9DCCF),
      child: Center(
        child: Icon(
          Icons.person_outline,
          size: height / 2,
          color: const Color(0xFF6E8968),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: asset != null
            ? Image.asset('assets/figma/$asset', fit: BoxFit.cover)
            : usableUrl
            ? Image.network(
                networkPhoto!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}
