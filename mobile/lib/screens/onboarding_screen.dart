import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';

// ─── Renk sabitleri (uygulamayla birebir) ──────────────────────────────────
const _kPrimary   = Color(0xFF2E7D32);
const _kPrimaryM  = Color(0xFF388E3C);
const _kPrimaryL  = Color(0xFF43A047);
const _kPrimaryXL = Color(0xFF66BB6A);
const _kBg        = Color(0xFFF1F8F1);
const _kTextDark  = Color(0xFF1B3A1C);

// ─── Sayfa verisi ─────────────────────────────────────────────────────────
class _Page {
  final String emoji;
  final IconData icon;
  final String title;
  final String body;
  final List<_Chip> chips;

  const _Page({
    required this.emoji,
    required this.icon,
    required this.title,
    required this.body,
    required this.chips,
  });
}

class _Chip {
  final IconData icon;
  final String label;
  const _Chip(this.icon, this.label);
}

const List<_Page> _pages = [
  _Page(
    emoji: '🐄',
    icon: Icons.store_mall_directory_rounded,
    title: 'Türkiye\'nin\nHayvan Pazarı',
    body: 'Büyükbaş, küçükbaş, kurbanlık ve çiftlik hayvanları. Çiftçiden çiftçiye, güvenli ve hızlı alışveriş.',
    chips: [
      _Chip(Icons.verified_user_rounded,      'Güvenilir satıcılar'),
      _Chip(Icons.inventory_2_rounded,   'Binlerce ilan'),
      _Chip(Icons.handshake_rounded,     'Doğrudan alışveriş'),
    ],
  ),
  _Page(
    emoji: '🔍',
    icon: Icons.search_rounded,
    title: 'İhtiyacını\nHemen Bul',
    body: 'Dana, düve, koç, kuzu, kurbanlık hayvan ve daha fazlası. İl ve ilçene göre filtrele, en yakını bul.',
    chips: [
      _Chip(Icons.my_location_rounded,   'Konum bazlı arama'),
      _Chip(Icons.dashboard_customize_rounded,      'Kategori filtresi'),
      _Chip(Icons.filter_alt_rounded,          'Gelişmiş filtreler'),
    ],
  ),
  _Page(
    emoji: '📱',
    icon: Icons.add_a_photo_rounded,
    title: 'İlanını\nKolayca Ver',
    body: 'Hayvanının fotoğrafını çek, bilgilerini gir, ilanın saniyeler içinde yayında. Ücretsiz ve sınırsız.',
    chips: [
      _Chip(Icons.collections_rounded,  'Çoklu fotoğraf'),
      _Chip(Icons.description_rounded,          'Detaylı bilgi'),
      _Chip(Icons.flash_on_rounded,          'Anında yayın'),
    ],
  ),
  _Page(
    emoji: '💬',
    icon: Icons.chat_bubble_rounded,
    title: 'Alıcıyla\nDirekt İletişim',
    body: 'Satıcıya mesaj at, fiyatı pazarla, anlaşmayı uygulama içinde kapat. Aracısız, doğrudan iletişim.',
    chips: [
      _Chip(Icons.message_rounded,   'Anlık mesajlaşma'),
      _Chip(Icons.notifications_active_rounded, 'Bildirim desteği'),
      _Chip(Icons.mark_chat_read_rounded,      'Okundu bilgisi'),
    ],
  ),
  _Page(
    emoji: '🐾',
    icon: Icons.pets_rounded,
    title: 'Evcil Hayvan\nSahiplendirme',
    body: 'Kedi, köpek, kuş ve daha fazlası sahiplenmeyi bekliyor. Hayvanlara yuva ol, onlara şans ver.',
    chips: [
      _Chip(Icons.favorite_rounded, 'Sahiplendirme ilanları'),
      _Chip(Icons.category_rounded,              'Tüm türler'),
      _Chip(Icons.home_rounded,              'Yuva bul'),
    ],
  ),
];

// ─── Ana ekran ──────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _current = 0;

  // Sadece float animasyonu — sayfa geçişlerinde reset yok
  late final AnimationController _floatCtrl;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _floatCtrl = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);

    _float = Tween<double>(begin: -7, end: 7).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => const LoginScreen(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _next() {
    if (_current < _pages.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // Dalgalı üst bölge
            _WaveHeader(height: size.height * 0.42),

            // Tam ekran içerik
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Üst bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                    child: Row(
                      children: [
                        // Logo
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: _kPrimary.withValues(alpha: 0.25),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Transform.scale(
                            scale: 1.6,
                            child: Image.asset(
                              'assets/logo_high_res.png',
                              width: 26, 
                              height: 26,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.agriculture_rounded,
                                size: 26, 
                                color: _kPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Hayvanyeri',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const Spacer(),
                        if (_current < _pages.length - 1)
                          TextButton(
                            onPressed: _finish,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text(
                              'Atla →',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Sayfalar
                  Expanded(
                    child: PageView.builder(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _current = i),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _pages.length,
                      itemBuilder: (_, i) => _PageBody(
                        page: _pages[i],
                        float: _float,
                      ),
                    ),
                  ),

                  // Alt bar
                  Padding(
                    padding: EdgeInsets.fromLTRB(28, 8, 28, 12 + bottom),
                    child: Row(
                      children: [
                        // Dots
                        Row(
                          children: List.generate(
                            _pages.length,
                            (i) => _Dot(active: i == _current),
                          ),
                        ),
                        const Spacer(),
                        // İleri butonu
                        _NextButton(
                          isLast: _current == _pages.length - 1,
                          onTap: _next,
                        ),
                      ],
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

// ─── Sayfa gövdesi ──────────────────────────────────────────────────────────
class _PageBody extends StatelessWidget {
  final _Page page;
  final Animation<double> float;

  const _PageBody({required this.page, required this.float});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),

            // Yüzen ikon
            AnimatedBuilder(
              animation: float,
              builder: (_, __) => Transform.translate(
                offset: Offset(0, float.value),
                child: _IconCircle(page: page),
              ),
            ),

            const SizedBox(height: 30),

            // Başlık
            Text(
              page.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: _kTextDark,
                height: 1.15,
                letterSpacing: -1.0,
              ),
            ),

            const SizedBox(height: 12),

            // Açıklama
            Text(
              page.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: Colors.grey[600],
                height: 1.6,
                fontWeight: FontWeight.w400,
              ),
            ),

            const SizedBox(height: 24),

            // Özellik chip'leri
            ...page.chips.map((c) => _ChipRow(chip: c)),

            const SizedBox(height: 80), // Alt bar için boşluk
          ],
        ),
      ),
    );
  }
}

// ─── İkon dairesi ───────────────────────────────────────────────────────────
class _IconCircle extends StatelessWidget {
  final _Page page;
  const _IconCircle({required this.page});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Dış glow efekti
        Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _kPrimaryL.withValues(alpha: 0.3),
                _kPrimaryL.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        // Ana daire
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kPrimaryXL, _kPrimaryL, _kPrimary],
            ),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withValues(alpha: 0.45),
                blurRadius: 35,
                offset: const Offset(0, 16),
                spreadRadius: -5,
              ),
              BoxShadow(
                color: _kPrimaryL.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // İç parlama efekti
              Positioned(
                top: 20,
                left: 20,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.4),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Emoji
              Text(
                page.emoji,
                style: const TextStyle(
                  fontSize: 52,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Özellik satırı ─────────────────────────────────────────────────────────
class _ChipRow extends StatelessWidget {
  final _Chip chip;
  const _ChipRow({required this.chip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _kPrimaryXL.withValues(alpha: 0.12),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _kPrimary.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 3),
              spreadRadius: -2,
            ),
            BoxShadow(
              color: _kPrimaryL.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _kPrimaryXL.withValues(alpha: 0.2),
                    _kPrimaryL.withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: _kPrimaryL.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(chip.icon, size: 18, color: _kPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                chip.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _kTextDark,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: _kPrimaryL.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 14,
                color: _kPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dot indikatör ──────────────────────────────────────────────────────────
class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(right: 6),
      width: active ? 22 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? _kPrimary : _kPrimaryXL.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ─── İleri butonu ───────────────────────────────────────────────────────────
class _NextButton extends StatelessWidget {
  final bool isLast;
  final VoidCallback onTap;
  const _NextButton({required this.isLast, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: 52,
        width: isLast ? 130 : 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kPrimaryL, _kPrimary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: _kPrimary.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: isLast
              ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Başla',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 18),
                    ],
                  )
                : const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
        ),
      ),
    );
  }
}

// ─── Dalgalı üst arka plan ──────────────────────────────────────────────────
class _WaveHeader extends StatelessWidget {
  final double height;
  const _WaveHeader({required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kPrimary, _kPrimaryM, _kPrimaryL],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -50, right: -50,
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 40, left: -30,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path();
    p.lineTo(0, size.height - 55);
    p.quadraticBezierTo(
      size.width * 0.28, size.height + 10,
      size.width * 0.55, size.height - 45,
    );
    p.quadraticBezierTo(
      size.width * 0.78, size.height - 90,
      size.width, size.height - 25,
    );
    p.lineTo(size.width, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}
