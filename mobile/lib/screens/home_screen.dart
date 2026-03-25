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

  Key _myListingsKey = UniqueKey();
  Key _profileKey = UniqueKey();
  int _unreadMessageCount = 0;
  Color get _primaryGreen => Colors.green[700]!;

  final List<Map<String, dynamic>> _categories = [
    {'id': null, 'name': 'Tümü', 'icon': Icons.apps_rounded},
    {'id': 'büyükbaş', 'name': 'Büyükbaş', 'icon': Icons.agriculture_rounded},
    {'id': 'küçükbaş', 'name': 'Küçükbaş', 'icon': Icons.pets_rounded},
    {'id': 'kanatlı', 'name': 'Kanatlı', 'icon': Icons.flutter_dash_rounded},
    {'id': 'evcil', 'name': 'Evcil', 'icon': Icons.favorite_rounded},
    {'id': 'diğer', 'name': 'Diğer', 'icon': Icons.more_horiz_rounded},
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
    return isForSale ? '${listing.price.toStringAsFixed(0)} ₺' : 'Ücretsiz';
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}g önce';
    if (diff.inHours > 0) return '${diff.inHours}s önce';
    if (diff.inMinutes > 0) return '${diff.inMinutes}dk önce';
    return 'Şimdi';
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(isKeyboardOpen),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return MyListingsScreen(key: _myListingsKey);
      case 2:
        return const ConversationsScreen();
      case 3:
        return ProfileScreen(key: _profileKey);
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return RefreshIndicator(
      onRefresh: () => _loadListings(),
      child: CustomScrollView(
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
                          childAspectRatio: 0.58,
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
          childAspectRatio: 0.58,
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
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
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
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Container(height: 12, width: double.infinity, color: Colors.white),
                    Container(height: 12, width: 92, color: Colors.white),
                    Container(height: 15, width: 70, color: Colors.white),
                    Container(height: 10, width: 86, color: Colors.white),
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
              'Sonuç bulunamadı',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Filtreleri değiştirerek tekrar deneyebilirsin.',
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
    final accentColor = isForSale ? _primaryGreen : const Color(0xFF1565C0);
    final listingTypeText = isForSale ? 'Satılık' : 'Sahiplendirme';
    final bool isNew = DateTime.now().difference(listing.createdAt).inHours < 24;
    final categoryText = listing.category.isNotEmpty
        ? '${listing.category[0].toUpperCase()}${listing.category.substring(1)}'
        : 'İlan';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ListingDetailScreen(listingId: listing.id)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: imageUrl == null
                          ? Container(
                              color: Colors.grey[200],
                              child: Icon(Icons.pets_rounded, size: 56, color: Colors.grey[400]),
                            )
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 420,
                              placeholder: (_, __) => Container(color: Colors.grey[200]),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: Icon(Icons.pets_rounded, size: 56, color: Colors.grey[400]),
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.45),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _buildListingMetaChip(
                        icon: Icons.remove_red_eye_rounded,
                        text: '${listing.views}',
                        backgroundColor: Colors.black.withValues(alpha: 0.62),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _buildListingMetaChip(
                        icon: isForSale ? Icons.sell_rounded : Icons.volunteer_activism_rounded,
                        text: listingTypeText,
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (isNew)
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: _buildListingMetaChip(
                          icon: Icons.bolt_rounded,
                          text: 'Yeni',
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                        ),
                      ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: _buildListingMetaChip(
                        icon: Icons.category_rounded,
                        text: categoryText,
                        backgroundColor: Colors.white.withValues(alpha: 0.95),
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${listing.city}, ${listing.district}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            _timeAgo(listing.createdAt),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(height: 1, color: Colors.grey.withValues(alpha: 0.18)),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          _priceText(listing),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: -0.1,
                          ),
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
    );
  }

  Widget _buildListingMetaChip({
    required IconData icon,
    required String text,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final filterCount = _activeFilters?.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: _primaryGreen,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Transform.scale(
                      scale: 1.35,
                      child: Image.asset('assets/uygulama_logo.png'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Hayvanyeri',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _showAdvancedFilterSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: filterCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 16,
                              color: filterCount > 0 ? _primaryGreen : Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              filterCount > 0 ? '$filterCount filtre' : 'Filtre',
                              style: TextStyle(
                                color: filterCount > 0 ? _primaryGreen : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Türkiye’nin güvenli hayvan pazarı',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 12,
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
                  decoration: InputDecoration(
                    hintText: 'Hayvan ara...',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500]),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _loadListings();
                              setState(() {});
                            },
                            icon: Icon(Icons.close_rounded, color: Colors.grey[500]),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
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
              _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Keşfet'),
              _buildNavItem(1, Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'İlanlarım'),
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
                          'İlan Ekle',
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
          setState(() => _currentIndex = index);
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
          setState(() => _currentIndex = index);
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
}
