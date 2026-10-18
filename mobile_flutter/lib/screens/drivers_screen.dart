import 'package:flutter/material.dart';

import '../models/driver.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/status_chip.dart';
import 'login_screen.dart';

/// Lists every registered driver (`GET /api/drivers`).
class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});

  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  late Future<List<Driver>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getDrivers();
  }

  Future<void> _refresh() async {
    setState(() => _future = ApiService.getDrivers());
    await _future.catchError((_) => <Driver>[]);
  }

  Future<void> _handleAuthFailure() async {
    await AuthService.logout();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _delete(Driver driver) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove driver'),
        content: Text(
          'Delete the registration for ${driver.fullName} '
          '(${driver.licenseId})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.deleteDriver(driver.driverId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver removed.')),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _handleAuthFailure();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  void _showDetails(Driver driver) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(driver.fullName,
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            StatusChip(driver.status),
            const SizedBox(height: 16),
            _row(ctx, 'Licence ID', driver.licenseId),
            _row(ctx, 'Licence type', driver.licenseType ?? '—'),
            _row(ctx, 'Date of birth', driver.dateOfBirth ?? '—'),
            _row(ctx, 'Expiry date', driver.expiryDate ?? '—'),
            _row(
              ctx,
              'Registered on',
              driver.createdDate == null
                  ? '—'
                  : driver.createdDate!.toLocal().toString().split(' ').first,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _delete(driver);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove driver'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registered drivers')),
      body: FutureBuilder<List<Driver>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final unauthorized =
                error is ApiException && error.isUnauthorized;

            if (unauthorized) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleAuthFailure();
              });
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off,
                        size: 48,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      error is ApiException
                          ? error.message
                          : 'Could not load drivers: $error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final drivers = snapshot.data ?? const <Driver>[];

          if (drivers.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.folder_open, size: 48),
                  SizedBox(height: 12),
                  Center(child: Text('No drivers registered yet.')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: drivers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final driver = drivers[index];

                final driverName = driver.fullName.trim();

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      driverName.isEmpty
                          ? '?'
                          : driverName.substring(0, 1).toUpperCase(),
                    ),
                  ),
                  title: Text(driver.fullName),
                  subtitle: Text(
                    '${driver.licenseId}'
                    '${driver.licenseType == null ? '' : ' · ${driver.licenseType}'}'
                    '${driver.expiryDate == null ? '' : ' · expires ${driver.expiryDate}'}',
                  ),
                  trailing: StatusChip(driver.status),
                  onTap: () => _showDetails(driver),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
