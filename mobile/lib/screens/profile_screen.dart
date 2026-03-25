import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'favorites_screen.dart';
import 'login_screen.dart';
import 'personal_info_screen.dart';
import 'security_password_screen.dart';
import 'support_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  int _listingCount = 0;
  int _totalViews = 0;
  int _favoriteCount = 0;
  bool _isLoadingStats = true;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);

    try {
      final result = await _apiService.getMyListings();
      final listings = result['listings'] as List<dynamic>? ?? [];
      final authProvider = context.read<AuthProvider>();
      final favorites = (authProvider.user?['favorites'] as List<dynamic>?) ?? [];

      if (!mounted) return;
      setState(() {
        _listingCount = listings.length;
        _totalViews = listings.fold<int>(0, (sum, item) {
          final views = item['views'];
          return sum + (views is int ? views : 0);
        });
        _favoriteCount = favorites.length;
        _isLoadingStats = false;
      });
    } catch (_) {
      if (mounted) {
        final favorites = (context.read<AuthProvider>().user?['favorites'] as List<dynamic>?) ?? [];
        setState(() {
          _favoriteCount = favorites.length;
          _isLoadingStats = false;
        });
      }
    }
  }

  String _formatViews(int views) {
    if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}K';
    }
    return views.toString();
  }

  Future<void> _openAvatarPicker() async {
    if (_isUploadingAvatar) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Kamera'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galeri'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1400,
        maxHeight: 1400,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() => _isUploadingAvatar = true);

      await _apiService.updateProfile(avatarFile: File(picked.path));
      await context.read<AuthProvider>().refreshProfile();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil resmi güncellendi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profil resmi yüklenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    if (user == null) {
      return const Center(child: Text('Kullanıcı bilgisi bulunamadı'));
    }

    final avatarPath = (user['avatar'] ?? '').toString();
    final hasAvatar = avatarPath.isNotEmpty;
    final avatarUrl = hasAvatar ? '${ApiConfig.uploadsUrl}/$avatarPath' : '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Profilim', style: TextStyle(color: Colors.white)),
        elevation: 0,
        backgroundColor: Colors.green[700],
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await context.read<AuthProvider>().refreshProfile();
          await _loadStats();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(
                  color: Colors.green[700],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.3),
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
                        onTap: _openAvatarPicker,
                        child: Stack(
                          children: [
                            Container(
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
                                        memCacheWidth: 300,
                                        memCacheHeight: 300,
                                        placeholder: (_, __) => const Center(
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                        errorWidget: (_, __, ___) => _buildInitialAvatar(user),
                                      )
                                    : _buildInitialAvatar(user),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: _isUploadingAvatar
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.green[700],
                                        ),
                                      )
                                    : Icon(Icons.edit, size: 20, color: Colors.green[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      (user['name'] ?? '').toString(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (user['email'] ?? '').toString(),
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _isLoadingStats
                        ? _buildStatsSkeleton()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem('Aktif İlan', '$_listingCount', Icons.inventory_2),
                              Container(width: 1, height: 40, color: Colors.grey[200]),
                              _buildStatItem('Görüntülenme', _formatViews(_totalViews), Icons.remove_red_eye),
                              Container(width: 1, height: 40, color: Colors.grey[200]),
                              _buildStatItem('Favori İlan', '$_favoriteCount', Icons.favorite),
                            ],
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Hesap Ayarları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildMenuItem(Icons.person_outline, 'Kişisel Bilgiler', () async {
                      final updated = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
                      );
                      if (updated == true && mounted) {
                        await _loadStats();
                      }
                    }),
                    _buildMenuItem(Icons.favorite_border, 'Favori İlanlarım', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                      );
                    }),
                    _buildMenuItem(Icons.notifications_none, 'Bildirimler', () => _showComingSoon(context)),
                    _buildMenuItem(Icons.security, 'Güvenlik ve Şifre', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SecurityPasswordScreen()),
                      );
                    }),
                    const SizedBox(height: 24),
                    const Text('Diğer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildMenuItem(Icons.help_outline, 'Yardım ve Destek', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportScreen()),
                      );
                    }),
                    _buildMenuItem(Icons.info_outline, 'Hakkımızda', () => _showComingSoon(context)),
                    const SizedBox(height: 16),
                    _buildMenuItem(
                      Icons.logout,
                      'Çıkış Yap',
                      () async {
                        await authProvider.logout();
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      },
                      isDestructive: true,
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialAvatar(Map<String, dynamic> user) {
    final name = (user['name'] ?? '').toString();
    final first = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: Text(
        first,
        style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.green[800]),
      ),
    );
  }

  Widget _buildStatsSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatSkeletonBlock(),
          Container(width: 1, height: 40, color: Colors.grey[200]),
          _buildStatSkeletonBlock(),
          Container(width: 1, height: 40, color: Colors.grey[200]),
          _buildStatSkeletonBlock(),
        ],
      ),
    );
  }

  Widget _buildStatSkeletonBlock() {
    return Column(
      children: [
        Container(width: 26, height: 26, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13))),
        const SizedBox(height: 8),
        Container(width: 34, height: 18, color: Colors.white),
        const SizedBox(height: 6),
        Container(width: 62, height: 12, color: Colors.white),
      ],
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.green[600], size: 28),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDestructive ? Colors.red[50] : Colors.green[50],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: isDestructive ? Colors.red : Colors.green[700], size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDestructive ? Colors.red : Colors.black87,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu özellik yakında eklenecek')));
  }
}
