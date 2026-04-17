import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';
import 'listing_detail_screen.dart';
import 'edit_listing_screen.dart';

import '../utils/formatters.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<Listing> _myListings = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Debounce bayrağı
  bool _scrollDebounce = false;
  List<String> _selectedListings = [];

  @override
  void initState() {
    super.initState();
    _loadMyListings();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollDebounce || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _scrollDebounce = true;
      _loadMoreListings().whenComplete(() {
        Future.delayed(const Duration(milliseconds: 500), () {
          _scrollDebounce = false;
        });
      });
    }
  }

  Future<void> _loadMyListings() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _myListings = [];
      _currentPage = 1;
      _hasMore = true;
    });
    try {
      final result = await _apiService.getMyListings(page: 1, limit: _pageSize);
      if (!mounted) return;
      final raw = result['listings'] as List<dynamic>? ?? [];
      setState(() {
        _myListings = raw.map((j) => Listing.fromJson(j)).toList();
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Listeyi scroll pozisyonuna dokunmadan tazeler (sil/güncelle sonrası)
  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      final result = await _apiService.getMyListings(page: 1, limit: _pageSize);
      if (!mounted) return;
      final raw = result['listings'] as List<dynamic>? ?? [];
      setState(() {
        _myListings = raw.map((j) => Listing.fromJson(j)).toList();
        _hasMore = result['hasMore'] as bool? ?? false;
        _currentPage = 1;
      });
    } catch (_) {}
  }

  Future<void> _loadMoreListings() async {
    if (_isLoadingMore || !_hasMore) return;
    if (mounted) setState(() => _isLoadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final result = await _apiService.getMyListings(page: nextPage, limit: _pageSize);
      if (!mounted) return;
      final raw = result['listings'] as List<dynamic>? ?? [];
      setState(() {
        _myListings.addAll(raw.map((j) => Listing.fromJson(j)));
        _currentPage = nextPage;
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _deleteListing(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline, color: Colors.red[700], size: 36),
              ),
              const SizedBox(height: 16),
              const Text('İlanı Sil', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Bu ilanı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('İptal', style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Sil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await _apiService.deleteListing(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İlan başarıyla silindi')));
        // Tam reload yerine sadece listeden çıkar → scroll korunur
        setState(() {
          _myListings.removeWhere((l) => l.id == id);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteSelectedListings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_sweep, color: Colors.red[700], size: 36),
              ),
              const SizedBox(height: 16),
              Text('${_selectedListings.length} İlanı Sil', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Seçili ${_selectedListings.length} ilanı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('İptal', style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Sil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;
    
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator())
    );

    int successCount = 0;
    for (String id in _selectedListings) {
      try {
        await _apiService.deleteListing(id);
        successCount++;
        setState(() {
          _myListings.removeWhere((l) => l.id == id);
        });
      } catch (e) {
        // ignore
      }
    }
    
    Navigator.pop(context); // loading kapat
    setState(() {
      _selectedListings.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successCount ilan başarıyla silindi')),
      );
    }
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    try {
      await _apiService.updateListingStatus(id, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İlan durumu güncellendi')));
        // silentRefresh scroll pozisyonuna dokunmaz
        await _silentRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ─── Skeleton ──────────────────────────────────────────────────────────────
  // Tüm skeleton item'ları tek bir Shimmer wrapper içinde
  Widget _buildSkeletonList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      period: const Duration(milliseconds: 1100),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: 5,
        itemBuilder: (_, __) => _buildSkeletonRow(),
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 14,
                      width: double.infinity,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 8)),
                  Container(
                      height: 12,
                      width: 100,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12)),
                  Container(height: 10, width: 60, color: Colors.white),
                ],
              ),
            ),
            Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  // Load-more skeleton — shimmer olmadan sadece row (üst Shimmer yok)
  Widget _buildLoadMoreSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      period: const Duration(milliseconds: 1100),
      child: _buildSkeletonRow(),
    );
  }

  // ─── Listing card ──────────────────────────────────────────────────────────
  Widget _buildListingCard(Listing listing) {
    return Card(
      key: ValueKey(listing.id),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: () {
          setState(() {
            if (_selectedListings.contains(listing.id)) {
              _selectedListings.remove(listing.id);
            } else {
              _selectedListings.add(listing.id);
            }
          });
        },
        onTap: () {
          if (_selectedListings.isNotEmpty) {
            setState(() {
              if (_selectedListings.contains(listing.id)) {
                _selectedListings.remove(listing.id);
              } else {
                _selectedListings.add(listing.id);
              }
            });
            return;
          }
          Navigator.push(
            context,
            PageRouteBuilder(
              opaque: false,
              pageBuilder: (context, animation, secondaryAnimation) =>
                  ListingDetailScreen(
                    listingId: listing.id,
                    heroTag: 'my-listing-image-${listing.id}',
                  ),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ).then((_) => _silentRefresh());
        },
        child: Container(
          decoration: BoxDecoration(
            color: _selectedListings.contains(listing.id) ? Colors.green.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: _selectedListings.contains(listing.id) ? Border.all(color: Colors.green.withOpacity(0.5), width: 2) : Border.all(color: Colors.transparent, width: 2),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: listing.images.isNotEmpty
                    ? Hero(
                        tag: 'my-listing-image-${listing.id}',
                        child: CachedNetworkImage(
                          imageUrl:
                              '${ApiConfig.uploadsUrl}/${listing.images[0]}',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Shimmer.fromColors(
                            baseColor: Colors.grey[300]!,
                            highlightColor: Colors.grey[100]!,
                            child: Container(
                                width: 80, height: 80, color: Colors.white),
                          ),
                          errorWidget: (context, url, _) => _buildPlaceholder(),
                        ),
                      )
                    : _buildPlaceholder(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      listing.listingType == 'satılık'
                          ? '${AppFormatters.formatPrice(listing.price)} ₺'
                          : 'Sahiplendirme',
                      style: TextStyle(
                        color: listing.listingType == 'satılık'
                            ? Colors.green
                            : Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.visibility,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('${listing.views}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: listing.status == 'aktif'
                                ? Colors.green[50]
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            listing.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: listing.status == 'aktif'
                                  ? Colors.green[700]
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_selectedListings.isEmpty)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onSelected: (value) {
                    if (value == 'edit') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                EditListingScreen(listing: listing)),
                      ).then((_) => _silentRefresh());
                    } else if (value == 'toggle_status') {
                      _updateStatus(listing.id,
                          listing.status == 'aktif' ? 'pasif' : 'aktif');
                    } else if (value == 'delete') {
                      _deleteListing(listing.id);
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit, size: 20, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Düzenle'),
                        ])),
                    PopupMenuItem<String>(
                      value: 'toggle_status',
                      child: Row(children: [
                        Icon(
                            listing.status == 'aktif'
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                            color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(listing.status == 'aktif'
                            ? 'Pasife Al'
                            : 'Aktif Et'),
                      ]),
                    ),
                    const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Sil', style: TextStyle(color: Colors.red)),
                        ])),
                  ],
                )
              else 
                const SizedBox(width: 48), // Checkbox kaldırıldı, ikon genişliği kadar yer ayır
            ],
          ),
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedListings.isEmpty,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_selectedListings.isNotEmpty) {
          setState(() {
            _selectedListings.clear();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _selectedListings.isNotEmpty
              ? Text('${_selectedListings.length} İlan Seçildi', style: const TextStyle(color: Colors.white))
              : const Text('İlanlarım', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green[700],
        iconTheme: const IconThemeData(color: Colors.white),
        leading: _selectedListings.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedListings.clear()),
              )
            : null,
        actions: [
          if (_selectedListings.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedListings,
            ),
        ],
      ),
      body: _isLoading
          ? _buildSkeletonList()
          : _myListings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('Henüz ilanınız yok',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMyListings,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    cacheExtent: 600,
                    itemCount: _myListings.length + (_isLoadingMore ? 2 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _myListings.length) {
                        return _buildLoadMoreSkeleton();
                      }
                      return _buildListingCard(_myListings[index]);
                    },
                  ),
                ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey[200],
      child: Icon(Icons.pets, color: Colors.grey[400]),
    );
  }
}
