import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

class AdvancedFilterSheet extends StatefulWidget {
  final Map<String, dynamic>? initialFilters;

  const AdvancedFilterSheet({super.key, this.initialFilters});

  @override
  State<AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<AdvancedFilterSheet> {
  final ApiService _apiService = ApiService();

  // Cascade state
  String? _selectedCategory;
  List<String> _selectedAnimalTypes = [];
  List<String> _selectedBreeds = [];

  // Listing type
  String? _listingType; // null = tümü, 'satılık', 'sahiplendirme'

  // Gender
  String? _gender; // null = tümü

  // Health
  String? _healthStatus; // null = tümü, 'Sağlıklı', 'Sağlıksız'

  // Age range
  final _minAgeController = TextEditingController();
  final _maxAgeController = TextEditingController();

  // Weight range
  final _minWeightController = TextEditingController();
  final _maxWeightController = TextEditingController();

  // Price range
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();

  // Location
  List<dynamic> _cities = [];
  List<dynamic> _districts = [];
  String? _selectedCityName;
  String? _selectedCityId;
  String? _selectedDistrictName;
  bool _isLoadingCities = true;
  bool _isLoadingDistricts = false;

  static const _green = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _loadFromInitialFilters();
    _fetchCities();
  }

  void _loadFromInitialFilters() {
    final f = widget.initialFilters;
    if (f == null) return;
    _selectedCategory = f['category'];
    if (f['animalType'] != null) {
      _selectedAnimalTypes = f['animalType'].split(',').toList();
    }
    if (f['breed'] != null) {
      _selectedBreeds = f['breed'].split(',').toList();
    }
    _listingType = f['listingType'];
    _gender = f['gender'];
    _healthStatus = f['healthStatus'];
    if (f['minAge'] != null) _minAgeController.text = f['minAge'].toString();
    if (f['maxAge'] != null) _maxAgeController.text = f['maxAge'].toString();
    if (f['minWeight'] != null) _minWeightController.text = f['minWeight'].toString();
    if (f['maxWeight'] != null) _maxWeightController.text = f['maxWeight'].toString();
    if (f['minPrice'] != null) _minPriceController.text = f['minPrice'].toString();
    if (f['maxPrice'] != null) _maxPriceController.text = f['maxPrice'].toString();
    _selectedCityName = f['city'];
    _selectedDistrictName = f['district'];
  }

  Future<void> _fetchCities() async {
    try {
      final data = await _apiService.getCities();
      if (mounted) {
        setState(() {
          _cities = data;
          _isLoadingCities = false;
        });
        // If we have a city name from initial filters, load its districts
        if (_selectedCityName != null) {
          final cityObj = _cities.firstWhere(
            (c) => c['label'] == _selectedCityName,
            orElse: () => null,
          );
          if (cityObj != null) {
            _selectedCityId = cityObj['tkgm_id'];
            _fetchDistricts(_selectedCityId!);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCities = false);
    }
  }

  Future<void> _fetchDistricts(String cityId) async {
    setState(() {
      _isLoadingDistricts = true;
      _districts = [];
    });
    try {
      final data = await _apiService.getDistricts(cityId);
      if (mounted) {
        setState(() {
          _districts = data;
          _isLoadingDistricts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDistricts = false);
    }
  }

  @override
  void dispose() {
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _minWeightController.dispose();
    _maxWeightController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final Map<String, dynamic> filters = {};

    if (_selectedCategory != null) filters['category'] = _selectedCategory;
    if (_selectedAnimalTypes.isNotEmpty) filters['animalType'] = _selectedAnimalTypes.join(',');
    if (_selectedBreeds.isNotEmpty) filters['breed'] = _selectedBreeds.join(',');
    if (_listingType != null) filters['listingType'] = _listingType;
    if (_gender != null) filters['gender'] = _gender;
    if (_healthStatus != null) filters['healthStatus'] = _healthStatus;
    if (_minAgeController.text.isNotEmpty) filters['minAge'] = _minAgeController.text;
    if (_maxAgeController.text.isNotEmpty) filters['maxAge'] = _maxAgeController.text;
    if (_minWeightController.text.isNotEmpty) filters['minWeight'] = _minWeightController.text;
    if (_maxWeightController.text.isNotEmpty) filters['maxWeight'] = _maxWeightController.text;
    if (_minPriceController.text.isNotEmpty) filters['minPrice'] = _minPriceController.text.replaceAll('.', '');
    if (_maxPriceController.text.isNotEmpty) filters['maxPrice'] = _maxPriceController.text.replaceAll('.', '');
    if (_selectedCityName != null) filters['city'] = _selectedCityName;
    if (_selectedDistrictName != null) filters['district'] = _selectedDistrictName;

    Navigator.pop(context, filters);
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedAnimalTypes.clear();
      _selectedBreeds.clear();
      _listingType = null;
      _gender = null;
      _healthStatus = null;
      _selectedCityName = null;
      _selectedCityId = null;
      _selectedDistrictName = null;
      _districts = [];
      _minAgeController.clear();
      _maxAgeController.clear();
      _minWeightController.clear();
      _maxWeightController.clear();
      _minPriceController.clear();
      _maxPriceController.clear();
    });
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategory != null) count++;
    if (_selectedAnimalTypes.isNotEmpty) count++;
    if (_selectedBreeds.isNotEmpty) count++;
    if (_listingType != null) count++;
    if (_gender != null) count++;
    if (_healthStatus != null) count++;
    if (_minAgeController.text.isNotEmpty || _maxAgeController.text.isNotEmpty) count++;
    if (_minWeightController.text.isNotEmpty || _maxWeightController.text.isNotEmpty) count++;
    if (_minPriceController.text.isNotEmpty || _maxPriceController.text.isNotEmpty) count++;
    if (_selectedCityName != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAF8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                _buildSectionCard(
                  title: '🐄 Hayvan Kategorisi',
                  child: _buildCategoryGrid(),
                ),
                const SizedBox(height: 12),
                if (_selectedCategory != null) ...[
                  _buildSectionCard(
                    title: '🏷️ Hayvan Türü',
                    child: _buildAnimalTypeGrid(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_hasAnyBreeds()) ...[
                  _buildSectionCard(
                    title: '🧬 Irk',
                    child: _buildBreedGrid(),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildSectionCard(
                  title: '📋 İlan Tipi',
                  child: _buildChipRow(
                    items: const ['Tümü', 'Satılık', 'Sahiplendirme'],
                    selected: _listingType == null
                        ? 'Tümü'
                        : _listingType == 'satılık'
                            ? 'Satılık'
                            : 'Sahiplendirme',
                    onSelect: (v) {
                      setState(() {
                        _listingType = v == 'Tümü'
                            ? null
                            : v == 'Satılık'
                                ? 'satılık'
                                : 'sahiplendirme';
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionCard(
                  title: '⚥ Cinsiyet',
                  child: _buildChipRow(
                    items: const ['Tümü', 'Erkek', 'Dişi'],
                    selected: _gender == null
                        ? 'Tümü'
                        : _gender == 'erkek'
                            ? 'Erkek'
                            : 'Dişi',
                    onSelect: (v) {
                      setState(() {
                        _gender = v == 'Tümü'
                            ? null
                            : v == 'Erkek'
                                ? 'erkek'
                                : 'dişi';
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionCard(
                  title: '🏥 Sağlık Durumu',
                  child: _buildChipRow(
                    items: const ['Tümü', 'Sağlıklı', 'Sağlıksız'],
                    selected: _healthStatus ?? 'Tümü',
                    onSelect: (v) {
                      setState(() {
                        _healthStatus = v == 'Tümü' ? null : v;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionCard(
                  title: '📅 Yaş Aralığı (yıl)',
                  child: _buildRangeRow(
                    minController: _minAgeController,
                    maxController: _maxAgeController,
                    minHint: 'Min yaş',
                    maxHint: 'Max yaş',
                    suffix: 'yıl',
                    isDecimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionCard(
                  title: '⚖️ Ağırlık Aralığı (kg)',
                  child: _buildRangeRow(
                    minController: _minWeightController,
                    maxController: _maxWeightController,
                    minHint: 'Min ağırlık',
                    maxHint: 'Max ağırlık',
                    suffix: 'kg',
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionCard(
                  title: '💰 Fiyat Aralığı',
                  child: _buildRangeRow(
                    minController: _minPriceController,
                    maxController: _maxPriceController,
                    minHint: 'Min fiyat',
                    maxHint: 'Max fiyat',
                    suffix: '₺',
                    isPrice: true,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionCard(
                  title: '📍 Konum',
                  child: _buildLocationSection(),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detaylı Arama',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (_activeFilterCount > 0)
                        Text(
                          '$_activeFilterCount filtre aktif',
                          style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
                if (_activeFilterCount > 0) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Aramayı Sıfırla'),
                            content: const Text('Tüm arama ve filtreleri temizleyip en başa dönmek istediğinize emin misiniz?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sıfırla', style: TextStyle(color: Colors.blue))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          _clearFilters();
                          if (context.mounted) Navigator.pop(context, {'reset': true});
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sync_rounded, size: 18, color: Colors.blue[600]),
                              const SizedBox(width: 2),
                              Text('Sıfırla', style: TextStyle(color: Colors.blue[600], fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Filtreleri Temizle'),
                            content: const Text('Seçili filtreleri temizlemek istediğinize emin misiniz? (Sonuçlar görünmez, sadece form temizlenir)'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Temizle', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          _clearFilters();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.filter_alt_off_rounded, size: 18, color: Colors.red[500]),
                              const SizedBox(width: 2),
                              Text('Temizle', style: TextStyle(color: Colors.red[500], fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 0),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final categories = AppConstants.categoryAnimals.keys.toList();
    final icons = {
      'büyükbaş': '🐄',
      'küçükbaş': '🐑',
      'kanatlı': '🐔',
      'evcil': '🐾',
      'diğer': '⋯',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        final isSelected = _selectedCategory == cat;
        return GestureDetector(
          onTap: () {
            setState(() {
              if (_selectedCategory == cat) {
                _selectedCategory = null;
                _selectedAnimalTypes.clear();
                _selectedBreeds.clear();
              } else {
                _selectedCategory = cat;
                _selectedAnimalTypes.clear();
                _selectedBreeds.clear();
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? _green : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _green : Colors.grey[200]!,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icons[cat] ?? '🐾', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  cat[0].toUpperCase() + cat.substring(1),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isSelected ? Colors.white : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAnimalTypeGrid() {
    final animals = AppConstants.getAnimalsForCategory(_selectedCategory!);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: animals.map((animal) {
        final isSelected = _selectedAnimalTypes.contains(animal);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedAnimalTypes.remove(animal);
              } else {
                _selectedAnimalTypes.add(animal);
              }
              _selectedBreeds.clear();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? _green : Colors.grey[200]!,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              animal,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
                color: isSelected ? _green : Colors.grey[800],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  bool _hasAnyBreeds() {
    if (_selectedAnimalTypes.isEmpty) return false;
    for (var type in _selectedAnimalTypes) {
      final b = AppConstants.getBreedsForAnimal(type);
      if (b.isNotEmpty && b.first != 'Belirtilmemiş') return true;
    }
    return false;
  }

  Widget _buildBreedGrid() {
    List<String> combinedBreeds = [];
    for (var type in _selectedAnimalTypes) {
      final b = AppConstants.getBreedsForAnimal(type);
      if (b.isNotEmpty && b.first != 'Belirtilmemiş') {
        combinedBreeds.addAll(b);
      }
    }
    final breeds = combinedBreeds.toSet().toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: breeds.map((breed) {
        final isSelected = _selectedBreeds.contains(breed);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedBreeds.remove(breed);
              } else {
                _selectedBreeds.add(breed);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? _green : Colors.grey[200]!,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              breed,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                color: isSelected ? _green : Colors.grey[700],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChipRow({
    required List<String> items,
    required String selected,
    required Function(String) onSelect,
  }) {
    return Row(
      children: items.map((item) {
        final isSelected = selected == item;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: item == items.last ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _green : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? _green : Colors.grey[200]!,
                ),
              ),
              child: Text(
                item,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                  color: isSelected ? Colors.white : Colors.grey[700],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRangeRow({
    required TextEditingController minController,
    required TextEditingController maxController,
    required String minHint,
    required String maxHint,
    required String suffix,
    bool isDecimal = false,
    bool isPrice = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildRangeInput(
            controller: minController,
            hint: minHint,
            suffix: suffix,
            isDecimal: isDecimal,
            isPrice: isPrice,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            width: 20,
            height: 2,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        Expanded(
          child: _buildRangeInput(
            controller: maxController,
            hint: maxHint,
            suffix: suffix,
            isDecimal: isDecimal,
            isPrice: isPrice,
          ),
        ),
      ],
    );
  }

  Widget _buildRangeInput({
    required TextEditingController controller,
    required String hint,
    required String suffix,
    bool isDecimal = false,
    bool isPrice = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: isPrice
          ? [ThousandsSeparatorInputFormatter()]
          : isDecimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))]
              : [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.normal),
        suffixText: suffix,
        suffixStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAF8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _green, width: 1.5),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildLocationSection() {
    return Column(
      children: [
        // City dropdown
        _isLoadingCities
            ? const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              ))
            : _buildLocationDropdown(
                hint: 'İl seçin',
                icon: Icons.location_city_outlined,
                value: _selectedCityName,
                items: _cities.map<String>((c) => c['label'] as String).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final cityObj = _cities.firstWhere((c) => c['label'] == v);
                  setState(() {
                    _selectedCityName = v;
                    _selectedCityId = cityObj['tkgm_id'];
                    _selectedDistrictName = null;
                    _districts = [];
                  });
                  _fetchDistricts(_selectedCityId!);
                },
                onClear: () {
                  setState(() {
                    _selectedCityName = null;
                    _selectedCityId = null;
                    _selectedDistrictName = null;
                    _districts = [];
                  });
                },
              ),
        if (_selectedCityName != null) ...[
          const SizedBox(height: 12),
          _isLoadingDistricts
              ? const Center(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                ))
              : _buildLocationDropdown(
                  hint: 'İlçe seçin',
                  icon: Icons.location_on_outlined,
                  value: _selectedDistrictName,
                  items: _districts.map<String>((d) => d['label'] as String).toList(),
                  onChanged: (v) {
                    setState(() => _selectedDistrictName = v);
                  },
                  onClear: () {
                    setState(() => _selectedDistrictName = null);
                  },
                ),
        ],
      ],
    );
  }

  Widget _buildLocationDropdown({
    required String hint,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF8),
        border: Border.all(
          color: value != null ? _green : Colors.grey[200]!,
          width: value != null ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value != null ? _green : Colors.grey[500]),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                hint: Text(hint, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                items: items.map((item) {
                  return DropdownMenuItem<String>(value: item, child: Text(item));
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close, size: 16, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, -4))],
      ),
      child: Row(
        children: [
          // Active filter count badge
          if (_activeFilterCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, size: 18, color: Colors.grey[700]),
                  const SizedBox(width: 6),
                  Text(
                    '$_activeFilterCount',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ElevatedButton(
              onPressed: _applyFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text(
                'Sonuçları Göster',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
