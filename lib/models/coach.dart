import 'package:cloud_firestore/cloud_firestore.dart';

class Coach {
  final String id;
  final String name;
  final String bio;
  final String specialization;
  final String price;
  final String photoUrl;
  final double rating;
  final int ratingCount;

  Coach({
    required this.id,
    required this.name,
    required this.bio,
    required this.specialization,
    required this.price,
    required this.photoUrl,
    required this.rating,
    required this.ratingCount,
  });

  factory Coach.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    
    return Coach(
      id: doc.id,
      name: data['name']?.toString() ?? 'Имя не указано',
      bio: data['bio']?.toString() ?? '',
      specialization: data['specialization']?.toString() ?? '',
      price: data['price']?.toString() ?? '',
      photoUrl: data['photoUrl']?.toString() ?? '',
      rating: (data['rating'] ?? 5.0).toDouble(),
      ratingCount: (data['ratingCount'] ?? 0).toInt(),
    );
  }
}