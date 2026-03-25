class Listing {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String category;
  final String animalType;
  final String listingType;
  final double price;
  final String? age;
  final String? gender;
  final String? breed;
  final String? weight;
  final String? healthStatus;
  final bool vaccinated;
  final String? vaccines;
  final String city;
  final String district;
  final List<String> images;
  final String status;
  final int views;
  final DateTime createdAt;

  Listing({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.category,
    required this.animalType,
    required this.listingType,
    required this.price,
    this.age,
    this.gender,
    this.breed,
    this.weight,
    this.healthStatus,
    required this.vaccinated,
    this.vaccines,
    required this.city,
    required this.district,
    required this.images,
    required this.status,
    required this.views,
    required this.createdAt,
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      id: json['_id'],
      userId: json['user'] is String ? json['user'] : json['user']['_id'],
      title: json['title'],
      description: json['description'],
      category: json['category'],
      animalType: json['animalType'],
      listingType: json['listingType'],
      price: (json['price'] ?? 0).toDouble(),
      age: json['age'],
      gender: json['gender'],
      breed: json['breed'],
      weight: json['weight'],
      healthStatus: json['healthStatus'],
      vaccinated: json['vaccinated'] ?? false,
      vaccines: json['vaccines'],
      city: json['location']['city'],
      district: json['location']['district'],
      images: List<String>.from(json['images'] ?? []),
      status: json['status'],
      views: json['views'] ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
