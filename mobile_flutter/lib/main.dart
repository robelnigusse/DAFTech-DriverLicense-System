import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;

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
  final BarcodeScanner _barcodeScanner = BarcodeScanner();

  bool _initializing = true;
  bool _scanning = false;
  bool _isScanningBack =
      false; // false = Step 1 (Front OCR), true = Step 2 (Back QR)
  bool _isProcessingFrame = false; // Prevents overlapping live-stream QR checks
  String? _error;
  Map<String, String>? _fields;

  final Map<String, TextEditingController> _inputs = {
    'License ID number': TextEditingController(),
    'Full name': TextEditingController(),
    'Date of birth': TextEditingController(),
    'Expiry date': TextEditingController(),
    'License type (Gerad)': TextEditingController(),
    'QR raw data': TextEditingController(),
    'OCR raw text': TextEditingController(),
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
        ResolutionPreset.max, // Kept exactly as your working code
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
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

  /// STEP 1: Your exact working Front OCR scan
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
        language: 'eng',
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

      // Populate your 5 fields + OCR raw text from front scan
      for (final entry in result.entries) {
        _inputs[entry.key]!.text = entry.value;
      }
      _inputs['OCR raw text']!.text = text.trim();

      if (result.values.every((value) => value.isEmpty)) {
        _showMessage(
          'No fields were detected. Try better lighting and keep the licence steady.',
        );
        return;
      }

      // Move to Step 2 and start live automatic QR detection
      setState(() {
        _isScanningBack = true;
      });
      _showMessage(
          'Front scanned! Flip the licence — QR will scan automatically.');
      await _startAutoQrScan();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Scanning failed: $e');
    } finally {
      try {
        if (rawFile != null && await rawFile.exists()) await rawFile.delete();
        if (croppedFile != null && await croppedFile.exists()) {
          await croppedFile.delete();
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  /// Starts the live camera stream on Step 2 to auto-detect the QR code
  Future<void> _startAutoQrScan() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isStreamingImages) {
      return;
    }

    try {
      await camera.setFocusMode(FocusMode.auto);
      await camera.startImageStream((CameraImage image) async {
        if (_isProcessingFrame || !_isScanningBack || _scanning) return;
        _isProcessingFrame = true;

        try {
          final inputImage = _inputImageFromCameraImage(image);
          if (inputImage == null) return;

          final barcodes = await _barcodeScanner.processImage(inputImage);
          if (barcodes.isNotEmpty) {
            final qrRaw = barcodes
                .map((b) => b.rawValue ?? b.displayValue ?? '')
                .where((v) => v.isNotEmpty)
                .join('\n')
                .trim();

            if (qrRaw.isNotEmpty) {
              // Stop the stream immediately once a valid QR code is found
              await _stopAutoQrScan();

              if (!mounted) return;

              debugPrint('========== AUTO RAW QR DATA ==========');
              debugPrint(qrRaw);
              debugPrint('========== END AUTO QR DATA ==========');

              HapticFeedback.mediumImpact();
              _inputs['QR raw data']!.text = qrRaw;

              // Overwrite Full Name, License ID, and License Type with accurate QR data
              _applyQrDataToFields(qrRaw);

              setState(() {
                _fields = {
                  for (final entry in _inputs.entries)
                    entry.key: entry.value.text,
                };
              });
            }
          }
        } catch (e) {
          debugPrint('Live QR frame error: $e');
        } finally {
          await Future.delayed(const Duration(milliseconds: 150));
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      debugPrint('Could not start QR stream: $e');
    }
  }

  /// Safely stops the live camera stream
  Future<void> _stopAutoQrScan() async {
    final camera = _camera;
    if (camera != null && camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } catch (_) {}
    }
    _isProcessingFrame = false;
  }

  /// Converts a live CameraImage frame into an ML Kit InputImage
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;

    final sensorOrientation = camera.description.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation90deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format != null && image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  /// Manual fallback button on Step 2: Takes a high-res photo if user taps the button
  Future<void> _scanBackQrManual() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _scanning) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    File? rawFile;
    File? croppedFile;

    try {
      await _stopAutoQrScan();

      await camera.setFocusMode(FocusMode.locked);
      final photo = await camera.takePicture();
      await camera.setFocusMode(FocusMode.auto);

      rawFile = File(photo.path);
      croppedFile = await _cropOnly(photo.path);

      var barcodes = await _barcodeScanner.processImage(
        InputImage.fromFilePath(croppedFile.path),
      );

      if (barcodes.isEmpty) {
        barcodes = await _barcodeScanner.processImage(
          InputImage.fromFilePath(photo.path),
        );
      }

      if (!mounted) return;

      if (barcodes.isEmpty) {
        _showMessage(
          'No QR code detected yet. Keep holding steady — auto-scan is active.',
        );
        await _startAutoQrScan();
        return;
      }

      final qrRaw = barcodes
          .map((b) => b.rawValue ?? b.displayValue ?? '')
          .where((v) => v.isNotEmpty)
          .join('\n')
          .trim();

      _inputs['QR raw data']!.text = qrRaw;

      // Overwrite Full Name, License ID, and License Type with accurate QR data
      _applyQrDataToFields(qrRaw);

      setState(() {
        _fields = {
          for (final entry in _inputs.entries) entry.key: entry.value.text,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'QR scanning failed: $e');
    } finally {
      try {
        if (rawFile != null && await rawFile.exists()) await rawFile.delete();
        if (croppedFile != null && await croppedFile.exists()) {
          await croppedFile.delete();
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  /// Parses the Ethiopian Driver's License QR payload and OVERWRITES the fields:
  /// Example: "የአሽከርካሪው ስም :-ናሆም ክፍሉየመንጃ ፍቃድ ቁጥር :-አዲስ አበባ-አውቶ-774944"
  void _applyQrDataToFields(String qrRaw) {
    // 1. Extract and overwrite Full Name from "የአሽከርካሪው ስም :-..."
    final nameMatch = RegExp(
      r'የአሽከርካሪው\s*ስም\s*[:：-]*(.+?)(?=የመንጃ\s*ፍቃድ\s*ቁጥር|$)',
      dotAll: true,
    ).firstMatch(qrRaw);

    if (nameMatch != null) {
      final qrName = _clean(nameMatch.group(1)!);
      if (qrName.isNotEmpty) {
        _inputs['Full name']!.text = qrName;
      }
    }

    // 2. Extract and overwrite License Type & License ID from "የመንጃ ፍቃድ ቁጥር :-አዲስ አበባ-አውቶ-774944"
    final licenseMatch = RegExp(
      r'የመንጃ\s*ፍቃድ\s*ቁጥር\s*[:：-]*(.+)$',
      dotAll: true,
    ).firstMatch(qrRaw);

    if (licenseMatch != null) {
      final fullLicenseStr = licenseMatch.group(1)!.trim();
      final parts = fullLicenseStr
          .split('-')
          .map((s) => _clean(s))
          .where((s) => s.isNotEmpty)
          .toList();

      if (parts.length >= 3) {
        // Format: <Region> - <License Type/Grade> - <License ID Number>
        // Example: parts[0] = አዲስ አበባ, parts[1] = አውቶ, parts[2] = 774944
        final qrGrade = parts[1];
        final qrLicenseId = parts.sublist(2).join('-');

        if (qrGrade.isNotEmpty) {
          _inputs['License type (Gerad)']!.text = qrGrade;
        }
        if (qrLicenseId.isNotEmpty) {
          _inputs['License ID number']!.text = qrLicenseId;
        }
      } else if (parts.length == 2) {
        // Fallback if only Grade-ID is present
        _inputs['License type (Gerad)']!.text = parts[0];
        _inputs['License ID number']!.text = parts[1];
      } else if (parts.length == 1 && parts.first.isNotEmpty) {
        _inputs['License ID number']!.text = parts.first;
      }
    }
  }

  /// Your exact working _extractFields logic for Front OCR
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

  /// Your exact working _cropAndPreprocess for Front OCR
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

  /// Crops to the frame for manual QR snapshot fallback
  Future<File> _cropOnly(String path) async {
    final bytes = await File(path).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return File(path);

    final cropWidth = (original.width * 0.90).round();
    final cropHeight = (original.height * 0.36).round();
    final offsetX = ((original.width - cropWidth) / 2).round();
    final offsetY = ((original.height - cropHeight) / 2).round();

    final cropped = img.copyCrop(
      original,
      x: offsetX,
      y: offsetY,
      width: cropWidth,
      height: cropHeight,
    );

    final croppedPath = '${path}_qr_cropped.jpg';
    final croppedFile = File(croppedPath);
    await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: 90));
    return croppedFile;
  }

  String _clean(String value) {
    return value
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
    _stopAutoQrScan();
    _camera?.dispose();
    _barcodeScanner.close();
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
        title: Text(
          _fields != null
              ? 'Review Extracted Info'
              : _isScanningBack
                  ? 'Step 2: Auto-Scanning QR...'
                  : 'Driving License Scanner',
        ),
      ),
      body: SafeArea(
        child: _fields == null ? _buildCamera(camera) : _buildResults(),
      ),
    );
  }

  Widget _buildCamera(CameraController? camera) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _isScanningBack
                ? 'Point the camera at the QR code on the back — it will scan automatically.'
                : 'Place the entire driving licence inside the frame.',
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
                                        color: _isScanningBack
                                            ? Colors.amberAccent
                                            : Colors.greenAccent,
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
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          _isScanningBack
                                              ? 'Reading QR code...'
                                              : 'Reading licence...',
                                          style: const TextStyle(
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
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _initializing ||
                          _scanning ||
                          camera == null ||
                          _error != null
                      ? null
                      : (_isScanningBack ? _scanBackQrManual : _scanLicense),
                  icon: Icon(
                    _isScanningBack
                        ? Icons.qr_code_scanner
                        : Icons.document_scanner,
                  ),
                  label: Text(
                    _scanning
                        ? 'Scanning...'
                        : (_isScanningBack
                            ? 'Auto-Scanning QR (Tap to Capture)'
                            : 'Scan licence'),
                  ),
                ),
              ),
              if (_isScanningBack) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _scanning
                      ? null
                      : () async {
                          await _stopAutoQrScan();
                          if (!mounted) return;
                          setState(() {
                            _fields = {
                              for (final entry in _inputs.entries)
                                entry.key: entry.value.text,
                            };
                          });
                        },
                  child: const Text('Skip QR Code'),
                ),
              ],
            ],
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
            maxLines: entry.key == 'OCR raw text'
                ? 5
                : entry.key == 'QR raw data'
                    ? 3
                    : 1,
            decoration: InputDecoration(
              labelText: entry.key,
              alignLabelWithHint: true,
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
          onPressed: () async {
            await _stopAutoQrScan();
            for (final controller in _inputs.values) {
              controller.clear();
            }
            if (!mounted) return;
            setState(() {
              _fields = null;
              _isScanningBack = false;
            });
          },
          child: const Text('Scan another licence'),
        ),
      ],
    );
  }
}
