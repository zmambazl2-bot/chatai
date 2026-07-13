import 'package:flutter/material.dart';

class DoctorImageUtils {
  static const String malePlaceholder = 'assets/images/doctor_placeholder.png';
  static const String femalePlaceholder = 'assets/images/doctor_placeholder1.png';

  static bool isFemale(dynamic value) {
    final gender = (value ?? '').toString().trim().toLowerCase();
    return gender == 'female' ||
        gender == 'f' ||
        gender == 'woman' ||
        gender == 'أنثى' ||
        gender == 'انثى' ||
        gender == 'طبيبة' ||
        gender.contains('female') ||
        gender.contains('انث') ||
        gender.contains('أنث');
  }

  static String placeholderForGender(dynamic gender) =>
      isFemale(gender) ? femalePlaceholder : malePlaceholder;

  static ImageProvider imageProvider({String? imageUrl, dynamic gender}) {
    final cleanUrl = imageUrl?.trim() ?? '';
    if (cleanUrl.isNotEmpty) return NetworkImage(cleanUrl);
    return AssetImage(placeholderForGender(gender));
  }
}