import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LicenseScannerApp());
}

class LicenseScannerApp extends StatelessWidget {
  const LicenseScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'License Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B57),
        ),
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _camera;
  bool _initializing = true;
  bool _scanning = false;
  String? _error;
  Map<String, String>? _fields;

  final Map<String, TextEditingController> _inputs = {
    'License ID number': TextEditingController(),
    'Full name': TextEditingController(),
    'Date of birth': TextEditingController(),
    'Expiry date': TextEditingController(),
    'License type (Gerad)': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera was found on this device.');
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _camera = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _initializing = false;
        _error = 'Could not open camera: $e';
      });
    }
  }

  Future<void> _scanLicense() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _scanning) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    File? rawFile;
    File? croppedFile;

    try {
      await camera.setFocusMode(FocusMode.locked);
      final photo = await camera.takePicture();
      await camera.setFocusMode(FocusMode.auto);

      rawFile = File(photo.path);
      croppedFile = await _cropAndPreprocess(photo.path);

      final text = await FlutterTesseractOcr.extractText(
        croppedFile.path,
        language: 'eng', // Use 'eng+amh' if you bundle amh.traineddata
        args: {
          'psm': '6',
          'preserve_interword_spaces': '1',
        },
      );

      debugPrint('========== RAW OCR TEXT ==========');
      debugPrint(text);
      debugPrint('========== END OCR TEXT ==========');

      final result = _extractFields(text);

      if (!mounted) return;

      setState(() {
        _fields = result;
        for (final entry in result.entries) {
          _inputs[entry.key]!.text = entry.value;
        }
      });

      if (result.values.every((value) => value.isEmpty)) {
        _showMessage(
          'No fields were detected. Try better lighting and keep the licence steady.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Scanning failed: $e');
    } finally {
      // Clean up temporary images so cache doesn't bloat
      try {
        if (rawFile != null && await rawFile.exists()) await rawFile.delete();
        if (croppedFile != null && await croppedFile.exists())
          await croppedFile.delete();
      } catch (_) {}

      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Map<String, String> _extractFields(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    String findValue(RegExp label, RegExp stopLabels) {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final match = label.firstMatch(line);

        if (match == null) continue;

        // 1. Grab everything after the matched label
        var value = line.substring(match.end).trim();

        // 2. Strip leading punctuation/separators (colons, dashes, slashes)
        value = value.replaceFirst(RegExp(r'^[\s:./-]+'), '');

        // 3. CRITICAL FIX: Split at the first stopLabel to discard it AND everything after it
        value = value.split(stopLabels).first.trim();

        if (value.isNotEmpty) {
          return value;
        }

        // 4. Fallback to the next line if the value was printed below the label
        if (i + 1 < lines.length && !stopLabels.hasMatch(lines[i + 1])) {
          return lines[i + 1].split(stopLabels).first.trim();
        }
      }
      return '';
    }

    // Tolerate minor OCR typos in labels (e.g., "Licensc", "Expirv")
    final licenseId = findValue(
      RegExp(r'Licen[sc]e\s*(?:No|Number|ID)?\.?', caseSensitive: false),
      RegExp(r'Full\s*Name|DOB|Date|Nationality|Expiry|Sex',
          caseSensitive: false),
    );

    final fullName = findValue(
      RegExp(r'Full\s*Name|Name', caseSensitive: false),
      RegExp(r'DOB|Date\s*of\s*Birth|Nationality|Sex|Issue|Expiry|License',
          caseSensitive: false),
    );

    var dob = findValue(
      RegExp(r'\b(?:DOB|D\.O\.B|Date\s*of\s*Birth)\b', caseSensitive: false),
      RegExp(r'Nationality|Sex|Issue|Expiry|Grade|Blood', caseSensitive: false),
    );

    var expiry = findValue(
      RegExp(r'Expir[yv]\s*(?:Date)?', caseSensitive: false),
      RegExp(r'Grade|Issue|Nationality|Region|SubCity|Woreda',
          caseSensitive: false),
    );

    final grade = findValue(
      RegExp(r'Grade\s*[:.]?', caseSensitive: false),
      RegExp(r'Region|SubCity|Woreda|Blood|Phone', caseSensitive: false),
    );

    // Optional fallback: If DOB or Expiry failed label matching, extract all dates in order
    final datePattern = RegExp(
        r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})\b');
    final allDates =
        datePattern.allMatches(text).map((m) => m.group(0)!).toList();

    if (dob.isEmpty && allDates.isNotEmpty) {
      dob = allDates.first;
    }
    if (expiry.isEmpty && allDates.length >= 2) {
      expiry = allDates.last;
    }

    return {
      'License ID number': _clean(licenseId),
      'Full name': _clean(fullName),
      'Date of birth': _clean(dob),
      'Expiry date': _clean(expiry),
      'License type (Gerad)': _clean(grade),
    };
  }

  Future<File> _cropAndPreprocess(String path) async {
    final bytes = await File(path).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return File(path);

    // Match your FractionallySizedBox (widthFactor: 0.90, heightFactor: 0.36, centered)
    final cropWidth = (original.width * 0.90).round();
    final cropHeight = (original.height * 0.36).round();
    final offsetX = ((original.width - cropWidth) / 2).round();
    final offsetY = ((original.height - cropHeight) / 2).round();

    var processed = img.copyCrop(
      original,
      x: offsetX,
      y: offsetY,
      width: cropWidth,
      height: cropHeight,
    );

    // Convert to grayscale and boost contrast for sharper OCR text edges
    processed = img.grayscale(processed);
    processed = img.contrast(processed, contrast: 130);

    final croppedPath = '${path}_cropped.jpg';
    final croppedFile = File(croppedPath);
    await croppedFile.writeAsBytes(img.encodeJpg(processed, quality: 90));
    return croppedFile;
  }

  String _clean(String value) {
    return value
        // Remove leading/trailing pipes, colons, slashes, underscores, and symbols
        .replaceAll(RegExp(r'^[\s:./|_~-]+|[\s:./|_~-]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _camera?.dispose();

    for (final controller in _inputs.values) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driving License Scanner'),
      ),
      body: SafeArea(
        child: _fields == null ? _buildCamera(camera) : _buildResults(),
      ),
    );
  }

  Widget _buildCamera(CameraController? camera) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Place the entire driving licence inside the frame.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: _initializing
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : camera != null && camera.value.isInitialized
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(camera),
                              Center(
                                child: FractionallySizedBox(
                                  widthFactor: 0.90,
                                  heightFactor: 0.36,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.greenAccent,
                                        width: 3,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              if (_scanning)
                                Container(
                                  color: Colors.black54,
                                  child: const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'Reading licence...',
                                          style: TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : const Center(
                            child: Text(
                              'Camera unavailable',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed:
                  _initializing || _scanning || camera == null || _error != null
                      ? null
                      : _scanLicense,
              icon: const Icon(Icons.document_scanner),
              label: Text(
                _scanning ? 'Scanning...' : 'Scan licence',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(
          Icons.fact_check_outlined,
          size: 48,
          color: Colors.green,
        ),
        const SizedBox(height: 12),
        Text(
          'Review extracted information',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Check the values and correct any recognition errors.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        for (final entry in _inputs.entries) ...[
          TextField(
            controller: entry.value,
            decoration: InputDecoration(
              labelText: entry.key,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: () {
            final values = {
              for (final entry in _inputs.entries)
                entry.key: entry.value.text.trim(),
            };

            _showMessage('Information reviewed locally.');
            debugPrint('Reviewed fields: $values');
          },
          icon: const Icon(Icons.check),
          label: const Text('Confirm information'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            setState(() => _fields = null);
          },
          child: const Text('Scan another licence'),
        ),
      ],
    );
  }
}
