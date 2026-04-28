import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../config/api_config.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
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
  int _totalFound = 0;

  String? _selectedCategory;
  int _currentIndex = 0;
  Map<String, dynamic>? _activeFilters;
  bool _showAppBar = false;
  String _selectedSort = 'newest';

  Key _myListingsKey = UniqueKey();
  Key _profileKey = UniqueKey();
  final GlobalKey<ConversationsScreenState> _conversationsKey = GlobalKey<ConversationsScreenState>();
  int _unreadMessageCount = 0;
  Color get _primaryGreen => Colors.green[700]!;

  final List<Map<String, dynamic>> _categories = [
    {'id': null, 'name': 'Tümü', 'icon': Icons.apps_rounded},
    {'id': 'büyükbaş', 'name': 'Büyükbaş', 'emoji': '🐄'},
    {'id': 'küçükbaş', 'name': 'Küçükbaş', 'emoji': '🐑'},
    {'id': 'kanatlı', 'name': 'Kanatlı', 'emoji': '🐓'},
    {'id': 'evcil', 'name': 'Evcil', 'emoji': '🐾'},
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
    
    // Show/hide app bar based on scroll position (after header ends ~300px)
    if (_scrollController.offset > 300 && !_showAppBar) {
      setState(() => _showAppBar = true);
    } else if (_scrollController.offset <= 300 && _showAppBar) {
      setState(() => _showAppBar = false);
    }
  }

  Future<void> _loadListings({bool showLoading = true, int page = 1, bool scrollToTop = false}) async {
    // Hata durumunda önceki değerlere dönmek için sakla
    final previousListings = List<Listing>.from(_listings);
    final previousTotal = _totalFound;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _listings = [];
        _currentPage = page;
        _hasMore = true;
        _showAppBar = false;
      });
    }

    try {
      final queryFilters = <String, dynamic>{
        if (_activeFilters != null) ..._activeFilters!,
        if (_selectedCategory != null) 'category': _selectedCategory,
        if (_searchController.text.isNotEmpty) 'search': _searchController.text,
        if (_selectedSort != 'newest') 'sort': _selectedSort,
      };

      final result = await _apiService.getListings(
        filters: queryFilters,
        page: page,
        limit: _pageSize,
      );

      if (!mounted) return;
      final rawList = result['listings'] as List<dynamic>? ?? [];
      final hasMore = result['hasMore'] as bool? ?? false;
      final total = result['totalCount'] as int? ?? 0;

      // DEBUG: Sorunun nedenini bul
      debugPrint('🔍 rawList.length=${rawList.length}, totalCount=$total, category=$_selectedCategory');

      List<Listing> parsedListings = [];
      for (int i = 0; i < rawList.length; i++) {
        try {
          parsedListings.add(Listing.fromJson(rawList[i]));
        } catch (e) {
          debugPrint('❌ Listing[$i] parse hatası: $e');
        }
      }
      debugPrint('✅ parsedListings.length=${parsedListings.length}');

      setState(() {
        _listings = parsedListings;
        _currentPage = page;
        _hasMore = hasMore;
        _totalFound = total;
        _isLoading = false;
      });

      if (scrollToTop && _scrollController.hasClients) {
         _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Hata durumunda önceki listeyi geri yükle — boş ekran gösterme
          if (_listings.isEmpty) {
            _listings = previousListings;
            _totalFound = previousTotal;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bağlantı hatası. Lütfen tekrar deneyin.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
    // Filtre sayfasına giderken, header kategori seçimini de dahil et
    final mergedFilters = <String, dynamic>{
      if (_activeFilters != null) ..._activeFilters!,
      if (_selectedCategory != null) 'category': _selectedCategory,
    };

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdvancedFilterSheet(initialFilters: mergedFilters.isEmpty ? null : mergedFilters),
    );

    if (result != null) {
      if (result['reset'] == true) {
        setState(() {
          _activeFilters = null;
          _searchController.clear();
          _selectedCategory = null;
        });
      } else {
        // 'category' key'ini _selectedCategory'ye taşı, _activeFilters'da BİRAKMA
        // Çünkü queryFilters zaten _selectedCategory'yi ayrıca ekliyor
        final newCategory = result['category'] as String?;
        final filtersWithoutCategory = Map<String, dynamic>.from(result)
          ..remove('category');
        setState(() {
          _selectedCategory = newCategory;
          _activeFilters = filtersWithoutCategory.isEmpty ? null : filtersWithoutCategory;
        });
      }
      _loadListings(scrollToTop: true);
    }
  }

  Future<void> _openCreateListing() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );

    if (result == true) {
      setState(() {
        _myListingsKey = UniqueKey();
        _profileKey = UniqueKey();
      });
    }
  }

  int get _calculatedFilterCount {
    int count = 0;
    // Header kategori seçimini say (activeFilters içinde de olabilir, ama _selectedCategory öncelikli)
    if (_selectedCategory != null) count++;
    if (_activeFilters != null) {
      final f = _activeFilters!;
      // category zaten _selectedCategory üzerinden sayıldı, tekrar sayma
      if (f.containsKey('animalType')) count++;
      if (f.containsKey('breed')) count++;
      if (f.containsKey('listingType')) count++;
      if (f.containsKey('gender')) count++;
      if (f.containsKey('healthStatus')) count++;
      if (f.containsKey('minAge') || f.containsKey('maxAge')) count++;
      if (f.containsKey('minWeight') || f.containsKey('maxWeight')) count++;
      if (f.containsKey('minPrice') || f.containsKey('maxPrice')) count++;
      if (f.containsKey('city')) count++;
    }
    return count;
  }

  bool _isForSaleType(String listingType) {
    final t = listingType.toLowerCase();
    return t.contains('sat') || t.contains('kurban') || t.contains('kirala');
  }

  String _priceText(Listing listing) {
    final isForSale = _isForSaleType(listing.listingType);
    return isForSale ? '${AppFormatters.formatPrice(listing.price)} TL' : 'Ücretsiz';
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
      backgroundColor: Colors.grey[100],
      extendBodyBehindAppBar: true,
      extendBody: false,
      body: Stack(
        children: [
          _buildBody(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !(_showAppBar && _currentIndex == 0),
              child: AnimatedSlide(
                offset: _showAppBar && _currentIndex == 0 ? Offset.zero : const Offset(0, -1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                child: AnimatedOpacity(
                  opacity: _showAppBar && _currentIndex == 0 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  child: _buildMinimalAppBar(),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: (_currentIndex == 0 || _currentIndex == 1)
          ? Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: FloatingActionButton(
                onPressed: _openCreateListing,
                backgroundColor: _primaryGreen,
                elevation: 6,
                heroTag: null, // Hero animasyonunu devre dışı bırak
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
              ),
            )
          : const SizedBox.shrink(), // null yerine boş widget
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(isKeyboardOpen),
    );
  }

  Widget _buildSortDropdown() {
    final sortLabels = {
      'newest': 'En Yeni',
      'oldest': 'En Eski',
      'price_asc': 'Fiyat (Artan)',
      'price_desc': 'Fiyat (Azalan)',
    };
    
    final sortIcons = {
      'newest': Icons.schedule_rounded,
      'oldest': Icons.history_rounded,
      'price_asc': Icons.trending_up_rounded,
      'price_desc': Icons.trending_down_rounded,
    };
    
    return PopupMenuButton<String>(
      initialValue: _selectedSort,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            sortIcons[_selectedSort],
            size: 18,
            color: _primaryGreen,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              sortLabels[_selectedSort] ?? 'En Yeni',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: Colors.grey[600],
          ),
        ],
      ),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 8,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'newest',
          child: _buildSortMenuItem('newest', 'En Yeni', sortIcons['newest']!),
        ),
        PopupMenuItem(
          value: 'oldest',
          child: _buildSortMenuItem('oldest', 'En Eski', sortIcons['oldest']!),
        ),
        PopupMenuItem(
          value: 'price_asc',
          child: _buildSortMenuItem('price_asc', 'Fiyat (Artan)', sortIcons['price_asc']!),
        ),
        PopupMenuItem(
          value: 'price_desc',
          child: _buildSortMenuItem('price_desc', 'Fiyat (Azalan)', sortIcons['price_desc']!),
        ),
      ],
      onSelected: (value) {
        if (value != _selectedSort) {
          setState(() => _selectedSort = value);
          _loadListings(scrollToTop: true);
        }
      },
    );
  }

  Widget _buildSortMenuItem(String value, String label, IconData icon) {
    final isSelected = _selectedSort == value;
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isSelected ? Colors.green[700] : Colors.grey[600],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.green[700] : Colors.grey[800],
            ),
          ),
        ),
        if (isSelected)
          Icon(Icons.check_circle_rounded, size: 18, color: Colors.green[700]),
      ],
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildHomeContent(),
        MyListingsScreen(key: _myListingsKey),
        ConversationsScreen(key: _conversationsKey),
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
          if (!_isLoading)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[200]!, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _primaryGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.inventory_2_rounded,
                              size: 18,
                              color: _primaryGreen,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Toplam Sonuç',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$_totalFound',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: Colors.grey[200],
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    Expanded(
                      child: _buildSortDropdown(),
                    ),
                  ],
                ),
              ),
            ),
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
                            if (index >= _listings.length) return const SizedBox.shrink();
                            return _buildListingCard(_listings[index]);
                          },
                          childCount: _listings.length,
                        ),
                      ),
                    ),
          if (!_isLoading && _listings.isNotEmpty)
            SliverToBoxAdapter(child: _buildPagination()),
        ],
      ),
    );
  }

  Widget _buildPageButton(int page) {
    final isActive = page == _currentPage;
    return GestureDetector(
      onTap: isActive ? null : () => _loadListings(page: page),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? _primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? Colors.transparent : Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: _primaryGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$page',
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey[700],
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    if (_totalFound <= _pageSize) return const SizedBox.shrink();
    
    final totalPages = (_totalFound / _pageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    int max(int a, int b) => a > b ? a : b;
    int min(int a, int b) => a < b ? a : b;

    List<Widget> pageButtons = [];
    int startPage = max(1, _currentPage - 2);
    int endPage = min(totalPages, startPage + 4);
    
    if (endPage - startPage < 4) {
      startPage = max(1, endPage - 4);
    }

    if (startPage > 1) {
      pageButtons.add(_buildPageButton(1));
      if (startPage > 2) {
        pageButtons.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ));
      }
    }

    for (int i = startPage; i <= endPage; i++) {
      pageButtons.add(_buildPageButton(i));
    }

    if (endPage < totalPages) {
      if (endPage < totalPages - 1) {
        pageButtons.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ));
      }
      pageButtons.add(_buildPageButton(totalPages));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            GestureDetector(
              onTap: _currentPage > 1 ? () => _loadListings(page: _currentPage - 1) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: _currentPage > 1 ? Colors.grey[800] : Colors.grey[300],
                ),
              ),
            ),
            const SizedBox(width: 4),
            ...pageButtons,
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _currentPage < totalPages ? () => _loadListings(page: _currentPage + 1) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: _currentPage < totalPages ? Colors.grey[800] : Colors.grey[300],
                ),
              ),
            ),
          ],
        ),
      ),
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
    // Satılık için yeşil, Sahiplendirme için mavi (ilan detay sayfasıyla aynı)
    final badgeColor = isForSale ? Colors.green[600]! : Colors.blue[600]!;
    // Siyah renk - Fiyat etiketi için
    final priceColor = const Color(0xFF212121); // Dark Grey/Black
    final listingTypeText = isForSale ? 'Satılık' : 'Sahiplendirme';

    return GestureDetector(
      onTap: () async {
        // İlan detayına git ve geri dönüldüğünde listeyi güncelle
        await Navigator.push(
          context,
          PageRouteBuilder(
            opaque: false,
            pageBuilder: (context, animation, secondaryAnimation) =>
                ListingDetailScreen(
                  listingId: listing.id,
                  heroTag: 'listing-image-${listing.id}',
                ),
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
                        : Hero(
                            tag: 'listing-image-${listing.id}',
                            child: CachedNetworkImage(
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
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
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
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: Colors.grey[900],
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Location
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${listing.city}, ${listing.district}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 6),
                    
                    // Time
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _timeAgo(listing.createdAt),
                          style: TextStyle(
                            fontSize: 12,
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
    final filterCount = _calculatedFilterCount;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(38),
        bottomRight: Radius.circular(38),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Transform.scale(
                        scale: 2.0,
                        child: Image.asset(
                          'assets/uygulama_logo.png',
                          width: 36,
                          height: 36,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hayvanyeri',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Türkiye\'nin En Güvenilir Hayvan Pazarı',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _showAdvancedFilterSheet,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: filterCount > 0 
                                    ? Colors.white 
                                    : Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                size: 22,
                                color: filterCount > 0 ? _primaryGreen : Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (filterCount > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.red[400]!, Colors.red[600]!],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              child: Center(
                                child: Text(
                                  '$filterCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
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
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
              ),
              _buildCategoryList(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        const itemSpacing = 6.0; // 10'dan 6'ya düşürdüm
        const minItemWidth = 64.0;
        
        // Ekran genişliğine göre kaç item sığacağını hesapla
        int itemsToShow = (screenWidth / (minItemWidth + itemSpacing)).floor();
        if (itemsToShow < 4) itemsToShow = 4; // Minimum 4 item göster
        if (itemsToShow > 7) itemsToShow = 7; // Maximum 7 item göster
        
        // Her item'ın genişliğini hesapla
        final totalSpacing = (itemsToShow - 1) * itemSpacing;
        final itemWidth = (screenWidth - totalSpacing) / itemsToShow;
        
        return Container(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              final isSelected = _selectedCategory == category['id'];
              
              return Container(
                width: itemWidth,
                margin: EdgeInsets.only(right: index == _categories.length - 1 ? 0 : itemSpacing),
                child: GestureDetector(
                  onTap: () {
                    // Sadece _selectedCategory'yi güncelle
                    // _activeFilters'a 'category' YAZMA - queryFilters zaten merge ediyor
                    setState(() => _selectedCategory = category['id'] as String?);
                    _loadListings();
                  },
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white.withOpacity(0.4),
                            width: 2,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: category['emoji'] != null
                              ? Text(
                                  category['emoji'] as String,
                                  style: const TextStyle(fontSize: 26),
                                )
                              : Icon(
                                  category['icon'] as IconData,
                                  size: 26,
                                  color: isSelected ? _primaryGreen : Colors.white,
                                ),
                        ),
                      ),
                      const SizedBox(height: 4), // 5'ten 4'e düşürdüm
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1), // 2'den 1'e düşürdüm
                        child: Text(
                          category['name'] as String,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 10,
                            shadows: isSelected
                                ? [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBottomNav(bool isKeyboardOpen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(0),
          topRight: Radius.circular(0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Keşfet'),
                  _buildNavItem(1, Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'İlanlarım'),
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
          if (_currentIndex == index) return; // Aynı sayfadaysa hiçbir şey yapma
          
          setState(() {
            _currentIndex = index;
            if (index == 3) _profileKey = UniqueKey();
            if (index == 1) _myListingsKey = UniqueKey();
            // Keşfet sayfasına dönüldüğünde scroll pozisyonuna göre mini bar'ı göster/gizle
            if (index == 0 && _scrollController.hasClients) {
              _showAppBar = _scrollController.offset > 300;
            } else if (index != 0) {
              // Keşfet dışındaki sayfalara geçildiğinde mini bar'ı gizle
              _showAppBar = false;
            }
          });
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
                color: isSelected ? _primaryGreen : const Color(0xFF1F2937),
                size: 26,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? _primaryGreen : const Color(0xFF1F2937),
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
          if (_currentIndex == index) {
            if (index == 2) {
              _loadUnreadCount();
              _conversationsKey.currentState?.refreshList();
            }
            return;
          }
          
          setState(() {
            _currentIndex = index;
            if (index == 3) _profileKey = UniqueKey();
            if (index == 1) _myListingsKey = UniqueKey();
            // Keşfet sayfasına dönüldüğünde scroll pozisyonuna göre mini bar'ı göster/gizle
            if (index == 0 && _scrollController.hasClients) {
              _showAppBar = _scrollController.offset > 300;
            } else if (index != 0) {
              // Keşfet dışındaki sayfalara geçildiğinde mini bar'ı gizle
              _showAppBar = false;
            }
          });
          
          if (index == 2) {
            _loadUnreadCount();
            _conversationsKey.currentState?.refreshList();
          }
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
                    color: isSelected ? _primaryGreen : const Color(0xFF1F2937),
                    size: 26,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD32F2F),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
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
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? _primaryGreen : const Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMinimalAppBar() {
    final filterCount = _calculatedFilterCount;
    
    return AppBar(
      backgroundColor: _primaryGreen,
      elevation: 0,
      toolbarHeight: 72,
      automaticallyImplyLeading: false,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_primaryGreen, Colors.green[800]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      title: GestureDetector(
        onTap: () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
            );
          }
        },
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Transform.scale(
                scale: 1.5,
                child: Image.asset(
                  'assets/uygulama_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Hayvanyeri',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (_totalFound > 0)
                  Text(
                    '$_totalFound ilan',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _openSearchModal,
              child: Container(
                padding: const EdgeInsets.all(12),
                child: const Icon(
                  Icons.search_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _showAdvancedFilterSheet,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: filterCount > 0
                        ? BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          )
                        : null,
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
              if (filterCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red[400]!, Colors.red[600]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Center(
                      child: Text(
                        '$filterCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openSearchModal() async {
    final result = await Navigator.push<String>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _SearchScreen(initialQuery: _searchController.text),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );

    if (result != null && result != _searchController.text) {
      _searchController.text = result;
      if (result.isNotEmpty && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      _loadListings();
    }
  }
}


class _SearchScreen extends StatefulWidget {
  final String initialQuery;
  
  const _SearchScreen({required this.initialQuery});

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  late TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();

  final List<String> _searchTags = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    
    // Etiketleri dinamik doldur (AppConstants üzerinden)
    final Set<String> uniqueTags = {};
    
    // Ana kategoriler
    for (var cat in AppConstants.categoryAnimals.keys) {
      if (cat.toLowerCase() != 'diğer') {
        uniqueTags.add('${cat[0].toUpperCase()}${cat.substring(1)}');
      }
    }
    
    // Türler
    for (var animals in AppConstants.categoryAnimals.values) {
      for (var animal in animals) {
        if (animal.toLowerCase() != 'diğer') {
          uniqueTags.add(animal);
        }
      }
    }
    
    // Irklar
    for (var breeds in AppConstants.breeds.values) {
      for (var breed in breeds) {
        if (breed.toLowerCase() != 'diğer' && breed.toLowerCase() != 'melez') {
          uniqueTags.add(breed);
        }
      }
    }
    
    _searchTags.addAll(uniqueTags);

    Future.delayed(const Duration(milliseconds: 100), () => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.trim().isNotEmpty) {
      Navigator.pop(context, query.trim());
    } else {
      Navigator.pop(context, '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[800], // Alt kısımdaki koyu yeşil arka plan
      appBar: AppBar(
        backgroundColor: Colors.green[100], // Üst kısımdaki açık yeşil
        elevation: 0,
        scrolledUnderElevation: 0, // Scroll yapıldığında parlamayı önler
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ÜST KISIM: Logo, Başlık ve Arama Çubuğu
          Container(
            color: Colors.green[100],
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                // Logo (üstte)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    'assets/uygulama_logo.png',
                    width: 64,
                    height: 64,
                  ),
                ),
                const SizedBox(height: 8),
                // Başlık (altta)
                Text(
                  'Hayvanyeri',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.green[900],
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 24),
                // Arama Çubuğu
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      onSubmitted: _performSearch,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Platformda arama yapın...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 20, right: 12),
                          child: Icon(Icons.search_rounded, color: Colors.green[600], size: 24),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.black54, size: 16),
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : const SizedBox(width: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // ALT KISIM: Etiketler ve Kaydırılabilir Alan
          Expanded(
            child: Container(
              color: Colors.green[800],
              width: double.infinity,
              child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_searchController.text.isEmpty) ...[
                      // 3 Sütunlu Dinamik Etiket Tablosu
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _searchTags.map((tag) {
                          // Ekranın tam genişliğini kullanarak her satırda tam 3 tane olacak şekilde boyut hesaplama
                          final sWidth = MediaQuery.of(context).size.width;
                          // 20 sol + 20 sağ padding = 40
                          // 2 adet yatay spacing (10x2) = 20
                          // Toplam boşluk = 60
                          final itemWidth = (sWidth - 60) / 3;
                          
                          return SizedBox(
                            width: itemWidth,
                            child: ElevatedButton(
                              onPressed: () => _performSearch(tag),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.green[600]!, width: 1),
                                ),
                              ),
                              child: Text(
                                tag,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ] else ...[
                      // Dinamik Arama Önizlemesi
                      Card(
                        elevation: 0,
                        color: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.green[600]!),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green[700],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.search_rounded, color: Colors.white),
                          ),
                          title: Text(
                            _searchController.text,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            'Tüm ilanlarda ara',
                            style: TextStyle(color: Colors.green[100]),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white54),
                          onTap: () => _performSearch(_searchController.text),
                        ),
                      ),
                    ],
                    const SizedBox(height: 48), // Alt boşluk
                  ],
                ),
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
