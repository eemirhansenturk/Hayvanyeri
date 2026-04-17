import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

// Türkçe karakterleri destekleyen Title Case formatter
class TurkishTitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Türkçe karakterler için özel haritalama
    String toUpperCaseTurkish(String char) {
      const turkishLowerToUpper = {
        'i': 'İ',
        'ı': 'I',
        'ş': 'Ş',
        'ğ': 'Ğ',
        'ü': 'Ü',
        'ö': 'Ö',
        'ç': 'Ç',
      };
      return turkishLowerToUpper[char] ?? char.toUpperCase();
    }

    String toLowerCaseTurkish(String char) {
      const turkishUpperToLower = {
        'İ': 'i',
        'I': 'ı',
        'Ş': 'ş',
        'Ğ': 'ğ',
        'Ü': 'ü',
        'Ö': 'ö',
        'Ç': 'ç',
      };
      return turkishUpperToLower[char] ?? char.toLowerCase();
    }

    final words = newValue.text.split(' ');
    final formattedWords = words.map((word) {
      if (word.isEmpty) return word;
      
      final firstChar = toUpperCaseTurkish(word[0]);
      if (word.length == 1) return firstChar;
      
      final restChars = word.substring(1).split('').map((char) {
        return toLowerCaseTurkish(char);
      }).join('');
      
      return firstChar + restChars;
    }).toList();

    final formattedText = formattedWords.join(' ');

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _email = '';
  String _avatarPath = '';

  List<dynamic> _cities = [];
  List<dynamic> _districts = [];
  String? _selectedCityName;
  String? _selectedCityId;
  String? _selectedDistrictName;

  bool _isLoadingCities = true;
  bool _isLoadingDistricts = false;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user ?? {};
    _nameController.text = (user['name'] ?? '').toString();
    _phoneController.text = (user['phone'] ?? '').toString();
    _email = (user['email'] ?? '').toString();
    _avatarPath = (user['avatar'] ?? '').toString();

    final location = user['location'];
    if (location is Map) {
      _selectedCityName = (location['city'] ?? '').toString().trim().isEmpty
          ? null
          : (location['city'] ?? '').toString();
      _selectedDistrictName = (location['district'] ?? '').toString().trim().isEmpty
          ? null
          : (location['district'] ?? '').toString();
    }

    _fetchCities();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchCities() async {
    try {
      final data = await _apiService.getCities();
      if (!mounted) return;

      String? selectedId;
      if (_selectedCityName != null && _selectedCityName!.isNotEmpty) {
        for (final city in data) {
          if ((city['label'] ?? '').toString() == _selectedCityName) {
            selectedId = (city['tkgm_id'] ?? '').toString();
            break;
          }
        }
      }

      setState(() {
        _cities = data;
        _selectedCityId = selectedId;
        _isLoadingCities = false;
      });

      if (selectedId != null && selectedId.isNotEmpty) {
        await _fetchDistricts(selectedId, keepSelection: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingCities = false);
      }
    }
  }

  Future<void> _fetchDistricts(String cityId, {bool keepSelection = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingDistricts = true;
      _districts = [];
      if (!keepSelection) _selectedDistrictName = null;
    });

    try {
      final data = await _apiService.getDistricts(cityId);
      if (!mounted) return;
      setState(() {
        _districts = data;
        _isLoadingDistricts = false;
      });

      if (keepSelection && _selectedDistrictName != null) {
        final exists = _districts.any((d) => (d['label'] ?? '').toString() == _selectedDistrictName);
        if (!exists && mounted) {
          setState(() => _selectedDistrictName = null);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingDistricts = false);
    }
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

      setState(() => _isUploadingAvatar = true);
      final updatedUser = await _apiService.updateProfile(avatarFile: File(picked.path));
      await context.read<AuthProvider>().refreshProfile();

      if (!mounted) return;
      setState(() {
        _avatarPath = (updatedUser['avatar'] ?? _avatarPath).toString();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profil resmi güncellenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _onUpdatePressed() async {
    if (_isSaving) return;

    if (!_isEditing) {
      setState(() => _isEditing = true);
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedCityName == null || _selectedDistrictName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen şehir ve ilçe seçin')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updatedUser = await _apiService.updateProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        city: _selectedCityName,
        district: _selectedDistrictName,
      );
      await context.read<AuthProvider>().refreshProfile();
      
      if (!mounted) return;
      
      // Controller'ları güncellenen verilerle yeniden doldur
      final user = context.read<AuthProvider>().user ?? updatedUser;
      _nameController.text = (user['name'] ?? '').toString();
      _phoneController.text = (user['phone'] ?? '').toString();
      
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bilgiler güncellendi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Güncelleme hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = _avatarPath.trim().isNotEmpty;
    final avatarUrl = hasAvatar ? '${ApiConfig.uploadsUrl}/$_avatarPath' : '';
    final hasCityValue = _cities.any((c) => (c['label'] ?? '').toString() == _selectedCityName);
    final hasDistrictValue = _districts.any((d) => (d['label'] ?? '').toString() == _selectedDistrictName);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kişisel Bilgiler',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.green[700],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _openAvatarPicker,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.green[100],
                        backgroundImage: hasAvatar
                            ? CachedNetworkImageProvider(avatarUrl)
                            : null,
                        child: hasAvatar
                            ? null
                            : Text(
                                _nameController.text.trim().isNotEmpty
                                    ? _nameController.text.trim()[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[800],
                                ),
                              ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: _isEditing ? Colors.white : Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: _isUploadingAvatar
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.green[700],
                                  ),
                                )
                              : Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.green[700],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                enabled: _isEditing,
                maxLength: 30,
                inputFormatters: [
                  TurkishTitleCaseFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'Ad Soyad',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Ad soyad zorunlu';
                  }
                  if (v.trim().length < 2) {
                    return 'Ad soyad en az 2 karakter olmalı';
                  }
                  if (v.trim().length > 30) {
                    return 'Ad soyad en fazla 30 karakter olabilir';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _email,
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'E-posta (Değiştirilemez)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                enabled: _isEditing,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                decoration: InputDecoration(
                  labelText: 'Telefon',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    final length = v.trim().length;
                    if (length < 10) {
                      return 'Telefon numarası en az 10 karakter olmalı';
                    }
                    if (length > 11) {
                      return 'Telefon numarası en fazla 11 karakter olabilir';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _isLoadingCities
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      value: hasCityValue ? _selectedCityName : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Şehir',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _cities.map((city) {
                        return DropdownMenuItem<String>(
                          value: (city['label'] ?? '').toString(),
                          child: Text((city['label'] ?? '').toString()),
                        );
                      }).toList(),
                      onChanged: !_isEditing
                          ? null
                          : (v) {
                              if (v == null) return;
                              final cityObj = _cities.firstWhere((c) => (c['label'] ?? '').toString() == v);
                              setState(() {
                                _selectedCityName = v;
                                _selectedCityId = (cityObj['tkgm_id'] ?? '').toString();
                                _selectedDistrictName = null;
                              });
                              if (_selectedCityId != null && _selectedCityId!.isNotEmpty) {
                                _fetchDistricts(_selectedCityId!);
                              }
                            },
                    ),
              const SizedBox(height: 12),
              _isLoadingDistricts
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      value: hasDistrictValue ? _selectedDistrictName : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'İlçe',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _districts.map((district) {
                        return DropdownMenuItem<String>(
                          value: (district['label'] ?? '').toString(),
                          child: Text((district['label'] ?? '').toString()),
                        );
                      }).toList(),
                      onChanged: (!_isEditing || _selectedCityId == null)
                          ? null
                          : (v) {
                              setState(() => _selectedDistrictName = v);
                            },
                    ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _onUpdatePressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isEditing ? 'Kaydet' : 'Güncelle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
