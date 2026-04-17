import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../config/api_config.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../widgets/advanced_filter_sheet.dart';
import 'conversations_screen.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';
import 'my_listings_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Listing> _listings = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 10;

  String? _selectedCategory;
  int _currentIndex = 0;
  Map<String, dynamic>? _activeFilters;
  bool _showAppBar = false;

  Key _myListingsKey = UniqueKey();
  Key _profileKey = UniqueKey();
  int _unreadMessageCount = 0;
  Color get _primaryGreen => Colors.green[700]!;

  final List<Map<String, dynamic>> _categories = [
    {'id': null, 'name': 'Tümü', 'icon': Icons.apps_rounded},
    {'id': 'büyükbaþ', 'name': 'Büyükbaþ', 'icon': Icons.agriculture_rounded},
    {'id': 'küçükbaþ', 'name': 'Küçükbaþ', 'icon': Icons.pets_rounded},
    {'id': 'kanatlý', 'name': 'Kanatlý', 'icon': Icons.flutter_dash_rounded},
    {'id': 'evcil', 'name': 'Evcil', 'icon': Icons.favorite_rounded},
    {'id': 'diðer', 'name': 'Diðer', 'icon': Icons.more_horiz_rounded},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadListings();
    _setupUnreadCountListener();
    _loadUnreadCount();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SocketService().removeUnreadCountListener(_onUnreadCountChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    // Show/hide app bar based on scroll position (after header ends ~200px)
    if (_scrollController.offset > 200 && !_showAppBar) {
      setState(() => _showAppBar = true);
    } else if (_scrollController.offset <= 200 && _showAppBar) {
      setState(() => _showAppBar = false);
    }
    
    // Load more listings
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.85) {
      _loadMoreListings();
    }
  }

  Future<void> _loadListings({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _listings = [];
        _currentPage = 1;
        _hasMore = true;
      });
    }

    try {
      final queryFilters = <String, dynamic>{
        if (_activeFilters != null) ..._activeFilters!,
        if (_selectedCategory != null) 'category': _selectedCategory,
        if (_searchController.text.isNotEmpty) 'search': _searchController.text,
      };

      final result = await _apiService.getListings(
        filters: queryFilters,
        page: 1,
        limit: _pageSize,
      );

      if (!mounted) return;
      final rawList = result['listings'] as List<dynamic>? ?? [];
      final hasMore = result['hasMore'] as bool? ?? false;

      setState(() {
        _listings = rawList.map((json) => Listing.fromJson(json)).toList();
        _currentPage = 1;
        _hasMore = hasMore;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreListings() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final queryFilters = <String, dynamic>{
        if (_activeFilters != null) ..._activeFilters!,
        if (_selectedCategory != null) 'category': _selectedCategory,
        if (_searchController.text.isNotEmpty) 'search': _searchController.text,
      };

      final nextPage = _currentPage + 1;
      final result = await _apiService.getListings(
        filters: queryFilters,
        page: nextPage,
        limit: _pageSize,
      );

      if (!mounted) return;
      final rawList = result['listings'] as List<dynamic>? ?? [];
      final hasMore = result['hasMore'] as bool? ?? false;

      setState(() {
        _listings.addAll(rawList.map((json) => Listing.fromJson(json)));
        _currentPage = nextPage;
        _hasMore = hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _apiService.getUnreadMessageCount();
      if (mounted) {
        setState(() => _unreadMessageCount = count);
        final socketService = SocketService();
        socketService.unreadCount = count;
        socketService.notifyUnreadCountListeners();
      }
    } catch (_) {}
  }

  void _setupUnreadCountListener() {
    final socketService = SocketService();
    socketService.addUnreadCountListener(_onUnreadCountChanged);
    setState(() => _unreadMessageCount = socketService.unreadCount);
  }

  void _onUnreadCountChanged(int count) {
    if (mounted) setState(() => _unreadMessageCount = count);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      SocketService().disconnectForBackground();
    }
  }

  Future<void> _onAppResumed() async {
    try {
      await SocketService().reconnectIfNeeded();
      await _loadUnreadCount();
    } catch (_) {}
  }

  Future<void> _showAdvancedFilterSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdvancedFilterSheet(initialFilters: _activeFilters),
    );

    if (result != null) {
      setState(() => _activeFilters = result);
      _loadListings();
    }
  }

  Future<void> _openCreateListing() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );

    if (result == true) {
      setState(() {
        if (_currentIndex == 0) _loadListings(showLoading: false);
        _myListingsKey = UniqueKey();
        _profileKey = UniqueKey();
      });
    }
  }

  bool _isForSaleType(String listingType) {
    final t = listingType.toLowerCase();
    return t.contains('sat') || t.contains('kurban') || t.contains('kirala');
  }

  String _priceText(Listing listing) {
    final isForSale = _isForSaleType(listing.listingType);
    return isForSale ? '${listing.price.toStringAsFixed(0)} TL' : 'Ücretsiz';
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}g önce';
    if (diff.inHours > 0) return '${diff.inHours}s önce';
    if (diff.inMinutes > 0) return '${diff.inMinutes}dk önce';
    return 'Þimdi';
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      extendBodyBehindAppBar: true,
      appBar: _showAppBar && _currentIndex == 0 ? _buildMinimalAppBar() : null,
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(isKeyboardOpen),
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildHomeContent(),
        MyListingsScreen(key: _myListingsKey),
        const ConversationsScreen(),
        ProfileScreen(key: _profileKey),
      ],
    );
  }

  Widget _buildHomeContent() {
    return RefreshIndicator(
      onRefresh: () => _loadListings(),
      child: CustomScrollView(
        key: const PageStorageKey<String>('homeScrollView'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildCategoryList()),
          _isLoading
              ? _buildSkeletonGrid()
              : _listings.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.61,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _listings.length) return _buildSkeletonCard();
                            return _buildListingCard(_listings[index]);
                          },
                          childCount: _listings.length + (_isLoadingMore ? 2 : 0),
                        ),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.61,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate((_, __) => _buildSkeletonCard(), childCount: 6),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      period: const Duration(milliseconds: 1200),
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
              flex: 6,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 14,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 70, color: Colors.grey[400]),
            const SizedBox(height: 14),
            Text(
              'Sonuç bulunamadý',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Filtreleri deðiþtirerek tekrar deneyebilirsin.',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingCard(Listing listing) {
    final isForSale = _isForSaleType(listing.listingType);
    final imageUrl = listing.images.isNotEmpty
        ? '${ApiConfig.uploadsUrl}/${listing.images.first}'
        : null;
    // Facebook beðeni mavisi - Satýlýk/Sahiplendirme etiketi için
    final badgeColor = const Color(0xFF1877F2); // Facebook Blue
    // Siyah renk - Fiyat etiketi için
    final priceColor = const Color(0xFF212121); // Dark Grey/Black
    final listingTypeText = isForSale ? 'Satýlýk' : 'Sahiplendirme';
    final bool isNew = DateTime.now().difference(listing.createdAt).inHours < 24;

    return GestureDetector(
      onTap: () async {
        // Ýlan detayýna git ve geri dönüldüðünde listeyi güncelle
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ListingDetailScreen(listingId: listing.id)),
        );
        // Geri dönüldüðünde listeyi yenile (loading göstermeden)
        _loadListings(showLoading: false);
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
            // Image Section
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  // Main Image
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: imageUrl == null
                        ? Container(
                            width: double.infinity,
                            color: Colors.grey[100],
                            child: Icon(Icons.pets, size: 48, color: Colors.grey[300]),
                          )
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            placeholder: (_, __) => Container(
                              color: Colors.grey[100],
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.grey[300]!),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[100],
                              child: Icon(Icons.pets, size: 48, color: Colors.grey[300]),
                            ),
                          ),
                  ),
                  
                  // Gradient Overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.transparent,
                            Colors.black.withOpacity(0.5),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  
                  // Top Left Badges (Listing Type & Views)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Listing Type Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: badgeColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isForSale ? Icons.sell : Icons.volunteer_activism,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                listingTypeText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Views Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.visibility, size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                '${listing.views}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (listing.favoriteCount > 0) ...[
                          const SizedBox(height: 6),
                          // Favorite Count Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '${listing.favoriteCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // Bottom Info
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // New Badge
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB300),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.fiber_new, size: 12, color: Colors.white),
                              ],
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        
                        // Price & Listing Type Stack
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Price Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: priceColor,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: priceColor.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                _priceText(listing),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Info Section
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                        color: Color(0xFF212121),
                      ),
                    ),
                    const Spacer(),
                    
                    // Location & Time
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${listing.city}, ${listing.district}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _timeAgo(listing.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalizeFirst(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return text;
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  Widget _buildHeader() {
    final filterCount = _activeFilters?.length ?? 0;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _primaryGreen,
              const Color(0xFF388E3C),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Transform.scale(
                        scale: 1.8,
                        child: Image.asset(
                          'assets/uygulama_logo.png',
                          width: 32,
                          height: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hayvanyeri',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Türkiye\'nin güvenli hayvan pazarý',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showAdvancedFilterSheet,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: filterCount > 0 
                                ? Colors.white 
                                : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: filterCount > 0 ? _primaryGreen : Colors.white,
                              ),
                              if (filterCount > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$filterCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      if (value.isEmpty) _loadListings();
                      setState(() {});
                    },
                    onSubmitted: (_) => _loadListings(),
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Hayvan ara...',
                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                      prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[600], size: 24),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _loadListings();
                                setState(() {});
                              },
                              icon: Icon(Icons.close_rounded, color: Colors.grey[600], size: 22),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: _categories.map((category) {
          final isSelected = _selectedCategory == category['id'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = category['id'] as String?);
                _loadListings();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? _primaryGreen : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? _primaryGreen : Colors.grey.shade300,
                  ),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      category['name'] as String,
                      maxLines: 1,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[800],
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomNav(bool isKeyboardOpen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 74,
          child: Row(
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Keþfet'),
              _buildNavItem(1, Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Ýlanlarým'),
              if (!isKeyboardOpen)
                Expanded(
                  child: GestureDetector(
                    onTap: _openCreateListing,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _primaryGreen,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ýlan Ekle',
                          style: TextStyle(
                            color: _primaryGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Expanded(child: SizedBox()),
              _buildNavItemWithBadge(
                2,
                Icons.chat_bubble_outline_rounded,
                Icons.chat_bubble_rounded,
                'Mesajlar',
                _unreadMessageCount,
              ),
              _buildNavItem(3, Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlinedIcon, IconData filledIcon, String label) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_currentIndex == index) return; // Ayný sayfadaysa hiçbir þey yapma
          
          setState(() {
            _currentIndex = index;
            // Keþfet sayfasýna dönüldüðünde scroll pozisyonuna göre mini bar'ý göster/gizle
            if (index == 0 && _scrollController.hasClients) {
              _showAppBar = _scrollController.offset > 200;
            } else if (index != 0) {
              // Keþfet dýþýndaki sayfalara geçildiðinde mini bar'ý gizle
              _showAppBar = false;
            }
          });
          if (index == 0) _loadListings(showLoading: false);
          if (index == 2) _loadUnreadCount();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? _primaryGreen.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSelected ? filledIcon : outlinedIcon,
                color: isSelected ? _primaryGreen : Colors.grey[600],
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _primaryGreen : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItemWithBadge(
    int index,
    IconData outlinedIcon,
    IconData filledIcon,
    String label,
    int badge,
  ) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_currentIndex == index) return; // Ayný sayfadaysa hiçbir þey yapma
          
          setState(() {
            _currentIndex = index;
            // Keþfet sayfasýna dönüldüðünde scroll pozisyonuna göre mini bar'ý göster/gizle
            if (index == 0 && _scrollController.hasClients) {
              _showAppBar = _scrollController.offset > 200;
            } else if (index != 0) {
              // Keþfet dýþýndaki sayfalara geçildiðinde mini bar'ý gizle
              _showAppBar = false;
            }
          });
          _loadUnreadCount();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryGreen.withValues(alpha: 0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSelected ? filledIcon : outlinedIcon,
                    color: isSelected ? _primaryGreen : Colors.grey[600],
                    size: 22,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    right: -7,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _primaryGreen : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMinimalAppBar() {
    final filterCount = _activeFilters?.length ?? 0;
    
    return AppBar(
      backgroundColor: _primaryGreen,
      elevation: 4,
      toolbarHeight: 60,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Transform.scale(
              scale: 1.3,
              child: Image.asset('assets/uygulama_logo.png'),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Hayvanyeri',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _openSearchModal,
          icon: const Icon(Icons.search_rounded, color: Colors.white, size: 24),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: _showAdvancedFilterSheet,
              icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
            ),
            if (filterCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Center(
                    child: Text(
                      '$filterCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _openSearchModal() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchModal(initialQuery: _searchController.text),
    );

    if (result != null) {
      _searchController.text = result;
      if (result.isNotEmpty) {
        // Arama yapýldýysa scroll'u en baþa al ve sonuçlarý yükle
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        _loadListings();
      }
    }
  }
}


