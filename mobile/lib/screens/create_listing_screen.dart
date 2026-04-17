import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

// Custom formatter to replace dots with commas
class DotToCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text == oldValue.text) {
      return newValue;
    }
    
    final newText = newValue.text.replaceAll('.', ',');
    
    // Eğer text değişmediyse (sadece nokta virgüle çevrildi), selection'ı koru
    if (newText.length == newValue.text.length) {
      return TextEditingValue(
        text: newText,
        selection: newValue.selection,
      );
    }
    
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _picker = ImagePicker();
  
  int _currentStep = 0;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _healthExplanationController = TextEditingController();
  
  String _category = 'büyükbaş';
  String? _animalType;
  String? _breed;
  String _listingType = 'satılık';
  String _gender = 'erkek';
  String _healthStatus = 'Sağlıklı';
  
  // Location
  List<dynamic> _cities = [];
  List<dynamic> _districts = [];
  String? _selectedCityName;
  String? _selectedCityId;
  String? _selectedDistrictName;
  bool _isLoadingCities = true;
  bool _isLoadingDistricts = false;

  List<String> _selectedVaccines = [];
  List<File> _images = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _animalType = AppConstants.getAnimalsForCategory(_category).first;
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
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCities = false);
    }
  }

  Future<void> _fetchDistricts(String cityId) async {
    setState(() {
      _isLoadingDistricts = true;
      _districts = [];
      _selectedDistrictName = null;
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
      final newImages = pickedFiles.map((xFile) => File(xFile.path)).toList();
      setState(() {
        _images.addAll(newImages);
        if (_images.length > 8) {
          _images = _images.sublist(0, 8);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maksimum 8 resim yükleyebilirsiniz')),
          );
        }
      });
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _submitData() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen zorunlu alanları doldurun')),
      );
      return;
    }
    
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az 1 fotoğraf yüklemelisiniz')),
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
        'price': _listingType == 'sahiplendirme' ? '0' : _priceController.text.replaceAll('.', '').trim(),
        'breed': _breed ?? '',
        'age': _ageController.text.trim(),
        'gender': _gender,
        'weight': _weightController.text.trim(),
        'healthStatus': finalHealthStatus,
        'vaccines': _selectedVaccines.join(','),
        'city': _selectedCityName ?? '',
        'district': _selectedDistrictName ?? '',
      };

      await _apiService.createListing(data, _images);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İlan başarıyla oluşturuldu!'), backgroundColor: Colors.green),
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
        title: const Text('Yeni İlan Ver', style: TextStyle(fontWeight: FontWeight.bold)),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen hayvan türünü seçin')));
        return;
      }
      setState(() => _currentStep += 1);
    } else if (_currentStep == 1) {
      if (_breed == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen ırk seçin')));
        return;
      }
      if (_ageController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen yaş bilgisini girin')));
        return;
      }
      if (_weightController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen ağırlık bilgisini girin')));
        return;
      }
      if (_ageController.text.isNotEmpty && !RegExp(r'^\d+(,\d+)?$').hasMatch(_ageController.text.trim())) {
        showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Hatalı Yaş Girdisi', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Lütfen yaşı 2,5 veya 3 şeklinde, sadece virgül kullanarak girin.\n(Nokta kullanmayınız.)'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam', style: TextStyle(color: Colors.green)))]
        ));
        return;
      }
      if (_healthStatus == 'Sağlıksız' && _healthExplanationController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen hastalık/sorun açıklamasını girin')));
        return;
      }
      setState(() => _currentStep += 1);
    } else if (_currentStep == 2) {
      if (_titleController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen ilan başlığını girin')));
        return;
      }
      if (_listingType != 'sahiplendirme' && _priceController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen fiyat bilgisini girin')));
        return;
      }
      if (_selectedCityName == null || _selectedDistrictName == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen şehir ve ilçe seçin')));
        return;
      }
      if (_descriptionController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen detaylı açıklamayı girin')));
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
      case 0: return _buildStep1BasicInfo();
      case 1: return _buildStep2Details();
      case 2: return _buildStep3Content();
      case 3: return _buildStep4Photos();
      default: return const SizedBox.shrink();
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
            child: Text(isLastStep ? 'İlanı Yayınla' : 'Devam Et', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            decoration: _buildInputDecoration('Irk *', Icons.pets_outlined),
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
                  decoration: _buildInputDecoration('Yaş *', Icons.calendar_today, hint: 'Örn: 4,5'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                    DotToCommaFormatter(),
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
            decoration: _buildInputDecoration('Ağırlık *', Icons.monitor_weight, hint: 'Örn: 450,5'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              DotToCommaFormatter(),
            ],
          ),
          const SizedBox(height: 16),
          
          DropdownButtonFormField<String>(
            value: _healthStatus,
            isExpanded: true,
            decoration: _buildInputDecoration('Sağlık Durumu *', Icons.health_and_safety),
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
              decoration: _buildInputDecoration('Hastalık / Sorun *', Icons.warning_amber),
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
              inputFormatters: [ThousandsSeparatorInputFormatter()],
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
                          });
                          _fetchDistricts(_selectedCityId!);
                        },
                        validator: (v) => v == null ? 'Şehir seçin' : null,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _isLoadingDistricts
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
                      ))
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
              border: Border.all(color: Colors.green.shade300, width: 2, style: BorderStyle.solid), // In a real app we could use dashed borders
              borderRadius: BorderRadius.circular(24),
            ),
            child: InkWell(
              onTap: _images.length < 8 ? _pickImages : null,
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
                    'Fotoğraf Ekle (${_images.length}/8)',
                    style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (_images.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text('En az 1 fotoğraf zorunludur', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
          if (_images.isNotEmpty) const SizedBox(height: 24),
          if (_images.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _images.length,
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
                        child: Image.file(_images[index], fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
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
