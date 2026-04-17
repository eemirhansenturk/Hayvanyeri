import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../models/listing.dart';
import '../config/api_config.dart';

class EditListingScreen extends StatefulWidget {
  final Listing listing;

  const EditListingScreen({super.key, required this.listing});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _picker = ImagePicker();

  int _currentStep = 0;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _ageController;
  late final TextEditingController _weightController;
  late final TextEditingController _healthExplanationController;

  late String _category;
  String? _animalType;
  String? _breed;
  late String _listingType;
  late String _gender;
  late String _healthStatus;

  // Location
  List<dynamic> _cities = [];
  List<dynamic> _districts = [];
  String? _selectedCityName;
  String? _selectedCityId;
  String? _selectedDistrictName;
  bool _isLoadingCities = true;
  bool _isLoadingDistricts = false;

  List<String> _selectedVaccines = [];

  // Images
  List<String> _existingImages = [];
  List<String> _deletedImages = [];
  List<File> _newImages = [];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.listing.title);
    _descriptionController = TextEditingController(
      text: widget.listing.description,
    );
    _priceController = TextEditingController(
      text: widget.listing.price > 0
          ? widget.listing.price.toStringAsFixed(0)
          : '',
    );
    _ageController = TextEditingController(text: widget.listing.age ?? '');
    _weightController = TextEditingController(
      text: widget.listing.weight ?? '',
    );

    _category = widget.listing.category;
    _animalType = widget.listing.animalType;
    _breed = widget.listing.breed;
    // Evcil hayvanlarda yasal olarak sadece sahiplendirme yapılabilir
    _listingType = _category == 'evcil' ? 'sahiplendirme' : widget.listing.listingType;
    _gender = widget.listing.gender ?? 'erkek';

    // Parse Health Status
    if (widget.listing.healthStatus != null &&
        widget.listing.healthStatus!.toLowerCase().contains('sağlıksız')) {
      _healthStatus = 'Sağlıksız';
      final parts = widget.listing.healthStatus!.split(':');
      _healthExplanationController = TextEditingController(
        text: parts.length > 1 ? parts[1].trim() : '',
      );
    } else {
      _healthStatus = 'Sağlıklı';
      _healthExplanationController = TextEditingController();
    }

    // Parse Vaccines
    if (widget.listing.vaccines != null &&
        widget.listing.vaccines!.isNotEmpty) {
      _selectedVaccines = widget.listing.vaccines!
          .split(',')
          .map((e) => e.trim())
          .toList();
    }

    // Existing Images
    _existingImages = List<String>.from(widget.listing.images);

    _selectedCityName = widget.listing.city;
    _selectedDistrictName = widget.listing.district;

    _fetchCities();
  }

  Future<void> _fetchCities() async {
    try {
      final data = await _apiService.getCities();
      if (mounted) {
        setState(() {
          _cities = data;
          _isLoadingCities = false;
        });

        if (_selectedCityName != null && _selectedCityName!.isNotEmpty) {
          try {
            final cityObj = _cities.firstWhere(
              (c) => c['label'] == _selectedCityName,
            );
            _selectedCityId = cityObj['tkgm_id'];
            _fetchDistricts(_selectedCityId!);
          } catch (e) {
            // City not found in list, fallback
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

  Future<void> _pickImages() async {
    final pickedFiles = await _picker.pickMultiImage(
      imageQuality: 75,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (pickedFiles.isNotEmpty) {
      final newImageFiles = pickedFiles
          .map((xFile) => File(xFile.path))
          .toList();
      setState(() {
        _newImages.addAll(newImageFiles);
        if ((_existingImages.length + _newImages.length) > 8) {
          final allowedNew = 8 - _existingImages.length;
          if (allowedNew > 0) {
            _newImages = _newImages.sublist(0, allowedNew);
          } else {
            _newImages = [];
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maksimum toplam 8 resim ekleyebilirsiniz'),
            ),
          );
        }
      });
    }
  }

  void _removeExistingImage(int index) {
    setState(() {
      _deletedImages.add(_existingImages[index]);
      _existingImages.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  Future<void> _submitData() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen zorunlu alanları doldurun')),
      );
      return;
    }

    if (_existingImages.isEmpty && _newImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az 1 fotoğraf bırakmalısınız')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String finalHealthStatus = _healthStatus == 'Sağlıklı'
          ? 'Sağlıklı'
          : 'Sağlıksız: ${_healthExplanationController.text}';

      final data = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _category,
        'animalType': _animalType ?? '',
        'listingType': _listingType,
        'price': _listingType == 'sahiplendirme'
            ? '0'
            : _priceController.text.trim(),
        'breed': _breed ?? '',
        'age': _ageController.text.trim(),
        'gender': _gender,
        'weight': _weightController.text.trim(),
        'healthStatus': finalHealthStatus,
        'vaccines': _selectedVaccines.join(','),
        'city': _selectedCityName ?? '',
        'district': _selectedDistrictName ?? '',
      };

      await _apiService.updateListingTextAndImages(
        widget.listing.id,
        data,
        _newImages,
        _deletedImages,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İlan başarıyla güncellendi!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Premium light gray background
      appBar: AppBar(
        title: const Text('İlanı Düzenle', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildCustomStepper(),
                  Expanded(
                    child: SafeArea(
                      bottom: true,
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCurrentStepContent(),
                            const SizedBox(height: 32),
                            _buildControls(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _handleCancel() {
    if (_currentStep > 0) setState(() => _currentStep -= 1);
  }

  void _handleContinue() {
    FocusScope.of(context).unfocus();

    if (_currentStep == 0) {
      if (_animalType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen hayvan türünü seçin')),
        );
        return;
      }
      setState(() => _currentStep += 1);
    } else if (_currentStep == 1) {
      if (_ageController.text.isNotEmpty &&
          !RegExp(r'^\d+(,\d+)?$').hasMatch(_ageController.text.trim())) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              'Hatalı Yaş Girdisi',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Lütfen yaşı 2,5 veya 3 şeklinde, sadece virgül kullanarak girin.\n(Nokta kullanmayınız.)',
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tamam', style: TextStyle(color: Colors.green)),
              ),
            ],
          ),
        );
        return;
      }
      if (_healthStatus == 'Sağlıksız' &&
          _healthExplanationController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen hastalık/sorun açıklamasını girin'),
          ),
        );
        return;
      }
      setState(() => _currentStep += 1);
    } else if (_currentStep == 2) {
      if (_titleController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen ilan başlığını girin')),
        );
        return;
      }
      if (_listingType != 'sahiplendirme' &&
          _priceController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen fiyat bilgisini girin')),
        );
        return;
      }
      if (_selectedCityName == null || _selectedDistrictName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen şehir ve ilçe seçin')),
        );
        return;
      }
      if (_descriptionController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen detaylı açıklamayı girin')),
        );
        return;
      }
      setState(() => _currentStep += 1);
    } else {
      _submitData();
    }
  }

  InputDecoration _buildInputDecoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.green[700]),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.green.shade600, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildStepCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: child,
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1BasicInfo();
      case 1:
        return _buildStep2Details();
      case 2:
        return _buildStep3Content();
      case 3:
        return _buildStep4Photos();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildControls() {
    final isLastStep = _currentStep == 3;
    return Row(
      children: [
        if (_currentStep > 0)
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: _handleCancel,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                side: BorderSide(color: Colors.green[700]!, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Geri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[800])),
            ),
          ),
        if (_currentStep > 0) const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _handleContinue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: Colors.green.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(isLastStep ? 'Güncelle' : 'Devam Et', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomStepper() {
    final steps = ['Tür', 'Detay', 'İçerik', 'Görsel'];
    return Container(
      padding: const EdgeInsets.only(top: 20, bottom: 16, left: 24, right: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          Widget stepCircle = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive ? Colors.green[600] : (isCompleted ? Colors.green[600] : Colors.grey[100]),
                  shape: BoxShape.circle,
                  border: Border.all(color: isActive ? Colors.green[100]! : (isCompleted ? Colors.green[600]! : Colors.grey.shade300), width: isActive ? 4 : 1),
                  boxShadow: isActive ? [BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check_rounded, size: 20, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                steps[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive || isCompleted ? Colors.green[800] : Colors.grey[500],
                ),
              ),
            ],
          );

          if (index == steps.length - 1) {
            return stepCircle;
          }

          return Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                stepCircle,
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(top: 17, left: 4, right: 4),
                    height: 3,
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green[600] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1BasicInfo() {
    return _buildStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hayvan Kategorisi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppConstants.categoryAnimals.keys.map((cat) {
              final isSelected = _category == cat;
              return ChoiceChip(
                label: Text(cat[0].toUpperCase() + cat.substring(1), style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                selected: isSelected,
                selectedColor: Colors.green[700],
                backgroundColor: Colors.grey.shade100,
                elevation: isSelected ? 2 : 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _category = cat;
                      _animalType = AppConstants.getAnimalsForCategory(_category).first;
                      _breed = null;
                      // Evcil kategorisinde yasal olarak sadece sahiplendirme yapılabilir
                      if (_category == 'evcil') {
                        _listingType = 'sahiplendirme';
                      }
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _animalType,
            isExpanded: true,
            decoration: _buildInputDecoration('Hayvan Türü *', Icons.pets),
            items: AppConstants.getAnimalsForCategory(_category).map((animal) {
              return DropdownMenuItem(value: animal, child: Text(animal));
            }).toList(),
            onChanged: (v) {
              setState(() {
                _animalType = v;
                _breed = null;
              });
            },
          ),
          const SizedBox(height: 24),
          const Text('İlan Tipi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 12),
          if (_category == 'evcil') ...[  
            // Yasal bilgilendirme - evcil hayvan satışı devlet onaylı olmalı
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber[300]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.amber[800], size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yasal Bilgilendirme',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[900], fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Türkiye\'de evcil hayvan satışı devlet onaylı yerlerde yapılabilir. Bu nedenle evcil hayvanlar sadece \'Sahiplendirme\' ilanı olarak verilebilmektedir.',
                          style: TextStyle(color: Colors.amber[900], fontSize: 12, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green[700],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Sahiplendirme ✓',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[  
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['satılık', 'sahiplendirme'].map((type) {
                final isSelected = _listingType == type;
                return ChoiceChip(
                  label: Text(type[0].toUpperCase() + type.substring(1), style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  selected: isSelected,
                  selectedColor: Colors.green[700],
                  backgroundColor: Colors.grey.shade100,
                  elevation: isSelected ? 2 : 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
                  onSelected: (selected) {
                    if (selected) setState(() => _listingType = type);
                  },
                );
              }).toList(),
            ),
          ],
        ],
      )
    );
  }

  Widget _buildStep2Details() {
    return _buildStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _breed,
            isExpanded: true,
            decoration: _buildInputDecoration('Irk', Icons.pets_outlined),
            items: AppConstants.getBreedsForAnimal(_animalType ?? '').map((breed) {
              return DropdownMenuItem(value: breed, child: Text(breed));
            }).toList(),
            onChanged: (v) => setState(() => _breed = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _ageController,
                  decoration: _buildInputDecoration('Yaş', Icons.calendar_today),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      return newValue.copyWith(
                        text: newValue.text.replaceAll('.', ','),
                      );
                    }),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _gender,
                  isExpanded: true,
                  decoration: _buildInputDecoration('Cinsiyet *', Icons.wc),
                  items: const [
                    DropdownMenuItem(value: 'erkek', child: Text('Erkek')),
                    DropdownMenuItem(value: 'dişi', child: Text('Dişi')),
                  ],
                  onChanged: (v) => setState(() => _gender = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _weightController,
            decoration: _buildInputDecoration('Ağırlık', Icons.monitor_weight, hint: 'Örn: 450 kg'),
          ),
          const SizedBox(height: 16),
          
          DropdownButtonFormField<String>(
            value: _healthStatus,
            isExpanded: true,
            decoration: _buildInputDecoration('Sağlık Durumu', Icons.health_and_safety),
            items: const [
              DropdownMenuItem(value: 'Sağlıklı', child: Text('Sağlıklı')),
              DropdownMenuItem(value: 'Sağlıksız', child: Text('Sağlıksız')),
            ],
            onChanged: (v) => setState(() {
              _healthStatus = v!;
              if (_healthStatus == 'Sağlıklı') {
                _healthExplanationController.clear();
              }
            }),
          ),
          
          if (_healthStatus == 'Sağlıksız') ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _healthExplanationController,
              decoration: _buildInputDecoration('Hastalık / Sorun Açıklaması *', Icons.warning_amber),
              maxLines: 2,
              validator: (v) => _healthStatus == 'Sağlıksız' && (v?.isEmpty ?? true) ? 'Açıklama gerekli' : null,
            ),
          ],

          const SizedBox(height: 24),
          const Text('Yapılan Aşılar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppConstants.vaccines.map((vaccine) {
              final isSelected = _selectedVaccines.contains(vaccine);
              return FilterChip(
                label: Text(vaccine, style: TextStyle(color: isSelected ? Colors.green[900] : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                selected: isSelected,
                selectedColor: Colors.green[100],
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSelected ? Colors.green.shade400 : Colors.grey.shade300)),
                checkmarkColor: Colors.green[800],
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedVaccines.add(vaccine);
                    } else {
                      _selectedVaccines.remove(vaccine);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      )
    );
  }

  Widget _buildStep3Content() {
    return _buildStepCard(
      child: Column(
        children: [
          TextFormField(
            controller: _titleController,
            decoration: _buildInputDecoration('İlan Başlığı *', Icons.title),
            validator: (v) => v?.trim().isEmpty ?? true ? 'Başlık gerekli' : null,
          ),
          const SizedBox(height: 16),
          if (_listingType != 'sahiplendirme')
            TextFormField(
              controller: _priceController,
              decoration: _buildInputDecoration('Fiyat (₺) *', Icons.attach_money),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (_listingType != 'sahiplendirme')
                  ? (v) => v?.trim().isEmpty ?? true ? 'Fiyat gerekli' : null
                  : null,
            ),
          if (_listingType != 'sahiplendirme') const SizedBox(height: 16),
          
          // Location Setup
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _isLoadingCities
                    ? const Center(child: CircularProgressIndicator())
                    : DropdownButtonFormField<String>(
                        value: _selectedCityName,
                        isExpanded: true,
                        decoration: _buildInputDecoration('Şehir *', Icons.location_city),
                        items: _cities.map((city) {
                          return DropdownMenuItem<String>(
                            value: city['label'],
                            child: Text(city['label']),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          final cityObj = _cities.firstWhere((c) => c['label'] == v);
                          setState(() {
                            _selectedCityName = v;
                            _selectedCityId = cityObj['tkgm_id'];
                            _selectedDistrictName = null;
                          });
                          _fetchDistricts(_selectedCityId!);
                        },
                        validator: (v) => v == null ? 'Şehir seçin' : null,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _isLoadingDistricts
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        value: _selectedDistrictName,
                        isExpanded: true,
                        decoration: _buildInputDecoration('İlçe *', Icons.location_on),
                        items: _districts.map((district) {
                          return DropdownMenuItem<String>(
                            value: district['label'],
                            child: Text(district['label']),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedDistrictName = v;
                          });
                        },
                        validator: (v) => v == null ? 'İlçe seçin' : null,
                        disabledHint: const Text('Önce Şehir Seçin'),
                      ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            decoration: _buildInputDecoration('Detaylı Açıklama *', Icons.description),
            maxLines: 5,
            validator: (v) => v?.trim().isEmpty ?? true ? 'Açıklama gerekli' : null,
          ),
        ],
      )
    );
  }

  Widget _buildStep4Photos() {
    return _buildStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Görseller', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Text('İlanınız için en fazla 8 adet fotoğraf yükleyebilirsiniz. Kaliteli ve net fotoğraflar ilanınızı öne çıkarır.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.green.shade50.withOpacity(0.5),
              border: Border.all(color: Colors.green.shade300, width: 2, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(24),
            ),
            child: InkWell(
              onTap: (_existingImages.length + _newImages.length) < 8 ? _pickImages : null,
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.1), blurRadius: 8)],
                    ),
                    child: Icon(Icons.add_a_photo_rounded, size: 32, color: Colors.green[700]),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Fotoğraf Ekle (${_existingImages.length + _newImages.length}/8)',
                    style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (_existingImages.isEmpty && _newImages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text('En az 1 fotoğraf zorunludur', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Existing Network Images
          if (_existingImages.isNotEmpty) ...[
            const Text(
              'Kayıtlı Fotoğraflar:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _existingImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: '${ApiConfig.uploadsUrl}/${_existingImages[index]}',
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: Colors.grey[200], child: const CircularProgressIndicator()),
                          errorWidget: (context, url, _) => const Icon(Icons.error),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => _removeExistingImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                          ),
                          child: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // Newly picked File Images
          if (_newImages.isNotEmpty) ...[
            const Text(
              'Yeni Eklenecek Fotoğraflar:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _newImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(_newImages[index], fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => _removeNewImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                          ),
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      )
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _healthExplanationController.dispose();
    super.dispose();
  }
}
