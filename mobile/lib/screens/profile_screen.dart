import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'favorites_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
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
  int _notificationCount = 0;
  bool _isLoadingStats = true;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadNotificationCount();
    _setupNotificationListener();
  }

  @override
  void dispose() {
    SocketService().removeNotificationCountListener(_onNotificationCountChanged);
    super.dispose();
  }

  void _setupNotificationListener() {
    SocketService().addNotificationCountListener(_onNotificationCountChanged);
  }

  void _onNotificationCountChanged(int count) {
    if (mounted) {
      setState(() => _notificationCount = count);
    }
  }

  Future<void> _loadNotificationCount() async {
    try {
      final count = await _apiService.getUnreadNotificationCount();
      if (mounted) {
        setState(() => _notificationCount = count);
        SocketService().notificationCount = count;
      }
    } catch (_) {}
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
        _listingCount = listings.where((item) => item['status'] == 'aktif').length;
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

  Future<void> _openAvatarPicker(bool hasAvatar) async {
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
              if (hasAvatar)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Profil Resmini Kaldır', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _removeAvatar();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _removeAvatar() async {
    try {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = true);

      await _apiService.updateProfile(removeAvatar: true);
      await context.read<AuthProvider>().refreshProfile();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil resmi kaldırıldı')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profil resmi kaldırılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  void _viewAvatar(String avatarUrl, dynamic user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: avatarUrl.isNotEmpty
                    ? InteractiveViewer(
                        child: CachedNetworkImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                          errorWidget: (_, __, ___) => _buildFullScreenInitialAvatar(user),
                        ),
                      )
                    : _buildFullScreenInitialAvatar(user),
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

  Widget _buildFullScreenInitialAvatar(Map<String, dynamic> user) {
    final name = (user['name'] ?? '').toString();
    final first = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green[400]!,
            Colors.green[700]!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Center(
        child: Text(
          first,
          style: const TextStyle(
            fontSize: 120,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
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
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _viewAvatar(avatarUrl, user),
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
                                        memCacheWidth: 300,
                                        memCacheHeight: 300,
                                        placeholder: (_, __) => Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                        errorWidget: (_, __, ___) => _buildInitialAvatar(user),
                                      )
                                    : _buildInitialAvatar(user),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _openAvatarPicker(hasAvatar),
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
                          ),
                        ],
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
                    _buildMenuItem(
                      Icons.notifications_none,
                      'Bildirimler',
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        );
                        if (mounted) {
                          await _loadNotificationCount();
                        }
                      },
                      badge: _notificationCount > 0 ? _notificationCount : null,
                    ),
                    _buildMenuItem(Icons.security, 'Güvenlik ve Şifre', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SecurityPasswordScreen()),
                      );
                    }),
                    _buildMenuItem(
                      Icons.delete_forever,
                      'Hesabı Sil',
                      () => _showDeleteAccountDialog(),
                    ),
                    const SizedBox(height: 24),
                    const Text('Diğer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildMenuItem(Icons.help_outline, 'Yardım ve Destek', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportScreen()),
                      );
                    }),
                    _buildMenuItem(Icons.star_rate_rounded, 'Uygulamayı Değerlendir', _rateApp),
                    _buildMenuItem(Icons.info_outline, 'Hakkımızda', () => _showComingSoon(context)),
                    const SizedBox(height: 16),
                    _buildMenuItem(
                      Icons.logout,
                      'Çıkış Yap',
                      () async {
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
                                    child: Icon(Icons.logout, color: Colors.red[700], size: 36),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('Çıkış Yap', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Hesabınızdan çıkış yapmak istediğinize emin misiniz?',
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
                                          child: const Text('Çıkış Yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        
                        if (confirm == true) {
                          await authProvider.logout();
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (route) => false,
                            );
                          }
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

  Future<void> _rateApp() async {
    // Paket adı + App Store ID’yi buraya yaz
    const androidPackageName = 'com.qparkai.hayvanyeri';
    const iosAppId = '6762561614';

    final uri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/app/id$iosAppId?action=write-review')
        : Uri.parse('market://details?id=$androidPackageName');

    final fallbackUri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/app/id$iosAppId?action=write-review')
        : Uri.parse('https://play.google.com/store/apps/details?id=$androidPackageName');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mağaza açılamadı')),
        );
      }
    }
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false, int? badge}) {
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null && badge > 0)
              Container(
                padding: const EdgeInsets.all(6),
                margin: const EdgeInsets.only(right: 8),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isDeleting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delete_forever, color: Colors.red[700], size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Hesabı Sil',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Warning text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Bu işlem geri alınamaz!',
                            style: TextStyle(
                              color: Colors.red[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hesabınızı sildiğinizde tüm ilanlarınız, mesajlarınız ve favori listeniz kalıcı olarak silinecektir.',
                        style: TextStyle(color: Colors.red[800], fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Devam etmek için şifrenizi girin',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  enabled: !isDeleting,
                  decoration: InputDecoration(
                    hintText: 'Şifreniz',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[500], size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey[500],
                        size: 20,
                      ),
                      onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.red[400]!, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'İptal',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isDeleting
                            ? null
                            : () async {
                                final password = passwordController.text.trim();
                                if (password.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Lütfen şifrenizi girin')),
                                  );
                                  return;
                                }
                                setDialogState(() => isDeleting = true);
                                try {
                                  await _apiService.deleteAccount(password: password);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    await context.read<AuthProvider>().logout();
                                    if (context.mounted) {
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                                        (route) => false,
                                      );
                                    }
                                  }
                                } catch (e) {
                                  setDialogState(() => isDeleting = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e.toString().replaceAll('Exception: ', '')),
                                        backgroundColor: Colors.red[600],
                                      ),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.red[600],
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isDeleting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Hesabı Sil',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    passwordController.dispose();
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu özellik yakında eklenecek')));
  }
}
