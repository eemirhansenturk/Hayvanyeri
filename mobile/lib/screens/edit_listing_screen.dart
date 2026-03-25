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
    _listingType = widget.listing.listingType;
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
      imageQuality: 85,
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('İlanı Düzenle'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(primary: Colors.green[700]!),
                ),
                child: Stepper(
                  type: StepperType.horizontal,
                  currentStep: _currentStep,
                  elevation: 0,
                  onStepCancel: () {
                    if (_currentStep > 0) setState(() => _currentStep -= 1);
                  },
                  onStepContinue: () {
                    FocusScope.of(context).unfocus();

                    if (_currentStep == 0) {
                      if (_animalType == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lütfen hayvan türünü seçin'),
                          ),
                        );
                        return;
                      }
                      setState(() => _currentStep += 1);
                    } else if (_currentStep == 1) {
                      if (_ageController.text.isNotEmpty &&
                          !RegExp(
                            r'^\d+(,\d+)?$',
                          ).hasMatch(_ageController.text.trim())) {
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
                                child: const Text(
                                  'Tamam',
                                  style: TextStyle(color: Colors.green),
                                ),
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
                            content: Text(
                              'Lütfen hastalık/sorun açıklamasını girin',
                            ),
                          ),
                        );
                        return;
                      }
                      setState(() => _currentStep += 1);
                    } else if (_currentStep == 2) {
                      if (_titleController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lütfen ilan başlığını girin'),
                          ),
                        );
                        return;
                      }
                      if (_listingType != 'sahiplendirme' &&
                          _priceController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lütfen fiyat bilgisini girin'),
                          ),
                        );
                        return;
                      }
                      if (_selectedCityName == null ||
                          _selectedDistrictName == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lütfen şehir ve ilçe seçin'),
                          ),
                        );
                        return;
                      }
                      if (_descriptionController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lütfen detaylı açıklamayı girin'),
                          ),
                        );
                        return;
                      }
                      setState(() => _currentStep += 1);
                    } else {
                      _submitData();
                    }
                  },
                  controlsBuilder:
                      (BuildContext context, ControlsDetails details) {
                        final isLastStep = _currentStep == 3;
                        return Container(
                          margin: const EdgeInsets.only(top: 32),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: details.onStepContinue,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    isLastStep ? 'Güncelle' : 'Devam Et',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                              if (_currentStep > 0) const SizedBox(width: 12),
                              if (_currentStep > 0)
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: details.onStepCancel,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Geri',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                  steps: [
                    Step(
                      title: const Text('Tür'),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0
                          ? StepState.complete
                          : StepState.indexed,
                      content: _buildStep1BasicInfo(),
                    ),
                    Step(
                      title: const Text('Detay'),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1
                          ? StepState.complete
                          : StepState.indexed,
                      content: _buildStep2Details(),
                    ),
                    Step(
                      title: const Text('İçerik'),
                      isActive: _currentStep >= 2,
                      state: _currentStep > 2
                          ? StepState.complete
                          : StepState.indexed,
                      content: _buildStep3Content(),
                    ),
                    Step(
                      title: const Text('Görsel'),
                      isActive: _currentStep >= 3,
                      content: _buildStep4Photos(),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStep1BasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hayvan Kategorisi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppConstants.categoryAnimals.keys.map((cat) {
            final isSelected = _category == cat;
            return ChoiceChip(
              label: Text(
                cat[0].toUpperCase() + cat.substring(1),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
              selected: isSelected,
              selectedColor: Colors.green[700],
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _category = cat;
                    _animalType = AppConstants.getAnimalsForCategory(
                      _category,
                    ).first;
                    _breed = null;
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
          decoration: const InputDecoration(
            labelText: 'Hayvan Türü *',
            prefixIcon: Icon(Icons.pets),
          ),
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
        const Text(
          'İlan Tipi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['satılık', 'sahiplendirme'].map((type) {
            final isSelected = _listingType == type;
            return ChoiceChip(
              label: Text(
                type[0].toUpperCase() + type.substring(1),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
              selected: isSelected,
              selectedColor: Colors.green[700],
              onSelected: (selected) {
                if (selected) setState(() => _listingType = type);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStep2Details() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _breed,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Irk',
            prefixIcon: Icon(Icons.pets_outlined),
          ),
          items: AppConstants.getBreedsForAnimal(_animalType ?? '').map((
            breed,
          ) {
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
                decoration: const InputDecoration(
                  labelText: 'Yaş',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Cinsiyet *',
                  prefixIcon: Icon(Icons.wc),
                ),
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
          decoration: const InputDecoration(
            labelText: 'Ağırlık',
            hintText: 'Örn: 450 kg',
            prefixIcon: Icon(Icons.monitor_weight),
          ),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          value: _healthStatus,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sağlık Durumu',
            prefixIcon: Icon(Icons.health_and_safety),
          ),
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
            decoration: const InputDecoration(
              labelText: 'Hastalık / Sorun Açıklaması *',
              prefixIcon: Icon(Icons.warning_amber),
            ),
            maxLines: 2,
            validator: (v) =>
                _healthStatus == 'Sağlıksız' && (v?.isEmpty ?? true)
                ? 'Açıklama gerekli'
                : null,
          ),
        ],

        const SizedBox(height: 24),
        const Text(
          'Yapılan Aşılar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppConstants.vaccines.map((vaccine) {
            final isSelected = _selectedVaccines.contains(vaccine);
            return FilterChip(
              label: Text(vaccine),
              selected: isSelected,
              selectedColor: Colors.green[100],
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
    );
  }

  Widget _buildStep3Content() {
    return Column(
      children: [
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'İlan Başlığı *',
            prefixIcon: Icon(Icons.title),
          ),
          validator: (v) => v?.trim().isEmpty ?? true ? 'Başlık gerekli' : null,
        ),
        const SizedBox(height: 16),
        if (_listingType != 'sahiplendirme')
          TextFormField(
            controller: _priceController,
            decoration: const InputDecoration(
              labelText: 'Fiyat (₺) *',
              prefixIcon: Icon(Icons.attach_money),
            ),
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
                      decoration: const InputDecoration(
                        labelText: 'Şehir *',
                        prefixIcon: Icon(Icons.location_city),
                      ),
                      items: _cities.map((city) {
                        return DropdownMenuItem<String>(
                          value: city['label'],
                          child: Text(city['label']),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final cityObj = _cities.firstWhere(
                          (c) => c['label'] == v,
                        );
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
                      decoration: const InputDecoration(
                        labelText: 'İlçe *',
                        prefixIcon: Icon(Icons.location_on),
                      ),
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
          decoration: const InputDecoration(
            labelText: 'Detaylı Açıklama *',
            prefixIcon: Icon(Icons.description),
          ),
          maxLines: 5,
          validator: (v) =>
              v?.trim().isEmpty ?? true ? 'Açıklama gerekli' : null,
        ),
      ],
    );
  }

  Widget _buildStep4Photos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.green[50],
            border: Border.all(
              color: Colors.green[200]!,
              width: 2,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: (_existingImages.length + _newImages.length) < 8
                ? _pickImages
                : null,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo, size: 40, color: Colors.green[700]),
                const SizedBox(height: 8),
                Text(
                  'Fotoğraf Ekle (${_existingImages.length + _newImages.length}/8)',
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_existingImages.isEmpty && _newImages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text(
                      'En az 1 fotoğraf bırakmalısınız',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Existing Network Images
        if (_existingImages.isNotEmpty) ...[
          const Text(
            'Kayıtlı Fotoğraflar:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl:
                          '${ApiConfig.uploadsUrl}/${_existingImages[index]}',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[200],
                        child: const CircularProgressIndicator(),
                      ),
                      errorWidget: (context, url, _) => const Icon(Icons.error),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeExistingImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        // Newly picked File Images
        if (_newImages.isNotEmpty) ...[
          const Text(
            'Yeni Eklenecek Fotoğraflar:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_newImages[index], fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeNewImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
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
