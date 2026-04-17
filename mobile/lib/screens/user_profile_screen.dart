import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../models/listing.dart';
import '../config/api_config.dart';
import '../utils/formatters.dart';
import 'listing_detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;
  
  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _user;
  List<Listing> _listings = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _apiService.getUserProfile(widget.userId);
      if (mounted) {
        setState(() {
          _user = data['user'];
          final rawList = data['listings'] as List<dynamic>? ?? [];
          _listings = rawList.map((json) => Listing.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profil yüklenemedi: $e')),
        );
      }
    }
  }

  void _viewAvatar(String avatarUrl) {
    if (avatarUrl.isEmpty) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: avatarUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (_, __, ___) => _buildInitialAvatar(),
                ),
              ),
              Positioned(
                top: 50,
                right: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialAvatar() {
    final name = _user?['name'] ?? widget.userName;
    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.green[100],
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.green[800],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text(widget.userName, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.green[700],
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.green),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.userName),
          backgroundColor: Colors.green[700],
        ),
        body: const Center(child: Text('Kullanıcı bulunamadı')),
      );
    }

    final avatarPath = (_user!['avatar'] ?? '').toString();
    final hasAvatar = avatarPath.isNotEmpty;
    final avatarUrl = hasAvatar ? '${ApiConfig.uploadsUrl}/$avatarPath' : '';
    final name = _user!['name'] ?? widget.userName;
    final email = _user!['email'] ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(name, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green[700],
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(
                  color: Colors.green[700],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: () => _viewAvatar(avatarUrl),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green[200]!, width: 4),
                          ),
                          child: ClipOval(
                            child: hasAvatar
                                ? CachedNetworkImage(
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                    width: 100,
                                    height: 100,
                                    placeholder: (_, __) => Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => _buildInitialAvatar(),
                                  )
                                : _buildInitialAvatar(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.only(top: 28, bottom: 20, left: 20, right: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatItem(Icons.pets, _listings.length.toString(), 'Aktif İlan'),
                        Container(width: 1, height: 40, color: Colors.grey[300]),
                        _buildStatItem(Icons.calendar_today, _user!['createdAt'] != null ? _formatDate(_user!['createdAt']) : '-', 'Kayıt'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Kullanıcının İlanları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_listings.isEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('Bu kullanıcının henüz aktif\nbir ilanı bulunmuyor.', 
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final listing = _listings[index];
                      return _buildListingCard(listing);
                    },
                    childCount: _listings.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.green[700], size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
  
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}.${date.month}.${date.year}';
    } catch (_) {
      return '-';
    }
  }

  Widget _buildListingCard(Listing listing) {
    final isForSale = listing.listingType == 'satılık';
    final priceColor = const Color(0xFF212121);
    final listingTypeText = isForSale ? 'Satılık' : 'Sahiplendirme';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            opaque: false,
            pageBuilder: (context, animation, secondaryAnimation) =>
                ListingDetailScreen(listingId: listing.id),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: listing.images.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: '${ApiConfig.uploadsUrl}/${listing.images[0]}',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            placeholder: (_, __) => Container(color: Colors.grey[200]),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[100],
                              child: Icon(Icons.pets, size: 48, color: Colors.grey[300]),
                            ),
                          )
                        : Container(
                            color: Colors.grey[100],
                            child: Icon(Icons.pets, size: 48, color: Colors.grey[300]),
                          ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('${listing.views}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: isForSale ? Colors.green[50] : Colors.blue[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isForSale ? Colors.green[200]! : Colors.blue[200]!,
                          ),
                        ),
                        child: Text(
                          listingTypeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isForSale ? Colors.green[700] : Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          '${listing.city}, ${listing.district}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isForSale 
                        ? '${AppFormatters.formatPrice(listing.price)} ₺'
                        : 'Ücretsiz',
                    style: TextStyle(
                      color: priceColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
