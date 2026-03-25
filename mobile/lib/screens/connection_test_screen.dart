import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  String _status = 'Bağlantı test edilmedi';
  Color _statusColor = Colors.grey;
  bool _isTesting = false;

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _status = 'Test ediliyor...';
      _statusColor = Colors.orange;
    });

    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.apiUrl}/listings'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _status = '✅ Bağlantı başarılı!\nBackend çalışıyor.';
          _statusColor = Colors.green;
        });
      } else {
        setState(() {
          _status = '⚠️ Backend yanıt verdi ama hata var\nStatus: ${response.statusCode}';
          _statusColor = Colors.orange;
        });
      }
    } catch (e) {
      setState(() {
        _status = '❌ Bağlantı başarısız!\n\n$e\n\nIP: ${ApiConfig.baseUrl}';
        _statusColor = Colors.red;
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bağlantı Testi')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _statusColor == Colors.green
                  ? Icons.check_circle
                  : _statusColor == Colors.red
                      ? Icons.error
                      : Icons.info,
              size: 80,
              color: _statusColor,
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: _statusColor),
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bağlantı Bilgileri:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Backend URL: ${ApiConfig.baseUrl}'),
                    Text('API URL: ${ApiConfig.apiUrl}'),
                    Text('Uploads URL: ${ApiConfig.uploadsUrl}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isTesting ? null : _testConnection,
                child: _isTesting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Bağlantıyı Test Et'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sorun mu yaşıyorsunuz?\n\n'
              '1. Backend çalışıyor mu kontrol edin\n'
              '2. Telefon ve bilgisayar aynı WiFi\'de mi?\n'
              '3. IP adresi doğru mu?\n'
              '4. Firewall 3000 portunu engelliyor mu?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
