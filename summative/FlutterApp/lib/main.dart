import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Base URL of the API (no trailing slash).
///
/// The deployed Render API is the default. For local development, override it
/// at launch time:
///   Flutter web/desktop/iOS simulator: http://127.0.0.1:8000
///   Android emulator:                  http://10.0.2.2:8000
/// Example:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://health-facility-absence-api.onrender.com',
);

void main() => runApp(const AbsenteeismApp());

class AbsenteeismApp extends StatelessWidget {
  const AbsenteeismApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absenteeism Predictor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const PredictPage(),
    );
  }
}

/// One input variable of the model = one labelled text field.
class FieldSpec {
  final String key; // JSON key expected by the API
  final String label;
  final String helper;
  final bool numeric;
  const FieldSpec(this.key, this.label, this.helper, {this.numeric = false});
}

const List<FieldSpec> fields = [
  FieldSpec('country', 'Country-survey',
      'Kenya-2012, Madagascar-2016, Mozambique-2014, Niger-2015, Nigeria-2013, Tanzania-2014, Tanzania-2016, Togo-2013 or Uganda-2013'),
  FieldSpec('facility_level', 'Facility level', 'Health Post, Health Center or Hospital'),
  FieldSpec('publicprivate', 'Ownership', 'Public or Private'),
  FieldSpec('ruralurban', 'Location', 'Rural or Urban'),
  FieldSpec('has_autosyringe', 'Auto-disable syringes', '1 = available, 0 = not available', numeric: true),
  FieldSpec('has_dispsyringe', 'Disposable syringes', '1 = available, 0 = not available', numeric: true),
  FieldSpec('has_fridge', 'Working refrigerator', '1 = available, 0 = not available', numeric: true),
  FieldSpec('has_gloves', 'Gloves', '1 = available, 0 = not available', numeric: true),
  FieldSpec('has_sharps', 'Sharps container', '1 = available, 0 = not available', numeric: true),
  FieldSpec('has_vaccarrier', 'Vaccine carrier', '1 = available, 0 = not available', numeric: true),
];

class PredictPage extends StatefulWidget {
  const PredictPage({super.key});

  @override
  State<PredictPage> createState() => _PredictPageState();
}

class _PredictPageState extends State<PredictPage> {
  final Map<String, TextEditingController> _controllers = {
    for (final f in fields) f.key: TextEditingController(),
  };

  bool _loading = false;
  bool _isError = false;
  String _message = 'The predicted absence rate will appear here.';

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _predict() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _isError = false;
      _message = 'Contacting the server... (the first request can take up to a minute while the free server wakes up)';
    });

    // Build the JSON body exactly as typed so that the API itself reports missing / wrong-type / out-of-range values.
    final Map<String, dynamic> body = {};
    for (final f in fields) {
      final text = _controllers[f.key]!.text.trim();
      if (text.isEmpty) continue; // missing value -> API answers "Field required"
      if (f.numeric) {
        body[f.key] = int.tryParse(text) ?? text; // not a number -> sent as text -> API answers "valid integer"
      } else {
        body[f.key] = text;
      }
    }

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final percent = (data['predicted_absence_percent'] as num).toStringAsFixed(1);
        final risk = data['risk_level'];
        final model = data['model'];
        _show('Predicted staff absence rate: $percent%\nRisk level: $risk\nModel: $model', false);
      } else if (response.statusCode == 422) {
        _show(_readValidationErrors(response.body), true);
      } else {
        _show('Server error (${response.statusCode}). Please try again.', true);
      }
    } on TimeoutException {
      _show('The server took too long to answer. Wait a moment and try again.', true);
    } catch (_) {
      _show('Could not reach the server. Check your internet connection and the API address.', true);
    }
  }

  /// Turns FastAPI's 422 response into short readable lines such as "Gloves: Input should be less than or equal to 1".
  String _readValidationErrors(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is List) {
        final lines = <String>[];
        for (final item in detail) {
          final loc = (item['loc'] as List).map((e) => e.toString()).toList();
          final key = loc.isNotEmpty ? loc.last : '';
          final label = fields.where((f) => f.key == key).map((f) => f.label).firstOrNull ?? key;
          lines.add('• $label: ${item['msg']}');
        }
        return 'Please correct these inputs:\n${lines.join('\n')}';
      }
    } catch (_) {}
    return 'Some inputs are invalid. Please check every field.';
  }

  void _show(String message, bool isError) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _isError = isError;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Health Facility Absenteeism')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the facility details to predict the share of health workers likely to be absent.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final f in fields) ...[
                TextField(
                  controller: _controllers[f.key],
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: f.label,
                    helperText: f.helper,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _predict,
                  child: const Text('Predict'),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isError ? scheme.errorContainer : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _isError ? scheme.error : scheme.secondary),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 12, top: 2),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    Expanded(
                      child: Text(
                        _message,
                        key: const Key('result_text'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _isError ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
