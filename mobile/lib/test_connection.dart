import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config/api_config.dart';

void main() {
  runApp(const TestConnectionApp());
}

class TestConnectionApp extends StatelessWidget {
  const TestConnectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Backend Bağlantı Testi')),
        body: const TestConnectionScreen(),
      ),
    );
  }
}

class TestConnectionScreen extends StatefulWidget {
  const TestConnectionScreen({super.key});

  @override
  State<TestConnectionScreen> createState() => _TestConnectionScreenState();
}

class _TestConnectionScreenState extends State<TestConnectionScreen> {
  String _result = 'Test başlatılmadı';
  bool _isLoading = false;

  Future<void> _testHealth() async {
    setState(() {
      _isLoading = true;
      _result = 'Health endpoint test ediliyor...';
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/health'),
      ).timeout(const Duration(seconds: 5));

      setState(() {
        _isLoading = false;
        _result = 'Health Test Başarılı!\n'
            'Status: ${response.statusCode}\n'
            'Body: ${response.body}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result = 'Health Test Başarısız!\nHata: $e';
      });
    }
  }

  Future<void> _testForgotPassword() async {
    setState(() {
      _isLoading = true;
      _result = 'Forgot password endpoint test ediliyor...';
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.apiUrl}/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': 'test@test.com'}),
      ).timeout(const Duration(seconds: 10));

      setState(() {
        _isLoading = false;
        _result = 'Forgot Password Test Tamamlandı!\n'
            'Status: ${response.statusCode}\n'
            'Body: ${response.body}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result = 'Forgot Password Test Başarısız!\nHata: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('API URL: ${ApiConfig.baseUrl}', 
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          ElevatedButton(
            onPressed: _isLoading ? null : _testHealth,
            child: const Text('Health Endpoint Test Et'),
          ),
          const SizedBox(height: 10),
          
          ElevatedButton(
            onPressed: _isLoading ? null : _testForgotPassword,
            child: const Text('Forgot Password Endpoint Test Et'),
          ),
          const SizedBox(height: 20),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(_result),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
