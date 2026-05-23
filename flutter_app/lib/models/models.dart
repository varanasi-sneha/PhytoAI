class PredictionResult {
  final String disease;
  final String displayName;
  final double confidence;
  final String plantType;
  final Map<String, dynamic>? distribution;
  final bool isBlurry;
  final double blurScore;

  PredictionResult({
    required this.disease,
    required this.displayName,
    required this.confidence,
    required this.plantType,
    this.distribution,
    this.isBlurry = false,
    this.blurScore = 0.0,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      disease: json['disease'] ?? '',
      displayName: json['display_name'] ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      plantType: json['plant_type'] ?? '',
      distribution: json['distribution'] as Map<String, dynamic>?,
      isBlurry: json['is_blurry'] ?? false,
      blurScore: (json['blur_score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class UserProfile {
  final String email;
  final String? firstName;
  final String? lastName;
  final String? profileImagePath;

  UserProfile({
    required this.email,
    this.firstName,
    this.lastName,
    this.profileImagePath,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      email: json['email'] ?? '',
      firstName: json['first_name'],
      lastName: json['last_name'],
      profileImagePath: json['profile_image_path'],
    );
  }
}

class HistoryItem {
  final String id;
  final String prediction;
  final String displayName;
  final double confidence;
  final String plantType;
  final DateTime createdAt;

  HistoryItem({
    required this.id,
    required this.prediction,
    required this.displayName,
    required this.confidence,
    required this.plantType,
    required this.createdAt,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id']?.toString() ?? '',
      prediction: json['prediction'] ?? '',
      displayName: json['display_name'] ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      plantType: json['plant_type'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}