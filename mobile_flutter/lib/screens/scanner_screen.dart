import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;

import '../models/driver.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/camera_image_converter.dart';
import '../utils/license_parser.dart';
import '../widgets/status_chip.dart';
import 'login_screen.dart';

/// Scans a driving licence (OCR on the front, QR on the back), lets the
/// officer review the extracted values, then registers it with the API.
class LicenseScannerScreen extends StatefulWidget {
  const LicenseScannerScreen({super.key});

  @override
  State<LicenseScannerScreen> createState() => _LicenseScannerScreenState();
}

class _LicenseScannerScreenState extends State<LicenseScannerScreen> {
  CameraController? _camera;
  final BarcodeScanner _barcodeScanner = BarcodeScanner();

  bool _initializing = true;
  bool _scanning = false;
  bool _scanningBack = false;
  bool _reviewing = false;
  bool _submitting = false;
  bool _isProcessingFrame = false;
  String? _error;

  final _licenseIdController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _expiryController = TextEditingController();
  final _licenseTypeController = TextEditingController();

  String _qrRaw = '';
  String _ocrRaw = '';

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

  /// Step 1: OCR the front of the card.
  Future<void> _scanFront() async {
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
      _ocrRaw = text.trim();

      if (!mounted) return;

      for (final entry in result.entries) {
        _controllerFor(entry.key)?.text = entry.value;
      }

      if (result.values.every((value) => value.isEmpty)) {
        _showMessage(
          'No fields were detected. Try better lighting and keep the '
          'licence steady.',
        );
        return;
      }

      setState(() => _scanningBack = true);
      _showMessage(
        'Front scanned. Flip the licence — the QR code will be read '
        'automatically.',
      );
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

  TextEditingController? _controllerFor(String label) {
    switch (label) {
      case 'License ID number':
        return _licenseIdController;
      case 'Full name':
        return _fullNameController;
      case 'Date of birth':
        return _dobController;
      case 'Expiry date':
        return _expiryController;
      case 'License type (Gerad)':
        return _licenseTypeController;
      default:
        return null;
    }
  }

  /// Step 2: automatically detect the QR code on the back.
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
        if (_isProcessingFrame || !_scanningBack || _scanning) return;
        _isProcessingFrame = true;

        try {
          final inputImage =
              CameraImageConverter.fromCameraImage(image, camera);
          if (inputImage == null) return;

          final barcodes = await _barcodeScanner.processImage(inputImage);
          if (barcodes.isNotEmpty) {
            final qrRaw = barcodes
                .map((b) => b.rawValue ?? b.displayValue ?? '')
                .where((v) => v.isNotEmpty)
                .join('\n')
                .trim();

            if (qrRaw.isNotEmpty) {
              await _stopAutoQrScan();

              if (!mounted) return;

              debugPrint('========== AUTO RAW QR DATA ==========');
              debugPrint(qrRaw);
              debugPrint('========== END AUTO QR DATA ==========');

              HapticFeedback.mediumImpact();
              _applyQr(qrRaw);

              setState(() {
                _reviewing = true;
                _scanningBack = false;
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

  Future<void> _stopAutoQrScan() async {
    final camera = _camera;
    if (camera != null && camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } catch (_) {}
    }
    _isProcessingFrame = false;
  }

  /// Fallback capture for the QR when auto-detection is struggling.
  Future<void> _captureQrManually() async {
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
          'No QR code detected yet. Keep holding steady — automatic '
          'scanning is still active.',
        );
        await _startAutoQrScan();
        return;
      }

      final qrRaw = barcodes
          .map((b) => b.rawValue ?? b.displayValue ?? '')
          .where((v) => v.isNotEmpty)
          .join('\n')
          .trim();

      _applyQr(qrRaw);

      setState(() {
        _reviewing = true;
        _scanningBack = false;
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

  void _applyQr(String qrRaw) {
    _qrRaw = qrRaw;

    final parsed = LicenseParser.parseQr(qrRaw);

    if (parsed.fullName != null && parsed.fullName!.isNotEmpty) {
      _fullNameController.text = parsed.fullName!;
    }
    if (parsed.licenseType != null && parsed.licenseType!.isNotEmpty) {
      _licenseTypeController.text = parsed.licenseType!;
    }
    if (parsed.licenseId != null && parsed.licenseId!.isNotEmpty) {
      _licenseIdController.text = parsed.licenseId!;
    }
  }

  /// Sends the reviewed values to `POST /api/drivers`.
  Future<void> _submitRegistration() async {
    if (_submitting) return;

    final licenseId = _licenseIdController.text.trim();
    final fullName = _fullNameController.text.trim();

    if (licenseId.isEmpty) {
      _showMessage('A licence ID number is required.');
      return;
    }
    if (fullName.isEmpty) {
      _showMessage('The full name is required.');
      return;
    }

    final rawDob = _dobController.text.trim();
    final rawExpiry = _expiryController.text.trim();

    final dateOfBirth = LicenseParser.normalizeDate(rawDob);
    final expiryDate = LicenseParser.normalizeDate(rawExpiry);

    if (rawDob.isNotEmpty && dateOfBirth == null) {
      _showMessage(
        'Date of birth "$rawDob" is not a valid date. Use DD/MM/YYYY.',
      );
      return;
    }
    if (rawExpiry.isNotEmpty && expiryDate == null) {
      _showMessage(
        'Expiry date "$rawExpiry" is not a valid date. Use DD/MM/YYYY.',
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final driver = await ApiService.registerDriver(
        licenseId: licenseId,
        fullName: fullName,
        dateOfBirth: dateOfBirth,
        licenseType: _licenseTypeController.text.trim().isEmpty
            ? null
            : _licenseTypeController.text.trim(),
        expiryDate: expiryDate,
        qrRawData: _qrRaw.isEmpty ? null : _qrRaw,
        ocrRawText: _ocrRaw.isEmpty ? null : _ocrRaw,
      );

      if (!mounted) return;
      await _showSuccess(driver);
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.isConflict) {
        await _showDuplicate(e);
      } else if (e.isUnauthorized) {
        await _handleSessionExpired();
      } else {
        _showMessage(e.message);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Registration failed: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _showSuccess(Driver driver) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon:
            const Icon(Icons.check_circle, color: Color(0xFF1B7F4B), size: 40),
        title: const Text('Licence registered'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(driver.fullName),
            const SizedBox(height: 6),
            Text('Licence ID: ${driver.licenseId}'),
            const SizedBox(height: 10),
            StatusChip(driver.status),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    _resetForm();
  }

  Future<void> _showDuplicate(ApiException error) async {
    final status = error.duplicateStatus ?? 'Unknown';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon:
            const Icon(Icons.info_outline, color: Color(0xFFB26A00), size: 40),
        title: const Text('Licence already registered'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error.message),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Status: '),
                StatusChip(status),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSessionExpired() async {
    await _stopAutoQrScan();
    await _camera?.dispose();
    await AuthService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _resetForm() async {
    _licenseIdController.clear();
    _fullNameController.clear();
    _dobController.clear();
    _expiryController.clear();
    _licenseTypeController.clear();
    _qrRaw = '';
    _ocrRaw = '';

    // Release the previous controller before opening a fresh preview.
    final old = _camera;
    _camera = null;
    if (old != null) {
      try {
        if (old.value.isStreamingImages) {
          await old.stopImageStream();
        }
      } catch (_) {}
      await old.dispose();
    }

    if (!mounted) return;

    setState(() {
      _reviewing = false;
      _scanningBack = false;
      _initializing = true;
      _error = null;
    });

    await _initializeCamera();
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

        var value = line.substring(match.end).trim();
        value = value.replaceFirst(RegExp(r'^[\s:./-]+'), '');
        value = value.split(stopLabels).first.trim();

        if (value.isNotEmpty) {
          return value;
        }

        if (i + 1 < lines.length && !stopLabels.hasMatch(lines[i + 1])) {
          return lines[i + 1].split(stopLabels).first.trim();
        }
      }
      return '';
    }

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
      'License ID number': LicenseParser.clean(licenseId),
      'Full name': LicenseParser.clean(fullName),
      'Date of birth': LicenseParser.clean(dob),
      'Expiry date': LicenseParser.clean(expiry),
      'License type (Gerad)': LicenseParser.clean(grade),
    };
  }

  Future<File> _cropAndPreprocess(String path) async {
    final bytes = await File(path).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return File(path);

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

    processed = img.grayscale(processed);
    processed = img.contrast(processed, contrast: 130);

    final croppedFile = File('${path}_cropped.jpg');
    await croppedFile.writeAsBytes(img.encodeJpg(processed, quality: 90));
    return croppedFile;
  }

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

    final croppedFile = File('${path}_qr_cropped.jpg');
    await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: 90));
    return croppedFile;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _stopAutoQrScan();
    _camera?.dispose();
    _barcodeScanner.close();
    _licenseIdController.dispose();
    _fullNameController.dispose();
    _dobController.dispose();
    _expiryController.dispose();
    _licenseTypeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _reviewing
              ? 'Review licence details'
              : _scanningBack
                  ? 'Step 2: scanning QR code'
                  : 'Register licence',
        ),
      ),
      body: SafeArea(
        child: _reviewing ? _buildReviewForm() : _buildCameraView(),
      ),
    );
  }

  Widget _buildCameraView() {
    final camera = _camera;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _scanningBack
                ? 'Point the camera at the QR code on the back of the '
                    'licence. It will be read automatically.'
                : 'Place the front of the driving licence inside the frame '
                    'and tap Scan.',
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
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
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
                                        color: _scanningBack
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
                                          _scanningBack
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
                      : (_scanningBack ? _captureQrManually : _scanFront),
                  icon: Icon(
                    _scanningBack
                        ? Icons.qr_code_scanner
                        : Icons.document_scanner,
                  ),
                  label: Text(
                    _scanning
                        ? 'Scanning...'
                        : (_scanningBack
                            ? 'Capture QR manually'
                            : 'Scan licence'),
                  ),
                ),
              ),
              if (_scanningBack) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _scanning
                      ? null
                      : () async {
                          await _stopAutoQrScan();
                          if (!mounted) return;
                          setState(() {
                            _reviewing = true;
                            _scanningBack = false;
                          });
                        },
                  child: const Text('Skip QR and review manually'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(
          Icons.fact_check_outlined,
          size: 44,
          color: Color(0xFF176B57),
        ),
        const SizedBox(height: 10),
        Text(
          'Check the extracted information',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Correct any recognition errors before registering the licence.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _licenseIdController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Licence ID number *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _fullNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Full name *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _dobController,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Date of birth',
            hintText: 'DD/MM/YYYY',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.cake_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _expiryController,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Expiry date',
            hintText: 'DD/MM/YYYY',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.event_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _licenseTypeController,
          decoration: const InputDecoration(
            labelText: 'Licence type (Gerad)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.drive_eta_outlined),
          ),
        ),
        if (_qrRaw.isNotEmpty || _ocrRaw.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Raw scan data'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              if (_qrRaw.isNotEmpty) _RawBlock(label: 'QR data', value: _qrRaw),
              if (_ocrRaw.isNotEmpty)
                _RawBlock(label: 'OCR text', value: _ocrRaw),
            ],
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submitRegistration,
            icon: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_submitting ? 'Registering...' : 'Register licence'),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _submitting
              ? null
              : () async {
                  await _stopAutoQrScan();
                  _resetForm();
                },
          child: const Text('Cancel and rescan'),
        ),
      ],
    );
  }
}

class _RawBlock extends StatelessWidget {
  final String label;
  final String value;

  const _RawBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
