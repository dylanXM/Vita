import 'package:flutter/material.dart';

const vitaEnv = String.fromEnvironment('VITA_ENV', defaultValue: 'dev');
const vitaApiBaseUrl = String.fromEnvironment(
  'VITA_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8260',
);

void main() {
  runApp(const VitaApp());
}

class VitaApp extends StatelessWidget {
  const VitaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vita',
      home: Scaffold(
        appBar: AppBar(title: const Text('Vita App')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('App started successfully.'),
              SizedBox(height: 8),
              Text('Environment: ' + vitaEnv),
              Text('API Base URL: ' + vitaApiBaseUrl),
            ],
          ),
        ),
      ),
    );
  }
}
