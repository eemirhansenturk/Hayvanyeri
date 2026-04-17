import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../config/api_config.dart';
import '../utils/formatters.dart';
import 'chat_screen.dart';
import 'user_profile_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  final String listingId;
  final String? heroTag;

  const ListingDetailScreen({
    super.key, 
    required this.listingId,
    this.heroTag,
  });

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _listing;
  bool _isLoading = true;
  int _currentImageIndex = 0;

  // ── Swipe-down-to-dismiss state ──
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _dismissDragY = ValueNotifier<double>(0.0);
  bool _isDismissDragging = false;
  Offset? _dismissPointerStart;
  int _dismissPointerId = -1;
  late AnimationController _dismissSnapCtrl;
  Animation<double>? _dismissSnapAnim;

  bool get _isAtScrollTop =>
      !_scrollController.hasClients || _scrollController.offset <= 0;

  @override
  void initState() {
    super.initState();
    _loadListing();
    _dismissSnapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_dismissSnapAnim != null && mounted) {
          _dismissDragY.value = _dismissSnapAnim!.value;
        }
      });
  }

  Future<void> _toggleFavorite() async {
    try {
      await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).toggleFavorite(widget.listingId);
      
      // Favori sayısını güncelle
      await _loadListing();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favori işlemi başarısız')),
        );
      }
    }
  }

  Future<void> _loadListing() async {
    try {
      final data = await _apiService.getListing(widget.listingId);
      if (mounted) {
        setState(() {
          _listing = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dismissSnapCtrl.dispose();
    super.dispose();
  }

  void _openFullScreenGallery(List<String> images, int initialIndex) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, __) => _FullScreenGalleryView(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  // ── Dismiss drag handlers ──
  void _onDismissPointerDown(PointerDownEvent event) {
    if (_isDismissDragging) return;
    _dismissPointerStart = event.position;
    _dismissPointerId = event.pointer;
  }

  void _onDismissPointerMove(PointerMoveEvent event) {
    if (event.pointer != _dismissPointerId) return;
    if (_dismissPointerStart == null) return;

    final delta = event.position - _dismissPointerStart!;

    // Only start dismiss if at scroll top and dragging downward with dominant vertical movement
    if (!_isDismissDragging) {
      if (_isAtScrollTop &&
          delta.dy > 20 &&
          delta.dy > delta.dx.abs() * 2) {
        _isDismissDragging = true;
        _dismissSnapCtrl.stop();
      }
    }

    if (_isDismissDragging) {
      // Only allow downward drag (positive values)
      final newY = (delta.dy - 20).clamp(0.0, double.infinity);
      _dismissDragY.value = newY;
    }
  }

  void _onDismissPointerUp(PointerUpEvent event) {
    if (event.pointer != _dismissPointerId) return;

    if (_isDismissDragging) {
      _isDismissDragging = false;
      _dismissPointerStart = null;
      _dismissPointerId = -1;

      if (_dismissDragY.value > 120) {
        // Animate the card entirely off the screen smoothly, then pop.
        final screenHeight = MediaQuery.of(context).size.height;
        _dismissSnapAnim = Tween<double>(
          begin: _dismissDragY.value,
          end: screenHeight,
        ).animate(CurvedAnimation(
          parent: _dismissSnapCtrl,
          curve: Curves.easeOutCubic,
        ));
        
        _dismissSnapCtrl.forward(from: 0).then((_) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        // Snap back
        _dismissSnapAnim = Tween<double>(
          begin: _dismissDragY.value,
          end: 0.0,
        ).animate(CurvedAnimation(
          parent: _dismissSnapCtrl,
          curve: Curves.easeOutCubic,
        ));
        _dismissSnapCtrl.forward(from: 0);
      }
    } else {
      _dismissPointerStart = null;
      _dismissPointerId = -1;
    }
  }

  void _onDismissPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _dismissPointerId) return;
    if (_isDismissDragging) {
      _isDismissDragging = false;
      _dismissSnapAnim = Tween<double>(
        begin: _dismissDragY.value,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _dismissSnapCtrl,
        curve: Curves.easeOutCubic,
      ));
      _dismissSnapCtrl.forward(from: 0);
    }
    _dismissPointerStart = null;
    _dismissPointerId = -1;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_listing == null) {
      return Scaffold(
        appBar: AppBar(elevation: 0),
        body: const Center(child: Text('İlan bulunamadı')),
      );
    }

    final images = List<String>.from(_listing!['images'] ?? []);
    final user = _listing!['user'];
    final isSatilik =
        _listing!['listingType'] == 'satılık' ||
        _listing!['listingType'] == 'kurbanlık' ||
        _listing!['listingType'] == 'kiralık';

    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    final bool isOwner =
        currentUser != null && currentUser['_id'] == user['_id'];

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isFavorited = authProvider.isFavorite(widget.listingId);

        return ValueListenableBuilder<double>(
          valueListenable: _dismissDragY,
          builder: (context, dismissDragY, child) {
            // ── Dismiss drag progress (0.0 → 1.0) ──
            final dismissProgress = (dismissDragY / 300).clamp(0.0, 1.0);
            final scale = 1.0 - (dismissProgress * 0.08);

            return Listener(
              onPointerDown: _onDismissPointerDown,
              onPointerMove: _onDismissPointerMove,
              onPointerUp: _onDismissPointerUp,
              onPointerCancel: _onDismissPointerCancel,
              behavior: HitTestBehavior.translucent,
              child: Container(
                color: Colors.transparent,
                child: Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.diagonal3Values(scale, scale, 1.0)
                    ..setTranslationRaw(0, dismissDragY, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(dismissProgress * 20),
                    child: Container(
                      color: dismissProgress > 0
                          ? Colors.grey[50]!.withOpacity(1.0 - dismissProgress)
                          : Colors.grey[50],
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: CustomScrollView(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: 350.0,
                  floating: false,
                  pinned: true,
                  iconTheme: const IconThemeData(
                    color: Colors.white,
                  ),
                  backgroundColor: Colors.green[700],
                  actions: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOwner)
                            // Kendi ilanı - tıklanınca uyarı göster
                            IconButton(
                              icon: const Icon(
                                Icons.favorite_border,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Kendi ilanınızı favoriye alamazsınız'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            )
                          else
                            // Başkasının ilanı - aktif
                            IconButton(
                              icon: Icon(
                                isFavorited ? Icons.favorite : Icons.favorite_border,
                                color: isFavorited ? Colors.red : Colors.white,
                              ),
                              onPressed: _toggleFavorite,
                            ),
                          if ((_listing!['favoriteCount'] ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${_listing!['favoriteCount']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Paylaşma özelliği yakında eklenecek'),
                        ),
                      );
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (images.isNotEmpty)
                        PageView.builder(
                          itemCount: images.length,
                          onPageChanged: (index) =>
                              setState(() => _currentImageIndex = index),
                          itemBuilder: (context, index) {
                            final imageWidget = CachedNetworkImage(
                              imageUrl:
                                  '${ApiConfig.uploadsUrl}/${images[index]}',
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, _) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.pets, size: 100),
                              ),
                            );
                            return GestureDetector(
                              onTap: () =>
                                  _openFullScreenGallery(images, index),
                              child: imageWidget,
                            );
                          },
                        )
                      else
                        Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(
                              Icons.pets,
                              size: 100,
                              color: Colors.grey,
                            ),
                          ),
                        ),

                      // Gradient Overlay for AppBar text visibility
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 100,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Image Indicator
                      if (images.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              images.length,
                              (index) => Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: _currentImageIndex == index ? 24 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: _currentImageIndex == index
                                      ? Colors.green
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // View Count
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.remove_red_eye,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_listing!['views']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50], // Match the background
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  transform: Matrix4.translationValues(0.0, -28.0, 0.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // MAIN CONTENT CARD
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // TITLE
                            Text(
                              _listing!['title'],
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                                letterSpacing: -0.5,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 20),
                            
                            // PRICE WITH TYPE BADGE
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isSatilik 
                                        ? [Colors.green[50]!, Colors.green[100]!.withOpacity(0.3)]
                                        : [Colors.blue[50]!, Colors.blue[100]!.withOpacity(0.3)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSatilik ? Colors.green[200]! : Colors.blue[200]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isSatilik ? Icons.payments : Icons.volunteer_activism,
                                          color: isSatilik ? Colors.green[700] : Colors.blue[700],
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Fiyat',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isSatilik
                                                ? '${AppFormatters.formatPrice(_listing!['price'])} ₺'
                                                : 'Ücretsiz',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              color: isSatilik ? Colors.green[700] : Colors.blue[700],
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // TYPE BADGE ON TOP RIGHT (RIBBON STYLE)
                                Positioned(
                                  top: -6,
                                  right: 16,
                                  child: Transform.rotate(
                                    angle: 0.05, // Slight rotation for casual look
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.0, end: 1.0),
                                      duration: const Duration(milliseconds: 800),
                                      curve: Curves.elasticOut,
                                      builder: (context, value, child) {
                                        return Transform.scale(
                                          scale: value,
                                          child: Transform.rotate(
                                            angle: (1 - value) * 0.5,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: isSatilik 
                                              ? [Colors.green[500]!, Colors.green[700]!]
                                              : [Colors.blue[500]!, Colors.blue[700]!],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (isSatilik ? Colors.green : Colors.blue).withOpacity(0.5),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                              spreadRadius: 1,
                                            ),
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.15),
                                              blurRadius: 8,
                                              offset: const Offset(2, 4),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _listing!['listingType'] == 'satılık' 
                                                ? Icons.sell_rounded
                                                : _listing!['listingType'] == 'kiralık'
                                                  ? Icons.key_rounded
                                                  : _listing!['listingType'] == 'kurbanlık'
                                                    ? Icons.mosque_rounded
                                                    : Icons.card_giftcard_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _listing!['listingType'].toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                letterSpacing: 1.0,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black26,
                                                    offset: Offset(1, 1),
                                                    blurRadius: 2,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // LOCATION & DATE
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.location_on, size: 18, color: Colors.green[700]),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Konum',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _listing!['location'] != null
                                                  ? '${_listing!['location']['city']}, ${_listing!['location']['district']}'
                                                  : 'Konum Belirtilmemiş',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFF2D2D2D),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    height: 1,
                                    color: Colors.grey[200],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.access_time, size: 18, color: Colors.grey[700]),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'İlan Tarihi',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateFormat('dd.MM.yyyy').format(DateTime.parse(_listing!['createdAt'])),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[800],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // FEATURES CARD
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.info_outline, size: 20, color: Colors.green[700]),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Özellikler',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildFeaturesGrid(),
                          ],
                        ),
                      ),
                      
                      // HEALTH INFO CARD
                      if ((_listing!['healthStatus'] != null && _listing!['healthStatus'].toString().isNotEmpty) || 
                          (_listing!['vaccines'] != null && _listing!['vaccines'].toString().isNotEmpty))
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.health_and_safety_outlined, size: 20, color: Colors.red[600]),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Sağlık Bilgileri',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (_listing!['healthStatus'] != null && _listing!['healthStatus'].toString().isNotEmpty) ...[
                                Builder(
                                  builder: (context) {
                                    final healthStatusFull = _listing!['healthStatus'].toString();
                                    final isHealthy = healthStatusFull.toLowerCase().startsWith('sağlıklı');
                                    
                                    // Sağlıksız ise açıklamayı al (örn: "Sağlıksız: açıklama" -> "açıklama")
                                    String? explanation;
                                    if (!isHealthy && healthStatusFull.contains(':')) {
                                      explanation = healthStatusFull.split(':').skip(1).join(':').trim();
                                    }
                                    
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        gradient: isHealthy
                                            ? LinearGradient(
                                                colors: [Colors.red[50]!, Colors.pink[50]!],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              )
                                            : LinearGradient(
                                                colors: [Colors.grey[100]!, Colors.grey[50]!],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isHealthy ? Colors.red[100]! : Colors.grey[800]!,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: isHealthy ? Colors.red[200]! : Colors.grey[700]!,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.favorite,
                                                  size: 18,
                                                  color: isHealthy ? Colors.red[600] : Colors.grey[800],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                'Sağlık Durumu',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: isHealthy ? Colors.red[800] : Colors.grey[900],
                                                ),
                                              ),
                                              const Spacer(),
                                              AnimatedContainer(
                                                duration: const Duration(milliseconds: 300),
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: isHealthy ? Colors.red[600] : Colors.grey[800],
                                                  borderRadius: BorderRadius.circular(20),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: (isHealthy ? Colors.red[600]! : Colors.grey[800]!).withOpacity(0.3),
                                                      blurRadius: 8,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  isHealthy ? 'Sağlıklı' : 'Sağlıksız',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (explanation != null && explanation.isNotEmpty) ...[
                                            const SizedBox(height: 16),
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: 'Açıklama: ',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: explanation,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      color: Colors.grey[800],
                                                      height: 1.5,
                                                      fontWeight: FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                              if (_listing!['vaccines'] != null && _listing!['vaccines'].toString().isNotEmpty) ...[
                                if (_listing!['healthStatus'] != null && _listing!['healthStatus'].toString().isNotEmpty)
                                  const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey[200]!, width: 1.5),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.grey[300]!, width: 2),
                                            ),
                                            child: Icon(Icons.vaccines, size: 18, color: Colors.grey[700]),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Aşılar',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: _listing!['vaccines'].toString().split(',').map<Widget>((v) => Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            children: [
                                              Icon(Icons.check_circle, size: 16, color: Colors.green[600]),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  v.trim(),
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[800],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      // DESCRIPTION CARD
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.description_outlined, size: 20, color: Colors.green[700]),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Açıklama',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _listing!['description'],
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Color(0xFF3D3D3D),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // SELLER PROFILE CARD WITH ACTION BUTTONS
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // PROFILE INFO
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                      userId: user['_id'],
                                      userName: user['name'],
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: [Colors.green[400]!, Colors.green[600]!],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.green.withOpacity(0.3),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          padding: const EdgeInsets.all(3),
                                          child: CircleAvatar(
                                            radius: 34,
                                            backgroundColor: Colors.white,
                                            child: CircleAvatar(
                                              radius: 32,
                                              backgroundColor: Colors.grey[100],
                                              backgroundImage: (user['avatar'] != null && user['avatar'].toString().isNotEmpty)
                                                  ? NetworkImage('${ApiConfig.uploadsUrl}/${user['avatar']}')
                                                  : null,
                                              child: (user['avatar'] == null || user['avatar'].toString().isEmpty)
                                                  ? Text(
                                                      user['name'][0].toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 24,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.green[700],
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Colors.green[400]!, Colors.green[600]!],
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white, width: 2.5),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.green.withOpacity(0.4),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(Icons.verified, size: 14, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user['name'],
                                            style: const TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1A1A1A),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(Icons.person_rounded, size: 14, color: Colors.grey[600]),
                                              const SizedBox(width: 6),
                                              Text(
                                                'İlan Sahibi',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            // DIVIDER
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                            ),
                            
                            // ACTION BUTTONS
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // CALL BUTTON
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          if (user['phone'] != null && user['phone'].toString().isNotEmpty) {
                                            final Uri url = Uri(
                                              scheme: 'tel',
                                              path: user['phone'].toString().trim(),
                                            );
                                            try {
                                              await launchUrl(url, mode: LaunchMode.externalApplication);
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Arama başlatılamadı')),
                                                );
                                              }
                                            }
                                          } else {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('İlan sahibinin telefon numarası bulunmuyor')),
                                              );
                                            }
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(14),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: Colors.grey[300]!, width: 2),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.call_rounded, color: Colors.grey[800], size: 20),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Ara',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  if (!isOwner) ...[
                                    const SizedBox(width: 12),
                                    // MESSAGE BUTTON
                                    Expanded(
                                      flex: 2,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ChatScreen(
                                                  listingId: widget.listingId,
                                                  listingTitle: (_listing?['title'] ?? '').toString(),
                                                  receiverId: user['_id'],
                                                  receiverName: user['name'],
                                                  receiverAvatar: (user['avatar'] ?? '').toString(),
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(14),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Colors.green[500]!, Colors.green[700]!],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.green.withOpacity(0.4),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.message_rounded, color: Colors.white, size: 20),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Mesaj Gönder',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                        const SizedBox(height: 24),
                      ],
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

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  Widget _buildFeaturesGrid() {
    final features = <Map<String, dynamic>>[];
    
    features.add({'icon': Icons.category_outlined, 'title': 'Kategori', 'value': _capitalize(_listing!['category'] ?? '')});
    features.add({'icon': Icons.pets_outlined, 'title': 'Tür', 'value': _capitalize(_listing!['animalType'] ?? '')});
    
    if (_listing!['breed'] != null && _listing!['breed'].toString().isNotEmpty) {
      features.add({'icon': Icons.auto_awesome_outlined, 'title': 'Irk', 'value': _listing!['breed']});
    }
    if (_listing!['age'] != null && _listing!['age'].toString().isNotEmpty) {
      features.add({'icon': Icons.cake_outlined, 'title': 'Yaş', 'value': _listing!['age']});
    }
    if (_listing!['gender'] != null) {
      features.add({
        'icon': _listing!['gender'].toString().toLowerCase() == 'dişi' ? Icons.female_outlined : Icons.male_outlined,
        'title': 'Cinsiyet',
        'value': _capitalize(_listing!['gender'])
      });
    }
    if (_listing!['weight'] != null && _listing!['weight'].toString().isNotEmpty) {
      features.add({'icon': Icons.scale_outlined, 'title': 'Ağırlık', 'value': '${_listing!['weight']} kg'});
    }

    return Column(
      children: [
        for (int i = 0; i < features.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < features.length ? 12 : 0),
            child: Row(
              children: [
                Expanded(
                  child: _buildFeatureChip(
                    features[i]['icon'],
                    features[i]['title'],
                    features[i]['value'],
                  ),
                ),
                if (i + 1 < features.length) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeatureChip(
                      features[i + 1]['icon'],
                      features[i + 1]['title'],
                      features[i + 1]['value'],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureChip(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.green[700]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D2D2D),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenGalleryView extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenGalleryView({required this.images, required this.initialIndex});

  @override
  _FullScreenGalleryViewState createState() => _FullScreenGalleryViewState();
}

class _FullScreenGalleryViewState extends State<_FullScreenGalleryView> {
  late PageController _pageController;
  double _bgOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(_bgOpacity),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white.withOpacity(_bgOpacity)),
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        itemCount: widget.images.length,
        controller: _pageController,
        physics: const ClampingScrollPhysics(),
        itemBuilder: (context, index) {
          return _ZoomableImagePage(
            imageUrl: '${ApiConfig.uploadsUrl}/${widget.images[index]}',
            bgOpacity: _bgOpacity,
            onBgOpacityChanged: (v) {
              if (mounted) setState(() => _bgOpacity = v);
            },
            onDismiss: () => Navigator.pop(context),
          );
        },
      ),
    );
  }
}

// ─── Facebook-style zoomable image with swipe-to-dismiss ───

class _ZoomableImagePage extends StatefulWidget {
  final String imageUrl;
  final double bgOpacity;
  final ValueChanged<double> onBgOpacityChanged;
  final VoidCallback onDismiss;

  const _ZoomableImagePage({
    required this.imageUrl,
    required this.bgOpacity,
    required this.onBgOpacityChanged,
    required this.onDismiss,
  });

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage>
    with TickerProviderStateMixin {
  final TransformationController _transformCtrl = TransformationController();

  // ── Zoom animation ──
  late AnimationController _zoomAnimCtrl;
  Animation<Matrix4>? _zoomAnimation;

  // ── Dismiss drag state ──
  double _dragOffsetY = 0.0;
  bool _isDismissDragging = false;
  Offset? _dismissStartGlobalPos;

  // ── Snap-back animation ──
  late AnimationController _dismissAnimCtrl;
  Animation<double>? _dismissSnapBack;

  // ── Raw pointer tracking ──
  final Set<int> _activePointers = {};

  // ── Double-tap position ──
  Offset _doubleTapPosition = Offset.zero;

  // ── Zoom state ──
  bool _isCurrentlyZoomed = false;

  void _updateZoomState() {
    _isCurrentlyZoomed = _transformCtrl.value.getMaxScaleOnAxis() > 1.05;
  }

  @override
  void initState() {
    super.initState();

    _zoomAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformCtrl.value = _zoomAnimation!.value;
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _updateZoomState();
          if (mounted) setState(() {});
        }
      });

    _dismissAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_dismissSnapBack != null && mounted) {
          setState(() {
            _dragOffsetY = _dismissSnapBack!.value;
            widget.onBgOpacityChanged(
              (1.0 - (_dragOffsetY.abs() / 300)).clamp(0.0, 1.0),
            );
          });
        }
      });

    _transformCtrl.addListener(_updateZoomState);
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_updateZoomState);
    _zoomAnimCtrl.dispose();
    _dismissAnimCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  // ── Double-tap: toggle zoom ──
  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    _zoomAnimCtrl.stop();
    if (_isCurrentlyZoomed) {
      // Reset to default view — clears all zoom
      _animateZoomTo(Matrix4.identity());
    } else {
      // Zoom in to 2.5x centered on the tapped point
      const double s = 2.5;
      final pos = _doubleTapPosition;
      final zoomed = Matrix4.diagonal3Values(s, s, 1.0)
        ..setTranslationRaw(pos.dx * (1 - s), pos.dy * (1 - s), 0);
      _animateZoomTo(zoomed);
    }
  }

  void _animateZoomTo(Matrix4 target) {
    _zoomAnimCtrl.stop();
    _zoomAnimation = Matrix4Tween(
      begin: _transformCtrl.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _zoomAnimCtrl,
      curve: Curves.easeOutCubic,
    ));
    _zoomAnimCtrl.forward(from: 0);
  }

  // ── Raw pointer event handlers (bypass gesture arena — no conflicts) ──

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);

    if (_activePointers.length == 1 && !_isCurrentlyZoomed) {
      // Potential dismiss drag — record start position
      _dismissStartGlobalPos = event.position;
    }

    // Multi-touch detected: cancel any ongoing dismiss drag
    if (_activePointers.length >= 2 && _isDismissDragging) {
      _isDismissDragging = false;
      _dismissStartGlobalPos = null;
      _snapBackDismiss();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isCurrentlyZoomed) return; // InteractiveViewer handles pan when zoomed
    if (_activePointers.length != 1) return; // Only single-finger dismiss
    if (_dismissStartGlobalPos == null) return;

    final delta = event.position - _dismissStartGlobalPos!;

    // Start dismiss drag only when vertical movement is dominant
    if (!_isDismissDragging) {
      if (delta.dy.abs() > 15 && delta.dy.abs() > delta.dx.abs() * 1.5) {
        _isDismissDragging = true;
        _dismissAnimCtrl.stop();
      }
    }

    if (_isDismissDragging) {
      setState(() {
        _dragOffsetY = delta.dy;
        widget.onBgOpacityChanged(
          (1.0 - (_dragOffsetY.abs() / 300)).clamp(0.0, 1.0),
        );
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    // Evaluate dismiss when the dragging finger lifts
    if (_isDismissDragging && _activePointers.isEmpty) {
      _isDismissDragging = false;
      _dismissStartGlobalPos = null;

      if (_dragOffsetY.abs() > 100) {
        widget.onDismiss();
      } else {
        _snapBackDismiss();
      }
      return;
    }

    // When all fingers are off, update zoom state
    if (_activePointers.isEmpty) {
      _dismissStartGlobalPos = null;
      Future.microtask(() {
        if (mounted) {
          _updateZoomState();
          // Snap to identity if scale is near 1.0 (sloppy pinch)
          if (!_isCurrentlyZoomed) {
            final s = _transformCtrl.value.getMaxScaleOnAxis();
            if (s > 1.001 && s < 1.05) {
              _animateZoomTo(Matrix4.identity());
            }
          }
          setState(() {});
        }
      });
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_isDismissDragging) {
      _isDismissDragging = false;
      _snapBackDismiss();
    }
  }

  void _snapBackDismiss() {
    _dismissSnapBack = Tween<double>(begin: _dragOffsetY, end: 0.0)
        .animate(CurvedAnimation(
      parent: _dismissAnimCtrl,
      curve: Curves.easeOutCubic,
    ));
    _dismissAnimCtrl.forward(from: 0);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      behavior: HitTestBehavior.translucent,
      child: GestureDetector(
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        child: Transform.translate(
          offset: Offset(0, _dragOffsetY),
          child: InteractiveViewer(
            transformationController: _transformCtrl,
            minScale: 1.0,
            maxScale: 5.0,
            panEnabled: _isCurrentlyZoomed,
            scaleEnabled: true,
            onInteractionEnd: (_) {
              _updateZoomState();
              if (!_isCurrentlyZoomed) {
                final s = _transformCtrl.value.getMaxScaleOnAxis();
                if (s > 1.001 && s < 1.05) {
                  _animateZoomTo(Matrix4.identity());
                }
              }
              setState(() {});
            },
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, _) => const Icon(
                    Icons.error,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

