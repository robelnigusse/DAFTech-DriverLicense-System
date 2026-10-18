import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../models/verification_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/camera_image_converter.dart';
import '../utils/license_parser.dart';
import '../widgets/status_chip.dart';
import 'login_screen.dart';

/// Scans the QR code on a licence and asks the backend whether it is
/// registered (`Real`) or not (`Fake`), plus its expiry status.
class VerifyLicenseScreen extends StatefulWidget {
  const VerifyLicenseScreen({super.key});

  @override
  State<VerifyLicenseScreen> createState() => _VerifyLicenseScreenState();
}

class _VerifyLicenseScreenState extends State<VerifyLicenseScreen> {
  final BarcodeScanner _scanner = BarcodeScanner();

  CameraController? _camera;
  bool _initializing = true;
  bool _processing = false;
  bool _isProcessingFrame = false;
  String? _cameraError;

  VerificationResult? _result;
  String? _checkedLicenseId;
  String? _verifyError;

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
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
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

      await _startStream();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraError = 'Could not open camera: $e';
      });
    }
  }

  Future<void> _startStream() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isStreamingImages ||
        _processing ||
        _result != null) {
      return;
    }

    await camera.startImageStream((image) async {
      if (_isProcessingFrame || _processing || _result != null) return;
      _isProcessingFrame = true;

      try {
        final input = CameraImageConverter.fromCameraImage(image, camera);
        if (input == null) return;

        final barcodes = await _scanner.processImage(input);
        final raw = barcodes
            .map((b) => b.rawValue ?? b.displayValue ?? '')
            .where((v) => v.isNotEmpty)
            .join('\n')
            .trim();

        if (raw.isEmpty) return;

        final licenseId = LicenseParser.licenseIdFromRaw(raw);
        if (licenseId == null || licenseId.isEmpty) return;

        HapticFeedback.mediumImpact();
        await _stopStream();

        if (!mounted) return;
        await _verify(licenseId);
      } catch (e) {
        debugPrint('Verify frame error: $e');
      } finally {
        await Future.delayed(const Duration(milliseconds: 200));
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _stopStream() async {
    final camera = _camera;
    if (camera != null && camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } catch (_) {}
    }
    _isProcessingFrame = false;
  }

  Future<void> _verify(String licenseId) async {
    setState(() {
      _processing = true;
      _verifyError = null;
      _checkedLicenseId = licenseId;
    });

    try {
      final result = await ApiService.verifyLicense(licenseId);
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.isUnauthorized) {
        await _handleSessionExpired();
        return;
      }
      setState(() => _verifyError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifyError = 'Verification failed: $e');
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _promptManualEntry() async {
    final controller = TextEditingController();
    await _stopStream();

    final licenseId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter licence ID'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Licence ID number',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Check'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (!mounted) return;

    if (licenseId == null || licenseId.isEmpty) {
      await _startStream();
      return;
    }

    await _verify(licenseId);
  }

  Future<void> _handleSessionExpired() async {
    await _stopStream();
    await AuthService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _reset() async {
    setState(() {
      _result = null;
      _verifyError = null;
      _checkedLicenseId = null;
    });

    if (_camera == null || !_camera!.value.isInitialized) {
      await _initializeCamera();
    } else {
      await _startStream();
    }
  }

  @override
  void dispose() {
    _stopStream();
    _camera?.dispose();
    _scanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify licence')),
      body: SafeArea(
        child: _result != null
            ? _buildResult(_result!)
            : _buildScanner(),
      ),
    );
  }

  Widget _buildScanner() {
    final camera = _camera;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Scan the QR code on the back of the licence to check whether '
            'it is registered.',
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
                : _cameraError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _cameraError!,
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
                                  widthFactor: 0.7,
                                  heightFactor: 0.7,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.greenAccent,
                                        width: 3,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              if (_processing)
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
                                          'Checking licence...',
                                          style:
                                              TextStyle(color: Colors.white),
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
        if (_verifyError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              _verifyError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _processing ? null : _promptManualEntry,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Enter licence ID manually'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(VerificationResult result) {
    final real = result.isReal;

    final Color accent = real
        ? (result.isActive ? const Color(0xFF1B7F4B) : const Color(0xFFB26A00))
        : const Color(0xFFB3261E);

    final String headline = real
        ? 'Real licence'
        : 'Fake / not registered';

    final String description = real
        ? (result.isActive
            ? 'This licence is registered and currently valid.'
            : result.expiryStatus.toLowerCase() == 'expired'
                ? 'This licence is registered but has expired.'
                : 'This licence is registered, but its expiry needs review.')
        : 'No licence with this number is registered in the system.';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Icon(
                real ? Icons.verified_outlined : Icons.gpp_bad_outlined,
                size: 56,
                color: accent,
              ),
              const SizedBox(height: 12),
              Text(
                headline,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              StatusChip(result.expiryStatus),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _DetailRow(label: 'Licence ID', value: result.licenseId),
        _DetailRow(
          label: 'Full name',
          value: (result.fullName == null || result.fullName!.isEmpty)
              ? '—'
              : result.fullName!,
        ),
        _DetailRow(label: 'Status', value: result.status),
        _DetailRow(label: 'Expiry status', value: result.expiryStatus),
        _DetailRow(
          label: 'Checked at',
          value: result.checkedDate == null
              ? '—'
              : _formatDateTime(result.checkedDate!),
        ),
        if (result.checkedBy != null)
          _DetailRow(label: 'Checked by', value: result.checkedBy!),
        if (_checkedLicenseId != null && _checkedLicenseId != result.licenseId)
          _DetailRow(label: 'Scanned ID', value: _checkedLicenseId!),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan another licence'),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
